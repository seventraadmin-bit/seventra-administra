import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/utils/clock.dart';
import 'package:uuid/uuid.dart';

import '../tables/comercial_evento_table.dart';
import 'comercial_evento_writer.dart';
import '../../domain/repositories/configuracion_cobro_repository.dart';
import '../../domain/usecases/configuracion_cobro_con_vigencia.dart';
import '../../domain/usecases/configuracion_cobro_etapa_validator.dart';
import '../../domain/usecases/configuracion_cobro_validator.dart';

class ConfiguracionCobroRepositoryImpl implements ConfiguracionCobroRepository {
  ConfiguracionCobroRepositoryImpl(this._db, {Clock clock = const SystemClock()}) : _clock = clock;

  final AppDatabase _db;
  final Clock _clock;

  /// BUG REAL (MORGAN ATLACOMULCO): "Nueva vigencia" fallaba siempre con
  /// `UNIQUE constraint failed: configuracion_cobro_etapa.id`.
  ///
  /// `EtapaCobroBorrador.id` es una **clave de correlación dentro del
  /// lote** — existe para que `etapaReferenciaId` pueda apuntar a una
  /// etapa hermana antes de que ninguna fila exista. NO es la clave
  /// primaria de la fila, aunque hasta ahora se insertaba tal cual.
  ///
  /// El formulario de Nueva vigencia se precarga con las etapas de la
  /// vigencia vigente (`EtapaEditState.desdeExistente` conserva su `id`
  /// real, y debe conservarlo: es lo que mantiene válidas las
  /// referencias entre etapas mientras se edita). Al guardar, esos
  /// mismos ids llegaban aquí y se intentaban insertar como filas
  /// NUEVAS de una vigencia NUEVA — colisión de llave primaria contra
  /// las filas de la vigencia anterior, que siguen existiendo porque el
  /// histórico no se toca. La transacción revertía todo, así que la
  /// vigencia anterior quedaba intacta y la nueva no se creaba:
  /// exactamente el síntoma reportado.
  ///
  /// La identidad de la fila la asigna la capa de persistencia, aquí:
  /// se reasigna un id nuevo a cada etapa y se remapea
  /// `etapaReferenciaId` por el mismo diccionario, de modo que el grafo
  /// de referencias del lote se conserva idéntico. Corregirlo aquí (y no
  /// en el formulario) deja bien a TODOS los llamadores — alta,
  /// corrección y nueva vigencia — y no vuelve a romperse si mañana otro
  /// llamador reusa ids.
  Future<void> _insertarCorreosYEtapas({
    required String vigenciaId,
    required List<String> correos,
    required List<EtapaCobroValidada> etapas,
  }) async {
    // Una etapa puede referenciar a otra que aparezca después en la
    // lista (el orden de captura del usuario no tiene por qué coincidir
    // con el orden de dependencia) — diferir el chequeo de FK al final
    // de la transacción evita depender de insertar en un orden
    // topológico exacto.
    await _db.customStatement('PRAGMA defer_foreign_keys = ON');
    for (final correo in correos) {
      await _db.into(_db.configuracionCobroCorreo).insert(
            ConfiguracionCobroCorreoCompanion.insert(configuracionCobroVigenciaId: vigenciaId, correo: correo),
          );
    }

    final idPersistido = {for (final etapa in etapas) etapa.id: const Uuid().v4()};

    for (final etapa in etapas) {
      final referencia = etapa.etapaReferenciaId;
      await _db.into(_db.configuracionCobroEtapa).insert(
            ConfiguracionCobroEtapaCompanion.insert(
              id: idPersistido[etapa.id]!,
              configuracionCobroVigenciaId: vigenciaId,
              tipoSistema: Value(etapa.tipoSistema?.name),
              nombre: Value(etapa.nombre),
              orden: etapa.orden,
              tipoRegla: Value(etapa.tipoRegla?.name),
              mesRelativo: Value(etapa.mesRelativo?.name),
              diaDelMes: Value(etapa.diaDelMes),
              ordinalSemana: Value(etapa.ordinalSemana?.name),
              diaSemana: Value(etapa.diaSemana?.name),
              offsetDias: Value(etapa.offsetDias),
              // Una referencia siempre apunta a una etapa del MISMO lote
              // (lo garantiza `ConfiguracionCobroEtapaValidator`), así
              // que el diccionario siempre la resuelve. El `??` deja la
              // referencia original solo por defensa: nunca debería
              // usarse, y si se usara la FK diferida la rechazaría en
              // vez de escribir un vínculo silenciosamente roto.
              etapaReferenciaId: Value(referencia == null ? null : idPersistido[referencia] ?? referencia),
              referenciaCierrePeriodo: Value(etapa.referenciaCierrePeriodo),
            ),
          );
    }
  }

  /// Las reglas de cobro de una vigencia, tal como quedan.
  ///
  /// Se usa como snapshot en los hechos que ABREN reglas (alta y nueva
  /// vigencia): ahí no hay un "antes" que comparar; lo que hay que
  /// poder responder después es qué empezó a aplicar y desde cuándo se
  /// factura o se espera cobrar.
  Map<String, dynamic> _reglasDe(ConfiguracionCobroVigenciaData v) => {
        'vigenciaId': v.id,
        'tipoDocumento': v.tipoDocumento,
        'frecuenciaId': v.frecuenciaId,
        'diaInicioPeriodo': v.diaInicioPeriodo,
        'agrupacion': v.agrupacion,
        'metodo': v.metodo,
        'requiereComplemento': v.requiereComplemento,
        'entidadFiscalId': v.entidadFiscalId,
        'fechaInicioVigencia': v.fechaInicioVigencia.toIso8601String(),
        'fechaFinVigencia': v.fechaFinVigencia?.toIso8601String(),
      };

  /// Resumen de las etapas — qué determina CUÁNDO se factura y cuándo
  /// se espera el pago. Se guarda la forma de cada regla y su
  /// referencia ya remapeada, nunca el id del borrador.
  Future<List<Map<String, dynamic>>> _resumenEtapas(String vigenciaId) async {
    final etapas = await listarEtapas(vigenciaId);
    return [
      for (final e in etapas)
        {
          'etapaId': e.id,
          'tipoSistema': e.tipoSistema,
          'nombre': e.nombre,
          'orden': e.orden,
          'tipoRegla': e.tipoRegla,
          'mesRelativo': e.mesRelativo,
          'diaDelMes': e.diaDelMes,
          'ordinalSemana': e.ordinalSemana,
          'diaSemana': e.diaSemana,
          'offsetDias': e.offsetDias,
          'etapaReferenciaId': e.etapaReferenciaId,
          'referenciaCierrePeriodo': e.referenciaCierrePeriodo,
        },
    ];
  }

  DiffEvento _diffReglas(ConfiguracionCobroVigenciaData antes, ConfiguracionCobroVigenciaData despues) =>
      DiffEvento()
        ..anotar('tipoDocumento', antes.tipoDocumento, despues.tipoDocumento)
        ..anotar('frecuenciaId', antes.frecuenciaId, despues.frecuenciaId)
        ..anotar('diaInicioPeriodo', antes.diaInicioPeriodo, despues.diaInicioPeriodo)
        ..anotar('agrupacion', antes.agrupacion, despues.agrupacion)
        ..anotar('metodo', antes.metodo, despues.metodo)
        ..anotar('requiereComplemento', antes.requiereComplemento, despues.requiereComplemento)
        ..anotar('entidadFiscalId', antes.entidadFiscalId, despues.entidadFiscalId)
        ..anotar('clientePortalId', antes.clientePortalId, despues.clientePortalId)
        ..anotar('cuentaBancaria', antes.cuentaBancaria, despues.cuentaBancaria)
        ..anotar('observaciones', antes.observaciones, despues.observaciones)
        ..anotar('fechaInicioVigencia', antes.fechaInicioVigencia, despues.fechaInicioVigencia)
        ..anotar('fechaFinVigencia', antes.fechaFinVigencia, despues.fechaFinVigencia);

  @override
  Future<({ConfiguracionCobroData configuracion, ConfiguracionCobroVigenciaData vigencia})> crearConfiguracion({
    required String servicioId,
    required ConfiguracionCobroValidada datos,
    required List<EtapaCobroValidada> etapas,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final configuracion = await _db.into(_db.configuracionCobro).insertReturning(
            ConfiguracionCobroCompanion.insert(servicioId: servicioId),
          );

      final vigencia = await _db.into(_db.configuracionCobroVigencia).insertReturning(
            ConfiguracionCobroVigenciaCompanion.insert(
              configuracionCobroId: configuracion.id,
              tipoDocumento: datos.tipoDocumento.name,
              frecuenciaId: datos.frecuenciaId,
              diaInicioPeriodo: datos.diaInicioPeriodo,
              agrupacion: datos.agrupacion.name,
              metodo: datos.metodo.name,
              requiereComplemento: Value(datos.requiereComplemento),
              entidadFiscalId: Value(datos.entidadFiscalId),
              clientePortalId: Value(datos.clientePortalId),
              cuentaBancaria: Value(datos.cuentaBancaria),
              observaciones: Value(datos.observaciones),
              fechaInicioVigencia: datos.fechaInicioVigencia,
            ),
          );

      await _insertarCorreosYEtapas(vigenciaId: vigencia.id, correos: datos.correos, etapas: etapas);

      // Alta: sin motivo — no hay nada que enmendar. Se guarda qué reglas
      // de facturación y cobro empiezan a aplicar, con sus etapas ya
      // persistidas (ids reales, nunca los del borrador).
      await registrarEventoConfiguracionCobro(
        _db,
        configuracionCobroId: configuracion.id,
        tipoEvento: TipoEventoConfiguracionCobro.creada,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {..._reglasDe(vigencia), 'etapas': await _resumenEtapas(vigencia.id)},
      );

      return (configuracion: configuracion, vigencia: vigencia);
    });
  }

  Future<List<ConfiguracionCobroVigenciaData>> _vigenciasActivas(String configuracionCobroId) {
    return (_db.select(_db.configuracionCobroVigencia)
          ..where(
            (t) =>
                t.configuracionCobroId.equals(configuracionCobroId) &
                t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
          ))
        .get();
  }

  @override
  Future<ConfiguracionCobroConVigencia?> obtenerConfiguracion(String servicioId) async {
    final configuracion =
        await (_db.select(_db.configuracionCobro)..where((t) => t.servicioId.equals(servicioId))).getSingleOrNull();
    if (configuracion == null) return null;

    final vigenciasActivas = await _vigenciasActivas(configuracion.id);

    final hoy = _clock.now();
    final (:vigente, :programadas) = clasificarVigenciasCobro(vigenciasActivas, hoy);
    final vigenciaParaDetalle = vigente ?? (programadas.isEmpty ? null : programadas.first);

    var correos = const <String>[];
    var etapas = const <ConfiguracionCobroEtapaData>[];
    String? entidadFiscalRazonSocial;
    String? frecuenciaNombre;
    String? clientePortalNombre;
    if (vigenciaParaDetalle != null) {
      correos = await listarCorreos(vigenciaParaDetalle.id);
      etapas = await listarEtapas(vigenciaParaDetalle.id);

      final entidadFiscalId = vigenciaParaDetalle.entidadFiscalId;
      if (entidadFiscalId != null) {
        final entidad =
            await (_db.select(_db.entidadFiscal)..where((t) => t.id.equals(entidadFiscalId))).getSingleOrNull();
        entidadFiscalRazonSocial = entidad?.razonSocial;
      }

      final clientePortalId = vigenciaParaDetalle.clientePortalId;
      if (clientePortalId != null) {
        final portal =
            await (_db.select(_db.clientePortal)..where((t) => t.id.equals(clientePortalId))).getSingleOrNull();
        clientePortalNombre = portal?.nombre;
      }

      final frecuencia = await (_db.select(_db.tipoFrecuenciaCobro)
            ..where((t) => t.id.equals(vigenciaParaDetalle.frecuenciaId)))
          .getSingleOrNull();
      frecuenciaNombre = frecuencia?.nombre;
    }

    // Etapa 15: "corregible" = sigue siendo la captura original, sin
    // historia real todavía — mismo criterio que
    // `ServicioComercialRepositoryImpl.listarLineasEnFecha`.
    final esCorregible =
        vigenciasActivas.length == 1 && !(await tieneDocumentosGenerados(vigenciasActivas.single.id));

    return ConfiguracionCobroConVigencia(
      configuracion: configuracion,
      vigenciaActual: vigente,
      vigenciasProgramadas: programadas,
      correos: correos,
      etapas: etapas,
      esCorregible: esCorregible,
      entidadFiscalRazonSocial: entidadFiscalRazonSocial,
      frecuenciaNombre: frecuenciaNombre,
      clientePortalNombre: clientePortalNombre,
    );
  }

  @override
  Future<ConfiguracionCobroData?> obtenerConfiguracionPorId(String configuracionCobroId) {
    return (_db.select(_db.configuracionCobro)..where((t) => t.id.equals(configuracionCobroId))).getSingleOrNull();
  }

  @override
  Future<ConfiguracionCobroVigenciaData?> obtenerVigencia(String vigenciaId) {
    return (_db.select(_db.configuracionCobroVigencia)..where((t) => t.id.equals(vigenciaId))).getSingleOrNull();
  }

  @override
  Future<List<ConfiguracionCobroVigenciaData>> listarHistorial(String configuracionCobroId) {
    return (_db.select(_db.configuracionCobroVigencia)
          ..where((t) => t.configuracionCobroId.equals(configuracionCobroId))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaInicioVigencia)]))
        .get();
  }

  @override
  Future<List<String>> listarCorreos(String vigenciaId) async {
    final filas = await (_db.select(_db.configuracionCobroCorreo)
          ..where((t) => t.configuracionCobroVigenciaId.equals(vigenciaId)))
        .get();
    return [for (final f in filas) f.correo];
  }

  @override
  Future<List<ConfiguracionCobroEtapaData>> listarEtapas(String vigenciaId) {
    return (_db.select(_db.configuracionCobroEtapa)
          ..where((t) => t.configuracionCobroVigenciaId.equals(vigenciaId))
          ..orderBy([(t) => OrderingTerm.asc(t.orden)]))
        .get();
  }

  @override
  Future<ConfiguracionCobroVigenciaData> cambiarVigencia({
    required String configuracionCobroId,
    required ConfiguracionCobroValidada datos,
    required List<EtapaCobroValidada> etapas,
    String? observacion,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final existentes = await _vigenciasActivas(configuracionCobroId);
      final inicioNueva = soloFechaCobro(datos.fechaInicioVigencia);

      ConfiguracionCobroVigenciaData? predecesora;
      for (final v in existentes) {
        final inicio = soloFechaCobro(v.fechaInicioVigencia);
        final fin = v.fechaFinVigencia == null ? null : soloFechaCobro(v.fechaFinVigencia!);
        if (!inicio.isAfter(inicioNueva) && (fin == null || !fin.isBefore(inicioNueva))) {
          if (predecesora == null || inicio.isAfter(soloFechaCobro(predecesora.fechaInicioVigencia))) {
            predecesora = v;
          }
        }
      }

      if (predecesora != null) {
        await (_db.update(_db.configuracionCobroVigencia)..where((t) => t.id.equals(predecesora!.id))).write(
          ConfiguracionCobroVigenciaCompanion(
            fechaFinVigencia: Value(inicioNueva.subtract(const Duration(days: 1))),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }

      ConfiguracionCobroVigenciaData? sucesora;
      for (final v in existentes) {
        if (predecesora != null && v.id == predecesora.id) continue;
        final inicio = soloFechaCobro(v.fechaInicioVigencia);
        if (inicio.isAfter(inicioNueva)) {
          if (sucesora == null || inicio.isBefore(soloFechaCobro(sucesora.fechaInicioVigencia))) {
            sucesora = v;
          }
        }
      }

      // A diferencia de línea comercial, `ConfiguracionCobroBorrador`
      // nunca captura `fechaFinVigencia` a mano — siempre es derivada:
      // `null` si no hay sucesora, o un día antes de que la sucesora
      // empiece.
      final fechaFinNueva =
          sucesora == null ? null : soloFechaCobro(sucesora.fechaInicioVigencia).subtract(const Duration(days: 1));

      final nueva = await _db.into(_db.configuracionCobroVigencia).insertReturning(
            ConfiguracionCobroVigenciaCompanion.insert(
              configuracionCobroId: configuracionCobroId,
              tipoDocumento: datos.tipoDocumento.name,
              frecuenciaId: datos.frecuenciaId,
              diaInicioPeriodo: datos.diaInicioPeriodo,
              agrupacion: datos.agrupacion.name,
              metodo: datos.metodo.name,
              requiereComplemento: Value(datos.requiereComplemento),
              entidadFiscalId: Value(datos.entidadFiscalId),
              clientePortalId: Value(datos.clientePortalId),
              cuentaBancaria: Value(datos.cuentaBancaria),
              observaciones: Value(datos.observaciones),
              fechaInicioVigencia: datos.fechaInicioVigencia,
              fechaFinVigencia: Value(fechaFinNueva),
            ),
          );

      await _insertarCorreosYEtapas(vigenciaId: nueva.id, correos: datos.correos, etapas: etapas);

      // Abrir una vigencia NUEVA de cobro es un hecho de negocio: la
      // anterior queda histórica, intacta. Nunca se registra como
      // corrección.
      await registrarEventoConfiguracionCobro(
        _db,
        configuracionCobroId: configuracionCobroId,
        tipoEvento: TipoEventoConfiguracionCobro.vigenciaAbierta,
        observacion: observacion,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          if (predecesora != null) 'vigenciaAnteriorId': predecesora.id,
          ..._reglasDe(nueva),
          'etapas': await _resumenEtapas(nueva.id),
        },
      );

      return nueva;
    });
  }

  @override
  Future<ConfiguracionCobroVigenciaData> cerrarVigencia({
    required String vigenciaId,
    required DateTime fechaEfectiva,
    String? motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final antes =
          await (_db.select(_db.configuracionCobroVigencia)..where((t) => t.id.equals(vigenciaId))).getSingle();
      await (_db.update(_db.configuracionCobroVigencia)..where((t) => t.id.equals(vigenciaId))).write(
        ConfiguracionCobroVigenciaCompanion(
          fechaFinVigencia: Value(fechaEfectiva),
          updatedAt: Value(DateTime.now()),
        ),
      );
      final cerrada =
          await (_db.select(_db.configuracionCobroVigencia)..where((t) => t.id.equals(vigenciaId))).getSingle();

      final diff = DiffEvento()..anotar('fechaFinVigencia', antes.fechaFinVigencia, cerrada.fechaFinVigencia);
      await registrarEventoConfiguracionCobro(
        _db,
        configuracionCobroId: cerrada.configuracionCobroId,
        tipoEvento: TipoEventoConfiguracionCobro.cerrada,
        estadoAnterior: diff.estadoAnteriorJson,
        estadoNuevo: diff.estadoNuevoJson,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {'vigenciaId': vigenciaId},
      );
      return cerrada;
    });
  }

  @override
  Future<void> cancelarVigenciaProgramada(String vigenciaId, {String? motivo, String? actorUsuarioId}) {
    return _db.transaction(() async {
      final cancelada =
          await (_db.select(_db.configuracionCobroVigencia)..where((t) => t.id.equals(vigenciaId))).getSingle();
      final existentes = await _vigenciasActivas(cancelada.configuracionCobroId);
      final inicioCancelada = soloFechaCobro(cancelada.fechaInicioVigencia);

      ConfiguracionCobroVigenciaData? predecesora;
      for (final v in existentes) {
        if (v.id == cancelada.id) continue;
        final inicio = soloFechaCobro(v.fechaInicioVigencia);
        if (inicio.isBefore(inicioCancelada)) {
          if (predecesora == null || inicio.isAfter(soloFechaCobro(predecesora.fechaInicioVigencia))) {
            predecesora = v;
          }
        }
      }

      if (predecesora != null) {
        await (_db.update(_db.configuracionCobroVigencia)..where((t) => t.id.equals(predecesora!.id))).write(
          ConfiguracionCobroVigenciaCompanion(
            fechaFinVigencia: Value(cancelada.fechaFinVigencia),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }

      await (_db.update(_db.configuracionCobroVigencia)..where((t) => t.id.equals(vigenciaId))).write(
        ConfiguracionCobroVigenciaCompanion(
          cicloVidaRegistro: Value(CicloVidaRegistro.archivado.name),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // La vigencia cancelada NO se borra: queda archivada y sigue en
      // el historial. El evento deja claro cuál fue y qué reglas de
      // cobro se habían programado.
      await registrarEventoConfiguracionCobro(
        _db,
        configuracionCobroId: cancelada.configuracionCobroId,
        tipoEvento: TipoEventoConfiguracionCobro.vigenciaCancelada,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          if (predecesora != null) 'vigenciaRestauradaId': predecesora.id,
          ..._reglasDe(cancelada),
        },
      );
    });
  }

  @override
  Future<ConfiguracionCobroVigenciaData> actualizarObservaciones({
    required String vigenciaId,
    String? observaciones,
  }) async {
    await (_db.update(_db.configuracionCobroVigencia)..where((t) => t.id.equals(vigenciaId))).write(
      ConfiguracionCobroVigenciaCompanion(
        observaciones: Value(observaciones),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return (_db.select(_db.configuracionCobroVigencia)..where((t) => t.id.equals(vigenciaId))).getSingle();
  }

  @override
  Future<ConfiguracionCobroVigenciaData?> obtenerVigenciaEnFecha(String configuracionCobroId, DateTime fecha) async {
    final fechaSinHora = soloFechaCobro(fecha);
    final vigencias = await (_db.select(_db.configuracionCobroVigencia)
          ..where(
            (t) =>
                t.configuracionCobroId.equals(configuracionCobroId) &
                t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
          ))
        .get();

    for (final v in vigencias) {
      final inicio = soloFechaCobro(v.fechaInicioVigencia);
      final fin = v.fechaFinVigencia == null ? null : soloFechaCobro(v.fechaFinVigencia!);
      if (!inicio.isAfter(fechaSinHora) && (fin == null || !fin.isBefore(fechaSinHora))) {
        return v;
      }
    }
    return null;
  }

  @override
  Future<List<ConfiguracionCobroData>> listarConfiguraciones({String? clienteId, String? servicioId}) async {
    if (servicioId != null) {
      final fila =
          await (_db.select(_db.configuracionCobro)..where((t) => t.servicioId.equals(servicioId))).getSingleOrNull();
      return fila == null ? const [] : [fila];
    }

    if (clienteId != null) {
      final query = _db.select(_db.configuracionCobro).join([
        innerJoin(_db.servicio, _db.servicio.id.equalsExp(_db.configuracionCobro.servicioId)),
      ])
        ..where(_db.servicio.clienteId.equals(clienteId));
      final filas = await query.get();
      return [for (final f in filas) f.readTable(_db.configuracionCobro)];
    }

    return _db.select(_db.configuracionCobro).get();
  }

  @override
  Future<bool> tieneDocumentosGenerados(String vigenciaId) async {
    final documento = await (_db.select(_db.documentoPorEmitirConfiguracion)
          ..where((t) => t.configuracionCobroVigenciaId.equals(vigenciaId))
          ..limit(1))
        .getSingleOrNull();
    return documento != null;
  }

  @override
  Future<ConfiguracionCobroVigenciaData> corregirVigencia({
    required String vigenciaId,
    required ConfiguracionCobroValidada datos,
    required List<EtapaCobroValidada> etapas,
    String? motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final antesCorreccion =
          await (_db.select(_db.configuracionCobroVigencia)..where((t) => t.id.equals(vigenciaId))).getSingle();
      final etapasAntes = await _resumenEtapas(vigenciaId);
      await (_db.update(_db.configuracionCobroVigencia)..where((t) => t.id.equals(vigenciaId))).write(
        ConfiguracionCobroVigenciaCompanion(
          tipoDocumento: Value(datos.tipoDocumento.name),
          frecuenciaId: Value(datos.frecuenciaId),
          diaInicioPeriodo: Value(datos.diaInicioPeriodo),
          agrupacion: Value(datos.agrupacion.name),
          metodo: Value(datos.metodo.name),
          requiereComplemento: Value(datos.requiereComplemento),
          entidadFiscalId: Value(datos.entidadFiscalId),
          clientePortalId: Value(datos.clientePortalId),
          cuentaBancaria: Value(datos.cuentaBancaria),
          observaciones: Value(datos.observaciones),
          fechaInicioVigencia: Value(datos.fechaInicioVigencia),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // Correos y etapas se reemplazan por completo — no hay historia
      // que proteger todavía (garantizado por el caso de uso antes de
      // llegar aquí), así que no tiene sentido intentar conciliar filas
      // existentes una por una. `etapaReferenciaId` es una FK propia
      // (self-reference) con `onDelete: restrict` — borrar el lote
      // completo en una sola sentencia puede intentar borrar una etapa
      // todavía referenciada por otra fila del mismo lote (que también
      // se va a borrar, pero el motor no lo sabe todavía sin diferir el
      // chequeo); `PRAGMA defer_foreign_keys` pospone la validación de
      // FK al final de la transacción, sin cambiar el significado de
      // `restrict` para ningún otro caso (borrar una sola etapa
      // referenciada por otra que sobrevive sigue rechazándose).
      await _db.customStatement('PRAGMA defer_foreign_keys = ON');
      await (_db.delete(_db.configuracionCobroCorreo)..where((t) => t.configuracionCobroVigenciaId.equals(vigenciaId)))
          .go();
      await (_db.delete(_db.configuracionCobroEtapa)..where((t) => t.configuracionCobroVigenciaId.equals(vigenciaId)))
          .go();
      await _insertarCorreosYEtapas(vigenciaId: vigenciaId, correos: datos.correos, etapas: etapas);
      final despuesCorreccion =
          await (_db.select(_db.configuracionCobroVigencia)..where((t) => t.id.equals(vigenciaId))).getSingle();
      final etapasDespues = await _resumenEtapas(vigenciaId);

      // Corrección de una vigencia EXISTENTE. Las etapas se comparan
      // como conjunto: se reemplazan enteras, así que el diff campo a
      // campo no las describiría.
      final diff = _diffReglas(antesCorreccion, despuesCorreccion);
      final etapasCambiaron = jsonEncode(etapasAntes) != jsonEncode(etapasDespues);
      if (diff.hayCambios || etapasCambiaron) {
        await registrarEventoConfiguracionCobro(
          _db,
          configuracionCobroId: despuesCorreccion.configuracionCobroId,
          tipoEvento: TipoEventoConfiguracionCobro.corregida,
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          observacion: motivo,
          actorUsuarioId: actorUsuarioId,
          datosRelevantes: {
            'vigenciaId': vigenciaId,
            if (etapasCambiaron) 'etapasAntes': etapasAntes,
            if (etapasCambiaron) 'etapasDespues': etapasDespues,
          },
        );
      }
      return despuesCorreccion;
    });
  }
}
