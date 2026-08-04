import 'package:riseg_one/core/database/app_database.dart';

/// Delgado a propósito: su única razón de ser es aplicar de forma
/// consistente el filtro por `cicloVidaRegistro` — no tiene reglas de
/// negocio propias comparables a las de Sucursal/Cliente/Servicio.
abstract interface class PuestoRepository {
  Future<PuestoData> crear(PuestoCompanion datos);

  Future<PuestoData?> obtenerPorId(String id);

  Future<List<PuestoData>> listarActivos();
}
