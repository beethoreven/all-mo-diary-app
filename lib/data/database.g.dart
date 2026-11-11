// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $DiariesTable extends Diaries with TableInfo<$DiariesTable, DiaryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DiariesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<String> day = GeneratedColumn<String>(
    'day',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyPlainMeta = const VerificationMeta(
    'bodyPlain',
  );
  @override
  late final GeneratedColumn<String> bodyPlain = GeneratedColumn<String>(
    'body_plain',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    day,
    title,
    body,
    bodyPlain,
    createdAt,
    updatedAt,
    deleted,
    dirty,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'diaries';
  @override
  VerificationContext validateIntegrity(
    Insertable<DiaryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('day')) {
      context.handle(
        _dayMeta,
        day.isAcceptableOrUnknown(data['day']!, _dayMeta),
      );
    } else if (isInserting) {
      context.missing(_dayMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('body_plain')) {
      context.handle(
        _bodyPlainMeta,
        bodyPlain.isAcceptableOrUnknown(data['body_plain']!, _bodyPlainMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyPlainMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DiaryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DiaryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      day: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}day'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      bodyPlain: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body_plain'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
    );
  }

  @override
  $DiariesTable createAlias(String alias) {
    return $DiariesTable(attachedDatabase, alias);
  }
}

class DiaryRow extends DataClass implements Insertable<DiaryRow> {
  final String id;

  /// The day it belongs to, 2026-11-10 (Taiwan calendar day).
  final String day;
  final String title;

  /// The body as a Quill Delta (JSON). Images are embeds that name a file in files/images/.
  final String body;

  /// The body's plain text, kept for search (spec §5) so search never parses JSON.
  final String bodyPlain;
  final int createdAt;
  final int updatedAt;
  final bool deleted;

  /// Changed since the last upload (for cloud sync later).
  final bool dirty;
  const DiaryRow({
    required this.id,
    required this.day,
    required this.title,
    required this.body,
    required this.bodyPlain,
    required this.createdAt,
    required this.updatedAt,
    required this.deleted,
    required this.dirty,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['day'] = Variable<String>(day);
    map['title'] = Variable<String>(title);
    map['body'] = Variable<String>(body);
    map['body_plain'] = Variable<String>(bodyPlain);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    map['deleted'] = Variable<bool>(deleted);
    map['dirty'] = Variable<bool>(dirty);
    return map;
  }

  DiariesCompanion toCompanion(bool nullToAbsent) {
    return DiariesCompanion(
      id: Value(id),
      day: Value(day),
      title: Value(title),
      body: Value(body),
      bodyPlain: Value(bodyPlain),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deleted: Value(deleted),
      dirty: Value(dirty),
    );
  }

  factory DiaryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DiaryRow(
      id: serializer.fromJson<String>(json['id']),
      day: serializer.fromJson<String>(json['day']),
      title: serializer.fromJson<String>(json['title']),
      body: serializer.fromJson<String>(json['body']),
      bodyPlain: serializer.fromJson<String>(json['bodyPlain']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      dirty: serializer.fromJson<bool>(json['dirty']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'day': serializer.toJson<String>(day),
      'title': serializer.toJson<String>(title),
      'body': serializer.toJson<String>(body),
      'bodyPlain': serializer.toJson<String>(bodyPlain),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deleted': serializer.toJson<bool>(deleted),
      'dirty': serializer.toJson<bool>(dirty),
    };
  }

  DiaryRow copyWith({
    String? id,
    String? day,
    String? title,
    String? body,
    String? bodyPlain,
    int? createdAt,
    int? updatedAt,
    bool? deleted,
    bool? dirty,
  }) => DiaryRow(
    id: id ?? this.id,
    day: day ?? this.day,
    title: title ?? this.title,
    body: body ?? this.body,
    bodyPlain: bodyPlain ?? this.bodyPlain,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deleted: deleted ?? this.deleted,
    dirty: dirty ?? this.dirty,
  );
  DiaryRow copyWithCompanion(DiariesCompanion data) {
    return DiaryRow(
      id: data.id.present ? data.id.value : this.id,
      day: data.day.present ? data.day.value : this.day,
      title: data.title.present ? data.title.value : this.title,
      body: data.body.present ? data.body.value : this.body,
      bodyPlain: data.bodyPlain.present ? data.bodyPlain.value : this.bodyPlain,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DiaryRow(')
          ..write('id: $id, ')
          ..write('day: $day, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('bodyPlain: $bodyPlain, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deleted: $deleted, ')
          ..write('dirty: $dirty')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    day,
    title,
    body,
    bodyPlain,
    createdAt,
    updatedAt,
    deleted,
    dirty,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiaryRow &&
          other.id == this.id &&
          other.day == this.day &&
          other.title == this.title &&
          other.body == this.body &&
          other.bodyPlain == this.bodyPlain &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deleted == this.deleted &&
          other.dirty == this.dirty);
}

class DiariesCompanion extends UpdateCompanion<DiaryRow> {
  final Value<String> id;
  final Value<String> day;
  final Value<String> title;
  final Value<String> body;
  final Value<String> bodyPlain;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<bool> deleted;
  final Value<bool> dirty;
  final Value<int> rowid;
  const DiariesCompanion({
    this.id = const Value.absent(),
    this.day = const Value.absent(),
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.bodyPlain = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deleted = const Value.absent(),
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DiariesCompanion.insert({
    required String id,
    required String day,
    required String title,
    required String body,
    required String bodyPlain,
    required int createdAt,
    required int updatedAt,
    this.deleted = const Value.absent(),
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       day = Value(day),
       title = Value(title),
       body = Value(body),
       bodyPlain = Value(bodyPlain),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<DiaryRow> custom({
    Expression<String>? id,
    Expression<String>? day,
    Expression<String>? title,
    Expression<String>? body,
    Expression<String>? bodyPlain,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<bool>? deleted,
    Expression<bool>? dirty,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (day != null) 'day': day,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (bodyPlain != null) 'body_plain': bodyPlain,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deleted != null) 'deleted': deleted,
      if (dirty != null) 'dirty': dirty,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DiariesCompanion copyWith({
    Value<String>? id,
    Value<String>? day,
    Value<String>? title,
    Value<String>? body,
    Value<String>? bodyPlain,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<bool>? deleted,
    Value<bool>? dirty,
    Value<int>? rowid,
  }) {
    return DiariesCompanion(
      id: id ?? this.id,
      day: day ?? this.day,
      title: title ?? this.title,
      body: body ?? this.body,
      bodyPlain: bodyPlain ?? this.bodyPlain,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
      dirty: dirty ?? this.dirty,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (day.present) {
      map['day'] = Variable<String>(day.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (bodyPlain.present) {
      map['body_plain'] = Variable<String>(bodyPlain.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DiariesCompanion(')
          ..write('id: $id, ')
          ..write('day: $day, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('bodyPlain: $bodyPlain, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deleted: $deleted, ')
          ..write('dirty: $dirty, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DraftsTable extends Drafts with TableInfo<$DraftsTable, DraftRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DraftsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _diaryIdMeta = const VerificationMeta(
    'diaryId',
  );
  @override
  late final GeneratedColumn<String> diaryId = GeneratedColumn<String>(
    'diary_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<String> day = GeneratedColumn<String>(
    'day',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    key,
    diaryId,
    day,
    title,
    body,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'drafts';
  @override
  VerificationContext validateIntegrity(
    Insertable<DraftRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('diary_id')) {
      context.handle(
        _diaryIdMeta,
        diaryId.isAcceptableOrUnknown(data['diary_id']!, _diaryIdMeta),
      );
    }
    if (data.containsKey('day')) {
      context.handle(
        _dayMeta,
        day.isAcceptableOrUnknown(data['day']!, _dayMeta),
      );
    } else if (isInserting) {
      context.missing(_dayMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  DraftRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DraftRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      diaryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}diary_id'],
      ),
      day: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}day'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DraftsTable createAlias(String alias) {
    return $DraftsTable(attachedDatabase, alias);
  }
}

class DraftRow extends DataClass implements Insertable<DraftRow> {
  /// 'new:2026-11-10' for a new diary, 'edit:' + the diary id for editing an existing one.
  final String key;
  final String? diaryId;
  final String day;
  final String title;
  final String body;
  final int updatedAt;
  const DraftRow({
    required this.key,
    this.diaryId,
    required this.day,
    required this.title,
    required this.body,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    if (!nullToAbsent || diaryId != null) {
      map['diary_id'] = Variable<String>(diaryId);
    }
    map['day'] = Variable<String>(day);
    map['title'] = Variable<String>(title);
    map['body'] = Variable<String>(body);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  DraftsCompanion toCompanion(bool nullToAbsent) {
    return DraftsCompanion(
      key: Value(key),
      diaryId: diaryId == null && nullToAbsent
          ? const Value.absent()
          : Value(diaryId),
      day: Value(day),
      title: Value(title),
      body: Value(body),
      updatedAt: Value(updatedAt),
    );
  }

  factory DraftRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DraftRow(
      key: serializer.fromJson<String>(json['key']),
      diaryId: serializer.fromJson<String?>(json['diaryId']),
      day: serializer.fromJson<String>(json['day']),
      title: serializer.fromJson<String>(json['title']),
      body: serializer.fromJson<String>(json['body']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'diaryId': serializer.toJson<String?>(diaryId),
      'day': serializer.toJson<String>(day),
      'title': serializer.toJson<String>(title),
      'body': serializer.toJson<String>(body),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  DraftRow copyWith({
    String? key,
    Value<String?> diaryId = const Value.absent(),
    String? day,
    String? title,
    String? body,
    int? updatedAt,
  }) => DraftRow(
    key: key ?? this.key,
    diaryId: diaryId.present ? diaryId.value : this.diaryId,
    day: day ?? this.day,
    title: title ?? this.title,
    body: body ?? this.body,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  DraftRow copyWithCompanion(DraftsCompanion data) {
    return DraftRow(
      key: data.key.present ? data.key.value : this.key,
      diaryId: data.diaryId.present ? data.diaryId.value : this.diaryId,
      day: data.day.present ? data.day.value : this.day,
      title: data.title.present ? data.title.value : this.title,
      body: data.body.present ? data.body.value : this.body,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DraftRow(')
          ..write('key: $key, ')
          ..write('diaryId: $diaryId, ')
          ..write('day: $day, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, diaryId, day, title, body, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DraftRow &&
          other.key == this.key &&
          other.diaryId == this.diaryId &&
          other.day == this.day &&
          other.title == this.title &&
          other.body == this.body &&
          other.updatedAt == this.updatedAt);
}

class DraftsCompanion extends UpdateCompanion<DraftRow> {
  final Value<String> key;
  final Value<String?> diaryId;
  final Value<String> day;
  final Value<String> title;
  final Value<String> body;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const DraftsCompanion({
    this.key = const Value.absent(),
    this.diaryId = const Value.absent(),
    this.day = const Value.absent(),
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DraftsCompanion.insert({
    required String key,
    this.diaryId = const Value.absent(),
    required String day,
    required String title,
    required String body,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       day = Value(day),
       title = Value(title),
       body = Value(body),
       updatedAt = Value(updatedAt);
  static Insertable<DraftRow> custom({
    Expression<String>? key,
    Expression<String>? diaryId,
    Expression<String>? day,
    Expression<String>? title,
    Expression<String>? body,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (diaryId != null) 'diary_id': diaryId,
      if (day != null) 'day': day,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DraftsCompanion copyWith({
    Value<String>? key,
    Value<String?>? diaryId,
    Value<String>? day,
    Value<String>? title,
    Value<String>? body,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return DraftsCompanion(
      key: key ?? this.key,
      diaryId: diaryId ?? this.diaryId,
      day: day ?? this.day,
      title: title ?? this.title,
      body: body ?? this.body,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (diaryId.present) {
      map['diary_id'] = Variable<String>(diaryId.value);
    }
    if (day.present) {
      map['day'] = Variable<String>(day.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DraftsCompanion(')
          ..write('key: $key, ')
          ..write('diaryId: $diaryId, ')
          ..write('day: $day, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings
    with TableInfo<$SettingsTable, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  final String key;
  final String value;
  const SettingRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory SettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SettingRow copyWith({String? key, String? value}) =>
      SettingRow(key: key ?? this.key, value: value ?? this.value);
  SettingRow copyWithCompanion(SettingsCompanion data) {
    return SettingRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow &&
          other.key == this.key &&
          other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SettingRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ImagesTable extends Images with TableInfo<$ImagesTable, ImageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hasLocalMeta = const VerificationMeta(
    'hasLocal',
  );
  @override
  late final GeneratedColumn<bool> hasLocal = GeneratedColumn<bool>(
    'has_local',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_local" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _cloudFileIdMeta = const VerificationMeta(
    'cloudFileId',
  );
  @override
  late final GeneratedColumn<String> cloudFileId = GeneratedColumn<String>(
    'cloud_file_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cloudMd5Meta = const VerificationMeta(
    'cloudMd5',
  );
  @override
  late final GeneratedColumn<String> cloudMd5 = GeneratedColumn<String>(
    'cloud_md5',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    hasLocal,
    cloudFileId,
    cloudMd5,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'images';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImageRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('has_local')) {
      context.handle(
        _hasLocalMeta,
        hasLocal.isAcceptableOrUnknown(data['has_local']!, _hasLocalMeta),
      );
    }
    if (data.containsKey('cloud_file_id')) {
      context.handle(
        _cloudFileIdMeta,
        cloudFileId.isAcceptableOrUnknown(
          data['cloud_file_id']!,
          _cloudFileIdMeta,
        ),
      );
    }
    if (data.containsKey('cloud_md5')) {
      context.handle(
        _cloudMd5Meta,
        cloudMd5.isAcceptableOrUnknown(data['cloud_md5']!, _cloudMd5Meta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ImageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImageRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      hasLocal: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_local'],
      )!,
      cloudFileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cloud_file_id'],
      ),
      cloudMd5: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cloud_md5'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ImagesTable createAlias(String alias) {
    return $ImagesTable(attachedDatabase, alias);
  }
}

class ImageRow extends DataClass implements Insertable<ImageRow> {
  final String id;
  final bool hasLocal;
  final String? cloudFileId;
  final String? cloudMd5;
  final int createdAt;
  const ImageRow({
    required this.id,
    required this.hasLocal,
    this.cloudFileId,
    this.cloudMd5,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['has_local'] = Variable<bool>(hasLocal);
    if (!nullToAbsent || cloudFileId != null) {
      map['cloud_file_id'] = Variable<String>(cloudFileId);
    }
    if (!nullToAbsent || cloudMd5 != null) {
      map['cloud_md5'] = Variable<String>(cloudMd5);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  ImagesCompanion toCompanion(bool nullToAbsent) {
    return ImagesCompanion(
      id: Value(id),
      hasLocal: Value(hasLocal),
      cloudFileId: cloudFileId == null && nullToAbsent
          ? const Value.absent()
          : Value(cloudFileId),
      cloudMd5: cloudMd5 == null && nullToAbsent
          ? const Value.absent()
          : Value(cloudMd5),
      createdAt: Value(createdAt),
    );
  }

  factory ImageRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImageRow(
      id: serializer.fromJson<String>(json['id']),
      hasLocal: serializer.fromJson<bool>(json['hasLocal']),
      cloudFileId: serializer.fromJson<String?>(json['cloudFileId']),
      cloudMd5: serializer.fromJson<String?>(json['cloudMd5']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'hasLocal': serializer.toJson<bool>(hasLocal),
      'cloudFileId': serializer.toJson<String?>(cloudFileId),
      'cloudMd5': serializer.toJson<String?>(cloudMd5),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  ImageRow copyWith({
    String? id,
    bool? hasLocal,
    Value<String?> cloudFileId = const Value.absent(),
    Value<String?> cloudMd5 = const Value.absent(),
    int? createdAt,
  }) => ImageRow(
    id: id ?? this.id,
    hasLocal: hasLocal ?? this.hasLocal,
    cloudFileId: cloudFileId.present ? cloudFileId.value : this.cloudFileId,
    cloudMd5: cloudMd5.present ? cloudMd5.value : this.cloudMd5,
    createdAt: createdAt ?? this.createdAt,
  );
  ImageRow copyWithCompanion(ImagesCompanion data) {
    return ImageRow(
      id: data.id.present ? data.id.value : this.id,
      hasLocal: data.hasLocal.present ? data.hasLocal.value : this.hasLocal,
      cloudFileId: data.cloudFileId.present
          ? data.cloudFileId.value
          : this.cloudFileId,
      cloudMd5: data.cloudMd5.present ? data.cloudMd5.value : this.cloudMd5,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImageRow(')
          ..write('id: $id, ')
          ..write('hasLocal: $hasLocal, ')
          ..write('cloudFileId: $cloudFileId, ')
          ..write('cloudMd5: $cloudMd5, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, hasLocal, cloudFileId, cloudMd5, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImageRow &&
          other.id == this.id &&
          other.hasLocal == this.hasLocal &&
          other.cloudFileId == this.cloudFileId &&
          other.cloudMd5 == this.cloudMd5 &&
          other.createdAt == this.createdAt);
}

class ImagesCompanion extends UpdateCompanion<ImageRow> {
  final Value<String> id;
  final Value<bool> hasLocal;
  final Value<String?> cloudFileId;
  final Value<String?> cloudMd5;
  final Value<int> createdAt;
  final Value<int> rowid;
  const ImagesCompanion({
    this.id = const Value.absent(),
    this.hasLocal = const Value.absent(),
    this.cloudFileId = const Value.absent(),
    this.cloudMd5 = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ImagesCompanion.insert({
    required String id,
    this.hasLocal = const Value.absent(),
    this.cloudFileId = const Value.absent(),
    this.cloudMd5 = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt);
  static Insertable<ImageRow> custom({
    Expression<String>? id,
    Expression<bool>? hasLocal,
    Expression<String>? cloudFileId,
    Expression<String>? cloudMd5,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (hasLocal != null) 'has_local': hasLocal,
      if (cloudFileId != null) 'cloud_file_id': cloudFileId,
      if (cloudMd5 != null) 'cloud_md5': cloudMd5,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ImagesCompanion copyWith({
    Value<String>? id,
    Value<bool>? hasLocal,
    Value<String?>? cloudFileId,
    Value<String?>? cloudMd5,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return ImagesCompanion(
      id: id ?? this.id,
      hasLocal: hasLocal ?? this.hasLocal,
      cloudFileId: cloudFileId ?? this.cloudFileId,
      cloudMd5: cloudMd5 ?? this.cloudMd5,
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
    if (hasLocal.present) {
      map['has_local'] = Variable<bool>(hasLocal.value);
    }
    if (cloudFileId.present) {
      map['cloud_file_id'] = Variable<String>(cloudFileId.value);
    }
    if (cloudMd5.present) {
      map['cloud_md5'] = Variable<String>(cloudMd5.value);
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
    return (StringBuffer('ImagesCompanion(')
          ..write('id: $id, ')
          ..write('hasLocal: $hasLocal, ')
          ..write('cloudFileId: $cloudFileId, ')
          ..write('cloudMd5: $cloudMd5, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDb extends GeneratedDatabase {
  _$AppDb(QueryExecutor e) : super(e);
  $AppDbManager get managers => $AppDbManager(this);
  late final $DiariesTable diaries = $DiariesTable(this);
  late final $DraftsTable drafts = $DraftsTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $ImagesTable images = $ImagesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    diaries,
    drafts,
    settings,
    images,
  ];
}

typedef $$DiariesTableCreateCompanionBuilder = DiariesCompanion Function({
  required String id,
  required String day,
  required String title,
  required String body,
  required String bodyPlain,
  required int createdAt,
  required int updatedAt,
  Value<bool> deleted,
  Value<bool> dirty,
  Value<int> rowid,
});
typedef $$DiariesTableUpdateCompanionBuilder = DiariesCompanion Function({
  Value<String> id,
  Value<String> day,
  Value<String> title,
  Value<String> body,
  Value<String> bodyPlain,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<bool> deleted,
  Value<bool> dirty,
  Value<int> rowid,
});

class $$DiariesTableFilterComposer extends Composer<_$AppDb, $DiariesTable> {
  $$DiariesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bodyPlain => $composableBuilder(
    column: $table.bodyPlain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DiariesTableOrderingComposer extends Composer<_$AppDb, $DiariesTable> {
  $$DiariesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bodyPlain => $composableBuilder(
    column: $table.bodyPlain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DiariesTableAnnotationComposer
    extends Composer<_$AppDb, $DiariesTable> {
  $$DiariesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get bodyPlain =>
      $composableBuilder(column: $table.bodyPlain, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);
}

class $$DiariesTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $DiariesTable,
          DiaryRow,
          $$DiariesTableFilterComposer,
          $$DiariesTableOrderingComposer,
          $$DiariesTableAnnotationComposer,
          $$DiariesTableCreateCompanionBuilder,
          $$DiariesTableUpdateCompanionBuilder,
          (DiaryRow, BaseReferences<_$AppDb, $DiariesTable, DiaryRow>),
          DiaryRow,
          PrefetchHooks Function()
        > {
  $$DiariesTableTableManager(_$AppDb db, $DiariesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DiariesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DiariesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DiariesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> day = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String> bodyPlain = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiariesCompanion(
                id: id,
                day: day,
                title: title,
                body: body,
                bodyPlain: bodyPlain,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deleted: deleted,
                dirty: dirty,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String day,
                required String title,
                required String body,
                required String bodyPlain,
                required int createdAt,
                required int updatedAt,
                Value<bool> deleted = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiariesCompanion.insert(
                id: id,
                day: day,
                title: title,
                body: body,
                bodyPlain: bodyPlain,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deleted: deleted,
                dirty: dirty,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DiariesTable, DiaryRow>(table),
                  BaseReferences<_$AppDb, $DiariesTable, DiaryRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DiariesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $DiariesTable,
      DiaryRow,
      $$DiariesTableFilterComposer,
      $$DiariesTableOrderingComposer,
      $$DiariesTableAnnotationComposer,
      $$DiariesTableCreateCompanionBuilder,
      $$DiariesTableUpdateCompanionBuilder,
      (DiaryRow, BaseReferences<_$AppDb, $DiariesTable, DiaryRow>),
      DiaryRow,
      PrefetchHooks Function()
    >;
typedef $$DraftsTableCreateCompanionBuilder = DraftsCompanion Function({
  required String key,
  Value<String?> diaryId,
  required String day,
  required String title,
  required String body,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$DraftsTableUpdateCompanionBuilder = DraftsCompanion Function({
  Value<String> key,
  Value<String?> diaryId,
  Value<String> day,
  Value<String> title,
  Value<String> body,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$DraftsTableFilterComposer extends Composer<_$AppDb, $DraftsTable> {
  $$DraftsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get diaryId => $composableBuilder(
    column: $table.diaryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DraftsTableOrderingComposer extends Composer<_$AppDb, $DraftsTable> {
  $$DraftsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get diaryId => $composableBuilder(
    column: $table.diaryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DraftsTableAnnotationComposer extends Composer<_$AppDb, $DraftsTable> {
  $$DraftsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get diaryId =>
      $composableBuilder(column: $table.diaryId, builder: (column) => column);

  GeneratedColumn<String> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$DraftsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $DraftsTable,
          DraftRow,
          $$DraftsTableFilterComposer,
          $$DraftsTableOrderingComposer,
          $$DraftsTableAnnotationComposer,
          $$DraftsTableCreateCompanionBuilder,
          $$DraftsTableUpdateCompanionBuilder,
          (DraftRow, BaseReferences<_$AppDb, $DraftsTable, DraftRow>),
          DraftRow,
          PrefetchHooks Function()
        > {
  $$DraftsTableTableManager(_$AppDb db, $DraftsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DraftsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DraftsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DraftsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String?> diaryId = const Value.absent(),
                Value<String> day = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DraftsCompanion(
                key: key,
                diaryId: diaryId,
                day: day,
                title: title,
                body: body,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                Value<String?> diaryId = const Value.absent(),
                required String day,
                required String title,
                required String body,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => DraftsCompanion.insert(
                key: key,
                diaryId: diaryId,
                day: day,
                title: title,
                body: body,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DraftsTable, DraftRow>(table),
                  BaseReferences<_$AppDb, $DraftsTable, DraftRow>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DraftsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $DraftsTable,
      DraftRow,
      $$DraftsTableFilterComposer,
      $$DraftsTableOrderingComposer,
      $$DraftsTableAnnotationComposer,
      $$DraftsTableCreateCompanionBuilder,
      $$DraftsTableUpdateCompanionBuilder,
      (DraftRow, BaseReferences<_$AppDb, $DraftsTable, DraftRow>),
      DraftRow,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$SettingsTableFilterComposer extends Composer<_$AppDb, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDb, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDb, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $SettingsTable,
          SettingRow,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (SettingRow, BaseReferences<_$AppDb, $SettingsTable, SettingRow>),
          SettingRow,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDb db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTable, SettingRow>(table),
                  BaseReferences<_$AppDb, $SettingsTable, SettingRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $SettingsTable,
      SettingRow,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (SettingRow, BaseReferences<_$AppDb, $SettingsTable, SettingRow>),
      SettingRow,
      PrefetchHooks Function()
    >;
typedef $$ImagesTableCreateCompanionBuilder = ImagesCompanion Function({
  required String id,
  Value<bool> hasLocal,
  Value<String?> cloudFileId,
  Value<String?> cloudMd5,
  required int createdAt,
  Value<int> rowid,
});
typedef $$ImagesTableUpdateCompanionBuilder = ImagesCompanion Function({
  Value<String> id,
  Value<bool> hasLocal,
  Value<String?> cloudFileId,
  Value<String?> cloudMd5,
  Value<int> createdAt,
  Value<int> rowid,
});

class $$ImagesTableFilterComposer extends Composer<_$AppDb, $ImagesTable> {
  $$ImagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasLocal => $composableBuilder(
    column: $table.hasLocal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cloudFileId => $composableBuilder(
    column: $table.cloudFileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cloudMd5 => $composableBuilder(
    column: $table.cloudMd5,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ImagesTableOrderingComposer extends Composer<_$AppDb, $ImagesTable> {
  $$ImagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasLocal => $composableBuilder(
    column: $table.hasLocal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cloudFileId => $composableBuilder(
    column: $table.cloudFileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cloudMd5 => $composableBuilder(
    column: $table.cloudMd5,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ImagesTableAnnotationComposer extends Composer<_$AppDb, $ImagesTable> {
  $$ImagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<bool> get hasLocal =>
      $composableBuilder(column: $table.hasLocal, builder: (column) => column);

  GeneratedColumn<String> get cloudFileId => $composableBuilder(
    column: $table.cloudFileId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cloudMd5 =>
      $composableBuilder(column: $table.cloudMd5, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ImagesTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $ImagesTable,
          ImageRow,
          $$ImagesTableFilterComposer,
          $$ImagesTableOrderingComposer,
          $$ImagesTableAnnotationComposer,
          $$ImagesTableCreateCompanionBuilder,
          $$ImagesTableUpdateCompanionBuilder,
          (ImageRow, BaseReferences<_$AppDb, $ImagesTable, ImageRow>),
          ImageRow,
          PrefetchHooks Function()
        > {
  $$ImagesTableTableManager(_$AppDb db, $ImagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ImagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ImagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ImagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<bool> hasLocal = const Value.absent(),
                Value<String?> cloudFileId = const Value.absent(),
                Value<String?> cloudMd5 = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ImagesCompanion(
                id: id,
                hasLocal: hasLocal,
                cloudFileId: cloudFileId,
                cloudMd5: cloudMd5,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<bool> hasLocal = const Value.absent(),
                Value<String?> cloudFileId = const Value.absent(),
                Value<String?> cloudMd5 = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => ImagesCompanion.insert(
                id: id,
                hasLocal: hasLocal,
                cloudFileId: cloudFileId,
                cloudMd5: cloudMd5,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ImagesTable, ImageRow>(table),
                  BaseReferences<_$AppDb, $ImagesTable, ImageRow>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ImagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $ImagesTable,
      ImageRow,
      $$ImagesTableFilterComposer,
      $$ImagesTableOrderingComposer,
      $$ImagesTableAnnotationComposer,
      $$ImagesTableCreateCompanionBuilder,
      $$ImagesTableUpdateCompanionBuilder,
      (ImageRow, BaseReferences<_$AppDb, $ImagesTable, ImageRow>),
      ImageRow,
      PrefetchHooks Function()
    >;

class $AppDbManager {
  final _$AppDb _db;
  $AppDbManager(this._db);
  $$DiariesTableTableManager get diaries =>
      $$DiariesTableTableManager(_db, _db.diaries);
  $$DraftsTableTableManager get drafts =>
      $$DraftsTableTableManager(_db, _db.drafts);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$ImagesTableTableManager get images =>
      $$ImagesTableTableManager(_db, _db.images);
}
