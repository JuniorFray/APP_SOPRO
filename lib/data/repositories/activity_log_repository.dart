import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/daos/activity_log_dao.dart';
import '../database/sopro_database.dart';
import '../../domain/entities/activity_log_entry_entity.dart';
import '../../domain/repositories/i_activity_log_repository.dart';

// Implementação concreta do IActivityLogRepository usando Drift (SQLite).
// Converte entre o row do banco (ActivityLogEntry) e a entidade de domínio,
// incluindo o parsing do campo type (string snake_case <-> enum ActivityType).
class ActivityLogRepository implements IActivityLogRepository {
  final ActivityLogDao _dao;
  final _uuid = const Uuid();

  ActivityLogRepository(this._dao);

  @override
  Stream<List<ActivityLogEntryEntity>> watchRecent({int limit = 20}) =>
      _dao.watchRecent(limit: limit).map((rows) => rows.map(_toEntity).toList());

  @override
  Future<void> log({
    required ActivityType type,
    required String title,
    String subtitle = '',
    String? environmentId,
  }) {
    return _dao.insert(
      ActivityLogEntriesCompanion(
        id: Value(_uuid.v4()),
        type: Value(_typeToString(type)),
        title: Value(title),
        subtitle: Value(subtitle),
        environmentId: Value(environmentId),
        createdAt: Value(DateTime.now()),
      ),
    );
  }

  ActivityLogEntryEntity _toEntity(ActivityLogEntry row) =>
      ActivityLogEntryEntity(
        id: row.id,
        type: _typeFromString(row.type),
        title: row.title,
        subtitle: row.subtitle,
        environmentId: row.environmentId,
        createdAt: row.createdAt,
      );

  // --- Conversão do campo type (persistido como snake_case) ---

  static const _typeStrings = {
    ActivityType.environmentEntered: 'environment_entered',
    ActivityType.triggerFired: 'trigger_fired',
    ActivityType.reminderCompleted: 'reminder_completed',
    ActivityType.shoppingCompleted: 'shopping_completed',
  };

  String _typeToString(ActivityType type) => _typeStrings[type]!;

  ActivityType _typeFromString(String value) => _typeStrings.entries
      .firstWhere(
        (e) => e.value == value,
        orElse: () =>
            const MapEntry(ActivityType.environmentEntered, 'environment_entered'),
      )
      .key;
}
