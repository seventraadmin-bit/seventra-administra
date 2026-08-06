import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/utils/clock.dart';

import '../../domain/repositories/configuracion_cobro_repository.dart';
import '../../domain/usecases/configuracion_cobro_con_vigencia.dart';
import '../../domain/usecases/configuracion_cobro_regla_evento_validator.dart';
import '../../domain/usecases/configuracion_cobro_validator.dart';

class ConfiguracionCobroRepositoryImpl implements ConfiguracionCobroRepository {
  ConfiguracionCobroRepositoryImpl(this._db, {Clock clock = const SystemClock()}) : _clock = clock;

  final AppDatabase _db;
  final Clock _clock;

  Future<void> _insertarCorreosYReglas({
    required String vigenciaId,
    required List<String> correos,
    required List<ReglaEventoValidada> reglas,
  }) async {
    for (final correo in correos) {
      await _db.into(_db.configuracionCobroCorreo).insert(
            ConfiguracionCobroCorreoCompanion.insert(configuracionCobroVigenciaId: vigenciaId, correo: correo),
          );
    }
    for (final regla in reglas) {
      await _db.into(_db.configuracionCobroReglaEvento).insert(
            ConfiguracionCobroReglaEventoCompanion.insert(
              configuracionCobroVigenciaId: vigenciaId,
              tipoEvento: regla.tipoEvento.name,
              tipoRegla: regla.tipoRegla.name,
              mesRelativo: Value(regla.mesRelativo?.name),
              diaDelMes: Value(regla.diaDelMes),
              ordinalSemana: Value(regla.ordinalSemana?.name),
              diaSemana: Value(regla.diaSemana?.name),
              offsetDiasHabiles: Value(regla.offsetDiasHabiles),
              eventoReferencia: Value(regla.eventoReferencia?.name),
            ),
          );
    }
  }

  @override
  Future<({ConfiguracionCobroData configuracion, ConfiguracionCobroVigenciaData vigencia})> crearConfiguracion({
    required String servicioId,
    required ConfiguracionCobroValidada datos,
    required List<ReglaEventoValidada> reglas,
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
              portalNombre: Value(datos.portalNombre),
              portalUrl: Value(datos.portalUrl),
              portalUsuario: Value(datos.portalUsuario),
              portalContrasena: Value(datos.portalContrasena),
              portalObservaciones: Value(datos.portalObservaciones),
              cuentaBancaria: Value(datos.cuentaBancaria),
              observaciones: Value(datos.observaciones),
              fechaInicioVigencia: datos.fechaInicioVigencia,
            ),
          );

      await _insertarCorreosYReglas(vigenciaId: vigencia.id, correos: datos.correos, reglas: reglas);

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
    var reglasEventos = const <ConfiguracionCobroReglaEventoData>[];
    String? entidadFiscalRazonSocial;
    String? frecuenciaNombre;
    if (vigenciaParaDetalle != null) {
      correos = await listarCorreos(vigenciaParaDetalle.id);
      reglasEventos = await listarReglas(vigenciaParaDetalle.id);

      final entidadFiscalId = vigenciaParaDetalle.entidadFiscalId;
      if (entidadFiscalId != null) {
        final entidad =
            await (_db.select(_db.entidadFiscal)..where((t) => t.id.equals(entidadFiscalId))).getSingleOrNull();
        entidadFiscalRazonSocial = entidad?.razonSocial;
      }

      final frecuencia = await (_db.select(_db.tipoFrecuenciaCobro)
            ..where((t) => t.id.equals(vigenciaParaDetalle.frecuenciaId)))
          .getSingleOrNull();
      frecuenciaNombre = frecuencia?.nombre;
    }

    return ConfiguracionCobroConVigencia(
      configuracion: configuracion,
      vigenciaActual: vigente,
      vigenciasProgramadas: programadas,
      correos: correos,
      reglasEventos: reglasEventos,
      entidadFiscalRazonSocial: entidadFiscalRazonSocial,
      frecuenciaNombre: frecuenciaNombre,
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
  Future<List<ConfiguracionCobroReglaEventoData>> listarReglas(String vigenciaId) {
    return (_db.select(_db.configuracionCobroReglaEvento)
          ..where((t) => t.configuracionCobroVigenciaId.equals(vigenciaId)))
        .get();
  }

  @override
  Future<ConfiguracionCobroVigenciaData> cambiarVigencia({
    required String configuracionCobroId,
    required ConfiguracionCobroValidada datos,
    required List<ReglaEventoValidada> reglas,
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
              portalNombre: Value(datos.portalNombre),
              portalUrl: Value(datos.portalUrl),
              portalUsuario: Value(datos.portalUsuario),
              portalContrasena: Value(datos.portalContrasena),
              portalObservaciones: Value(datos.portalObservaciones),
              cuentaBancaria: Value(datos.cuentaBancaria),
              observaciones: Value(datos.observaciones),
              fechaInicioVigencia: datos.fechaInicioVigencia,
              fechaFinVigencia: Value(fechaFinNueva),
            ),
          );

      await _insertarCorreosYReglas(vigenciaId: nueva.id, correos: datos.correos, reglas: reglas);

      return nueva;
    });
  }

  @override
  Future<ConfiguracionCobroVigenciaData> cerrarVigencia({
    required String vigenciaId,
    required DateTime fechaEfectiva,
  }) async {
    await (_db.update(_db.configuracionCobroVigencia)..where((t) => t.id.equals(vigenciaId))).write(
      ConfiguracionCobroVigenciaCompanion(
        fechaFinVigencia: Value(fechaEfectiva),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return (_db.select(_db.configuracionCobroVigencia)..where((t) => t.id.equals(vigenciaId))).getSingle();
  }

  @override
  Future<void> cancelarVigenciaProgramada(String vigenciaId) {
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
}
