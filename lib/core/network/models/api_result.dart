import '../failures/network_failure.dart';

/// Typed result for REST calls — use in repositories, not in widgets directly.
sealed class ApiResult<T> {
  const ApiResult();

  bool get isSuccess => this is ApiSuccess<T>;
  bool get isFailure => this is ApiFailure<T>;

  T? get dataOrNull => switch (this) {
        ApiSuccess<T>(:final data) => data,
        ApiFailure<T>() => null,
      };

  NetworkFailure? get failureOrNull => switch (this) {
        ApiSuccess<T>() => null,
        ApiFailure<T>(:final failure) => failure,
      };

  R fold<R>({
    required R Function(T data) onSuccess,
    required R Function(NetworkFailure failure) onFailure,
  }) {
    return switch (this) {
      ApiSuccess<T>(:final data) => onSuccess(data),
      ApiFailure<T>(:final failure) => onFailure(failure),
    };
  }
}

final class ApiSuccess<T> extends ApiResult<T> {
  const ApiSuccess(this.data);
  final T data;
}

final class ApiFailure<T> extends ApiResult<T> {
  const ApiFailure(this.failure);
  final NetworkFailure failure;
}
