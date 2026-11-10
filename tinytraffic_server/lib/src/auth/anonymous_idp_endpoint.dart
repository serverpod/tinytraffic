import 'package:serverpod_auth_idp_server/providers/anonymous.dart';

/// Players get an anonymous account per device the first time they open the
/// game, so they can play and post scores without signing up.
class AnonymousIdpEndpoint extends AnonymousIdpBaseEndpoint {}
