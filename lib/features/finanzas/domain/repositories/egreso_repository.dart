import 'package:riseg_one/core/database/app_database.dart';

import '../fuente_egreso.dart';
import '../origen_financiero_gasto.dart';
import '../usecases/eliminar_egreso_fisicamente_usecase.dart';

/// Dinero pagado por RISEG (Etapa 4K.1) — captura manual, y desde las
/// Etapas 10/6D/"origen financiero unificado"/19B/"Cierre del ciclo
/// financiero de Descuentos Programados" también generado
/// automáticamente por `Compra` (`Compra.egresoId`), `PagoNomina`
/// (`PagoNomina.egresoId`), `TiempoExtra`/`TiempoExtraCostoAdicional`
/// (pago desde Cuenta financiera), un pago de `Deuda`
/// (`MovimientoDeuda.egresoId`, solo `tipo == pago`) y un desembolso de
/// `DescuentoProgramadoEmpleado` (`DescuentoProgramadoEmpleado.egresoId`
/// — típicamente un préstamo; una recuperación de concepto como botas
/// nunca genera Egreso) — todas `onDelete: restrict` — un Egreso de
/// cualquiera de esos orígenes nunca se elimina físicamente de forma
/// aislada (ver `eliminarFisicamente`) ni se corrige/cancela
/// directamente desde este repositorio (ver
/// `ObtenerOrigenAutomaticoEgresoUseCase`, `CorregirEgresoUseCase`,
/// `CancelarEgresoUseCase`).
abstract interface class EgresoRepository {
  Future<EgresoData?> obtenerPorId(String id);

  /// [soloSalidaDeEfectivo] (Etapa "Origen financiero de Egresos
  /// manuales") excluye los Egresos financiados con TDC
  /// (`deudaId != null`), que son gasto operativo pero NO salida de
  /// caja — su peso sale después, al pagar la tarjeta. `false` (default)
  /// devuelve todo, que es lo que la pantalla de Egresos necesita: un
  /// gasto pagado con tarjeta debe verse en el listado como cualquier
  /// otro. Pásalo en `true` únicamente donde la cifra representa flujo
  /// de efectivo real (serie financiera del Dashboard) o donde debe
  /// cuadrar con [totalEgresos] (`ClasificarEgresosPorOrigenUseCase`).
  Future<List<EgresoData>> listar({
    String? estatus,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    DateTime? rangoInicio,
    DateTime? rangoFin,
    bool soloSalidaDeEfectivo = false,
  });

  Future<List<EgresoEventoData>> listarEventos(String egresoId);

  Future<EgresoData> crear({
    required String folioEgreso,
    required int monto,
    required DateTime fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,

    /// Mutuamente excluyente con [deudaId] — pasar los dos lanza
    /// `StateError` (invariante verificada aquí, en el único punto de
    /// entrada de escritura, nunca vía `CHECK` de esquema).
    String? cuentaFinancieraId,

    /// **La verdad del efecto sobre las cuentas** (schemaVersion 91).
    /// Si se omite, la cuenta unica de [cuentaFinancieraId] se
    /// convierte en una sola fuente por el importe completo, de modo
    /// que TODO Egreso pagado desde cuenta queda representado igual y
    /// ningun origen tiene que enterarse. Si se da, debe sumar
    /// exactamente el importe del Egreso, sin cuentas repetidas y con
    /// todos los importes positivos; cada cuenta debe tener saldo
    /// suficiente al confirmar, validado dentro de la transaccion.
    List<FuenteEgreso>? fuentes,

    /// Etapa "Origen financiero de Egresos manuales" — la TDC que
    /// financió el gasto. Poblarlo NO genera aquí el `MovimientoDeuda`
    /// del cargo: esta es escritura cruda, el cargo lo registra el
    /// caso de uso (`RegistrarEgresoUseCase`) vía
    /// `DeudaRepository.registrarCargoEgreso` dentro de la MISMA
    /// transacción — mismo criterio de composición que ya usan Compra
    /// y TiempoExtra.
    String? deudaId,
    required String formaPago,
    String? beneficiario,
    required String concepto,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Corrige metadatos administrativos de un Egreso MANUAL — [monto]
  /// incluido (etapa "Ingresos y Egresos": antes solo `corregirMonto`,
  /// usado exclusivamente por `Compra`/`TiempoExtra` para sincronizar
  /// SU PROPIO Egreso automático, nunca expuesto a un caso de uso/UI
  /// para un Egreso manual). Un Egreso automático (Compra/PagoNomina/
  /// TiempoExtra/pago de Deuda) nunca llega aquí desde Finanzas — el
  /// caso de uso (`CorregirEgresoUseCase`) lo bloquea antes vía
  /// `ObtenerOrigenAutomaticoEgresoUseCase`; ese mismo bloqueo NO aplica
  /// a las llamadas internas que Compra/TiempoExtra hacen a
  /// [corregirMonto] sobre su propio Egreso (composición interna, nunca
  /// pasa por `CorregirEgresoUseCase`). Un solo `EgresoEvento`
  /// `corregido` con `estadoAnterior`/`estadoNuevo` (`DiffEvento`)
  /// cubriendo TODOS los campos que realmente cambiaron.
  Future<EgresoData> corregir({
    required String egresoId,
    int? monto,
    DateTime? fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    String? cuentaFinancieraId,
    List<FuenteEgreso>? fuentes,
    bool limpiarCuentaFinancieraId = false,

    /// Etapa "Origen financiero de Egresos manuales" — la invariante
    /// "cuenta XOR tarjeta" se evalúa sobre el estado RESULTANTE, no
    /// solo sobre los argumentos: una transición TDC → Cuenta debe
    /// pasar `limpiarDeudaId: true` junto con la cuenta nueva, y una
    /// Cuenta → TDC `limpiarCuentaFinancieraId: true` junto con
    /// [deudaId]. Igual que [crear], NO registra aquí el cargo/la
    /// reversión en la Deuda: eso lo orquesta `CorregirEgresoUseCase`
    /// en la misma transacción.
    String? deudaId,
    bool limpiarDeudaId = false,
    String? formaPago,
    String? beneficiario,
    String? concepto,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Etapa "Origen financiero de Egresos manuales: Cuenta vs. TDC" —
  /// alta de un gasto manual CON su origen financiero resuelto en una
  /// sola transacción: el `Egreso` y, si el origen es una TDC, el
  /// `MovimientoDeuda` del cargo. Es el punto de entrada de
  /// `RegistrarEgresoUseCase`; [crear] sigue siendo la escritura cruda
  /// que usan Compra/Nómina/TiempoExtra/pago de Deuda para SU propio
  /// Egreso automático (ninguno de ellos financiado con TDC por esta
  /// vía — cuando lo están, directamente no generan Egreso).
  ///
  /// Asume que el llamador ya validó la tarjeta con
  /// `validarOrigenTarjeta` (existe, activa, límite suficiente) — mismo
  /// criterio que `DeudaRepository.registrarCargoCompra`.
  Future<EgresoData> crearConOrigen({
    required String folioEgreso,
    required int monto,
    required DateTime fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    OrigenFinancieroGasto? origen,
    required String formaPago,
    String? beneficiario,
    required String concepto,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Corrección completa de un gasto manual —metadatos, monto y origen
  /// financiero— en UNA sola transacción, cubriendo las 6 transiciones
  /// reales: Cuenta→misma Cuenta, Cuenta→otra Cuenta, TDC→misma TDC,
  /// TDC→otra TDC, Cuenta→TDC y TDC→Cuenta (más "sin origen" en
  /// cualquiera de los dos extremos, que se comporta como el caso
  /// Cuenta sin cuenta asignada).
  ///
  /// El `Egreso` NUNCA se cancela ni se recrea al cambiar de origen: es
  /// el documento del gasto, conserva id, folio, historial y
  /// comprobantes. Esa es la diferencia real con la transición
  /// equivalente de `TiempoExtra`, donde el Egreso sí es desechable
  /// porque el documento del gasto es la fila `TiempoExtra`.
  ///
  /// [origen] `null` sin [limpiarOrigen] CONSERVA el origen actual —
  /// corregir solo el monto de un gasto con TDC ajusta su cargo
  /// (`ajustePositivo`/`ajusteNegativo` por la diferencia, nunca
  /// reescribiendo el cargo original) sin desvincular la tarjeta.
  /// [limpiarOrigen] lo deja explícitamente "sin especificar".
  ///
  /// Asume que el llamador (`CorregirEgresoUseCase`) ya validó crédito
  /// disponible contra `DeudaRepository.netoAportadoPorEgreso` cuando
  /// la tarjeta destino es la misma que ya financiaba el gasto.
  Future<EgresoData> corregirConOrigen({
    required String egresoId,
    int? monto,
    DateTime? fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    OrigenFinancieroGasto? origen,
    bool limpiarOrigen = false,
    String? formaPago,
    String? beneficiario,
    String? concepto,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Cancela un gasto manual revirtiendo el mecanismo que REALMENTE lo
  /// financió, en una sola transacción: siempre el `Egreso` (que deja
  /// de contar en Caja y bancos por su `estatus`), y además el cargo a
  /// la tarjeta cuando el gasto se financió con TDC (`ajusteNegativo`
  /// por el neto que aportaba, devolviendo crédito disponible sin
  /// tocar caja). Una segunda cancelación nunca duplica la reversión —
  /// el caso de uso corta antes por `estatus`, y el neto ya en cero
  /// hace que la reversión no escriba nada.
  Future<EgresoData> cancelarConOrigen({
    required String egresoId,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Corrige exclusivamente el `monto` de un Egreso ya existente,
  /// conservando folio/id — nunca cancela ni crea uno nuevo. Uso
  /// exclusivo de `Compra`/`TiempoExtra` para sincronizar SU PROPIO
  /// Egreso automático cuando el total del origen cambia (nunca
  /// alcanzable desde Finanzas — para un Egreso manual, usar [corregir]
  /// con `monto`, que además audita TODOS los campos cambiados en un
  /// solo evento).
  Future<EgresoData> corregirMonto({
    required String egresoId,
    required int nuevoMonto,
    required String motivo,
    String? actorUsuarioId,
  });

  Future<EgresoData> cancelar({
    required String egresoId,
    required String motivo,
    String? actorUsuarioId,
  });

  Future<AttachmentData> adjuntarComprobante({
    required String egresoId,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actorUsuarioId,
  });

  /// Suma de `monto` de Egresos `registrado` en el rango dado —
  /// consulta base para reportes (Resolución 5 de Marlon).
  ///
  /// Etapa "Origen financiero de Egresos manuales": EXCLUYE siempre los
  /// Egresos financiados con TDC (`deudaId != null`) — no es un filtro
  /// opcional porque esta cifra significa "salidas de efectivo"
  /// (`ObtenerFlujoEfectivoUseCase`) y alimenta
  /// `ResumenFinancieroState.egresosPeriodo`, de donde sale
  /// `egresosOperativos = egresosPeriodo - egresosDeuda +
  /// cargosTarjetaPeriodo`. Un gasto con TDC ya se reconoce como gasto
  /// por el término `cargosTarjetaPeriodo` (su `MovimientoDeuda` tipo
  /// `cargoCompra`); sumarlo también aquí sería doble conteo exacto del
  /// mismo peso, y además fingiría una salida de caja que todavía no
  /// ocurrió. Mismo tratamiento que ya recibían Compra/TiempoExtra con
  /// TDC, que directamente nunca generan Egreso.
  Future<int> totalEgresos({DateTime? rangoInicio, DateTime? rangoFin});

  /// Suma de `monto` de Egresos `registrado` en el rango, agrupada por
  /// `categoriaFinancieraId` — Etapa 12A (Reportes). La llave `null`
  /// agrupa los Egresos sin categoría asignada.
  Future<Map<String?, int>> totalPorCategoria({DateTime? rangoInicio, DateTime? rangoFin});

  /// Resumen de solo lectura para el mensaje de confirmación dinámico
  /// de la UI antes de pedir el motivo — ver el doc comment de
  /// `ResumenEliminacionEgreso`.
  Future<ResumenEliminacionEgreso> obtenerResumenEliminacionFisica(String egresoId);

  /// Eliminación física extraordinaria (Etapa 15, Usuario Maestro) —
  /// ver el doc comment de la implementación para las condiciones
  /// exactas de elegibilidad.
  Future<EliminarEgresoFisicamenteResultado> eliminarFisicamente({
    required String egresoId,
    required String motivo,
    String? actorUsuarioId,
  });
}
