// onboarding_screen.dart - Tela de Onboarding do Sopro
//
// Apresenta o conceito do app e solicita permissoes.
// SPRINT 0: versao placeholder.
// Implementacao completa: Sprint 8.

import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Tela de primeiro acesso ao Sopro.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icone representando o "sopro"
              const Icon(Icons.air, size: 80, color: AppTheme.accent),
              const SizedBox(height: 32),

              // Titulo de boas-vindas
              Text(
                'Bem-vindo ao Sopro',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 16),

              // Descricao do conceito do app
              Text(
                'Imagine ter alguem que sussurra exatamente '
                'o que voce precisa saber, no momento em que '
                'voce chega num lugar.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 48),

              // Botao para comecar - vai para HomeScreen
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.pushReplacementNamed(context, '/home'),
                  child: const Text('Comecar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}