import 'package:flutter/material.dart';

// Chave global do Navigator — permite navegar de fora da árvore de widgets.
//
// Usos:
//   1. NotificationService: ao tocar numa notificação de trigger, o app
//      abre diretamente a tela do ambiente correspondente.
//   2. BackgroundServiceManager: futuras ações de deep-link.
//
// Registro: passado ao MaterialApp.navigatorKey em main.dart.
// Acesso: qualquer arquivo que importe este módulo pode chamar
//   navigatorKey.currentState?.pushNamed('/environment', arguments: id)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Navega para [screen] com animação de slide + fade suave (280 ms).
// Substitui MaterialPageRoute em todas as navegações push do app para
// oferecer transições consistentes entre telas.
Future<T?> pushScreen<T>(BuildContext context, Widget screen) {
  return Navigator.push<T>(
    context,
    PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => screen,
      transitionsBuilder: (_, animation, __, child) {
        // Slide da direita + fade sutil — padrão fluido para navegação no app
        final slide = Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

        final fade = Tween<double>(begin: 0.4, end: 1.0)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeIn));

        return SlideTransition(
          position: slide,
          child: FadeTransition(opacity: fade, child: child),
        );
      },
    ),
  );
}
