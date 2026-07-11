import 'package:flutter/material.dart';

/// Aliases semânticos para os Material Icons usados no Sopro.
/// Facilita substituição futura por ícones customizados em um único lugar.
/// Inclui apenas ícones que representam conceitos centrais do app ou
/// aparecem em múltiplas telas.
abstract final class AppIcons {
  // ── Voz (feature central) ──────────────────────────────────────────────────
  static const IconData micIdle     = Icons.mic_rounded;
  static const IconData micOff      = Icons.mic_off_rounded;
  static const IconData micExternal = Icons.mic_external_on_outlined;
  static const IconData voiceOver   = Icons.record_voice_over_outlined;

  // ── Localização e ambientes ────────────────────────────────────────────────
  static const IconData location    = Icons.location_on_outlined;
  static const IconData locationOff = Icons.location_off_outlined;
  static const IconData locationPin = Icons.location_pin;
  static const IconData locationAdd = Icons.add_location_alt_outlined;
  static const IconData myLocation  = Icons.my_location;

  // ── Gatilhos ───────────────────────────────────────────────────────────────
  static const IconData trigger = Icons.bolt_outlined;
  static const IconData check   = Icons.check_rounded;

  // ── Ações CRUD ─────────────────────────────────────────────────────────────
  static const IconData add     = Icons.add;
  static const IconData edit    = Icons.edit_outlined;
  static const IconData delete  = Icons.delete_outline;
  static const IconData warning = Icons.warning_amber_rounded;

  // ── Navegação ──────────────────────────────────────────────────────────────
  static const IconData people       = Icons.people_outline;
  static const IconData person       = Icons.person_outline;
  static const IconData settings     = Icons.settings_outlined;
  static const IconData chevronRight = Icons.chevron_right;

  // ── Notificações e conectividade ──────────────────────────────────────────
  static const IconData notification = Icons.notifications_none_outlined;
  static const IconData bluetooth    = Icons.bluetooth_outlined;

  // ── Identidade do app ─────────────────────────────────────────────────────
  static const IconData air  = Icons.air;
  static const IconData info = Icons.info_outline;
}
