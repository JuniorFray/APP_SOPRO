// OnboardingScreen — Primeiro acesso ao Sopro.
//
// 4 passos que explicam o VALOR antes de pedir cada permissão:
//   0. Boas-vindas      — conceito do app (sem permissão)
//   1. Localização      — geofences locais, sem envio de GPS para servidores
//   2. Notificações     — sussurros discretos, sem marketing
//   3. Bluetooth        — troca de ContextCard diretamente entre dispositivos
//
// Após o passo 3, o usuário vai para ProfileScreen criar seu ContextCard.
// Exibida pelo HomeScreen quando nenhum ContextCard existe no banco.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

// Conteúdo dos 4 passos — definido como constante para evitar recriação
const _steps = [
  _Step(
    icon: Icons.air,
    iconColor: AppTheme.accent,
    title: AppStrings.obWelcomeTitle,
    body: AppStrings.obWelcomeBody,
  ),
  _Step(
    icon: Icons.location_on_outlined,
    iconColor: Color(0xFF4CAF50), // verde — transmite segurança de localização
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
  bool _actionInProgress = false; // true enquanto aguarda resposta do sistema de permissão

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Avança para o próximo passo com animação
  void _nextPage() {
    if (_currentStep < _steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _goToProfile();
    }
  }

  // Substitui o onboarding pela tela de perfil (flag arguments=true indica primeiro acesso)
  void _goToProfile() {
    Navigator.pushReplacementNamed(context, '/profile', arguments: true);
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

  // Solicita permissões BLE → vai para o perfil independentemente do resultado
  Future<void> _requestBle() async {
    setState(() => _actionInProgress = true);
    try {
      await ref.read(bleServiceProvider).requestPermissions();
    } finally {
      if (mounted) {
        setState(() => _actionInProgress = false);
        _goToProfile();
      }
    }
  }

  // Texto do botão primário muda conforme o passo atual
  String get _primaryLabel {
    switch (_currentStep) {
      case 1:  return AppStrings.obLocationBtn;
      case 2:  return AppStrings.obNotifBtn;
      case 3:  return AppStrings.obBleBtn;
      default: return AppStrings.obNext;
    }
  }

  // Callback do botão primário — null durante loading bloqueia o botão
  VoidCallback? get _primaryAction {
    if (_actionInProgress) return null;
    switch (_currentStep) {
      case 0:  return _nextPage;
      case 1:  return _requestLocation;
      case 2:  return _requestNotifications;
      case 3:  return _requestBle;
      default: return _nextPage;
    }
  }

  // Texto do botão secundário (pular ou configurar perfil no último passo)
  String get _secondaryLabel =>
      _currentStep == _steps.length - 1 ? AppStrings.obFinish : AppStrings.obSkip;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Botão "Pular tudo" no canto superior direito (passos 1-3)
            SizedBox(
              height: 48,
              child: _currentStep > 0
                  ? Align(
                      alignment: Alignment.topRight,
                      child: TextButton(
                        onPressed: _actionInProgress ? null : _goToProfile,
                        child: const Text(
                          AppStrings.obSkip,
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ),
                    )
                  : null,
            ),

            // PageView com conteúdo de cada passo
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                // Navegação apenas pelos botões — evita gestos acidentais
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
                  // Indicadores de passo (bolinha expandida = passo atual)
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

                  // Botão primário (ação do passo)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _primaryAction,
                      child: _actionInProgress
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

                  // Botão secundário nos passos de permissão (pular ou terminar)
                  if (_currentStep > 0) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: _actionInProgress ? null : _nextPage,
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

          // Corpo explicando o valor — lido antes de ver o diálogo de permissão do SO
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
