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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/ble_providers.dart';
import '../../providers/location_providers.dart';

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

// Conteúdo dos 4 passos — constante para evitar recriação a cada rebuild
const _steps = [
  _Step(
    icon: Icons.air,
    iconColor: AppTheme.accent,
    title: AppStrings.obWelcomeTitle,
    body: AppStrings.obWelcomeBody,
  ),
  _Step(
    icon: Icons.location_on_outlined,
    iconColor: Color(0xFF4CAF50), // verde — segurança de localização
    title: AppStrings.obLocationTitle,
    body: AppStrings.obLocationBody,
  ),
  _Step(
    icon: Icons.notifications_none_outlined,
    iconColor: Color(0xFFFFA726), // laranja — notificações discretas
    title: AppStrings.obNotifTitle,
    body: AppStrings.obNotifBody,
  ),
  _Step(
    icon: Icons.bluetooth_outlined,
    iconColor: Color(0xFF42A5F5), // azul — Bluetooth
    title: AppStrings.obBleTitle,
    body: AppStrings.obBleBody,
  ),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentStep = 0;
  bool _actionInProgress = false; // true enquanto aguarda resposta do SO de permissão
  bool _finishing = false;        // true enquanto salva SharedPreferences antes de navegar

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
    } finally {
      if (mounted) {
        // pushReplacement impede que o botão "voltar" retorne ao onboarding
        Navigator.pushReplacementNamed(context, '/home');
      }
    }
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

  // Solicita permissão de notificações → avança independentemente do resultado
  Future<void> _requestNotifications() async {
    setState(() => _actionInProgress = true);
    try {
      await ref.read(notificationServiceProvider).requestPermission();
    } finally {
      if (mounted) {
        setState(() => _actionInProgress = false);
        _nextPage();
      }
    }
  }

  // Solicita permissões BLE → conclui o onboarding independentemente do resultado
  Future<void> _requestBle() async {
    setState(() => _actionInProgress = true);
    try {
      await ref.read(bleServiceProvider).requestPermissions();
    } finally {
      if (mounted) {
        setState(() => _actionInProgress = false);
        _goHome();
      }
    }
  }

  // Texto do botão primário muda conforme o passo
  String get _primaryLabel {
    switch (_currentStep) {
      case 1:  return AppStrings.obLocationBtn;
      case 2:  return AppStrings.obNotifBtn;
      case 3:  return AppStrings.obBleBtn;
      default: return AppStrings.obNext;
    }
  }

  // Callback do botão primário — null durante loading bloqueia interação
  VoidCallback? get _primaryAction {
    if (_actionInProgress || _finishing) return null;
    switch (_currentStep) {
      case 0:  return _nextPage;
      case 1:  return _requestLocation;
      case 2:  return _requestNotifications;
      case 3:  return _requestBle;
      default: return _nextPage;
    }
  }

  // Botão secundário: "Pular" nos passos 1-2, "Ir para o app" no passo 3
  String get _secondaryLabel =>
      _currentStep == _steps.length - 1 ? AppStrings.obFinish : AppStrings.obSkip;

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
                onPageChanged: (i) => setState(() => _currentStep = i),
                itemCount: _steps.length,
                itemBuilder: (_, i) => _StepPage(step: _steps[i]),
              ),
            ),

            // Rodapé: indicadores de progresso + botões de ação
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Indicadores de passo animados (bolinha larga = passo atual)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _steps.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentStep == i ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentStep == i
                              ? AppTheme.accent
                              : AppTheme.textDisabled,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Botão primário (ação específica do passo)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _primaryAction,
                      child: (_actionInProgress || _finishing)
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_primaryLabel),
                    ),
                  ),

                  // Botão secundário nos passos de permissão (pular / ir para o app)
                  if (_currentStep > 0) ...[
                    const SizedBox(height: 4),
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
      padding: const EdgeInsets.symmetric(horizontal: 32),
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
          const SizedBox(height: 36),

          // Título do passo
          Text(
            step.title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
          ),
          const SizedBox(height: 16),

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
