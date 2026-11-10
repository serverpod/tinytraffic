/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters
// ignore_for_file: invalid_use_of_internal_member

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'dart:async' as _ida;
import 'dart:typed_data' as _idt;
import 'package:serverpod/serverpod.dart' as _is;
import '../../game/models/run_status.dart' as _ipc0ayvg;

/// A run the server handed out a seed for. Scores are only accepted for
/// runs started here, and only once.
abstract class GameRun
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  GameRun._({
    this.id,
    required this.authUserId,
    required this.seed,
    required this.simVersion,
    required this.startedAt,
    this.finishedAt,
    required this.status,
    this.score,
    this.ticks,
    this.rejectReason,
    bool? unverifiable,
    this.inputLog,
  }) : unverifiable = unverifiable ?? false;

  factory GameRun({
    int? id,
    required _is.UuidValue authUserId,
    required int seed,
    required int simVersion,
    required DateTime startedAt,
    DateTime? finishedAt,
    required _ipc0ayvg.RunStatus status,
    int? score,
    int? ticks,
    String? rejectReason,
    bool? unverifiable,
    _idt.ByteData? inputLog,
  }) = _GameRunImpl;

  factory GameRun.fromJson(Map<String, dynamic> jsonSerialization) {
    return GameRun(
      id: jsonSerialization['id'] as int?,
      authUserId: _is.UuidValueJsonExtension.fromJson(
        jsonSerialization['authUserId'],
      ),
      seed: jsonSerialization['seed'] as int,
      simVersion: jsonSerialization['simVersion'] as int,
      startedAt: _is.DateTimeJsonExtension.fromJson(
        jsonSerialization['startedAt'],
      ),
      finishedAt: jsonSerialization['finishedAt'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(jsonSerialization['finishedAt']),
      status: _ipc0ayvg.RunStatus.fromJson(
        (jsonSerialization['status'] as String),
      ),
      score: jsonSerialization['score'] as int?,
      ticks: jsonSerialization['ticks'] as int?,
      rejectReason: jsonSerialization['rejectReason'] as String?,
      unverifiable: jsonSerialization['unverifiable'] == null
          ? null
          : _is.BoolJsonExtension.fromJson(jsonSerialization['unverifiable']),
      inputLog: jsonSerialization['inputLog'] == null
          ? null
          : _is.ByteDataJsonExtension.fromJson(jsonSerialization['inputLog']),
    );
  }

  static final t = GameRunTable();

  static const db = GameRunRepository._();

  @override
  int? id;

  _is.UuidValue authUserId;

  int seed;

  int simVersion;

  DateTime startedAt;

  DateTime? finishedAt;

  _ipc0ayvg.RunStatus status;

  /// Verified score, from replaying the run on the server.
  int? score;

  int? ticks;

  String? rejectReason;

  /// The app's simulation differed from the server's when the run started,
  /// so its result can't be verified. Not cheating (likely an outdated app):
  /// the run is quietly left out instead.
  bool unverifiable;

  /// The submitted steering inputs (InputLog encoding), kept so any run can
  /// be replayed again later, e.g. to investigate a rejection.
  _idt.ByteData? inputLog;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [GameRun]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  GameRun copyWith({
    int? id,
    _is.UuidValue? authUserId,
    int? seed,
    int? simVersion,
    DateTime? startedAt,
    DateTime? finishedAt = const _is.$UndefinedDateTime(),
    _ipc0ayvg.RunStatus? status,
    int? score,
    int? ticks,
    String? rejectReason,
    bool? unverifiable,
    _idt.ByteData? inputLog,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'GameRun',
      if (id != null) 'id': id,
      'authUserId': authUserId.toJson(),
      'seed': seed,
      'simVersion': simVersion,
      'startedAt': startedAt.toJson(),
      if (finishedAt != null) 'finishedAt': finishedAt?.toJson(),
      'status': status.toJson(),
      if (score != null) 'score': score,
      if (ticks != null) 'ticks': ticks,
      if (rejectReason != null) 'rejectReason': rejectReason,
      'unverifiable': unverifiable,
      if (inputLog != null) 'inputLog': inputLog?.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static GameRunInclude include() {
    return GameRunInclude._();
  }

  static GameRunIncludeList includeList({
    _is.WhereExpressionBuilder<GameRunTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<GameRunTable>? orderBy,
    _is.OrderByListBuilder<GameRunTable>? orderByList,
    GameRunInclude? include,
  }) {
    return GameRunIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(GameRun.t),
      orderByList: orderByList?.call(GameRun.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _GameRunImpl extends GameRun {
  _GameRunImpl({
    int? id,
    required _is.UuidValue authUserId,
    required int seed,
    required int simVersion,
    required DateTime startedAt,
    DateTime? finishedAt,
    required _ipc0ayvg.RunStatus status,
    int? score,
    int? ticks,
    String? rejectReason,
    bool? unverifiable,
    _idt.ByteData? inputLog,
  }) : super._(
         id: id,
         authUserId: authUserId,
         seed: seed,
         simVersion: simVersion,
         startedAt: startedAt,
         finishedAt: finishedAt,
         status: status,
         score: score,
         ticks: ticks,
         rejectReason: rejectReason,
         unverifiable: unverifiable,
         inputLog: inputLog,
       );

  /// Returns a shallow copy of this [GameRun]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  GameRun copyWith({
    Object? id = _Undefined,
    _is.UuidValue? authUserId,
    int? seed,
    int? simVersion,
    DateTime? startedAt,
    DateTime? finishedAt = const _is.$UndefinedDateTime(),
    _ipc0ayvg.RunStatus? status,
    Object? score = _Undefined,
    Object? ticks = _Undefined,
    Object? rejectReason = _Undefined,
    bool? unverifiable,
    Object? inputLog = _Undefined,
  }) {
    return GameRun(
      id: id is int? ? id : this.id,
      authUserId: authUserId ?? this.authUserId,
      seed: seed ?? this.seed,
      simVersion: simVersion ?? this.simVersion,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt is _is.UndefinedSentinel
          ? this.finishedAt
          : finishedAt,
      status: status ?? this.status,
      score: score is int? ? score : this.score,
      ticks: ticks is int? ? ticks : this.ticks,
      rejectReason: rejectReason is String? ? rejectReason : this.rejectReason,
      unverifiable: unverifiable ?? this.unverifiable,
      inputLog: inputLog is _idt.ByteData? ? inputLog : this.inputLog?.clone(),
    );
  }
}

class GameRunUpdateTable extends _is.UpdateTable<GameRunTable> {
  GameRunUpdateTable(super.table);

  _is.ColumnValue<_is.UuidValue, _is.UuidValue> authUserId(
    _is.UuidValue value,
  ) => _is.ColumnValue(
    table.authUserId,
    value,
  );

  _is.ColumnValue<int, int> seed(int value) => _is.ColumnValue(
    table.seed,
    value,
  );

  _is.ColumnValue<int, int> simVersion(int value) => _is.ColumnValue(
    table.simVersion,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> startedAt(DateTime value) =>
      _is.ColumnValue(
        table.startedAt,
        value,
      );

  _is.ColumnValue<DateTime, DateTime> finishedAt(DateTime? value) =>
      _is.ColumnValue(
        table.finishedAt,
        value,
      );

  _is.ColumnValue<_ipc0ayvg.RunStatus, _ipc0ayvg.RunStatus> status(
    _ipc0ayvg.RunStatus value,
  ) => _is.ColumnValue(
    table.status,
    value,
  );

  _is.ColumnValue<int, int> score(int? value) => _is.ColumnValue(
    table.score,
    value,
  );

  _is.ColumnValue<int, int> ticks(int? value) => _is.ColumnValue(
    table.ticks,
    value,
  );

  _is.ColumnValue<String, String> rejectReason(String? value) =>
      _is.ColumnValue(
        table.rejectReason,
        value,
      );

  _is.ColumnValue<bool, bool> unverifiable(bool value) => _is.ColumnValue(
    table.unverifiable,
    value,
  );

  _is.ColumnValue<_idt.ByteData, _idt.ByteData> inputLog(
    _idt.ByteData? value,
  ) => _is.ColumnValue(
    table.inputLog,
    value,
  );
}

class GameRunTable extends _is.Table<int?> {
  GameRunTable({super.tableRelation}) : super(tableName: 'game_run') {
    updateTable = GameRunUpdateTable(this);
    authUserId = _is.ColumnUuid(
      'authUserId',
      this,
    );
    seed = _is.ColumnInt(
      'seed',
      this,
    );
    simVersion = _is.ColumnInt(
      'simVersion',
      this,
    );
    startedAt = _is.ColumnDateTime(
      'startedAt',
      this,
    );
    finishedAt = _is.ColumnDateTime(
      'finishedAt',
      this,
    );
    status = _is.ColumnEnum(
      'status',
      this,
      _is.EnumSerialization.byName,
    );
    score = _is.ColumnInt(
      'score',
      this,
    );
    ticks = _is.ColumnInt(
      'ticks',
      this,
    );
    rejectReason = _is.ColumnString(
      'rejectReason',
      this,
    );
    unverifiable = _is.ColumnBool(
      'unverifiable',
      this,
      hasDefault: true,
    );
    inputLog = _is.ColumnByteData(
      'inputLog',
      this,
    );
  }

  late final GameRunUpdateTable updateTable;

  late final _is.ColumnUuid authUserId;

  late final _is.ColumnInt seed;

  late final _is.ColumnInt simVersion;

  late final _is.ColumnDateTime startedAt;

  late final _is.ColumnDateTime finishedAt;

  late final _is.ColumnEnum<_ipc0ayvg.RunStatus> status;

  /// Verified score, from replaying the run on the server.
  late final _is.ColumnInt score;

  late final _is.ColumnInt ticks;

  late final _is.ColumnString rejectReason;

  /// The app's simulation differed from the server's when the run started,
  /// so its result can't be verified. Not cheating (likely an outdated app):
  /// the run is quietly left out instead.
  late final _is.ColumnBool unverifiable;

  /// The submitted steering inputs (InputLog encoding), kept so any run can
  /// be replayed again later, e.g. to investigate a rejection.
  late final _is.ColumnByteData inputLog;

  @override
  List<_is.Column> get columns => [
    id,
    authUserId,
    seed,
    simVersion,
    startedAt,
    finishedAt,
    status,
    score,
    ticks,
    rejectReason,
    unverifiable,
    inputLog,
  ];
}

class GameRunInclude extends _is.IncludeObject {
  GameRunInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => GameRun.t;
}

class GameRunIncludeList extends _is.IncludeList {
  GameRunIncludeList._({
    _is.WhereExpressionBuilder<GameRunTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(GameRun.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => GameRun.t;
}

class GameRunRepository {
  const GameRunRepository._();

  /// Returns a list of [GameRun]s matching the given query parameters.
  ///
  /// Use [where] to specify which items to include in the return value.
  /// If none is specified, all items will be returned.
  ///
  /// To specify the order of the items use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// The maximum number of items can be set by [limit]. If no limit is set,
  /// all items matching the query will be returned.
  ///
  /// [offset] defines how many items to skip, after which [limit] (or all)
  /// items are read from the database.
  ///
  /// ```dart
  /// var persons = await Persons.db.find(
  ///   session,
  ///   where: (t) => t.lastName.equals('Jones'),
  ///   orderBy: (t) => t.firstName,
  ///   limit: 100,
  /// );
  /// ```
  Future<List<GameRun>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<GameRunTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<GameRunTable>? orderBy,
    _is.OrderByListBuilder<GameRunTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<GameRun>(
      where: where?.call(GameRun.t),
      orderBy: orderBy?.call(GameRun.t),
      orderByList: orderByList?.call(GameRun.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Emits [GameRun]s matching the given query parameters every time the
  /// source tables are modified.
  ///
  /// Use [where] to specify which items to include in the return value.
  /// If none is specified, all items will be returned.
  ///
  /// To specify the order of the items use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// The maximum number of items can be set by [limit]. If no limit is set,
  /// all items matching the query will be returned.
  ///
  /// [offset] defines how many items to skip, after which [limit] (or all)
  /// items are read from the database.
  ///
  /// Use [throttle] to specify the minimum interval between queries. It can
  /// also be set to `null`, in which case the stream will only be throttled
  /// when its subscription is paused.
  ///
  /// Source tables are collected from the queried table, [where], [orderBy],
  /// [orderByList], and the [include] graph. [alsoTriggerOnTables] is added
  /// to that set. Pass [Table] instances such as `GameRun.t`.
  ///
  /// Raw [Expression] SQL is not inspected. Tables referenced only in raw
  /// SQL must be passed via [alsoTriggerOnTables].
  ///
  /// The stream always reads committed state and never joins an ambient
  /// [Transaction]. Emissions for a write fire after that write commits.
  ///
  /// Currently only supported on SQLite. Calling this method on PostgreSQL
  /// throws an [UnsupportedError].
  ///
  /// ```dart
  /// var subscription = Persons.db.watch(
  ///   session,
  ///   where: (t) => t.lastName.equals('Jones'),
  ///   orderBy: (t) => t.firstName,
  ///   limit: 100,
  /// ).listen((persons) {
  ///   // Handle the latest matching rows.
  /// });
  /// ```
  _ida.Stream<List<GameRun>> watch(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<GameRunTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<GameRunTable>? orderBy,
    _is.OrderByListBuilder<GameRunTable>? orderByList,
    Duration? throttle = const Duration(milliseconds: 30),
    Iterable<_is.Table>? alsoTriggerOnTables,
  }) {
    return session.db.watch<GameRun>(
      where: where?.call(GameRun.t),
      orderBy: orderBy?.call(GameRun.t),
      orderByList: orderByList?.call(GameRun.t),
      limit: limit,
      offset: offset,
      throttle: throttle,
      alsoTriggerOnTables: alsoTriggerOnTables,
    );
  }

  /// Returns the first matching [GameRun] matching the given query parameters.
  ///
  /// Use [where] to specify which items to include in the return value.
  /// If none is specified, all items will be returned.
  ///
  /// To specify the order use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// [offset] defines how many items to skip, after which the next one will be picked.
  ///
  /// ```dart
  /// var youngestPerson = await Persons.db.findFirstRow(
  ///   session,
  ///   where: (t) => t.lastName.equals('Jones'),
  ///   orderBy: (t) => t.age,
  /// );
  /// ```
  Future<GameRun?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<GameRunTable>? where,
    int? offset,
    _is.OrderByBuilder<GameRunTable>? orderBy,
    _is.OrderByListBuilder<GameRunTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<GameRun>(
      where: where?.call(GameRun.t),
      orderBy: orderBy?.call(GameRun.t),
      orderByList: orderByList?.call(GameRun.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [GameRun] by its [id] or null if no such row exists.
  Future<GameRun?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<GameRun>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [GameRun]s in the list and returns the inserted rows.
  ///
  /// The returned [GameRun]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  ///
  /// If [noReturn] is set to `true`, the inserted rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<GameRun>> insert(
    _is.DatabaseSession session,
    List<GameRun> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<GameRun>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [GameRun] and returns the inserted row.
  ///
  /// The returned [GameRun] will have its `id` field set.
  Future<GameRun> insertRow(
    _is.DatabaseSession session,
    GameRun row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<GameRun>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [GameRun]s in the list and returns the resulting rows.
  ///
  /// If a row conflicts on the given [conflictColumns], the existing row is
  /// updated with the new values. Otherwise, a new row is inserted.
  ///
  /// If [updateColumns] is provided, only those columns will be updated on
  /// conflict. If null, all non-conflict, non-id columns are updated.
  ///
  /// If [updateWhere] is provided, the update only applies to rows matching the
  /// given expression. Conflicting rows that don't match are skipped and not
  /// returned, so the resulting list may be shorter than [rows].
  ///
  /// The returned [GameRun]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<GameRun>> upsert(
    _is.DatabaseSession session,
    List<GameRun> rows, {
    required _is.ColumnSelections<GameRunTable> conflictColumns,
    _is.ColumnSelections<GameRunTable>? updateColumns,
    _is.WhereExpressionBuilder<GameRunTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<GameRun>(
      rows,
      conflictColumns: conflictColumns(GameRun.t),
      updateColumns: updateColumns?.call(GameRun.t),
      updateWhere: updateWhere?.call(GameRun.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [GameRun] and returns the resulting row.
  ///
  /// If the row conflicts on the given [conflictColumns], the existing row is
  /// updated. Otherwise, a new row is inserted.
  ///
  /// If [updateColumns] is provided, only those columns will be updated on
  /// conflict. If null, all non-conflict, non-id columns are updated.
  ///
  /// If [updateWhere] is provided, the update only applies when the existing
  /// row matches the expression. Returns `null` if no row was affected — for
  /// example when [updateWhere] does not match the conflicting row.
  ///
  /// The returned [GameRun] will have its `id` field set.
  Future<GameRun?> upsertRow(
    _is.DatabaseSession session,
    GameRun row, {
    required _is.ColumnSelections<GameRunTable> conflictColumns,
    _is.ColumnSelections<GameRunTable>? updateColumns,
    _is.WhereExpressionBuilder<GameRunTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<GameRun>(
      row,
      conflictColumns: conflictColumns(GameRun.t),
      updateColumns: updateColumns?.call(GameRun.t),
      updateWhere: updateWhere?.call(GameRun.t),
      transaction: transaction,
    );
  }

  /// Updates all [GameRun]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<GameRun>> update(
    _is.DatabaseSession session,
    List<GameRun> rows, {
    _is.ColumnSelections<GameRunTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<GameRun>(
      rows,
      columns: columns?.call(GameRun.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [GameRun]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<GameRun> updateRow(
    _is.DatabaseSession session,
    GameRun row, {
    _is.ColumnSelections<GameRunTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<GameRun>(
      row,
      columns: columns?.call(GameRun.t),
      transaction: transaction,
    );
  }

  /// Updates a single [GameRun] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<GameRun?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<GameRunUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<GameRun>(
      id,
      columnValues: columnValues(GameRun.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [GameRun]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<GameRun>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<GameRunUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<GameRunTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<GameRunTable>? orderBy,
    _is.OrderByListBuilder<GameRunTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<GameRun>(
      columnValues: columnValues(GameRun.t.updateTable),
      where: where(GameRun.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(GameRun.t),
      orderByList: orderByList?.call(GameRun.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [GameRun]s in the list and returns the deleted rows.
  ///
  /// To specify the order of the returned rows use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  ///
  /// If [noReturn] is set to `true`, the deleted rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<GameRun>> delete(
    _is.DatabaseSession session,
    List<GameRun> rows, {
    _is.OrderByBuilder<GameRunTable>? orderBy,
    _is.OrderByListBuilder<GameRunTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<GameRun>(
      rows,
      orderBy: orderBy?.call(GameRun.t),
      orderByList: orderByList?.call(GameRun.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [GameRun].
  Future<GameRun> deleteRow(
    _is.DatabaseSession session,
    GameRun row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<GameRun>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  ///
  /// To specify the order of the returned rows use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// If [noReturn] is set to `true`, the deleted rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<GameRun>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<GameRunTable> where,
    _is.OrderByBuilder<GameRunTable>? orderBy,
    _is.OrderByListBuilder<GameRunTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<GameRun>(
      where: where(GameRun.t),
      orderBy: orderBy?.call(GameRun.t),
      orderByList: orderByList?.call(GameRun.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<GameRunTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<GameRun>(
      where: where?.call(GameRun.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [GameRun] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<GameRunTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<GameRun>(
      where: where(GameRun.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
