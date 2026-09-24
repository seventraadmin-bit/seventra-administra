import '../core/database/app_database.dart';
import '../core/logging/app_logger.dart';
import '../features/respaldo/domain/salud_base_datos.dart';
import '../features/respaldo/domain/usecases/aplicar_restauracion_pendiente_usecase.dart';

/// Por qué una restauración recién instalada **no** se pudo aceptar.
enum MotivoRestauracionNoConfirmada {
  /// Ni siquiera abrió, o sus migraciones lanzaron. Es el caso de un
  /// respaldo viejo que ya no puede llegar al esquema de hoy.
  noAbreOMigracionFallida,

  /// Abrió, pero terminó en un esquema distinto del que esta build
  /// espera. Migrar "a medias" sin que nadie se queje es peor que
  /// fallar.
  versionInesperada,

  /// `PRAGMA integrity_check` no devolvió `ok`.
  integridad,

  /// `PRAGMA foreign_key_check` devolvió filas.
  referencias,

  /// Los adjuntos instalados no son los que se validaron.
  adjuntos,
}

/// Resultado de abrir la base después de aplicar una restauración.
class AperturaBaseRestaurada {
  const AperturaBaseRestaurada({required this.database, required this.motivo, required this.estadoAnteriorRepuesto});

  /// La conexión utilizable: la restaurada si se confirmó, o la repuesta
  /// si hubo que volver atrás.
  final AppDatabase database;

  /// `null` cuando la restauración se confirmó.
  final MotivoRestauracionNoConfirmada? motivo;

  /// Sólo significa algo cuando [motivo] no es `null`: si el estado
  /// anterior pudo reponerse. `false` es la situación grave —hay que
  /// decírselo a alguien, no seguir como si nada.
  final bool? estadoAnteriorRepuesto;

  bool get confirmada => motivo == null;
}

/// Interna, para cortar el flujo en cuanto una comprobación falla.
class _NoConfirmable implements Exception {
  _NoConfirmable(this.motivo, [this.detalle]);
  final MotivoRestauracionNoConfirmada motivo;
  final Object? detalle;
}

/// Abre la base recién restaurada y decide si la restauración se acepta.
///
/// **Abrir no es aceptar.** Antes de esta pasada bastaba con que Drift
/// lograra abrir el archivo para borrar `restore_old` —el único
/// ejemplar del estado anterior— y esa vara es demasiado baja: un
/// respaldo de un esquema viejo puede abrir, migrar a medias y dejar la
/// aplicación operando sobre datos que ya nadie puede reponer.
///
/// Ahora se le pregunta a la base **ya instalada y ya migrada**:
///  1. ¿abrió y completó sus migraciones?
///  2. ¿su `user_version` es exactamente la de esta build?
///  3. ¿`PRAGMA integrity_check` dice `ok`?
///  4. ¿`PRAGMA foreign_key_check` viene vacío?
///  5. ¿los adjuntos instalados son los que se validaron?
///
/// Sólo con las cinco respuestas afirmativas se llama a `confirmar()` y
/// se suelta el estado anterior. Con cualquiera negativa se revierte.
///
/// Las preguntas 3 y 4 son literalmente las mismas que el validador del
/// paquete hace sobre el `.zip` —comparten `revisarSaludBaseDatos`—,
/// porque validar el paquete **no sustituye** a esta comprobación: una
/// base puede estar impecable dentro del respaldo y romperse durante la
/// migración hacia el esquema actual.
Future<AperturaBaseRestaurada> abrirConfirmandoRestauracion({
  required String databaseFile,
  required AplicarRestauracionPendienteUseCase restaurador,
  required AppLogger logger,
}) async {
  AppDatabase? database;
  try {
    database = AppDatabase(openAppDatabaseConnection(databaseFile));

    // Drift ejecuta las migraciones de forma perezosa: sin una consulta
    // real no ocurren, y confirmar aquí sería confirmar que se pudo
    // abrir un archivo. Esta consulta las fuerza AHORA, mientras la
    // vuelta atrás sigue disponible.
    try {
      await database.customSelect('SELECT 1').get();
    } catch (e) {
      throw _NoConfirmable(MotivoRestauracionNoConfirmada.noAbreOMigracionFallida, e);
    }

    final salud = await revisarSaludBaseDatos((sql) async {
      final filas = await database!.customSelect(sql).get();
      return filas.map((f) => f.data.values.toList()).toList();
    });

    if (salud.userVersion != database.schemaVersion) {
      throw _NoConfirmable(
        MotivoRestauracionNoConfirmada.versionInesperada,
        'quedó en ${salud.userVersion}, se esperaba ${database.schemaVersion}',
      );
    }
    if (!salud.integridadOk) throw _NoConfirmable(MotivoRestauracionNoConfirmada.integridad);
    if (!salud.referenciasOk) throw _NoConfirmable(MotivoRestauracionNoConfirmada.referencias);

    final discrepancia = await restaurador.revisarAdjuntosInstalados();
    if (discrepancia != null) {
      throw _NoConfirmable(MotivoRestauracionNoConfirmada.adjuntos, discrepancia);
    }

    await restaurador.confirmar();
    logger.info('Restauración confirmada: base migrada a ${salud.userVersion}, íntegra y con sus adjuntos.');
    return AperturaBaseRestaurada(database: database, motivo: null, estadoAnteriorRepuesto: null);
  } catch (e, stack) {
    final motivo = e is _NoConfirmable ? e.motivo : MotivoRestauracionNoConfirmada.noAbreOMigracionFallida;
    final detalle = e is _NoConfirmable ? e.detalle : e;
    logger.error('Restauración NO confirmada (${motivo.name}). Se repone el estado anterior.', detalle, stack);

    // La conexión mantiene el archivo abierto: en Windows, mover algo
    // encima fallaría en silencio-por-excepción. Se cierra antes de
    // tocar un solo archivo.
    await database?.close();

    final repuesto = await restaurador.revertir();
    if (!repuesto) {
      // Ya no hay a qué volver, o reponerlo falló. No se oculta ni se
      // borra nada: queda constancia de dónde mirar.
      logger.error(
        'No fue posible reponer el estado anterior. Los archivos siguen en disco sin borrarse; '
        'revisa la carpeta de datos antes de continuar.',
      );
    }
    return AperturaBaseRestaurada(
      database: AppDatabase(openAppDatabaseConnection(databaseFile)),
      motivo: motivo,
      estadoAnteriorRepuesto: repuesto,
    );
  }
}
