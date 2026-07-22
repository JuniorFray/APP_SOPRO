import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// Campo de texto padrão do Sopro — V2 Premium.
/// Fill: backgroundInput. Radius: input(14). FloatingLabel: accent.
/// Toda a decoração nasce aqui — sem InputDecoration.copyWith() nas telas.
class SoproTextField extends StatelessWidget {
  const SoproTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.helperText,
    this.helperStyle,
    this.suffixText,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.maxLength,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.enabled,
    this.autofocus = false,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? helperText;
  final TextStyle? helperStyle;
  final String? suffixText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int? maxLines;
  final int? maxLength;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool? enabled;
  final bool autofocus;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(AppRadius.input);
    final baseBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide.none,
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
    );
    final errorBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: const BorderSide(color: AppColors.danger, width: 1.0),
    );
    final focusedErrorBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
    );

    // Com maxLength: o label sobe para uma linha própria acima do campo
    // (label à esquerda, contador X/Y à direita) e o contador padrão do
    // rodapé é suprimido. Sem maxLength: comportamento original intacto
    // (label flutuante do TextFormField) — não afeta o _TriggerSheet.
    final hasCounter = maxLength != null;

    final field = TextFormField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      maxLines: maxLines,
      maxLength: maxLength,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: hasCounter ? null : label,
        counterText: hasCounter ? '' : null,
        hintText: hint,
        suffixText: suffixText,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        helperText: helperText,
        helperStyle: helperStyle ??
            AppTypography.caption.copyWith(color: AppColors.textDisabled),
        labelStyle: AppTypography.bodySmall.copyWith(
          color: AppColors.textSecondary,
        ),
        floatingLabelStyle: AppTypography.caption.copyWith(
          color: AppColors.accent,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: AppTypography.bodySmall.copyWith(
          color: AppColors.textDisabled,
        ),
        suffixStyle: AppTypography.bodySmall.copyWith(
          color: AppColors.textSecondary,
        ),
        errorStyle: AppTypography.caption.copyWith(
          color: AppColors.danger,
        ),
        counterStyle: AppTypography.caption.copyWith(
          color: AppColors.textDisabled,
        ),
        filled: true,
        fillColor: AppColors.backgroundInput,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: baseBorder,
        enabledBorder: baseBorder,
        focusedBorder: focusedBorder,
        errorBorder: errorBorder,
        focusedErrorBorder: focusedErrorBorder,
      ),
    );

    if (!hasCounter) return field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xxs,
            right: AppSpacing.xxs,
            bottom: AppSpacing.gap6,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label ?? '',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
              // Contador em tempo real: ouve o controller e atualiza a cada tecla.
              _CharCounter(controller: controller, maxLength: maxLength!),
            ],
          ),
        ),
        field,
      ],
    );
  }
}

/// Contador "X/Y" reativo — reflete o tamanho atual do texto do [controller].
/// Sem controller cai para "0/Y" estático (caso raro; todo campo com maxLength
/// no app passa um controller).
class _CharCounter extends StatelessWidget {
  const _CharCounter({required this.controller, required this.maxLength});

  final TextEditingController? controller;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    final style =
        AppTypography.caption.copyWith(color: AppColors.textDisabled);
    if (controller == null) {
      return Text('0/$maxLength', style: style);
    }
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller!,
      builder: (_, value, __) =>
          Text('${value.text.characters.length}/$maxLength', style: style),
    );
  }
}
