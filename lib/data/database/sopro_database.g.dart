// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sopro_database.dart';

// ignore_for_file: type=lint
class $EnvironmentsTable extends Environments
    with TableInfo<$EnvironmentsTable, Environment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EnvironmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 100),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _latitudeMeta =
      const VerificationMeta('latitude');
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
      'latitude', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _longitudeMeta =
      const VerificationMeta('longitude');
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
      'longitude', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _radiusMetersMeta =
      const VerificationMeta('radiusMeters');
  @override
  late final GeneratedColumn<double> radiusMeters = GeneratedColumn<double>(
      'radius_meters', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _isMarketMeta =
      const VerificationMeta('isMarket');
  @override
  late final GeneratedColumn<bool> isMarket = GeneratedColumn<bool>(
      'is_market', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_market" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, latitude, longitude, radiusMeters, createdAt, isMarket];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'environments';
  @override
  VerificationContext validateIntegrity(Insertable<Environment> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(_latitudeMeta,
          latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta));
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(_longitudeMeta,
          longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta));
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('radius_meters')) {
      context.handle(
          _radiusMetersMeta,
          radiusMeters.isAcceptableOrUnknown(
              data['radius_meters']!, _radiusMetersMeta));
    } else if (isInserting) {
      context.missing(_radiusMetersMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('is_market')) {
      context.handle(_isMarketMeta,
          isMarket.isAcceptableOrUnknown(data['is_market']!, _isMarketMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Environment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Environment(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      latitude: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}latitude'])!,
      longitude: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}longitude'])!,
      radiusMeters: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}radius_meters'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      isMarket: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_market'])!,
    );
  }

  @override
  $EnvironmentsTable createAlias(String alias) {
    return $EnvironmentsTable(attachedDatabase, alias);
  }
}

class Environment extends DataClass implements Insertable<Environment> {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final DateTime createdAt;
  final bool isMarket;
  const Environment(
      {required this.id,
      required this.name,
      required this.latitude,
      required this.longitude,
      required this.radiusMeters,
      required this.createdAt,
      required this.isMarket});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    map['radius_meters'] = Variable<double>(radiusMeters);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['is_market'] = Variable<bool>(isMarket);
    return map;
  }

  EnvironmentsCompanion toCompanion(bool nullToAbsent) {
    return EnvironmentsCompanion(
      id: Value(id),
      name: Value(name),
      latitude: Value(latitude),
      longitude: Value(longitude),
      radiusMeters: Value(radiusMeters),
      createdAt: Value(createdAt),
      isMarket: Value(isMarket),
    );
  }

  factory Environment.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Environment(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      radiusMeters: serializer.fromJson<double>(json['radiusMeters']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      isMarket: serializer.fromJson<bool>(json['isMarket']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'radiusMeters': serializer.toJson<double>(radiusMeters),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'isMarket': serializer.toJson<bool>(isMarket),
    };
  }

  Environment copyWith(
          {String? id,
          String? name,
          double? latitude,
          double? longitude,
          double? radiusMeters,
          DateTime? createdAt,
          bool? isMarket}) =>
      Environment(
        id: id ?? this.id,
        name: name ?? this.name,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        radiusMeters: radiusMeters ?? this.radiusMeters,
        createdAt: createdAt ?? this.createdAt,
        isMarket: isMarket ?? this.isMarket,
      );
  Environment copyWithCompanion(EnvironmentsCompanion data) {
    return Environment(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      radiusMeters: data.radiusMeters.present
          ? data.radiusMeters.value
          : this.radiusMeters,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      isMarket: data.isMarket.present ? data.isMarket.value : this.isMarket,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Environment(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('radiusMeters: $radiusMeters, ')
          ..write('createdAt: $createdAt, ')
          ..write('isMarket: $isMarket')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, name, latitude, longitude, radiusMeters, createdAt, isMarket);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Environment &&
          other.id == this.id &&
          other.name == this.name &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.radiusMeters == this.radiusMeters &&
          other.createdAt == this.createdAt &&
          other.isMarket == this.isMarket);
}

class EnvironmentsCompanion extends UpdateCompanion<Environment> {
  final Value<String> id;
  final Value<String> name;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<double> radiusMeters;
  final Value<DateTime> createdAt;
  final Value<bool> isMarket;
  final Value<int> rowid;
  const EnvironmentsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.radiusMeters = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.isMarket = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EnvironmentsCompanion.insert({
    required String id,
    required String name,
    required double latitude,
    required double longitude,
    required double radiusMeters,
    required DateTime createdAt,
    this.isMarket = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        latitude = Value(latitude),
        longitude = Value(longitude),
        radiusMeters = Value(radiusMeters),
        createdAt = Value(createdAt);
  static Insertable<Environment> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? radiusMeters,
    Expression<DateTime>? createdAt,
    Expression<bool>? isMarket,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (radiusMeters != null) 'radius_meters': radiusMeters,
      if (createdAt != null) 'created_at': createdAt,
      if (isMarket != null) 'is_market': isMarket,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EnvironmentsCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<double>? latitude,
      Value<double>? longitude,
      Value<double>? radiusMeters,
      Value<DateTime>? createdAt,
      Value<bool>? isMarket,
      Value<int>? rowid}) {
    return EnvironmentsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      createdAt: createdAt ?? this.createdAt,
      isMarket: isMarket ?? this.isMarket,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (radiusMeters.present) {
      map['radius_meters'] = Variable<double>(radiusMeters.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (isMarket.present) {
      map['is_market'] = Variable<bool>(isMarket.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EnvironmentsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('radiusMeters: $radiusMeters, ')
          ..write('createdAt: $createdAt, ')
          ..write('isMarket: $isMarket, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TriggersTable extends Triggers
    with TableInfo<$TriggersTable, TriggerRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TriggersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _environmentIdMeta =
      const VerificationMeta('environmentId');
  @override
  late final GeneratedColumn<String> environmentId = GeneratedColumn<String>(
      'environment_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES environments (id) ON DELETE CASCADE'));
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      additionalChecks: GeneratedColumn.checkTextLength(maxTextLength: 200),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, environmentId, title, content, isActive, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'triggers';
  @override
  VerificationContext validateIntegrity(Insertable<TriggerRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('environment_id')) {
      context.handle(
          _environmentIdMeta,
          environmentId.isAcceptableOrUnknown(
              data['environment_id']!, _environmentIdMeta));
    } else if (isInserting) {
      context.missing(_environmentIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TriggerRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TriggerRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      environmentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}environment_id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $TriggersTable createAlias(String alias) {
    return $TriggersTable(attachedDatabase, alias);
  }
}

class TriggerRow extends DataClass implements Insertable<TriggerRow> {
  final String id;
  final String environmentId;
  final String title;
  final String content;
  final bool isActive;
  final DateTime createdAt;
  const TriggerRow(
      {required this.id,
      required this.environmentId,
      required this.title,
      required this.content,
      required this.isActive,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['environment_id'] = Variable<String>(environmentId);
    map['title'] = Variable<String>(title);
    map['content'] = Variable<String>(content);
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  TriggersCompanion toCompanion(bool nullToAbsent) {
    return TriggersCompanion(
      id: Value(id),
      environmentId: Value(environmentId),
      title: Value(title),
      content: Value(content),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
    );
  }

  factory TriggerRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TriggerRow(
      id: serializer.fromJson<String>(json['id']),
      environmentId: serializer.fromJson<String>(json['environmentId']),
      title: serializer.fromJson<String>(json['title']),
      content: serializer.fromJson<String>(json['content']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'environmentId': serializer.toJson<String>(environmentId),
      'title': serializer.toJson<String>(title),
      'content': serializer.toJson<String>(content),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  TriggerRow copyWith(
          {String? id,
          String? environmentId,
          String? title,
          String? content,
          bool? isActive,
          DateTime? createdAt}) =>
      TriggerRow(
        id: id ?? this.id,
        environmentId: environmentId ?? this.environmentId,
        title: title ?? this.title,
        content: content ?? this.content,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt ?? this.createdAt,
      );
  TriggerRow copyWithCompanion(TriggersCompanion data) {
    return TriggerRow(
      id: data.id.present ? data.id.value : this.id,
      environmentId: data.environmentId.present
          ? data.environmentId.value
          : this.environmentId,
      title: data.title.present ? data.title.value : this.title,
      content: data.content.present ? data.content.value : this.content,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TriggerRow(')
          ..write('id: $id, ')
          ..write('environmentId: $environmentId, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, environmentId, title, content, isActive, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TriggerRow &&
          other.id == this.id &&
          other.environmentId == this.environmentId &&
          other.title == this.title &&
          other.content == this.content &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt);
}

class TriggersCompanion extends UpdateCompanion<TriggerRow> {
  final Value<String> id;
  final Value<String> environmentId;
  final Value<String> title;
  final Value<String> content;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const TriggersCompanion({
    this.id = const Value.absent(),
    this.environmentId = const Value.absent(),
    this.title = const Value.absent(),
    this.content = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TriggersCompanion.insert({
    required String id,
    required String environmentId,
    required String title,
    required String content,
    this.isActive = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        environmentId = Value(environmentId),
        title = Value(title),
        content = Value(content),
        createdAt = Value(createdAt);
  static Insertable<TriggerRow> custom({
    Expression<String>? id,
    Expression<String>? environmentId,
    Expression<String>? title,
    Expression<String>? content,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (environmentId != null) 'environment_id': environmentId,
      if (title != null) 'title': title,
      if (content != null) 'content': content,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TriggersCompanion copyWith(
      {Value<String>? id,
      Value<String>? environmentId,
      Value<String>? title,
      Value<String>? content,
      Value<bool>? isActive,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return TriggersCompanion(
      id: id ?? this.id,
      environmentId: environmentId ?? this.environmentId,
      title: title ?? this.title,
      content: content ?? this.content,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (environmentId.present) {
      map['environment_id'] = Variable<String>(environmentId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TriggersCompanion(')
          ..write('id: $id, ')
          ..write('environmentId: $environmentId, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ContextCardsTable extends ContextCards
    with TableInfo<$ContextCardsTable, ContextCard> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ContextCardsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _displayNameMeta =
      const VerificationMeta('displayName');
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
      'display_name', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 50),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
      'role', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _companyMeta =
      const VerificationMeta('company');
  @override
  late final GeneratedColumn<String> company = GeneratedColumn<String>(
      'company', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _bioMeta = const VerificationMeta('bio');
  @override
  late final GeneratedColumn<String> bio = GeneratedColumn<String>(
      'bio', aliasedName, false,
      additionalChecks: GeneratedColumn.checkTextLength(maxTextLength: 500),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _tagsMeta = const VerificationMeta('tags');
  @override
  late final GeneratedColumn<String> tags = GeneratedColumn<String>(
      'tags', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
      'phone', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, displayName, role, company, bio, tags, phone, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'context_cards';
  @override
  VerificationContext validateIntegrity(Insertable<ContextCard> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
          _displayNameMeta,
          displayName.isAcceptableOrUnknown(
              data['display_name']!, _displayNameMeta));
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
          _roleMeta, role.isAcceptableOrUnknown(data['role']!, _roleMeta));
    }
    if (data.containsKey('company')) {
      context.handle(_companyMeta,
          company.isAcceptableOrUnknown(data['company']!, _companyMeta));
    }
    if (data.containsKey('bio')) {
      context.handle(
          _bioMeta, bio.isAcceptableOrUnknown(data['bio']!, _bioMeta));
    } else if (isInserting) {
      context.missing(_bioMeta);
    }
    if (data.containsKey('tags')) {
      context.handle(
          _tagsMeta, tags.isAcceptableOrUnknown(data['tags']!, _tagsMeta));
    }
    if (data.containsKey('phone')) {
      context.handle(
          _phoneMeta, phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ContextCard map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ContextCard(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      displayName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}display_name'])!,
      role: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}role'])!,
      company: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}company'])!,
      bio: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}bio'])!,
      tags: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tags'])!,
      phone: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}phone'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $ContextCardsTable createAlias(String alias) {
    return $ContextCardsTable(attachedDatabase, alias);
  }
}

class ContextCard extends DataClass implements Insertable<ContextCard> {
  final String id;
  final String displayName;
  final String role;
  final String company;
  final String bio;
  final String tags;
  final String phone;
  final DateTime createdAt;
  final DateTime updatedAt;
  const ContextCard(
      {required this.id,
      required this.displayName,
      required this.role,
      required this.company,
      required this.bio,
      required this.tags,
      required this.phone,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['display_name'] = Variable<String>(displayName);
    map['role'] = Variable<String>(role);
    map['company'] = Variable<String>(company);
    map['bio'] = Variable<String>(bio);
    map['tags'] = Variable<String>(tags);
    map['phone'] = Variable<String>(phone);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ContextCardsCompanion toCompanion(bool nullToAbsent) {
    return ContextCardsCompanion(
      id: Value(id),
      displayName: Value(displayName),
      role: Value(role),
      company: Value(company),
      bio: Value(bio),
      tags: Value(tags),
      phone: Value(phone),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ContextCard.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ContextCard(
      id: serializer.fromJson<String>(json['id']),
      displayName: serializer.fromJson<String>(json['displayName']),
      role: serializer.fromJson<String>(json['role']),
      company: serializer.fromJson<String>(json['company']),
      bio: serializer.fromJson<String>(json['bio']),
      tags: serializer.fromJson<String>(json['tags']),
      phone: serializer.fromJson<String>(json['phone']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'displayName': serializer.toJson<String>(displayName),
      'role': serializer.toJson<String>(role),
      'company': serializer.toJson<String>(company),
      'bio': serializer.toJson<String>(bio),
      'tags': serializer.toJson<String>(tags),
      'phone': serializer.toJson<String>(phone),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ContextCard copyWith(
          {String? id,
          String? displayName,
          String? role,
          String? company,
          String? bio,
          String? tags,
          String? phone,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      ContextCard(
        id: id ?? this.id,
        displayName: displayName ?? this.displayName,
        role: role ?? this.role,
        company: company ?? this.company,
        bio: bio ?? this.bio,
        tags: tags ?? this.tags,
        phone: phone ?? this.phone,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  ContextCard copyWithCompanion(ContextCardsCompanion data) {
    return ContextCard(
      id: data.id.present ? data.id.value : this.id,
      displayName:
          data.displayName.present ? data.displayName.value : this.displayName,
      role: data.role.present ? data.role.value : this.role,
      company: data.company.present ? data.company.value : this.company,
      bio: data.bio.present ? data.bio.value : this.bio,
      tags: data.tags.present ? data.tags.value : this.tags,
      phone: data.phone.present ? data.phone.value : this.phone,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ContextCard(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('role: $role, ')
          ..write('company: $company, ')
          ..write('bio: $bio, ')
          ..write('tags: $tags, ')
          ..write('phone: $phone, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, displayName, role, company, bio, tags, phone, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContextCard &&
          other.id == this.id &&
          other.displayName == this.displayName &&
          other.role == this.role &&
          other.company == this.company &&
          other.bio == this.bio &&
          other.tags == this.tags &&
          other.phone == this.phone &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ContextCardsCompanion extends UpdateCompanion<ContextCard> {
  final Value<String> id;
  final Value<String> displayName;
  final Value<String> role;
  final Value<String> company;
  final Value<String> bio;
  final Value<String> tags;
  final Value<String> phone;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ContextCardsCompanion({
    this.id = const Value.absent(),
    this.displayName = const Value.absent(),
    this.role = const Value.absent(),
    this.company = const Value.absent(),
    this.bio = const Value.absent(),
    this.tags = const Value.absent(),
    this.phone = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ContextCardsCompanion.insert({
    required String id,
    required String displayName,
    this.role = const Value.absent(),
    this.company = const Value.absent(),
    required String bio,
    this.tags = const Value.absent(),
    this.phone = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        displayName = Value(displayName),
        bio = Value(bio),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<ContextCard> custom({
    Expression<String>? id,
    Expression<String>? displayName,
    Expression<String>? role,
    Expression<String>? company,
    Expression<String>? bio,
    Expression<String>? tags,
    Expression<String>? phone,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (displayName != null) 'display_name': displayName,
      if (role != null) 'role': role,
      if (company != null) 'company': company,
      if (bio != null) 'bio': bio,
      if (tags != null) 'tags': tags,
      if (phone != null) 'phone': phone,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ContextCardsCompanion copyWith(
      {Value<String>? id,
      Value<String>? displayName,
      Value<String>? role,
      Value<String>? company,
      Value<String>? bio,
      Value<String>? tags,
      Value<String>? phone,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return ContextCardsCompanion(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      company: company ?? this.company,
      bio: bio ?? this.bio,
      tags: tags ?? this.tags,
      phone: phone ?? this.phone,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (company.present) {
      map['company'] = Variable<String>(company.value);
    }
    if (bio.present) {
      map['bio'] = Variable<String>(bio.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(tags.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContextCardsCompanion(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('role: $role, ')
          ..write('company: $company, ')
          ..write('bio: $bio, ')
          ..write('tags: $tags, ')
          ..write('phone: $phone, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BleEncountersTable extends BleEncounters
    with TableInfo<$BleEncountersTable, BleEncounter> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BleEncountersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta =
      const VerificationMeta('deviceId');
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
      'device_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _displayNameMeta =
      const VerificationMeta('displayName');
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
      'display_name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
      'role', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _companyMeta =
      const VerificationMeta('company');
  @override
  late final GeneratedColumn<String> company = GeneratedColumn<String>(
      'company', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _bioMeta = const VerificationMeta('bio');
  @override
  late final GeneratedColumn<String> bio = GeneratedColumn<String>(
      'bio', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _tagsMeta = const VerificationMeta('tags');
  @override
  late final GeneratedColumn<String> tags = GeneratedColumn<String>(
      'tags', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
      'phone', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _encounteredAtMeta =
      const VerificationMeta('encounteredAt');
  @override
  late final GeneratedColumn<DateTime> encounteredAt =
      GeneratedColumn<DateTime>('encountered_at', aliasedName, false,
          type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [deviceId, displayName, role, company, bio, tags, phone, encounteredAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ble_encounters';
  @override
  VerificationContext validateIntegrity(Insertable<BleEncounter> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(_deviceIdMeta,
          deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta));
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
          _displayNameMeta,
          displayName.isAcceptableOrUnknown(
              data['display_name']!, _displayNameMeta));
    }
    if (data.containsKey('role')) {
      context.handle(
          _roleMeta, role.isAcceptableOrUnknown(data['role']!, _roleMeta));
    }
    if (data.containsKey('company')) {
      context.handle(_companyMeta,
          company.isAcceptableOrUnknown(data['company']!, _companyMeta));
    }
    if (data.containsKey('bio')) {
      context.handle(
          _bioMeta, bio.isAcceptableOrUnknown(data['bio']!, _bioMeta));
    }
    if (data.containsKey('tags')) {
      context.handle(
          _tagsMeta, tags.isAcceptableOrUnknown(data['tags']!, _tagsMeta));
    }
    if (data.containsKey('phone')) {
      context.handle(
          _phoneMeta, phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta));
    }
    if (data.containsKey('encountered_at')) {
      context.handle(
          _encounteredAtMeta,
          encounteredAt.isAcceptableOrUnknown(
              data['encountered_at']!, _encounteredAtMeta));
    } else if (isInserting) {
      context.missing(_encounteredAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deviceId};
  @override
  BleEncounter map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BleEncounter(
      deviceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}device_id'])!,
      displayName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}display_name'])!,
      role: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}role'])!,
      company: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}company'])!,
      bio: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}bio'])!,
      tags: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tags'])!,
      phone: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}phone'])!,
      encounteredAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}encountered_at'])!,
    );
  }

  @override
  $BleEncountersTable createAlias(String alias) {
    return $BleEncountersTable(attachedDatabase, alias);
  }
}

class BleEncounter extends DataClass implements Insertable<BleEncounter> {
  final String deviceId;
  final String displayName;
  final String role;
  final String company;
  final String bio;
  final String tags;
  final String phone;
  final DateTime encounteredAt;
  const BleEncounter(
      {required this.deviceId,
      required this.displayName,
      required this.role,
      required this.company,
      required this.bio,
      required this.tags,
      required this.phone,
      required this.encounteredAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_id'] = Variable<String>(deviceId);
    map['display_name'] = Variable<String>(displayName);
    map['role'] = Variable<String>(role);
    map['company'] = Variable<String>(company);
    map['bio'] = Variable<String>(bio);
    map['tags'] = Variable<String>(tags);
    map['phone'] = Variable<String>(phone);
    map['encountered_at'] = Variable<DateTime>(encounteredAt);
    return map;
  }

  BleEncountersCompanion toCompanion(bool nullToAbsent) {
    return BleEncountersCompanion(
      deviceId: Value(deviceId),
      displayName: Value(displayName),
      role: Value(role),
      company: Value(company),
      bio: Value(bio),
      tags: Value(tags),
      phone: Value(phone),
      encounteredAt: Value(encounteredAt),
    );
  }

  factory BleEncounter.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BleEncounter(
      deviceId: serializer.fromJson<String>(json['deviceId']),
      displayName: serializer.fromJson<String>(json['displayName']),
      role: serializer.fromJson<String>(json['role']),
      company: serializer.fromJson<String>(json['company']),
      bio: serializer.fromJson<String>(json['bio']),
      tags: serializer.fromJson<String>(json['tags']),
      phone: serializer.fromJson<String>(json['phone']),
      encounteredAt: serializer.fromJson<DateTime>(json['encounteredAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String>(deviceId),
      'displayName': serializer.toJson<String>(displayName),
      'role': serializer.toJson<String>(role),
      'company': serializer.toJson<String>(company),
      'bio': serializer.toJson<String>(bio),
      'tags': serializer.toJson<String>(tags),
      'phone': serializer.toJson<String>(phone),
      'encounteredAt': serializer.toJson<DateTime>(encounteredAt),
    };
  }

  BleEncounter copyWith(
          {String? deviceId,
          String? displayName,
          String? role,
          String? company,
          String? bio,
          String? tags,
          String? phone,
          DateTime? encounteredAt}) =>
      BleEncounter(
        deviceId: deviceId ?? this.deviceId,
        displayName: displayName ?? this.displayName,
        role: role ?? this.role,
        company: company ?? this.company,
        bio: bio ?? this.bio,
        tags: tags ?? this.tags,
        phone: phone ?? this.phone,
        encounteredAt: encounteredAt ?? this.encounteredAt,
      );
  BleEncounter copyWithCompanion(BleEncountersCompanion data) {
    return BleEncounter(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      displayName:
          data.displayName.present ? data.displayName.value : this.displayName,
      role: data.role.present ? data.role.value : this.role,
      company: data.company.present ? data.company.value : this.company,
      bio: data.bio.present ? data.bio.value : this.bio,
      tags: data.tags.present ? data.tags.value : this.tags,
      phone: data.phone.present ? data.phone.value : this.phone,
      encounteredAt: data.encounteredAt.present
          ? data.encounteredAt.value
          : this.encounteredAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BleEncounter(')
          ..write('deviceId: $deviceId, ')
          ..write('displayName: $displayName, ')
          ..write('role: $role, ')
          ..write('company: $company, ')
          ..write('bio: $bio, ')
          ..write('tags: $tags, ')
          ..write('phone: $phone, ')
          ..write('encounteredAt: $encounteredAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      deviceId, displayName, role, company, bio, tags, phone, encounteredAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BleEncounter &&
          other.deviceId == this.deviceId &&
          other.displayName == this.displayName &&
          other.role == this.role &&
          other.company == this.company &&
          other.bio == this.bio &&
          other.tags == this.tags &&
          other.phone == this.phone &&
          other.encounteredAt == this.encounteredAt);
}

class BleEncountersCompanion extends UpdateCompanion<BleEncounter> {
  final Value<String> deviceId;
  final Value<String> displayName;
  final Value<String> role;
  final Value<String> company;
  final Value<String> bio;
  final Value<String> tags;
  final Value<String> phone;
  final Value<DateTime> encounteredAt;
  final Value<int> rowid;
  const BleEncountersCompanion({
    this.deviceId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.role = const Value.absent(),
    this.company = const Value.absent(),
    this.bio = const Value.absent(),
    this.tags = const Value.absent(),
    this.phone = const Value.absent(),
    this.encounteredAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BleEncountersCompanion.insert({
    required String deviceId,
    this.displayName = const Value.absent(),
    this.role = const Value.absent(),
    this.company = const Value.absent(),
    this.bio = const Value.absent(),
    this.tags = const Value.absent(),
    this.phone = const Value.absent(),
    required DateTime encounteredAt,
    this.rowid = const Value.absent(),
  })  : deviceId = Value(deviceId),
        encounteredAt = Value(encounteredAt);
  static Insertable<BleEncounter> custom({
    Expression<String>? deviceId,
    Expression<String>? displayName,
    Expression<String>? role,
    Expression<String>? company,
    Expression<String>? bio,
    Expression<String>? tags,
    Expression<String>? phone,
    Expression<DateTime>? encounteredAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (displayName != null) 'display_name': displayName,
      if (role != null) 'role': role,
      if (company != null) 'company': company,
      if (bio != null) 'bio': bio,
      if (tags != null) 'tags': tags,
      if (phone != null) 'phone': phone,
      if (encounteredAt != null) 'encountered_at': encounteredAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BleEncountersCompanion copyWith(
      {Value<String>? deviceId,
      Value<String>? displayName,
      Value<String>? role,
      Value<String>? company,
      Value<String>? bio,
      Value<String>? tags,
      Value<String>? phone,
      Value<DateTime>? encounteredAt,
      Value<int>? rowid}) {
    return BleEncountersCompanion(
      deviceId: deviceId ?? this.deviceId,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      company: company ?? this.company,
      bio: bio ?? this.bio,
      tags: tags ?? this.tags,
      phone: phone ?? this.phone,
      encounteredAt: encounteredAt ?? this.encounteredAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (company.present) {
      map['company'] = Variable<String>(company.value);
    }
    if (bio.present) {
      map['bio'] = Variable<String>(bio.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(tags.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (encounteredAt.present) {
      map['encountered_at'] = Variable<DateTime>(encounteredAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BleEncountersCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('displayName: $displayName, ')
          ..write('role: $role, ')
          ..write('company: $company, ')
          ..write('bio: $bio, ')
          ..write('tags: $tags, ')
          ..write('phone: $phone, ')
          ..write('encounteredAt: $encounteredAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GeocodingCacheTable extends GeocodingCache
    with TableInfo<$GeocodingCacheTable, GeocodingCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GeocodingCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _queryKeyMeta =
      const VerificationMeta('queryKey');
  @override
  late final GeneratedColumn<String> queryKey = GeneratedColumn<String>(
      'query_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _displayNameMeta =
      const VerificationMeta('displayName');
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
      'display_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
      'lat', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _lonMeta = const VerificationMeta('lon');
  @override
  late final GeneratedColumn<double> lon = GeneratedColumn<double>(
      'lon', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
      'source', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _storagePolicyMeta =
      const VerificationMeta('storagePolicy');
  @override
  late final GeneratedColumn<String> storagePolicy = GeneratedColumn<String>(
      'storage_policy', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('permanent'));
  static const VerificationMeta _placeIdMeta =
      const VerificationMeta('placeId');
  @override
  late final GeneratedColumn<String> placeId = GeneratedColumn<String>(
      'place_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        queryKey,
        displayName,
        lat,
        lon,
        source,
        storagePolicy,
        placeId,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'geocoding_cache';
  @override
  VerificationContext validateIntegrity(Insertable<GeocodingCacheData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('query_key')) {
      context.handle(_queryKeyMeta,
          queryKey.isAcceptableOrUnknown(data['query_key']!, _queryKeyMeta));
    } else if (isInserting) {
      context.missing(_queryKeyMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
          _displayNameMeta,
          displayName.isAcceptableOrUnknown(
              data['display_name']!, _displayNameMeta));
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('lat')) {
      context.handle(
          _latMeta, lat.isAcceptableOrUnknown(data['lat']!, _latMeta));
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lon')) {
      context.handle(
          _lonMeta, lon.isAcceptableOrUnknown(data['lon']!, _lonMeta));
    } else if (isInserting) {
      context.missing(_lonMeta);
    }
    if (data.containsKey('source')) {
      context.handle(_sourceMeta,
          source.isAcceptableOrUnknown(data['source']!, _sourceMeta));
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('storage_policy')) {
      context.handle(
          _storagePolicyMeta,
          storagePolicy.isAcceptableOrUnknown(
              data['storage_policy']!, _storagePolicyMeta));
    }
    if (data.containsKey('place_id')) {
      context.handle(_placeIdMeta,
          placeId.isAcceptableOrUnknown(data['place_id']!, _placeIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GeocodingCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GeocodingCacheData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      queryKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}query_key'])!,
      displayName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}display_name'])!,
      lat: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}lat'])!,
      lon: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}lon'])!,
      source: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source'])!,
      storagePolicy: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}storage_policy'])!,
      placeId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}place_id'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $GeocodingCacheTable createAlias(String alias) {
    return $GeocodingCacheTable(attachedDatabase, alias);
  }
}

class GeocodingCacheData extends DataClass
    implements Insertable<GeocodingCacheData> {
  final String id;
  final String queryKey;
  final String displayName;
  final double lat;
  final double lon;
  final String source;
  final String storagePolicy;
  final String placeId;
  final int createdAt;
  const GeocodingCacheData(
      {required this.id,
      required this.queryKey,
      required this.displayName,
      required this.lat,
      required this.lon,
      required this.source,
      required this.storagePolicy,
      required this.placeId,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['query_key'] = Variable<String>(queryKey);
    map['display_name'] = Variable<String>(displayName);
    map['lat'] = Variable<double>(lat);
    map['lon'] = Variable<double>(lon);
    map['source'] = Variable<String>(source);
    map['storage_policy'] = Variable<String>(storagePolicy);
    map['place_id'] = Variable<String>(placeId);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  GeocodingCacheCompanion toCompanion(bool nullToAbsent) {
    return GeocodingCacheCompanion(
      id: Value(id),
      queryKey: Value(queryKey),
      displayName: Value(displayName),
      lat: Value(lat),
      lon: Value(lon),
      source: Value(source),
      storagePolicy: Value(storagePolicy),
      placeId: Value(placeId),
      createdAt: Value(createdAt),
    );
  }

  factory GeocodingCacheData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GeocodingCacheData(
      id: serializer.fromJson<String>(json['id']),
      queryKey: serializer.fromJson<String>(json['queryKey']),
      displayName: serializer.fromJson<String>(json['displayName']),
      lat: serializer.fromJson<double>(json['lat']),
      lon: serializer.fromJson<double>(json['lon']),
      source: serializer.fromJson<String>(json['source']),
      storagePolicy: serializer.fromJson<String>(json['storagePolicy']),
      placeId: serializer.fromJson<String>(json['placeId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'queryKey': serializer.toJson<String>(queryKey),
      'displayName': serializer.toJson<String>(displayName),
      'lat': serializer.toJson<double>(lat),
      'lon': serializer.toJson<double>(lon),
      'source': serializer.toJson<String>(source),
      'storagePolicy': serializer.toJson<String>(storagePolicy),
      'placeId': serializer.toJson<String>(placeId),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  GeocodingCacheData copyWith(
          {String? id,
          String? queryKey,
          String? displayName,
          double? lat,
          double? lon,
          String? source,
          String? storagePolicy,
          String? placeId,
          int? createdAt}) =>
      GeocodingCacheData(
        id: id ?? this.id,
        queryKey: queryKey ?? this.queryKey,
        displayName: displayName ?? this.displayName,
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
        source: source ?? this.source,
        storagePolicy: storagePolicy ?? this.storagePolicy,
        placeId: placeId ?? this.placeId,
        createdAt: createdAt ?? this.createdAt,
      );
  GeocodingCacheData copyWithCompanion(GeocodingCacheCompanion data) {
    return GeocodingCacheData(
      id: data.id.present ? data.id.value : this.id,
      queryKey: data.queryKey.present ? data.queryKey.value : this.queryKey,
      displayName:
          data.displayName.present ? data.displayName.value : this.displayName,
      lat: data.lat.present ? data.lat.value : this.lat,
      lon: data.lon.present ? data.lon.value : this.lon,
      source: data.source.present ? data.source.value : this.source,
      storagePolicy: data.storagePolicy.present
          ? data.storagePolicy.value
          : this.storagePolicy,
      placeId: data.placeId.present ? data.placeId.value : this.placeId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GeocodingCacheData(')
          ..write('id: $id, ')
          ..write('queryKey: $queryKey, ')
          ..write('displayName: $displayName, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('source: $source, ')
          ..write('storagePolicy: $storagePolicy, ')
          ..write('placeId: $placeId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, queryKey, displayName, lat, lon, source,
      storagePolicy, placeId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GeocodingCacheData &&
          other.id == this.id &&
          other.queryKey == this.queryKey &&
          other.displayName == this.displayName &&
          other.lat == this.lat &&
          other.lon == this.lon &&
          other.source == this.source &&
          other.storagePolicy == this.storagePolicy &&
          other.placeId == this.placeId &&
          other.createdAt == this.createdAt);
}

class GeocodingCacheCompanion extends UpdateCompanion<GeocodingCacheData> {
  final Value<String> id;
  final Value<String> queryKey;
  final Value<String> displayName;
  final Value<double> lat;
  final Value<double> lon;
  final Value<String> source;
  final Value<String> storagePolicy;
  final Value<String> placeId;
  final Value<int> createdAt;
  final Value<int> rowid;
  const GeocodingCacheCompanion({
    this.id = const Value.absent(),
    this.queryKey = const Value.absent(),
    this.displayName = const Value.absent(),
    this.lat = const Value.absent(),
    this.lon = const Value.absent(),
    this.source = const Value.absent(),
    this.storagePolicy = const Value.absent(),
    this.placeId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GeocodingCacheCompanion.insert({
    required String id,
    required String queryKey,
    required String displayName,
    required double lat,
    required double lon,
    required String source,
    this.storagePolicy = const Value.absent(),
    this.placeId = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        queryKey = Value(queryKey),
        displayName = Value(displayName),
        lat = Value(lat),
        lon = Value(lon),
        source = Value(source),
        createdAt = Value(createdAt);
  static Insertable<GeocodingCacheData> custom({
    Expression<String>? id,
    Expression<String>? queryKey,
    Expression<String>? displayName,
    Expression<double>? lat,
    Expression<double>? lon,
    Expression<String>? source,
    Expression<String>? storagePolicy,
    Expression<String>? placeId,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (queryKey != null) 'query_key': queryKey,
      if (displayName != null) 'display_name': displayName,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
      if (source != null) 'source': source,
      if (storagePolicy != null) 'storage_policy': storagePolicy,
      if (placeId != null) 'place_id': placeId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GeocodingCacheCompanion copyWith(
      {Value<String>? id,
      Value<String>? queryKey,
      Value<String>? displayName,
      Value<double>? lat,
      Value<double>? lon,
      Value<String>? source,
      Value<String>? storagePolicy,
      Value<String>? placeId,
      Value<int>? createdAt,
      Value<int>? rowid}) {
    return GeocodingCacheCompanion(
      id: id ?? this.id,
      queryKey: queryKey ?? this.queryKey,
      displayName: displayName ?? this.displayName,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      source: source ?? this.source,
      storagePolicy: storagePolicy ?? this.storagePolicy,
      placeId: placeId ?? this.placeId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (queryKey.present) {
      map['query_key'] = Variable<String>(queryKey.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lon.present) {
      map['lon'] = Variable<double>(lon.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (storagePolicy.present) {
      map['storage_policy'] = Variable<String>(storagePolicy.value);
    }
    if (placeId.present) {
      map['place_id'] = Variable<String>(placeId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GeocodingCacheCompanion(')
          ..write('id: $id, ')
          ..write('queryKey: $queryKey, ')
          ..write('displayName: $displayName, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('source: $source, ')
          ..write('storagePolicy: $storagePolicy, ')
          ..write('placeId: $placeId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ShoppingListItemsTable extends ShoppingListItems
    with TableInfo<$ShoppingListItemsTable, ShoppingListItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShoppingListItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _environmentIdMeta =
      const VerificationMeta('environmentId');
  @override
  late final GeneratedColumn<String> environmentId = GeneratedColumn<String>(
      'environment_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 200),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _isCheckedMeta =
      const VerificationMeta('isChecked');
  @override
  late final GeneratedColumn<bool> isChecked = GeneratedColumn<bool>(
      'is_checked', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_checked" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, environmentId, name, isChecked, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shopping_list_items';
  @override
  VerificationContext validateIntegrity(Insertable<ShoppingListItem> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('environment_id')) {
      context.handle(
          _environmentIdMeta,
          environmentId.isAcceptableOrUnknown(
              data['environment_id']!, _environmentIdMeta));
    } else if (isInserting) {
      context.missing(_environmentIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('is_checked')) {
      context.handle(_isCheckedMeta,
          isChecked.isAcceptableOrUnknown(data['is_checked']!, _isCheckedMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ShoppingListItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShoppingListItem(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      environmentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}environment_id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      isChecked: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_checked'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $ShoppingListItemsTable createAlias(String alias) {
    return $ShoppingListItemsTable(attachedDatabase, alias);
  }
}

class ShoppingListItem extends DataClass
    implements Insertable<ShoppingListItem> {
  final String id;
  final String environmentId;
  final String name;
  final bool isChecked;
  final DateTime createdAt;
  const ShoppingListItem(
      {required this.id,
      required this.environmentId,
      required this.name,
      required this.isChecked,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['environment_id'] = Variable<String>(environmentId);
    map['name'] = Variable<String>(name);
    map['is_checked'] = Variable<bool>(isChecked);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ShoppingListItemsCompanion toCompanion(bool nullToAbsent) {
    return ShoppingListItemsCompanion(
      id: Value(id),
      environmentId: Value(environmentId),
      name: Value(name),
      isChecked: Value(isChecked),
      createdAt: Value(createdAt),
    );
  }

  factory ShoppingListItem.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShoppingListItem(
      id: serializer.fromJson<String>(json['id']),
      environmentId: serializer.fromJson<String>(json['environmentId']),
      name: serializer.fromJson<String>(json['name']),
      isChecked: serializer.fromJson<bool>(json['isChecked']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'environmentId': serializer.toJson<String>(environmentId),
      'name': serializer.toJson<String>(name),
      'isChecked': serializer.toJson<bool>(isChecked),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ShoppingListItem copyWith(
          {String? id,
          String? environmentId,
          String? name,
          bool? isChecked,
          DateTime? createdAt}) =>
      ShoppingListItem(
        id: id ?? this.id,
        environmentId: environmentId ?? this.environmentId,
        name: name ?? this.name,
        isChecked: isChecked ?? this.isChecked,
        createdAt: createdAt ?? this.createdAt,
      );
  ShoppingListItem copyWithCompanion(ShoppingListItemsCompanion data) {
    return ShoppingListItem(
      id: data.id.present ? data.id.value : this.id,
      environmentId: data.environmentId.present
          ? data.environmentId.value
          : this.environmentId,
      name: data.name.present ? data.name.value : this.name,
      isChecked: data.isChecked.present ? data.isChecked.value : this.isChecked,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShoppingListItem(')
          ..write('id: $id, ')
          ..write('environmentId: $environmentId, ')
          ..write('name: $name, ')
          ..write('isChecked: $isChecked, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, environmentId, name, isChecked, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShoppingListItem &&
          other.id == this.id &&
          other.environmentId == this.environmentId &&
          other.name == this.name &&
          other.isChecked == this.isChecked &&
          other.createdAt == this.createdAt);
}

class ShoppingListItemsCompanion extends UpdateCompanion<ShoppingListItem> {
  final Value<String> id;
  final Value<String> environmentId;
  final Value<String> name;
  final Value<bool> isChecked;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ShoppingListItemsCompanion({
    this.id = const Value.absent(),
    this.environmentId = const Value.absent(),
    this.name = const Value.absent(),
    this.isChecked = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ShoppingListItemsCompanion.insert({
    required String id,
    required String environmentId,
    required String name,
    this.isChecked = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        environmentId = Value(environmentId),
        name = Value(name),
        createdAt = Value(createdAt);
  static Insertable<ShoppingListItem> custom({
    Expression<String>? id,
    Expression<String>? environmentId,
    Expression<String>? name,
    Expression<bool>? isChecked,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (environmentId != null) 'environment_id': environmentId,
      if (name != null) 'name': name,
      if (isChecked != null) 'is_checked': isChecked,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ShoppingListItemsCompanion copyWith(
      {Value<String>? id,
      Value<String>? environmentId,
      Value<String>? name,
      Value<bool>? isChecked,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return ShoppingListItemsCompanion(
      id: id ?? this.id,
      environmentId: environmentId ?? this.environmentId,
      name: name ?? this.name,
      isChecked: isChecked ?? this.isChecked,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (environmentId.present) {
      map['environment_id'] = Variable<String>(environmentId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (isChecked.present) {
      map['is_checked'] = Variable<bool>(isChecked.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShoppingListItemsCompanion(')
          ..write('id: $id, ')
          ..write('environmentId: $environmentId, ')
          ..write('name: $name, ')
          ..write('isChecked: $isChecked, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ScheduledRemindersTable extends ScheduledReminders
    with TableInfo<$ScheduledRemindersTable, ScheduledReminder> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScheduledRemindersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 200),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _scheduledAtMeta =
      const VerificationMeta('scheduledAt');
  @override
  late final GeneratedColumn<DateTime> scheduledAt = GeneratedColumn<DateTime>(
      'scheduled_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _repeatRuleMeta =
      const VerificationMeta('repeatRule');
  @override
  late final GeneratedColumn<String> repeatRule = GeneratedColumn<String>(
      'repeat_rule', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('none'));
  static const VerificationMeta _repeatDaysOfWeekMeta =
      const VerificationMeta('repeatDaysOfWeek');
  @override
  late final GeneratedColumn<String> repeatDaysOfWeek = GeneratedColumn<String>(
      'repeat_days_of_week', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _alertModeMeta =
      const VerificationMeta('alertMode');
  @override
  late final GeneratedColumn<String> alertMode = GeneratedColumn<String>(
      'alert_mode', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('notification'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        title,
        content,
        scheduledAt,
        repeatRule,
        repeatDaysOfWeek,
        isActive,
        alertMode,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'scheduled_reminders';
  @override
  VerificationContext validateIntegrity(Insertable<ScheduledReminder> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    }
    if (data.containsKey('scheduled_at')) {
      context.handle(
          _scheduledAtMeta,
          scheduledAt.isAcceptableOrUnknown(
              data['scheduled_at']!, _scheduledAtMeta));
    } else if (isInserting) {
      context.missing(_scheduledAtMeta);
    }
    if (data.containsKey('repeat_rule')) {
      context.handle(
          _repeatRuleMeta,
          repeatRule.isAcceptableOrUnknown(
              data['repeat_rule']!, _repeatRuleMeta));
    }
    if (data.containsKey('repeat_days_of_week')) {
      context.handle(
          _repeatDaysOfWeekMeta,
          repeatDaysOfWeek.isAcceptableOrUnknown(
              data['repeat_days_of_week']!, _repeatDaysOfWeekMeta));
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    if (data.containsKey('alert_mode')) {
      context.handle(_alertModeMeta,
          alertMode.isAcceptableOrUnknown(data['alert_mode']!, _alertModeMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ScheduledReminder map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScheduledReminder(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      scheduledAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}scheduled_at'])!,
      repeatRule: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}repeat_rule'])!,
      repeatDaysOfWeek: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}repeat_days_of_week'])!,
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      alertMode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}alert_mode'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $ScheduledRemindersTable createAlias(String alias) {
    return $ScheduledRemindersTable(attachedDatabase, alias);
  }
}

class ScheduledReminder extends DataClass
    implements Insertable<ScheduledReminder> {
  final String id;
  final String title;
  final String content;
  final DateTime scheduledAt;
  final String repeatRule;
  final String repeatDaysOfWeek;
  final bool isActive;
  final String alertMode;
  final DateTime createdAt;
  const ScheduledReminder(
      {required this.id,
      required this.title,
      required this.content,
      required this.scheduledAt,
      required this.repeatRule,
      required this.repeatDaysOfWeek,
      required this.isActive,
      required this.alertMode,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['content'] = Variable<String>(content);
    map['scheduled_at'] = Variable<DateTime>(scheduledAt);
    map['repeat_rule'] = Variable<String>(repeatRule);
    map['repeat_days_of_week'] = Variable<String>(repeatDaysOfWeek);
    map['is_active'] = Variable<bool>(isActive);
    map['alert_mode'] = Variable<String>(alertMode);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ScheduledRemindersCompanion toCompanion(bool nullToAbsent) {
    return ScheduledRemindersCompanion(
      id: Value(id),
      title: Value(title),
      content: Value(content),
      scheduledAt: Value(scheduledAt),
      repeatRule: Value(repeatRule),
      repeatDaysOfWeek: Value(repeatDaysOfWeek),
      isActive: Value(isActive),
      alertMode: Value(alertMode),
      createdAt: Value(createdAt),
    );
  }

  factory ScheduledReminder.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScheduledReminder(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      content: serializer.fromJson<String>(json['content']),
      scheduledAt: serializer.fromJson<DateTime>(json['scheduledAt']),
      repeatRule: serializer.fromJson<String>(json['repeatRule']),
      repeatDaysOfWeek: serializer.fromJson<String>(json['repeatDaysOfWeek']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      alertMode: serializer.fromJson<String>(json['alertMode']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'content': serializer.toJson<String>(content),
      'scheduledAt': serializer.toJson<DateTime>(scheduledAt),
      'repeatRule': serializer.toJson<String>(repeatRule),
      'repeatDaysOfWeek': serializer.toJson<String>(repeatDaysOfWeek),
      'isActive': serializer.toJson<bool>(isActive),
      'alertMode': serializer.toJson<String>(alertMode),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ScheduledReminder copyWith(
          {String? id,
          String? title,
          String? content,
          DateTime? scheduledAt,
          String? repeatRule,
          String? repeatDaysOfWeek,
          bool? isActive,
          String? alertMode,
          DateTime? createdAt}) =>
      ScheduledReminder(
        id: id ?? this.id,
        title: title ?? this.title,
        content: content ?? this.content,
        scheduledAt: scheduledAt ?? this.scheduledAt,
        repeatRule: repeatRule ?? this.repeatRule,
        repeatDaysOfWeek: repeatDaysOfWeek ?? this.repeatDaysOfWeek,
        isActive: isActive ?? this.isActive,
        alertMode: alertMode ?? this.alertMode,
        createdAt: createdAt ?? this.createdAt,
      );
  ScheduledReminder copyWithCompanion(ScheduledRemindersCompanion data) {
    return ScheduledReminder(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      content: data.content.present ? data.content.value : this.content,
      scheduledAt:
          data.scheduledAt.present ? data.scheduledAt.value : this.scheduledAt,
      repeatRule:
          data.repeatRule.present ? data.repeatRule.value : this.repeatRule,
      repeatDaysOfWeek: data.repeatDaysOfWeek.present
          ? data.repeatDaysOfWeek.value
          : this.repeatDaysOfWeek,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      alertMode: data.alertMode.present ? data.alertMode.value : this.alertMode,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScheduledReminder(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('repeatRule: $repeatRule, ')
          ..write('repeatDaysOfWeek: $repeatDaysOfWeek, ')
          ..write('isActive: $isActive, ')
          ..write('alertMode: $alertMode, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, title, content, scheduledAt, repeatRule,
      repeatDaysOfWeek, isActive, alertMode, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduledReminder &&
          other.id == this.id &&
          other.title == this.title &&
          other.content == this.content &&
          other.scheduledAt == this.scheduledAt &&
          other.repeatRule == this.repeatRule &&
          other.repeatDaysOfWeek == this.repeatDaysOfWeek &&
          other.isActive == this.isActive &&
          other.alertMode == this.alertMode &&
          other.createdAt == this.createdAt);
}

class ScheduledRemindersCompanion extends UpdateCompanion<ScheduledReminder> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> content;
  final Value<DateTime> scheduledAt;
  final Value<String> repeatRule;
  final Value<String> repeatDaysOfWeek;
  final Value<bool> isActive;
  final Value<String> alertMode;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ScheduledRemindersCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.content = const Value.absent(),
    this.scheduledAt = const Value.absent(),
    this.repeatRule = const Value.absent(),
    this.repeatDaysOfWeek = const Value.absent(),
    this.isActive = const Value.absent(),
    this.alertMode = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ScheduledRemindersCompanion.insert({
    required String id,
    required String title,
    this.content = const Value.absent(),
    required DateTime scheduledAt,
    this.repeatRule = const Value.absent(),
    this.repeatDaysOfWeek = const Value.absent(),
    this.isActive = const Value.absent(),
    this.alertMode = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        title = Value(title),
        scheduledAt = Value(scheduledAt),
        createdAt = Value(createdAt);
  static Insertable<ScheduledReminder> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? content,
    Expression<DateTime>? scheduledAt,
    Expression<String>? repeatRule,
    Expression<String>? repeatDaysOfWeek,
    Expression<bool>? isActive,
    Expression<String>? alertMode,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (content != null) 'content': content,
      if (scheduledAt != null) 'scheduled_at': scheduledAt,
      if (repeatRule != null) 'repeat_rule': repeatRule,
      if (repeatDaysOfWeek != null) 'repeat_days_of_week': repeatDaysOfWeek,
      if (isActive != null) 'is_active': isActive,
      if (alertMode != null) 'alert_mode': alertMode,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ScheduledRemindersCompanion copyWith(
      {Value<String>? id,
      Value<String>? title,
      Value<String>? content,
      Value<DateTime>? scheduledAt,
      Value<String>? repeatRule,
      Value<String>? repeatDaysOfWeek,
      Value<bool>? isActive,
      Value<String>? alertMode,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return ScheduledRemindersCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      repeatRule: repeatRule ?? this.repeatRule,
      repeatDaysOfWeek: repeatDaysOfWeek ?? this.repeatDaysOfWeek,
      isActive: isActive ?? this.isActive,
      alertMode: alertMode ?? this.alertMode,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (scheduledAt.present) {
      map['scheduled_at'] = Variable<DateTime>(scheduledAt.value);
    }
    if (repeatRule.present) {
      map['repeat_rule'] = Variable<String>(repeatRule.value);
    }
    if (repeatDaysOfWeek.present) {
      map['repeat_days_of_week'] = Variable<String>(repeatDaysOfWeek.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (alertMode.present) {
      map['alert_mode'] = Variable<String>(alertMode.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScheduledRemindersCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('repeatRule: $repeatRule, ')
          ..write('repeatDaysOfWeek: $repeatDaysOfWeek, ')
          ..write('isActive: $isActive, ')
          ..write('alertMode: $alertMode, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActivityLogEntriesTable extends ActivityLogEntries
    with TableInfo<$ActivityLogEntriesTable, ActivityLogEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActivityLogEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _subtitleMeta =
      const VerificationMeta('subtitle');
  @override
  late final GeneratedColumn<String> subtitle = GeneratedColumn<String>(
      'subtitle', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _environmentIdMeta =
      const VerificationMeta('environmentId');
  @override
  late final GeneratedColumn<String> environmentId = GeneratedColumn<String>(
      'environment_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, type, title, subtitle, environmentId, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'activity_log_entries';
  @override
  VerificationContext validateIntegrity(Insertable<ActivityLogEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('subtitle')) {
      context.handle(_subtitleMeta,
          subtitle.isAcceptableOrUnknown(data['subtitle']!, _subtitleMeta));
    }
    if (data.containsKey('environment_id')) {
      context.handle(
          _environmentIdMeta,
          environmentId.isAcceptableOrUnknown(
              data['environment_id']!, _environmentIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ActivityLogEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActivityLogEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      subtitle: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}subtitle'])!,
      environmentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}environment_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $ActivityLogEntriesTable createAlias(String alias) {
    return $ActivityLogEntriesTable(attachedDatabase, alias);
  }
}

class ActivityLogEntry extends DataClass
    implements Insertable<ActivityLogEntry> {
  final String id;
  final String type;
  final String title;
  final String subtitle;
  final String? environmentId;
  final DateTime createdAt;
  const ActivityLogEntry(
      {required this.id,
      required this.type,
      required this.title,
      required this.subtitle,
      this.environmentId,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['type'] = Variable<String>(type);
    map['title'] = Variable<String>(title);
    map['subtitle'] = Variable<String>(subtitle);
    if (!nullToAbsent || environmentId != null) {
      map['environment_id'] = Variable<String>(environmentId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ActivityLogEntriesCompanion toCompanion(bool nullToAbsent) {
    return ActivityLogEntriesCompanion(
      id: Value(id),
      type: Value(type),
      title: Value(title),
      subtitle: Value(subtitle),
      environmentId: environmentId == null && nullToAbsent
          ? const Value.absent()
          : Value(environmentId),
      createdAt: Value(createdAt),
    );
  }

  factory ActivityLogEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActivityLogEntry(
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      title: serializer.fromJson<String>(json['title']),
      subtitle: serializer.fromJson<String>(json['subtitle']),
      environmentId: serializer.fromJson<String?>(json['environmentId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<String>(type),
      'title': serializer.toJson<String>(title),
      'subtitle': serializer.toJson<String>(subtitle),
      'environmentId': serializer.toJson<String?>(environmentId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ActivityLogEntry copyWith(
          {String? id,
          String? type,
          String? title,
          String? subtitle,
          Value<String?> environmentId = const Value.absent(),
          DateTime? createdAt}) =>
      ActivityLogEntry(
        id: id ?? this.id,
        type: type ?? this.type,
        title: title ?? this.title,
        subtitle: subtitle ?? this.subtitle,
        environmentId:
            environmentId.present ? environmentId.value : this.environmentId,
        createdAt: createdAt ?? this.createdAt,
      );
  ActivityLogEntry copyWithCompanion(ActivityLogEntriesCompanion data) {
    return ActivityLogEntry(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      title: data.title.present ? data.title.value : this.title,
      subtitle: data.subtitle.present ? data.subtitle.value : this.subtitle,
      environmentId: data.environmentId.present
          ? data.environmentId.value
          : this.environmentId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActivityLogEntry(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('subtitle: $subtitle, ')
          ..write('environmentId: $environmentId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, type, title, subtitle, environmentId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActivityLogEntry &&
          other.id == this.id &&
          other.type == this.type &&
          other.title == this.title &&
          other.subtitle == this.subtitle &&
          other.environmentId == this.environmentId &&
          other.createdAt == this.createdAt);
}

class ActivityLogEntriesCompanion extends UpdateCompanion<ActivityLogEntry> {
  final Value<String> id;
  final Value<String> type;
  final Value<String> title;
  final Value<String> subtitle;
  final Value<String?> environmentId;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ActivityLogEntriesCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.title = const Value.absent(),
    this.subtitle = const Value.absent(),
    this.environmentId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActivityLogEntriesCompanion.insert({
    required String id,
    required String type,
    required String title,
    this.subtitle = const Value.absent(),
    this.environmentId = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        type = Value(type),
        title = Value(title),
        createdAt = Value(createdAt);
  static Insertable<ActivityLogEntry> custom({
    Expression<String>? id,
    Expression<String>? type,
    Expression<String>? title,
    Expression<String>? subtitle,
    Expression<String>? environmentId,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (title != null) 'title': title,
      if (subtitle != null) 'subtitle': subtitle,
      if (environmentId != null) 'environment_id': environmentId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActivityLogEntriesCompanion copyWith(
      {Value<String>? id,
      Value<String>? type,
      Value<String>? title,
      Value<String>? subtitle,
      Value<String?>? environmentId,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return ActivityLogEntriesCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      environmentId: environmentId ?? this.environmentId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (subtitle.present) {
      map['subtitle'] = Variable<String>(subtitle.value);
    }
    if (environmentId.present) {
      map['environment_id'] = Variable<String>(environmentId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActivityLogEntriesCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('subtitle: $subtitle, ')
          ..write('environmentId: $environmentId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WeatherCacheEntriesTable extends WeatherCacheEntries
    with TableInfo<$WeatherCacheEntriesTable, WeatherCacheEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WeatherCacheEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
      'lat', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _lonMeta = const VerificationMeta('lon');
  @override
  late final GeneratedColumn<double> lon = GeneratedColumn<double>(
      'lon', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _tempCelsiusMeta =
      const VerificationMeta('tempCelsius');
  @override
  late final GeneratedColumn<double> tempCelsius = GeneratedColumn<double>(
      'temp_celsius', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _conditionMeta =
      const VerificationMeta('condition');
  @override
  late final GeneratedColumn<String> condition = GeneratedColumn<String>(
      'condition', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _iconCodeMeta =
      const VerificationMeta('iconCode');
  @override
  late final GeneratedColumn<String> iconCode = GeneratedColumn<String>(
      'icon_code', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _humidityMeta =
      const VerificationMeta('humidity');
  @override
  late final GeneratedColumn<int> humidity = GeneratedColumn<int>(
      'humidity', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _cityNameMeta =
      const VerificationMeta('cityName');
  @override
  late final GeneratedColumn<String> cityName = GeneratedColumn<String>(
      'city_name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _fetchedAtMeta =
      const VerificationMeta('fetchedAt');
  @override
  late final GeneratedColumn<int> fetchedAt = GeneratedColumn<int>(
      'fetched_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _expiresAtMeta =
      const VerificationMeta('expiresAt');
  @override
  late final GeneratedColumn<int> expiresAt = GeneratedColumn<int>(
      'expires_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        lat,
        lon,
        tempCelsius,
        condition,
        description,
        iconCode,
        humidity,
        cityName,
        fetchedAt,
        expiresAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'weather_cache_entries';
  @override
  VerificationContext validateIntegrity(Insertable<WeatherCacheEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('lat')) {
      context.handle(
          _latMeta, lat.isAcceptableOrUnknown(data['lat']!, _latMeta));
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lon')) {
      context.handle(
          _lonMeta, lon.isAcceptableOrUnknown(data['lon']!, _lonMeta));
    } else if (isInserting) {
      context.missing(_lonMeta);
    }
    if (data.containsKey('temp_celsius')) {
      context.handle(
          _tempCelsiusMeta,
          tempCelsius.isAcceptableOrUnknown(
              data['temp_celsius']!, _tempCelsiusMeta));
    } else if (isInserting) {
      context.missing(_tempCelsiusMeta);
    }
    if (data.containsKey('condition')) {
      context.handle(_conditionMeta,
          condition.isAcceptableOrUnknown(data['condition']!, _conditionMeta));
    } else if (isInserting) {
      context.missing(_conditionMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('icon_code')) {
      context.handle(_iconCodeMeta,
          iconCode.isAcceptableOrUnknown(data['icon_code']!, _iconCodeMeta));
    } else if (isInserting) {
      context.missing(_iconCodeMeta);
    }
    if (data.containsKey('humidity')) {
      context.handle(_humidityMeta,
          humidity.isAcceptableOrUnknown(data['humidity']!, _humidityMeta));
    }
    if (data.containsKey('city_name')) {
      context.handle(_cityNameMeta,
          cityName.isAcceptableOrUnknown(data['city_name']!, _cityNameMeta));
    }
    if (data.containsKey('fetched_at')) {
      context.handle(_fetchedAtMeta,
          fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta));
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    if (data.containsKey('expires_at')) {
      context.handle(_expiresAtMeta,
          expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta));
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WeatherCacheEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WeatherCacheEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      lat: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}lat'])!,
      lon: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}lon'])!,
      tempCelsius: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}temp_celsius'])!,
      condition: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}condition'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      iconCode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}icon_code'])!,
      humidity: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}humidity'])!,
      cityName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}city_name'])!,
      fetchedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}fetched_at'])!,
      expiresAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}expires_at'])!,
    );
  }

  @override
  $WeatherCacheEntriesTable createAlias(String alias) {
    return $WeatherCacheEntriesTable(attachedDatabase, alias);
  }
}

class WeatherCacheEntry extends DataClass
    implements Insertable<WeatherCacheEntry> {
  final String id;
  final double lat;
  final double lon;
  final double tempCelsius;
  final String condition;
  final String description;
  final String iconCode;
  final int humidity;
  final String cityName;
  final int fetchedAt;
  final int expiresAt;
  const WeatherCacheEntry(
      {required this.id,
      required this.lat,
      required this.lon,
      required this.tempCelsius,
      required this.condition,
      required this.description,
      required this.iconCode,
      required this.humidity,
      required this.cityName,
      required this.fetchedAt,
      required this.expiresAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['lat'] = Variable<double>(lat);
    map['lon'] = Variable<double>(lon);
    map['temp_celsius'] = Variable<double>(tempCelsius);
    map['condition'] = Variable<String>(condition);
    map['description'] = Variable<String>(description);
    map['icon_code'] = Variable<String>(iconCode);
    map['humidity'] = Variable<int>(humidity);
    map['city_name'] = Variable<String>(cityName);
    map['fetched_at'] = Variable<int>(fetchedAt);
    map['expires_at'] = Variable<int>(expiresAt);
    return map;
  }

  WeatherCacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return WeatherCacheEntriesCompanion(
      id: Value(id),
      lat: Value(lat),
      lon: Value(lon),
      tempCelsius: Value(tempCelsius),
      condition: Value(condition),
      description: Value(description),
      iconCode: Value(iconCode),
      humidity: Value(humidity),
      cityName: Value(cityName),
      fetchedAt: Value(fetchedAt),
      expiresAt: Value(expiresAt),
    );
  }

  factory WeatherCacheEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WeatherCacheEntry(
      id: serializer.fromJson<String>(json['id']),
      lat: serializer.fromJson<double>(json['lat']),
      lon: serializer.fromJson<double>(json['lon']),
      tempCelsius: serializer.fromJson<double>(json['tempCelsius']),
      condition: serializer.fromJson<String>(json['condition']),
      description: serializer.fromJson<String>(json['description']),
      iconCode: serializer.fromJson<String>(json['iconCode']),
      humidity: serializer.fromJson<int>(json['humidity']),
      cityName: serializer.fromJson<String>(json['cityName']),
      fetchedAt: serializer.fromJson<int>(json['fetchedAt']),
      expiresAt: serializer.fromJson<int>(json['expiresAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'lat': serializer.toJson<double>(lat),
      'lon': serializer.toJson<double>(lon),
      'tempCelsius': serializer.toJson<double>(tempCelsius),
      'condition': serializer.toJson<String>(condition),
      'description': serializer.toJson<String>(description),
      'iconCode': serializer.toJson<String>(iconCode),
      'humidity': serializer.toJson<int>(humidity),
      'cityName': serializer.toJson<String>(cityName),
      'fetchedAt': serializer.toJson<int>(fetchedAt),
      'expiresAt': serializer.toJson<int>(expiresAt),
    };
  }

  WeatherCacheEntry copyWith(
          {String? id,
          double? lat,
          double? lon,
          double? tempCelsius,
          String? condition,
          String? description,
          String? iconCode,
          int? humidity,
          String? cityName,
          int? fetchedAt,
          int? expiresAt}) =>
      WeatherCacheEntry(
        id: id ?? this.id,
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
        tempCelsius: tempCelsius ?? this.tempCelsius,
        condition: condition ?? this.condition,
        description: description ?? this.description,
        iconCode: iconCode ?? this.iconCode,
        humidity: humidity ?? this.humidity,
        cityName: cityName ?? this.cityName,
        fetchedAt: fetchedAt ?? this.fetchedAt,
        expiresAt: expiresAt ?? this.expiresAt,
      );
  WeatherCacheEntry copyWithCompanion(WeatherCacheEntriesCompanion data) {
    return WeatherCacheEntry(
      id: data.id.present ? data.id.value : this.id,
      lat: data.lat.present ? data.lat.value : this.lat,
      lon: data.lon.present ? data.lon.value : this.lon,
      tempCelsius:
          data.tempCelsius.present ? data.tempCelsius.value : this.tempCelsius,
      condition: data.condition.present ? data.condition.value : this.condition,
      description:
          data.description.present ? data.description.value : this.description,
      iconCode: data.iconCode.present ? data.iconCode.value : this.iconCode,
      humidity: data.humidity.present ? data.humidity.value : this.humidity,
      cityName: data.cityName.present ? data.cityName.value : this.cityName,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WeatherCacheEntry(')
          ..write('id: $id, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('tempCelsius: $tempCelsius, ')
          ..write('condition: $condition, ')
          ..write('description: $description, ')
          ..write('iconCode: $iconCode, ')
          ..write('humidity: $humidity, ')
          ..write('cityName: $cityName, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('expiresAt: $expiresAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, lat, lon, tempCelsius, condition,
      description, iconCode, humidity, cityName, fetchedAt, expiresAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WeatherCacheEntry &&
          other.id == this.id &&
          other.lat == this.lat &&
          other.lon == this.lon &&
          other.tempCelsius == this.tempCelsius &&
          other.condition == this.condition &&
          other.description == this.description &&
          other.iconCode == this.iconCode &&
          other.humidity == this.humidity &&
          other.cityName == this.cityName &&
          other.fetchedAt == this.fetchedAt &&
          other.expiresAt == this.expiresAt);
}

class WeatherCacheEntriesCompanion extends UpdateCompanion<WeatherCacheEntry> {
  final Value<String> id;
  final Value<double> lat;
  final Value<double> lon;
  final Value<double> tempCelsius;
  final Value<String> condition;
  final Value<String> description;
  final Value<String> iconCode;
  final Value<int> humidity;
  final Value<String> cityName;
  final Value<int> fetchedAt;
  final Value<int> expiresAt;
  final Value<int> rowid;
  const WeatherCacheEntriesCompanion({
    this.id = const Value.absent(),
    this.lat = const Value.absent(),
    this.lon = const Value.absent(),
    this.tempCelsius = const Value.absent(),
    this.condition = const Value.absent(),
    this.description = const Value.absent(),
    this.iconCode = const Value.absent(),
    this.humidity = const Value.absent(),
    this.cityName = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WeatherCacheEntriesCompanion.insert({
    required String id,
    required double lat,
    required double lon,
    required double tempCelsius,
    required String condition,
    required String description,
    required String iconCode,
    this.humidity = const Value.absent(),
    this.cityName = const Value.absent(),
    required int fetchedAt,
    required int expiresAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        lat = Value(lat),
        lon = Value(lon),
        tempCelsius = Value(tempCelsius),
        condition = Value(condition),
        description = Value(description),
        iconCode = Value(iconCode),
        fetchedAt = Value(fetchedAt),
        expiresAt = Value(expiresAt);
  static Insertable<WeatherCacheEntry> custom({
    Expression<String>? id,
    Expression<double>? lat,
    Expression<double>? lon,
    Expression<double>? tempCelsius,
    Expression<String>? condition,
    Expression<String>? description,
    Expression<String>? iconCode,
    Expression<int>? humidity,
    Expression<String>? cityName,
    Expression<int>? fetchedAt,
    Expression<int>? expiresAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
      if (tempCelsius != null) 'temp_celsius': tempCelsius,
      if (condition != null) 'condition': condition,
      if (description != null) 'description': description,
      if (iconCode != null) 'icon_code': iconCode,
      if (humidity != null) 'humidity': humidity,
      if (cityName != null) 'city_name': cityName,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WeatherCacheEntriesCompanion copyWith(
      {Value<String>? id,
      Value<double>? lat,
      Value<double>? lon,
      Value<double>? tempCelsius,
      Value<String>? condition,
      Value<String>? description,
      Value<String>? iconCode,
      Value<int>? humidity,
      Value<String>? cityName,
      Value<int>? fetchedAt,
      Value<int>? expiresAt,
      Value<int>? rowid}) {
    return WeatherCacheEntriesCompanion(
      id: id ?? this.id,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      tempCelsius: tempCelsius ?? this.tempCelsius,
      condition: condition ?? this.condition,
      description: description ?? this.description,
      iconCode: iconCode ?? this.iconCode,
      humidity: humidity ?? this.humidity,
      cityName: cityName ?? this.cityName,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lon.present) {
      map['lon'] = Variable<double>(lon.value);
    }
    if (tempCelsius.present) {
      map['temp_celsius'] = Variable<double>(tempCelsius.value);
    }
    if (condition.present) {
      map['condition'] = Variable<String>(condition.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (iconCode.present) {
      map['icon_code'] = Variable<String>(iconCode.value);
    }
    if (humidity.present) {
      map['humidity'] = Variable<int>(humidity.value);
    }
    if (cityName.present) {
      map['city_name'] = Variable<String>(cityName.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<int>(fetchedAt.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<int>(expiresAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WeatherCacheEntriesCompanion(')
          ..write('id: $id, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('tempCelsius: $tempCelsius, ')
          ..write('condition: $condition, ')
          ..write('description: $description, ')
          ..write('iconCode: $iconCode, ')
          ..write('humidity: $humidity, ')
          ..write('cityName: $cityName, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WeatherForecastCacheTable extends WeatherForecastCache
    with TableInfo<$WeatherForecastCacheTable, WeatherForecastCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WeatherForecastCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _forecastJsonMeta =
      const VerificationMeta('forecastJson');
  @override
  late final GeneratedColumn<String> forecastJson = GeneratedColumn<String>(
      'forecast_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _fetchedAtMeta =
      const VerificationMeta('fetchedAt');
  @override
  late final GeneratedColumn<int> fetchedAt = GeneratedColumn<int>(
      'fetched_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _expiresAtMeta =
      const VerificationMeta('expiresAt');
  @override
  late final GeneratedColumn<int> expiresAt = GeneratedColumn<int>(
      'expires_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, forecastJson, fetchedAt, expiresAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'weather_forecast_cache';
  @override
  VerificationContext validateIntegrity(
      Insertable<WeatherForecastCacheData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('forecast_json')) {
      context.handle(
          _forecastJsonMeta,
          forecastJson.isAcceptableOrUnknown(
              data['forecast_json']!, _forecastJsonMeta));
    } else if (isInserting) {
      context.missing(_forecastJsonMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(_fetchedAtMeta,
          fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta));
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    if (data.containsKey('expires_at')) {
      context.handle(_expiresAtMeta,
          expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta));
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WeatherForecastCacheData map(Map<String, dynamic> data,
      {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WeatherForecastCacheData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      forecastJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}forecast_json'])!,
      fetchedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}fetched_at'])!,
      expiresAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}expires_at'])!,
    );
  }

  @override
  $WeatherForecastCacheTable createAlias(String alias) {
    return $WeatherForecastCacheTable(attachedDatabase, alias);
  }
}

class WeatherForecastCacheData extends DataClass
    implements Insertable<WeatherForecastCacheData> {
  final String id;
  final String forecastJson;
  final int fetchedAt;
  final int expiresAt;
  const WeatherForecastCacheData(
      {required this.id,
      required this.forecastJson,
      required this.fetchedAt,
      required this.expiresAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['forecast_json'] = Variable<String>(forecastJson);
    map['fetched_at'] = Variable<int>(fetchedAt);
    map['expires_at'] = Variable<int>(expiresAt);
    return map;
  }

  WeatherForecastCacheCompanion toCompanion(bool nullToAbsent) {
    return WeatherForecastCacheCompanion(
      id: Value(id),
      forecastJson: Value(forecastJson),
      fetchedAt: Value(fetchedAt),
      expiresAt: Value(expiresAt),
    );
  }

  factory WeatherForecastCacheData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WeatherForecastCacheData(
      id: serializer.fromJson<String>(json['id']),
      forecastJson: serializer.fromJson<String>(json['forecastJson']),
      fetchedAt: serializer.fromJson<int>(json['fetchedAt']),
      expiresAt: serializer.fromJson<int>(json['expiresAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'forecastJson': serializer.toJson<String>(forecastJson),
      'fetchedAt': serializer.toJson<int>(fetchedAt),
      'expiresAt': serializer.toJson<int>(expiresAt),
    };
  }

  WeatherForecastCacheData copyWith(
          {String? id, String? forecastJson, int? fetchedAt, int? expiresAt}) =>
      WeatherForecastCacheData(
        id: id ?? this.id,
        forecastJson: forecastJson ?? this.forecastJson,
        fetchedAt: fetchedAt ?? this.fetchedAt,
        expiresAt: expiresAt ?? this.expiresAt,
      );
  WeatherForecastCacheData copyWithCompanion(
      WeatherForecastCacheCompanion data) {
    return WeatherForecastCacheData(
      id: data.id.present ? data.id.value : this.id,
      forecastJson: data.forecastJson.present
          ? data.forecastJson.value
          : this.forecastJson,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WeatherForecastCacheData(')
          ..write('id: $id, ')
          ..write('forecastJson: $forecastJson, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('expiresAt: $expiresAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, forecastJson, fetchedAt, expiresAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WeatherForecastCacheData &&
          other.id == this.id &&
          other.forecastJson == this.forecastJson &&
          other.fetchedAt == this.fetchedAt &&
          other.expiresAt == this.expiresAt);
}

class WeatherForecastCacheCompanion
    extends UpdateCompanion<WeatherForecastCacheData> {
  final Value<String> id;
  final Value<String> forecastJson;
  final Value<int> fetchedAt;
  final Value<int> expiresAt;
  final Value<int> rowid;
  const WeatherForecastCacheCompanion({
    this.id = const Value.absent(),
    this.forecastJson = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WeatherForecastCacheCompanion.insert({
    required String id,
    required String forecastJson,
    required int fetchedAt,
    required int expiresAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        forecastJson = Value(forecastJson),
        fetchedAt = Value(fetchedAt),
        expiresAt = Value(expiresAt);
  static Insertable<WeatherForecastCacheData> custom({
    Expression<String>? id,
    Expression<String>? forecastJson,
    Expression<int>? fetchedAt,
    Expression<int>? expiresAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (forecastJson != null) 'forecast_json': forecastJson,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WeatherForecastCacheCompanion copyWith(
      {Value<String>? id,
      Value<String>? forecastJson,
      Value<int>? fetchedAt,
      Value<int>? expiresAt,
      Value<int>? rowid}) {
    return WeatherForecastCacheCompanion(
      id: id ?? this.id,
      forecastJson: forecastJson ?? this.forecastJson,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (forecastJson.present) {
      map['forecast_json'] = Variable<String>(forecastJson.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<int>(fetchedAt.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<int>(expiresAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WeatherForecastCacheCompanion(')
          ..write('id: $id, ')
          ..write('forecastJson: $forecastJson, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$SoproDatabase extends GeneratedDatabase {
  _$SoproDatabase(QueryExecutor e) : super(e);
  $SoproDatabaseManager get managers => $SoproDatabaseManager(this);
  late final $EnvironmentsTable environments = $EnvironmentsTable(this);
  late final $TriggersTable triggers = $TriggersTable(this);
  late final $ContextCardsTable contextCards = $ContextCardsTable(this);
  late final $BleEncountersTable bleEncounters = $BleEncountersTable(this);
  late final $GeocodingCacheTable geocodingCache = $GeocodingCacheTable(this);
  late final $ShoppingListItemsTable shoppingListItems =
      $ShoppingListItemsTable(this);
  late final $ScheduledRemindersTable scheduledReminders =
      $ScheduledRemindersTable(this);
  late final $ActivityLogEntriesTable activityLogEntries =
      $ActivityLogEntriesTable(this);
  late final $WeatherCacheEntriesTable weatherCacheEntries =
      $WeatherCacheEntriesTable(this);
  late final $WeatherForecastCacheTable weatherForecastCache =
      $WeatherForecastCacheTable(this);
  late final EnvironmentsDao environmentsDao =
      EnvironmentsDao(this as SoproDatabase);
  late final TriggersDao triggersDao = TriggersDao(this as SoproDatabase);
  late final ContextCardsDao contextCardsDao =
      ContextCardsDao(this as SoproDatabase);
  late final BleEncountersDao bleEncountersDao =
      BleEncountersDao(this as SoproDatabase);
  late final GeocodingCacheDao geocodingCacheDao =
      GeocodingCacheDao(this as SoproDatabase);
  late final ShoppingListItemsDao shoppingListItemsDao =
      ShoppingListItemsDao(this as SoproDatabase);
  late final ScheduledRemindersDao scheduledRemindersDao =
      ScheduledRemindersDao(this as SoproDatabase);
  late final ActivityLogDao activityLogDao =
      ActivityLogDao(this as SoproDatabase);
  late final WeatherCacheDao weatherCacheDao =
      WeatherCacheDao(this as SoproDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        environments,
        triggers,
        contextCards,
        bleEncounters,
        geocodingCache,
        shoppingListItems,
        scheduledReminders,
        activityLogEntries,
        weatherCacheEntries,
        weatherForecastCache
      ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules(
        [
          WritePropagation(
            on: TableUpdateQuery.onTableName('environments',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('triggers', kind: UpdateKind.delete),
            ],
          ),
        ],
      );
}

typedef $$EnvironmentsTableCreateCompanionBuilder = EnvironmentsCompanion
    Function({
  required String id,
  required String name,
  required double latitude,
  required double longitude,
  required double radiusMeters,
  required DateTime createdAt,
  Value<bool> isMarket,
  Value<int> rowid,
});
typedef $$EnvironmentsTableUpdateCompanionBuilder = EnvironmentsCompanion
    Function({
  Value<String> id,
  Value<String> name,
  Value<double> latitude,
  Value<double> longitude,
  Value<double> radiusMeters,
  Value<DateTime> createdAt,
  Value<bool> isMarket,
  Value<int> rowid,
});

final class $$EnvironmentsTableReferences
    extends BaseReferences<_$SoproDatabase, $EnvironmentsTable, Environment> {
  $$EnvironmentsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TriggersTable, List<TriggerRow>>
      _triggersRefsTable(_$SoproDatabase db) =>
          MultiTypedResultKey.fromTable(db.triggers,
              aliasName: $_aliasNameGenerator(
                  db.environments.id, db.triggers.environmentId));

  $$TriggersTableProcessedTableManager get triggersRefs {
    final manager = $$TriggersTableTableManager($_db, $_db.triggers)
        .filter((f) => f.environmentId.id($_item.id));

    final cache = $_typedResult.readTableOrNull(_triggersRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$EnvironmentsTableFilterComposer
    extends Composer<_$SoproDatabase, $EnvironmentsTable> {
  $$EnvironmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get latitude => $composableBuilder(
      column: $table.latitude, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get longitude => $composableBuilder(
      column: $table.longitude, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get radiusMeters => $composableBuilder(
      column: $table.radiusMeters, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isMarket => $composableBuilder(
      column: $table.isMarket, builder: (column) => ColumnFilters(column));

  Expression<bool> triggersRefs(
      Expression<bool> Function($$TriggersTableFilterComposer f) f) {
    final $$TriggersTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.triggers,
        getReferencedColumn: (t) => t.environmentId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TriggersTableFilterComposer(
              $db: $db,
              $table: $db.triggers,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$EnvironmentsTableOrderingComposer
    extends Composer<_$SoproDatabase, $EnvironmentsTable> {
  $$EnvironmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get latitude => $composableBuilder(
      column: $table.latitude, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get longitude => $composableBuilder(
      column: $table.longitude, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get radiusMeters => $composableBuilder(
      column: $table.radiusMeters,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isMarket => $composableBuilder(
      column: $table.isMarket, builder: (column) => ColumnOrderings(column));
}

class $$EnvironmentsTableAnnotationComposer
    extends Composer<_$SoproDatabase, $EnvironmentsTable> {
  $$EnvironmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<double> get radiusMeters => $composableBuilder(
      column: $table.radiusMeters, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get isMarket =>
      $composableBuilder(column: $table.isMarket, builder: (column) => column);

  Expression<T> triggersRefs<T extends Object>(
      Expression<T> Function($$TriggersTableAnnotationComposer a) f) {
    final $$TriggersTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.triggers,
        getReferencedColumn: (t) => t.environmentId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TriggersTableAnnotationComposer(
              $db: $db,
              $table: $db.triggers,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$EnvironmentsTableTableManager extends RootTableManager<
    _$SoproDatabase,
    $EnvironmentsTable,
    Environment,
    $$EnvironmentsTableFilterComposer,
    $$EnvironmentsTableOrderingComposer,
    $$EnvironmentsTableAnnotationComposer,
    $$EnvironmentsTableCreateCompanionBuilder,
    $$EnvironmentsTableUpdateCompanionBuilder,
    (Environment, $$EnvironmentsTableReferences),
    Environment,
    PrefetchHooks Function({bool triggersRefs})> {
  $$EnvironmentsTableTableManager(_$SoproDatabase db, $EnvironmentsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EnvironmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EnvironmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EnvironmentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<double> latitude = const Value.absent(),
            Value<double> longitude = const Value.absent(),
            Value<double> radiusMeters = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<bool> isMarket = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              EnvironmentsCompanion(
            id: id,
            name: name,
            latitude: latitude,
            longitude: longitude,
            radiusMeters: radiusMeters,
            createdAt: createdAt,
            isMarket: isMarket,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required double latitude,
            required double longitude,
            required double radiusMeters,
            required DateTime createdAt,
            Value<bool> isMarket = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              EnvironmentsCompanion.insert(
            id: id,
            name: name,
            latitude: latitude,
            longitude: longitude,
            radiusMeters: radiusMeters,
            createdAt: createdAt,
            isMarket: isMarket,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$EnvironmentsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({triggersRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (triggersRefs) db.triggers],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (triggersRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable: $$EnvironmentsTableReferences
                            ._triggersRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$EnvironmentsTableReferences(db, table, p0)
                                .triggersRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.environmentId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$EnvironmentsTableProcessedTableManager = ProcessedTableManager<
    _$SoproDatabase,
    $EnvironmentsTable,
    Environment,
    $$EnvironmentsTableFilterComposer,
    $$EnvironmentsTableOrderingComposer,
    $$EnvironmentsTableAnnotationComposer,
    $$EnvironmentsTableCreateCompanionBuilder,
    $$EnvironmentsTableUpdateCompanionBuilder,
    (Environment, $$EnvironmentsTableReferences),
    Environment,
    PrefetchHooks Function({bool triggersRefs})>;
typedef $$TriggersTableCreateCompanionBuilder = TriggersCompanion Function({
  required String id,
  required String environmentId,
  required String title,
  required String content,
  Value<bool> isActive,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$TriggersTableUpdateCompanionBuilder = TriggersCompanion Function({
  Value<String> id,
  Value<String> environmentId,
  Value<String> title,
  Value<String> content,
  Value<bool> isActive,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

final class $$TriggersTableReferences
    extends BaseReferences<_$SoproDatabase, $TriggersTable, TriggerRow> {
  $$TriggersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $EnvironmentsTable _environmentIdTable(_$SoproDatabase db) =>
      db.environments.createAlias(
          $_aliasNameGenerator(db.triggers.environmentId, db.environments.id));

  $$EnvironmentsTableProcessedTableManager get environmentId {
    final manager = $$EnvironmentsTableTableManager($_db, $_db.environments)
        .filter((f) => f.id($_item.environmentId));
    final item = $_typedResult.readTableOrNull(_environmentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$TriggersTableFilterComposer
    extends Composer<_$SoproDatabase, $TriggersTable> {
  $$TriggersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  $$EnvironmentsTableFilterComposer get environmentId {
    final $$EnvironmentsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.environmentId,
        referencedTable: $db.environments,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$EnvironmentsTableFilterComposer(
              $db: $db,
              $table: $db.environments,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TriggersTableOrderingComposer
    extends Composer<_$SoproDatabase, $TriggersTable> {
  $$TriggersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  $$EnvironmentsTableOrderingComposer get environmentId {
    final $$EnvironmentsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.environmentId,
        referencedTable: $db.environments,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$EnvironmentsTableOrderingComposer(
              $db: $db,
              $table: $db.environments,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TriggersTableAnnotationComposer
    extends Composer<_$SoproDatabase, $TriggersTable> {
  $$TriggersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$EnvironmentsTableAnnotationComposer get environmentId {
    final $$EnvironmentsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.environmentId,
        referencedTable: $db.environments,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$EnvironmentsTableAnnotationComposer(
              $db: $db,
              $table: $db.environments,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TriggersTableTableManager extends RootTableManager<
    _$SoproDatabase,
    $TriggersTable,
    TriggerRow,
    $$TriggersTableFilterComposer,
    $$TriggersTableOrderingComposer,
    $$TriggersTableAnnotationComposer,
    $$TriggersTableCreateCompanionBuilder,
    $$TriggersTableUpdateCompanionBuilder,
    (TriggerRow, $$TriggersTableReferences),
    TriggerRow,
    PrefetchHooks Function({bool environmentId})> {
  $$TriggersTableTableManager(_$SoproDatabase db, $TriggersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TriggersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TriggersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TriggersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> environmentId = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> content = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TriggersCompanion(
            id: id,
            environmentId: environmentId,
            title: title,
            content: content,
            isActive: isActive,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String environmentId,
            required String title,
            required String content,
            Value<bool> isActive = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              TriggersCompanion.insert(
            id: id,
            environmentId: environmentId,
            title: title,
            content: content,
            isActive: isActive,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$TriggersTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({environmentId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (environmentId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.environmentId,
                    referencedTable:
                        $$TriggersTableReferences._environmentIdTable(db),
                    referencedColumn:
                        $$TriggersTableReferences._environmentIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$TriggersTableProcessedTableManager = ProcessedTableManager<
    _$SoproDatabase,
    $TriggersTable,
    TriggerRow,
    $$TriggersTableFilterComposer,
    $$TriggersTableOrderingComposer,
    $$TriggersTableAnnotationComposer,
    $$TriggersTableCreateCompanionBuilder,
    $$TriggersTableUpdateCompanionBuilder,
    (TriggerRow, $$TriggersTableReferences),
    TriggerRow,
    PrefetchHooks Function({bool environmentId})>;
typedef $$ContextCardsTableCreateCompanionBuilder = ContextCardsCompanion
    Function({
  required String id,
  required String displayName,
  Value<String> role,
  Value<String> company,
  required String bio,
  Value<String> tags,
  Value<String> phone,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$ContextCardsTableUpdateCompanionBuilder = ContextCardsCompanion
    Function({
  Value<String> id,
  Value<String> displayName,
  Value<String> role,
  Value<String> company,
  Value<String> bio,
  Value<String> tags,
  Value<String> phone,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$ContextCardsTableFilterComposer
    extends Composer<_$SoproDatabase, $ContextCardsTable> {
  $$ContextCardsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get company => $composableBuilder(
      column: $table.company, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get bio => $composableBuilder(
      column: $table.bio, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tags => $composableBuilder(
      column: $table.tags, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get phone => $composableBuilder(
      column: $table.phone, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$ContextCardsTableOrderingComposer
    extends Composer<_$SoproDatabase, $ContextCardsTable> {
  $$ContextCardsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get company => $composableBuilder(
      column: $table.company, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get bio => $composableBuilder(
      column: $table.bio, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tags => $composableBuilder(
      column: $table.tags, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get phone => $composableBuilder(
      column: $table.phone, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$ContextCardsTableAnnotationComposer
    extends Composer<_$SoproDatabase, $ContextCardsTable> {
  $$ContextCardsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get company =>
      $composableBuilder(column: $table.company, builder: (column) => column);

  GeneratedColumn<String> get bio =>
      $composableBuilder(column: $table.bio, builder: (column) => column);

  GeneratedColumn<String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ContextCardsTableTableManager extends RootTableManager<
    _$SoproDatabase,
    $ContextCardsTable,
    ContextCard,
    $$ContextCardsTableFilterComposer,
    $$ContextCardsTableOrderingComposer,
    $$ContextCardsTableAnnotationComposer,
    $$ContextCardsTableCreateCompanionBuilder,
    $$ContextCardsTableUpdateCompanionBuilder,
    (
      ContextCard,
      BaseReferences<_$SoproDatabase, $ContextCardsTable, ContextCard>
    ),
    ContextCard,
    PrefetchHooks Function()> {
  $$ContextCardsTableTableManager(_$SoproDatabase db, $ContextCardsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ContextCardsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ContextCardsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ContextCardsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> displayName = const Value.absent(),
            Value<String> role = const Value.absent(),
            Value<String> company = const Value.absent(),
            Value<String> bio = const Value.absent(),
            Value<String> tags = const Value.absent(),
            Value<String> phone = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ContextCardsCompanion(
            id: id,
            displayName: displayName,
            role: role,
            company: company,
            bio: bio,
            tags: tags,
            phone: phone,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String displayName,
            Value<String> role = const Value.absent(),
            Value<String> company = const Value.absent(),
            required String bio,
            Value<String> tags = const Value.absent(),
            Value<String> phone = const Value.absent(),
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ContextCardsCompanion.insert(
            id: id,
            displayName: displayName,
            role: role,
            company: company,
            bio: bio,
            tags: tags,
            phone: phone,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ContextCardsTableProcessedTableManager = ProcessedTableManager<
    _$SoproDatabase,
    $ContextCardsTable,
    ContextCard,
    $$ContextCardsTableFilterComposer,
    $$ContextCardsTableOrderingComposer,
    $$ContextCardsTableAnnotationComposer,
    $$ContextCardsTableCreateCompanionBuilder,
    $$ContextCardsTableUpdateCompanionBuilder,
    (
      ContextCard,
      BaseReferences<_$SoproDatabase, $ContextCardsTable, ContextCard>
    ),
    ContextCard,
    PrefetchHooks Function()>;
typedef $$BleEncountersTableCreateCompanionBuilder = BleEncountersCompanion
    Function({
  required String deviceId,
  Value<String> displayName,
  Value<String> role,
  Value<String> company,
  Value<String> bio,
  Value<String> tags,
  Value<String> phone,
  required DateTime encounteredAt,
  Value<int> rowid,
});
typedef $$BleEncountersTableUpdateCompanionBuilder = BleEncountersCompanion
    Function({
  Value<String> deviceId,
  Value<String> displayName,
  Value<String> role,
  Value<String> company,
  Value<String> bio,
  Value<String> tags,
  Value<String> phone,
  Value<DateTime> encounteredAt,
  Value<int> rowid,
});

class $$BleEncountersTableFilterComposer
    extends Composer<_$SoproDatabase, $BleEncountersTable> {
  $$BleEncountersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get company => $composableBuilder(
      column: $table.company, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get bio => $composableBuilder(
      column: $table.bio, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tags => $composableBuilder(
      column: $table.tags, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get phone => $composableBuilder(
      column: $table.phone, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get encounteredAt => $composableBuilder(
      column: $table.encounteredAt, builder: (column) => ColumnFilters(column));
}

class $$BleEncountersTableOrderingComposer
    extends Composer<_$SoproDatabase, $BleEncountersTable> {
  $$BleEncountersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get company => $composableBuilder(
      column: $table.company, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get bio => $composableBuilder(
      column: $table.bio, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tags => $composableBuilder(
      column: $table.tags, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get phone => $composableBuilder(
      column: $table.phone, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get encounteredAt => $composableBuilder(
      column: $table.encounteredAt,
      builder: (column) => ColumnOrderings(column));
}

class $$BleEncountersTableAnnotationComposer
    extends Composer<_$SoproDatabase, $BleEncountersTable> {
  $$BleEncountersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get company =>
      $composableBuilder(column: $table.company, builder: (column) => column);

  GeneratedColumn<String> get bio =>
      $composableBuilder(column: $table.bio, builder: (column) => column);

  GeneratedColumn<String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<DateTime> get encounteredAt => $composableBuilder(
      column: $table.encounteredAt, builder: (column) => column);
}

class $$BleEncountersTableTableManager extends RootTableManager<
    _$SoproDatabase,
    $BleEncountersTable,
    BleEncounter,
    $$BleEncountersTableFilterComposer,
    $$BleEncountersTableOrderingComposer,
    $$BleEncountersTableAnnotationComposer,
    $$BleEncountersTableCreateCompanionBuilder,
    $$BleEncountersTableUpdateCompanionBuilder,
    (
      BleEncounter,
      BaseReferences<_$SoproDatabase, $BleEncountersTable, BleEncounter>
    ),
    BleEncounter,
    PrefetchHooks Function()> {
  $$BleEncountersTableTableManager(
      _$SoproDatabase db, $BleEncountersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BleEncountersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BleEncountersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BleEncountersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> deviceId = const Value.absent(),
            Value<String> displayName = const Value.absent(),
            Value<String> role = const Value.absent(),
            Value<String> company = const Value.absent(),
            Value<String> bio = const Value.absent(),
            Value<String> tags = const Value.absent(),
            Value<String> phone = const Value.absent(),
            Value<DateTime> encounteredAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              BleEncountersCompanion(
            deviceId: deviceId,
            displayName: displayName,
            role: role,
            company: company,
            bio: bio,
            tags: tags,
            phone: phone,
            encounteredAt: encounteredAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String deviceId,
            Value<String> displayName = const Value.absent(),
            Value<String> role = const Value.absent(),
            Value<String> company = const Value.absent(),
            Value<String> bio = const Value.absent(),
            Value<String> tags = const Value.absent(),
            Value<String> phone = const Value.absent(),
            required DateTime encounteredAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              BleEncountersCompanion.insert(
            deviceId: deviceId,
            displayName: displayName,
            role: role,
            company: company,
            bio: bio,
            tags: tags,
            phone: phone,
            encounteredAt: encounteredAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$BleEncountersTableProcessedTableManager = ProcessedTableManager<
    _$SoproDatabase,
    $BleEncountersTable,
    BleEncounter,
    $$BleEncountersTableFilterComposer,
    $$BleEncountersTableOrderingComposer,
    $$BleEncountersTableAnnotationComposer,
    $$BleEncountersTableCreateCompanionBuilder,
    $$BleEncountersTableUpdateCompanionBuilder,
    (
      BleEncounter,
      BaseReferences<_$SoproDatabase, $BleEncountersTable, BleEncounter>
    ),
    BleEncounter,
    PrefetchHooks Function()>;
typedef $$GeocodingCacheTableCreateCompanionBuilder = GeocodingCacheCompanion
    Function({
  required String id,
  required String queryKey,
  required String displayName,
  required double lat,
  required double lon,
  required String source,
  Value<String> storagePolicy,
  Value<String> placeId,
  required int createdAt,
  Value<int> rowid,
});
typedef $$GeocodingCacheTableUpdateCompanionBuilder = GeocodingCacheCompanion
    Function({
  Value<String> id,
  Value<String> queryKey,
  Value<String> displayName,
  Value<double> lat,
  Value<double> lon,
  Value<String> source,
  Value<String> storagePolicy,
  Value<String> placeId,
  Value<int> createdAt,
  Value<int> rowid,
});

class $$GeocodingCacheTableFilterComposer
    extends Composer<_$SoproDatabase, $GeocodingCacheTable> {
  $$GeocodingCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get queryKey => $composableBuilder(
      column: $table.queryKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get lat => $composableBuilder(
      column: $table.lat, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get lon => $composableBuilder(
      column: $table.lon, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get storagePolicy => $composableBuilder(
      column: $table.storagePolicy, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get placeId => $composableBuilder(
      column: $table.placeId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$GeocodingCacheTableOrderingComposer
    extends Composer<_$SoproDatabase, $GeocodingCacheTable> {
  $$GeocodingCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get queryKey => $composableBuilder(
      column: $table.queryKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get lat => $composableBuilder(
      column: $table.lat, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get lon => $composableBuilder(
      column: $table.lon, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get storagePolicy => $composableBuilder(
      column: $table.storagePolicy,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get placeId => $composableBuilder(
      column: $table.placeId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$GeocodingCacheTableAnnotationComposer
    extends Composer<_$SoproDatabase, $GeocodingCacheTable> {
  $$GeocodingCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get queryKey =>
      $composableBuilder(column: $table.queryKey, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lon =>
      $composableBuilder(column: $table.lon, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get storagePolicy => $composableBuilder(
      column: $table.storagePolicy, builder: (column) => column);

  GeneratedColumn<String> get placeId =>
      $composableBuilder(column: $table.placeId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$GeocodingCacheTableTableManager extends RootTableManager<
    _$SoproDatabase,
    $GeocodingCacheTable,
    GeocodingCacheData,
    $$GeocodingCacheTableFilterComposer,
    $$GeocodingCacheTableOrderingComposer,
    $$GeocodingCacheTableAnnotationComposer,
    $$GeocodingCacheTableCreateCompanionBuilder,
    $$GeocodingCacheTableUpdateCompanionBuilder,
    (
      GeocodingCacheData,
      BaseReferences<_$SoproDatabase, $GeocodingCacheTable, GeocodingCacheData>
    ),
    GeocodingCacheData,
    PrefetchHooks Function()> {
  $$GeocodingCacheTableTableManager(
      _$SoproDatabase db, $GeocodingCacheTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GeocodingCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GeocodingCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GeocodingCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> queryKey = const Value.absent(),
            Value<String> displayName = const Value.absent(),
            Value<double> lat = const Value.absent(),
            Value<double> lon = const Value.absent(),
            Value<String> source = const Value.absent(),
            Value<String> storagePolicy = const Value.absent(),
            Value<String> placeId = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              GeocodingCacheCompanion(
            id: id,
            queryKey: queryKey,
            displayName: displayName,
            lat: lat,
            lon: lon,
            source: source,
            storagePolicy: storagePolicy,
            placeId: placeId,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String queryKey,
            required String displayName,
            required double lat,
            required double lon,
            required String source,
            Value<String> storagePolicy = const Value.absent(),
            Value<String> placeId = const Value.absent(),
            required int createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              GeocodingCacheCompanion.insert(
            id: id,
            queryKey: queryKey,
            displayName: displayName,
            lat: lat,
            lon: lon,
            source: source,
            storagePolicy: storagePolicy,
            placeId: placeId,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$GeocodingCacheTableProcessedTableManager = ProcessedTableManager<
    _$SoproDatabase,
    $GeocodingCacheTable,
    GeocodingCacheData,
    $$GeocodingCacheTableFilterComposer,
    $$GeocodingCacheTableOrderingComposer,
    $$GeocodingCacheTableAnnotationComposer,
    $$GeocodingCacheTableCreateCompanionBuilder,
    $$GeocodingCacheTableUpdateCompanionBuilder,
    (
      GeocodingCacheData,
      BaseReferences<_$SoproDatabase, $GeocodingCacheTable, GeocodingCacheData>
    ),
    GeocodingCacheData,
    PrefetchHooks Function()>;
typedef $$ShoppingListItemsTableCreateCompanionBuilder
    = ShoppingListItemsCompanion Function({
  required String id,
  required String environmentId,
  required String name,
  Value<bool> isChecked,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$ShoppingListItemsTableUpdateCompanionBuilder
    = ShoppingListItemsCompanion Function({
  Value<String> id,
  Value<String> environmentId,
  Value<String> name,
  Value<bool> isChecked,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$ShoppingListItemsTableFilterComposer
    extends Composer<_$SoproDatabase, $ShoppingListItemsTable> {
  $$ShoppingListItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get environmentId => $composableBuilder(
      column: $table.environmentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isChecked => $composableBuilder(
      column: $table.isChecked, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$ShoppingListItemsTableOrderingComposer
    extends Composer<_$SoproDatabase, $ShoppingListItemsTable> {
  $$ShoppingListItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get environmentId => $composableBuilder(
      column: $table.environmentId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isChecked => $composableBuilder(
      column: $table.isChecked, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$ShoppingListItemsTableAnnotationComposer
    extends Composer<_$SoproDatabase, $ShoppingListItemsTable> {
  $$ShoppingListItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get environmentId => $composableBuilder(
      column: $table.environmentId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get isChecked =>
      $composableBuilder(column: $table.isChecked, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ShoppingListItemsTableTableManager extends RootTableManager<
    _$SoproDatabase,
    $ShoppingListItemsTable,
    ShoppingListItem,
    $$ShoppingListItemsTableFilterComposer,
    $$ShoppingListItemsTableOrderingComposer,
    $$ShoppingListItemsTableAnnotationComposer,
    $$ShoppingListItemsTableCreateCompanionBuilder,
    $$ShoppingListItemsTableUpdateCompanionBuilder,
    (
      ShoppingListItem,
      BaseReferences<_$SoproDatabase, $ShoppingListItemsTable, ShoppingListItem>
    ),
    ShoppingListItem,
    PrefetchHooks Function()> {
  $$ShoppingListItemsTableTableManager(
      _$SoproDatabase db, $ShoppingListItemsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShoppingListItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShoppingListItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ShoppingListItemsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> environmentId = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<bool> isChecked = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ShoppingListItemsCompanion(
            id: id,
            environmentId: environmentId,
            name: name,
            isChecked: isChecked,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String environmentId,
            required String name,
            Value<bool> isChecked = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ShoppingListItemsCompanion.insert(
            id: id,
            environmentId: environmentId,
            name: name,
            isChecked: isChecked,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ShoppingListItemsTableProcessedTableManager = ProcessedTableManager<
    _$SoproDatabase,
    $ShoppingListItemsTable,
    ShoppingListItem,
    $$ShoppingListItemsTableFilterComposer,
    $$ShoppingListItemsTableOrderingComposer,
    $$ShoppingListItemsTableAnnotationComposer,
    $$ShoppingListItemsTableCreateCompanionBuilder,
    $$ShoppingListItemsTableUpdateCompanionBuilder,
    (
      ShoppingListItem,
      BaseReferences<_$SoproDatabase, $ShoppingListItemsTable, ShoppingListItem>
    ),
    ShoppingListItem,
    PrefetchHooks Function()>;
typedef $$ScheduledRemindersTableCreateCompanionBuilder
    = ScheduledRemindersCompanion Function({
  required String id,
  required String title,
  Value<String> content,
  required DateTime scheduledAt,
  Value<String> repeatRule,
  Value<String> repeatDaysOfWeek,
  Value<bool> isActive,
  Value<String> alertMode,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$ScheduledRemindersTableUpdateCompanionBuilder
    = ScheduledRemindersCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<String> content,
  Value<DateTime> scheduledAt,
  Value<String> repeatRule,
  Value<String> repeatDaysOfWeek,
  Value<bool> isActive,
  Value<String> alertMode,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$ScheduledRemindersTableFilterComposer
    extends Composer<_$SoproDatabase, $ScheduledRemindersTable> {
  $$ScheduledRemindersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get scheduledAt => $composableBuilder(
      column: $table.scheduledAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get repeatRule => $composableBuilder(
      column: $table.repeatRule, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get repeatDaysOfWeek => $composableBuilder(
      column: $table.repeatDaysOfWeek,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get alertMode => $composableBuilder(
      column: $table.alertMode, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$ScheduledRemindersTableOrderingComposer
    extends Composer<_$SoproDatabase, $ScheduledRemindersTable> {
  $$ScheduledRemindersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get scheduledAt => $composableBuilder(
      column: $table.scheduledAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get repeatRule => $composableBuilder(
      column: $table.repeatRule, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get repeatDaysOfWeek => $composableBuilder(
      column: $table.repeatDaysOfWeek,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get alertMode => $composableBuilder(
      column: $table.alertMode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$ScheduledRemindersTableAnnotationComposer
    extends Composer<_$SoproDatabase, $ScheduledRemindersTable> {
  $$ScheduledRemindersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<DateTime> get scheduledAt => $composableBuilder(
      column: $table.scheduledAt, builder: (column) => column);

  GeneratedColumn<String> get repeatRule => $composableBuilder(
      column: $table.repeatRule, builder: (column) => column);

  GeneratedColumn<String> get repeatDaysOfWeek => $composableBuilder(
      column: $table.repeatDaysOfWeek, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<String> get alertMode =>
      $composableBuilder(column: $table.alertMode, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ScheduledRemindersTableTableManager extends RootTableManager<
    _$SoproDatabase,
    $ScheduledRemindersTable,
    ScheduledReminder,
    $$ScheduledRemindersTableFilterComposer,
    $$ScheduledRemindersTableOrderingComposer,
    $$ScheduledRemindersTableAnnotationComposer,
    $$ScheduledRemindersTableCreateCompanionBuilder,
    $$ScheduledRemindersTableUpdateCompanionBuilder,
    (
      ScheduledReminder,
      BaseReferences<_$SoproDatabase, $ScheduledRemindersTable,
          ScheduledReminder>
    ),
    ScheduledReminder,
    PrefetchHooks Function()> {
  $$ScheduledRemindersTableTableManager(
      _$SoproDatabase db, $ScheduledRemindersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ScheduledRemindersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ScheduledRemindersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ScheduledRemindersTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> content = const Value.absent(),
            Value<DateTime> scheduledAt = const Value.absent(),
            Value<String> repeatRule = const Value.absent(),
            Value<String> repeatDaysOfWeek = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<String> alertMode = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ScheduledRemindersCompanion(
            id: id,
            title: title,
            content: content,
            scheduledAt: scheduledAt,
            repeatRule: repeatRule,
            repeatDaysOfWeek: repeatDaysOfWeek,
            isActive: isActive,
            alertMode: alertMode,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String title,
            Value<String> content = const Value.absent(),
            required DateTime scheduledAt,
            Value<String> repeatRule = const Value.absent(),
            Value<String> repeatDaysOfWeek = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<String> alertMode = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ScheduledRemindersCompanion.insert(
            id: id,
            title: title,
            content: content,
            scheduledAt: scheduledAt,
            repeatRule: repeatRule,
            repeatDaysOfWeek: repeatDaysOfWeek,
            isActive: isActive,
            alertMode: alertMode,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ScheduledRemindersTableProcessedTableManager = ProcessedTableManager<
    _$SoproDatabase,
    $ScheduledRemindersTable,
    ScheduledReminder,
    $$ScheduledRemindersTableFilterComposer,
    $$ScheduledRemindersTableOrderingComposer,
    $$ScheduledRemindersTableAnnotationComposer,
    $$ScheduledRemindersTableCreateCompanionBuilder,
    $$ScheduledRemindersTableUpdateCompanionBuilder,
    (
      ScheduledReminder,
      BaseReferences<_$SoproDatabase, $ScheduledRemindersTable,
          ScheduledReminder>
    ),
    ScheduledReminder,
    PrefetchHooks Function()>;
typedef $$ActivityLogEntriesTableCreateCompanionBuilder
    = ActivityLogEntriesCompanion Function({
  required String id,
  required String type,
  required String title,
  Value<String> subtitle,
  Value<String?> environmentId,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$ActivityLogEntriesTableUpdateCompanionBuilder
    = ActivityLogEntriesCompanion Function({
  Value<String> id,
  Value<String> type,
  Value<String> title,
  Value<String> subtitle,
  Value<String?> environmentId,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$ActivityLogEntriesTableFilterComposer
    extends Composer<_$SoproDatabase, $ActivityLogEntriesTable> {
  $$ActivityLogEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get subtitle => $composableBuilder(
      column: $table.subtitle, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get environmentId => $composableBuilder(
      column: $table.environmentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$ActivityLogEntriesTableOrderingComposer
    extends Composer<_$SoproDatabase, $ActivityLogEntriesTable> {
  $$ActivityLogEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get subtitle => $composableBuilder(
      column: $table.subtitle, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get environmentId => $composableBuilder(
      column: $table.environmentId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$ActivityLogEntriesTableAnnotationComposer
    extends Composer<_$SoproDatabase, $ActivityLogEntriesTable> {
  $$ActivityLogEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get subtitle =>
      $composableBuilder(column: $table.subtitle, builder: (column) => column);

  GeneratedColumn<String> get environmentId => $composableBuilder(
      column: $table.environmentId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ActivityLogEntriesTableTableManager extends RootTableManager<
    _$SoproDatabase,
    $ActivityLogEntriesTable,
    ActivityLogEntry,
    $$ActivityLogEntriesTableFilterComposer,
    $$ActivityLogEntriesTableOrderingComposer,
    $$ActivityLogEntriesTableAnnotationComposer,
    $$ActivityLogEntriesTableCreateCompanionBuilder,
    $$ActivityLogEntriesTableUpdateCompanionBuilder,
    (
      ActivityLogEntry,
      BaseReferences<_$SoproDatabase, $ActivityLogEntriesTable,
          ActivityLogEntry>
    ),
    ActivityLogEntry,
    PrefetchHooks Function()> {
  $$ActivityLogEntriesTableTableManager(
      _$SoproDatabase db, $ActivityLogEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActivityLogEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActivityLogEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActivityLogEntriesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> subtitle = const Value.absent(),
            Value<String?> environmentId = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ActivityLogEntriesCompanion(
            id: id,
            type: type,
            title: title,
            subtitle: subtitle,
            environmentId: environmentId,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String type,
            required String title,
            Value<String> subtitle = const Value.absent(),
            Value<String?> environmentId = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ActivityLogEntriesCompanion.insert(
            id: id,
            type: type,
            title: title,
            subtitle: subtitle,
            environmentId: environmentId,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ActivityLogEntriesTableProcessedTableManager = ProcessedTableManager<
    _$SoproDatabase,
    $ActivityLogEntriesTable,
    ActivityLogEntry,
    $$ActivityLogEntriesTableFilterComposer,
    $$ActivityLogEntriesTableOrderingComposer,
    $$ActivityLogEntriesTableAnnotationComposer,
    $$ActivityLogEntriesTableCreateCompanionBuilder,
    $$ActivityLogEntriesTableUpdateCompanionBuilder,
    (
      ActivityLogEntry,
      BaseReferences<_$SoproDatabase, $ActivityLogEntriesTable,
          ActivityLogEntry>
    ),
    ActivityLogEntry,
    PrefetchHooks Function()>;
typedef $$WeatherCacheEntriesTableCreateCompanionBuilder
    = WeatherCacheEntriesCompanion Function({
  required String id,
  required double lat,
  required double lon,
  required double tempCelsius,
  required String condition,
  required String description,
  required String iconCode,
  Value<int> humidity,
  Value<String> cityName,
  required int fetchedAt,
  required int expiresAt,
  Value<int> rowid,
});
typedef $$WeatherCacheEntriesTableUpdateCompanionBuilder
    = WeatherCacheEntriesCompanion Function({
  Value<String> id,
  Value<double> lat,
  Value<double> lon,
  Value<double> tempCelsius,
  Value<String> condition,
  Value<String> description,
  Value<String> iconCode,
  Value<int> humidity,
  Value<String> cityName,
  Value<int> fetchedAt,
  Value<int> expiresAt,
  Value<int> rowid,
});

class $$WeatherCacheEntriesTableFilterComposer
    extends Composer<_$SoproDatabase, $WeatherCacheEntriesTable> {
  $$WeatherCacheEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get lat => $composableBuilder(
      column: $table.lat, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get lon => $composableBuilder(
      column: $table.lon, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get tempCelsius => $composableBuilder(
      column: $table.tempCelsius, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get condition => $composableBuilder(
      column: $table.condition, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get iconCode => $composableBuilder(
      column: $table.iconCode, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get humidity => $composableBuilder(
      column: $table.humidity, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cityName => $composableBuilder(
      column: $table.cityName, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get fetchedAt => $composableBuilder(
      column: $table.fetchedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get expiresAt => $composableBuilder(
      column: $table.expiresAt, builder: (column) => ColumnFilters(column));
}

class $$WeatherCacheEntriesTableOrderingComposer
    extends Composer<_$SoproDatabase, $WeatherCacheEntriesTable> {
  $$WeatherCacheEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get lat => $composableBuilder(
      column: $table.lat, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get lon => $composableBuilder(
      column: $table.lon, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get tempCelsius => $composableBuilder(
      column: $table.tempCelsius, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get condition => $composableBuilder(
      column: $table.condition, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get iconCode => $composableBuilder(
      column: $table.iconCode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get humidity => $composableBuilder(
      column: $table.humidity, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cityName => $composableBuilder(
      column: $table.cityName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get fetchedAt => $composableBuilder(
      column: $table.fetchedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get expiresAt => $composableBuilder(
      column: $table.expiresAt, builder: (column) => ColumnOrderings(column));
}

class $$WeatherCacheEntriesTableAnnotationComposer
    extends Composer<_$SoproDatabase, $WeatherCacheEntriesTable> {
  $$WeatherCacheEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lon =>
      $composableBuilder(column: $table.lon, builder: (column) => column);

  GeneratedColumn<double> get tempCelsius => $composableBuilder(
      column: $table.tempCelsius, builder: (column) => column);

  GeneratedColumn<String> get condition =>
      $composableBuilder(column: $table.condition, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get iconCode =>
      $composableBuilder(column: $table.iconCode, builder: (column) => column);

  GeneratedColumn<int> get humidity =>
      $composableBuilder(column: $table.humidity, builder: (column) => column);

  GeneratedColumn<String> get cityName =>
      $composableBuilder(column: $table.cityName, builder: (column) => column);

  GeneratedColumn<int> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);

  GeneratedColumn<int> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);
}

class $$WeatherCacheEntriesTableTableManager extends RootTableManager<
    _$SoproDatabase,
    $WeatherCacheEntriesTable,
    WeatherCacheEntry,
    $$WeatherCacheEntriesTableFilterComposer,
    $$WeatherCacheEntriesTableOrderingComposer,
    $$WeatherCacheEntriesTableAnnotationComposer,
    $$WeatherCacheEntriesTableCreateCompanionBuilder,
    $$WeatherCacheEntriesTableUpdateCompanionBuilder,
    (
      WeatherCacheEntry,
      BaseReferences<_$SoproDatabase, $WeatherCacheEntriesTable,
          WeatherCacheEntry>
    ),
    WeatherCacheEntry,
    PrefetchHooks Function()> {
  $$WeatherCacheEntriesTableTableManager(
      _$SoproDatabase db, $WeatherCacheEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WeatherCacheEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WeatherCacheEntriesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WeatherCacheEntriesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<double> lat = const Value.absent(),
            Value<double> lon = const Value.absent(),
            Value<double> tempCelsius = const Value.absent(),
            Value<String> condition = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<String> iconCode = const Value.absent(),
            Value<int> humidity = const Value.absent(),
            Value<String> cityName = const Value.absent(),
            Value<int> fetchedAt = const Value.absent(),
            Value<int> expiresAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              WeatherCacheEntriesCompanion(
            id: id,
            lat: lat,
            lon: lon,
            tempCelsius: tempCelsius,
            condition: condition,
            description: description,
            iconCode: iconCode,
            humidity: humidity,
            cityName: cityName,
            fetchedAt: fetchedAt,
            expiresAt: expiresAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required double lat,
            required double lon,
            required double tempCelsius,
            required String condition,
            required String description,
            required String iconCode,
            Value<int> humidity = const Value.absent(),
            Value<String> cityName = const Value.absent(),
            required int fetchedAt,
            required int expiresAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              WeatherCacheEntriesCompanion.insert(
            id: id,
            lat: lat,
            lon: lon,
            tempCelsius: tempCelsius,
            condition: condition,
            description: description,
            iconCode: iconCode,
            humidity: humidity,
            cityName: cityName,
            fetchedAt: fetchedAt,
            expiresAt: expiresAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$WeatherCacheEntriesTableProcessedTableManager = ProcessedTableManager<
    _$SoproDatabase,
    $WeatherCacheEntriesTable,
    WeatherCacheEntry,
    $$WeatherCacheEntriesTableFilterComposer,
    $$WeatherCacheEntriesTableOrderingComposer,
    $$WeatherCacheEntriesTableAnnotationComposer,
    $$WeatherCacheEntriesTableCreateCompanionBuilder,
    $$WeatherCacheEntriesTableUpdateCompanionBuilder,
    (
      WeatherCacheEntry,
      BaseReferences<_$SoproDatabase, $WeatherCacheEntriesTable,
          WeatherCacheEntry>
    ),
    WeatherCacheEntry,
    PrefetchHooks Function()>;
typedef $$WeatherForecastCacheTableCreateCompanionBuilder
    = WeatherForecastCacheCompanion Function({
  required String id,
  required String forecastJson,
  required int fetchedAt,
  required int expiresAt,
  Value<int> rowid,
});
typedef $$WeatherForecastCacheTableUpdateCompanionBuilder
    = WeatherForecastCacheCompanion Function({
  Value<String> id,
  Value<String> forecastJson,
  Value<int> fetchedAt,
  Value<int> expiresAt,
  Value<int> rowid,
});

class $$WeatherForecastCacheTableFilterComposer
    extends Composer<_$SoproDatabase, $WeatherForecastCacheTable> {
  $$WeatherForecastCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get forecastJson => $composableBuilder(
      column: $table.forecastJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get fetchedAt => $composableBuilder(
      column: $table.fetchedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get expiresAt => $composableBuilder(
      column: $table.expiresAt, builder: (column) => ColumnFilters(column));
}

class $$WeatherForecastCacheTableOrderingComposer
    extends Composer<_$SoproDatabase, $WeatherForecastCacheTable> {
  $$WeatherForecastCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get forecastJson => $composableBuilder(
      column: $table.forecastJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get fetchedAt => $composableBuilder(
      column: $table.fetchedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get expiresAt => $composableBuilder(
      column: $table.expiresAt, builder: (column) => ColumnOrderings(column));
}

class $$WeatherForecastCacheTableAnnotationComposer
    extends Composer<_$SoproDatabase, $WeatherForecastCacheTable> {
  $$WeatherForecastCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get forecastJson => $composableBuilder(
      column: $table.forecastJson, builder: (column) => column);

  GeneratedColumn<int> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);

  GeneratedColumn<int> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);
}

class $$WeatherForecastCacheTableTableManager extends RootTableManager<
    _$SoproDatabase,
    $WeatherForecastCacheTable,
    WeatherForecastCacheData,
    $$WeatherForecastCacheTableFilterComposer,
    $$WeatherForecastCacheTableOrderingComposer,
    $$WeatherForecastCacheTableAnnotationComposer,
    $$WeatherForecastCacheTableCreateCompanionBuilder,
    $$WeatherForecastCacheTableUpdateCompanionBuilder,
    (
      WeatherForecastCacheData,
      BaseReferences<_$SoproDatabase, $WeatherForecastCacheTable,
          WeatherForecastCacheData>
    ),
    WeatherForecastCacheData,
    PrefetchHooks Function()> {
  $$WeatherForecastCacheTableTableManager(
      _$SoproDatabase db, $WeatherForecastCacheTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WeatherForecastCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WeatherForecastCacheTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WeatherForecastCacheTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> forecastJson = const Value.absent(),
            Value<int> fetchedAt = const Value.absent(),
            Value<int> expiresAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              WeatherForecastCacheCompanion(
            id: id,
            forecastJson: forecastJson,
            fetchedAt: fetchedAt,
            expiresAt: expiresAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String forecastJson,
            required int fetchedAt,
            required int expiresAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              WeatherForecastCacheCompanion.insert(
            id: id,
            forecastJson: forecastJson,
            fetchedAt: fetchedAt,
            expiresAt: expiresAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$WeatherForecastCacheTableProcessedTableManager
    = ProcessedTableManager<
        _$SoproDatabase,
        $WeatherForecastCacheTable,
        WeatherForecastCacheData,
        $$WeatherForecastCacheTableFilterComposer,
        $$WeatherForecastCacheTableOrderingComposer,
        $$WeatherForecastCacheTableAnnotationComposer,
        $$WeatherForecastCacheTableCreateCompanionBuilder,
        $$WeatherForecastCacheTableUpdateCompanionBuilder,
        (
          WeatherForecastCacheData,
          BaseReferences<_$SoproDatabase, $WeatherForecastCacheTable,
              WeatherForecastCacheData>
        ),
        WeatherForecastCacheData,
        PrefetchHooks Function()>;

class $SoproDatabaseManager {
  final _$SoproDatabase _db;
  $SoproDatabaseManager(this._db);
  $$EnvironmentsTableTableManager get environments =>
      $$EnvironmentsTableTableManager(_db, _db.environments);
  $$TriggersTableTableManager get triggers =>
      $$TriggersTableTableManager(_db, _db.triggers);
  $$ContextCardsTableTableManager get contextCards =>
      $$ContextCardsTableTableManager(_db, _db.contextCards);
  $$BleEncountersTableTableManager get bleEncounters =>
      $$BleEncountersTableTableManager(_db, _db.bleEncounters);
  $$GeocodingCacheTableTableManager get geocodingCache =>
      $$GeocodingCacheTableTableManager(_db, _db.geocodingCache);
  $$ShoppingListItemsTableTableManager get shoppingListItems =>
      $$ShoppingListItemsTableTableManager(_db, _db.shoppingListItems);
  $$ScheduledRemindersTableTableManager get scheduledReminders =>
      $$ScheduledRemindersTableTableManager(_db, _db.scheduledReminders);
  $$ActivityLogEntriesTableTableManager get activityLogEntries =>
      $$ActivityLogEntriesTableTableManager(_db, _db.activityLogEntries);
  $$WeatherCacheEntriesTableTableManager get weatherCacheEntries =>
      $$WeatherCacheEntriesTableTableManager(_db, _db.weatherCacheEntries);
  $$WeatherForecastCacheTableTableManager get weatherForecastCache =>
      $$WeatherForecastCacheTableTableManager(_db, _db.weatherForecastCache);
}
