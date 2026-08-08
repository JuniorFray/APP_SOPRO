import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

// Switch padrão do app — ponto ÚNICO de estilo/tamanho dos toggles.
//
// Estilo: ligado coral (trilho) + thumb claro; desligado neutro; sem outline.
// Reduzido ~30% via Transform.scale (paint-only: não altera o espaço ocupado no
// layout, então não quebra alinhamento — só o visual encolhe). A área de toque
// escala junto, mas parte de um alvo padrão (sem shrinkWrap) para continuar
// confortável.
//
// Toda tela deve usar este widget em vez de Switch cru, garantindo consistência.
// [activeTrackColor] só é sobrescrito quando há semântica de marca no trilho
// ligado (ex.: Google azul / Outlook azul na tela de contas da Agenda).
class SoproSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeTrackColor;

  const SoproSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeTrackColor,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.7, // ~-30% no visual
      child: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.textPrimary,
        activeTrackColor: activeTrackColor ?? AppColors.accent,
        inactiveThumbColor: AppColors.textDisabled,
        inactiveTrackColor: AppColors.backgroundElevated,
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    );
  }
}
