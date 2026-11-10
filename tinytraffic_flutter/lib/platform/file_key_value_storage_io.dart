import 'dart:io';

import 'package:serverpod_auth_idp_flutter/serverpod_auth_idp_flutter.dart';

/// Keeps each value in its own file in the app's private Application Support
/// directory.
///
/// This is for the Apple Watch, where neither `flutter_secure_storage` nor
/// `path_provider` has an implementation. The directory is found without
/// `path_provider`: like on iOS, the app's temporary directory sits directly
/// inside its sandbox container, next to `Library/`.
class FileKeyValueStorage implements KeyValueStorage {
  final Map<String, String?> _cache = {};
  Directory? _dir;

  Directory get _directory => _dir ??= Directory(
    '${Directory.systemTemp.parent.path}/Library/Application Support/tinytraffic',
  );

  File _file(String key) =>
      File('${_directory.path}/${Uri.encodeComponent(key)}');

  @override
  Future<String?> get(String key) async {
    if (_cache.containsKey(key)) return _cache[key];
    final file = _file(key);
    final value = await file.exists() ? await file.readAsString() : null;
    _cache[key] = value;
    return value;
  }

  @override
  Future<void> set(String key, String? value) async {
    _cache[key] = value;
    final file = _file(key);
    if (value == null) {
      if (await file.exists()) await file.delete();
      return;
    }
    await _directory.create(recursive: true);
    await file.writeAsString(value, flush: true);
  }
}
