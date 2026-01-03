// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pairing_database.dart';

// ignore_for_file: type=lint
class $PairedDevicesTable extends PairedDevices
    with TableInfo<$PairedDevicesTable, PairedDevice> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PairedDevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta =
      const VerificationMeta('deviceId');
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
      'device_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _deviceNameMeta =
      const VerificationMeta('deviceName');
  @override
  late final GeneratedColumn<String> deviceName = GeneratedColumn<String>(
      'device_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sessionTokenMeta =
      const VerificationMeta('sessionToken');
  @override
  late final GeneratedColumn<String> sessionToken = GeneratedColumn<String>(
      'session_token', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _pairedAtMeta =
      const VerificationMeta('pairedAt');
  @override
  late final GeneratedColumn<DateTime> pairedAt = GeneratedColumn<DateTime>(
      'paired_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _lastConnectedAtMeta =
      const VerificationMeta('lastConnectedAt');
  @override
  late final GeneratedColumn<DateTime> lastConnectedAt =
      GeneratedColumn<DateTime>('last_connected_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _deviceTypeMeta =
      const VerificationMeta('deviceType');
  @override
  late final GeneratedColumn<String> deviceType = GeneratedColumn<String>(
      'device_type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('mobile'));
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
  @override
  List<GeneratedColumn> get $columns => [
        deviceId,
        deviceName,
        sessionToken,
        pairedAt,
        lastConnectedAt,
        deviceType,
        isActive
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'paired_devices';
  @override
  VerificationContext validateIntegrity(Insertable<PairedDevice> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(_deviceIdMeta,
          deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta));
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('device_name')) {
      context.handle(
          _deviceNameMeta,
          deviceName.isAcceptableOrUnknown(
              data['device_name']!, _deviceNameMeta));
    } else if (isInserting) {
      context.missing(_deviceNameMeta);
    }
    if (data.containsKey('session_token')) {
      context.handle(
          _sessionTokenMeta,
          sessionToken.isAcceptableOrUnknown(
              data['session_token']!, _sessionTokenMeta));
    } else if (isInserting) {
      context.missing(_sessionTokenMeta);
    }
    if (data.containsKey('paired_at')) {
      context.handle(_pairedAtMeta,
          pairedAt.isAcceptableOrUnknown(data['paired_at']!, _pairedAtMeta));
    } else if (isInserting) {
      context.missing(_pairedAtMeta);
    }
    if (data.containsKey('last_connected_at')) {
      context.handle(
          _lastConnectedAtMeta,
          lastConnectedAt.isAcceptableOrUnknown(
              data['last_connected_at']!, _lastConnectedAtMeta));
    }
    if (data.containsKey('device_type')) {
      context.handle(
          _deviceTypeMeta,
          deviceType.isAcceptableOrUnknown(
              data['device_type']!, _deviceTypeMeta));
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deviceId};
  @override
  PairedDevice map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PairedDevice(
      deviceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}device_id'])!,
      deviceName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}device_name'])!,
      sessionToken: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}session_token'])!,
      pairedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}paired_at'])!,
      lastConnectedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_connected_at']),
      deviceType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}device_type'])!,
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
    );
  }

  @override
  $PairedDevicesTable createAlias(String alias) {
    return $PairedDevicesTable(attachedDatabase, alias);
  }
}

class PairedDevice extends DataClass implements Insertable<PairedDevice> {
  /// Unique device identifier (UUID)
  final String deviceId;

  /// Device name provided during pairing (e.g., "John's iPhone")
  final String deviceName;

  /// Secure session token (32 bytes, hex-encoded)
  final String sessionToken;

  /// Timestamp when this device was paired
  final DateTime pairedAt;

  /// Last time this device connected successfully
  final DateTime? lastConnectedAt;

  /// Device type (e.g., "mobile", "tablet", "desktop")
  final String deviceType;

  /// Whether this device is currently active (not revoked)
  final bool isActive;
  const PairedDevice(
      {required this.deviceId,
      required this.deviceName,
      required this.sessionToken,
      required this.pairedAt,
      this.lastConnectedAt,
      required this.deviceType,
      required this.isActive});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_id'] = Variable<String>(deviceId);
    map['device_name'] = Variable<String>(deviceName);
    map['session_token'] = Variable<String>(sessionToken);
    map['paired_at'] = Variable<DateTime>(pairedAt);
    if (!nullToAbsent || lastConnectedAt != null) {
      map['last_connected_at'] = Variable<DateTime>(lastConnectedAt);
    }
    map['device_type'] = Variable<String>(deviceType);
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  PairedDevicesCompanion toCompanion(bool nullToAbsent) {
    return PairedDevicesCompanion(
      deviceId: Value(deviceId),
      deviceName: Value(deviceName),
      sessionToken: Value(sessionToken),
      pairedAt: Value(pairedAt),
      lastConnectedAt: lastConnectedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastConnectedAt),
      deviceType: Value(deviceType),
      isActive: Value(isActive),
    );
  }

  factory PairedDevice.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PairedDevice(
      deviceId: serializer.fromJson<String>(json['deviceId']),
      deviceName: serializer.fromJson<String>(json['deviceName']),
      sessionToken: serializer.fromJson<String>(json['sessionToken']),
      pairedAt: serializer.fromJson<DateTime>(json['pairedAt']),
      lastConnectedAt: serializer.fromJson<DateTime?>(json['lastConnectedAt']),
      deviceType: serializer.fromJson<String>(json['deviceType']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String>(deviceId),
      'deviceName': serializer.toJson<String>(deviceName),
      'sessionToken': serializer.toJson<String>(sessionToken),
      'pairedAt': serializer.toJson<DateTime>(pairedAt),
      'lastConnectedAt': serializer.toJson<DateTime?>(lastConnectedAt),
      'deviceType': serializer.toJson<String>(deviceType),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  PairedDevice copyWith(
          {String? deviceId,
          String? deviceName,
          String? sessionToken,
          DateTime? pairedAt,
          Value<DateTime?> lastConnectedAt = const Value.absent(),
          String? deviceType,
          bool? isActive}) =>
      PairedDevice(
        deviceId: deviceId ?? this.deviceId,
        deviceName: deviceName ?? this.deviceName,
        sessionToken: sessionToken ?? this.sessionToken,
        pairedAt: pairedAt ?? this.pairedAt,
        lastConnectedAt: lastConnectedAt.present
            ? lastConnectedAt.value
            : this.lastConnectedAt,
        deviceType: deviceType ?? this.deviceType,
        isActive: isActive ?? this.isActive,
      );
  PairedDevice copyWithCompanion(PairedDevicesCompanion data) {
    return PairedDevice(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      deviceName:
          data.deviceName.present ? data.deviceName.value : this.deviceName,
      sessionToken: data.sessionToken.present
          ? data.sessionToken.value
          : this.sessionToken,
      pairedAt: data.pairedAt.present ? data.pairedAt.value : this.pairedAt,
      lastConnectedAt: data.lastConnectedAt.present
          ? data.lastConnectedAt.value
          : this.lastConnectedAt,
      deviceType:
          data.deviceType.present ? data.deviceType.value : this.deviceType,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PairedDevice(')
          ..write('deviceId: $deviceId, ')
          ..write('deviceName: $deviceName, ')
          ..write('sessionToken: $sessionToken, ')
          ..write('pairedAt: $pairedAt, ')
          ..write('lastConnectedAt: $lastConnectedAt, ')
          ..write('deviceType: $deviceType, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(deviceId, deviceName, sessionToken, pairedAt,
      lastConnectedAt, deviceType, isActive);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PairedDevice &&
          other.deviceId == this.deviceId &&
          other.deviceName == this.deviceName &&
          other.sessionToken == this.sessionToken &&
          other.pairedAt == this.pairedAt &&
          other.lastConnectedAt == this.lastConnectedAt &&
          other.deviceType == this.deviceType &&
          other.isActive == this.isActive);
}

class PairedDevicesCompanion extends UpdateCompanion<PairedDevice> {
  final Value<String> deviceId;
  final Value<String> deviceName;
  final Value<String> sessionToken;
  final Value<DateTime> pairedAt;
  final Value<DateTime?> lastConnectedAt;
  final Value<String> deviceType;
  final Value<bool> isActive;
  final Value<int> rowid;
  const PairedDevicesCompanion({
    this.deviceId = const Value.absent(),
    this.deviceName = const Value.absent(),
    this.sessionToken = const Value.absent(),
    this.pairedAt = const Value.absent(),
    this.lastConnectedAt = const Value.absent(),
    this.deviceType = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PairedDevicesCompanion.insert({
    required String deviceId,
    required String deviceName,
    required String sessionToken,
    required DateTime pairedAt,
    this.lastConnectedAt = const Value.absent(),
    this.deviceType = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : deviceId = Value(deviceId),
        deviceName = Value(deviceName),
        sessionToken = Value(sessionToken),
        pairedAt = Value(pairedAt);
  static Insertable<PairedDevice> custom({
    Expression<String>? deviceId,
    Expression<String>? deviceName,
    Expression<String>? sessionToken,
    Expression<DateTime>? pairedAt,
    Expression<DateTime>? lastConnectedAt,
    Expression<String>? deviceType,
    Expression<bool>? isActive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (deviceName != null) 'device_name': deviceName,
      if (sessionToken != null) 'session_token': sessionToken,
      if (pairedAt != null) 'paired_at': pairedAt,
      if (lastConnectedAt != null) 'last_connected_at': lastConnectedAt,
      if (deviceType != null) 'device_type': deviceType,
      if (isActive != null) 'is_active': isActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PairedDevicesCompanion copyWith(
      {Value<String>? deviceId,
      Value<String>? deviceName,
      Value<String>? sessionToken,
      Value<DateTime>? pairedAt,
      Value<DateTime?>? lastConnectedAt,
      Value<String>? deviceType,
      Value<bool>? isActive,
      Value<int>? rowid}) {
    return PairedDevicesCompanion(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      sessionToken: sessionToken ?? this.sessionToken,
      pairedAt: pairedAt ?? this.pairedAt,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      deviceType: deviceType ?? this.deviceType,
      isActive: isActive ?? this.isActive,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (deviceName.present) {
      map['device_name'] = Variable<String>(deviceName.value);
    }
    if (sessionToken.present) {
      map['session_token'] = Variable<String>(sessionToken.value);
    }
    if (pairedAt.present) {
      map['paired_at'] = Variable<DateTime>(pairedAt.value);
    }
    if (lastConnectedAt.present) {
      map['last_connected_at'] = Variable<DateTime>(lastConnectedAt.value);
    }
    if (deviceType.present) {
      map['device_type'] = Variable<String>(deviceType.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PairedDevicesCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('deviceName: $deviceName, ')
          ..write('sessionToken: $sessionToken, ')
          ..write('pairedAt: $pairedAt, ')
          ..write('lastConnectedAt: $lastConnectedAt, ')
          ..write('deviceType: $deviceType, ')
          ..write('isActive: $isActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PairingSessionsTable extends PairingSessions
    with TableInfo<$PairingSessionsTable, PairingSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PairingSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _pairingCodeMeta =
      const VerificationMeta('pairingCode');
  @override
  late final GeneratedColumn<String> pairingCode = GeneratedColumn<String>(
      'pairing_code', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _sessionTokenMeta =
      const VerificationMeta('sessionToken');
  @override
  late final GeneratedColumn<String> sessionToken = GeneratedColumn<String>(
      'session_token', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _expiresAtMeta =
      const VerificationMeta('expiresAt');
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
      'expires_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _isUsedMeta = const VerificationMeta('isUsed');
  @override
  late final GeneratedColumn<bool> isUsed = GeneratedColumn<bool>(
      'is_used', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_used" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns =>
      [id, pairingCode, sessionToken, createdAt, expiresAt, isUsed];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pairing_sessions';
  @override
  VerificationContext validateIntegrity(Insertable<PairingSession> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('pairing_code')) {
      context.handle(
          _pairingCodeMeta,
          pairingCode.isAcceptableOrUnknown(
              data['pairing_code']!, _pairingCodeMeta));
    } else if (isInserting) {
      context.missing(_pairingCodeMeta);
    }
    if (data.containsKey('session_token')) {
      context.handle(
          _sessionTokenMeta,
          sessionToken.isAcceptableOrUnknown(
              data['session_token']!, _sessionTokenMeta));
    } else if (isInserting) {
      context.missing(_sessionTokenMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('expires_at')) {
      context.handle(_expiresAtMeta,
          expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta));
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
    }
    if (data.containsKey('is_used')) {
      context.handle(_isUsedMeta,
          isUsed.isAcceptableOrUnknown(data['is_used']!, _isUsedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PairingSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PairingSession(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      pairingCode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}pairing_code'])!,
      sessionToken: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}session_token'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      expiresAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}expires_at'])!,
      isUsed: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_used'])!,
    );
  }

  @override
  $PairingSessionsTable createAlias(String alias) {
    return $PairingSessionsTable(attachedDatabase, alias);
  }
}

class PairingSession extends DataClass implements Insertable<PairingSession> {
  /// Unique session identifier
  final int id;

  /// User-friendly pairing code (e.g., "STAR-1234")
  final String pairingCode;

  /// Full session token that will be assigned when pairing completes
  final String sessionToken;

  /// Timestamp when this pairing session was created
  final DateTime createdAt;

  /// Timestamp when this pairing session expires (typically createdAt + 5 minutes)
  final DateTime expiresAt;

  /// Whether this pairing session has been used
  final bool isUsed;
  const PairingSession(
      {required this.id,
      required this.pairingCode,
      required this.sessionToken,
      required this.createdAt,
      required this.expiresAt,
      required this.isUsed});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['pairing_code'] = Variable<String>(pairingCode);
    map['session_token'] = Variable<String>(sessionToken);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['expires_at'] = Variable<DateTime>(expiresAt);
    map['is_used'] = Variable<bool>(isUsed);
    return map;
  }

  PairingSessionsCompanion toCompanion(bool nullToAbsent) {
    return PairingSessionsCompanion(
      id: Value(id),
      pairingCode: Value(pairingCode),
      sessionToken: Value(sessionToken),
      createdAt: Value(createdAt),
      expiresAt: Value(expiresAt),
      isUsed: Value(isUsed),
    );
  }

  factory PairingSession.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PairingSession(
      id: serializer.fromJson<int>(json['id']),
      pairingCode: serializer.fromJson<String>(json['pairingCode']),
      sessionToken: serializer.fromJson<String>(json['sessionToken']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      expiresAt: serializer.fromJson<DateTime>(json['expiresAt']),
      isUsed: serializer.fromJson<bool>(json['isUsed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'pairingCode': serializer.toJson<String>(pairingCode),
      'sessionToken': serializer.toJson<String>(sessionToken),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'expiresAt': serializer.toJson<DateTime>(expiresAt),
      'isUsed': serializer.toJson<bool>(isUsed),
    };
  }

  PairingSession copyWith(
          {int? id,
          String? pairingCode,
          String? sessionToken,
          DateTime? createdAt,
          DateTime? expiresAt,
          bool? isUsed}) =>
      PairingSession(
        id: id ?? this.id,
        pairingCode: pairingCode ?? this.pairingCode,
        sessionToken: sessionToken ?? this.sessionToken,
        createdAt: createdAt ?? this.createdAt,
        expiresAt: expiresAt ?? this.expiresAt,
        isUsed: isUsed ?? this.isUsed,
      );
  PairingSession copyWithCompanion(PairingSessionsCompanion data) {
    return PairingSession(
      id: data.id.present ? data.id.value : this.id,
      pairingCode:
          data.pairingCode.present ? data.pairingCode.value : this.pairingCode,
      sessionToken: data.sessionToken.present
          ? data.sessionToken.value
          : this.sessionToken,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      isUsed: data.isUsed.present ? data.isUsed.value : this.isUsed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PairingSession(')
          ..write('id: $id, ')
          ..write('pairingCode: $pairingCode, ')
          ..write('sessionToken: $sessionToken, ')
          ..write('createdAt: $createdAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('isUsed: $isUsed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, pairingCode, sessionToken, createdAt, expiresAt, isUsed);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PairingSession &&
          other.id == this.id &&
          other.pairingCode == this.pairingCode &&
          other.sessionToken == this.sessionToken &&
          other.createdAt == this.createdAt &&
          other.expiresAt == this.expiresAt &&
          other.isUsed == this.isUsed);
}

class PairingSessionsCompanion extends UpdateCompanion<PairingSession> {
  final Value<int> id;
  final Value<String> pairingCode;
  final Value<String> sessionToken;
  final Value<DateTime> createdAt;
  final Value<DateTime> expiresAt;
  final Value<bool> isUsed;
  const PairingSessionsCompanion({
    this.id = const Value.absent(),
    this.pairingCode = const Value.absent(),
    this.sessionToken = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.isUsed = const Value.absent(),
  });
  PairingSessionsCompanion.insert({
    this.id = const Value.absent(),
    required String pairingCode,
    required String sessionToken,
    required DateTime createdAt,
    required DateTime expiresAt,
    this.isUsed = const Value.absent(),
  })  : pairingCode = Value(pairingCode),
        sessionToken = Value(sessionToken),
        createdAt = Value(createdAt),
        expiresAt = Value(expiresAt);
  static Insertable<PairingSession> custom({
    Expression<int>? id,
    Expression<String>? pairingCode,
    Expression<String>? sessionToken,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? expiresAt,
    Expression<bool>? isUsed,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (pairingCode != null) 'pairing_code': pairingCode,
      if (sessionToken != null) 'session_token': sessionToken,
      if (createdAt != null) 'created_at': createdAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (isUsed != null) 'is_used': isUsed,
    });
  }

  PairingSessionsCompanion copyWith(
      {Value<int>? id,
      Value<String>? pairingCode,
      Value<String>? sessionToken,
      Value<DateTime>? createdAt,
      Value<DateTime>? expiresAt,
      Value<bool>? isUsed}) {
    return PairingSessionsCompanion(
      id: id ?? this.id,
      pairingCode: pairingCode ?? this.pairingCode,
      sessionToken: sessionToken ?? this.sessionToken,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      isUsed: isUsed ?? this.isUsed,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (pairingCode.present) {
      map['pairing_code'] = Variable<String>(pairingCode.value);
    }
    if (sessionToken.present) {
      map['session_token'] = Variable<String>(sessionToken.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (isUsed.present) {
      map['is_used'] = Variable<bool>(isUsed.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PairingSessionsCompanion(')
          ..write('id: $id, ')
          ..write('pairingCode: $pairingCode, ')
          ..write('sessionToken: $sessionToken, ')
          ..write('createdAt: $createdAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('isUsed: $isUsed')
          ..write(')'))
        .toString();
  }
}

abstract class _$PairingDatabase extends GeneratedDatabase {
  _$PairingDatabase(QueryExecutor e) : super(e);
  $PairingDatabaseManager get managers => $PairingDatabaseManager(this);
  late final $PairedDevicesTable pairedDevices = $PairedDevicesTable(this);
  late final $PairingSessionsTable pairingSessions =
      $PairingSessionsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [pairedDevices, pairingSessions];
}

typedef $$PairedDevicesTableCreateCompanionBuilder = PairedDevicesCompanion
    Function({
  required String deviceId,
  required String deviceName,
  required String sessionToken,
  required DateTime pairedAt,
  Value<DateTime?> lastConnectedAt,
  Value<String> deviceType,
  Value<bool> isActive,
  Value<int> rowid,
});
typedef $$PairedDevicesTableUpdateCompanionBuilder = PairedDevicesCompanion
    Function({
  Value<String> deviceId,
  Value<String> deviceName,
  Value<String> sessionToken,
  Value<DateTime> pairedAt,
  Value<DateTime?> lastConnectedAt,
  Value<String> deviceType,
  Value<bool> isActive,
  Value<int> rowid,
});

class $$PairedDevicesTableFilterComposer
    extends Composer<_$PairingDatabase, $PairedDevicesTable> {
  $$PairedDevicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deviceName => $composableBuilder(
      column: $table.deviceName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sessionToken => $composableBuilder(
      column: $table.sessionToken, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get pairedAt => $composableBuilder(
      column: $table.pairedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastConnectedAt => $composableBuilder(
      column: $table.lastConnectedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deviceType => $composableBuilder(
      column: $table.deviceType, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));
}

class $$PairedDevicesTableOrderingComposer
    extends Composer<_$PairingDatabase, $PairedDevicesTable> {
  $$PairedDevicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deviceName => $composableBuilder(
      column: $table.deviceName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sessionToken => $composableBuilder(
      column: $table.sessionToken,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get pairedAt => $composableBuilder(
      column: $table.pairedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastConnectedAt => $composableBuilder(
      column: $table.lastConnectedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deviceType => $composableBuilder(
      column: $table.deviceType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));
}

class $$PairedDevicesTableAnnotationComposer
    extends Composer<_$PairingDatabase, $PairedDevicesTable> {
  $$PairedDevicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get deviceName => $composableBuilder(
      column: $table.deviceName, builder: (column) => column);

  GeneratedColumn<String> get sessionToken => $composableBuilder(
      column: $table.sessionToken, builder: (column) => column);

  GeneratedColumn<DateTime> get pairedAt =>
      $composableBuilder(column: $table.pairedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastConnectedAt => $composableBuilder(
      column: $table.lastConnectedAt, builder: (column) => column);

  GeneratedColumn<String> get deviceType => $composableBuilder(
      column: $table.deviceType, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);
}

class $$PairedDevicesTableTableManager extends RootTableManager<
    _$PairingDatabase,
    $PairedDevicesTable,
    PairedDevice,
    $$PairedDevicesTableFilterComposer,
    $$PairedDevicesTableOrderingComposer,
    $$PairedDevicesTableAnnotationComposer,
    $$PairedDevicesTableCreateCompanionBuilder,
    $$PairedDevicesTableUpdateCompanionBuilder,
    (
      PairedDevice,
      BaseReferences<_$PairingDatabase, $PairedDevicesTable, PairedDevice>
    ),
    PairedDevice,
    PrefetchHooks Function()> {
  $$PairedDevicesTableTableManager(
      _$PairingDatabase db, $PairedDevicesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PairedDevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PairedDevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PairedDevicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> deviceId = const Value.absent(),
            Value<String> deviceName = const Value.absent(),
            Value<String> sessionToken = const Value.absent(),
            Value<DateTime> pairedAt = const Value.absent(),
            Value<DateTime?> lastConnectedAt = const Value.absent(),
            Value<String> deviceType = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PairedDevicesCompanion(
            deviceId: deviceId,
            deviceName: deviceName,
            sessionToken: sessionToken,
            pairedAt: pairedAt,
            lastConnectedAt: lastConnectedAt,
            deviceType: deviceType,
            isActive: isActive,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String deviceId,
            required String deviceName,
            required String sessionToken,
            required DateTime pairedAt,
            Value<DateTime?> lastConnectedAt = const Value.absent(),
            Value<String> deviceType = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PairedDevicesCompanion.insert(
            deviceId: deviceId,
            deviceName: deviceName,
            sessionToken: sessionToken,
            pairedAt: pairedAt,
            lastConnectedAt: lastConnectedAt,
            deviceType: deviceType,
            isActive: isActive,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PairedDevicesTableProcessedTableManager = ProcessedTableManager<
    _$PairingDatabase,
    $PairedDevicesTable,
    PairedDevice,
    $$PairedDevicesTableFilterComposer,
    $$PairedDevicesTableOrderingComposer,
    $$PairedDevicesTableAnnotationComposer,
    $$PairedDevicesTableCreateCompanionBuilder,
    $$PairedDevicesTableUpdateCompanionBuilder,
    (
      PairedDevice,
      BaseReferences<_$PairingDatabase, $PairedDevicesTable, PairedDevice>
    ),
    PairedDevice,
    PrefetchHooks Function()>;
typedef $$PairingSessionsTableCreateCompanionBuilder = PairingSessionsCompanion
    Function({
  Value<int> id,
  required String pairingCode,
  required String sessionToken,
  required DateTime createdAt,
  required DateTime expiresAt,
  Value<bool> isUsed,
});
typedef $$PairingSessionsTableUpdateCompanionBuilder = PairingSessionsCompanion
    Function({
  Value<int> id,
  Value<String> pairingCode,
  Value<String> sessionToken,
  Value<DateTime> createdAt,
  Value<DateTime> expiresAt,
  Value<bool> isUsed,
});

class $$PairingSessionsTableFilterComposer
    extends Composer<_$PairingDatabase, $PairingSessionsTable> {
  $$PairingSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pairingCode => $composableBuilder(
      column: $table.pairingCode, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sessionToken => $composableBuilder(
      column: $table.sessionToken, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
      column: $table.expiresAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isUsed => $composableBuilder(
      column: $table.isUsed, builder: (column) => ColumnFilters(column));
}

class $$PairingSessionsTableOrderingComposer
    extends Composer<_$PairingDatabase, $PairingSessionsTable> {
  $$PairingSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pairingCode => $composableBuilder(
      column: $table.pairingCode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sessionToken => $composableBuilder(
      column: $table.sessionToken,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
      column: $table.expiresAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isUsed => $composableBuilder(
      column: $table.isUsed, builder: (column) => ColumnOrderings(column));
}

class $$PairingSessionsTableAnnotationComposer
    extends Composer<_$PairingDatabase, $PairingSessionsTable> {
  $$PairingSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get pairingCode => $composableBuilder(
      column: $table.pairingCode, builder: (column) => column);

  GeneratedColumn<String> get sessionToken => $composableBuilder(
      column: $table.sessionToken, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<bool> get isUsed =>
      $composableBuilder(column: $table.isUsed, builder: (column) => column);
}

class $$PairingSessionsTableTableManager extends RootTableManager<
    _$PairingDatabase,
    $PairingSessionsTable,
    PairingSession,
    $$PairingSessionsTableFilterComposer,
    $$PairingSessionsTableOrderingComposer,
    $$PairingSessionsTableAnnotationComposer,
    $$PairingSessionsTableCreateCompanionBuilder,
    $$PairingSessionsTableUpdateCompanionBuilder,
    (
      PairingSession,
      BaseReferences<_$PairingDatabase, $PairingSessionsTable, PairingSession>
    ),
    PairingSession,
    PrefetchHooks Function()> {
  $$PairingSessionsTableTableManager(
      _$PairingDatabase db, $PairingSessionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PairingSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PairingSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PairingSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> pairingCode = const Value.absent(),
            Value<String> sessionToken = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> expiresAt = const Value.absent(),
            Value<bool> isUsed = const Value.absent(),
          }) =>
              PairingSessionsCompanion(
            id: id,
            pairingCode: pairingCode,
            sessionToken: sessionToken,
            createdAt: createdAt,
            expiresAt: expiresAt,
            isUsed: isUsed,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String pairingCode,
            required String sessionToken,
            required DateTime createdAt,
            required DateTime expiresAt,
            Value<bool> isUsed = const Value.absent(),
          }) =>
              PairingSessionsCompanion.insert(
            id: id,
            pairingCode: pairingCode,
            sessionToken: sessionToken,
            createdAt: createdAt,
            expiresAt: expiresAt,
            isUsed: isUsed,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PairingSessionsTableProcessedTableManager = ProcessedTableManager<
    _$PairingDatabase,
    $PairingSessionsTable,
    PairingSession,
    $$PairingSessionsTableFilterComposer,
    $$PairingSessionsTableOrderingComposer,
    $$PairingSessionsTableAnnotationComposer,
    $$PairingSessionsTableCreateCompanionBuilder,
    $$PairingSessionsTableUpdateCompanionBuilder,
    (
      PairingSession,
      BaseReferences<_$PairingDatabase, $PairingSessionsTable, PairingSession>
    ),
    PairingSession,
    PrefetchHooks Function()>;

class $PairingDatabaseManager {
  final _$PairingDatabase _db;
  $PairingDatabaseManager(this._db);
  $$PairedDevicesTableTableManager get pairedDevices =>
      $$PairedDevicesTableTableManager(_db, _db.pairedDevices);
  $$PairingSessionsTableTableManager get pairingSessions =>
      $$PairingSessionsTableTableManager(_db, _db.pairingSessions);
}
