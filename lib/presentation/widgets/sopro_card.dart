import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_shadows.dart';

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
      // Outer container: apenas margin + sombra difusa (fora do ClipRRect para não cortar)
      return Container(
        margin: margin,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 24,
              spreadRadius: 0,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0x14FFFFFF), // white 8%
                    Color(0x03FFFFFF), // white 1%
                  ],
                ),
                border: bordered
                    ? Border.all(color: AppColors.borderHighlight, width: 0.5)
                    : null,
              ),
              foregroundDecoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0x1EFFFFFF), // white 12% — reflexo superior
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.45],
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: content,
              ),
            ),
          ),
        ),
      );
    }

    // Modo sólido (padrão)
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.backgroundCardHighlight,
            AppColors.backgroundCard,
          ],
          stops: [0.0, 0.7],
        ),
        border: bordered
            ? Border.all(color: AppColors.border, width: 0.5)
            : null,
        boxShadow: const [AppShadows.card],
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
