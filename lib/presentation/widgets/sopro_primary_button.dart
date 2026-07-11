import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_typography.dart';

/// Botão primário do Sopro — V2 Premium.
/// Gradiente accent→secondary, micro-scale no press, full-width, h:52.
/// `loading` controla visual (spinner). `onPressed: null` desabilita.
class SoproPrimaryButton extends StatefulWidget {
  const SoproPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool loading;

  @override
  State<SoproPrimaryButton> createState() => _SoproPrimaryButtonState();
}

class _SoproPrimaryButtonState extends State<SoproPrimaryButton> {
  bool _pressed = false;

  bool get _isDisabled => widget.onPressed == null;

  void _onTapDown(TapDownDetails _) {
    if (!_isDisabled && !widget.loading) setState(() => _pressed = true);
  }

  void _onTapUp(TapUpDetails _) {
    if (!_pressed) return;
    setState(() => _pressed = false);
    if (!_isDisabled && !widget.loading) widget.onPressed!();
  }

  void _onTapCancel() => setState(() => _pressed = false);

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: AppMotion.micro,
      curve: AppMotion.snap,
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: _buildSurface(),
      ),
    );
  }

  Widget _buildSurface() {
    final borderRadius = BorderRadius.circular(AppRadius.button);

    return AnimatedContainer(
      duration: AppMotion.quick,
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: _isDisabled
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.secondary, AppColors.accent],
                stops: [0.0, 1.0],
              ),
        color: _isDisabled
            ? AppColors.backgroundInput
            : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Material(
          color: Colors.transparent,
          child: Center(child: _buildContent()),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (widget.loading) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.textPrimary,
          strokeCap: StrokeCap.round,
        ),
      );
    }

    final labelText = Text(
      widget.label,
      style: AppTypography.titleSmall.copyWith(
        color: _isDisabled ? AppColors.textDisabled : AppColors.textPrimary,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );

    if (widget.icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          widget.icon!,
          const SizedBox(width: 8),
          labelText,
        ],
      );
    }

    return labelText;
  }
}
