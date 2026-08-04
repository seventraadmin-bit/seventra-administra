import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Genera códigos visibles únicos y nunca reutilizables.
///
/// Único punto de la aplicación que lee o incrementa `CodigoSecuencia` —
/// ningún módulo debe tocar esa tabla directamente. El incremento ocurre
/// dentro de una transacción; en esta fase (un solo escritor SQLite) eso
/// basta para que dos códigos nunca coincidan. En una futura fase LAN, el
/// contador se movería al servidor — este servicio es el único punto que
/// tendría que cambiar.
class CodigoSecuenciaService {
  CodigoSecuenciaService(this._db);

  final AppDatabase _db;

  /// Devuelve el siguiente código visible para [entityType] (ej.
  /// `'cliente'` -> `'CLI-000001'`). Lanza [StateError] si [entityType] no
  /// tiene configuración registrada en `CodigoSecuencia`.
  Future<String> siguienteCodigo(String entityType) {
    return _db.transaction(() async {
      final config = await (_db.select(_db.codigoSecuencia)
            ..where((t) => t.entityType.equals(entityType)))
          .getSingleOrNull();

      if (config == null) {
        throw StateError('Tipo de entidad sin configuración de código: $entityType');
      }

      final anioActual = DateTime.now().year;
      final int contador;
      if (config.reseteaAnualmente && config.anioActual == anioActual) {
        contador = config.contadorActual + 1;
      } else if (config.reseteaAnualmente) {
        // Cambió el año (o es la primera vez que se genera este tipo):
        // el contador arranca de nuevo en 1.
        contador = 1;
      } else {
        contador = config.contadorActual + 1;
      }

      await (_db.update(_db.codigoSecuencia)..where((t) => t.entityType.equals(entityType)))
          .write(
        CodigoSecuenciaCompanion(
          contadorActual: Value(contador),
          anioActual: config.reseteaAnualmente ? Value(anioActual) : const Value.absent(),
        ),
      );

      final numero = contador.toString().padLeft(config.digitos, '0');
      return '${config.prefijo}-$numero';
    });
  }
}
