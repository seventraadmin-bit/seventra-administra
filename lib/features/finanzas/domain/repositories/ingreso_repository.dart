import 'package:riseg_one/core/database/app_database.dart';

/// Dinero reconocido como ingreso de RISEG (Etapa 4K.1) — automático
/// cuando proviene de un `Pago` (esa composición vive dentro de
/// `PagoRepositoryImpl`, no aquí — ver la nota de arquitectura en ese
/// archivo) o manual cuando no pasa por ninguna Cuenta por cobrar.
abstract interface class IngresoRepository {
  Future<IngresoData?> obtenerPorId(String id);

  Future<IngresoData?> obtenerPorPagoId(String pagoId);

  Future<List<IngresoData>> listar({
    String? estatus,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    DateTime? rangoInicio,
    DateTime? rangoFin,
  });

  Future<List<IngresoEventoData>> listarEventos(String ingresoId);

  /// Inserta el Ingreso y registra el evento `registrado`. El llamador
  /// ya generó `folioIngreso` (mismo criterio que `PagoRepository.crear`).
  Future<IngresoData> crear({
    String? pagoId,
    required String folioIngreso,
    required int monto,
    required DateTime fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    String? cuentaFinancieraId,
    required String formaPago,
    required String concepto,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Corrige metadatos administrativos de un Ingreso MANUAL — [monto]
  /// incluido (etapa "Ingresos y Egresos": antes solo `corregirMonto`,
  /// nunca expuesto a un caso de uso/UI real, podía tocarlo). Un
  /// Ingreso automático (`pagoId != null`) nunca llega aquí — el caso
  /// de uso (`CorregirIngresoUseCase`) lo bloquea antes. Un solo
  /// `IngresoEvento` `corregido` con `estadoAnterior`/`estadoNuevo`
  /// (`DiffEvento`) cubriendo TODOS los campos que realmente cambiaron,
  /// nunca un evento por campo.
  Future<IngresoData> corregir({
    required String ingresoId,
    int? monto,
    DateTime? fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    String? cuentaFinancieraId,
    bool limpiarCuentaFinancieraId = false,
    String? formaPago,
    String? concepto,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  });

  Future<IngresoData> cancelar({
    required String ingresoId,
    required String motivo,
    String? actorUsuarioId,
  });

  Future<AttachmentData> adjuntarComprobante({
    required String ingresoId,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actorUsuarioId,
  });

  /// Suma de `monto` de Ingresos `registrado` (nunca `cancelado`) en el
  /// rango dado — consulta base para reportes (Resolución 5 de
  /// Marlon), sin pantalla de reporte todavía.
  Future<int> totalIngresos({DateTime? rangoInicio, DateTime? rangoFin});

  /// Suma de `monto` de Ingresos `registrado` en el rango, agrupada por
  /// `categoriaFinancieraId` — Etapa 12A (Reportes). La llave `null`
  /// agrupa los Ingresos sin categoría asignada.
  Future<Map<String?, int>> totalPorCategoria({DateTime? rangoInicio, DateTime? rangoFin});
}
