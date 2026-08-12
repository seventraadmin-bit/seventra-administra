import 'dart:io';

import 'package:path/path.dart' as p;

/// Aplica una restauración dejada en espera por
/// `PrepararRestauracionUseCase` — se ejecuta desde `bootstrap()`,
/// **antes** de abrir la conexión Drift, para nunca intentar sustituir
/// un archivo que la propia aplicación ya tiene abierto.
///
/// Sin efecto (retorna de inmediato) si no hay ninguna restauración
/// pendiente — es seguro llamarla en cada arranque.
///
/// Recibe rutas planas, no `AppPaths` completo — mismo criterio que
/// `CrearRespaldoUseCase`: permite probarla con carpetas temporales,
/// sin depender de `path_provider`.
class AplicarRestauracionPendienteUseCase {
  AplicarRestauracionPendienteUseCase({
    required String databaseFile,
    required String attachmentsDir,
    required String restorePendingDir,
    required String restorePendingMarkerFile,
  })  : _databaseFile = databaseFile,
        _attachmentsDir = attachmentsDir,
        _restorePendingDir = restorePendingDir,
        _restorePendingMarkerFile = restorePendingMarkerFile;

  final String _databaseFile;
  final String _attachmentsDir;
  final String _restorePendingDir;
  final String _restorePendingMarkerFile;

  Future<bool> ejecutar() async {
    final marcador = File(_restorePendingMarkerFile);
    if (!marcador.existsSync()) return false;

    // `restorePendingDir` y `databaseFile` viven bajo la misma raíz
    // (`AppPaths.rootDir`), así que `rename` es seguro aquí — a
    // diferencia de `PrepararRestauracionUseCase`, que mueve desde una
    // carpeta temporal del sistema que podría estar en otra unidad.
    final staging = Directory(_restorePendingDir);
    final sqliteStaged = File(p.join(staging.path, 'riseg_one.sqlite'));
    if (sqliteStaged.existsSync()) {
      // `rename` reemplaza el destino si ya existe (documentado en
      // `dart:io`), así que no hace falta borrar `databaseFile` antes.
      await sqliteStaged.rename(_databaseFile);
    }

    final attachmentsStaged = Directory(p.join(staging.path, 'attachments'));
    final attachmentsDestino = Directory(_attachmentsDir);
    if (attachmentsDestino.existsSync()) {
      await attachmentsDestino.delete(recursive: true);
    }
    if (attachmentsStaged.existsSync()) {
      await attachmentsStaged.rename(_attachmentsDir);
    }

    if (staging.existsSync()) {
      await staging.delete(recursive: true);
    }
    await marcador.delete();
    return true;
  }
}
