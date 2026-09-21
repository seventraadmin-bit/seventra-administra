import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/presentation/empleados/empleados_list_screen.dart' show empleadoNombreCompleto;

import 'calcular_ciclo_laboral_empleado.dart';

/// Un EVENTO de baja (Etapa 15, rediseño de Personal/Bajas) — no un
/// Empleado único: si alguien tuvo Ingreso → Baja → Reingreso → Baja,
/// aparecen DOS filas aquí, una por periodo laboral terminado
/// (Resolución explícita de Marlon: "cada fila debe corresponder a un
/// periodo laboral terminado, no a un Empleado único", para que las
/// métricas de rotación sean correctas). [esBajaVigente] distingue la
/// baja actual (el Empleado sigue `estatus == baja`, nunca
/// reingresó — vive en `Empleado` mismo) de una ya archivada en
/// `EmpleadoPeriodoLaboral` tras un Reingreso posterior.
class BajaEvento {
  const BajaEvento({
    required this.empleadoId,
    required this.numeroEmpleado,
    required this.nombreCompleto,
    required this.fechaIngreso,
    required this.fechaBaja,
    required this.motivoBaja,
    this.observacionesBaja,
    this.puestoNombre,
    this.servicioNombre,
    this.turnoNombre,
    required this.esBajaVigente,
  });

  final String empleadoId;
  final int numeroEmpleado;
  final String nombreCompleto;
  final DateTime fechaIngreso;
  final DateTime fechaBaja;
  final String motivoBaja;
  final String? observacionesBaja;
  final String? puestoNombre;
  final String? servicioNombre;
  final String? turnoNombre;
  final bool esBajaVigente;

  /// Permanencia de este periodo — MISMA fórmula que
  /// `calcularCicloLaboralEmpleado` (nunca una fórmula paralela):
  /// `fechaBaja - fechaIngreso` de ESTE periodo laboral, nunca la fecha
  /// de creación del Empleado.
  CicloLaboralEmpleado get permanencia => calcularCicloLaboralDesdeFechas(
        fechaIngreso: fechaIngreso,
        estatus: EstatusEmpleado.baja.name,
        fechaBaja: fechaBaja,
      );

  int get permanenciaDias => permanencia.diasLaborados;

  bool get esRotacionTemprana => permanenciaDias < 30;
}

/// Construye TODOS los eventos de baja de la compañía a partir de los
/// Empleados ya cargados y sus periodos archivados — función pura, sin
/// BD. `periodosPorEmpleado` normalmente viene de
/// `EmpleadoRepository.listarPeriodosLaboralesArchivadosPorEmpleados`.
/// Orden por defecto: fecha de baja más reciente primero (Resolución
/// explícita de Marlon).
List<BajaEvento> construirEventosBaja(
  List<EmpleadoData> empleados,
  Map<String, List<EmpleadoPeriodoLaboralData>> periodosPorEmpleado,
) {
  final eventos = <BajaEvento>[];

  for (final empleado in empleados) {
    if (EstatusEmpleado.values.byName(empleado.estatus) == EstatusEmpleado.baja &&
        empleado.fechaBaja != null &&
        empleado.motivoBaja != null) {
      eventos.add(
        BajaEvento(
          empleadoId: empleado.id,
          numeroEmpleado: empleado.numeroEmpleado,
          nombreCompleto: empleadoNombreCompleto(empleado),
          fechaIngreso: empleado.fechaIngreso,
          fechaBaja: empleado.fechaBaja!,
          motivoBaja: empleado.motivoBaja!,
          observacionesBaja: empleado.observacionesBaja,
          puestoNombre: empleado.puestoNombreBaja,
          servicioNombre: empleado.servicioNombreBaja,
          turnoNombre: empleado.turnoNombreBaja,
          esBajaVigente: true,
        ),
      );
    }

    for (final periodo in periodosPorEmpleado[empleado.id] ?? const <EmpleadoPeriodoLaboralData>[]) {
      eventos.add(
        BajaEvento(
          empleadoId: empleado.id,
          numeroEmpleado: empleado.numeroEmpleado,
          nombreCompleto: empleadoNombreCompleto(empleado),
          fechaIngreso: periodo.fechaIngreso,
          fechaBaja: periodo.fechaBaja,
          motivoBaja: periodo.motivoBaja,
          observacionesBaja: periodo.observacionesBaja,
          puestoNombre: periodo.puestoNombre,
          servicioNombre: periodo.servicioNombre,
          turnoNombre: periodo.turnoNombre,
          esBajaVigente: false,
        ),
      );
    }
  }

  eventos.sort((a, b) => b.fechaBaja.compareTo(a.fechaBaja));
  return eventos;
}
