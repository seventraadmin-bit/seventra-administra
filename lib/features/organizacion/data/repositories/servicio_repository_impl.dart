import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/direccion_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/ubicacion_table.dart';

import '../../domain/repositories/servicio_repository.dart';

class ServicioRepositoryImpl implements ServicioRepository {
  ServicioRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<ServicioData> crear({
    required String codigoServicio,
    required String clienteId,
    required String nombre,
    required String tipoServicioId,
    required String sucursalAdministrativaId,
    required DateTime fechaInicio,
    required String codigoUbicacionRaiz,
    required DireccionOperativaInput direccionOperativa,
    DateTime? fechaTermino,
    int elementosAutorizados = 0,
    String? responsableClienteContactoId,
    String? observaciones,
  }) {
    return _db.transaction(() async {
      final servicio = await _db.into(_db.servicio).insertReturning(
            ServicioCompanion.insert(
              codigo: codigoServicio,
              clienteId: clienteId,
              nombre: nombre,
              tipoServicioId: tipoServicioId,
              sucursalAdministrativaId: sucursalAdministrativaId,
              fechaInicio: fechaInicio,
              fechaTermino: Value(fechaTermino),
              elementosAutorizados: Value(elementosAutorizados),
              responsableClienteContactoId: Value(responsableClienteContactoId),
              observaciones: Value(observaciones),
            ),
          );

      await _db.into(_db.direccion).insert(
            DireccionCompanion.insert(
              servicioId: Value(servicio.id),
              tipoDireccion: TipoDireccion.operativa.name,
              calle: direccionOperativa.calle,
              numeroExterior: direccionOperativa.numeroExterior,
              numeroInterior: Value(direccionOperativa.numeroInterior),
              colonia: direccionOperativa.colonia,
              municipioAlcaldia: direccionOperativa.municipioAlcaldia,
              ciudadLocalidad: Value(direccionOperativa.ciudadLocalidad),
              estado: direccionOperativa.estado,
              codigoPostal: direccionOperativa.codigoPostal,
              pais: Value(direccionOperativa.pais),
              referencias: Value(direccionOperativa.referencias),
            ),
          );

      await _db.into(_db.ubicacion).insert(
            UbicacionCompanion.insert(
              codigo: codigoUbicacionRaiz,
              nombre: nombre,
              tipoUbicacion: TipoUbicacion.servicio.name,
              servicioId: Value(servicio.id),
            ),
          );

      return servicio;
    });
  }

  @override
  Future<ServicioData?> obtenerPorId(String id) {
    return (_db.select(_db.servicio)..where((t) => t.id.equals(id))).getSingleOrNull();
  }
}
