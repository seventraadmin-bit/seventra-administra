import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'env.dart';

/// Resuelve las rutas de almacenamiento de RISEG ONE en el equipo local.
///
/// Cada entorno ([Env]) usa una carpeta de datos separada para que el
/// desarrollo nunca toque la base de datos ni los adjuntos de producción.
class AppPaths {
  AppPaths._(this._root, this.env);

  final String _root;
  final Env env;

  static Future<AppPaths> resolve(Env env) async {
    final supportDir = await getApplicationSupportDirectory();
    final folderName = env.isDev ? 'RISEGONE-dev' : 'RISEGONE';
    final root = p.join(supportDir.path, folderName);
    return AppPaths._(root, env);
  }

  /// Carpeta raíz de datos de la aplicación para este entorno.
  String get rootDir => _root;

  /// Ruta del archivo de base de datos SQLite (Drift).
  String get databaseFile => p.join(_root, 'riseg_one.sqlite');

  /// Raíz donde vivirán los adjuntos (fotos, documentos) — sin uso todavía.
  String get attachmentsDir => p.join(_root, 'attachments');

  /// Raíz donde vivirán los respaldos de la base de datos — sin uso todavía.
  String get backupsDir => p.join(_root, 'backups');
}
