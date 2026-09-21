import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../organizacion/data/tables/servicio_table.dart';
import '../../../personal/data/tables/empleado_table.dart';
import 'nomina_table.dart';

/// De dónde viene el sueldo/bono del **último** tramo de un
/// `NominaEmpleado` — mismo criterio de detección automática que 6A/6B:
/// con `AsignacionServicio` vigente usa `servicio`; sin ninguna, usa
/// `administrativo` (`Empleado.sueldoMensualAdministrativo`/
/// `bonoMensualAdministrativo`). Ver también `NominaEmpleadoTramo`, que
/// registra la fuente por tramo, no solo la del último.
enum FuenteSueldoNomina { servicio, administrativo }

/// Estado de pago **individual** de un renglón — independiente del
/// `estatus` general de la `Nomina` (Resolución explícita de Marlon:
/// "Pagada debe representar que el dinero efectivamente salió"; puede
/// haber Empleados ya pagados y otros pendientes dentro de la misma
/// Nómina cerrada). Mantenido transaccionalmente por
/// `PagoNominaRepositoryImpl` en cada `AplicacionPagoNomina` (Etapa 6D)
/// — mismo criterio que `CuentaPorCobrar.estatus` se mantiene en cada
/// `AplicacionPago`. `parcial` agregado en 6D: sin `CHECK` que
/// restrinja los valores de esta columna, así que sumar un valor de
/// enum no requiere migración.
enum EstatusPagoNominaEmpleado { pendiente, parcial, pagado }

/// Un renglón de Nómina por Empleado (Etapa 6C) — snapshot completo:
/// identidad, cálculo, movimientos manuales y distribución Fiscal/No
/// fiscal, todo en la misma fila (Resolución explícita de Marlon: "no
/// quiero dos Nóminas separadas, Fiscal y No fiscal deben convivir en
/// la misma fila").
///
/// **Por qué todo aquí es un snapshot, nunca una referencia en vivo a
/// Personal**: mientras la Nómina está en Borrador, estos valores se
/// mantienen sincronizados solo a través de la acción explícita
/// `ActualizarNominaDesdePersonalUseCase` — nunca automáticamente. Una
/// vez `Cerrada`, ya no hay ninguna acción que los vuelva a tocar, ni
/// aunque el Servicio/sueldo/asignación del Empleado cambie después en
/// Personal. Esto resuelve de raíz la instrucción de Marlon de "no
/// duplicar datos de Personal, pero conservar historial protegido".
///
/// `numeroEmpleado`/`nombreCompleto`/`puestoNombre`/`servicioNombre`/
/// `turnoNombre`/`bancoNombre`/`numeroCuentaTarjeta`/`clabe` son puro
/// texto de despliegue — nunca se navega de vuelta a través de ellos
/// (por eso no son FK), a diferencia de `servicioId`, que sí es una FK
/// real (`restrict`) porque sí tiene un consumidor claro: reportes por
/// Servicio.
class NominaEmpleado extends Table with AuditColumns {
  TextColumn get nominaId => text().references(Nomina, #id, onDelete: KeyAction.cascade)();

  TextColumn get empleadoId => text().references(Empleado, #id, onDelete: KeyAction.restrict)();

  // --- Snapshot de identidad ---

  IntColumn get numeroEmpleado => integer()();

  TextColumn get nombreCompleto => text()();

  TextColumn get puestoNombre => text().nullable()();

  TextColumn get servicioId => text().nullable().references(Servicio, #id, onDelete: KeyAction.restrict)();

  TextColumn get servicioNombre => text().nullable()();

  TextColumn get turnoNombre => text().nullable()();

  TextColumn get bancoNombre => text().nullable()();

  TextColumn get numeroCuentaTarjeta => text().nullable()();

  TextColumn get clabe => text().nullable()();

  // --- Cálculo (ver `calcularDiasPagablesEmpleado`) ---

  // Literal en vez de referencia al enum — mismo motivo que
  // `AuditColumns.cicloVidaRegistro`.
  TextColumn get fuenteSueldoUtilizada => text()();

  IntColumn get diasPagables => integer()();

  /// Sueldo mensual del **último** tramo — nunca un promedio.
  IntColumn get sueldoMensualUtilizado => integer()();

  /// `sueldoMensualUtilizado / 2` — se almacena, no se deriva en
  /// pantalla, mismo criterio de snapshot que el resto de la fila.
  IntColumn get sueldoQuincenalReferencia => integer()();

  /// `sueldoMensualUtilizado / 30` — base de `descuentoPorFaltas`.
  IntColumn get pagoPorDia => integer()();

  /// Suma de `NominaEmpleadoTramo.importeTramo` de este renglón.
  IntColumn get importeBase => integer()();

  // --- Movimientos manuales (Etapa 6C, Resolución explícita de Marlon:
  // columnas fijas, no una tabla de movimientos genérica — faltas es un
  // conteo de días, no un monto, lo que vuelve una tabla uniforme menos
  // simple, no más). Percepciones: bono, tiempoExtra. Deducciones:
  // prestamo, descuentoPorFaltas, otrosDescuentos. ---

  IntColumn get prestamo => integer().withDefault(const Constant(0))();

  IntColumn get tiempoExtra => integer().withDefault(const Constant(0))();

  /// Propuesto automáticamente solo en la Nómina de la segunda quincena
  /// (pago del día 5) — `$0` por defecto en la primera. Nunca se
  /// prorratea entre tramos (Resolución explícita de Marlon).
  IntColumn get bono => integer().withDefault(const Constant(0))();

  /// `true` en cuanto el usuario edita `bono` a mano — evita que
  /// `ActualizarNominaDesdePersonalUseCase` lo vuelva a proponer
  /// automáticamente y lo pise.
  BoolColumn get bonoModificadoManualmente => boolean().withDefault(const Constant(false))();

  /// Días de falta — **independiente** de `diasPagables` (Resolución
  /// explícita de Marlon: una falta nunca reduce los días pagables,
  /// solo genera una deducción). Sin lógica automática de pérdida de
  /// bono en esta etapa.
  IntColumn get faltas => integer().withDefault(const Constant(0))();

  /// `faltas × pagoPorDia` — se recalcula cada vez que `faltas` cambia,
  /// pero se almacena como cualquier otro campo de esta fila.
  IntColumn get descuentoPorFaltas => integer().withDefault(const Constant(0))();

  IntColumn get otrosDescuentos => integer().withDefault(const Constant(0))();

  /// Suma de los `DescuentoInventario` (daño/pérdida con cargo al
  /// Empleado, Etapa 7B) aplicados a este renglón — Etapa 15,
  /// integración real con Nómina. Distinto de [otrosDescuentos]
  /// (siempre manual, texto libre): este campo lo puebla
  /// exclusivamente `NominaRepositoryImpl.generar`, nunca una edición a
  /// mano — el desglose identificable (artículo, motivo, monto) vive en
  /// las filas de `DescuentoInventario` vinculadas por
  /// `DescuentoInventario.nominaEmpleadoId`, no aquí.
  ///
  /// Deliberadamente **sin** `CHECK (>= 0)` propio: `NominaEmpleado` ya
  /// existe desde la Etapa 6C, así que una migración posterior no puede
  /// agregar una restricción de tabla nueva sin romper la validación
  /// contra los esquemas históricos congelados (`Migrator.createTable`
  /// siempre usa la forma *actual* de esta clase en los pasos
  /// `onUpgrade` que recrean la tabla desde cero para un `from`
  /// antiguo — la migración a un objetivo intermedio viejo terminaría
  /// con más constraints de las que ese esquema histórico espera).
  /// Nunca puede ser negativo de todas formas: siempre es la suma de
  /// `DescuentoInventario.importe`, que ya exige `CHECK (importe > 0)`.
  IntColumn get descuentosInventario => integer().withDefault(const Constant(0))();

  /// `true` cuando los `DescuentoInventario` pendientes de este Empleado
  /// superaban el neto disponible al aplicar (Etapa 15, resolución
  /// explícita de Marlon: "bloquear y avisar" — nunca un
  /// `totalAPagar` negativo silencioso). Solo se aplica hasta donde el
  /// neto alcanza (orden FIFO por fecha de creación del descuento); el
  /// resto queda `pendiente` para una Nómina futura. Mismo criterio
  /// exacto que [distribucionPendienteRevision]: bloquea el cierre
  /// (`CerrarNominaUseCase`), nunca se ajusta en silencio.
  BoolColumn get descuentosInventarioPendienteRevision => boolean().withDefault(const Constant(false))();

  /// Suma de `DescuentoProgramadoCuota` (préstamos, costo de botas, y
  /// futuros tipos — Etapa 15, "Descuentos Programados al Personal")
  /// vinculadas a este renglón — mismo criterio exacto que
  /// [descuentosInventario]: lo puebla exclusivamente
  /// `NominaRepositoryImpl.guardarRenglon`, nunca una edición a mano; el
  /// desglose identificable (folio, número de cuota) vive en
  /// `DescuentoProgramadoCuota.nominaEmpleadoId`, no aquí. Deliberadamente
  /// **sin** `CHECK (>= 0)` propio — mismo motivo exacto que
  /// [descuentosInventario] (tabla ya existente desde 6C).
  IntColumn get descuentosProgramados => integer().withDefault(const Constant(0))();

  /// `true` cuando las `DescuentoProgramadoCuota` elegibles de este
  /// Empleado superaban el neto disponible al resolver (mismo criterio
  /// exacto que [descuentosInventarioPendienteRevision]) — bloquea el
  /// cierre (`CerrarNominaUseCase`), nunca se ajusta en silencio. El
  /// neto disponible para este pool ya viene descontado de
  /// [descuentosInventario] (Inventario se resuelve primero, ver
  /// `NominaRepositoryImpl._resolverCuotasProgramadasAplicables`).
  BoolColumn get descuentosProgramadosPendienteRevision => boolean().withDefault(const Constant(false))();

  TextColumn get observaciones => text().nullable()();

  // --- Fiscal / No fiscal (Etapa 6C, Resolución explícita de Marlon:
  // una sola Nómina, nunca dos separadas) ---

  IntColumn get montoFiscal => integer().withDefault(const Constant(0))();

  IntColumn get montoNoFiscal => integer().withDefault(const Constant(0))();

  /// `true` en cuanto el usuario edita la distribución a mano — mismo
  /// criterio que `bonoModificadoManualmente`.
  BoolColumn get distribucionModificadaManualmente => boolean().withDefault(const Constant(false))();

  /// `true` cuando `ActualizarNominaDesdePersonalUseCase` recalculó el
  /// total y la distribución manual ya capturada dejó de sumar el
  /// total — nunca se ajusta en silencio (Resolución explícita de
  /// Marlon). Bloquea el cierre de la Nómina mientras siga en `true`.
  BoolColumn get distribucionPendienteRevision => boolean().withDefault(const Constant(false))();

  /// `importeBase + bono + tiempoExtra − prestamo − descuentoPorFaltas
  /// − otrosDescuentos − descuentosInventario − descuentosProgramados`.
  /// Se recalcula en cada escritura del renglón, nunca en pantalla —
  /// igual que el resto de esta fila (`calcularTotalesRenglonNomina`,
  /// única fuente de verdad de la fórmula).
  IntColumn get totalAPagar => integer()();

  // Literal en vez de referencia al enum — mismo motivo de siempre.
  // Inerte en 6C: ver el doc comment de `EstatusPagoNominaEmpleado`.
  TextColumn get estatusPago => text().withDefault(const Constant('pendiente'))();

  @override
  List<String> get customConstraints => [
        'UNIQUE (nomina_id, empleado_id)',
        'CHECK (dias_pagables >= 0)',
        'CHECK (sueldo_mensual_utilizado > 0)',
        'CHECK (importe_base >= 0)',
        'CHECK (prestamo >= 0)',
        'CHECK (tiempo_extra >= 0)',
        'CHECK (bono >= 0)',
        'CHECK (faltas >= 0)',
        'CHECK (descuento_por_faltas >= 0)',
        'CHECK (otros_descuentos >= 0)',
        'CHECK (monto_fiscal >= 0)',
        'CHECK (monto_no_fiscal >= 0)',
      ];
}
