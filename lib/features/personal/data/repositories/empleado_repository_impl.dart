import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/telefonia/data/repositories/asignacion_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/domain/repositories/asignacion_linea_telefonica_repository.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/database/tables/direccion_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart' show TipoPuesto;
import 'package:riseg_one/features/organizacion/domain/shared/direccion_input.dart';
import 'package:riseg_one/features/personal/domain/repositories/asignacion_servicio_repository.dart';
import 'package:uuid/uuid.dart';

import '../../domain/plantilla_personal.dart';
import '../../domain/repositories/empleado_repository.dart';
import '../../domain/usecases/eliminar_empleado_fisicamente_usecase.dart';
import '../tables/empleado_table.dart';
import 'empleado_evento_writer.dart';

class EmpleadoRepositoryImpl implements EmpleadoRepository {
  EmpleadoRepositoryImpl(
    this._db,
    this._asignacionServicioRepository, {
    AttachmentStorage? attachmentStorage,
    AsignacionLineaTelefonicaRepository? asignacionLineaTelefonicaRepository,
  })  : _attachmentStorage = attachmentStorage,
        _asignacionLineaTelefonicaRepository =
            asignacionLineaTelefonicaRepository ?? AsignacionLineaTelefonicaRepositoryImpl(_db);

  final AppDatabase _db;
  final AsignacionServicioRepository _asignacionServicioRepository;

  /// Telefonía entra aquí por la misma puerta que Servicios: al cerrar
  /// la relación laboral hay que cerrar TODO lo que la persona tenía
  /// vigente, y la línea telefónica es una de esas cosas.
  ///
  /// Dependencia en un solo sentido (Personal → Telefonía): los
  /// repositorios de Telefonía no dependen de `EmpleadoRepository`, así
  /// que no se introduce ningún ciclo. Con `default` para no romper a
  /// los muchos llamadores que solo necesitan leer Empleados.
  final AsignacionLineaTelefonicaRepository _asignacionLineaTelefonicaRepository;

  late final AttachmentRepository _attachmentRepository = AttachmentRepository(_db);

  /// Opcional a propósito (Etapa 15): la mayoría de los llamadores de
  /// este repositorio (Nómina, Reportes, Servicio, otras pruebas)
  /// nunca ejecutan `eliminarFisicamente` y no necesitan construir un
  /// `AttachmentStorage` real solo para satisfacer el constructor. En
  /// producción, el provider siempre lo pasa. Si es `null` y sí hay
  /// adjuntos que limpiar, el archivo físico simplemente no se intenta
  /// borrar — se reporta como no eliminado, nunca se oculta ni se
  /// finge éxito completo. Mismo criterio ya usado por
  /// `DocumentoPorEmitirRepositoryImpl`.
  final AttachmentStorage? _attachmentStorage;

  @override
  Future<EmpleadoData?> obtenerPorId(String id) {
    return (_db.select(_db.empleado)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<EmpleadoData>> listarPorIds(List<String> ids) {
    if (ids.isEmpty) return Future.value(const []);
    return (_db.select(_db.empleado)..where((t) => t.id.isIn(ids))).get();
  }

  @override
  Future<List<EmpleadoData>> listar({
    String? estatus,
    String? puestoId,
    String? empresaId,
    String? sucursalId,
  }) {
    final query = _db.select(_db.empleado)..where((t) => t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name));
    if (estatus != null) query.where((t) => t.estatus.equals(estatus));
    if (puestoId != null) query.where((t) => t.puestoId.equals(puestoId));
    if (empresaId != null) query.where((t) => t.empresaId.equals(empresaId));
    if (sucursalId != null) query.where((t) => t.sucursalId.equals(sucursalId));
    query.orderBy([(t) => OrderingTerm.asc(t.apellidoPaterno)]);
    return query.get();
  }

  @override
  Future<List<EmpleadoReporteRow>> listarParaReporte({String? estatus}) async {
    final query = _db.selectOnly(_db.empleado)
      ..addColumns([
        _db.empleado.id,
        _db.empleado.numeroEmpleado,
        _db.empleado.nombres,
        _db.empleado.apellidoPaterno,
        _db.empleado.apellidoMaterno,
        _db.empleado.estatus,
        _db.empleado.fechaIngreso,
        _db.empleado.fechaBaja,
        _db.empleado.motivoBaja,
        _db.empleado.puestoId,
        _db.empleado.sucursalId,
      ])
      ..where(_db.empleado.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name));
    if (estatus != null) query.where(_db.empleado.estatus.equals(estatus));
    query.orderBy([OrderingTerm.asc(_db.empleado.apellidoPaterno)]);

    final filas = await query.get();
    return [
      for (final fila in filas)
        EmpleadoReporteRow(
          id: fila.read(_db.empleado.id)!,
          numeroEmpleado: fila.read(_db.empleado.numeroEmpleado)!,
          nombres: fila.read(_db.empleado.nombres)!,
          apellidoPaterno: fila.read(_db.empleado.apellidoPaterno)!,
          apellidoMaterno: fila.read(_db.empleado.apellidoMaterno),
          estatus: fila.read(_db.empleado.estatus)!,
          fechaIngreso: fila.read(_db.empleado.fechaIngreso)!,
          fechaBaja: fila.read(_db.empleado.fechaBaja),
          motivoBaja: fila.read(_db.empleado.motivoBaja),
          puestoId: fila.read(_db.empleado.puestoId),
          sucursalId: fila.read(_db.empleado.sucursalId),
        ),
    ];
  }

  @override
  Future<List<EmpleadoEventoData>> listarEventos(String empleadoId) {
    return (_db.select(_db.empleadoEvento)
          ..where((t) => t.empleadoId.equals(empleadoId))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaHora)]))
        .get();
  }

  Future<void> _registrarEvento({
    required String empleadoId,
    required TipoEventoEmpleado tipoEvento,
    String? estadoAnterior,
    String? estadoNuevo,
    String? observacion,
    String? actorUsuarioId,
    Map<String, dynamic>? datosRelevantes,
  }) {
    return registrarEventoEmpleado(
      _db,
      empleadoId: empleadoId,
      tipoEvento: tipoEvento,
      estadoAnterior: estadoAnterior,
      estadoNuevo: estadoNuevo,
      observacion: observacion,
      actorUsuarioId: actorUsuarioId,
      datosRelevantes: datosRelevantes,
    );
  }

  @override
  Future<EmpleadoData> crear(
    EmpleadoCompanion datos, {
    String? servicioIdAsignacion,
    String? turnoIdAsignacion,
    String? lineaComercialIdAsignacion,
    int? sueldoMensualAsignacion,
    int? bonoMensualAsignacion,
  }) {
    return _db.transaction(() async {
      final empleado = await _db.into(_db.empleado).insertReturning(datos);
      await _registrarEvento(
        empleadoId: empleado.id,
        tipoEvento: TipoEventoEmpleado.creado,
        estadoNuevo: empleado.estatus,
      );

      // Adscripción a Servicio capturada en la misma alta (Etapa 5D) —
      // compuesto aquí, en la misma transacción, para que "para el
      // usuario parezca una sola captura" (Resolución explícita de
      // Marlon) sin que Empleado gane una columna `servicioId`. La
      // validación de que el Servicio exista y esté activo, y la
      // resolución de sueldo/bono (precarga desde Servicio o excepción
      // individual, Etapa 6B), ya ocurrieron en `CrearEmpleadoUseCase`
      // antes de llegar aquí — este método solo escribe.
      if (servicioIdAsignacion != null) {
        await _asignacionServicioRepository.asignar(
          empleadoId: empleado.id,
          servicioId: servicioIdAsignacion,
          fechaInicio: empleado.fechaIngreso,
          sueldoMensual: sueldoMensualAsignacion!,
          bonoMensual: bonoMensualAsignacion!,
          turnoId: turnoIdAsignacion,
          lineaComercialId: lineaComercialIdAsignacion,
        );
      }
      return empleado;
    });
  }

  @override
  Future<EmpleadoData> corregir({
    required String empleadoId,
    required EmpleadoCompanion cambios,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.empleado)..where((t) => t.id.equals(empleadoId))).write(
        cambios.copyWith(updatedAt: Value(DateTime.now())),
      );
      final actualizado = await (_db.select(_db.empleado)..where((t) => t.id.equals(empleadoId))).getSingle();

      await _registrarEvento(
        empleadoId: empleadoId,
        tipoEvento: TipoEventoEmpleado.corregido,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return actualizado;
    });
  }

  @override
  Future<EmpleadoData> registrarBajaLaboral({
    required String empleadoId,
    required DateTime fechaBaja,
    required String motivo,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.empleado)..where((t) => t.id.equals(empleadoId))).getSingle();

      // Snapshot de baja (Etapa 15) — se resuelve ANTES de cerrar la
      // asignación (todavía vigente en este punto exacto), para que
      // "el servicio/turno al momento de salir" quede capturado como
      // puro texto, nunca vuelto a resolver en vivo después (ver el
      // doc comment de `Empleado.puestoNombreBaja`).
      final puestoNombreBaja = await _resolverNombrePuesto(anterior.puestoId);
      final asignacionVigente = await _asignacionServicioRepository.obtenerActivaPorEmpleado(empleadoId);
      final servicioNombreBaja =
          asignacionVigente == null ? null : await _resolverNombreServicio(asignacionVigente.servicioId);
      final turnoNombreBaja =
          asignacionVigente == null ? null : await _resolverNombreTurno(asignacionVigente.turnoId);

      await (_db.update(_db.empleado)..where((t) => t.id.equals(empleadoId))).write(
        EmpleadoCompanion(
          estatus: Value(EstatusEmpleado.baja.name),
          fechaBaja: Value(fechaBaja),
          motivoBaja: Value(motivo),
          observacionesBaja: Value(observaciones),
          puestoNombreBaja: Value(puestoNombreBaja),
          servicioNombreBaja: Value(servicioNombreBaja),
          turnoNombreBaja: Value(turnoNombreBaja),
          updatedAt: Value(DateTime.now()),
        ),
      );
      final actualizado = await (_db.select(_db.empleado)..where((t) => t.id.equals(empleadoId))).getSingle();

      await _registrarEvento(
        empleadoId: empleadoId,
        tipoEvento: TipoEventoEmpleado.bajaLaboral,
        estadoAnterior: anterior.estatus,
        estadoNuevo: EstatusEmpleado.baja.name,
        observacion: observaciones,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {'motivo': motivo},
      );

      // Nunca debe quedar "Empleado = Baja, Servicio = Todavía asignado"
      // (Resolución explícita de Marlon, Etapa 5D) — se cierra en la
      // misma transacción, con la misma fecha efectiva de la baja.
      await _asignacionServicioRepository.cerrarPorBajaEmpleado(empleadoId: empleadoId, fecha: fechaBaja);

      // Y tampoco "Empleado = Baja, Línea telefónica = Todavía
      // asignada" (mini-etapa "Cierre automático de asignaciones de
      // Telefonía"). Misma transacción y misma fecha efectiva: si algo
      // falla al cerrar las líneas, la baja laboral tampoco ocurre.
      //
      // La línea NO se da de baja — queda disponible para reasignarse.
      // Quien se fue es la persona, no la línea.
      await _asignacionLineaTelefonicaRepository.cerrarPorBajaEmpleado(
        empleadoId: empleadoId,
        fecha: fechaBaja,
        actorUsuarioId: actorUsuarioId,
      );

      // Los bienes FÍSICOS son otra cosa (schemaVersion 82). Servicio y
      // línea son relaciones lógicas: terminarlas es la verdad completa.
      // Un radio o una camioneta siguen existiendo y siguen con la
      // persona hasta que alguien registre la devolución REAL.
      //
      // Por eso aquí no se cierra nada: se MARCA. Cerrar habría emitido
      // un movimiento de entrada por devolución, dejado la unidad
      // disponible y puesto el vehículo en disponible — es decir, habría
      // hecho desaparecer administrativamente bienes que RISEG todavía
      // debe recuperar.
      //
      // La baja laboral NUNCA se bloquea por esto: terminar la relación
      // laboral no depende de que alguien devuelva un radio.
      //
      // El marcado masivo automático SE RETIRÓ (ajuste de cierre de la
      // conciliación): era una puerta trasera al flujo obligatorio y
      // dejaba bienes en un limbo de "pendiente" que nadie había
      // decidido. Ahora `RegistrarBajaLaboralUseCase` rechaza la baja
      // si queda algún bien vigente sin resolver, y cada pendiente
      // nace de una resolución documentada.

      return actualizado;
    });
  }

  @override
  Future<ClasificacionEmpleado?> clasificar(String empleadoId) async {
    final empleado = await obtenerPorId(empleadoId);
    if (empleado == null) return null;
    final asignacion = await _asignacionServicioRepository.obtenerActivaPorEmpleado(empleadoId);
    final puesto = empleado.puestoId == null
        ? null
        : await (_db.select(_db.puesto)..where((t) => t.id.equals(empleado.puestoId!))).getSingleOrNull();
    return clasificarEmpleado(
      empleado: empleado,
      servicioIdVigente: asignacion?.servicioId,
      tipoPuesto: puesto == null ? null : TipoPuesto.values.byName(puesto.tipo),
    );
  }

  Future<String?> _resolverNombrePuesto(String? puestoId) async {
    if (puestoId == null) return null;
    final fila = await (_db.select(_db.puesto)..where((t) => t.id.equals(puestoId))).getSingleOrNull();
    return fila?.nombre;
  }

  Future<String?> _resolverNombreServicio(String servicioId) async {
    final fila = await (_db.select(_db.servicio)..where((t) => t.id.equals(servicioId))).getSingleOrNull();
    return fila?.nombre;
  }

  Future<String?> _resolverNombreTurno(String? turnoId) async {
    if (turnoId == null) return null;
    final fila = await (_db.select(_db.tipoModalidadTurno)..where((t) => t.id.equals(turnoId))).getSingleOrNull();
    return fila?.nombre;
  }

  @override
  Future<EmpleadoData> registrarReingreso({
    required String empleadoId,
    required DateTime fechaIngreso,
    String? puestoId,
    bool limpiarPuesto = false,
    String? sucursalId,
    bool limpiarSucursal = false,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.empleado)..where((t) => t.id.equals(empleadoId))).getSingle();

      // Archiva el periodo cerrado que se está reemplazando — solo si
      // realmente había uno cerrado (fechaBaja/motivoBaja no nulos).
      // Ver el doc comment de `EmpleadoPeriodoLaboral`: nunca contiene
      // el periodo vigente, solo se le agrega una fila aquí.
      if (anterior.fechaBaja != null && anterior.motivoBaja != null) {
        await _db.into(_db.empleadoPeriodoLaboral).insert(
              EmpleadoPeriodoLaboralCompanion.insert(
                empleadoId: empleadoId,
                fechaIngreso: anterior.fechaIngreso,
                fechaBaja: anterior.fechaBaja!,
                motivoBaja: anterior.motivoBaja!,
                observacionesBaja: Value(anterior.observacionesBaja),
                // Copiado tal cual desde el snapshot ya capturado en
                // `registrarBajaLaboral` — nunca se vuelve a resolver
                // aquí (ver el doc comment de `EmpleadoPeriodoLaboral`).
                puestoNombre: Value(anterior.puestoNombreBaja),
                servicioNombre: Value(anterior.servicioNombreBaja),
                turnoNombre: Value(anterior.turnoNombreBaja),
              ),
            );
      }

      await (_db.update(_db.empleado)..where((t) => t.id.equals(empleadoId))).write(
        EmpleadoCompanion(
          estatus: Value(EstatusEmpleado.activo.name),
          fechaIngreso: Value(fechaIngreso),
          fechaBaja: const Value(null),
          motivoBaja: const Value(null),
          observacionesBaja: const Value(null),
          puestoNombreBaja: const Value(null),
          servicioNombreBaja: const Value(null),
          turnoNombreBaja: const Value(null),
          puestoId: limpiarPuesto ? const Value(null) : (puestoId == null ? const Value.absent() : Value(puestoId)),
          sucursalId:
              limpiarSucursal ? const Value(null) : (sucursalId == null ? const Value.absent() : Value(sucursalId)),
          updatedAt: Value(DateTime.now()),
        ),
      );
      final actualizado = await (_db.select(_db.empleado)..where((t) => t.id.equals(empleadoId))).getSingle();

      await _registrarEvento(
        empleadoId: empleadoId,
        tipoEvento: TipoEventoEmpleado.reingreso,
        estadoAnterior: anterior.estatus,
        estadoNuevo: EstatusEmpleado.activo.name,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {'fechaIngreso': fechaIngreso.toIso8601String()},
      );
      return actualizado;
    });
  }

  @override
  Future<List<EmpleadoPeriodoLaboralData>> listarPeriodosLaboralesArchivados(String empleadoId) {
    return (_db.select(_db.empleadoPeriodoLaboral)
          ..where((t) => t.empleadoId.equals(empleadoId))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaIngreso)]))
        .get();
  }

  @override
  Future<Map<String, List<EmpleadoPeriodoLaboralData>>> listarPeriodosLaboralesArchivadosPorEmpleados(
    List<String> empleadoIds,
  ) async {
    if (empleadoIds.isEmpty) return {};
    final filas = await (_db.select(_db.empleadoPeriodoLaboral)
          ..where((t) => t.empleadoId.isIn(empleadoIds))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaIngreso)]))
        .get();

    final porEmpleado = <String, List<EmpleadoPeriodoLaboralData>>{};
    for (final fila in filas) {
      (porEmpleado[fila.empleadoId] ??= []).add(fila);
    }
    return porEmpleado;
  }

  @override
  Future<EmpleadoData> actualizarFotografia({
    required String empleadoId,
    required String attachmentId,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.empleado)..where((t) => t.id.equals(empleadoId))).write(
        EmpleadoCompanion(fotografiaAttachmentId: Value(attachmentId), updatedAt: Value(DateTime.now())),
      );
      final actualizado = await (_db.select(_db.empleado)..where((t) => t.id.equals(empleadoId))).getSingle();

      await _registrarEvento(
        empleadoId: empleadoId,
        tipoEvento: TipoEventoEmpleado.fotografiaActualizada,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {'attachmentId': attachmentId},
      );
      return actualizado;
    });
  }

  @override
  Future<DireccionData?> obtenerDomicilio(String empleadoId) {
    return (_db.select(_db.direccion)
          ..where((t) => t.empleadoId.equals(empleadoId) & t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name)))
        .getSingleOrNull();
  }

  /// Busca el domicilio de este Empleado sin importar
  /// `cicloVidaRegistro` — `empleadoId` tiene un `.unique()` real en
  /// `Direccion` (1:1), así que solo puede existir una fila por
  /// Empleado en toda su historia (mismo patrón que
  /// `EntidadFiscalRepositoryImpl._buscarDomicilioDeEntidadFiscal`).
  Future<DireccionData?> _buscarDomicilioDeEmpleado(String empleadoId) {
    return (_db.select(_db.direccion)..where((t) => t.empleadoId.equals(empleadoId))).getSingleOrNull();
  }

  @override
  Future<DireccionData?> guardarDomicilio(String empleadoId, DireccionInput? input, {String? actorUsuarioId}) async {
    final existente = await _buscarDomicilioDeEmpleado(empleadoId);

    if (input == null) {
      if (existente != null && existente.cicloVidaRegistro == CicloVidaRegistro.activo.name) {
        await (_db.update(_db.direccion)..where((t) => t.id.equals(existente.id))).write(
          DireccionCompanion(
            cicloVidaRegistro: Value(CicloVidaRegistro.archivado.name),
            updatedAt: Value(DateTime.now()),
          ),
        );
        await _registrarEvento(empleadoId: empleadoId, tipoEvento: TipoEventoEmpleado.domicilioActualizado, actorUsuarioId: actorUsuarioId);
      }
      return null;
    }

    final cambios = DireccionCompanion(
      cicloVidaRegistro: Value(CicloVidaRegistro.activo.name),
      calle: Value(input.calle),
      numeroExterior: Value(input.numeroExterior),
      numeroInterior: Value(input.numeroInterior),
      colonia: Value(input.colonia),
      municipioAlcaldia: Value(input.municipioAlcaldia),
      ciudadLocalidad: Value(input.ciudadLocalidad),
      estado: Value(input.estado),
      codigoPostal: Value(input.codigoPostal),
      pais: Value(input.pais),
      referencias: Value(input.referencias),
      updatedAt: Value(DateTime.now()),
    );

    final DireccionData resultado;
    if (existente != null) {
      // Reactiva (si venía archivado) y actualiza — nunca un segundo
      // `INSERT`, que chocaría con el `.unique()` de `empleadoId`.
      final actualizada = existente.copyWithCompanion(cambios);
      await _db.update(_db.direccion).replace(actualizada);
      resultado = actualizada;
    } else {
      resultado = await _db.into(_db.direccion).insertReturning(
            DireccionCompanion.insert(
              empleadoId: Value(empleadoId),
              tipoDireccion: TipoDireccion.domicilio.name,
              calle: input.calle,
              numeroExterior: input.numeroExterior,
              numeroInterior: Value(input.numeroInterior),
              colonia: input.colonia,
              municipioAlcaldia: input.municipioAlcaldia,
              ciudadLocalidad: Value(input.ciudadLocalidad),
              estado: input.estado,
              codigoPostal: input.codigoPostal,
              pais: Value(input.pais),
              referencias: Value(input.referencias),
            ),
          );
    }

    await _registrarEvento(empleadoId: empleadoId, tipoEvento: TipoEventoEmpleado.domicilioActualizado, actorUsuarioId: actorUsuarioId);
    return resultado;
  }

  @override
  Future<AttachmentData> adjuntarDocumento({
    required String empleadoId,
    required String categoria,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final adjunto = await _db.into(_db.attachment).insertReturning(
            AttachmentCompanion.insert(
              id: const Uuid().v4(),
              categoria: Value(categoria),
              originalFileName: originalFileName,
              storedFileName: storedFileName,
              path: path,
              mimeType: mimeType,
              sizeBytes: sizeBytes,
            ),
          );
      await _db.into(_db.empleadoAttachment).insert(
            EmpleadoAttachmentCompanion.insert(attachmentId: adjunto.id, empleadoId: empleadoId),
          );

      await _registrarEvento(
        empleadoId: empleadoId,
        tipoEvento: TipoEventoEmpleado.documentoAdjuntado,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {'categoria': categoria, 'archivoNuevo': originalFileName, 'attachmentId': adjunto.id},
      );

      return adjunto;
    });
  }

  @override
  Future<EmpleadoData> actualizarPerfilPsicologico({
    required String empleadoId,
    required DateTime fecha,
    String? resumen,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.empleado)..where((t) => t.id.equals(empleadoId))).write(
        EmpleadoCompanion(
          fechaEvaluacionPsicologica: Value(fecha),
          resumenPsicologico: Value(resumen),
          observacionesPsicologico: Value(observaciones),
          updatedAt: Value(DateTime.now()),
        ),
      );
      final actualizado = await (_db.select(_db.empleado)..where((t) => t.id.equals(empleadoId))).getSingle();

      await _registrarEvento(
        empleadoId: empleadoId,
        tipoEvento: TipoEventoEmpleado.perfilPsicologicoActualizado,
        actorUsuarioId: actorUsuarioId,
      );
      return actualizado;
    });
  }

  @override
  Future<EmpleadoData> actualizarEstudioSocioeconomico({
    required String empleadoId,
    required DateTime fecha,
    String? resumen,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.empleado)..where((t) => t.id.equals(empleadoId))).write(
        EmpleadoCompanion(
          fechaEstudioSocioeconomico: Value(fecha),
          resumenEstudioSocioeconomico: Value(resumen),
          observacionesEstudioSocioeconomico: Value(observaciones),
          updatedAt: Value(DateTime.now()),
        ),
      );
      final actualizado = await (_db.select(_db.empleado)..where((t) => t.id.equals(empleadoId))).getSingle();

      await _registrarEvento(
        empleadoId: empleadoId,
        tipoEvento: TipoEventoEmpleado.estudioSocioeconomicoActualizado,
        actorUsuarioId: actorUsuarioId,
      );
      return actualizado;
    });
  }

  @override
  Future<EmpleadoData> actualizarAntidoping({
    required String empleadoId,
    required DateTime fecha,
    required ResultadoSustanciaAntidoping amp,
    required ResultadoSustanciaAntidoping bzd,
    required ResultadoSustanciaAntidoping coc,
    required ResultadoSustanciaAntidoping met,
    required ResultadoSustanciaAntidoping opi,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.empleado)..where((t) => t.id.equals(empleadoId))).write(
        EmpleadoCompanion(
          fechaAntidoping: Value(fecha),
          resultadoAmp: Value(amp.name),
          resultadoBzd: Value(bzd.name),
          resultadoCoc: Value(coc.name),
          resultadoMet: Value(met.name),
          resultadoOpi: Value(opi.name),
          observacionesAntidoping: Value(observaciones),
          updatedAt: Value(DateTime.now()),
        ),
      );
      final actualizado = await (_db.select(_db.empleado)..where((t) => t.id.equals(empleadoId))).getSingle();

      await _registrarEvento(
        empleadoId: empleadoId,
        tipoEvento: TipoEventoEmpleado.antidopingActualizado,
        actorUsuarioId: actorUsuarioId,
      );
      return actualizado;
    });
  }

  /// Única historia real que bloquea la eliminación física (Etapa 15,
  /// decisión explícita de Marlon): Nómina generada, Asignación a
  /// Servicio, resguardo/reclamo de Inventario, Vehículo o Línea
  /// telefónica asignados — todas FK `restrict` reales hacia Empleado.
  /// `FichaTecnicaEmpleado` (también `restrict`) deliberadamente NO
  /// está aquí: se limpia junto con el Empleado (ver
  /// [eliminarFisicamente]), nunca bloquea — los expedientes de prueba
  /// de esta etapa ya generaron fichas técnicas y eso no debe impedir
  /// limpiarlos.
  Future<String?> _detalleBloqueoEliminacionFisica(String empleadoId) async {
    final asignacionesServicio =
        await (_db.select(_db.asignacionServicio)..where((t) => t.empleadoId.equals(empleadoId))).get();
    if (asignacionesServicio.isNotEmpty) {
      return 'Este Empleado tiene historial de Asignación a Servicio — no puede eliminarse físicamente.';
    }

    final nomina = await (_db.select(_db.nominaEmpleado)..where((t) => t.empleadoId.equals(empleadoId))).get();
    if (nomina.isNotEmpty) {
      return 'Este Empleado tiene Nómina generada — no puede eliminarse físicamente.';
    }

    final asignacionesInventario = await (_db.select(_db.asignacion)..where((t) => t.empleadoId.equals(empleadoId))).get();
    if (asignacionesInventario.isNotEmpty) {
      return 'Este Empleado tiene resguardos de Inventario registrados — no puede eliminarse físicamente.';
    }

    final descuentos = await (_db.select(_db.descuentoInventario)..where((t) => t.empleadoId.equals(empleadoId))).get();
    if (descuentos.isNotEmpty) {
      return 'Este Empleado tiene reclamos de Inventario (daño/pérdida) registrados — no puede eliminarse '
          'físicamente.';
    }

    final vehiculos = await (_db.select(_db.asignacionVehiculo)..where((t) => t.empleadoId.equals(empleadoId))).get();
    if (vehiculos.isNotEmpty) {
      return 'Este Empleado tiene Vehículos asignados — no puede eliminarse físicamente.';
    }

    final lineas =
        await (_db.select(_db.asignacionLineaTelefonica)..where((t) => t.empleadoId.equals(empleadoId))).get();
    if (lineas.isNotEmpty) {
      return 'Este Empleado tiene Líneas telefónicas asignadas — no puede eliminarse físicamente.';
    }

    return null;
  }

  @override
  Future<ResumenEliminacionEmpleado> obtenerResumenEliminacionFisica(String empleadoId) async {
    final empleado = await obtenerPorId(empleadoId);
    if (empleado == null) return const ResumenEliminacionEmpleado(existe: false);

    final detalleBloqueo = await _detalleBloqueoEliminacionFisica(empleadoId);
    final fichas = await (_db.select(_db.fichaTecnicaEmpleado)..where((t) => t.empleadoId.equals(empleadoId))).get();
    final documentos = await (_db.select(_db.empleadoAttachment)..where((t) => t.empleadoId.equals(empleadoId))).get();

    return ResumenEliminacionEmpleado(
      existe: true,
      cantidadFichasTecnicas: fichas.length,
      cantidadDocumentos: documentos.length,
      detalleBloqueo: detalleBloqueo,
    );
  }

  /// Eliminación física extraordinaria (Etapa 15) — el único bloqueador
  /// real es historia posterior verificada por
  /// [_detalleBloqueoEliminacionFisica]. `FichaTecnicaEmpleado` nunca
  /// bloquea (decisión explícita de Marlon): se limpia junto con el
  /// Empleado, incluido su PDF físico, con el mismo criterio seguro ya
  /// usado por `DocumentoPorEmitirRepositoryImpl.eliminarFisicamente`:
  /// las filas de BD (fichas técnicas, domicilio, Empleado, y los
  /// `Attachment` ahora huérfanos de la ficha y del propio expediente
  /// — fotografía/documentos) se borran todas dentro de una sola
  /// transacción; los archivos físicos en disco se borran DESPUÉS de
  /// que esa transacción haga commit — nunca antes: si la transacción
  /// falla, ningún registro queda apuntando a un archivo ya borrado; si
  /// un archivo no se puede borrar (permisos, en uso), la base de datos
  /// ya quedó consistente y el Empleado ya está eliminado — el archivo
  /// huérfano se reporta explícitamente en el resultado, nunca se
  /// oculta. `EmpleadoEvento`/`EmpleadoPeriodoLaboral`/
  /// `EmpleadoAttachment` (la tabla puente) son `cascade`, se limpian
  /// solos al borrar la fila de Empleado.
  @override
  Future<EliminarEmpleadoFisicamenteResultado> eliminarFisicamente({
    required String empleadoId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final empleadoInicial = await obtenerPorId(empleadoId);
    if (empleadoInicial == null) return EliminarEmpleadoFisicamenteNoExiste();

    final detalleBloqueo = await _detalleBloqueoEliminacionFisica(empleadoId);
    if (detalleBloqueo != null) return EliminarEmpleadoFisicamenteTieneDependencias(detalleBloqueo);

    final fichas = await (_db.select(_db.fichaTecnicaEmpleado)..where((t) => t.empleadoId.equals(empleadoId))).get();
    final eventos = await listarEventos(empleadoId);
    final periodos = await listarPeriodosLaboralesArchivados(empleadoId);
    final domicilio = await _buscarDomicilioDeEmpleado(empleadoId);

    // Capturados antes de la transacción para poder borrar los
    // archivos físicos después del commit.
    final fichaAdjuntosQuery = _db.select(_db.attachment).join([
      innerJoin(_db.fichaTecnicaEmpleado, _db.fichaTecnicaEmpleado.attachmentId.equalsExp(_db.attachment.id)),
    ])
      ..where(_db.fichaTecnicaEmpleado.empleadoId.equals(empleadoId));
    final fichaAdjuntos = await fichaAdjuntosQuery.map((row) => row.readTable(_db.attachment)).get();

    final empleadoAdjuntosQuery = _db.select(_db.attachment).join([
      innerJoin(_db.empleadoAttachment, _db.empleadoAttachment.attachmentId.equalsExp(_db.attachment.id)),
    ])
      ..where(_db.empleadoAttachment.empleadoId.equals(empleadoId));
    final empleadoAdjuntos = await empleadoAdjuntosQuery.map((row) => row.readTable(_db.attachment)).get();

    await _db.transaction(() async {
      final snapshot = <String, Object?>{
        'empleado': empleadoInicial.toJson(),
        'domicilio': domicilio?.toJson(),
        'eventos': [for (final e in eventos) e.toJson()],
        'periodosLaboralesArchivados': [for (final p in periodos) p.toJson()],
        'fichasTecnicas': [for (final f in fichas) f.toJson()],
        'fichaAdjuntos': [for (final a in fichaAdjuntos) a.toJson()],
        'empleadoAdjuntos': [for (final a in empleadoAdjuntos) a.toJson()],
      };

      // 1. Fichas técnicas — su FK hacia Empleado es `restrict`, deben
      // limpiarse antes de poder borrar el Empleado.
      for (final ficha in fichas) {
        await (_db.delete(_db.fichaTecnicaEmpleado)..where((t) => t.id.equals(ficha.id))).go();
      }

      await _db.into(_db.eliminacionFisicaEvento).insert(
            EliminacionFisicaEventoCompanion.insert(
              tipoEntidad: 'empleado',
              entidadIdOriginal: empleadoId,
              fechaHora: DateTime.now(),
              motivo: motivo,
              snapshotJson: jsonEncode(snapshot),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );

      // 2. Domicilio (`Direccion.empleadoId` — columna simple, sin FK
      // real) — se limpia explícitamente para no dejarlo huérfano.
      if (domicilio != null) {
        await (_db.delete(_db.direccion)..where((t) => t.id.equals(domicilio.id))).go();
      }

      // 3. El Empleado en sí — `EmpleadoEvento`/`EmpleadoPeriodoLaboral`/
      // `EmpleadoAttachment` son `cascade`, se limpian solos.
      await (_db.delete(_db.empleado)..where((t) => t.id.equals(empleadoId))).go();

      // 4. Attachments ahora huérfanos (PDFs de fichas técnicas +
      // fotografía/documentos propios del expediente) — ninguna FK los
      // cascada automáticamente, se borran explícitamente.
      for (final adjunto in fichaAdjuntos) {
        await _attachmentRepository.eliminarFisico(adjunto.id);
      }
      for (final adjunto in empleadoAdjuntos) {
        await _attachmentRepository.eliminarFisico(adjunto.id);
      }
    });

    final archivosNoEliminados = <String>[];
    for (final adjunto in [...fichaAdjuntos, ...empleadoAdjuntos]) {
      if (_attachmentStorage == null) {
        archivosNoEliminados.add(adjunto.originalFileName);
        continue;
      }
      try {
        await _attachmentStorage.eliminarArchivo(adjunto.path);
      } catch (_) {
        archivosNoEliminados.add(adjunto.originalFileName);
      }
    }

    return EliminarEmpleadoFisicamenteExitoso(archivosNoEliminadosFisicamente: archivosNoEliminados);
  }
}
