/// Entorno de ejecución de RISEG ONE.
///
/// Se resuelve en tiempo de compilación mediante:
/// `--dart-define=APP_ENV=dev` o `--dart-define=APP_ENV=prod`.
/// Sin ese flag, se asume `prod` por seguridad (ver [PermissionService]:
/// el entorno por defecto nunca debe habilitar accesos de desarrollo).
enum Env {
  dev,
  prod;

  static const _raw = String.fromEnvironment('APP_ENV', defaultValue: 'prod');

  static Env resolve() {
    switch (_raw) {
      case 'dev':
        return Env.dev;
      case 'prod':
      default:
        return Env.prod;
    }
  }

  bool get isDev => this == Env.dev;

  bool get isProd => this == Env.prod;
}
