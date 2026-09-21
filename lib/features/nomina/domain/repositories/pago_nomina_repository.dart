import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/domain/fuente_egreso.dart';

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

  /// Resuelve el `PagoNomina` que generó un `Egreso` puntual (vía
  /// `PagoNomina.egresoId`, la única FK real) — `null` si ese Egreso no
  /// vino de ningún Pago de Nómina. Usado por el bloqueo de corrección/
  /// cancelación directa de Egreso (Etapa "Ingresos y Egresos") y por
  /// la navegación "Ver origen" desde su expediente.
  Future<PagoNominaData?> obtenerPorEgresoId(String egresoId);

  Future<AplicacionPagoNominaData?> obtenerAplicacionPorId(String id);

  Future<List<PagoNominaData>> listarPorNomina(String nominaId);

  /// Todos los `PagoNomina` `registrado` (nunca `cancelado`) cuya
  /// `fechaPago` cae en el rango — Etapa 12A (Reportes), mismo criterio
  /// de exclusión que `EgresoRepository.listar`/`totalEgresos`. Cruza
  /// Nóminas distintas, a diferencia de `listarPorNomina`.
  Future<List<PagoNominaData>> listarEnRango({DateTime? rangoInicio, DateTime? rangoFin});

  Future<List<AplicacionPagoNominaData>> listarAplicacionesPorPagoNomina(String pagoNominaId);

  Future<List<AplicacionPagoNominaData>> listarAplicacionesPorRenglon(String nominaEmpleadoId);

  Future<List<PagoNominaEventoData>> listarEventos(String pagoNominaId);

  /// Cuánto de `NominaEmpleado.totalAPagar` sigue sin cubrirse — se
  /// deriva sumando sus `AplicacionPagoNomina` activas, nunca se lee de
  /// una columna cacheada (ver el doc comment de `AplicacionPagoNomina`
  /// sobre por qué `NominaEmpleado` no gana un `saldoPendientePago`).
  Future<int> saldoPendientePago(String nominaEmpleadoId);

  /// Versión en lote de [saldoPendientePago] — Etapa 12B (Reportes):
  /// una sola consulta `selectOnly`+`groupBy` sobre varios renglones a
  /// la vez, evitando N+1 al calcular el saldo pendiente de un
  /// conjunto grande de renglones. El llamador resta cada resultado de
  /// `totalAPagar` (no se hace aquí porque este repositorio no conoce
  /// `NominaEmpleado.totalAPagar` de cada renglón — eso ya lo tiene
  /// quien llama). Los renglones sin ninguna aplicación no aparecen en
  /// el mapa (equivalen a `0` aplicado).
  Future<Map<String, int>> totalAplicadoPorRenglon(List<String> nominaEmpleadoIds);

  /// Suma de `montoTotal` de `PagoNomina` `registrado` (nunca
  /// `cancelado`) cuya `fechaPago` cae en el rango — Etapa 12A
  /// (Reportes), mismo patrón que `EgresoRepository.totalEgresos`.
  /// Indicador informativo: ya está contenido dentro de
  /// `EgresoRepository.totalEgresos` vía `PagoNomina.egresoId`, nunca se
  /// suma de nuevo a un Resultado operativo.
  Future<int> totalPagadoEnRango({DateTime? rangoInicio, DateTime? rangoFin});

  /// Recalcula `NominaEmpleado.estatusPago` a partir de su saldo
  /// pendiente actual, sin crear ninguna `AplicacionPagoNomina` — para
  /// cuando `totalAPagar` cambia (regenerar/editar un renglón) fuera de
  /// un pago real. Necesario porque un renglón cuyo `totalAPagar`
  /// recalculado da `0` nunca pasa por [crear] (no hay nada que pagar),
  /// así que su `estatusPago` se quedaría atorado en el default
  /// `pendiente` para siempre. No hace nada si el estatus no cambió —
  /// devuelve `false`, sin ninguna escritura (idempotente: puede
  /// llamarse cualquier número de veces sobre el mismo renglón sin
  /// efecto adicional después de la primera). Si cambia (devuelve
  /// `true`), aplica exactamente el mismo efecto secundario sobre
  /// `Nomina.estatus` y sobre `DescuentoProgramadoCuota` (`reservada`
  /// ⇄ `aplicada`) que [crear]/[cancelar] — mismo criterio, un único
  /// punto de cruce. Usado también por
  /// `ReconciliarEstatusPagoNominaUseCase` (Etapa 15, reparación de
  /// datos históricos anteriores a este método) para reconciliar
  /// renglones ya existentes sin duplicar esta fórmula.
  Future<bool> sincronizarEstatusPago({required String nominaEmpleadoId, String? actorUsuarioId});

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
    String? cuentaFinancieraId,
    /// Reparto explícito entre varias cuentas para el Egreso del pago:
    /// un solo PagoNomina y un solo Egreso, repartido entre N cuentas.
    List<FuenteEgreso>? fuentes,
    String? observaciones,
    required List<({String nominaEmpleadoId, int monto})> aplicaciones,
    String? actorUsuarioId,
  });

  /// Corrige metadatos administrativos del `PagoNomina` — nunca montos
  /// (mismo límite que `PagoRepository.corregir`: un monto incorrecto
  /// se cancela y se vuelve a registrar).
  /// Etapa 4 (hallazgo real de auditoría): si el `Egreso` vinculado
  /// existe, propaga [fechaPago]/[formaPago]/[cuentaBancariaOrigen]/
  /// [cuentaFinancieraId] a él en la MISMA transacción — antes, esta
  /// corrección nunca tocaba el `Egreso`, dejándolo divergente para
  /// siempre. [cuentaFinancieraId] es la única forma de corregir la
  /// Cuenta financiera de un pago ya registrado (antes, imposible).
  /// `montoTotal`/empleados NUNCA son editables aquí — mismo criterio
  /// que `CorregirEgresoUseCase`/`CorregirCompraUseCase`: un monto mal
  /// capturado se cancela y se vuelve a registrar, nunca se edita.
  Future<PagoNominaData> corregir({
    required String pagoNominaId,
    DateTime? fechaPago,
    String? formaPago,
    String? referencia,
    String? cuentaBancariaOrigen,
    String? cuentaFinancieraId,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Cancela el `PagoNomina` completo: cancela en cascada todas sus
  /// `AplicacionPagoNomina` (revierte `estatusPago` de cada renglón
  /// afectado), cancela el `Egreso` ligado, y si la Nómina estaba
  /// `pagada` la regresa a `cerrada` — nunca bloquea la cancelación por
  /// tener aplicaciones activas (mismo criterio que `PagoRepository.cancelar`).
  Future<PagoNominaData> cancelar({
    required String pagoNominaId,
    required String motivo,
    String? actorUsuarioId,
  });

  Future<AttachmentData> adjuntarComprobante({
    required String pagoNominaId,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actorUsuarioId,
  });
}
