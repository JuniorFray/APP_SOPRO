import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/daos/scheduled_reminders_dao.dart';
import '../database/sopro_database.dart';
import '../../domain/entities/scheduled_reminder_entity.dart';
import '../../domain/repositories/i_scheduled_reminder_repository.dart';
import '../../infrastructure/reminders/reminder_scheduler.dart';

// Implementação concreta do IScheduledReminderRepository usando Drift (SQLite).
// Converte entre o row do banco (ScheduledReminder) e a entidade de domínio,
// incluindo o parsing dos campos compostos (repeatRule string <-> enum e
// repeatDaysOfWeek "1,3,5" <-> List<int>).
//
// Além de persistir, sincroniza o alarme nativo (ReminderScheduler): agenda ao
// criar/atualizar um lembrete ativo, cancela ao desativar ou deletar.
class ScheduledReminderRepository implements IScheduledReminderRepository {
  final ScheduledRemindersDao _dao;
  final ReminderScheduler _scheduler;
  final _uuid = const Uuid();

  ScheduledReminderRepository(this._dao, this._scheduler);

  @override
  Stream<List<ScheduledReminderEntity>> watchAllActive() =>
      _dao.watchAllActive().map((rows) => rows.map(_toEntity).toList());

  @override
  Stream<ScheduledReminderEntity?> watchNext() =>
      _dao.watchNext().map((row) => row == null ? null : _toEntity(row));

  @override
  Future<void> upsert(ScheduledReminderEntity reminder) async {
    final id = reminder.id.isEmpty ? _uuid.v4() : reminder.id;
    await _dao.upsert(
      ScheduledRemindersCompanion(
        id: Value(id),
        title: Value(reminder.title),
        content: Value(reminder.content),
        scheduledAt: Value(reminder.scheduledAt),
        repeatRule: Value(_ruleToString(reminder.repeatRule)),
        repeatDaysOfWeek: Value(_daysToString(reminder.repeatDaysOfWeek)),
        isActive: Value(reminder.isActive),
        alertMode: Value(_alertToString(reminder.alertMode)),
        createdAt: Value(reminder.createdAt),
      ),
    );
    // Sincroniza o alarme nativo: ativo → agenda; inativo → cancela.
    if (reminder.isActive) {
      await _scheduler.scheduleReminder(
          id, reminder.scheduledAt.millisecondsSinceEpoch);
    } else {
      await _scheduler.cancelReminder(id);
    }
  }

  @override
  Future<void> setActive(String id, bool active) async {
    await _dao.setActive(id, active: active);
    // Desativar cancela o alarme pendente (reativar volta a agendar via upsert).
    if (!active) await _scheduler.cancelReminder(id);
  }

  @override
  Future<void> delete(String id) async {
    await _dao.deleteById(id);
    await _scheduler.cancelReminder(id);
  }

  @override
  Future<void> updateAlertMode(String id, ReminderAlertMode mode) =>
      // Só altera a coluna: o próximo disparo relê alert_mode do banco, então
      // não é preciso reagendar o alarme nativo já existente.
      _dao.updateAlertMode(id, _alertToString(mode));

  ScheduledReminderEntity _toEntity(ScheduledReminder row) =>
      ScheduledReminderEntity(
        id: row.id,
        title: row.title,
        content: row.content,
        scheduledAt: row.scheduledAt,
        repeatRule: _ruleFromString(row.repeatRule),
        repeatDaysOfWeek: _daysFromString(row.repeatDaysOfWeek),
        isActive: row.isActive,
        alertMode: _alertFromString(row.alertMode),
        createdAt: row.createdAt,
      );

  // --- Conversões dos campos compostos ---

  String _ruleToString(ReminderRepeatRule rule) => rule.name; // none/daily/weekly

  ReminderRepeatRule _ruleFromString(String value) =>
      ReminderRepeatRule.values.firstWhere(
        (r) => r.name == value,
        orElse: () => ReminderRepeatRule.none,
      );

  String _daysToString(List<int> days) => days.join(',');

  List<int> _daysFromString(String value) => value.isEmpty
      ? const []
      : value.split(',').map(int.parse).toList();

  String _alertToString(ReminderAlertMode mode) => mode.name; // notification/alarm/both

  ReminderAlertMode _alertFromString(String value) =>
      ReminderAlertMode.values.firstWhere(
        (m) => m.name == value,
        orElse: () => ReminderAlertMode.notification,
      );
}
