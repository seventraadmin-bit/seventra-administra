import '../../data/tables/nomina_empleado_table.dart';
import 'calcular_dias_pagables_empleado.dart';

/// Un renglón de Nómina ya calculado, listo para persistirse — puente
/// entre el cálculo (`calcularDiasPagablesEmpleado`) y la escritura
/// (`NominaRepository.guardarRenglon`). `bono` ya viene decidido por el
/// llamador (solo se propone en la Nómina de la segunda quincena,
/// Resolución explícita de Marlon) — nunca lo decide el repositorio.
class FilaNominaGenerada {
  const FilaNominaGenerada({
    required this.empleadoId,
    required this.numeroEmpleado,
    required this.nombreCompleto,
    required this.puestoNombre,
    required this.servicioId,
    required this.servicioNombre,
    required this.turnoNombre,
    required this.bancoNombre,
    required this.numeroCuentaTarjeta,
    required this.clabe,
    required this.fuenteSueldoUtilizada,
    required this.diasPagables,
    required this.sueldoMensualUtilizado,
    required this.importeBase,
    required this.bonoPropuesto,
    required this.tramos,
  });

  final String empleadoId;
  final int numeroEmpleado;
  final String nombreCompleto;
  final String? puestoNombre;
  final String? servicioId;
  final String? servicioNombre;
  final String? turnoNombre;
  final String? bancoNombre;
  final String? numeroCuentaTarjeta;
  final String? clabe;
  final FuenteSueldoNomina fuenteSueldoUtilizada;
  final int diasPagables;
  final int sueldoMensualUtilizado;
  final int importeBase;
  final int bonoPropuesto;
  final List<TramoCalculado> tramos;
}
