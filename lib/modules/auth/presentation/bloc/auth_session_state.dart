part of 'auth_session_cubit.dart';

sealed class AuthSessionState extends Equatable {
  const AuthSessionState();

  @override
  List<Object?> get props => [];
}

class AuthSessionUnknown extends AuthSessionState {
  const AuthSessionUnknown();
}

class AuthSessionUnauthenticated extends AuthSessionState {
  const AuthSessionUnauthenticated();
}

class AuthSessionAuthenticated extends AuthSessionState {
  const AuthSessionAuthenticated();
}
