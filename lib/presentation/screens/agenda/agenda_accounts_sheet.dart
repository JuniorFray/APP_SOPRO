import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:device_calendar/device_calendar.dart' as dc;
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'dart:io' show Platform;

import '../../../core/theme/app_colors.dart';
import '../../../domain/models/calendar_event.dart';
import '../../providers/agenda_providers.dart';
import '../../widgets/sopro_switch.dart';

class AgendaAccountsSheet extends ConsumerStatefulWidget {
  const AgendaAccountsSheet({super.key});

  @override
  ConsumerState<AgendaAccountsSheet> createState() => _AgendaAccountsSheetState();
}

class _AgendaAccountsSheetState extends ConsumerState<AgendaAccountsSheet> {
  final dc.DeviceCalendarPlugin _deviceCalendarPlugin = dc.DeviceCalendarPlugin();
  List<dc.Calendar> _calendars = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCalendars();
  }

  Future<void> _loadCalendars() async {
    final permissionsGranted = await _deviceCalendarPlugin.hasPermissions();
    if (permissionsGranted.isSuccess && permissionsGranted.data!) {
      final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
      if (calendarsResult.isSuccess && calendarsResult.data != null) {
        setState(() {
          _calendars = calendarsResult.data!;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openAddAccountSettings() async {
    if (Platform.isAndroid) {
      const intent = AndroidIntent(
        action: 'android.settings.ADD_ACCOUNT_SETTINGS',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vá em Ajustes > Senhas e Contas no iPhone.')),
      );
    }
  }

  bool _isGoogleAccount(String name) {
    final lower = name.toLowerCase();
    return lower.contains('gmail') || lower.contains('google') || lower.contains('com.google');
  }

  bool _isOutlookAccount(String name) {
    final lower = name.toLowerCase();
    return lower.contains('outlook') || lower.contains('hotmail') || lower.contains('live') || lower.contains('office365') || lower.contains('microsoft');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agendaProvider);
    final notifier = ref.read(agendaProvider.notifier);

    // Filter discovered calendars from the device
    final googleCalendars = _calendars.where((c) => _isGoogleAccount(c.accountName ?? c.name ?? '')).toList();
    final outlookCalendars = _calendars.where((c) => _isOutlookAccount(c.accountName ?? c.name ?? '')).toList();
    final otherCalendars = _calendars.where((c) => !_isGoogleAccount(c.accountName ?? c.name ?? '') && !_isOutlookAccount(c.accountName ?? c.name ?? '')).toList();

    final isSoproEnabled = state.enabledSources.contains(EventSource.sopro);
    final isGoogleEnabled = state.enabledSources.contains(EventSource.google);
    final isOutlookEnabled = state.enabledSources.contains(EventSource.outlook);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.backgroundSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.only(top: 16),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Calendários & Sincronização',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 6),
              child: Text(
                'Gerencie quais contas exibem eventos no Sopro.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),

            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    // 1. Agenda Pessoal Sopro (Sempre presente)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.backgroundCardHighlight,
                        child: Icon(Icons.person_outline, color: AppColors.accent, size: 22),
                      ),
                      title: const Text(
                        'Pessoal (Sopro)',
                        style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      subtitle: const Text(
                        'Eventos locais e exclusivos do app',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      trailing: SoproSwitch(
                        value: isSoproEnabled,
                        onChanged: (_) => notifier.toggleSource(EventSource.sopro),
                      ),
                    ),

                    // 2. Google Workspace / Google Calendar
                    if (googleCalendars.isNotEmpty) ...[
                      ...googleCalendars.map((cal) {
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
                          leading: const CircleAvatar(
                            backgroundColor: AppColors.backgroundCardHighlight,
                            child: Icon(Icons.g_mobiledata, color: Color(0xFF4285F4), size: 26),
                          ),
                          title: Text(
                            cal.name ?? 'Google Calendar',
                            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                          subtitle: Text(
                            cal.accountName ?? 'Google Workspace',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                          trailing: SoproSwitch(
                            value: isGoogleEnabled,
                            onChanged: (_) => notifier.toggleSource(EventSource.google),
                            // Marca Google: trilho azul quando ligado.
                            activeTrackColor: const Color(0xFF4285F4),
                          ),
                        );
                      }),
                    ] else ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                        child: OutlinedButton.icon(
                          onPressed: _openAddAccountSettings,
                          icon: const Icon(Icons.g_mobiledata, color: Color(0xFF4285F4), size: 26),
                          label: const Text('Conectar Google Calendar', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.border),
                            minimumSize: const Size(double.infinity, 48),
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],

                    // 3. Outlook / Microsoft
                    if (outlookCalendars.isNotEmpty) ...[
                      ...outlookCalendars.map((cal) {
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
                          leading: const CircleAvatar(
                            backgroundColor: AppColors.backgroundCardHighlight,
                            child: Icon(Icons.mail_outline, color: Color(0xFF0078D4), size: 22),
                          ),
                          title: Text(
                            cal.name ?? 'Outlook Calendar',
                            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                          subtitle: Text(
                            cal.accountName ?? 'Microsoft Outlook',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                          trailing: SoproSwitch(
                            value: isOutlookEnabled,
                            onChanged: (_) => notifier.toggleSource(EventSource.outlook),
                            // Marca Outlook: trilho azul quando ligado.
                            activeTrackColor: const Color(0xFF0078D4),
                          ),
                        );
                      }),
                    ] else ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                        child: OutlinedButton.icon(
                          onPressed: _openAddAccountSettings,
                          icon: const Icon(Icons.mail_outline, color: Color(0xFF0078D4), size: 22),
                          label: const Text('Conectar Outlook Calendar', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.border),
                            minimumSize: const Size(double.infinity, 48),
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],

                    // 4. Outros calendários locais detectados no celular
                    if (otherCalendars.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.only(left: 24, top: 12, bottom: 4),
                        child: Text(
                          'Outros Calendários Locais',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ...otherCalendars.map((cal) {
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                          leading: const CircleAvatar(
                            backgroundColor: AppColors.backgroundCardHighlight,
                            child: Icon(Icons.calendar_today, color: AppColors.textSecondary, size: 18),
                          ),
                          title: Text(cal.name ?? 'Calendário Local', style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                          subtitle: Text(cal.accountName ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        );
                      }),
                    ],
                  ],
                ),
              ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
