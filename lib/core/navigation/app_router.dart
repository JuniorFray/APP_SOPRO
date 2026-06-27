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
