import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/portable/configuracion_recuperacion.dart';

/// Persistencia de la configuración de recuperación portable
/// (Etapa 4D, schemaVersion 93).
///
/// Sólo existe **una** configuración activa: el conjunto de respaldos de
/// esta instalación. Cambiar la frase o regenerar la clave de
/// recuperación sustituye la fila, no añade otra — dos configuraciones
/// vivas significarían dos claves maestras y respaldos que unos abren y
/// otros no.
///
/// Nada de lo que se guarda aquí es secreto; ver el comentario de la
/// tabla. Lo que **nunca** entra: la frase, la clave de recuperación, sus
/// KEK, la clave maestra en claro, ninguna DEK y la clave AES de la
/// aplicación.
class ConfiguracionRecuperacionRepositoryImpl {
  ConfiguracionRecuperacionRepositoryImpl(this._db);

  final AppDatabase _db;

  /// La configuración vigente, o `null` si la recuperación portable
  /// todavía no se ha configurado.
  Future<ConfiguracionRecuperacion?> obtener() async {
    final fila = await _db.select(_db.configuracionRecuperacionPortable).getSingleOrNull();
    if (fila == null) return null;

    return ConfiguracionRecuperacion.desdePersistido(
      backupSetId: fila.backupSetId,
      formatoVersion: fila.formatoVersion,
      envolturaFraseJson: fila.envolturaFrase,
      envolturaClaveRecuperacionJson: fila.envolturaClaveRecuperacion,
      claveRecuperacionGeneradaEn: fila.claveRecuperacionGeneradaEn,
    );
  }

  /// Guarda la configuración, sustituyendo la anterior si la hubiera.
  ///
  /// Se hace en una transacción porque borrar y volver a insertar deja,
  /// entre las dos operaciones, una instalación sin configuración: si algo
  /// se interpusiera ahí, la recuperación portable pasaría a "no
  /// configurada" y los respaldos existentes quedarían sin bloque local
  /// con el que trabajar.
  Future<void> guardar(ConfiguracionRecuperacion configuracion) async {
    await _db.transaction(() async {
      await _db.delete(_db.configuracionRecuperacionPortable).go();
      await _db
          .into(_db.configuracionRecuperacionPortable)
          .insert(
            ConfiguracionRecuperacionPortableCompanion.insert(
              backupSetId: configuracion.backupSetId,
              formatoVersion: Value(configuracion.formatoVersion),
              envolturaFrase: configuracion.envolturaFraseJson(),
              envolturaClaveRecuperacion: configuracion.envolturaClaveRecuperacionJson(),
              claveRecuperacionGeneradaEn: configuracion.claveRecuperacionGeneradaEn,
            ),
          );
    });
  }

  Future<bool> estaConfigurada() async => await obtener() != null;
}
