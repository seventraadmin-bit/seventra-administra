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
      final config = await _leerConfig(entityType);
      final contador = await _incrementarContador(entityType, config);
      final numero = contador.toString().padLeft(config.digitos, '0');
      return '${config.prefijo}-$numero';
    });
  }

  /// Devuelve el siguiente **número entero crudo** para [entityType] —
  /// mismo contador atómico/transaccional/nunca-reutilizado que
  /// [siguienteCodigo], pero sin anteponer `prefijo` ni rellenar con
  /// ceros (Etapa 6A: `Empleado.numeroEmpleado` debe verse como `1`,
  /// `2`, `3`..., nunca `EMP-000001`). No es un `MAX(columna) + 1`: usa
  /// la misma fila persistente de `CodigoSecuencia` que ya garantiza
  /// que un número usado jamás vuelve a asignarse, incluso si algún día
  /// una fila de negocio pudiera eliminarse.
  Future<int> siguienteNumero(String entityType) {
    return _db.transaction(() async {
      final config = await _leerConfig(entityType);
      return _incrementarContador(entityType, config);
    });
  }

  Future<CodigoSecuenciaData> _leerConfig(String entityType) async {
    final config = await (_db.select(_db.codigoSecuencia)
          ..where((t) => t.entityType.equals(entityType)))
        .getSingleOrNull();
    if (config == null) {
      throw StateError('Tipo de entidad sin configuración de código: $entityType');
    }
    return config;
  }

  Future<int> _incrementarContador(String entityType, CodigoSecuenciaData config) async {
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

    await (_db.update(_db.codigoSecuencia)..where((t) => t.entityType.equals(entityType))).write(
      CodigoSecuenciaCompanion(
        contadorActual: Value(contador),
        anioActual: config.reseteaAnualmente ? Value(anioActual) : const Value.absent(),
      ),
    );

    return contador;
  }
}
