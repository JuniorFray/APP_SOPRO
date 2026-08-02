import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../providers/voice_providers.dart';
import 'glass_surface.dart';

// Popup visual da fala da persona — modo "Responder com texto" (acessibilidade).
//
// Mostra o TEXTO de QUALQUER fala (sucesso, pergunta, confirmacao destrutiva,
// pergunta de encadeamento) num toast glass que aparece e some sozinho, sem
// depender do TTS. Injetado nos 2 funis de fala do Flutter — _speak (Home) e a
// closure speak (action_handlers_builder) — ANTES do guard de audio; por isso
// funciona mesmo com a voz desligada (audio OFF + texto ON = modo so-leitura).
//
// Gate unico: voiceTextResponseProvider (antes inerte, agora o gate real).
class VoiceTextPopup {
  VoiceTextPopup._();

  // Entrada ativa — so uma por vez. Uma fala nova substitui a anterior (nao
  // empilha), mantendo a tela limpa quando a persona fala varias frases seguidas.
  static OverlayEntry? _entry;

  // Exibe [text] se o toggle de texto estiver ligado. No-op se vazio, sem
  // Overlay disponivel ou com o contexto ja desmontado (Skills async).
  static void show(BuildContext context, WidgetRef ref, String text) {
    if (!context.mounted) return;
    if (!ref.read(voiceTextResponseProvider)) return;
    final msg = text.trim();
    if (msg.isEmpty) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _remove(); // troca imediata: descarta o popup anterior
    // Duracao proporcional ao tamanho do texto (leitura confortavel): 5s base
    // + ~55ms por caractere, com teto de 12s pra dar tempo real de leitura.
    final holdMs = (5000 + msg.length * 55).clamp(5000, 12000);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _VoiceTextToast(
        text: msg,
        holdMs: holdMs,
        onDone: () {
          if (identical(_entry, entry)) _entry = null;
          try {
            entry.remove();
          } catch (_) {}
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  // Remove a entrada atual imediatamente (usado na troca por uma fala nova).
  static void _remove() {
    final e = _entry;
    _entry = null;
    if (e != null) {
      try {
        e.remove();
      } catch (_) {}
    }
  }
}

// Toast glass autossuficiente: fade+slide de entrada, espera [holdMs], faz o
// fade de saida e chama [onDone] pro manager remover a OverlayEntry.
class _VoiceTextToast extends StatefulWidget {
  const _VoiceTextToast({
    required this.text,
    required this.holdMs,
    required this.onDone,
  });

  final String text;
  final int holdMs;
  final VoidCallback onDone;

  @override
  State<_VoiceTextToast> createState() => _VoiceTextToastState();
}

class _VoiceTextToastState extends State<_VoiceTextToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    _ctrl.forward(); // entra (fade + slide)
    _holdTimer = Timer(Duration(milliseconds: widget.holdMs), () async {
      if (!mounted) return;
      await _ctrl.reverse(); // sai
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // TOPO da tela (abaixo da area segura do sistema) — nao cobre o botao de
    // segurar-pra-falar nem a lista de baixo.
    final top = MediaQuery.of(context).padding.top + 16;
    final fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    return Positioned(
      left: 20,
      right: 20,
      top: top,
      child: IgnorePointer( // so informativo — nao intercepta toques da tela
        child: FadeTransition(
          opacity: fade,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.15), // entra deslizando de cima
              end: Offset.zero,
            ).animate(fade),
            child: GlassSurface(
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Text(
                  widget.text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
