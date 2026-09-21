import 'package:drift/drift.dart';

import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/domain/repositories/linea_telefonica_de_unidad.dart';

import '../../domain/coherencia_linea_equipo.dart';
import '../../domain/repositories/asignacion_linea_telefonica_repository.dart';
import '../tables/asignacion_linea_telefonica_table.dart'
    show MotivoTerminoAsignacionLineaTelefonica;
import '../tables/linea_telefonica_table.dart' show TipoEventoLineaTelefonica;
import 'asignacion_linea_telefonica_repository_impl.dart';

/// Implementación de Telefonía del puerto que declara Inventario — ver
/// el doc comment de [LineaTelefonicaDeUnidad] para la decisión de
/// dirección.
///
/// Deliberadamente NO compone ningún repositorio de Inventario: sólo la
/// base y el repositorio de asignaciones de línea. Es lo que garantiza
/// que no exista `Inventario → Telefonía → Inventario`.
///
/// Se ejecuta dentro de la transacción que Inventario ya tiene abierta,
/// así que o se mueven custodia y línea juntas, o no se mueve ninguna.
///
/// **Cada movimiento deja su propio asiento** (§1B de la Rebanada 3):
/// un `LineaTelefonicaEvento` de tipo
/// `asignacionSincronizadaPorInventario` con el actor que ejecutó la
/// operación de Inventario, el antes/después, el aparato y el id de la
/// `Asignacion` que la causó. Sin ese asiento, la bitácora no podría
/// distinguir este cambio de uno hecho a mano en Telefonía — y esa
/// distinción es justo la que evita leerlo como un permiso que el
/// usuario no tiene.
class LineaTelefonicaDeUnidadCoordinador implements LineaTelefonicaDeUnidad {
  LineaTelefonicaDeUnidadCoordinador(this._db, this._asignacionLinea);

  factory LineaTelefonicaDeUnidadCoordinador.desde(AppDatabase db) =>
      LineaTelefonicaDeUnidadCoordinador(db, AsignacionLineaTelefonicaRepositoryImpl(db));

  final AppDatabase _db;
  final AsignacionLineaTelefonicaRepository _asignacionLinea;

  /// La línea que esta unidad trae físicamente AHORA, si alguna.
  /// Lectura directa de la tabla de Telefonía: no pasa por
  /// `LineaTelefonicaEquipoRepository`, que sí compone Inventario para
  /// leer custodia y reintroduciría el ciclo.
  Future<LineaTelefonicaEquipoData?> _equipoVigente(String unidadId) {
    return (_db.select(_db.lineaTelefonicaEquipo)
          ..where((t) => t.unidadId.equals(unidadId) & t.fechaFin.isNull()))
        .getSingleOrNull();
  }

  /// El asiento de la consecuencia sistémica. Escribe directo en
  /// `lineaTelefonicaEvento` por el mismo motivo que la lectura de
  /// arriba: `LineaTelefonicaRepositoryImpl` compone Inventario.
  Future<void> _asentar({
    required LineaTelefonicaEquipoData equipo,
    required DestinoTelefonia? antes,
    required DestinoTelefonia? despues,
    required DateTime fechaHora,
    required String? origenAsignacionInventarioId,
    required String? actorUsuarioId,
  }) async {
    final diff = DiffEvento()
      ..anotar('destinoLinea', antes?.toString(), despues?.toString())
      // El aparato no "cambia" en esta operación, pero §1B pide que el
      // asiento diga CUÁL fue: se anota como dato del estado nuevo, no
      // como diferencia.
      ..anotar('equipoInvolucrado', null, equipo.unidadId)
      ..anotar('origenAsignacionInventario', null, origenAsignacionInventarioId);

    await _db.into(_db.lineaTelefonicaEvento).insert(
          LineaTelefonicaEventoCompanion.insert(
            lineaTelefonicaId: equipo.lineaTelefonicaId,
            fechaHora: fechaHora,
            tipoEvento: TipoEventoLineaTelefonica.asignacionSincronizadaPorInventario.name,
            observacion: const Value(
              'Asignación de línea actualizada automáticamente por un cambio '
              'de custodia del equipo en Inventario.',
            ),
            estadoAnterior: Value(diff.estadoAnteriorJson),
            estadoNuevo: Value(diff.estadoNuevoJson),
            actorUsuarioId: Value(actorUsuarioId),
          ),
        );
  }

  @override
  Future<bool> traeLineaVigente(String unidadId) async => await _equipoVigente(unidadId) != null;

  @override
  Future<void> alinearAlNuevoDestino({
    required String unidadId,
    String? empleadoId,
    String? servicioId,
    required DateTime fecha,
    String? origenAsignacionInventarioId,
    String? actorUsuarioId,
  }) async {
    final equipo = await _equipoVigente(unidadId);
    if (equipo == null) return;

    final destinoNuevo = destinoDe(empleadoId: empleadoId, servicioId: servicioId);
    if (destinoNuevo == null) return;

    final vigente = await _asignacionLinea.obtenerActivaPorLinea(equipo.lineaTelefonicaId);
    final destinoAnterior = destinoDeAsignacionLinea(vigente);
    if (destinoAnterior == destinoNuevo) return;

    const observacion = 'Sigue la custodia del equipo en Inventario.';

    if (vigente == null) {
      await _asignacionLinea.crear(
        lineaTelefonicaId: equipo.lineaTelefonicaId,
        empleadoId: empleadoId,
        servicioId: servicioId,
        fechaInicio: fecha,
        observaciones: observacion,
        actorUsuarioId: actorUsuarioId,
      );
    } else {
      // Cierra el periodo anterior y abre el nuevo — nunca reescribe la
      // fila histórica para que parezca que siempre apuntó ahí (§24).
      await _asignacionLinea.cambiarResponsable(
        asignacionLineaTelefonicaActualId: vigente.id,
        fecha: fecha,
        motivoTermino: MotivoTerminoAsignacionLineaTelefonica.sincronizacionCustodiaInventario.name,
        observacionesTermino: observacion,
        nuevoEmpleadoId: empleadoId,
        nuevoServicioId: servicioId,
        observacionesNueva: observacion,
        actorUsuarioId: actorUsuarioId,
      );
    }

    await _asentar(
      equipo: equipo,
      fechaHora: fecha,
      antes: destinoAnterior,
      despues: destinoNuevo,
      origenAsignacionInventarioId: origenAsignacionInventarioId,
      actorUsuarioId: actorUsuarioId,
    );
  }

  @override
  Future<void> cerrarPorFinDeCustodia({
    required String unidadId,
    required DateTime fecha,
    String? origenAsignacionInventarioId,
    String? actorUsuarioId,
  }) async {
    final equipo = await _equipoVigente(unidadId);
    if (equipo == null) return;

    final vigente = await _asignacionLinea.obtenerActivaPorLinea(equipo.lineaTelefonicaId);
    if (vigente == null) return;

    await _asignacionLinea.cerrar(
      asignacionLineaTelefonicaId: vigente.id,
      fechaTermino: fecha,
      motivoTermino: MotivoTerminoAsignacionLineaTelefonica.custodiaEquipoTerminada.name,
      observacionesTermino: 'El equipo que traía la línea dejó de estar bajo custodia.',
      actorUsuarioId: actorUsuarioId,
    );

    await _asentar(
      equipo: equipo,
      fechaHora: fecha,
      antes: destinoDeAsignacionLinea(vigente),
      despues: null,
      origenAsignacionInventarioId: origenAsignacionInventarioId,
      actorUsuarioId: actorUsuarioId,
    );
  }
}
