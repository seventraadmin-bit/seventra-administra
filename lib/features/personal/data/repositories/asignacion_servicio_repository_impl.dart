import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/atribucion_historica_linea_comercial.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_con_vigencia.dart' show clasificarVigencias;

import '../../domain/repositories/asignacion_servicio_repository.dart';
import '../../domain/usecases/asignacion_sueldo_con_vigencia.dart';
import '../tables/asignacion_servicio_table.dart';
import '../tables/empleado_table.dart';
import 'empleado_evento_writer.dart';
import 'vacante_operativa_repository_impl.dart';

class AsignacionServicioRepositoryImpl implements AsignacionServicioRepository {
  AsignacionServicioRepositoryImpl(this._db);

  final AppDatabase _db;

  /// Compuesto internamente (no inyectado): evita que este cambio
  /// obligue a tocar los ~50 call sites existentes de
  /// `AsignacionServicioRepositoryImpl(db)` solo para agregar un
  /// parámetro — mismo criterio ya usado en el proyecto para
  /// dependencias que solo necesitan `_db` (ej. `CompraRepositoryImpl.
  /// _codigoSecuencia`).
  late final _vacantes = VacanteOperativaRepositoryImpl(_db);

  /// Reconcilia las `VacanteOperativa` de UNA línea comercial contra su
  /// cobertura real en este momento (Etapa 15, rediseño del Dashboard
  /// gerencial) — ver el doc comment completo de `VacanteOperativa` y de
  /// `VacanteOperativaRepository.sincronizarLinea`. Se llama después de
  /// CUALQUIER mutación de `AsignacionServicio` que pueda cambiar cuántas
  /// asignaciones vigentes tiene una línea: crear, cerrar (por cualquier
  /// motivo), o mover de línea. No-op silencioso si [lineaComercialId]
  /// es `null` (asignación sin línea clasificada — nunca participa en
  /// cobertura por línea, ver el doc comment de esa columna).
  Future<void> _reconciliarVacante({
    required String? lineaComercialId,
    required String servicioId,
    required DateTime fecha,
    required String motivoApertura,
    String? asignacionOrigenId,
    String? asignacionCoberturaId,
  }) async {
    if (lineaComercialId == null) return;

    final vigenciasActivas = await (_db.select(_db.servicioLineaComercialVigencia)
          ..where(
            (t) =>
                t.lineaComercialId.equals(lineaComercialId) & t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
          ))
        .get();
    final clasificadas = clasificarVigencias(vigenciasActivas, fecha);
    final requerido = clasificadas.vigente?.cantidadElementos ?? 0;

    final cubierto = await (_db.selectOnly(_db.asignacionServicio)
          ..addColumns([_db.asignacionServicio.id.count()])
          ..where(_db.asignacionServicio.lineaComercialId.equals(lineaComercialId) & _db.asignacionServicio.fechaTermino.isNull()))
        .map((row) => row.read(_db.asignacionServicio.id.count()) ?? 0)
        .getSingle();

    await _vacantes.sincronizarLinea(
      servicioId: servicioId,
      lineaComercialId: lineaComercialId,
      requerido: requerido,
      cubierto: cubierto,
      fecha: fecha,
      motivoApertura: motivoApertura,
      asignacionOrigenId: asignacionOrigenId,
      asignacionCoberturaId: asignacionCoberturaId,
    );
  }

  /// Resuelve qué línea comercial reconciliar al cerrar (retirar/dar de
  /// baja) una `AsignacionServicio` — si ya tiene `lineaComercialId`, esa
  /// misma; si es histórica (`lineaComercialId == null`), reutiliza la
  /// MISMA atribución de solo lectura que usa el Dashboard
  /// (`atribuirAsignacionesHistoricas`, ver `listarLineasEnFecha`): solo
  /// cuando resulta inequívoca (una sola línea vigente, o turno
  /// coincide con exactamente una) se abre la vacante correspondiente al
  /// cerrarse — nunca se adivina, así como nunca se adivinó al contarla
  /// como cobertura.
  Future<String?> _lineaComercialIdParaReconciliar(AsignacionServicioData asignacion, DateTime fecha) async {
    if (asignacion.lineaComercialId != null) return asignacion.lineaComercialId;

    final lineas = await (_db.select(_db.servicioLineaComercial)..where((t) => t.servicioId.equals(asignacion.servicioId))).get();
    final lineasVigentes = <LineaVigenteAtribuible>[];
    for (final linea in lineas) {
      final vigenciasActivas = await (_db.select(_db.servicioLineaComercialVigencia)
            ..where(
              (t) =>
                  t.lineaComercialId.equals(linea.id) & t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
            ))
          .get();
      final (:vigente, :programadas) = clasificarVigencias(vigenciasActivas, fecha);
      if (vigente != null) {
        lineasVigentes.add(LineaVigenteAtribuible(lineaComercialId: linea.id, modalidadTurnoId: vigente.modalidadTurnoId));
      }
    }
    if (lineasVigentes.isEmpty) return null;

    final atribucion = atribuirAsignacionesHistoricas(asignacionesSinLinea: [asignacion], lineasVigentes: lineasVigentes);
    final claves = atribucion.atribuidasPorLinea.keys;
    return claves.length == 1 ? claves.single : null;
  }

  Future<AsignacionServicioData?> _buscarActivaPorEmpleado(String empleadoId) {
    return (_db.select(_db.asignacionServicio)
          ..where((t) => t.empleadoId.equals(empleadoId) & t.fechaTermino.isNull()))
        .getSingleOrNull();
  }

  @override
  Future<AsignacionServicioData?> obtenerActivaPorEmpleado(String empleadoId) => _buscarActivaPorEmpleado(empleadoId);

  @override
  Future<AsignacionServicioData?> obtenerPorId(String asignacionServicioId) {
    return (_db.select(_db.asignacionServicio)..where((t) => t.id.equals(asignacionServicioId))).getSingleOrNull();
  }

  @override
  Future<List<AsignacionServicioData>> listarPorEmpleado(String empleadoId) {
    return (_db.select(_db.asignacionServicio)
          ..where((t) => t.empleadoId.equals(empleadoId))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaInicio)]))
        .get();
  }

  @override
  Future<Map<String, List<AsignacionServicioData>>> listarPorEmpleados(Iterable<String> empleadoIds) async {
    final unicos = empleadoIds.toSet();
    if (unicos.isEmpty) return {};
    final filas = await (_db.select(_db.asignacionServicio)
          ..where((t) => t.empleadoId.isIn(unicos))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaInicio)]))
        .get();

    final porEmpleado = <String, List<AsignacionServicioData>>{};
    for (final fila in filas) {
      porEmpleado.putIfAbsent(fila.empleadoId, () => []).add(fila);
    }
    return porEmpleado;
  }

  @override
  Future<List<AsignacionServicioData>> listarActivasPorServicio(String servicioId) {
    return (_db.select(_db.asignacionServicio)
          ..where((t) => t.servicioId.equals(servicioId) & t.fechaTermino.isNull()))
        .get();
  }

  @override
  Future<List<AsignacionServicioData>> listarTodasActivas() {
    return (_db.select(_db.asignacionServicio)..where((t) => t.fechaTermino.isNull())).get();
  }

  @override
  Future<List<AsignacionServicioData>> listarTodas() {
    return (_db.select(_db.asignacionServicio)..orderBy([(t) => OrderingTerm.asc(t.fechaInicio)])).get();
  }

  @override
  Future<List<AsignacionServicioData>> listarPorServicio(String servicioId) {
    return (_db.select(_db.asignacionServicio)
          ..where((t) => t.servicioId.equals(servicioId))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaInicio)]))
        .get();
  }

  /// Primera vigencia de sueldo de una asignación recién creada (Etapa
  /// 6B) — siempre abierta (`fechaFinVigencia == null`), fecha de inicio
  /// igual a la de la propia asignación. Ninguna `AsignacionServicio`
  /// existe sin al menos una de estas.
  Future<void> _crearPrimeraVigenciaSueldo({
    required String asignacionServicioId,
    required DateTime fechaInicio,
    required int sueldoMensual,
    required int bonoMensual,
  }) {
    return _db.into(_db.asignacionServicioSueldoVigencia).insert(
          AsignacionServicioSueldoVigenciaCompanion.insert(
            asignacionServicioId: asignacionServicioId,
            sueldoMensual: sueldoMensual,
            bonoMensual: bonoMensual,
            fechaInicioVigencia: fechaInicio,
          ),
        );
  }

  @override
  Future<AsignacionServicioData> asignar({
    required String empleadoId,
    required String servicioId,
    required DateTime fechaInicio,
    required int sueldoMensual,
    required int bonoMensual,
    String? turnoId,
    String? lineaComercialId,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final asignacion = await _db.into(_db.asignacionServicio).insertReturning(
            AsignacionServicioCompanion.insert(
              empleadoId: empleadoId,
              servicioId: servicioId,
              fechaInicio: fechaInicio,
              turnoId: Value(turnoId),
              lineaComercialId: Value(lineaComercialId),
              observaciones: Value(observaciones),
            ),
          );
      await _crearPrimeraVigenciaSueldo(
        asignacionServicioId: asignacion.id,
        fechaInicio: fechaInicio,
        sueldoMensual: sueldoMensual,
        bonoMensual: bonoMensual,
      );
      await registrarEventoEmpleado(
        _db,
        empleadoId: empleadoId,
        tipoEvento: TipoEventoEmpleado.asignacionServicio,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {'servicioId': servicioId, if (turnoId != null) 'turnoId': turnoId},
      );
      await _reconciliarVacante(
        lineaComercialId: lineaComercialId,
        servicioId: servicioId,
        fecha: fechaInicio,
        motivoApertura: 'aumentoRequerimiento',
        asignacionCoberturaId: asignacion.id,
      );
      return asignacion;
    });
  }

  @override
  Future<AsignacionServicioData> cambiarServicio({
    required String empleadoId,
    required String nuevoServicioId,
    required DateTime fecha,
    required int sueldoMensual,
    required int bonoMensual,
    String? turnoId,
    String? lineaComercialId,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await _buscarActivaPorEmpleado(empleadoId);
      if (anterior == null) {
        throw StateError('cambiarServicio: el Empleado $empleadoId no tiene una asignación vigente.');
      }

      await (_db.update(_db.asignacionServicio)..where((t) => t.id.equals(anterior.id))).write(
        AsignacionServicioCompanion(
          fechaTermino: Value(fecha),
          motivoTermino: Value(MotivoTerminoAsignacion.cambioServicio.name),
          updatedAt: Value(DateTime.now()),
        ),
      );

      final nueva = await _db.into(_db.asignacionServicio).insertReturning(
            AsignacionServicioCompanion.insert(
              empleadoId: empleadoId,
              servicioId: nuevoServicioId,
              fechaInicio: fecha,
              turnoId: Value(turnoId),
              lineaComercialId: Value(lineaComercialId),
              observaciones: Value(observaciones),
            ),
          );
      await _crearPrimeraVigenciaSueldo(
        asignacionServicioId: nueva.id,
        fechaInicio: fecha,
        sueldoMensual: sueldoMensual,
        bonoMensual: bonoMensual,
      );

      await registrarEventoEmpleado(
        _db,
        empleadoId: empleadoId,
        tipoEvento: TipoEventoEmpleado.cambioServicio,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {'servicioAnteriorId': anterior.servicioId, 'servicioNuevoId': nuevoServicioId},
      );
      // Dos líneas potencialmente afectadas: la que el Empleado deja
      // (puede abrir una vacante) y la nueva que ocupa (puede cerrar
      // una). Nunca la misma reconciliación — son líneas distintas.
      await _reconciliarVacante(
        lineaComercialId: anterior.lineaComercialId,
        servicioId: anterior.servicioId,
        fecha: fecha,
        motivoApertura: MotivoTerminoAsignacion.cambioServicio.name,
        asignacionOrigenId: anterior.id,
      );
      await _reconciliarVacante(
        lineaComercialId: lineaComercialId,
        servicioId: nuevoServicioId,
        fecha: fecha,
        motivoApertura: 'aumentoRequerimiento',
        asignacionCoberturaId: nueva.id,
      );
      return nueva;
    });
  }

  @override
  Future<AsignacionServicioData> retirar({
    required String empleadoId,
    required DateTime fechaTermino,
    required String motivo,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final activa = await _buscarActivaPorEmpleado(empleadoId);
      if (activa == null) {
        throw StateError('retirar: el Empleado $empleadoId no tiene una asignación vigente.');
      }

      await (_db.update(_db.asignacionServicio)..where((t) => t.id.equals(activa.id))).write(
        AsignacionServicioCompanion(
          fechaTermino: Value(fechaTermino),
          motivoTermino: Value(motivo),
          observacionesTermino: Value(observaciones),
          updatedAt: Value(DateTime.now()),
        ),
      );
      final actualizada = await (_db.select(_db.asignacionServicio)..where((t) => t.id.equals(activa.id))).getSingle();

      await registrarEventoEmpleado(
        _db,
        empleadoId: empleadoId,
        tipoEvento: TipoEventoEmpleado.retiroServicio,
        actorUsuarioId: actorUsuarioId,
        observacion: observaciones,
        datosRelevantes: {'servicioId': activa.servicioId, 'motivo': motivo},
      );
      await _reconciliarVacante(
        lineaComercialId: await _lineaComercialIdParaReconciliar(activa, fechaTermino),
        servicioId: activa.servicioId,
        fecha: fechaTermino,
        motivoApertura: motivo,
        asignacionOrigenId: activa.id,
      );
      return actualizada;
    });
  }

  @override
  Future<void> cerrarPorBajaEmpleado({required String empleadoId, required DateTime fecha}) {
    return _db.transaction(() async {
      final activa = await _buscarActivaPorEmpleado(empleadoId);
      if (activa == null) return;

      await (_db.update(_db.asignacionServicio)..where((t) => t.id.equals(activa.id))).write(
        AsignacionServicioCompanion(
          fechaTermino: Value(fecha),
          motivoTermino: Value(MotivoTerminoAsignacion.bajaEmpleado.name),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await registrarEventoEmpleado(
        _db,
        empleadoId: empleadoId,
        tipoEvento: TipoEventoEmpleado.retiroServicio,
        observacion: 'Cierre automático por Baja laboral.',
        datosRelevantes: {'servicioId': activa.servicioId, 'motivo': MotivoTerminoAsignacion.bajaEmpleado.name},
      );
      await _reconciliarVacante(
        lineaComercialId: await _lineaComercialIdParaReconciliar(activa, fecha),
        servicioId: activa.servicioId,
        fecha: fecha,
        motivoApertura: MotivoTerminoAsignacion.bajaEmpleado.name,
        asignacionOrigenId: activa.id,
      );
    });
  }

  @override
  Future<void> cerrarTodasPorServicioTerminado({required String servicioId, required DateTime fecha}) {
    return _db.transaction(() async {
      final activas = await (_db.select(_db.asignacionServicio)
            ..where((t) => t.servicioId.equals(servicioId) & t.fechaTermino.isNull()))
          .get();

      for (final asignacion in activas) {
        await (_db.update(_db.asignacionServicio)..where((t) => t.id.equals(asignacion.id))).write(
          AsignacionServicioCompanion(
            fechaTermino: Value(fecha),
            motivoTermino: Value(MotivoTerminoAsignacion.servicioTerminado.name),
            updatedAt: Value(DateTime.now()),
          ),
        );
        await registrarEventoEmpleado(
          _db,
          empleadoId: asignacion.empleadoId,
          tipoEvento: TipoEventoEmpleado.retiroServicio,
          observacion: 'Cierre automático por término del Servicio.',
          datosRelevantes: {'servicioId': servicioId, 'motivo': MotivoTerminoAsignacion.servicioTerminado.name},
        );
      }
      // Deliberadamente SIN reconciliar `VacanteOperativa` aquí: un
      // Servicio `terminado` deja de requerir cobertura por completo —
      // abrir vacantes en este momento crearía posiciones "pendientes"
      // que nunca volverán a cubrirse de forma operativamente real. El
      // Dashboard filtra sus cálculos de cobertura/vacantes a Servicios
      // `activo` (Parte D del pedido), así que un Servicio terminado
      // simplemente deja de aparecer — sin necesidad de abrir ni cerrar
      // nada aquí.
    });
  }

  @override
  Future<List<AsignacionServicioSueldoVigenciaData>> listarVigenciasSueldoActivas(String asignacionServicioId) {
    return (_db.select(_db.asignacionServicioSueldoVigencia)
          ..where(
            (t) =>
                t.asignacionServicioId.equals(asignacionServicioId) &
                t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
          ))
        .get();
  }

  @override
  Future<List<AsignacionServicioSueldoVigenciaData>> listarHistorialSueldo(String asignacionServicioId) {
    return (_db.select(_db.asignacionServicioSueldoVigencia)
          ..where((t) => t.asignacionServicioId.equals(asignacionServicioId))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaInicioVigencia)]))
        .get();
  }

  @override
  Future<AsignacionServicioData> regularizarPerfil({
    required String asignacionServicioId,
    required String lineaComercialId,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final actual = await (_db.select(_db.asignacionServicio)..where((t) => t.id.equals(asignacionServicioId))).getSingle();

      await (_db.update(_db.asignacionServicio)..where((t) => t.id.equals(asignacionServicioId))).write(
        AsignacionServicioCompanion(
          lineaComercialId: Value(lineaComercialId),
          updatedAt: Value(DateTime.now()),
        ),
      );
      final actualizada = await (_db.select(_db.asignacionServicio)..where((t) => t.id.equals(asignacionServicioId))).getSingle();

      await registrarEventoEmpleado(
        _db,
        empleadoId: actual.empleadoId,
        tipoEvento: TipoEventoEmpleado.regularizacionPerfilAsignacion,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {'servicioId': actual.servicioId, 'lineaComercialId': lineaComercialId},
      );

      // Ahora que la asignación sí referencia una línea, puede cerrar
      // una vacante abierta si esa línea tenía déficit (nunca abre una
      // nueva: regularizar solo completa un dato que ya existía en la
      // realidad operativa, no cambia cuántas personas hay asignadas).
      await _reconciliarVacante(
        lineaComercialId: lineaComercialId,
        servicioId: actual.servicioId,
        fecha: DateTime.now(),
        motivoApertura: 'aumentoRequerimiento',
        asignacionCoberturaId: asignacionServicioId,
      );

      return actualizada;
    });
  }

  @override
  Future<AsignacionServicioSueldoVigenciaData> registrarVigenciaSueldo({
    required String asignacionServicioId,
    required int sueldoMensual,
    required int bonoMensual,
    required DateTime fechaInicioVigencia,
    String? observaciones,
  }) {
    return _db.transaction(() async {
      final existentes = await listarVigenciasSueldoActivas(asignacionServicioId);
      final inicioNueva = soloFechaSueldo(fechaInicioVigencia);

      // Predecesora: la vigencia `activo` cuyo rango contiene o antecede
      // a la nueva fecha de inicio — a lo más una, por la invariante de
      // no-solapamiento (mismo criterio que `ServicioComercialRepositoryImpl.cambiarVigencia`).
      AsignacionServicioSueldoVigenciaData? predecesora;
      for (final v in existentes) {
        final inicio = soloFechaSueldo(v.fechaInicioVigencia);
        final fin = v.fechaFinVigencia == null ? null : soloFechaSueldo(v.fechaFinVigencia!);
        if (!inicio.isAfter(inicioNueva) && (fin == null || !fin.isBefore(inicioNueva))) {
          if (predecesora == null || inicio.isAfter(soloFechaSueldo(predecesora.fechaInicioVigencia))) {
            predecesora = v;
          }
        }
      }

      if (predecesora != null) {
        await (_db.update(_db.asignacionServicioSueldoVigencia)..where((t) => t.id.equals(predecesora!.id))).write(
          AsignacionServicioSueldoVigenciaCompanion(
            fechaFinVigencia: Value(inicioNueva.subtract(const Duration(days: 1))),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }

      // Sucesora: entre las restantes, la de fecha de inicio más
      // próxima después de la nueva.
      AsignacionServicioSueldoVigenciaData? sucesora;
      for (final v in existentes) {
        if (predecesora != null && v.id == predecesora.id) continue;
        final inicio = soloFechaSueldo(v.fechaInicioVigencia);
        if (inicio.isAfter(inicioNueva)) {
          if (sucesora == null || inicio.isBefore(soloFechaSueldo(sucesora.fechaInicioVigencia))) {
            sucesora = v;
          }
        }
      }

      final fechaFinNueva =
          sucesora != null ? soloFechaSueldo(sucesora.fechaInicioVigencia).subtract(const Duration(days: 1)) : null;

      return _db.into(_db.asignacionServicioSueldoVigencia).insertReturning(
            AsignacionServicioSueldoVigenciaCompanion.insert(
              asignacionServicioId: asignacionServicioId,
              sueldoMensual: sueldoMensual,
              bonoMensual: bonoMensual,
              fechaInicioVigencia: fechaInicioVigencia,
              fechaFinVigencia: Value(fechaFinNueva),
              observaciones: Value(observaciones),
            ),
          );
    });
  }
}
