import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../../core/database/tables/catalogos_tables.dart';
import '../../../finanzas/data/tables/deuda_table.dart';
import '../../../finanzas/data/tables/egreso_table.dart';
import '../../../organizacion/data/tables/servicio_table.dart';
import '../../../personal/data/tables/empleado_table.dart';
import '../../../personal/data/tables/vacante_operativa_table.dart';
import '../../../usuarios/data/tables/usuario_table.dart';

/// Por qué el titular del turno no cubrió — catálogo cerrado (pedido
/// explícito de Marlon, las 4 opciones exactas), literal en vez de
/// referencia a enum — mismo motivo de siempre.
enum MotivoAusenciaTiempoExtra { problemasMedicos, faltaInjustificada, faltaJustificada, permisoOtorgado }

enum EstatusTiempoExtra { registrado, cancelado }

/// Por qué hubo que cubrir el turno — discriminador EXPLÍCITO del
/// dominio (Etapa "Tiempo Extra: origen de cobertura"). Hasta
/// schemaVersion 84 el modelo asumía que todo TiempoExtra existía
/// porque faltó un titular: `empleadoAusenteId` era `NOT NULL`. En
/// operación real también se cubre una plaza VACANTE (no falta nadie:
/// no hay nadie) o una necesidad puntual distinta.
///
/// Nunca se infiere por nulos: un `empleadoAusenteId` nulo no
/// significa "es vacante". El discriminador es esta columna, y las
/// invariantes de cada valor las impone `TiempoExtraValidator`.
enum OrigenCoberturaTiempoExtra {
  /// Faltó el titular del turno. Exige `empleadoAusenteId` +
  /// `motivoAusencia`. Es el único origen que existía antes de v85 y
  /// el único que se anota en la Nómina del ausente.
  ausenciaEmpleado,

  /// La plaza no tenía titular. Exige `vacanteOperativaId` (FK real a
  /// `VacanteOperativa`, nunca un nombre ficticio ni un empleado
  /// placeholder). Registrar el TiempoExtra NO cubre la vacante.
  vacante,

  /// Cualquier otra necesidad de cobertura (apoyo extraordinario,
  /// reforzamiento, traslado…). Exige `descripcionOrigen`, texto
  /// breve — deliberadamente NO un catálogo.
  otro,
}

/// Cobertura operativa por ausencia (pedido explícito de Marlon): cuando
/// falta el titular de un turno en un Servicio, alguien lo cubre —un
/// Empleado activo o un externo— y se le paga tiempo extra, más
/// cualquier costo adicional (traslado, Uber, recarga telefónica).
///
/// Etapa "origen financiero unificado" (schemaVersion 69): el pago base
/// y cada costo adicional tienen su PROPIO origen financiero
/// independiente — nunca se fusionan aunque compartan cuenta, para no
/// perder trazabilidad por ítem. El pago base genera, según su origen,
/// exactamente uno de `egresoId` (CuentaFinanciera, mismo patrón que
/// `Compra.egresoId`) o `deudaId` (tarjeta de crédito, mismo patrón que
/// `Compra.deudaId`) — mutuamente excluyentes, nunca ambos ni ninguno
/// para una fila nueva. `Egreso` en sí nunca guarda su origen, la
/// trazabilidad siempre vive en la tabla fuente. Nunca toca la Nómina
/// de quien cubre — ver `NominaEmpleadoAusencia` para la única huella
/// que deja esta tabla en Nómina, y solo del lado del Empleado
/// AUSENTE, nunca de quien cubrió.
class TiempoExtra extends Table with AuditColumns {
  TextColumn get folio => text().unique()();

  DateTimeColumn get fecha => dateTime()();

  TextColumn get servicioId => text().references(Servicio, #id, onDelete: KeyAction.restrict)();

  /// Discriminador explícito del origen de la cobertura (Etapa "Tiempo
  /// Extra: origen de cobertura", schemaVersion 85). Literal en vez de
  /// referencia al enum — mismo motivo de siempre. `ausenciaEmpleado`
  /// por defecto: es lo que TODA fila anterior a v85 representaba, por
  /// construcción (`empleadoAusenteId` era `NOT NULL`).
  TextColumn get origenCobertura =>
      text().withDefault(const Constant('ausenciaEmpleado'))();

  /// Sólo con `origenCobertura == ausenciaEmpleado`. Nullable desde
  /// v85: en una vacante no falta nadie —no hay titular— y en "otro"
  /// tampoco. La invariante la impone `TiempoExtraValidator`, nunca
  /// un `CHECK` (necesitaría leer el discriminador y tres columnas a
  /// la vez, y SQLite no permite relajarlo después sin recrear).
  TextColumn get empleadoAusenteId =>
      text().nullable().references(Empleado, #id, onDelete: KeyAction.restrict)();

  /// Sólo con `origenCobertura == ausenciaEmpleado`. Literal en vez de
  /// referencia al enum — mismo motivo de siempre.
  TextColumn get motivoAusencia => text().nullable()();

  /// Sólo con `origenCobertura == vacante`: la plaza real que se
  /// cubrió, por FK verdadera — nunca texto libre ni una bandera
  /// `esVacante`. `restrict`: un TiempoExtra histórico debe seguir
  /// resolviendo QUÉ vacante cubrió aunque ésa ya se haya cubierto
  /// después, así que la vacante no puede desaparecer bajo él.
  ///
  /// Registrar este TiempoExtra NO cierra la vacante ni la marca como
  /// cubierta: fue una cobertura temporal de un turno, no una
  /// contratación. `VacanteOperativa` sigue su propio ciclo.
  TextColumn get vacanteOperativaId =>
      text().nullable().references(VacanteOperativa, #id, onDelete: KeyAction.restrict)();

  /// Sólo con `origenCobertura == otro`: descripción breve de por qué
  /// se cubrió. Deliberadamente texto y no catálogo — el abanico real
  /// (apoyo extraordinario, reforzamiento, capacitación, traslado…) no
  /// se cierra bien, y un catálogo obligaría a mantenerlo. NO reutiliza
  /// `motivoAusencia`: ese enum describe por qué faltó una PERSONA
  /// (problemas médicos, falta injustificada…), que aquí no aplica.
  TextColumn get descripcionOrigen => text().nullable()();

  /// Exactamente uno de `empleadoCubreId`/`nombreExternoCubre` —
  /// validado en `TiempoExtraValidator`, nunca aquí (una FK nullable no
  /// puede expresar "uno de los dos, nunca ambos").
  TextColumn get empleadoCubreId => text().nullable().references(Empleado, #id, onDelete: KeyAction.restrict)();

  TextColumn get nombreExternoCubre => text().nullable()();

  TextColumn get turnoId => text().references(TipoModalidadTurno, #id, onDelete: KeyAction.restrict)();

  IntColumn get montoTiempoExtra => integer()();

  TextColumn get formaPago => text()();

  TextColumn get observaciones => text().nullable()();

  /// Único (mismo criterio que `Compra.egresoId`) — poblado cuando el
  /// PAGO BASE se paga desde una CuentaFinanciera. Mutuamente
  /// excluyente con `deudaId`.
  TextColumn get egresoId => text().nullable().unique().references(Egreso, #id, onDelete: KeyAction.restrict)();

  /// Etapa "origen financiero unificado" — poblado cuando el PAGO BASE
  /// se carga directo a una tarjeta de crédito en vez de salir de una
  /// CuentaFinanciera (mismo patrón dual que `Compra.egresoId`/
  /// `Compra.deudaId`). Nunca genera Egreso — ver
  /// `DeudaRepository.registrarCargoTiempoExtra`.
  TextColumn get deudaId => text().nullable().references(Deuda, #id, onDelete: KeyAction.restrict)();

  TextColumn get estatus => text().withDefault(const Constant('registrado'))();

  TextColumn get motivoCancelacion => text().nullable()();

  @override
  List<String> get customConstraints => ['CHECK (monto_tiempo_extra > 0)'];
}

/// Costos adicionales de una cobertura (Etapa Tiempos Extra) — traslado,
/// apoyo de transporte, recarga telefónica, etc. `concepto` es texto
/// libre (el formulario ofrece sugerencias rápidas, nunca un catálogo
/// cerrado — mismo criterio que `Egreso.beneficiario`/`cuentaCaja`):
/// puede haber más de un costo distinto en la misma cobertura, cada uno
/// con su PROPIO origen financiero independiente (Etapa "origen
/// financiero unificado", schemaVersion 69) — nunca fusionados en un
/// solo Egreso combinado, ni siquiera si comparten cuenta, para no
/// perder trazabilidad por ítem.
class TiempoExtraCostoAdicional extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get tiempoExtraId => text().references(TiempoExtra, #id, onDelete: KeyAction.cascade)();

  TextColumn get concepto => text()();

  IntColumn get monto => integer()();

  /// Nullable: las filas históricas nunca lo capturaron (Egreso único
  /// combinado con el pago base, sin forma de pago propia por costo).
  /// El diálogo nuevo lo exige para cada fila nueva.
  TextColumn get formaPago => text().nullable()();

  /// Poblado cuando ESTE costo se paga desde una CuentaFinanciera —
  /// genera su PROPIO Egreso, nunca combinado con el pago base ni con
  /// otro costo. Mutuamente excluyente con `deudaId`. A diferencia de
  /// `TiempoExtra.egresoId`/`Compra.egresoId`, deliberadamente sin
  /// `.unique()` a nivel de esquema (agregar esa restricción a una
  /// columna nueva vía `ALTER TABLE` no es soportado por SQLite); la
  /// unicidad la garantiza la ruta de escritura (cada Egreso se crea
  /// fresco para este costo exacto, nunca reutilizado).
  TextColumn get egresoId => text().nullable().references(Egreso, #id, onDelete: KeyAction.restrict)();

  /// Poblado cuando ESTE costo se carga directo a una tarjeta de
  /// crédito — nunca genera Egreso (ver
  /// `DeudaRepository.registrarCargoCostoAdicional`).
  TextColumn get deudaId => text().nullable().references(Deuda, #id, onDelete: KeyAction.restrict)();

  /// Etapa "corrección real de Tiempo Extra" (schemaVersion 70) —
  /// borrado lógico: un costo "quitado" durante una corrección revierte
  /// su efecto financiero (`MovimientoDeuda`/`Egreso.cancelar`) pero la
  /// fila NUNCA se borra físicamente — `MovimientoDeuda.costoAdicionalId`
  /// es `restrict`, así que la reversión (que sigue referenciando este
  /// mismo id) impediría el `DELETE`. `listarCostosAdicionales`/
  /// `totalCostosAdicionalesPorTiempoExtra` excluyen `eliminado == true`
  /// — el gasto operativo/expediente nunca vuelve a mostrarlo. Solo la
  /// eliminación física del TiempoExtra completo borra estas filas.
  BoolColumn get eliminado => boolean().withDefault(const Constant(false))();

  @override
  List<String> get customConstraints => ['CHECK (monto > 0)'];
}

/// Historial append-only de un TiempoExtra — mismo criterio exacto que
/// `CompraEvento`/`EgresoEvento` (sin la columna `actor` legada: esta
/// tabla nace después de la Etapa 11D, `actorUsuarioId` es la única
/// fuente de "quién" desde el principio).
///
/// Etapa "corrección real de Tiempo Extra" (schemaVersion 70):
/// `estadoAnterior`/`estadoNuevo` (JSON, nullable) se agregan para el
/// tipo `corregido` — solo los campos que cambiaron, mismo criterio
/// selectivo que `datosRelevantes` de `CompraEvento`. `null` en filas
/// `registrado`/`cancelado` preexistentes (nunca se rellenan
/// retroactivamente).
class TiempoExtraEvento extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get tiempoExtraId => text().references(TiempoExtra, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get fechaHora => dateTime()();

  TextColumn get tipoEvento => text()();

  TextColumn get observacion => text().nullable()();

  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  TextColumn get estadoAnterior => text().nullable()();

  TextColumn get estadoNuevo => text().nullable()();
}
