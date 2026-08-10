import 'package:riseg_one/core/database/app_database.dart';

/// Pagos de Nómina y su aplicación a renglones de `NominaEmpleado`
/// (Etapa 6D, mismo modelo N:M aprobado en 4J.2 para
/// `Pago`/`AplicacionPago`, trasplantado a este dominio) — `PagoNomina`
/// es un lote real de pago ("hoy salieron $X"), nunca ligado a un solo
/// renglón; `AplicacionPagoNomina` es cuánto de ese lote cubre a cada
/// renglón. `crear` compone también el `Egreso` automático en la misma
/// transacción (mismo criterio que `PagoRepositoryImpl` compone el
/// `Ingreso` automático de un `Pago`) y mantiene
/// `NominaEmpleado.estatusPago`/`Nomina.estatus` — ninguna validación
/// de negocio vive aquí (Nómina debe estar Cerrada, sobrepago, etc.
/// viven en los casos de uso), mismo criterio que el resto del
/// proyecto.
abstract interface class PagoNominaRepository {
  Future<PagoNominaData?> obtenerPorId(String id);

  Future<AplicacionPagoNominaData?> obtenerAplicacionPorId(String id);

  Future<List<PagoNominaData>> listarPorNomina(String nominaId);

  Future<List<AplicacionPagoNominaData>> listarAplicacionesPorPagoNomina(String pagoNominaId);

  Future<List<AplicacionPagoNominaData>> listarAplicacionesPorRenglon(String nominaEmpleadoId);

  Future<List<PagoNominaEventoData>> listarEventos(String pagoNominaId);

  /// Cuánto de `NominaEmpleado.totalAPagar` sigue sin cubrirse — se
  /// deriva sumando sus `AplicacionPagoNomina` activas, nunca se lee de
  /// una columna cacheada (ver el doc comment de `AplicacionPagoNomina`
  /// sobre por qué `NominaEmpleado` no gana un `saldoPendientePago`).
  Future<int> saldoPendientePago(String nominaEmpleadoId);

  /// Crea el `PagoNomina`, una `AplicacionPagoNomina` por cada entrada
  /// de [aplicaciones], el `Egreso` automático ligado (folio generado
  /// internamente, mismo criterio que el `Ingreso` automático de
  /// `PagoRepositoryImpl`), actualiza `estatusPago` de cada renglón
  /// tocado y evalúa si la Nómina completa pasa a `pagada` — todo en
  /// una sola transacción. El llamador (caso de uso) ya validó
  /// sobrepago, que la Nómina esté Cerrada y que cada renglón
  /// pertenezca a ella.
  Future<PagoNominaData> crear({
    required String folioPagoNomina,
    required String nominaId,
    required DateTime fechaPago,
    required String formaPago,
    String? referencia,
    String? cuentaBancariaOrigen,
    String? observaciones,
    required List<({String nominaEmpleadoId, int monto})> aplicaciones,
    String? actor,
  });

  /// Corrige metadatos administrativos del `PagoNomina` — nunca montos
  /// (mismo límite que `PagoRepository.corregir`: un monto incorrecto
  /// se cancela y se vuelve a registrar).
  Future<PagoNominaData> corregir({
    required String pagoNominaId,
    DateTime? fechaPago,
    String? formaPago,
    String? referencia,
    String? cuentaBancariaOrigen,
    String? observaciones,
    required String motivo,
    String? actor,
  });

  /// Cancela el `PagoNomina` completo: cancela en cascada todas sus
  /// `AplicacionPagoNomina` (revierte `estatusPago` de cada renglón
  /// afectado), cancela el `Egreso` ligado, y si la Nómina estaba
  /// `pagada` la regresa a `cerrada` — nunca bloquea la cancelación por
  /// tener aplicaciones activas (mismo criterio que `PagoRepository.cancelar`).
  Future<PagoNominaData> cancelar({
    required String pagoNominaId,
    required String motivo,
    String? actor,
  });

  Future<AttachmentData> adjuntarComprobante({
    required String pagoNominaId,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actor,
  });
}
