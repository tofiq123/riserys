// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $AlarmsTable extends Alarms with TableInfo<$AlarmsTable, AlarmRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlarmsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _hourMeta = const VerificationMeta('hour');
  @override
  late final GeneratedColumn<int> hour = GeneratedColumn<int>(
    'hour',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _minuteMeta = const VerificationMeta('minute');
  @override
  late final GeneratedColumn<int> minute = GeneratedColumn<int>(
    'minute',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _daysMeta = const VerificationMeta('days');
  @override
  late final GeneratedColumn<String> days = GeneratedColumn<String>(
    'days',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Alarm'),
  );
  static const VerificationMeta _soundAssetMeta = const VerificationMeta(
    'soundAsset',
  );
  @override
  late final GeneratedColumn<String> soundAsset = GeneratedColumn<String>(
    'sound_asset',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('sounds/default_alarm.mp3'),
  );
  static const VerificationMeta _vibrateMeta = const VerificationMeta(
    'vibrate',
  );
  @override
  late final GeneratedColumn<bool> vibrate = GeneratedColumn<bool>(
    'vibrate',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("vibrate" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _lastDismissedAtMeta = const VerificationMeta(
    'lastDismissedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastDismissedAt =
      GeneratedColumn<DateTime>(
        'last_dismissed_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _missionMeta = const VerificationMeta(
    'mission',
  );
  @override
  late final GeneratedColumn<String> mission = GeneratedColumn<String>(
    'mission',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('none'),
  );
  static const VerificationMeta _missionDiffMeta = const VerificationMeta(
    'missionDiff',
  );
  @override
  late final GeneratedColumn<String> missionDiff = GeneratedColumn<String>(
    'mission_diff',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('easy'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    hour,
    minute,
    days,
    enabled,
    label,
    soundAsset,
    vibrate,
    lastDismissedAt,
    mission,
    missionDiff,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'alarms';
  @override
  VerificationContext validateIntegrity(
    Insertable<AlarmRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('hour')) {
      context.handle(
        _hourMeta,
        hour.isAcceptableOrUnknown(data['hour']!, _hourMeta),
      );
    } else if (isInserting) {
      context.missing(_hourMeta);
    }
    if (data.containsKey('minute')) {
      context.handle(
        _minuteMeta,
        minute.isAcceptableOrUnknown(data['minute']!, _minuteMeta),
      );
    } else if (isInserting) {
      context.missing(_minuteMeta);
    }
    if (data.containsKey('days')) {
      context.handle(
        _daysMeta,
        days.isAcceptableOrUnknown(data['days']!, _daysMeta),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    }
    if (data.containsKey('sound_asset')) {
      context.handle(
        _soundAssetMeta,
        soundAsset.isAcceptableOrUnknown(data['sound_asset']!, _soundAssetMeta),
      );
    }
    if (data.containsKey('vibrate')) {
      context.handle(
        _vibrateMeta,
        vibrate.isAcceptableOrUnknown(data['vibrate']!, _vibrateMeta),
      );
    }
    if (data.containsKey('last_dismissed_at')) {
      context.handle(
        _lastDismissedAtMeta,
        lastDismissedAt.isAcceptableOrUnknown(
          data['last_dismissed_at']!,
          _lastDismissedAtMeta,
        ),
      );
    }
    if (data.containsKey('mission')) {
      context.handle(
        _missionMeta,
        mission.isAcceptableOrUnknown(data['mission']!, _missionMeta),
      );
    }
    if (data.containsKey('mission_diff')) {
      context.handle(
        _missionDiffMeta,
        missionDiff.isAcceptableOrUnknown(
          data['mission_diff']!,
          _missionDiffMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AlarmRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AlarmRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      hour: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hour'],
      )!,
      minute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}minute'],
      )!,
      days: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}days'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      soundAsset: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sound_asset'],
      )!,
      vibrate: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}vibrate'],
      )!,
      lastDismissedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_dismissed_at'],
      ),
      mission: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mission'],
      )!,
      missionDiff: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mission_diff'],
      )!,
    );
  }

  @override
  $AlarmsTable createAlias(String alias) {
    return $AlarmsTable(attachedDatabase, alias);
  }
}

class AlarmRow extends DataClass implements Insertable<AlarmRow> {
  final int id;
  final int hour;
  final int minute;

  /// Day indices 0=Sun..6=Sat joined by commas. Empty string = one-shot.
  final String days;
  final bool enabled;
  final String label;
  final String soundAsset;
  final bool vibrate;

  /// UTC instant the alarm was last dismissed, or null if never dismissed.
  /// Used by recovery to avoid re-ringing an occurrence the user already
  /// dealt with, and by [AlarmRepository.recordDismissed] to disable a
  /// one-shot alarm once it has fired.
  final DateTime? lastDismissedAt;

  /// Dismiss mission and difficulty (added in schema v2).
  final String mission;
  final String missionDiff;
  const AlarmRow({
    required this.id,
    required this.hour,
    required this.minute,
    required this.days,
    required this.enabled,
    required this.label,
    required this.soundAsset,
    required this.vibrate,
    this.lastDismissedAt,
    required this.mission,
    required this.missionDiff,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['hour'] = Variable<int>(hour);
    map['minute'] = Variable<int>(minute);
    map['days'] = Variable<String>(days);
    map['enabled'] = Variable<bool>(enabled);
    map['label'] = Variable<String>(label);
    map['sound_asset'] = Variable<String>(soundAsset);
    map['vibrate'] = Variable<bool>(vibrate);
    if (!nullToAbsent || lastDismissedAt != null) {
      map['last_dismissed_at'] = Variable<DateTime>(lastDismissedAt);
    }
    map['mission'] = Variable<String>(mission);
    map['mission_diff'] = Variable<String>(missionDiff);
    return map;
  }

  AlarmsCompanion toCompanion(bool nullToAbsent) {
    return AlarmsCompanion(
      id: Value(id),
      hour: Value(hour),
      minute: Value(minute),
      days: Value(days),
      enabled: Value(enabled),
      label: Value(label),
      soundAsset: Value(soundAsset),
      vibrate: Value(vibrate),
      lastDismissedAt: lastDismissedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastDismissedAt),
      mission: Value(mission),
      missionDiff: Value(missionDiff),
    );
  }

  factory AlarmRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AlarmRow(
      id: serializer.fromJson<int>(json['id']),
      hour: serializer.fromJson<int>(json['hour']),
      minute: serializer.fromJson<int>(json['minute']),
      days: serializer.fromJson<String>(json['days']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      label: serializer.fromJson<String>(json['label']),
      soundAsset: serializer.fromJson<String>(json['soundAsset']),
      vibrate: serializer.fromJson<bool>(json['vibrate']),
      lastDismissedAt: serializer.fromJson<DateTime?>(json['lastDismissedAt']),
      mission: serializer.fromJson<String>(json['mission']),
      missionDiff: serializer.fromJson<String>(json['missionDiff']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'hour': serializer.toJson<int>(hour),
      'minute': serializer.toJson<int>(minute),
      'days': serializer.toJson<String>(days),
      'enabled': serializer.toJson<bool>(enabled),
      'label': serializer.toJson<String>(label),
      'soundAsset': serializer.toJson<String>(soundAsset),
      'vibrate': serializer.toJson<bool>(vibrate),
      'lastDismissedAt': serializer.toJson<DateTime?>(lastDismissedAt),
      'mission': serializer.toJson<String>(mission),
      'missionDiff': serializer.toJson<String>(missionDiff),
    };
  }

  AlarmRow copyWith({
    int? id,
    int? hour,
    int? minute,
    String? days,
    bool? enabled,
    String? label,
    String? soundAsset,
    bool? vibrate,
    Value<DateTime?> lastDismissedAt = const Value.absent(),
    String? mission,
    String? missionDiff,
  }) => AlarmRow(
    id: id ?? this.id,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    days: days ?? this.days,
    enabled: enabled ?? this.enabled,
    label: label ?? this.label,
    soundAsset: soundAsset ?? this.soundAsset,
    vibrate: vibrate ?? this.vibrate,
    lastDismissedAt: lastDismissedAt.present
        ? lastDismissedAt.value
        : this.lastDismissedAt,
    mission: mission ?? this.mission,
    missionDiff: missionDiff ?? this.missionDiff,
  );
  AlarmRow copyWithCompanion(AlarmsCompanion data) {
    return AlarmRow(
      id: data.id.present ? data.id.value : this.id,
      hour: data.hour.present ? data.hour.value : this.hour,
      minute: data.minute.present ? data.minute.value : this.minute,
      days: data.days.present ? data.days.value : this.days,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      label: data.label.present ? data.label.value : this.label,
      soundAsset: data.soundAsset.present
          ? data.soundAsset.value
          : this.soundAsset,
      vibrate: data.vibrate.present ? data.vibrate.value : this.vibrate,
      lastDismissedAt: data.lastDismissedAt.present
          ? data.lastDismissedAt.value
          : this.lastDismissedAt,
      mission: data.mission.present ? data.mission.value : this.mission,
      missionDiff: data.missionDiff.present
          ? data.missionDiff.value
          : this.missionDiff,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AlarmRow(')
          ..write('id: $id, ')
          ..write('hour: $hour, ')
          ..write('minute: $minute, ')
          ..write('days: $days, ')
          ..write('enabled: $enabled, ')
          ..write('label: $label, ')
          ..write('soundAsset: $soundAsset, ')
          ..write('vibrate: $vibrate, ')
          ..write('lastDismissedAt: $lastDismissedAt, ')
          ..write('mission: $mission, ')
          ..write('missionDiff: $missionDiff')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    hour,
    minute,
    days,
    enabled,
    label,
    soundAsset,
    vibrate,
    lastDismissedAt,
    mission,
    missionDiff,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AlarmRow &&
          other.id == this.id &&
          other.hour == this.hour &&
          other.minute == this.minute &&
          other.days == this.days &&
          other.enabled == this.enabled &&
          other.label == this.label &&
          other.soundAsset == this.soundAsset &&
          other.vibrate == this.vibrate &&
          other.lastDismissedAt == this.lastDismissedAt &&
          other.mission == this.mission &&
          other.missionDiff == this.missionDiff);
}

class AlarmsCompanion extends UpdateCompanion<AlarmRow> {
  final Value<int> id;
  final Value<int> hour;
  final Value<int> minute;
  final Value<String> days;
  final Value<bool> enabled;
  final Value<String> label;
  final Value<String> soundAsset;
  final Value<bool> vibrate;
  final Value<DateTime?> lastDismissedAt;
  final Value<String> mission;
  final Value<String> missionDiff;
  const AlarmsCompanion({
    this.id = const Value.absent(),
    this.hour = const Value.absent(),
    this.minute = const Value.absent(),
    this.days = const Value.absent(),
    this.enabled = const Value.absent(),
    this.label = const Value.absent(),
    this.soundAsset = const Value.absent(),
    this.vibrate = const Value.absent(),
    this.lastDismissedAt = const Value.absent(),
    this.mission = const Value.absent(),
    this.missionDiff = const Value.absent(),
  });
  AlarmsCompanion.insert({
    this.id = const Value.absent(),
    required int hour,
    required int minute,
    this.days = const Value.absent(),
    this.enabled = const Value.absent(),
    this.label = const Value.absent(),
    this.soundAsset = const Value.absent(),
    this.vibrate = const Value.absent(),
    this.lastDismissedAt = const Value.absent(),
    this.mission = const Value.absent(),
    this.missionDiff = const Value.absent(),
  }) : hour = Value(hour),
       minute = Value(minute);
  static Insertable<AlarmRow> custom({
    Expression<int>? id,
    Expression<int>? hour,
    Expression<int>? minute,
    Expression<String>? days,
    Expression<bool>? enabled,
    Expression<String>? label,
    Expression<String>? soundAsset,
    Expression<bool>? vibrate,
    Expression<DateTime>? lastDismissedAt,
    Expression<String>? mission,
    Expression<String>? missionDiff,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (hour != null) 'hour': hour,
      if (minute != null) 'minute': minute,
      if (days != null) 'days': days,
      if (enabled != null) 'enabled': enabled,
      if (label != null) 'label': label,
      if (soundAsset != null) 'sound_asset': soundAsset,
      if (vibrate != null) 'vibrate': vibrate,
      if (lastDismissedAt != null) 'last_dismissed_at': lastDismissedAt,
      if (mission != null) 'mission': mission,
      if (missionDiff != null) 'mission_diff': missionDiff,
    });
  }

  AlarmsCompanion copyWith({
    Value<int>? id,
    Value<int>? hour,
    Value<int>? minute,
    Value<String>? days,
    Value<bool>? enabled,
    Value<String>? label,
    Value<String>? soundAsset,
    Value<bool>? vibrate,
    Value<DateTime?>? lastDismissedAt,
    Value<String>? mission,
    Value<String>? missionDiff,
  }) {
    return AlarmsCompanion(
      id: id ?? this.id,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      days: days ?? this.days,
      enabled: enabled ?? this.enabled,
      label: label ?? this.label,
      soundAsset: soundAsset ?? this.soundAsset,
      vibrate: vibrate ?? this.vibrate,
      lastDismissedAt: lastDismissedAt ?? this.lastDismissedAt,
      mission: mission ?? this.mission,
      missionDiff: missionDiff ?? this.missionDiff,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (hour.present) {
      map['hour'] = Variable<int>(hour.value);
    }
    if (minute.present) {
      map['minute'] = Variable<int>(minute.value);
    }
    if (days.present) {
      map['days'] = Variable<String>(days.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (soundAsset.present) {
      map['sound_asset'] = Variable<String>(soundAsset.value);
    }
    if (vibrate.present) {
      map['vibrate'] = Variable<bool>(vibrate.value);
    }
    if (lastDismissedAt.present) {
      map['last_dismissed_at'] = Variable<DateTime>(lastDismissedAt.value);
    }
    if (mission.present) {
      map['mission'] = Variable<String>(mission.value);
    }
    if (missionDiff.present) {
      map['mission_diff'] = Variable<String>(missionDiff.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlarmsCompanion(')
          ..write('id: $id, ')
          ..write('hour: $hour, ')
          ..write('minute: $minute, ')
          ..write('days: $days, ')
          ..write('enabled: $enabled, ')
          ..write('label: $label, ')
          ..write('soundAsset: $soundAsset, ')
          ..write('vibrate: $vibrate, ')
          ..write('lastDismissedAt: $lastDismissedAt, ')
          ..write('mission: $mission, ')
          ..write('missionDiff: $missionDiff')
          ..write(')'))
        .toString();
  }
}

class $WakeEventsTable extends WakeEvents
    with TableInfo<$WakeEventsTable, WakeEventRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WakeEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _alarmIdMeta = const VerificationMeta(
    'alarmId',
  );
  @override
  late final GeneratedColumn<int> alarmId = GeneratedColumn<int>(
    'alarm_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scheduledAtMeta = const VerificationMeta(
    'scheduledAt',
  );
  @override
  late final GeneratedColumn<DateTime> scheduledAt = GeneratedColumn<DateTime>(
    'scheduled_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firstRingAtMeta = const VerificationMeta(
    'firstRingAt',
  );
  @override
  late final GeneratedColumn<DateTime> firstRingAt = GeneratedColumn<DateTime>(
    'first_ring_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dismissedAtMeta = const VerificationMeta(
    'dismissedAt',
  );
  @override
  late final GeneratedColumn<DateTime> dismissedAt = GeneratedColumn<DateTime>(
    'dismissed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _methodMeta = const VerificationMeta('method');
  @override
  late final GeneratedColumn<String> method = GeneratedColumn<String>(
    'method',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _snoozeCountMeta = const VerificationMeta(
    'snoozeCount',
  );
  @override
  late final GeneratedColumn<int> snoozeCount = GeneratedColumn<int>(
    'snooze_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _missionFailuresMeta = const VerificationMeta(
    'missionFailures',
  );
  @override
  late final GeneratedColumn<int> missionFailures = GeneratedColumn<int>(
    'mission_failures',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _onTimeMeta = const VerificationMeta('onTime');
  @override
  late final GeneratedColumn<bool> onTime = GeneratedColumn<bool>(
    'on_time',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("on_time" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Alarm'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    alarmId,
    scheduledAt,
    firstRingAt,
    dismissedAt,
    method,
    snoozeCount,
    missionFailures,
    onTime,
    label,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'wake_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<WakeEventRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('alarm_id')) {
      context.handle(
        _alarmIdMeta,
        alarmId.isAcceptableOrUnknown(data['alarm_id']!, _alarmIdMeta),
      );
    } else if (isInserting) {
      context.missing(_alarmIdMeta);
    }
    if (data.containsKey('scheduled_at')) {
      context.handle(
        _scheduledAtMeta,
        scheduledAt.isAcceptableOrUnknown(
          data['scheduled_at']!,
          _scheduledAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scheduledAtMeta);
    }
    if (data.containsKey('first_ring_at')) {
      context.handle(
        _firstRingAtMeta,
        firstRingAt.isAcceptableOrUnknown(
          data['first_ring_at']!,
          _firstRingAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_firstRingAtMeta);
    }
    if (data.containsKey('dismissed_at')) {
      context.handle(
        _dismissedAtMeta,
        dismissedAt.isAcceptableOrUnknown(
          data['dismissed_at']!,
          _dismissedAtMeta,
        ),
      );
    }
    if (data.containsKey('method')) {
      context.handle(
        _methodMeta,
        method.isAcceptableOrUnknown(data['method']!, _methodMeta),
      );
    }
    if (data.containsKey('snooze_count')) {
      context.handle(
        _snoozeCountMeta,
        snoozeCount.isAcceptableOrUnknown(
          data['snooze_count']!,
          _snoozeCountMeta,
        ),
      );
    }
    if (data.containsKey('mission_failures')) {
      context.handle(
        _missionFailuresMeta,
        missionFailures.isAcceptableOrUnknown(
          data['mission_failures']!,
          _missionFailuresMeta,
        ),
      );
    }
    if (data.containsKey('on_time')) {
      context.handle(
        _onTimeMeta,
        onTime.isAcceptableOrUnknown(data['on_time']!, _onTimeMeta),
      );
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WakeEventRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WakeEventRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      alarmId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}alarm_id'],
      )!,
      scheduledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}scheduled_at'],
      )!,
      firstRingAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}first_ring_at'],
      )!,
      dismissedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}dismissed_at'],
      ),
      method: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}method'],
      ),
      snoozeCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}snooze_count'],
      )!,
      missionFailures: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}mission_failures'],
      )!,
      onTime: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}on_time'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
    );
  }

  @override
  $WakeEventsTable createAlias(String alias) {
    return $WakeEventsTable(attachedDatabase, alias);
  }
}

class WakeEventRow extends DataClass implements Insertable<WakeEventRow> {
  final int id;
  final int alarmId;
  final DateTime scheduledAt;
  final DateTime firstRingAt;
  final DateTime? dismissedAt;
  final String? method;
  final int snoozeCount;
  final int missionFailures;
  final bool onTime;
  final String label;
  const WakeEventRow({
    required this.id,
    required this.alarmId,
    required this.scheduledAt,
    required this.firstRingAt,
    this.dismissedAt,
    this.method,
    required this.snoozeCount,
    required this.missionFailures,
    required this.onTime,
    required this.label,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['alarm_id'] = Variable<int>(alarmId);
    map['scheduled_at'] = Variable<DateTime>(scheduledAt);
    map['first_ring_at'] = Variable<DateTime>(firstRingAt);
    if (!nullToAbsent || dismissedAt != null) {
      map['dismissed_at'] = Variable<DateTime>(dismissedAt);
    }
    if (!nullToAbsent || method != null) {
      map['method'] = Variable<String>(method);
    }
    map['snooze_count'] = Variable<int>(snoozeCount);
    map['mission_failures'] = Variable<int>(missionFailures);
    map['on_time'] = Variable<bool>(onTime);
    map['label'] = Variable<String>(label);
    return map;
  }

  WakeEventsCompanion toCompanion(bool nullToAbsent) {
    return WakeEventsCompanion(
      id: Value(id),
      alarmId: Value(alarmId),
      scheduledAt: Value(scheduledAt),
      firstRingAt: Value(firstRingAt),
      dismissedAt: dismissedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(dismissedAt),
      method: method == null && nullToAbsent
          ? const Value.absent()
          : Value(method),
      snoozeCount: Value(snoozeCount),
      missionFailures: Value(missionFailures),
      onTime: Value(onTime),
      label: Value(label),
    );
  }

  factory WakeEventRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WakeEventRow(
      id: serializer.fromJson<int>(json['id']),
      alarmId: serializer.fromJson<int>(json['alarmId']),
      scheduledAt: serializer.fromJson<DateTime>(json['scheduledAt']),
      firstRingAt: serializer.fromJson<DateTime>(json['firstRingAt']),
      dismissedAt: serializer.fromJson<DateTime?>(json['dismissedAt']),
      method: serializer.fromJson<String?>(json['method']),
      snoozeCount: serializer.fromJson<int>(json['snoozeCount']),
      missionFailures: serializer.fromJson<int>(json['missionFailures']),
      onTime: serializer.fromJson<bool>(json['onTime']),
      label: serializer.fromJson<String>(json['label']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'alarmId': serializer.toJson<int>(alarmId),
      'scheduledAt': serializer.toJson<DateTime>(scheduledAt),
      'firstRingAt': serializer.toJson<DateTime>(firstRingAt),
      'dismissedAt': serializer.toJson<DateTime?>(dismissedAt),
      'method': serializer.toJson<String?>(method),
      'snoozeCount': serializer.toJson<int>(snoozeCount),
      'missionFailures': serializer.toJson<int>(missionFailures),
      'onTime': serializer.toJson<bool>(onTime),
      'label': serializer.toJson<String>(label),
    };
  }

  WakeEventRow copyWith({
    int? id,
    int? alarmId,
    DateTime? scheduledAt,
    DateTime? firstRingAt,
    Value<DateTime?> dismissedAt = const Value.absent(),
    Value<String?> method = const Value.absent(),
    int? snoozeCount,
    int? missionFailures,
    bool? onTime,
    String? label,
  }) => WakeEventRow(
    id: id ?? this.id,
    alarmId: alarmId ?? this.alarmId,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    firstRingAt: firstRingAt ?? this.firstRingAt,
    dismissedAt: dismissedAt.present ? dismissedAt.value : this.dismissedAt,
    method: method.present ? method.value : this.method,
    snoozeCount: snoozeCount ?? this.snoozeCount,
    missionFailures: missionFailures ?? this.missionFailures,
    onTime: onTime ?? this.onTime,
    label: label ?? this.label,
  );
  WakeEventRow copyWithCompanion(WakeEventsCompanion data) {
    return WakeEventRow(
      id: data.id.present ? data.id.value : this.id,
      alarmId: data.alarmId.present ? data.alarmId.value : this.alarmId,
      scheduledAt: data.scheduledAt.present
          ? data.scheduledAt.value
          : this.scheduledAt,
      firstRingAt: data.firstRingAt.present
          ? data.firstRingAt.value
          : this.firstRingAt,
      dismissedAt: data.dismissedAt.present
          ? data.dismissedAt.value
          : this.dismissedAt,
      method: data.method.present ? data.method.value : this.method,
      snoozeCount: data.snoozeCount.present
          ? data.snoozeCount.value
          : this.snoozeCount,
      missionFailures: data.missionFailures.present
          ? data.missionFailures.value
          : this.missionFailures,
      onTime: data.onTime.present ? data.onTime.value : this.onTime,
      label: data.label.present ? data.label.value : this.label,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WakeEventRow(')
          ..write('id: $id, ')
          ..write('alarmId: $alarmId, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('firstRingAt: $firstRingAt, ')
          ..write('dismissedAt: $dismissedAt, ')
          ..write('method: $method, ')
          ..write('snoozeCount: $snoozeCount, ')
          ..write('missionFailures: $missionFailures, ')
          ..write('onTime: $onTime, ')
          ..write('label: $label')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    alarmId,
    scheduledAt,
    firstRingAt,
    dismissedAt,
    method,
    snoozeCount,
    missionFailures,
    onTime,
    label,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WakeEventRow &&
          other.id == this.id &&
          other.alarmId == this.alarmId &&
          other.scheduledAt == this.scheduledAt &&
          other.firstRingAt == this.firstRingAt &&
          other.dismissedAt == this.dismissedAt &&
          other.method == this.method &&
          other.snoozeCount == this.snoozeCount &&
          other.missionFailures == this.missionFailures &&
          other.onTime == this.onTime &&
          other.label == this.label);
}

class WakeEventsCompanion extends UpdateCompanion<WakeEventRow> {
  final Value<int> id;
  final Value<int> alarmId;
  final Value<DateTime> scheduledAt;
  final Value<DateTime> firstRingAt;
  final Value<DateTime?> dismissedAt;
  final Value<String?> method;
  final Value<int> snoozeCount;
  final Value<int> missionFailures;
  final Value<bool> onTime;
  final Value<String> label;
  const WakeEventsCompanion({
    this.id = const Value.absent(),
    this.alarmId = const Value.absent(),
    this.scheduledAt = const Value.absent(),
    this.firstRingAt = const Value.absent(),
    this.dismissedAt = const Value.absent(),
    this.method = const Value.absent(),
    this.snoozeCount = const Value.absent(),
    this.missionFailures = const Value.absent(),
    this.onTime = const Value.absent(),
    this.label = const Value.absent(),
  });
  WakeEventsCompanion.insert({
    this.id = const Value.absent(),
    required int alarmId,
    required DateTime scheduledAt,
    required DateTime firstRingAt,
    this.dismissedAt = const Value.absent(),
    this.method = const Value.absent(),
    this.snoozeCount = const Value.absent(),
    this.missionFailures = const Value.absent(),
    this.onTime = const Value.absent(),
    this.label = const Value.absent(),
  }) : alarmId = Value(alarmId),
       scheduledAt = Value(scheduledAt),
       firstRingAt = Value(firstRingAt);
  static Insertable<WakeEventRow> custom({
    Expression<int>? id,
    Expression<int>? alarmId,
    Expression<DateTime>? scheduledAt,
    Expression<DateTime>? firstRingAt,
    Expression<DateTime>? dismissedAt,
    Expression<String>? method,
    Expression<int>? snoozeCount,
    Expression<int>? missionFailures,
    Expression<bool>? onTime,
    Expression<String>? label,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (alarmId != null) 'alarm_id': alarmId,
      if (scheduledAt != null) 'scheduled_at': scheduledAt,
      if (firstRingAt != null) 'first_ring_at': firstRingAt,
      if (dismissedAt != null) 'dismissed_at': dismissedAt,
      if (method != null) 'method': method,
      if (snoozeCount != null) 'snooze_count': snoozeCount,
      if (missionFailures != null) 'mission_failures': missionFailures,
      if (onTime != null) 'on_time': onTime,
      if (label != null) 'label': label,
    });
  }

  WakeEventsCompanion copyWith({
    Value<int>? id,
    Value<int>? alarmId,
    Value<DateTime>? scheduledAt,
    Value<DateTime>? firstRingAt,
    Value<DateTime?>? dismissedAt,
    Value<String?>? method,
    Value<int>? snoozeCount,
    Value<int>? missionFailures,
    Value<bool>? onTime,
    Value<String>? label,
  }) {
    return WakeEventsCompanion(
      id: id ?? this.id,
      alarmId: alarmId ?? this.alarmId,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      firstRingAt: firstRingAt ?? this.firstRingAt,
      dismissedAt: dismissedAt ?? this.dismissedAt,
      method: method ?? this.method,
      snoozeCount: snoozeCount ?? this.snoozeCount,
      missionFailures: missionFailures ?? this.missionFailures,
      onTime: onTime ?? this.onTime,
      label: label ?? this.label,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (alarmId.present) {
      map['alarm_id'] = Variable<int>(alarmId.value);
    }
    if (scheduledAt.present) {
      map['scheduled_at'] = Variable<DateTime>(scheduledAt.value);
    }
    if (firstRingAt.present) {
      map['first_ring_at'] = Variable<DateTime>(firstRingAt.value);
    }
    if (dismissedAt.present) {
      map['dismissed_at'] = Variable<DateTime>(dismissedAt.value);
    }
    if (method.present) {
      map['method'] = Variable<String>(method.value);
    }
    if (snoozeCount.present) {
      map['snooze_count'] = Variable<int>(snoozeCount.value);
    }
    if (missionFailures.present) {
      map['mission_failures'] = Variable<int>(missionFailures.value);
    }
    if (onTime.present) {
      map['on_time'] = Variable<bool>(onTime.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WakeEventsCompanion(')
          ..write('id: $id, ')
          ..write('alarmId: $alarmId, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('firstRingAt: $firstRingAt, ')
          ..write('dismissedAt: $dismissedAt, ')
          ..write('method: $method, ')
          ..write('snoozeCount: $snoozeCount, ')
          ..write('missionFailures: $missionFailures, ')
          ..write('onTime: $onTime, ')
          ..write('label: $label')
          ..write(')'))
        .toString();
  }
}

abstract class _$RiseDatabase extends GeneratedDatabase {
  _$RiseDatabase(QueryExecutor e) : super(e);
  $RiseDatabaseManager get managers => $RiseDatabaseManager(this);
  late final $AlarmsTable alarms = $AlarmsTable(this);
  late final $WakeEventsTable wakeEvents = $WakeEventsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [alarms, wakeEvents];
}

typedef $$AlarmsTableCreateCompanionBuilder =
    AlarmsCompanion Function({
      Value<int> id,
      required int hour,
      required int minute,
      Value<String> days,
      Value<bool> enabled,
      Value<String> label,
      Value<String> soundAsset,
      Value<bool> vibrate,
      Value<DateTime?> lastDismissedAt,
      Value<String> mission,
      Value<String> missionDiff,
    });
typedef $$AlarmsTableUpdateCompanionBuilder =
    AlarmsCompanion Function({
      Value<int> id,
      Value<int> hour,
      Value<int> minute,
      Value<String> days,
      Value<bool> enabled,
      Value<String> label,
      Value<String> soundAsset,
      Value<bool> vibrate,
      Value<DateTime?> lastDismissedAt,
      Value<String> mission,
      Value<String> missionDiff,
    });

class $$AlarmsTableFilterComposer
    extends Composer<_$RiseDatabase, $AlarmsTable> {
  $$AlarmsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hour => $composableBuilder(
    column: $table.hour,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minute => $composableBuilder(
    column: $table.minute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get days => $composableBuilder(
    column: $table.days,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get soundAsset => $composableBuilder(
    column: $table.soundAsset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get vibrate => $composableBuilder(
    column: $table.vibrate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastDismissedAt => $composableBuilder(
    column: $table.lastDismissedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mission => $composableBuilder(
    column: $table.mission,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get missionDiff => $composableBuilder(
    column: $table.missionDiff,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AlarmsTableOrderingComposer
    extends Composer<_$RiseDatabase, $AlarmsTable> {
  $$AlarmsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hour => $composableBuilder(
    column: $table.hour,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minute => $composableBuilder(
    column: $table.minute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get days => $composableBuilder(
    column: $table.days,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get soundAsset => $composableBuilder(
    column: $table.soundAsset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get vibrate => $composableBuilder(
    column: $table.vibrate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastDismissedAt => $composableBuilder(
    column: $table.lastDismissedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mission => $composableBuilder(
    column: $table.mission,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get missionDiff => $composableBuilder(
    column: $table.missionDiff,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AlarmsTableAnnotationComposer
    extends Composer<_$RiseDatabase, $AlarmsTable> {
  $$AlarmsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get hour =>
      $composableBuilder(column: $table.hour, builder: (column) => column);

  GeneratedColumn<int> get minute =>
      $composableBuilder(column: $table.minute, builder: (column) => column);

  GeneratedColumn<String> get days =>
      $composableBuilder(column: $table.days, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get soundAsset => $composableBuilder(
    column: $table.soundAsset,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get vibrate =>
      $composableBuilder(column: $table.vibrate, builder: (column) => column);

  GeneratedColumn<DateTime> get lastDismissedAt => $composableBuilder(
    column: $table.lastDismissedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mission =>
      $composableBuilder(column: $table.mission, builder: (column) => column);

  GeneratedColumn<String> get missionDiff => $composableBuilder(
    column: $table.missionDiff,
    builder: (column) => column,
  );
}

class $$AlarmsTableTableManager
    extends
        RootTableManager<
          _$RiseDatabase,
          $AlarmsTable,
          AlarmRow,
          $$AlarmsTableFilterComposer,
          $$AlarmsTableOrderingComposer,
          $$AlarmsTableAnnotationComposer,
          $$AlarmsTableCreateCompanionBuilder,
          $$AlarmsTableUpdateCompanionBuilder,
          (AlarmRow, BaseReferences<_$RiseDatabase, $AlarmsTable, AlarmRow>),
          AlarmRow,
          PrefetchHooks Function()
        > {
  $$AlarmsTableTableManager(_$RiseDatabase db, $AlarmsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlarmsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlarmsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AlarmsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> hour = const Value.absent(),
                Value<int> minute = const Value.absent(),
                Value<String> days = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String> soundAsset = const Value.absent(),
                Value<bool> vibrate = const Value.absent(),
                Value<DateTime?> lastDismissedAt = const Value.absent(),
                Value<String> mission = const Value.absent(),
                Value<String> missionDiff = const Value.absent(),
              }) => AlarmsCompanion(
                id: id,
                hour: hour,
                minute: minute,
                days: days,
                enabled: enabled,
                label: label,
                soundAsset: soundAsset,
                vibrate: vibrate,
                lastDismissedAt: lastDismissedAt,
                mission: mission,
                missionDiff: missionDiff,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int hour,
                required int minute,
                Value<String> days = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String> soundAsset = const Value.absent(),
                Value<bool> vibrate = const Value.absent(),
                Value<DateTime?> lastDismissedAt = const Value.absent(),
                Value<String> mission = const Value.absent(),
                Value<String> missionDiff = const Value.absent(),
              }) => AlarmsCompanion.insert(
                id: id,
                hour: hour,
                minute: minute,
                days: days,
                enabled: enabled,
                label: label,
                soundAsset: soundAsset,
                vibrate: vibrate,
                lastDismissedAt: lastDismissedAt,
                mission: mission,
                missionDiff: missionDiff,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AlarmsTableProcessedTableManager =
    ProcessedTableManager<
      _$RiseDatabase,
      $AlarmsTable,
      AlarmRow,
      $$AlarmsTableFilterComposer,
      $$AlarmsTableOrderingComposer,
      $$AlarmsTableAnnotationComposer,
      $$AlarmsTableCreateCompanionBuilder,
      $$AlarmsTableUpdateCompanionBuilder,
      (AlarmRow, BaseReferences<_$RiseDatabase, $AlarmsTable, AlarmRow>),
      AlarmRow,
      PrefetchHooks Function()
    >;
typedef $$WakeEventsTableCreateCompanionBuilder =
    WakeEventsCompanion Function({
      Value<int> id,
      required int alarmId,
      required DateTime scheduledAt,
      required DateTime firstRingAt,
      Value<DateTime?> dismissedAt,
      Value<String?> method,
      Value<int> snoozeCount,
      Value<int> missionFailures,
      Value<bool> onTime,
      Value<String> label,
    });
typedef $$WakeEventsTableUpdateCompanionBuilder =
    WakeEventsCompanion Function({
      Value<int> id,
      Value<int> alarmId,
      Value<DateTime> scheduledAt,
      Value<DateTime> firstRingAt,
      Value<DateTime?> dismissedAt,
      Value<String?> method,
      Value<int> snoozeCount,
      Value<int> missionFailures,
      Value<bool> onTime,
      Value<String> label,
    });

class $$WakeEventsTableFilterComposer
    extends Composer<_$RiseDatabase, $WakeEventsTable> {
  $$WakeEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get alarmId => $composableBuilder(
    column: $table.alarmId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get firstRingAt => $composableBuilder(
    column: $table.firstRingAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dismissedAt => $composableBuilder(
    column: $table.dismissedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get snoozeCount => $composableBuilder(
    column: $table.snoozeCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get missionFailures => $composableBuilder(
    column: $table.missionFailures,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get onTime => $composableBuilder(
    column: $table.onTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WakeEventsTableOrderingComposer
    extends Composer<_$RiseDatabase, $WakeEventsTable> {
  $$WakeEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get alarmId => $composableBuilder(
    column: $table.alarmId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get firstRingAt => $composableBuilder(
    column: $table.firstRingAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dismissedAt => $composableBuilder(
    column: $table.dismissedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get snoozeCount => $composableBuilder(
    column: $table.snoozeCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get missionFailures => $composableBuilder(
    column: $table.missionFailures,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get onTime => $composableBuilder(
    column: $table.onTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WakeEventsTableAnnotationComposer
    extends Composer<_$RiseDatabase, $WakeEventsTable> {
  $$WakeEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get alarmId =>
      $composableBuilder(column: $table.alarmId, builder: (column) => column);

  GeneratedColumn<DateTime> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get firstRingAt => $composableBuilder(
    column: $table.firstRingAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get dismissedAt => $composableBuilder(
    column: $table.dismissedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get method =>
      $composableBuilder(column: $table.method, builder: (column) => column);

  GeneratedColumn<int> get snoozeCount => $composableBuilder(
    column: $table.snoozeCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get missionFailures => $composableBuilder(
    column: $table.missionFailures,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get onTime =>
      $composableBuilder(column: $table.onTime, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);
}

class $$WakeEventsTableTableManager
    extends
        RootTableManager<
          _$RiseDatabase,
          $WakeEventsTable,
          WakeEventRow,
          $$WakeEventsTableFilterComposer,
          $$WakeEventsTableOrderingComposer,
          $$WakeEventsTableAnnotationComposer,
          $$WakeEventsTableCreateCompanionBuilder,
          $$WakeEventsTableUpdateCompanionBuilder,
          (
            WakeEventRow,
            BaseReferences<_$RiseDatabase, $WakeEventsTable, WakeEventRow>,
          ),
          WakeEventRow,
          PrefetchHooks Function()
        > {
  $$WakeEventsTableTableManager(_$RiseDatabase db, $WakeEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WakeEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WakeEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WakeEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> alarmId = const Value.absent(),
                Value<DateTime> scheduledAt = const Value.absent(),
                Value<DateTime> firstRingAt = const Value.absent(),
                Value<DateTime?> dismissedAt = const Value.absent(),
                Value<String?> method = const Value.absent(),
                Value<int> snoozeCount = const Value.absent(),
                Value<int> missionFailures = const Value.absent(),
                Value<bool> onTime = const Value.absent(),
                Value<String> label = const Value.absent(),
              }) => WakeEventsCompanion(
                id: id,
                alarmId: alarmId,
                scheduledAt: scheduledAt,
                firstRingAt: firstRingAt,
                dismissedAt: dismissedAt,
                method: method,
                snoozeCount: snoozeCount,
                missionFailures: missionFailures,
                onTime: onTime,
                label: label,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int alarmId,
                required DateTime scheduledAt,
                required DateTime firstRingAt,
                Value<DateTime?> dismissedAt = const Value.absent(),
                Value<String?> method = const Value.absent(),
                Value<int> snoozeCount = const Value.absent(),
                Value<int> missionFailures = const Value.absent(),
                Value<bool> onTime = const Value.absent(),
                Value<String> label = const Value.absent(),
              }) => WakeEventsCompanion.insert(
                id: id,
                alarmId: alarmId,
                scheduledAt: scheduledAt,
                firstRingAt: firstRingAt,
                dismissedAt: dismissedAt,
                method: method,
                snoozeCount: snoozeCount,
                missionFailures: missionFailures,
                onTime: onTime,
                label: label,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WakeEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$RiseDatabase,
      $WakeEventsTable,
      WakeEventRow,
      $$WakeEventsTableFilterComposer,
      $$WakeEventsTableOrderingComposer,
      $$WakeEventsTableAnnotationComposer,
      $$WakeEventsTableCreateCompanionBuilder,
      $$WakeEventsTableUpdateCompanionBuilder,
      (
        WakeEventRow,
        BaseReferences<_$RiseDatabase, $WakeEventsTable, WakeEventRow>,
      ),
      WakeEventRow,
      PrefetchHooks Function()
    >;

class $RiseDatabaseManager {
  final _$RiseDatabase _db;
  $RiseDatabaseManager(this._db);
  $$AlarmsTableTableManager get alarms =>
      $$AlarmsTableTableManager(_db, _db.alarms);
  $$WakeEventsTableTableManager get wakeEvents =>
      $$WakeEventsTableTableManager(_db, _db.wakeEvents);
}
