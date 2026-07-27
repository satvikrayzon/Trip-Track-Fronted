import '../database/hive_database.dart';

/// JWT pair for `Authorization: Bearer …`.
abstract class TokenStore {
  String? get accessToken;

  String? get refreshToken;

  Future<void> setTokens({
    required String? accessToken,
    required String? refreshToken,
  });

  Future<void> clear();
}

class InMemoryTokenStore implements TokenStore {
  String? _access;
  String? _refresh;

  @override
  String? get accessToken => _access;

  @override
  String? get refreshToken => _refresh;

  @override
  Future<void> setTokens({
    required String? accessToken,
    required String? refreshToken,
  }) async {
    _access = accessToken;
    _refresh = refreshToken;
  }

  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
  }
}

/// Persists tokens in Hive (survives app restarts).
class HiveTokenStore implements TokenStore {
  HiveTokenStore() {
    final (a, r) = HiveDatabase.instance.getSessionTokensSync();
    _access = a;
    _refresh = r;
  }

  String? _access;
  String? _refresh;

  @override
  String? get accessToken => _access;

  @override
  String? get refreshToken => _refresh;

  @override
  Future<void> setTokens({
    required String? accessToken,
    required String? refreshToken,
  }) async {
    _access = accessToken;
    _refresh = refreshToken;
    await HiveDatabase.instance.saveSessionTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
    await HiveDatabase.instance.clearSessionTokens();
  }

  /// Re-read tokens from Hive (e.g. after app cold start).
  void reloadFromDisk() {
    final (a, r) = HiveDatabase.instance.getSessionTokensSync();
    _access = a;
    _refresh = r;
  }
}
