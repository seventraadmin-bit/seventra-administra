import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/database/tables/direccion_table.dart';

import '../../domain/repositories/entidad_fiscal_repository.dart';
import '../../domain/shared/direccion_input.dart';

class EntidadFiscalRepositoryImpl implements EntidadFiscalRepository {
  EntidadFiscalRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<EntidadFiscalData> crear(EntidadFiscalCompanion datos) {
    return _db.into(_db.entidadFiscal).insertReturning(datos);
  }

  @override
  Future<EntidadFiscalData?> obtenerPorId(String id) {
    return (_db.select(_db.entidadFiscal)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<EntidadFiscalConDomicilio>> listarPorCliente(String clienteId) async {
    final entidades = await (_db.select(_db.entidadFiscal)..where((t) => t.clienteId.equals(clienteId))).get();

    final resultado = <EntidadFiscalConDomicilio>[];
    for (final entidad in entidades) {
      final domicilio = await obtenerDomicilioFiscal(entidad.id);
      resultado.add(EntidadFiscalConDomicilio(entidadFiscal: entidad, domicilioFiscal: domicilio));
    }
    return resultado;
  }

  @override
  Future<EntidadFiscalData> actualizar({required String id, required EntidadFiscalCompanion cambios}) async {
    await (_db.update(_db.entidadFiscal)..where((t) => t.id.equals(id))).write(
      cambios.copyWith(updatedAt: Value(DateTime.now())),
    );
    return (_db.select(_db.entidadFiscal)..where((t) => t.id.equals(id))).getSingle();
  }

  @override
  Future<EntidadFiscalData> cambiarCicloVida({required String id, required CicloVidaRegistro nuevo}) async {
    await (_db.update(_db.entidadFiscal)..where((t) => t.id.equals(id))).write(
      EntidadFiscalCompanion(cicloVidaRegistro: Value(nuevo.name), updatedAt: Value(DateTime.now())),
    );
    return (_db.select(_db.entidadFiscal)..where((t) => t.id.equals(id))).getSingle();
  }

  @override
  Future<bool> existeRfc(String rfcNormalizado, {String? excluirId}) async {
    var query = _db.select(_db.entidadFiscal)..where((t) => t.rfc.equals(rfcNormalizado));
    if (excluirId != null) {
      query = query..where((t) => t.id.equals(excluirId).not());
    }
    final fila = await query.getSingleOrNull();
    return fila != null;
  }

  @override
  Future<DireccionData?> obtenerDomicilioFiscal(String entidadFiscalId) {
    return (_db.select(_db.direccion)
          ..where(
            (t) =>
                t.entidadFiscalId.equals(entidadFiscalId) &
                t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
          ))
        .getSingleOrNull();
  }

  /// Busca el domicilio fiscal de esta Entidad fiscal sin importar
  /// `cicloVidaRegistro` — `entidadFiscalId` tiene un `.unique()` real
  /// en `Direccion` (1:1), así que solo puede existir una fila por
  /// Entidad fiscal en toda su historia (mismo patrón que
  /// `_buscarDireccionDeSucursal`).
  Future<DireccionData?> _buscarDomicilioDeEntidadFiscal(String entidadFiscalId) {
    return (_db.select(_db.direccion)..where((t) => t.entidadFiscalId.equals(entidadFiscalId))).getSingleOrNull();
  }

  @override
  Future<DireccionData?> guardarDomicilioFiscal(String entidadFiscalId, DireccionInput? input) async {
    final existente = await _buscarDomicilioDeEntidadFiscal(entidadFiscalId);

    if (input == null) {
      // Sección vacía: si había un domicilio activo, se archiva — nunca
      // se borra físicamente la fila.
      if (existente != null && existente.cicloVidaRegistro == CicloVidaRegistro.activo.name) {
        await (_db.update(_db.direccion)..where((t) => t.id.equals(existente.id))).write(
          DireccionCompanion(
            cicloVidaRegistro: Value(CicloVidaRegistro.archivado.name),
            updatedAt: Value(DateTime.now()),
          ),
        );
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

    if (existente != null) {
      // Reactiva (si venía archivado) y actualiza — nunca un segundo
      // `INSERT`, que chocaría con el `.unique()` de `entidadFiscalId`.
      final actualizada = existente.copyWithCompanion(cambios);
      await _db.update(_db.direccion).replace(actualizada);
      return actualizada;
    }

    return _db.into(_db.direccion).insertReturning(
          DireccionCompanion.insert(
            entidadFiscalId: Value(entidadFiscalId),
            tipoDireccion: TipoDireccion.fiscal.name,
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
}
