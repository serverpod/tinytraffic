import 'package:serverpod_auth_idp_flutter/serverpod_auth_idp_flutter.dart';

/// Not available without `dart:io`; only the watch uses file storage.
class FileKeyValueStorage implements KeyValueStorage {
  @override
  Future<String?> get(String key) async => null;

  @override
  Future<void> set(String key, String? value) async {}
}
