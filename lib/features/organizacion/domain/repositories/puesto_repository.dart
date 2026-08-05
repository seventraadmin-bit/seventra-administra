import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

/// Delgado a propósito: su única razón de ser es aplicar de forma
/// consistente el filtro por `cicloVidaRegistro` — no tiene reglas de
/// negocio propias comparables a las de Sucursal/Cliente/Servicio.
abstract interface class PuestoRepository {
  Future<PuestoData> crear(PuestoCompanion datos);

  Future<PuestoData> actualizar({required String id, required PuestoCompanion cambios});

  Future<PuestoData?> obtenerPorId(String id);

  Future<List<PuestoData>> listarActivos();

  /// Operación mecánica — sin validar si el Área destino existe/está
  /// activa al reactivar; esa regla vive en
  /// `CambiarCicloVidaPuestoUseCase`.
  Future<PuestoData> cambiarCicloVida({required String id, required CicloVidaRegistro nuevo});

  /// Cuenta Puestos con `areaId` igual y `cicloVidaRegistro = activo` —
  /// usado por `DesactivarAreaUseCase` para bloquear la desactivación.
  /// Los Puestos archivados nunca cuentan.
  Future<int> contarActivosPorArea(String areaId);
}
