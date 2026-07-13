// OnboardingScreen — Primeiro acesso ao Sopro.
//
// 4 passos que explicam o VALOR antes de pedir cada permissão:
//   0. Boas-vindas      — conceito do app (sem permissão)
//   1. Localização      — geofences locais, sem envio de GPS para servidores
//   2. Notificações     — sussurros discretos, sem marketing
//   3. Bluetooth        — troca de ContextCard diretamente entre dispositivos
//
// NAVEGAÇÃO:
//   Todas as saídas do onboarding (botão primário no último passo, "Pular",
//   "Ir para o app") chamam _goHome(), que:
//     1. Persiste 'onboarding_done = true' no SharedPreferences
//     2. Chama pushReplacementNamed('/home')
//
//   Isso garante que, nas próximas aberturas, o HomeScreen vá direto para a
//   tela principal sem reapresentar o onboarding.
//
//   O perfil (ContextCard) é criado voluntariamente a partir do ícone na AppBar
//   do HomeScreen — não é obrigatório para acessar o app.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/ble_providers.dart';
import '../../providers/location_providers.dart';
import '../../providers/settings_providers.dart';
import '../../widgets/sopro_primary_button.dart';
import '../../../infrastructure/overlay/floating_voice_service_manager.dart';

// Dados imutáveis de cada passo do onboarding
class _Step {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;

  const _Step({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });
}

// Conteúdo dos 5 passos — constante para evitar recriação a cada rebuild.
// Passo 4 é opcional/informativo (sem permissão obrigatória), antecipa V3.
const _steps = [
  _Step(
    icon: Icons.air,
    iconColor: AppTheme.accent,
    title: AppStrings.obWelcomeTitle,
    body: AppStrings.obWelcomeBody,
  ),
  _Step(
    icon: Icons.location_on_outlined,
    iconColor: AppColors.onboardingLocation, // verde — segurança de localização
    title: AppStrings.obLocationTitle,
    body: AppStrings.obLocationBody,
  ),
  _Step(
    icon: Icons.notifications_none_outlined,
    iconColor: AppColors.onboardingNotification, // laranja — notificações discretas
    title: AppStrings.obNotifTitle,
    body: AppStrings.obNotifBody,
  ),
  _Step(
    icon: Icons.bluetooth_outlined,
    iconColor: AppColors.onboardingBle, // azul — Bluetooth
    title: AppStrings.obBleTitle,
    body: AppStrings.obBleBody,
  ),
  _Step(
    icon: Icons.mic_external_on_outlined,
    iconColor: AppTheme.accent, // accent — botão de voz
    title: AppStrings.obOverlayTitle,
    body: AppStrings.obOverlayBody,
  ),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

// Canal nativo para verificar/ativar o botão flutuante no passo 4 do onboarding
const _overlayChannel = MethodChannel('com.sopro.sopro/overlay');

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with WidgetsBindingObserver {
  final _pageController = PageController();
  int _currentStep = 0;
  bool _actionInProgress = false; // true enquanto aguarda resposta do SO de permissão
  bool _finishing = false;        // true enquanto salva SharedPreferences antes de navegar

  // Mensagem exibida inline quando o usuário nega uma permissão.
  // null = nenhuma negação recente; limpa ao trocar de passo.
  String? _denialMessage;

  // true quando o app foi para o background aguardando retorno da tela de
  // configurações de permissão de overlay — detectado em didChangeAppLifecycleState
  bool _waitingForOverlayPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  // Detecta retorno do app após o usuário visitar as configurações de overlay.
  // Se a permissão foi concedida → ativa o serviço automaticamente.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForOverlayPermission) {
      _waitingForOverlayPermission = false;
      _checkAndActivateOverlay();
    }
  }

  // Avança para o próximo passo (ou conclui o onboarding no último)
  void _nextPage() {
    if (_currentStep < _steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _goHome();
    }
  }

  // Ponto único de saída do onboarding — chamado por TODAS as rotas de conclusão/pular.
  //
  // Persiste o flag antes de navegar para garantir que não volte ao onboarding
  // mesmo se o usuário fechar o app no meio da transição.
  Future<void> _goHome() async {
    if (_finishing) return; // evita chamadas duplicadas (double-tap)
    setState(() => _finishing = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_done', true);
      await prefs.setString(
        'sopro_first_use_date',
        DateTime.now().toIso8601String(),
      );
    } finally {
      if (mounted) {
        // pushReplacement impede que o botão "voltar" retorne ao onboarding
        Navigator.pushReplacementNamed(context, '/home');
      }
    }
  }

  // ── Permissão de overlay (passo 4) ──────────────────────────────────────
  //
  // Não bloqueamos o avanço — o usuário pode pular e ativar depois nas Config.
  // Se já possui permissão → ativa imediatamente.
  // Se não possui → abre a tela do sistema e aguarda retorno via LifecycleObserver.

  Future<void> _requestOverlayPermission() async {
    setState(() => _actionInProgress = true);
    try {
      final hasPerm =
          await _overlayChannel.invokeMethod<bool>('hasOverlayPermission') ?? false;
      if (hasPerm) {
        // Permissão já concedida — ativa o serviço agora mesmo
        await _checkAndActivateOverlay();
      } else {
        // Abre a tela de configurações do sistema e aguarda retorno do app
        _waitingForOverlayPermission = true;
        await _overlayChannel.invokeMethod<void>('openOverlayPermissionSettings');
      }
    } catch (_) {
      // Falha no MethodChannel (ex: emulador sem suporte) — apenas avança
      _goHome();
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  // Ativa o FloatingVoiceService via política central e avança para o Home.
  Future<void> _checkAndActivateOverlay() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('floating_voice_enabled', true);
      final String? failure = await FloatingVoiceServiceManager.tryStart();
      if (failure == null) {
        if (mounted) {
          ref.read(floatingVoiceEnabledProvider.notifier).state = true;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(AppStrings.obOverlayActivated),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        // Pré-requisito ausente — reverte pref; o usuário ativa depois nas Configurações
        await prefs.setBool('floating_voice_enabled', false);
      }
    } catch (_) {
      // Silencioso — o usuário pode ativar depois nas Configurações
    }
    _goHome();
  }

  // Solicita permissão de localização → avança independentemente do resultado
  Future<void> _requestLocation() async {
    setState(() => _actionInProgress = true);
    try {
      await ref.read(nativeLocationServiceProvider).requestPermission();
    } finally {
      if (mounted) {
        setState(() => _actionInProgress = false);
        _nextPage();
      }
    }
  }

  // Solicita permissão de notificações (Android 13+ / API 33+).
  // Avança ao próximo passo se concedida; exibe mensagem de impacto se negada.
  // Em Android < 13, requestPermission() retorna true sem exibir diálogo.
  Future<void> _requestNotifications() async {
    setState(() => _actionInProgress = true);
    bool granted = false;
    try {
      granted = await ref.read(notificationServiceProvider).requestPermission();
    } catch (_) {
      // Falha na requisição — trata como negado para não bloquear o fluxo
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
    if (!mounted) return;
    if (granted) {
      _nextPage();
    } else {
      // Mostra aviso e aguarda o usuário pressionar "Continuar assim mesmo"
      setState(() => _denialMessage = AppStrings.obNotifDenied);
    }
  }

  // Solicita BLUETOOTH_SCAN e BLUETOOTH_ADVERTISE (Android 12+ / API 31+).
  // Avança para o passo de overlay (informativo) se concedido; exibe mensagem de impacto se negado.
  Future<void> _requestBle() async {
    setState(() => _actionInProgress = true);
    bool granted = false;
    try {
      granted = await ref.read(bleServiceProvider).requestPermissions();
    } catch (_) {
      // Falha na requisição — trata como negado
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
    if (!mounted) return;
    if (granted) {
      // Avança para o passo 4 (overlay informativo) em vez de ir direto ao home
      _nextPage();
    } else {
      // Mostra aviso e aguarda o usuário pressionar "Continuar assim mesmo"
      setState(() => _denialMessage = AppStrings.obBleDenied);
    }
  }

  // Texto do botão primário.
  // Quando uma permissão foi negada, muda para "Continuar assim mesmo".
  String get _primaryLabel {
    if (_denialMessage != null) return AppStrings.obContinueAnyway;
    switch (_currentStep) {
      case 1:  return AppStrings.obLocationBtn;
      case 2:  return AppStrings.obNotifBtn;
      case 3:  return AppStrings.obBleBtn;
      // Passo 4: solicita permissão de overlay para ativar o botão flutuante
      case 4:  return AppStrings.obOverlayBtn;
      default: return AppStrings.obNext;
    }
  }

  // Callback do botão primário — null durante loading bloqueia interação.
  // Quando há mensagem de negação ativa, o botão apenas avança (sem re-pedir).
  VoidCallback? get _primaryAction {
    if (_actionInProgress || _finishing) return null;
    if (_denialMessage != null) {
      // Avança após o usuário reconhecer o impacto da permissão negada
      return _currentStep == _steps.length - 1 ? _goHome : _nextPage;
    }
    switch (_currentStep) {
      case 0:  return _nextPage;
      case 1:  return _requestLocation;
      case 2:  return _requestNotifications;
      case 3:  return _requestBle;
      // Passo 4: solicita permissão SYSTEM_ALERT_WINDOW e ativa o botão flutuante
      case 4:  return _requestOverlayPermission;
      default: return _nextPage;
    }
  }

  // Botão secundário: "Pular" nos passos 1-3; "Agora não" no passo 4 (overlay).
  // Oculto quando há mensagem de negação ativa (o primário já oferece avanço).
  String get _secondaryLabel =>
      _currentStep == _steps.length - 1 ? AppStrings.obOverlaySkip : AppStrings.obSkip;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Botão "Pular tudo" no canto superior direito (visível nos passos 1-3)
            SizedBox(
              height: 48,
              child: _currentStep > 0
                  ? Align(
                      alignment: Alignment.topRight,
                      child: TextButton(
                        onPressed: (_actionInProgress || _finishing) ? null : _goHome,
                        child: const Text(
                          AppStrings.obSkip,
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ),
                    )
                  : null,
            ),

            // PageView com o conteúdo de cada passo
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                // Só os botões navegam — evita gestos acidentais
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() {
                  _currentStep = i;
                  _denialMessage = null; // limpa aviso ao mudar de passo
                }),
                itemCount: _steps.length,
                itemBuilder: (_, i) => _StepPage(step: _steps[i]),
              ),
            ),

            // Rodapé: aviso de negação (se houver) + indicadores + botões de ação
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Aviso inline exibido quando o usuário nega uma permissão.
                  // AnimatedSize suaviza o aparecimento/desaparecimento do container.
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    child: _denialMessage != null
                        ? Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: AppSpacing.md),
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              // ignore: deprecated_member_use
                              color: AppTheme.accent.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                              border: Border.all(
                                // ignore: deprecated_member_use
                                color: AppTheme.accent.withOpacity(0.30),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.info_outline,
                                  color: AppTheme.accent,
                                  size: 16,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(
                                  child: Text(
                                    _denialMessage!,
                                    style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 13,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),

                  // Indicadores de passo animados (bolinha larga = passo atual)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _steps.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                        width: _currentStep == i ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentStep == i
                              ? AppTheme.accent
                              : AppTheme.textDisabled,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Botão primário (ação específica do passo)
                  SoproPrimaryButton(
                    label: _primaryLabel,
                    onPressed: _primaryAction,
                    loading: _actionInProgress || _finishing,
                  ),

                  // Botão secundário: "Pular" / "Ir para o app".
                  // Oculto quando há mensagem de negação ativa — o botão primário
                  // já oferece "Continuar assim mesmo" como alternativa.
                  if (_currentStep > 0 && _denialMessage == null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    TextButton(
                      // Nos passos 1-2: avança sem pedir permissão
                      // No passo 3: conclui o onboarding e vai para /home
                      onPressed: (_actionInProgress || _finishing) ? null : _nextPage,
                      child: Text(
                        _secondaryLabel,
                        style: const TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Widget de conteúdo de um único passo: ícone + título + descrição
class _StepPage extends StatelessWidget {
  final _Step step;
  const _StepPage({required this.step});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ícone com fundo circular levemente colorido
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              // ignore: deprecated_member_use
              color: step.iconColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(step.icon, size: 44, color: step.iconColor),
          ),
          const SizedBox(height: AppSpacing.gap36),

          // Título do passo
          Text(
            step.title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Corpo — lido ANTES do diálogo de permissão do SO aparecer
          Text(
            step.body,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.6,
                ),
          ),
        ],
      ),
    );
  }
}
