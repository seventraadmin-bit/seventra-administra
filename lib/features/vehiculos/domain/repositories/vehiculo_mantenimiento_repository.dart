import 'package:riseg_one/core/database/app_database.dart';

/// Mantenimiento e incidencias de un Vehículo (Etapa 8D) — ver el doc
/// comment de `VehiculoMantenimiento` para el criterio de diseño
/// completo (una sola tabla para ambos conceptos).
abstract interface class VehiculoMantenimientoRepository {
  Future<VehiculoMantenimientoData?> obtenerPorId(String vehiculoMantenimientoId);

  /// El mantenimiento dueño de un `Egreso` automático (schemaVersion
  /// 80) — FK real (`egresoId`), nunca una heurística por concepto.
  /// Sostiene el bloqueo de corrección/cancelación desde Finanzas y la
  /// navegación "Ver origen".
  Future<VehiculoMantenimientoData?> obtenerPorEgresoId(String egresoId);

  /// Todos los `egresoId` generados por mantenimientos — insumo en lote
  /// de `ClasificarEgresosPorOrigenUseCase`, sin N+1.
  Future<List<String>> listarEgresoIds();

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
  /// [cuentaFinancieraId]/[deudaIdTarjeta] son el origen financiero
  /// (schemaVersion 80), mutuamente excluyentes y sólo con [costo] > 0:
  ///  - cuenta → crea el `Egreso` y guarda su `egresoId`;
  ///  - tarjeta → registra un `cargoCompra` en la TDC y guarda
  ///    `deudaId`, **sin** crear ningún Egreso.
  /// Ambos nulos con costo se permite únicamente para no romper el
  /// legacy; el caso de uso lo rechaza en capturas nuevas.
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
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
    String? actorUsuarioId,
  });

  /// Corrige un mantenimiento, incluida cualquier transición de origen
  /// financiero (schemaVersion 80): cuenta→misma cuenta, cuenta→otra
  /// cuenta, cuenta→TDC, TDC→cuenta, TDC→misma TDC, TDC→otra TDC, con o
  /// sin cambio de monto. Todo en UNA transacción — nunca queda un
  /// Egreso huérfano ni un cargo de tarjeta sin revertir.
  ///
  /// El llamador ya validó la tarjeta destino con `validarOrigenTarjeta`
  /// y que el motivo no esté vacío.
  Future<VehiculoMantenimientoData> corregir({
    required String vehiculoMantenimientoId,
    DateTime? fecha,
    String? tipo,
    String? descripcion,
    String? tallerProveedor,
    int? costo,
    bool limpiarCosto = false,
    DateTime? proximoMantenimientoFecha,
    int? proximoMantenimientoKilometraje,
    String? observaciones,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Anula el registro sin borrarlo y revierte EXACTAMENTE su efecto
  /// financiero: cancela el `Egreso`, o revierte el cargo de la TDC.
  /// Una segunda anulación nunca produce una segunda reversión.
  Future<VehiculoMantenimientoData> cancelar({
    required String vehiculoMantenimientoId,
    required String motivo,
    String? actorUsuarioId,
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
