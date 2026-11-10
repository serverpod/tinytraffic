import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:tinytraffic_client/tinytraffic_client.dart';
import 'package:serverpod_auth_idp_flutter/serverpod_auth_idp_flutter.dart';
import 'package:flutter_watchos/flutter_watchos.dart';
import 'package:serverpod_flutter/serverpod_flutter.dart';

import 'platform/file_key_value_storage.dart';

/// The production server, on Serverpod Cloud.
const productionServerUrl = 'https://tinytraffic.api.serverpod.space/';

/// Which server to talk to:
///
/// - `--dart-define=SERVER_URL=...` wins when given (e.g. a phone testing
///   against your computer's IP, or a release build against staging).
/// - Release builds of the native apps (App Store: iOS, macOS, watchOS) use
///   [productionServerUrl]. They can't use assets/config.json, which is
///   bundled into the app and points at a local development server.
/// - Everything else reads assets/config.json: on the web the server answers
///   that request itself with its own address (see AppConfigRoute), so a web
///   build always talks to the server that served it; in development it is
///   the local server.
final Future<String> serverUrl = () async {
  const fromDefine = String.fromEnvironment('SERVER_URL');
  if (fromDefine.isNotEmpty) return fromDefine;
  if (kReleaseMode && !kIsWeb) return productionServerUrl;
  return getServerUrl();
}();

/// Sets up a global client object that can be used to talk to the server from
/// anywhere in our app. The client is generated from your server code
/// and is set up to connect to a Serverpod running on a local server on
/// the default port. You will need to modify this to connect to staging or
/// production servers.
/// In a larger app, you may want to use the dependency injection of your choice
/// instead of using a global client object. This is just a simple example.
late final Client client;

Future<void> initializeClient() async {
  client = Client(await serverUrl);
  if (FlutterWatchosPlatform.isWatch) {
    // The Apple Watch has no implementation of the plugins the defaults use
    // (connectivity_plus, flutter_secure_storage), so keep the login in a
    // file and do without connectivity monitoring.
    client.authSessionManager = FlutterAuthSessionManager(
      storage: KeyValueClientAuthSuccessStorage(
        keyValueStorage: FileKeyValueStorage(),
      ),
    );
  } else {
    client
      ..connectivityMonitor = FlutterConnectivityMonitor()
      ..authSessionManager = FlutterAuthSessionManager();
  }
  unawaited(client.auth.initialize());
}
