import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../compras/data/tables/compra_table.dart';
import '../../../tiempos_extra/data/tables/tiempo_extra_table.dart';
import '../../../usuarios/data/tables/usuario_table.dart';
import '../../../servicios_eventuales/data/tables/servicio_eventual_table.dart';
import '../../../telefonia/data/tables/recarga_linea_telefonica_table.dart';
import '../../../vehiculos/data/tables/vehiculo_mantenimiento_table.dart';
import 'egreso_table.dart';

enum TipoDeuda { tarjetaCredito, prestamo, financiamiento, otro }

enum EstatusDeuda { activa, liquidada, cancelada }

/// Periodicidad informativa de un pago programado — sin ninguna regla
/// de negocio todavía (nada la lee para generar recordatorios), mismo
/// criterio que `CategoriaFinanciera.tipoMovimiento`.
enum PeriodicidadDeuda { mensual, quincenal, semanal, anual }

/// Regla explícita para calcular la próxima fecha límite de pago de una
/// tarjeta de crédito (nunca texto libre) — `diaFijo` usa
/// `tarjetaDiaPago` directo (día del mes); `diasDespuesDeCorte` cuenta
/// días naturales a partir de `tarjetaDiaCorte`. Ver
/// `proximaFechaLimitePago` en `calcular_fecha_tarjeta_usecase.dart`.
enum ReglaFechaLimitePagoTarjeta { diaFijo, diasDespuesDeCorte }

/// Estructura de la tasa ordinaria de una tarjeta de crédito (nunca
/// texto libre) — `fija` reutiliza `Deuda.tasaInteres` tal cual
/// (mismo campo que ya usa una deuda fija); `variable` se conserva
/// como referencia + diferencial + tratamiento de IVA, NUNCA
/// colapsada a un solo porcentaje falso. RISEG ONE nunca calcula una
/// tasa vigente a partir del índice — solo registra la condición
/// contractual tal como aparece en la carátula.
enum TipoTasaTarjeta { fija, variable }

/// Una obligación financiera de la empresa (Etapa 19: tarjeta de
/// crédito, préstamo, financiamiento u otro adeudo) — identidad propia
/// con saldo, nunca una `CategoriaFinanciera` más (esa tabla es
/// deliberadamente una etiqueta opcional sin reglas de negocio, ver su
/// doc comment). `saldoActual` nunca se edita directo desde la UI: solo
/// cambia a través de un `MovimientoDeuda` (alta/pago/cancelación),
/// igual que `DescuentoProgramadoEmpleado.saldoPendiente`.
///
/// `importeOriginal`/`saldoActual` representan "lo que se debía al
/// incorporar la Deuda a RISEG ONE" — para una deuda nueva coinciden;
/// para una ya existente (Parte 11 del pedido), `saldoActual` inicial
/// puede ser menor, capturado en el mismo alta sin generar Egreso.
///
/// Etapa 19B: el vínculo determinista hacia `Compra` vive en
/// `MovimientoDeuda.compraId` (no aquí) — una Deuda de tipo tarjeta
/// puede tener muchos cargos de muchas Compras distintas, así que la FK
/// pertenece al lado "muchos" del historial, nunca a la Deuda misma.
///
/// Campos de tarjeta (`tarjetaXxx`) son planos y nullable, solo tienen
/// sentido cuando `tipo == tarjetaCredito` — mismo criterio que otras
/// tablas del proyecto con campos condicionales por tipo, nunca una
/// tabla de extensión 1:1 para un puñado de columnas.
///
/// `importeOriginal`/`fechaOrigen` son nullable (schemaVersion 66,
/// ajuste "tarjeta como línea revolvente"): una TDC no tiene un
/// "importe original" real (es una línea de crédito, no un préstamo
/// con monto fijo) y su fecha de apertura real puede no conocerse al
/// incorporarla a RISEG ONE — ambos siguen siendo obligatorios para
/// `tipo != tarjetaCredito` (validado en `RegistrarDeudaUseCase`, nunca
/// aquí). `fechaSaldoInicial` es la fecha real a la que corresponde el
/// `saldoActual` capturado al alta — distinta de `fechaOrigen` (cuándo
/// se abrió la obligación) exactamente por el caso real de una tarjeta
/// que ya existía años antes de incorporarse a RISEG ONE.
class Deuda extends Table with AuditColumns {
  TextColumn get folio => text().unique()();

  TextColumn get nombre => text()();

  TextColumn get tipo => text()();

  /// Institución/persona acreedora — texto libre, sin catálogo (mismo
  /// criterio que `Egreso.beneficiario`/`Compra.proveedor`).
  TextColumn get acreedor => text().nullable()();

  DateTimeColumn get fechaOrigen => dateTime().nullable()();

  IntColumn get importeOriginal => integer().nullable()();

  IntColumn get saldoActual => integer()();

  /// Fecha real a la que corresponde `saldoActual` al momento del alta
  /// (Etapa "tarjeta revolvente") — puebla `MovimientoDeuda.altaInicial.
  /// fecha`. Nunca editable después de creada (mismo criterio que
  /// `importeOriginal`/`saldoActual`).
  DateTimeColumn get fechaSaldoInicial => dateTime().nullable()();

  DateTimeColumn get fechaVencimiento => dateTime().nullable()();

  IntColumn get pagoProgramado => integer().nullable()();

  TextColumn get periodicidad => text().nullable()();

  /// Tasa de interés anual, porcentaje simple (ej. 24.5) — puramente
  /// informativa, sin cálculo de intereses automático en esta etapa.
  RealColumn get tasaInteres => real().nullable()();

  TextColumn get referencia => text().nullable()();

  TextColumn get observaciones => text().nullable()();

  TextColumn get estatus => text().withDefault(const Constant('activa'))();

  TextColumn get motivoCancelacion => text().nullable()();

  TextColumn get tarjetaUltimosDigitos => text().nullable()();

  IntColumn get tarjetaLimiteCredito => integer().nullable()();

  IntColumn get tarjetaDiaCorte => integer().nullable()();

  IntColumn get tarjetaDiaPago => integer().nullable()();

  /// Opcional — nunca inventado si el operador no lo captura (pedido
  /// explícito: "no inventar pago mínimo si no se captura"). Ya no se
  /// captura en el alta/edición de TDC nuevas (Etapa "tarjeta
  /// revolvente") — permanece por compatibilidad con filas existentes,
  /// nunca leído por ningún cálculo (confirmado, cero consumidores).
  IntColumn get tarjetaPagoMinimo => integer().nullable()();

  /// Nombre de [ReglaFechaLimitePagoTarjeta] — solo tiene sentido cuando
  /// `tipo == tarjetaCredito`.
  TextColumn get tarjetaReglaFechaPago => text().nullable()();

  /// Días naturales después de `tarjetaDiaCorte` — solo se usa cuando
  /// `tarjetaReglaFechaPago == diasDespuesDeCorte`.
  IntColumn get tarjetaDiasDespuesCorte => integer().nullable()();

  /// Nombre de [TipoTasaTarjeta] — `null` significa "no capturada",
  /// nunca se asume `fija` por omisión. Cuando es `fija`, el valor vive
  /// en `tasaInteres` (mismo campo que una deuda fija, sin duplicar).
  /// Cuando es `variable`, `tasaInteres` se deja `null` — la tasa
  /// contractual vive en `tarjetaTasaReferencia`/`tarjetaTasaDiferencial`/
  /// `tarjetaTasaMasIva`/`tarjetaTasaDescripcion` (caso real: Konfío
  /// Empresarial, TIIE a 28 días + 60 puntos porcentuales + IVA — nunca
  /// "60%" fijo).
  TextColumn get tarjetaTipoTasa => text().nullable()();

  /// Índice/referencia de la tasa variable, texto libre (ej. "TIIE 28
  /// días") — mismo criterio que `acreedor`: la variedad real de
  /// índices es demasiado amplia para un catálogo cerrado.
  TextColumn get tarjetaTasaReferencia => text().nullable()();

  /// Diferencial en puntos porcentuales sobre la referencia (ej. `60.0`
  /// para "TIIE + 60 puntos") — NUNCA la tasa misma.
  RealColumn get tarjetaTasaDiferencial => real().nullable()();

  /// Tri-state real vía `nullable`: `null` = no especificado si la tasa
  /// variable se expresa contractualmente "+ IVA"; `true`/`false` = sí/no.
  BoolColumn get tarjetaTasaMasIva => boolean().nullable()();

  /// Descripción contractual legible, opcional (ej. "TIIE a 28 días +
  /// 60 puntos porcentuales + IVA") — nunca se deriva de los campos
  /// anteriores automáticamente, es una transcripción libre de la
  /// carátula del contrato.
  TextColumn get tarjetaTasaDescripcion => text().nullable()();

  /// CAT (Costo Anual Total) % anual, opcional — concepto regulatorio
  /// DISTINTO de la tasa ordinaria (caso real: Konfío Empresarial
  /// declara CAT 105.7% sin IVA junto con una tasa ordinaria variable
  /// TIIE + 60 puntos — nunca deben confundirse ni promediarse).
  RealColumn get tarjetaCat => real().nullable()();

  /// Mismo tri-state que `tarjetaTasaMasIva`, para el CAT — el
  /// tratamiento de IVA del CAT también varía por contrato, no se
  /// asume una convención fija.
  BoolColumn get tarjetaCatIncluyeIva => boolean().nullable()();

  /// Vencimiento del último ciclo de pago ya cubierto (schemaVersion
  /// 68, "reconciliación de ciclo de TDC") — ancla explícita para
  /// [proximaFechaLimitePago]/[proximaFechaPagoDeuda]
  /// (`calcular_fecha_tarjeta_usecase.dart`): la próxima obligación se
  /// calcula como la menor ocurrencia ESTRICTAMENTE POSTERIOR a este
  /// valor, nunca simplemente "la primera fecha >= hoy". `null`
  /// (comportamiento de siempre) para toda Deuda existente y para
  /// cualquier TDC nueva sin conciliar — anclado al VENCIMIENTO, nunca
  /// al corte, porque en la regla `diasDespuesDeCorte` son fechas
  /// distintas y el propio caso real que motivó este campo (Konfío)
  /// habla del vencimiento ya pagado, no del corte.
  ///
  /// Se puebla de dos formas, nunca inventadas: (1) al dar de alta una
  /// TDC que ya traía consigo un ciclo pagado ANTES de capturar sus
  /// saldos en RISEG ONE — pura reconciliación de apertura, jamás
  /// genera `Egreso`/`MovimientoDeuda`; (2) automáticamente al
  /// registrar un pago real (`registrarPago`), que avanza este valor
  /// hacia adelante (nunca hacia atrás) a la obligación vigente en ese
  /// momento. Comparado contra "hoy" en `proximaFechaPagoDeuda`, este
  /// mismo campo también permite detectar "vencida" — antes
  /// estructuralmente imposible porque el cálculo solo sabía avanzar
  /// desde hoy.
  DateTimeColumn get tarjetaVencimientoCubiertoHasta => dateTime().nullable()();

  @override
  List<String> get customConstraints => [
        'CHECK (importe_original IS NULL OR importe_original > 0)',
        'CHECK (saldo_actual >= 0)',
      ];
}

/// Historial append-only de una Deuda — cada línea conserva su propio
/// `saldoAnterior`/`saldoPosterior` explícito (nunca se recalcula el
/// historial completo para auditar un saldo, pedido explícito).
///
/// `deudaId` es `cascade` (nada externo referencia esta tabla — es
/// propiedad exclusiva de su Deuda, a diferencia de `ArticuloUnidad` en
/// Compra); `egresoId` es `restrict` y solo se puebla cuando
/// `tipo == pago`.
///
/// Etapa 19B — `cargoCompra` (renombrado desde `cargo`, nunca
/// persistido con ese nombre así que el rename no tuvo costo de
/// migración) es el cargo que una Compra pagada con tarjeta genera al
/// registrarse: aumenta el saldo, vincula `compraId` de forma
/// determinista (nunca por texto/monto/fecha) y **no** puebla
/// `egresoId` — el gasto operativo se reconoce en el momento de la
/// compra sin crear un segundo Egreso cuando la tarjeta se pague
/// después (ver `ResumenFinancieroState.egresosOperativos`).
/// `ajustePositivo`/`ajusteNegativo` corrigen ese cargo si el total de
/// la Compra cambia o se cancela — nunca reescriben la fila original.
///
/// Etapa "origen financiero unificado" (schemaVersion 69): el mismo
/// `tipo == cargoCompra` (el valor de texto persistido NUNCA se
/// renombra) se reutiliza para un cargo originado por un Tiempo Extra
/// (`tiempoExtraId`) o por uno de sus costos adicionales
/// (`costoAdicionalId`) — exactamente uno de `compraId`/
/// `tiempoExtraId`/`costoAdicionalId`/`egresoGastoId` (este último
/// desde la Etapa "Origen financiero de Egresos manuales: Cuenta vs.
/// TDC", schemaVersion 76) se puebla, nunca más de uno.
/// `DeudaRepository.totalCargadoEnRango` (y por lo tanto
/// `ResumenFinancieroState.cargosTarjetaPeriodo`) ya suma por `tipo`,
/// sin filtrar por origen — reconoce el gasto sin importar cuál módulo
/// lo generó, sin ningún cambio adicional.
///
/// **Deuda técnica documentada (auditoría 2026-09-07)**: el nombre
/// `cargoCompra` ya no describe con precisión su significado real —
/// hoy es "cargo de gasto financiado con TDC", sin importar si proviene
/// de una Compra, un Tiempo Extra, uno de sus costos adicionales o un
/// Egreso manual (schemaVersion 76 — cuarto origen, mismo nombre). NO
/// se renombra en esta etapa porque el valor está persistido como texto
/// en BD (`MovimientoDeuda.tipo`) y renombrarlo exige una migración de
/// datos, no solo de código. Candidato a una etapa futura dedicada
/// (ej. renombrar a `cargoGastoTarjeta` con migración de backfill).
/// Etapa 9 ("Corrección y cancelación individual de pagos") —
/// `reversionPago` es la reversión ÍNTEGRA de un pago que se cancela:
/// aumenta el saldo por el neto vivo de ese pago y se vincula a él con
/// `movimientoOrigenId`. Valor nuevo del enum, sin migración de datos
/// (ninguna fila existente lo usa).
///
/// Es un tipo propio y no una reutilización de `cancelacion` porque ese
/// significa otra cosa por completo: condonar la Deuda ENTERA (zera
/// `saldoActual`, `estatus → cancelada`). Tampoco se distingue por
/// `ajustePositivo` + `movimientoOrigenId`, porque una CORRECCIÓN a la
/// baja del mismo pago produce exactamente ese par — y "corregido" y
/// "cancelado" no son el mismo hecho. Con un tipo propio, "¿este pago
/// está cancelado?" se deriva de la existencia de su `reversionPago`,
/// sin mutar jamás la fila original ni leer texto libre.
enum TipoMovimientoDeuda { altaInicial, cargoCompra, pago, ajustePositivo, ajusteNegativo, cancelacion, reversionPago }

class MovimientoDeuda extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get deudaId => text().references(Deuda, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get fecha => dateTime()();

  TextColumn get tipo => text()();

  /// Magnitud del movimiento, siempre positiva — la dirección (suma o
  /// resta del saldo) la determina `tipo`, nunca el signo de `importe`.
  IntColumn get importe => integer()();

  IntColumn get saldoAnterior => integer()();

  IntColumn get saldoPosterior => integer()();

  /// El `Egreso` que ESTE movimiento GENERÓ — solo cuando
  /// `tipo == pago` (la salida de efectivo con la que se pagó la
  /// Deuda). Nunca confundir con [egresoGastoId], que apunta en la
  /// dirección contraria: el Egreso que ORIGINÓ un cargo.
  TextColumn get egresoId => text().nullable().references(Egreso, #id, onDelete: KeyAction.restrict)();

  /// Etapa "Origen financiero de Egresos manuales: Cuenta vs. TDC"
  /// (schemaVersion 76) — el `Egreso` (gasto manual) que ORIGINÓ este
  /// cargo, cuando se financió con tarjeta en vez de con una
  /// `CuentaFinanciera`. Cuarto miembro del grupo `compraId`/
  /// `tiempoExtraId`/`costoAdicionalId`: exactamente uno de los cuatro
  /// se puebla en un `cargoCompra`/`ajustePositivo`/`ajusteNegativo`,
  /// nunca más de uno. Mismo criterio `restrict` que los otros tres.
  ///
  /// Columna DISTINTA de [egresoId] a propósito, no una duplicación:
  /// [egresoId] es el Egreso que un pago produce (dirección
  /// Deuda → Egreso); este es el Egreso que produce un cargo
  /// (dirección Egreso → Deuda). Un mismo movimiento nunca puebla las
  /// dos — son tipos de movimiento mutuamente excluyentes.
  TextColumn get egresoGastoId => text().nullable().references(Egreso, #id, onDelete: KeyAction.restrict)();

  /// Etapa 19B — poblado únicamente cuando `tipo` es `cargoCompra`,
  /// `ajustePositivo` o `ajusteNegativo` originados por una corrección/
  /// cancelación de esa misma Compra. `restrict`: no se puede borrar la
  /// Compra mientras este movimiento exista (ver
  /// `CompraRepositoryImpl.eliminarFisicamente`, que revierte/borra este
  /// movimiento primero, solo si es el más reciente de la tarjeta).
  TextColumn get compraId => text().nullable().references(Compra, #id, onDelete: KeyAction.restrict)();

  /// Etapa "origen financiero unificado" (schemaVersion 69) — poblado
  /// cuando el cargo proviene del PAGO BASE de una cobertura de Tiempo
  /// Extra cobrada directo a una tarjeta (nunca junto con `compraId`/
  /// `costoAdicionalId`). Mismo criterio exacto que `compraId`.
  TextColumn get tiempoExtraId => text().nullable().references(TiempoExtra, #id, onDelete: KeyAction.restrict)();

  /// Igual que `tiempoExtraId`, pero cuando el cargo proviene de un
  /// COSTO ADICIONAL específico de la cobertura (ej. Uber, comida) —
  /// nunca del pago base. `TiempoExtraCostoAdicional.id` es
  /// `autoIncrement` (entero), a diferencia de la mayoría de los ids
  /// de este proyecto.
  IntColumn get costoAdicionalId =>
      integer().nullable().references(TiempoExtraCostoAdicional, #id, onDelete: KeyAction.restrict)();

  /// Etapa "Vehículos: ciclo de vida y origen financiero"
  /// (schemaVersion 80) — poblado cuando el cargo proviene de un
  /// mantenimiento/incidencia de un Vehículo cobrado directo a una
  /// tarjeta. Mismo criterio exacto que `compraId`/`tiempoExtraId`:
  /// una FK real, nunca una heurística.
  ///
  /// Como el resto de FK de gasto, cuenta para `totalCargadoEnRango`
  /// (es un CARGO, no la corrección de un pago).
  /// Etapa "Cierre integral de Telefonía" (schemaVersion 86) — la
  /// recarga de línea que originó este cargo, cuando se pagó con
  /// tarjeta. Mismo criterio exacto que [compraId]/[tiempoExtraId]/
  /// [vehiculoMantenimientoId]: FK real, nunca inferencia por concepto.
  TextColumn get recargaLineaTelefonicaId =>
      text().nullable().references(RecargaLineaTelefonica, #id, onDelete: KeyAction.restrict)();

  /// schemaVersion 87 — FK inversa real de un cargo por una cobertura
  /// de Servicio Eventual pagada con tarjeta. El origen NUNCA se busca
  /// por concepto, monto, fecha ni folio textual.
  TextColumn get servicioEventualCoberturaId =>
      text().nullable().references(ServicioEventualCobertura, #id, onDelete: KeyAction.restrict)();

  /// schemaVersion 87 — lo mismo para un costo adicional del eventual.
  TextColumn get servicioEventualCostoId =>
      text().nullable().references(ServicioEventualCosto, #id, onDelete: KeyAction.restrict)();

  TextColumn get vehiculoMantenimientoId =>
      text().nullable().references(VehiculoMantenimiento, #id, onDelete: KeyAction.restrict)();

  /// Etapa 9 ("Corrección y cancelación individual de pagos") — el
  /// `MovimientoDeuda` tipo `pago` que ESTE movimiento corrige o
  /// revierte. Poblado únicamente en `ajustePositivo`/`ajusteNegativo`
  /// nacidos de una corrección de pago y en `reversionPago`.
  ///
  /// Autorreferencia deliberada, en vez de una tabla genérica de
  /// correcciones: el pago ya tiene identidad propia e inequívoca
  /// (`MovimientoDeuda.id`, autoincremental), así que vincular el
  /// ajuste a esa identidad es una FK real de una línea — nunca una
  /// heurística por monto, fecha, texto o "el último movimiento".
  ///
  /// Es también el discriminador que separa los dos mundos de ajustes
  /// que conviven en esta tabla: `movimientoOrigenId != null` significa
  /// "esto corrige un PAGO" (no es gasto), mientras que un ajuste con
  /// `compraId`/`tiempoExtraId`/`costoAdicionalId`/`egresoGastoId`
  /// significa "esto corrige un CARGO" (sí es gasto). Por eso
  /// `totalCargadoEnRango` excluye explícitamente los primeros: contar
  /// la corrección de un pago como gasto operativo sería doble conteo
  /// de una realidad que ni siquiera es un gasto.
  IntColumn get movimientoOrigenId =>
      integer().nullable().references(MovimientoDeuda, #id, onDelete: KeyAction.restrict)();

  /// Etapa 9 — valor que `Deuda.tarjetaVencimientoCubiertoHasta` tenía
  /// ANTES de que este pago lo avanzara. Poblado solo en `tipo == pago`
  /// sobre una TDC cuya configuración permitió calcular el avance;
  /// `null` cuando el pago no movió el ciclo (deuda fija, o regla/día
  /// incompletos), y también en todo pago anterior a esta etapa.
  ///
  /// Existe para poder DESHACER el avance con exactitud al cancelar el
  /// pago, en vez de recalcularlo (imposible: la regla vigente avanza
  /// un ciclo por pago sin mirar el monto, y el campo también puede
  /// haberse conciliado a mano). Con `null` la cancelación nunca
  /// inventa un retroceso — deja el ciclo intacto y lo reporta, para
  /// que el operador concilie desde "Corregir deuda".
  DateTimeColumn get tarjetaVencimientoCubiertoAnterior => dateTime().nullable()();

  TextColumn get observaciones => text().nullable()();

  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => ['CHECK (importe > 0)'];
}
