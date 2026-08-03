import 'failure.dart';

/// Resultado de una operación que puede fallar de forma esperada.
///
/// Se usa en la capa de dominio/datos para no propagar excepciones por
/// errores previsibles (validación, permisos, registro no encontrado).
/// Los errores realmente inesperados siguen siendo excepciones normales,
/// capturadas por [errorBoundary].
sealed class Result<T> {
  const Result();

  const factory Result.ok(T value) = Ok<T>;

  const factory Result.failure(Failure failure) = Err<T>;

  R when<R>({
    required R Function(T value) ok,
    required R Function(Failure failure) failure,
  }) {
    final self = this;
    return switch (self) {
      Ok<T>() => ok(self.value),
      Err<T>() => failure(self.failure),
    };
  }

  bool get isOk => this is Ok<T>;

  bool get isFailure => this is Err<T>;
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);

  final Failure failure;
}
