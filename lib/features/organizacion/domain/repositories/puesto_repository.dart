import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

import '../usecases/eliminar_puesto_fisicamente_usecase.dart';

/// Delgado a propósito: su única razón de ser es aplicar de forma
/// consistente el filtro por `cicloVidaRegistro` — no tiene reglas de
/// negocio propias comparables a las de Sucursal/Cliente/Servicio.
abstract interface class PuestoRepository {
  Future<PuestoData> crear(PuestoCompanion datos);

  Future<PuestoData> actualizar({required String id, required PuestoCompanion cambios});

  Future<PuestoData?> obtenerPorId(String id);

  Future<List<PuestoData>> listarActivos();

  /// Incluye los archivados. Un reporte histórico tiene que poder
  /// nombrar el puesto de alguien que ya no está, aunque ese puesto se
  /// haya archivado después. Sólo lectura.
  Future<List<PuestoData>> listarTodos();

  /// Operación mecánica — sin validar si el Área destino existe/está
  /// activa al reactivar; esa regla vive en
  /// `CambiarCicloVidaPuestoUseCase`.
  Future<PuestoData> cambiarCicloVida({required String id, required CicloVidaRegistro nuevo});

  /// Cuenta Puestos con `areaId` igual y `cicloVidaRegistro = activo` —
  /// usado por `DesactivarAreaUseCase` para bloquear la desactivación.
  /// Los Puestos archivados nunca cuentan.
  Future<int> contarActivosPorArea(String areaId);

  /// Eliminación física extraordinaria (Etapa 11D) — ver el doc comment
  /// de la implementación para las condiciones exactas.
  Future<EliminarPuestoFisicamenteResultado> eliminarFisicamente({
    required String puestoId,
    required String motivo,
    String? actorUsuarioId,
  });
}
