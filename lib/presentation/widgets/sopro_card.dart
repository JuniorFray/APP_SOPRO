import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import 'glass_surface.dart';

/// Card padrão do Sopro — Dark Glass V3.
/// [glass: true]  BackdropFilter + fundo translúcido (EnvironmentCard, FAB, etc.)
/// [glass: false] gradiente sólido — padrão para telas secundárias (detalhes, etc.)
class SoproCard extends StatelessWidget {
  const SoproCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.bordered = true,
    this.glass = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool bordered;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(AppRadius.card);
    final content = padding != null
        ? Padding(padding: padding!, child: child)
        : child;

    if (glass) {
      // Liquid Glass espesso — delega ao primitivo central GlassSurface para
      // manter a identidade única do app (mesma receita da Home). Saída idêntica.
      return GlassSurface(
        margin: margin,
        borderRadius: borderRadius,
        edges: bordered ? GlassEdges.all : GlassEdges.none,
        shadows: GlassSurface.cardShadows,
        child: Material(
          color: Colors.transparent,
          child: content,
        ),
      );
    }

    // Modo sólido (padrão) — flat: cor única no meio-termo, sem gradiente/sombra.
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: AppColors.backgroundCardSolid,
        border: bordered
            ? Border.all(color: AppColors.border, width: 0.5)
            : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Material(
          color: Colors.transparent,
          child: content,
        ),
      ),
    );
  }
}
