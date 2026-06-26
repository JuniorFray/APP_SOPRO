// home_screen.dart - Tela Principal do Sopro
// Sprint 0: placeholder para o app compilar.
// Implementacao completa: Sprint 8.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';

/// Tela principal do Sopro.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sopro'),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.person_outline),
            tooltip: 'Perfil',
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.air, size: 80, color: AppTheme.accent),
            const SizedBox(height: 24),
            Text(
              'Sprint 0 - Setup Completo!',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppTheme.success,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '"O sussurro certo. No lugar certo."',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Novo Ambiente'),
      ),
    );
  }
}