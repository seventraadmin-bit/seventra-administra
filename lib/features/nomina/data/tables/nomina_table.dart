import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';

/// Los dos periodos de pago mensuales de RISEG (Etapa 6C) — mismo
/// criterio que ya operaba en Excel antes de esta etapa (Resolución
/// explícita de Marlon): nunca semanal, nunca configurable por
/// Servicio/Cliente. Primera quincena: días 1 a 15, paga el 20 del
/// mismo mes. Segunda quincena: día 16 al último día del mes, paga el 5
/// del mes siguiente.
enum TipoPeriodoNomina { primera, segunda }

/// Ciclo de vida de una Nómina — `pagada` existe en el esquema desde
/// ahora (evita otra migración estructural en la Etapa 6D), pero
/// ninguna acción de esta etapa la produce todavía: 6C solo llega hasta
/// `cerrada` (Resolución explícita de Marlon: "en 6C no generes aún
/// Egresos ni cierres financieros reales").
enum EstatusNomina { borrador, cerrada, pagada }

/// Encabezado de un periodo de Nómina (Etapa 6C) — el "Control interno
/// de pagos" aprobado: nunca calcula ISR/IMSS/SBC/UMA, nunca genera
/// CFDI/timbrado (fuera de alcance explícito). Una sola Nómina por
/// periodo (`UNIQUE (anio, mes, tipo_periodo)`) — no existe el concepto
/// de "Nómina cancelada y vuelta a generar" en esta etapa.
///
/// `Borrador` admite regenerar el detalle desde Personal
/// (`ActualizarNominaDesdePersonalUseCase`) cuantas veces haga falta,
/// preservando los movimientos manuales ya capturados. `Cerrada`
/// congela todo — ningún campo de `NominaEmpleado`/`NominaEmpleadoTramo`
/// vuelve a tocarse después, ni aunque cambie el Servicio/sueldo/
/// asignación del Empleado en Personal (Resolución explícita de
/// Marlon).
class Nomina extends Table with AuditColumns {
  TextColumn get folio => text().unique()();

  IntColumn get anio => integer()();

  /// 1 a 12.
  IntColumn get mes => integer()();

  // Literal en vez de referencia al enum — mismo motivo que
  // `AuditColumns.cicloVidaRegistro`.
  TextColumn get tipoPeriodo => text()();

  DateTimeColumn get fechaInicioPeriodo => dateTime()();

  DateTimeColumn get fechaFinPeriodo => dateTime()();

  /// Fecha de pago ordinaria calculada automáticamente
  /// (`calcularPeriodoNomina`) — nunca capturada a mano.
  DateTimeColumn get fechaPagoOrdinaria => dateTime()();

  TextColumn get estatus => text().withDefault(const Constant('borrador'))();

  DateTimeColumn get fechaCierre => dateTime().nullable()();

  TextColumn get observaciones => text().nullable()();

  @override
  List<String> get customConstraints => [
        'UNIQUE (anio, mes, tipo_periodo)',
        'CHECK (mes >= 1 AND mes <= 12)',
        'CHECK (fecha_fin_periodo >= fecha_inicio_periodo)',
      ];
}
