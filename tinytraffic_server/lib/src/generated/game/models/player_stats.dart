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
import 'package:serverpod/serverpod.dart' as _is;

/// Best score and totals per player.
abstract class PlayerStats
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  PlayerStats._({
    this.id,
    required this.authUserId,
    required this.nickname,
    required this.bestScore,
    this.bestRunId,
    this.bestAt,
    required this.totalRuns,
    required this.totalCoins,
    bool? shadowBanned,
    this.banReason,
    this.bannedAt,
  }) : shadowBanned = shadowBanned ?? false;

  factory PlayerStats({
    int? id,
    required _is.UuidValue authUserId,
    required String nickname,
    required int bestScore,
    int? bestRunId,
    DateTime? bestAt,
    required int totalRuns,
    required int totalCoins,
    bool? shadowBanned,
    String? banReason,
    DateTime? bannedAt,
  }) = _PlayerStatsImpl;

  factory PlayerStats.fromJson(Map<String, dynamic> jsonSerialization) {
    return PlayerStats(
      id: jsonSerialization['id'] as int?,
      authUserId: _is.UuidValueJsonExtension.fromJson(
        jsonSerialization['authUserId'],
      ),
      nickname: jsonSerialization['nickname'] as String,
      bestScore: jsonSerialization['bestScore'] as int,
      bestRunId: jsonSerialization['bestRunId'] as int?,
      bestAt: jsonSerialization['bestAt'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(jsonSerialization['bestAt']),
      totalRuns: jsonSerialization['totalRuns'] as int,
      totalCoins: jsonSerialization['totalCoins'] as int,
      shadowBanned: jsonSerialization['shadowBanned'] == null
          ? null
          : _is.BoolJsonExtension.fromJson(jsonSerialization['shadowBanned']),
      banReason: jsonSerialization['banReason'] as String?,
      bannedAt: jsonSerialization['bannedAt'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(jsonSerialization['bannedAt']),
    );
  }

  static final t = PlayerStatsTable();

  static const db = PlayerStatsRepository._();

  @override
  int? id;

  _is.UuidValue authUserId;

  String nickname;

  int bestScore;

  int? bestRunId;

  DateTime? bestAt;

  int totalRuns;

  int totalCoins;

  /// Shadow-banned players still see their own scores, but nobody else's
  /// placings or leaderboard count them. Set when a run fails verification
  /// in a way only a cheat can cause; clear it to lift the ban.
  bool shadowBanned;

  String? banReason;

  DateTime? bannedAt;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [PlayerStats]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  PlayerStats copyWith({
    int? id,
    _is.UuidValue? authUserId,
    String? nickname,
    int? bestScore,
    int? bestRunId,
    DateTime? bestAt = const _is.$UndefinedDateTime(),
    int? totalRuns,
    int? totalCoins,
    bool? shadowBanned,
    String? banReason,
    DateTime? bannedAt = const _is.$UndefinedDateTime(),
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'PlayerStats',
      if (id != null) 'id': id,
      'authUserId': authUserId.toJson(),
      'nickname': nickname,
      'bestScore': bestScore,
      if (bestRunId != null) 'bestRunId': bestRunId,
      if (bestAt != null) 'bestAt': bestAt?.toJson(),
      'totalRuns': totalRuns,
      'totalCoins': totalCoins,
      'shadowBanned': shadowBanned,
      if (banReason != null) 'banReason': banReason,
      if (bannedAt != null) 'bannedAt': bannedAt?.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static PlayerStatsInclude include() {
    return PlayerStatsInclude._();
  }

  static PlayerStatsIncludeList includeList({
    _is.WhereExpressionBuilder<PlayerStatsTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<PlayerStatsTable>? orderBy,
    _is.OrderByListBuilder<PlayerStatsTable>? orderByList,
    PlayerStatsInclude? include,
  }) {
    return PlayerStatsIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(PlayerStats.t),
      orderByList: orderByList?.call(PlayerStats.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _PlayerStatsImpl extends PlayerStats {
  _PlayerStatsImpl({
    int? id,
    required _is.UuidValue authUserId,
    required String nickname,
    required int bestScore,
    int? bestRunId,
    DateTime? bestAt,
    required int totalRuns,
    required int totalCoins,
    bool? shadowBanned,
    String? banReason,
    DateTime? bannedAt,
  }) : super._(
         id: id,
         authUserId: authUserId,
         nickname: nickname,
         bestScore: bestScore,
         bestRunId: bestRunId,
         bestAt: bestAt,
         totalRuns: totalRuns,
         totalCoins: totalCoins,
         shadowBanned: shadowBanned,
         banReason: banReason,
         bannedAt: bannedAt,
       );

  /// Returns a shallow copy of this [PlayerStats]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  PlayerStats copyWith({
    Object? id = _Undefined,
    _is.UuidValue? authUserId,
    String? nickname,
    int? bestScore,
    Object? bestRunId = _Undefined,
    DateTime? bestAt = const _is.$UndefinedDateTime(),
    int? totalRuns,
    int? totalCoins,
    bool? shadowBanned,
    Object? banReason = _Undefined,
    DateTime? bannedAt = const _is.$UndefinedDateTime(),
  }) {
    return PlayerStats(
      id: id is int? ? id : this.id,
      authUserId: authUserId ?? this.authUserId,
      nickname: nickname ?? this.nickname,
      bestScore: bestScore ?? this.bestScore,
      bestRunId: bestRunId is int? ? bestRunId : this.bestRunId,
      bestAt: bestAt is _is.UndefinedSentinel ? this.bestAt : bestAt,
      totalRuns: totalRuns ?? this.totalRuns,
      totalCoins: totalCoins ?? this.totalCoins,
      shadowBanned: shadowBanned ?? this.shadowBanned,
      banReason: banReason is String? ? banReason : this.banReason,
      bannedAt: bannedAt is _is.UndefinedSentinel ? this.bannedAt : bannedAt,
    );
  }
}

class PlayerStatsUpdateTable extends _is.UpdateTable<PlayerStatsTable> {
  PlayerStatsUpdateTable(super.table);

  _is.ColumnValue<_is.UuidValue, _is.UuidValue> authUserId(
    _is.UuidValue value,
  ) => _is.ColumnValue(
    table.authUserId,
    value,
  );

  _is.ColumnValue<String, String> nickname(String value) => _is.ColumnValue(
    table.nickname,
    value,
  );

  _is.ColumnValue<int, int> bestScore(int value) => _is.ColumnValue(
    table.bestScore,
    value,
  );

  _is.ColumnValue<int, int> bestRunId(int? value) => _is.ColumnValue(
    table.bestRunId,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> bestAt(DateTime? value) =>
      _is.ColumnValue(
        table.bestAt,
        value,
      );

  _is.ColumnValue<int, int> totalRuns(int value) => _is.ColumnValue(
    table.totalRuns,
    value,
  );

  _is.ColumnValue<int, int> totalCoins(int value) => _is.ColumnValue(
    table.totalCoins,
    value,
  );

  _is.ColumnValue<bool, bool> shadowBanned(bool value) => _is.ColumnValue(
    table.shadowBanned,
    value,
  );

  _is.ColumnValue<String, String> banReason(String? value) => _is.ColumnValue(
    table.banReason,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> bannedAt(DateTime? value) =>
      _is.ColumnValue(
        table.bannedAt,
        value,
      );
}

class PlayerStatsTable extends _is.Table<int?> {
  PlayerStatsTable({super.tableRelation}) : super(tableName: 'player_stats') {
    updateTable = PlayerStatsUpdateTable(this);
    authUserId = _is.ColumnUuid(
      'authUserId',
      this,
    );
    nickname = _is.ColumnString(
      'nickname',
      this,
    );
    bestScore = _is.ColumnInt(
      'bestScore',
      this,
    );
    bestRunId = _is.ColumnInt(
      'bestRunId',
      this,
    );
    bestAt = _is.ColumnDateTime(
      'bestAt',
      this,
    );
    totalRuns = _is.ColumnInt(
      'totalRuns',
      this,
    );
    totalCoins = _is.ColumnInt(
      'totalCoins',
      this,
    );
    shadowBanned = _is.ColumnBool(
      'shadowBanned',
      this,
      hasDefault: true,
    );
    banReason = _is.ColumnString(
      'banReason',
      this,
    );
    bannedAt = _is.ColumnDateTime(
      'bannedAt',
      this,
    );
  }

  late final PlayerStatsUpdateTable updateTable;

  late final _is.ColumnUuid authUserId;

  late final _is.ColumnString nickname;

  late final _is.ColumnInt bestScore;

  late final _is.ColumnInt bestRunId;

  late final _is.ColumnDateTime bestAt;

  late final _is.ColumnInt totalRuns;

  late final _is.ColumnInt totalCoins;

  /// Shadow-banned players still see their own scores, but nobody else's
  /// placings or leaderboard count them. Set when a run fails verification
  /// in a way only a cheat can cause; clear it to lift the ban.
  late final _is.ColumnBool shadowBanned;

  late final _is.ColumnString banReason;

  late final _is.ColumnDateTime bannedAt;

  @override
  List<_is.Column> get columns => [
    id,
    authUserId,
    nickname,
    bestScore,
    bestRunId,
    bestAt,
    totalRuns,
    totalCoins,
    shadowBanned,
    banReason,
    bannedAt,
  ];
}

class PlayerStatsInclude extends _is.IncludeObject {
  PlayerStatsInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => PlayerStats.t;
}

class PlayerStatsIncludeList extends _is.IncludeList {
  PlayerStatsIncludeList._({
    _is.WhereExpressionBuilder<PlayerStatsTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(PlayerStats.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => PlayerStats.t;
}

class PlayerStatsRepository {
  const PlayerStatsRepository._();

  /// Returns a list of [PlayerStats]s matching the given query parameters.
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
  Future<List<PlayerStats>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<PlayerStatsTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<PlayerStatsTable>? orderBy,
    _is.OrderByListBuilder<PlayerStatsTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<PlayerStats>(
      where: where?.call(PlayerStats.t),
      orderBy: orderBy?.call(PlayerStats.t),
      orderByList: orderByList?.call(PlayerStats.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Emits [PlayerStats]s matching the given query parameters every time the
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
  /// to that set. Pass [Table] instances such as `PlayerStats.t`.
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
  _ida.Stream<List<PlayerStats>> watch(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<PlayerStatsTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<PlayerStatsTable>? orderBy,
    _is.OrderByListBuilder<PlayerStatsTable>? orderByList,
    Duration? throttle = const Duration(milliseconds: 30),
    Iterable<_is.Table>? alsoTriggerOnTables,
  }) {
    return session.db.watch<PlayerStats>(
      where: where?.call(PlayerStats.t),
      orderBy: orderBy?.call(PlayerStats.t),
      orderByList: orderByList?.call(PlayerStats.t),
      limit: limit,
      offset: offset,
      throttle: throttle,
      alsoTriggerOnTables: alsoTriggerOnTables,
    );
  }

  /// Returns the first matching [PlayerStats] matching the given query parameters.
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
  Future<PlayerStats?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<PlayerStatsTable>? where,
    int? offset,
    _is.OrderByBuilder<PlayerStatsTable>? orderBy,
    _is.OrderByListBuilder<PlayerStatsTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<PlayerStats>(
      where: where?.call(PlayerStats.t),
      orderBy: orderBy?.call(PlayerStats.t),
      orderByList: orderByList?.call(PlayerStats.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [PlayerStats] by its [id] or null if no such row exists.
  Future<PlayerStats?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<PlayerStats>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [PlayerStats]s in the list and returns the inserted rows.
  ///
  /// The returned [PlayerStats]s will have their `id` fields set.
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
  Future<List<PlayerStats>> insert(
    _is.DatabaseSession session,
    List<PlayerStats> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<PlayerStats>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [PlayerStats] and returns the inserted row.
  ///
  /// The returned [PlayerStats] will have its `id` field set.
  Future<PlayerStats> insertRow(
    _is.DatabaseSession session,
    PlayerStats row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<PlayerStats>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [PlayerStats]s in the list and returns the resulting rows.
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
  /// The returned [PlayerStats]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<PlayerStats>> upsert(
    _is.DatabaseSession session,
    List<PlayerStats> rows, {
    required _is.ColumnSelections<PlayerStatsTable> conflictColumns,
    _is.ColumnSelections<PlayerStatsTable>? updateColumns,
    _is.WhereExpressionBuilder<PlayerStatsTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<PlayerStats>(
      rows,
      conflictColumns: conflictColumns(PlayerStats.t),
      updateColumns: updateColumns?.call(PlayerStats.t),
      updateWhere: updateWhere?.call(PlayerStats.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [PlayerStats] and returns the resulting row.
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
  /// The returned [PlayerStats] will have its `id` field set.
  Future<PlayerStats?> upsertRow(
    _is.DatabaseSession session,
    PlayerStats row, {
    required _is.ColumnSelections<PlayerStatsTable> conflictColumns,
    _is.ColumnSelections<PlayerStatsTable>? updateColumns,
    _is.WhereExpressionBuilder<PlayerStatsTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<PlayerStats>(
      row,
      conflictColumns: conflictColumns(PlayerStats.t),
      updateColumns: updateColumns?.call(PlayerStats.t),
      updateWhere: updateWhere?.call(PlayerStats.t),
      transaction: transaction,
    );
  }

  /// Updates all [PlayerStats]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<PlayerStats>> update(
    _is.DatabaseSession session,
    List<PlayerStats> rows, {
    _is.ColumnSelections<PlayerStatsTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<PlayerStats>(
      rows,
      columns: columns?.call(PlayerStats.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [PlayerStats]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<PlayerStats> updateRow(
    _is.DatabaseSession session,
    PlayerStats row, {
    _is.ColumnSelections<PlayerStatsTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<PlayerStats>(
      row,
      columns: columns?.call(PlayerStats.t),
      transaction: transaction,
    );
  }

  /// Updates a single [PlayerStats] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<PlayerStats?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<PlayerStatsUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<PlayerStats>(
      id,
      columnValues: columnValues(PlayerStats.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [PlayerStats]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<PlayerStats>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<PlayerStatsUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<PlayerStatsTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<PlayerStatsTable>? orderBy,
    _is.OrderByListBuilder<PlayerStatsTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<PlayerStats>(
      columnValues: columnValues(PlayerStats.t.updateTable),
      where: where(PlayerStats.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(PlayerStats.t),
      orderByList: orderByList?.call(PlayerStats.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [PlayerStats]s in the list and returns the deleted rows.
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
  Future<List<PlayerStats>> delete(
    _is.DatabaseSession session,
    List<PlayerStats> rows, {
    _is.OrderByBuilder<PlayerStatsTable>? orderBy,
    _is.OrderByListBuilder<PlayerStatsTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<PlayerStats>(
      rows,
      orderBy: orderBy?.call(PlayerStats.t),
      orderByList: orderByList?.call(PlayerStats.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [PlayerStats].
  Future<PlayerStats> deleteRow(
    _is.DatabaseSession session,
    PlayerStats row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<PlayerStats>(
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
  Future<List<PlayerStats>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<PlayerStatsTable> where,
    _is.OrderByBuilder<PlayerStatsTable>? orderBy,
    _is.OrderByListBuilder<PlayerStatsTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<PlayerStats>(
      where: where(PlayerStats.t),
      orderBy: orderBy?.call(PlayerStats.t),
      orderByList: orderByList?.call(PlayerStats.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<PlayerStatsTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<PlayerStats>(
      where: where?.call(PlayerStats.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [PlayerStats] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<PlayerStatsTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<PlayerStats>(
      where: where(PlayerStats.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
