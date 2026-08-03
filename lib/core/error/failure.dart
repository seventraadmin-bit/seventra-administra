/// Jerarquía base de errores esperados del dominio (no crashes inesperados).
///
/// Se usa como el lado "error" de [Result]. Los casos concretos se agregan
/// conforme cada módulo los necesite — esta etapa solo define la base común.
sealed class Failure {
  const Failure(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message);
}

class PermissionFailure extends Failure {
  const PermissionFailure(super.message);
}

class DatabaseFailure extends Failure {
  const DatabaseFailure(super.message);
}

class UnknownFailure extends Failure {
  const UnknownFailure(super.message);
}
