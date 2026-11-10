// Key-value storage in plain files, for platforms without a storage plugin.
export 'file_key_value_storage_stub.dart'
    if (dart.library.io) 'file_key_value_storage_io.dart';
