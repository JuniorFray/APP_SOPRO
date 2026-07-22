// HomeScreen — alias de compatibilidade.
//
// A raiz do app passou a ser o MainShellScreen (bottom nav de 4 abas). Este
// arquivo é mantido apenas porque a rota '/home' e o fallback de deep-link
// '/environment' em main.dart ainda referenciam HomeScreen. Renderiza o shell.

import 'package:flutter/material.dart';

import '../shell/main_shell_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const MainShellScreen();
}
