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

/// How many players have each best score, counting the players who count for
/// other players' placings (at least one run, not shadow-banned). Kept in
/// step with player_stats, so a placing adds up a few of these rows instead of
/// counting through every player.
abstract class ScoreCount
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  ScoreCount._({
    this.id,
    required this.score,
    required this.players,
  });

  factory ScoreCount({
    int? id,
    required int score,
    required int players,
  }) = _ScoreCountImpl;

  factory ScoreCount.fromJson(Map<String, dynamic> jsonSerialization) {
    return ScoreCount(
      id: jsonSerialization['id'] as int?,
      score: jsonSerialization['score'] as int,
      players: jsonSerialization['players'] as int,
    );
  }

  static final t = ScoreCountTable();

  static const db = ScoreCountRepository._();

  @override
  int? id;

  int score;

  int players;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [ScoreCount]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  ScoreCount copyWith({
    int? id,
    int? score,
    int? players,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'ScoreCount',
      if (id != null) 'id': id,
      'score': score,
      'players': players,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static ScoreCountInclude include() {
    return ScoreCountInclude._();
  }

  static ScoreCountIncludeList includeList({
    _is.WhereExpressionBuilder<ScoreCountTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<ScoreCountTable>? orderBy,
    _is.OrderByListBuilder<ScoreCountTable>? orderByList,
    ScoreCountInclude? include,
  }) {
    return ScoreCountIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(ScoreCount.t),
      orderByList: orderByList?.call(ScoreCount.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _ScoreCountImpl extends ScoreCount {
  _ScoreCountImpl({
    int? id,
    required int score,
    required int players,
  }) : super._(
         id: id,
         score: score,
         players: players,
       );

  /// Returns a shallow copy of this [ScoreCount]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  ScoreCount copyWith({
    Object? id = _Undefined,
    int? score,
    int? players,
  }) {
    return ScoreCount(
      id: id is int? ? id : this.id,
      score: score ?? this.score,
      players: players ?? this.players,
    );
  }
}

class ScoreCountUpdateTable extends _is.UpdateTable<ScoreCountTable> {
  ScoreCountUpdateTable(super.table);

  _is.ColumnValue<int, int> score(int value) => _is.ColumnValue(
    table.score,
    value,
  );

  _is.ColumnValue<int, int> players(int value) => _is.ColumnValue(
    table.players,
    value,
  );
}

class ScoreCountTable extends _is.Table<int?> {
  ScoreCountTable({super.tableRelation}) : super(tableName: 'score_count') {
    updateTable = ScoreCountUpdateTable(this);
    score = _is.ColumnInt(
      'score',
      this,
    );
    players = _is.ColumnInt(
      'players',
      this,
    );
  }

  late final ScoreCountUpdateTable updateTable;

  late final _is.ColumnInt score;

  late final _is.ColumnInt players;

  @override
  List<_is.Column> get columns => [
    id,
    score,
    players,
  ];
}

class ScoreCountInclude extends _is.IncludeObject {
  ScoreCountInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => ScoreCount.t;
}

class ScoreCountIncludeList extends _is.IncludeList {
  ScoreCountIncludeList._({
    _is.WhereExpressionBuilder<ScoreCountTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(ScoreCount.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => ScoreCount.t;
}

class ScoreCountRepository {
  const ScoreCountRepository._();

  /// Returns a list of [ScoreCount]s matching the given query parameters.
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
  Future<List<ScoreCount>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<ScoreCountTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<ScoreCountTable>? orderBy,
    _is.OrderByListBuilder<ScoreCountTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<ScoreCount>(
      where: where?.call(ScoreCount.t),
      orderBy: orderBy?.call(ScoreCount.t),
      orderByList: orderByList?.call(ScoreCount.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Emits [ScoreCount]s matching the given query parameters every time the
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
  /// to that set. Pass [Table] instances such as `ScoreCount.t`.
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
  _ida.Stream<List<ScoreCount>> watch(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<ScoreCountTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<ScoreCountTable>? orderBy,
    _is.OrderByListBuilder<ScoreCountTable>? orderByList,
    Duration? throttle = const Duration(milliseconds: 30),
    Iterable<_is.Table>? alsoTriggerOnTables,
  }) {
    return session.db.watch<ScoreCount>(
      where: where?.call(ScoreCount.t),
      orderBy: orderBy?.call(ScoreCount.t),
      orderByList: orderByList?.call(ScoreCount.t),
      limit: limit,
      offset: offset,
      throttle: throttle,
      alsoTriggerOnTables: alsoTriggerOnTables,
    );
  }

  /// Returns the first matching [ScoreCount] matching the given query parameters.
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
  Future<ScoreCount?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<ScoreCountTable>? where,
    int? offset,
    _is.OrderByBuilder<ScoreCountTable>? orderBy,
    _is.OrderByListBuilder<ScoreCountTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<ScoreCount>(
      where: where?.call(ScoreCount.t),
      orderBy: orderBy?.call(ScoreCount.t),
      orderByList: orderByList?.call(ScoreCount.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [ScoreCount] by its [id] or null if no such row exists.
  Future<ScoreCount?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<ScoreCount>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [ScoreCount]s in the list and returns the inserted rows.
  ///
  /// The returned [ScoreCount]s will have their `id` fields set.
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
  Future<List<ScoreCount>> insert(
    _is.DatabaseSession session,
    List<ScoreCount> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<ScoreCount>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [ScoreCount] and returns the inserted row.
  ///
  /// The returned [ScoreCount] will have its `id` field set.
  Future<ScoreCount> insertRow(
    _is.DatabaseSession session,
    ScoreCount row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<ScoreCount>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [ScoreCount]s in the list and returns the resulting rows.
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
  /// The returned [ScoreCount]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<ScoreCount>> upsert(
    _is.DatabaseSession session,
    List<ScoreCount> rows, {
    required _is.ColumnSelections<ScoreCountTable> conflictColumns,
    _is.ColumnSelections<ScoreCountTable>? updateColumns,
    _is.WhereExpressionBuilder<ScoreCountTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<ScoreCount>(
      rows,
      conflictColumns: conflictColumns(ScoreCount.t),
      updateColumns: updateColumns?.call(ScoreCount.t),
      updateWhere: updateWhere?.call(ScoreCount.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [ScoreCount] and returns the resulting row.
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
  /// The returned [ScoreCount] will have its `id` field set.
  Future<ScoreCount?> upsertRow(
    _is.DatabaseSession session,
    ScoreCount row, {
    required _is.ColumnSelections<ScoreCountTable> conflictColumns,
    _is.ColumnSelections<ScoreCountTable>? updateColumns,
    _is.WhereExpressionBuilder<ScoreCountTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<ScoreCount>(
      row,
      conflictColumns: conflictColumns(ScoreCount.t),
      updateColumns: updateColumns?.call(ScoreCount.t),
      updateWhere: updateWhere?.call(ScoreCount.t),
      transaction: transaction,
    );
  }

  /// Updates all [ScoreCount]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<ScoreCount>> update(
    _is.DatabaseSession session,
    List<ScoreCount> rows, {
    _is.ColumnSelections<ScoreCountTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<ScoreCount>(
      rows,
      columns: columns?.call(ScoreCount.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [ScoreCount]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<ScoreCount> updateRow(
    _is.DatabaseSession session,
    ScoreCount row, {
    _is.ColumnSelections<ScoreCountTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<ScoreCount>(
      row,
      columns: columns?.call(ScoreCount.t),
      transaction: transaction,
    );
  }

  /// Updates a single [ScoreCount] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<ScoreCount?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<ScoreCountUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<ScoreCount>(
      id,
      columnValues: columnValues(ScoreCount.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [ScoreCount]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<ScoreCount>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<ScoreCountUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<ScoreCountTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<ScoreCountTable>? orderBy,
    _is.OrderByListBuilder<ScoreCountTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<ScoreCount>(
      columnValues: columnValues(ScoreCount.t.updateTable),
      where: where(ScoreCount.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(ScoreCount.t),
      orderByList: orderByList?.call(ScoreCount.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [ScoreCount]s in the list and returns the deleted rows.
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
  Future<List<ScoreCount>> delete(
    _is.DatabaseSession session,
    List<ScoreCount> rows, {
    _is.OrderByBuilder<ScoreCountTable>? orderBy,
    _is.OrderByListBuilder<ScoreCountTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<ScoreCount>(
      rows,
      orderBy: orderBy?.call(ScoreCount.t),
      orderByList: orderByList?.call(ScoreCount.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [ScoreCount].
  Future<ScoreCount> deleteRow(
    _is.DatabaseSession session,
    ScoreCount row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<ScoreCount>(
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
  Future<List<ScoreCount>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<ScoreCountTable> where,
    _is.OrderByBuilder<ScoreCountTable>? orderBy,
    _is.OrderByListBuilder<ScoreCountTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<ScoreCount>(
      where: where(ScoreCount.t),
      orderBy: orderBy?.call(ScoreCount.t),
      orderByList: orderByList?.call(ScoreCount.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<ScoreCountTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<ScoreCount>(
      where: where?.call(ScoreCount.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [ScoreCount] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<ScoreCountTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<ScoreCount>(
      where: where(ScoreCount.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
