import 'package:riseg_one/core/database/app_database.dart';

/// Ledger de kilometraje de un Vehículo (Etapa 8B) — ver el doc comment
/// de `VehiculoKilometraje` para el criterio de diseño completo.
abstract interface class VehiculoKilometrajeRepository {
  /// El "kilometraje actual" — la fila con `fecha` más reciente (empate
  /// resuelto por `createdAt` más reciente). `null` si el Vehículo
  /// nunca ha tenido una lectura.
  Future<VehiculoKilometrajeData?> obtenerActual(String vehiculoId);

  /// Historial completo, orden descendente por `fecha`.
  Future<List<VehiculoKilometrajeData>> listarPorVehiculo(String vehiculoId);

  /// Escritura cruda — sin la validación de "nunca disminuye salvo
  /// corrección explícita" (vive en `RegistrarKilometrajeVehiculoUseCase`).
  /// El kilometraje opcional de entrega/devolución (Etapa 8B, punto 10)
  /// **no** pasa por aquí — `AsignacionVehiculoRepositoryImpl` escribe
  /// directo `_db.vehiculoKilometraje` dentro de su propia transacción,
  /// mismo criterio que ya usa para `Vehiculo.estatus` (misma tabla de
  /// dominio, sin inyectar este repositorio solo para un insert).
  Future<VehiculoKilometrajeData> registrar({
    required String vehiculoId,
    required DateTime fecha,
    required int kilometraje,
    required String origen,
    String? observaciones,
    String? actor,
  });
}
