import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../nomina/data/tables/nomina_empleado_table.dart';
import 'descuento_programado_empleado_table.dart';

/// Estado de una cuota — **crítico**: `reservada` es distinto de
/// `aplicada` a propósito (Etapa 15). Una cuota nunca se considera
/// recuperada solo porque una Nómina Borrador (o incluso Cerrada) la
/// incluyó — eso la deja `reservada`. Solo pasa a `aplicada` cuando el
/// renglón de Nómina al que está vinculada llega realmente a
/// `NominaEmpleado.estatusPago == 'pagado'` (`PagoNominaRepositoryImpl.
/// _aplicarInterna`, el único punto irreversible real del modelo
/// actual). Este es el motivo por el que esta tabla NO reutiliza el
/// enum/estados de `DescuentoInventario` (`pendiente`/`aplicado`/
/// `cancelado`): ese ya pasa a `aplicado` desde que un Nómina Borrador
/// lo incluye, lo que sería incorrecto para una cuota de préstamo.
enum EstatusDescuentoProgramadoCuota {
  pendiente,
  reservada,
  aplicada,
  cancelada,
}

/// Una cuota programada de un `DescuentoProgramadoEmpleado` — el plan
/// de recuperación completo vive en filas de esta tabla, nunca en un
/// solo saldo mutable.
class DescuentoProgramadoCuota extends Table with AuditColumns {
  TextColumn get descuentoProgramadoId =>
      text().references(
        DescuentoProgramadoEmpleado,
        #id,
        onDelete: KeyAction.cascade,
      )();

  IntColumn get numeroCuota => integer()();

  DateTimeColumn get fechaProgramada => dateTime()();

  IntColumn get importeProgramado => integer()();

  TextColumn get estatus => text().withDefault(const Constant('pendiente'))();

  /// El renglón de Nómina donde esta cuota está reservada o ya se
  /// aplicó — `null` mientras `estatus == pendiente`/`cancelada`.
  /// `restrict`: mismo criterio exacto que `DescuentoInventario.
  /// nominaEmpleadoId` — nunca se permite borrar/reemplazar un renglón
  /// que ya reservó/aplicó una cuota real sin resolverlo explícitamente
  /// primero (la reversión explícita en `eliminarFisicamente`/
  /// `eliminarCadenaPrueba` es exactamente esa resolución).
  TextColumn get nominaEmpleadoId =>
      text().nullable().references(
        NominaEmpleado,
        #id,
        onDelete: KeyAction.restrict,
      )();

  /// Solo se llena cuando `estatus` pasa a `aplicada` — nunca en
  /// `reservada`.
  DateTimeColumn get fechaAplicacion => dateTime().nullable()();

  @override
  List<String> get customConstraints => [
    'CHECK (numero_cuota > 0)',
    'CHECK (importe_programado > 0)',
  ];
}
