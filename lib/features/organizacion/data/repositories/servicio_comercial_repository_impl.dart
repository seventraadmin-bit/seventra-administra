import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/utils/clock.dart';

import '../../domain/repositories/servicio_comercial_repository.dart';
import '../../domain/usecases/linea_comercial_con_vigencia.dart';
import '../../domain/usecases/linea_comercial_validator.dart';

class ServicioComercialRepositoryImpl implements ServicioComercialRepository {
  ServicioComercialRepositoryImpl(this._db, {Clock clock = const SystemClock()}) : _clock = clock;

  final AppDatabase _db;
  final Clock _clock;

  @override
  Future<({ServicioLineaComercialData linea, ServicioLineaComercialVigenciaData vigencia})> crearLinea({
    required String servicioId,
    required LineaComercialValidada datos,
  }) {
    return _db.transaction(() async {
      final linea = await _db.into(_db.servicioLineaComercial).insertReturning(
            ServicioLineaComercialCompanion.insert(servicioId: servicioId),
          );

      final vigencia = await _db.into(_db.servicioLineaComercialVigencia).insertReturning(
            ServicioLineaComercialVigenciaCompanion.insert(
              lineaComercialId: linea.id,
              puestoId: datos.puestoId,
              modalidadTurnoId: datos.modalidadTurnoId,
              cantidadElementos: datos.cantidadElementos,
              precioUnitario: datos.precioUnitario,
              tratamientoIva: datos.tratamientoIva.name,
              descripcion: Value(datos.descripcion),
              fechaInicioVigencia: datos.fechaInicioVigencia,
              fechaFinVigencia: Value(datos.fechaFinVigencia),
              observaciones: Value(datos.observaciones),
            ),
          );

      return (linea: linea, vigencia: vigencia);
    });
  }

  @override
  Future<List<LineaComercialConVigencia>> listarLineas(String servicioId) async {
    final lineas = await (_db.select(_db.servicioLineaComercial)..where((t) => t.servicioId.equals(servicioId))).get();
    final hoy = _clock.now();

    final resultado = <LineaComercialConVigencia>[];
    for (final linea in lineas) {
      final vigenciasActivas = await _vigenciasActivasDeLinea(linea.id);

      final (:vigente, :programadas) = clasificarVigencias(vigenciasActivas, hoy);
      final vigenciaParaNombres = vigente ?? (programadas.isEmpty ? null : programadas.first);

      var puestoNombre = '';
      var modalidadTurnoNombre = '';
      if (vigenciaParaNombres != null) {
        final puesto = await (_db.select(_db.puesto)..where((t) => t.id.equals(vigenciaParaNombres.puestoId)))
            .getSingleOrNull();
        final modalidad = await (_db.select(_db.tipoModalidadTurno)
              ..where((t) => t.id.equals(vigenciaParaNombres.modalidadTurnoId)))
            .getSingleOrNull();
        puestoNombre = puesto?.nombre ?? '';
        modalidadTurnoNombre = modalidad?.nombre ?? '';
      }

      resultado.add(
        LineaComercialConVigencia(
          linea: linea,
          vigenciaActual: vigente,
          vigenciasProgramadas: programadas,
          puestoNombre: puestoNombre,
          modalidadTurnoNombre: modalidadTurnoNombre,
        ),
      );
    }

    return resultado;
  }

  @override
  Future<ServicioLineaComercialData?> obtenerLinea(String lineaComercialId) {
    return (_db.select(_db.servicioLineaComercial)..where((t) => t.id.equals(lineaComercialId))).getSingleOrNull();
  }

  @override
  Future<ServicioLineaComercialVigenciaData?> obtenerVigencia(String vigenciaId) {
    return (_db.select(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(vigenciaId))).getSingleOrNull();
  }

  @override
  Future<List<ServicioLineaComercialVigenciaData>> listarHistorial(String lineaComercialId) {
    return (_db.select(_db.servicioLineaComercialVigencia)
          ..where((t) => t.lineaComercialId.equals(lineaComercialId))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaInicioVigencia)]))
        .get();
  }

  Future<List<ServicioLineaComercialVigenciaData>> _vigenciasActivasDeLinea(String lineaComercialId) {
    return (_db.select(_db.servicioLineaComercialVigencia)
          ..where(
            (t) =>
                t.lineaComercialId.equals(lineaComercialId) & t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
          ))
        .get();
  }

  @override
  Future<ServicioLineaComercialVigenciaData> cambiarVigencia({
    required String lineaComercialId,
    required LineaComercialValidada datos,
  }) {
    return _db.transaction(() async {
      final existentes = await _vigenciasActivasDeLinea(lineaComercialId);
      final inicioNueva = soloFecha(datos.fechaInicioVigencia);

      // Predecesora: la vigencia `activo` cuyo rango contiene o antecede
      // a la nueva fecha de inicio — a lo más una, por la invariante de
      // no-solapamiento.
      ServicioLineaComercialVigenciaData? predecesora;
      for (final v in existentes) {
        final inicio = soloFecha(v.fechaInicioVigencia);
        final fin = v.fechaFinVigencia == null ? null : soloFecha(v.fechaFinVigencia!);
        if (!inicio.isAfter(inicioNueva) && (fin == null || !fin.isBefore(inicioNueva))) {
          if (predecesora == null || inicio.isAfter(soloFecha(predecesora.fechaInicioVigencia))) {
            predecesora = v;
          }
        }
      }

      if (predecesora != null) {
        await (_db.update(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(predecesora!.id))).write(
          ServicioLineaComercialVigenciaCompanion(
            fechaFinVigencia: Value(inicioNueva.subtract(const Duration(days: 1))),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }

      // Sucesora: entre las restantes, la de fecha de inicio más
      // próxima después de la nueva.
      ServicioLineaComercialVigenciaData? sucesora;
      for (final v in existentes) {
        if (predecesora != null && v.id == predecesora.id) continue;
        final inicio = soloFecha(v.fechaInicioVigencia);
        if (inicio.isAfter(inicioNueva)) {
          if (sucesora == null || inicio.isBefore(soloFecha(sucesora.fechaInicioVigencia))) {
            sucesora = v;
          }
        }
      }

      final fechaFinNueva =
          sucesora != null ? soloFecha(sucesora.fechaInicioVigencia).subtract(const Duration(days: 1)) : datos.fechaFinVigencia;

      return _db.into(_db.servicioLineaComercialVigencia).insertReturning(
            ServicioLineaComercialVigenciaCompanion.insert(
              lineaComercialId: lineaComercialId,
              puestoId: datos.puestoId,
              modalidadTurnoId: datos.modalidadTurnoId,
              cantidadElementos: datos.cantidadElementos,
              precioUnitario: datos.precioUnitario,
              tratamientoIva: datos.tratamientoIva.name,
              descripcion: Value(datos.descripcion),
              fechaInicioVigencia: datos.fechaInicioVigencia,
              fechaFinVigencia: Value(fechaFinNueva),
              observaciones: Value(datos.observaciones),
            ),
          );
    });
  }

  @override
  Future<ServicioLineaComercialVigenciaData> cerrarVigencia({
    required String vigenciaId,
    required DateTime fechaEfectiva,
  }) async {
    await (_db.update(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(vigenciaId))).write(
      ServicioLineaComercialVigenciaCompanion(
        fechaFinVigencia: Value(fechaEfectiva),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return (_db.select(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(vigenciaId))).getSingle();
  }

  @override
  Future<void> cancelarVigenciaProgramada(String vigenciaId) {
    return _db.transaction(() async {
      final cancelada =
          await (_db.select(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(vigenciaId))).getSingle();
      final existentes = await _vigenciasActivasDeLinea(cancelada.lineaComercialId);
      final inicioCancelada = soloFecha(cancelada.fechaInicioVigencia);

      ServicioLineaComercialVigenciaData? predecesora;
      for (final v in existentes) {
        if (v.id == cancelada.id) continue;
        final inicio = soloFecha(v.fechaInicioVigencia);
        if (inicio.isBefore(inicioCancelada)) {
          if (predecesora == null || inicio.isAfter(soloFecha(predecesora.fechaInicioVigencia))) {
            predecesora = v;
          }
        }
      }

      if (predecesora != null) {
        await (_db.update(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(predecesora!.id))).write(
          ServicioLineaComercialVigenciaCompanion(
            fechaFinVigencia: Value(cancelada.fechaFinVigencia),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }

      await (_db.update(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(vigenciaId))).write(
        ServicioLineaComercialVigenciaCompanion(
          cicloVidaRegistro: Value(CicloVidaRegistro.archivado.name),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  @override
  Future<ServicioLineaComercialVigenciaData> actualizarAnotaciones({
    required String vigenciaId,
    String? descripcion,
    String? observaciones,
  }) async {
    await (_db.update(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(vigenciaId))).write(
      ServicioLineaComercialVigenciaCompanion(
        descripcion: Value(descripcion),
        observaciones: Value(observaciones),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return (_db.select(_db.servicioLineaComercialVigencia)..where((t) => t.id.equals(vigenciaId))).getSingle();
  }
}
