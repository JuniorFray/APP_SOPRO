import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';

/// Direção da borda direcional do vidro.
/// [all] cartões · [bottom] AppBars/topo · [top] painéis inferiores · [none] sem borda.
enum GlassEdges { all, bottom, top, none }

/// Liquid Glass premium centralizado (iOS 26 / Apple Control Center).
///
/// Fonte única da identidade de vidro do app — todo componente glass delega aqui
/// para garantir consistência e evitar duplicação da receita.
///
/// Hierarquia (exigida): ClipRRect → BackdropFilter → Container(corpo+borda)
///                        → child.
///
/// Performance: UM único BackdropFilter. Todas as demais camadas são pintura de
/// decoração (custo desprezível). Sem filtro aninhado, sem RepaintBoundary novo,
/// sem Opacity, sem ShaderMask.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius,
    this.margin,
    this.blurSigma = 32,
    this.edges = GlassEdges.all,
    this.shadows,
    this.specular = true,
  });

  /// Conteúdo sobreposto ao vidro (não é desfocado — só o fundo atrás é).
  final Widget child;

  /// Raio das bordas. null → AppRadius.card (cartões).
  final BorderRadius? borderRadius;

  /// Margem externa (fora do clip, para as sombras respirarem).
  final EdgeInsetsGeometry? margin;

  /// Sigma do único BackdropFilter.
  final double blurSigma;

  /// Configuração da borda direcional.
  final GlassEdges edges;

  /// Sombras externas de profundidade. null → sem sombra (AppBars/painéis full-bleed).
  final List<BoxShadow>? shadows;

  /// Mantido por compatibilidade — o specular foi removido do design.
  final bool specular;

    /// Sombras de cartão — visual flat: sem sombra.
  static const List<BoxShadow> cardShadows = [];

  // Borda direcional conforme [edges]: topo brilha (luz de cima), base escurece.
  Border? _border() {
    switch (edges) {
      case GlassEdges.none:
        return null;
      case GlassEdges.all:
        // Borda uniforme de vidro — fina e clara em todos os lados
        // (aresta do vidro que captura luz, padrão glassmorphism/iOS).
        return Border.all(color: const Color(0x1FFFFFFF), width: 1.0); // white 12%
      case GlassEdges.bottom:
        return const Border(
          top: BorderSide(color: Color(0x1FFFFFFF), width: 0.5), // white 12% — rim superior
          bottom: BorderSide(color: Color(0x33FFFFFF), width: 0.5), // white 20% — separador
        );
      case GlassEdges.top:
        return const Border(
          top: BorderSide(color: Color(0x33FFFFFF), width: 0.5), // white 20% — separador
          bottom: BorderSide(color: Color(0x1FFFFFFF), width: 0.5), // white 12%
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ??
        BorderRadius.circular(AppRadius.card);

    return Container(
      margin: margin,
      // Sombras fora do clip para não serem cortadas.
      decoration: shadows == null
          ? null
          : BoxDecoration(
              borderRadius: radius, boxShadow: shadows),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [

                        // ── Camada 1: blur do fundo (BackdropFilter
            //    isolado — sem content dentro dele).
            //    Evita o save layer do Android engolir
            //    os filhos e torná-los invisíveis.
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                    sigmaX: blurSigma, sigmaY: blurSigma),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    // Preenchimento uniforme (flat) — sem gradiente, sem
                    // canto mais claro que o outro.
                    color: const Color(0x0DFFFFFF), // white 5%
                    border: _border(),
                  ),
                ),
              ),
            ),

            // ── Camada 2: conteúdo real (fora do
            //    BackdropFilter — sem conflito de layer).
            child,

            // ── Camada 3 (removida): o specular criava brilho artificial no
            //    topo. No glassmorphism atual, o brilho vem do fundo desfocado
            //    (GlowBackground) + borda de vidro — não de tinta pintada.
          ],
        ),
      ),
    );
  }
}