/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters
// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: dead_code, unnecessary_type_check

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:serverpod/protocol.dart' as _isp;
import 'package:serverpod/serverpod.dart' as _is;
import 'package:serverpod_auth_core_server/serverpod_auth_core_server.dart'
    as _iacs;
import 'package:serverpod_auth_idp_server/serverpod_auth_idp_server.dart'
    as _iais;
import 'package:tinytraffic_server/src/generated/game/models/leaderboard_entry.dart'
    as _i2gemiei;
import 'game/models/game_run.dart' as _ijdcfv7a;
import 'game/models/leaderboard_entry.dart' as _ifcls3fb;
import 'game/models/player_stats.dart' as _ik0fouzq;
import 'game/models/player_summary.dart' as _i6ok029z;
import 'game/models/run_rejected_exception.dart' as _izx42nav;
import 'game/models/run_result.dart' as _iaj2db4j;
import 'game/models/run_status.dart' as _io3kae3l;
import 'game/models/run_ticket.dart' as _ixvsu67a;
import 'game/models/score_count.dart' as _i4i9lkw0;
export 'game/models/game_run.dart';
export 'game/models/leaderboard_entry.dart';
export 'game/models/player_stats.dart';
export 'game/models/player_summary.dart';
export 'game/models/run_rejected_exception.dart';
export 'game/models/run_result.dart';
export 'game/models/run_status.dart';
export 'game/models/run_ticket.dart';
export 'game/models/score_count.dart';

class Protocol extends _is.DatabaseSerializationManager
    implements _is.DatabaseProtocolDeserializationProvider {
  Protocol._();

  factory Protocol() => _instance;

  static final Protocol _instance = Protocol._().._registerHostProtocols();

  @override
  _is.ProtocolDeserialization get deserializationMetadata =>
      _is.ProtocolDeserialization.cached(
        this,
        types: const [
          _is.getType<_ijdcfv7a.GameRun>,
          _is.getType<_ifcls3fb.LeaderboardEntry>,
          _is.getType<_ik0fouzq.PlayerStats>,
          _is.getType<_i6ok029z.PlayerSummary>,
          _is.getType<_izx42nav.RunRejectedException>,
          _is.getType<_iaj2db4j.RunResult>,
          _is.getType<_io3kae3l.RunStatus>,
          _is.getType<_ixvsu67a.RunTicket>,
          _is.getType<_i4i9lkw0.ScoreCount>,
          _is.getType<_ijdcfv7a.GameRun?>,
          _is.getType<_ifcls3fb.LeaderboardEntry?>,
          _is.getType<_ik0fouzq.PlayerStats?>,
          _is.getType<_i6ok029z.PlayerSummary?>,
          _is.getType<_izx42nav.RunRejectedException?>,
          _is.getType<_iaj2db4j.RunResult?>,
          _is.getType<_io3kae3l.RunStatus?>,
          _is.getType<_ixvsu67a.RunTicket?>,
          _is.getType<_i4i9lkw0.ScoreCount?>,
          _is.getType<List<_i2gemiei.LeaderboardEntry>>,
        ],
        modules: const [
          _iais.Protocol.new,
          _iacs.Protocol.new,
          _isp.Protocol.new,
        ],
      );

  static List<_isp.TableDefinition> get targetTableDefinitions => [
    _isp.TableDefinition(
      name: 'game_run',
      dartName: 'GameRun',
      schema: 'public',
      module: 'tinytraffic',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'authUserId',
          columnType: _isp.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue',
        ),
        _isp.ColumnDefinition(
          name: 'seed',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'simVersion',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'startedAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _isp.ColumnDefinition(
          name: 'finishedAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
        _isp.ColumnDefinition(
          name: 'status',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'protocol:RunStatus',
        ),
        _isp.ColumnDefinition(
          name: 'score',
          columnType: _isp.ColumnType.bigint,
          isNullable: true,
          dartType: 'int?',
        ),
        _isp.ColumnDefinition(
          name: 'ticks',
          columnType: _isp.ColumnType.bigint,
          isNullable: true,
          dartType: 'int?',
        ),
        _isp.ColumnDefinition(
          name: 'rejectReason',
          columnType: _isp.ColumnType.text,
          isNullable: true,
          dartType: 'String?',
        ),
        _isp.ColumnDefinition(
          name: 'unverifiable',
          columnType: _isp.ColumnType.boolean,
          isNullable: false,
          dartType: 'bool',
          columnDefault: 'false',
        ),
        _isp.ColumnDefinition(
          name: 'inputLog',
          columnType: _isp.ColumnType.bytea,
          isNullable: true,
          dartType: 'dart:typed_data:ByteData?',
        ),
      ],
      foreignKeys: [],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'game_run_user_idx',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'authUserId',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'startedAt',
            ),
          ],
          type: 'btree',
          isUnique: false,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'player_stats',
      dartName: 'PlayerStats',
      schema: 'public',
      module: 'tinytraffic',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'authUserId',
          columnType: _isp.ColumnType.uuid,
          isNullable: false,
          dartType: 'UuidValue',
        ),
        _isp.ColumnDefinition(
          name: 'nickname',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'bestScore',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'bestRunId',
          columnType: _isp.ColumnType.bigint,
          isNullable: true,
          dartType: 'int?',
        ),
        _isp.ColumnDefinition(
          name: 'bestAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
        _isp.ColumnDefinition(
          name: 'totalRuns',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'totalCoins',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'shadowBanned',
          columnType: _isp.ColumnType.boolean,
          isNullable: false,
          dartType: 'bool',
          columnDefault: 'false',
        ),
        _isp.ColumnDefinition(
          name: 'banReason',
          columnType: _isp.ColumnType.text,
          isNullable: true,
          dartType: 'String?',
        ),
        _isp.ColumnDefinition(
          name: 'bannedAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
      ],
      foreignKeys: [],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'player_stats_user_idx',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'authUserId',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
        _isp.IndexDefinition(
          indexName: 'player_stats_best_idx',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'bestScore',
            ),
          ],
          type: 'btree',
          isUnique: false,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'score_count',
      dartName: 'ScoreCount',
      schema: 'public',
      module: 'tinytraffic',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'score',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'players',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
      ],
      foreignKeys: [],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'score_count_score_idx',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'score',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    ..._iais.Protocol.targetTableDefinitions,
    ..._iacs.Protocol.targetTableDefinitions,
    ..._isp.Protocol.targetTableDefinitions,
  ];

  static String? getClassNameFromObjectJson(dynamic data) {
    if (data is! Map) return null;
    final className = data['__className__'] as String?;
    return className;
  }

  @override
  T deserialize<T>(
    dynamic data, [
    Type? t,
  ]) {
    t ??= T;

    final dataClassName = getClassNameFromObjectJson(data);
    if (dataClassName != null && dataClassName != getClassNameForType(t)) {
      try {
        return deserializeByClassName({
          'className': dataClassName,
          'data': data,
        });
      } on _is.DeserializationClassNameNotFoundException catch (_) {
        // If the className is not recognized (e.g., older client receiving
        // data with a new subtype), fall back to deserializing without the
        // className, using the expected type T.
      }
    }

    if (t == _ijdcfv7a.GameRun) {
      return _ijdcfv7a.GameRun.fromJson(data) as T;
    }
    if (t == _ifcls3fb.LeaderboardEntry) {
      return _ifcls3fb.LeaderboardEntry.fromJson(data) as T;
    }
    if (t == _ik0fouzq.PlayerStats) {
      return _ik0fouzq.PlayerStats.fromJson(data) as T;
    }
    if (t == _i6ok029z.PlayerSummary) {
      return _i6ok029z.PlayerSummary.fromJson(data) as T;
    }
    if (t == _izx42nav.RunRejectedException) {
      return _izx42nav.RunRejectedException.fromJson(data) as T;
    }
    if (t == _iaj2db4j.RunResult) {
      return _iaj2db4j.RunResult.fromJson(data) as T;
    }
    if (t == _io3kae3l.RunStatus) {
      return _io3kae3l.RunStatus.fromJson(data) as T;
    }
    if (t == _ixvsu67a.RunTicket) {
      return _ixvsu67a.RunTicket.fromJson(data) as T;
    }
    if (t == _i4i9lkw0.ScoreCount) {
      return _i4i9lkw0.ScoreCount.fromJson(data) as T;
    }
    if (t == _is.getType<_ijdcfv7a.GameRun?>()) {
      return (data != null ? _ijdcfv7a.GameRun.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_ifcls3fb.LeaderboardEntry?>()) {
      return (data != null ? _ifcls3fb.LeaderboardEntry.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_ik0fouzq.PlayerStats?>()) {
      return (data != null ? _ik0fouzq.PlayerStats.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_i6ok029z.PlayerSummary?>()) {
      return (data != null ? _i6ok029z.PlayerSummary.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_izx42nav.RunRejectedException?>()) {
      return (data != null
              ? _izx42nav.RunRejectedException.fromJson(data)
              : null)
          as T;
    }
    if (t == _is.getType<_iaj2db4j.RunResult?>()) {
      return (data != null ? _iaj2db4j.RunResult.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_io3kae3l.RunStatus?>()) {
      return (data != null ? _io3kae3l.RunStatus.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_ixvsu67a.RunTicket?>()) {
      return (data != null ? _ixvsu67a.RunTicket.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_i4i9lkw0.ScoreCount?>()) {
      return (data != null ? _i4i9lkw0.ScoreCount.fromJson(data) : null) as T;
    }
    if (t == List<_i2gemiei.LeaderboardEntry>) {
      return (data as List)
              .map((e) => deserialize<_i2gemiei.LeaderboardEntry>(e))
              .toList()
          as T;
    }
    final modules = dataClassName == null
        ? deserializationMetadata.modulesForType(t)
        : deserializationMetadata.modules;
    for (final module in modules) {
      try {
        return module.deserialize<T>(data, t);
      } on _is.DeserializationTypeNotFoundException catch (_) {}
    }

    return super.deserialize<T>(data, t);
  }

  static String? getClassNameForType(Type type) {
    return switch (type) {
      _ijdcfv7a.GameRun => 'GameRun',
      _ifcls3fb.LeaderboardEntry => 'LeaderboardEntry',
      _ik0fouzq.PlayerStats => 'PlayerStats',
      _i6ok029z.PlayerSummary => 'PlayerSummary',
      _izx42nav.RunRejectedException => 'RunRejectedException',
      _iaj2db4j.RunResult => 'RunResult',
      _io3kae3l.RunStatus => 'RunStatus',
      _ixvsu67a.RunTicket => 'RunTicket',
      _i4i9lkw0.ScoreCount => 'ScoreCount',
      _ => null,
    };
  }

  @override
  String? getClassNameForObject(Object? data) {
    String? className = super.getClassNameForObject(data);
    if (className != null) return className;

    if (data is Map<String, dynamic> && data['__className__'] is String) {
      return (data['__className__'] as String).replaceFirst('tinytraffic.', '');
    }

    switch (data) {
      case _ijdcfv7a.GameRun():
        return 'GameRun';
      case _ifcls3fb.LeaderboardEntry():
        return 'LeaderboardEntry';
      case _ik0fouzq.PlayerStats():
        return 'PlayerStats';
      case _i6ok029z.PlayerSummary():
        return 'PlayerSummary';
      case _izx42nav.RunRejectedException():
        return 'RunRejectedException';
      case _iaj2db4j.RunResult():
        return 'RunResult';
      case _io3kae3l.RunStatus():
        return 'RunStatus';
      case _ixvsu67a.RunTicket():
        return 'RunTicket';
      case _i4i9lkw0.ScoreCount():
        return 'ScoreCount';
    }
    className = _iais.Protocol().getClassNameForObject(data);
    if (className != null) {
      return className.contains('.')
          ? className
          : 'serverpod_auth_idp.$className';
    }
    className = _iacs.Protocol().getClassNameForObject(data);
    if (className != null) {
      return className.contains('.')
          ? className
          : 'serverpod_auth_core.$className';
    }
    className = _isp.Protocol().getClassNameForObject(data);
    if (className != null) {
      return className.contains('.') ? className : 'serverpod.$className';
    }
    return null;
  }

  @override
  dynamic deserializeByClassName(Map<String, dynamic> data) {
    var dataClassName = data['className'];
    if (dataClassName is! String) {
      return super.deserializeByClassName(data);
    }
    if (dataClassName == 'GameRun') {
      return deserialize<_ijdcfv7a.GameRun>(data['data']);
    }
    if (dataClassName == 'LeaderboardEntry') {
      return deserialize<_ifcls3fb.LeaderboardEntry>(data['data']);
    }
    if (dataClassName == 'PlayerStats') {
      return deserialize<_ik0fouzq.PlayerStats>(data['data']);
    }
    if (dataClassName == 'PlayerSummary') {
      return deserialize<_i6ok029z.PlayerSummary>(data['data']);
    }
    if (dataClassName == 'RunRejectedException') {
      return deserialize<_izx42nav.RunRejectedException>(data['data']);
    }
    if (dataClassName == 'RunResult') {
      return deserialize<_iaj2db4j.RunResult>(data['data']);
    }
    if (dataClassName == 'RunStatus') {
      return deserialize<_io3kae3l.RunStatus>(data['data']);
    }
    if (dataClassName == 'RunTicket') {
      return deserialize<_ixvsu67a.RunTicket>(data['data']);
    }
    if (dataClassName == 'ScoreCount') {
      return deserialize<_i4i9lkw0.ScoreCount>(data['data']);
    }
    if (dataClassName.startsWith('serverpod_auth_idp.')) {
      data['className'] = dataClassName.substring(19);
      return _iais.Protocol().deserializeByClassName(data);
    }
    if (dataClassName.startsWith('serverpod_auth_core.')) {
      data['className'] = dataClassName.substring(20);
      return _iacs.Protocol().deserializeByClassName(data);
    }
    if (dataClassName.startsWith('serverpod.')) {
      data['className'] = dataClassName.substring(10);
      return _isp.Protocol().deserializeByClassName(data);
    }
    return super.deserializeByClassName(data);
  }

  void _registerHostProtocols() {
    _iais.Protocol().registerHostProtocol('tinytraffic', this);
    _iacs.Protocol().registerHostProtocol('tinytraffic', this);
  }

  @override
  _is.Table? getTableForType(Type t) {
    {
      var table = _iais.Protocol().getTableForType(t);
      if (table != null) {
        return table;
      }
    }
    {
      var table = _iacs.Protocol().getTableForType(t);
      if (table != null) {
        return table;
      }
    }
    {
      var table = _isp.Protocol().getTableForType(t);
      if (table != null) {
        return table;
      }
    }
    switch (t) {
      case _ijdcfv7a.GameRun:
        return _ijdcfv7a.GameRun.t;
      case _ik0fouzq.PlayerStats:
        return _ik0fouzq.PlayerStats.t;
      case _i4i9lkw0.ScoreCount:
        return _i4i9lkw0.ScoreCount.t;
    }
    return null;
  }

  @override
  List<_isp.TableDefinition> getTargetTableDefinitions() =>
      targetTableDefinitions;

  @override
  String getModuleName() => 'tinytraffic';

  /// Maps any `Record`s known to this [Protocol] to their JSON representation
  ///
  /// Throws in case the record type is not known.
  ///
  /// This method will return `null` (only) for `null` inputs.
  Map<String, dynamic>? mapRecordToJson(Record? record) {
    if (record == null) {
      return null;
    }
    try {
      return _iais.Protocol().mapRecordToJson(record);
    } catch (_) {}
    try {
      return _iacs.Protocol().mapRecordToJson(record);
    } catch (_) {}
    throw Exception('Unsupported record type ${record.runtimeType}');
  }
}
