// EnvironmentLoaderScreen — tela intermediária de deep-link por notificação.
//
// Ao tocar numa notificação de trigger, o app navega para /environment
// passando o ID do ambiente como argumento. Esta tela carrega o
// EnvironmentEntity pelo ID (via Riverpod) e exibe a tela de detalhe
// quando o dado estiver disponível.
//
// Exibe um spinner de carregamento enquanto o banco não responde.
// Se o ID não existir no banco (ambiente foi deletado), volta para a home.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../providers/environment_providers.dart';
import 'environment_detail_screen.dart';

class EnvironmentLoaderScreen extends ConsumerWidget {
  // ID do ambiente recebido como argumento da rota '/environment'
  final String environmentId;

  const EnvironmentLoaderScreen({super.key, required this.environmentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envAsync = ref.watch(environmentByIdProvider(environmentId));

    return envAsync.when(
      // Enquanto carrega: spinner centralizado com tema Sopro
      loading: () => const Scaffold(
        backgroundColor: AppTheme.backgroundPrimary,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.accent),
        ),
      ),

      // Erro inesperado: volta para a raiz (não empilha uma tela de erro)
      error: (_, __) {
        // Usa addPostFrameCallback para não chamar pop() durante build()
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.of(context).pop();
        });
        return const Scaffold(
          backgroundColor: AppTheme.backgroundPrimary,
          body: Center(
            child: CircularProgressIndicator(color: AppTheme.accent),
          ),
        );
      },

      // Dado carregado: exibe o detalhe ou volta para a home se não existir
      data: (env) {
        if (env == null) {
          // Ambiente foi deletado — volta para a tela anterior
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).pop();
          });
          return const Scaffold(
            backgroundColor: AppTheme.backgroundPrimary,
            body: Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            ),
          );
        }
        // Ambiente encontrado: exibe diretamente sem transição extra
        return EnvironmentDetailScreen(environment: env);
      },
    );
  }
}
