import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_shadows.dart';

/// Card padrão do Sopro — V2 Premium.
/// Gradiente suave top→bottom, borda discreta, sombra difusa.
/// Usa Material internamente para clipar o InkWell dos filhos interativos.
class SoproCard extends StatelessWidget {
  const SoproCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.bordered = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(AppRadius.card);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        // Gradiente sutil: leve brilho no topo, profundidade no bottom.
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
          child: padding != null
              ? Padding(padding: padding!, child: child)
              : child,
        ),
      ),
    );
  }
}
