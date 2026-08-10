import 'package:riseg_one/core/database/app_database.dart';

/// Mantenimiento e incidencias de un Vehículo (Etapa 8D) — ver el doc
/// comment de `VehiculoMantenimiento` para el criterio de diseño
/// completo (una sola tabla para ambos conceptos).
abstract interface class VehiculoMantenimientoRepository {
  Future<VehiculoMantenimientoData?> obtenerPorId(String vehiculoMantenimientoId);

  /// Historial completo de este Vehículo, orden descendente por `fecha`
  /// (empate resuelto por `createdAt` más reciente) — el llamador filtra
  /// por `tipo.esIncidencia` en memoria para el toggle
  /// Todos/Mantenimiento/Incidencias (punto 9: "un solo historial con
  /// filtros", nunca dos consultas separadas).
  Future<List<VehiculoMantenimientoData>> listarPorVehiculo(String vehiculoId);

  /// Todos los registros de todos los Vehículos, sin acotar — misma
  /// consulta masiva de una sola vez que usa `ReportesController`
  /// (Inventario 7D) y `VehiculoDocumentoRepository.listarTodos` (8C)
  /// para evitar N+1: la pantalla de Alertas deriva el resumen operativo
  /// (punto 10) agrupando en memoria.
  Future<List<VehiculoMantenimientoData>> listarTodos();

  /// Escritura cruda — sin validaciones de negocio (descripción no
  /// vacía, fechas/kilometrajes coherentes, no-decremento); esas viven
  /// en `RegistrarMantenimientoVehiculoUseCase`. Si [kilometraje] no es
  /// nulo, inserta también una fila en `VehiculoKilometraje` (origen
  /// `mantenimiento`) en la misma transacción — nunca una fuente
  /// paralela (punto 4).
  Future<VehiculoMantenimientoData> crear({
    required String vehiculoId,
    required DateTime fecha,
    int? kilometraje,
    required String tipo,
    required String descripcion,
    String? tallerProveedor,
    int? costo,
    DateTime? proximoMantenimientoFecha,
    int? proximoMantenimientoKilometraje,
    String? observaciones,
  });

  /// Adjunta un comprobante — inserta `Attachment` +
  /// `VehiculoMantenimientoAttachment`, una transacción. Permite varios
  /// adjuntos por registro (ver el doc comment de
  /// `VehiculoMantenimientoAttachment`).
  Future<AttachmentData> adjuntarArchivo({
    required String vehiculoMantenimientoId,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
  });
}
