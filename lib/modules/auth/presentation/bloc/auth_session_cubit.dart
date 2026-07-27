import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/network/token_store.dart';

part 'auth_session_state.dart';

/// Holds API session (JWT). Synced with [AppAuthController].
class AuthSessionCubit extends Cubit<AuthSessionState> {
  AuthSessionCubit(this._tokens) : super(const AuthSessionUnknown());

  final TokenStore _tokens;

  void hydrate() {
    final t = _tokens.accessToken;
    if (t != null && t.isNotEmpty) {
      emit(const AuthSessionAuthenticated());
    } else {
      emit(const AuthSessionUnauthenticated());
    }
  }

  Future<void> applyTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    await _tokens.setTokens(
      accessToken: accessToken,
      refreshToken: refreshToken ?? _tokens.refreshToken,
    );
    emit(const AuthSessionAuthenticated());
  }

  Future<void> signOut() async {
    await _tokens.clear();
    emit(const AuthSessionUnauthenticated());
  }
}
