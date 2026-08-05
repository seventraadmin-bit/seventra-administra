import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

import '../../domain/repositories/servicio_comercial_repository.dart';
import '../../domain/usecases/linea_comercial_con_vigencia.dart';
import '../../domain/usecases/linea_comercial_validator.dart';

class ServicioComercialRepositoryImpl implements ServicioComercialRepository {
  ServicioComercialRepositoryImpl(this._db);

  final AppDatabase _db;

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
    final hoy = DateTime.now();

    final resultado = <LineaComercialConVigencia>[];
    for (final linea in lineas) {
      final vigenciasActivas = await (_db.select(_db.servicioLineaComercialVigencia)
            ..where(
              (t) =>
                  t.lineaComercialId.equals(linea.id) & t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
            ))
          .get();

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
}
