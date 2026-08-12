import 'package:riseg_one/features/inventario/domain/repositories/asignacion_repository.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';

/// Un Empleado actualmente de baja que todavía tiene custodia de
/// Inventario activa — Etapa 13 (Dashboard). No existía ninguna
/// consulta que cruzara esto antes; compone dos repositorios ya
/// existentes por `empleadoId`, sin tabla ni columna nueva.
class EmpleadoConAsignacionesPendientes {
  const EmpleadoConAsignacionesPendientes({required this.empleado, required this.cantidadAsignaciones});

  final EmpleadoReporteRow empleado;
  final int cantidadAsignaciones;
}

/// Compone `EmpleadoRepository.listarParaReporte(estatus:'baja')` +
/// `AsignacionRepository.listarTodasActivas()` (ambos ya existentes,
/// ya usados por Reportes 12B/12C) — solo cruza por `empleadoId`, sin
/// N+1 (una sola pasada de lectura por repositorio).
class ObtenerEmpleadosBajaConPendienteUseCase {
  ObtenerEmpleadosBajaConPendienteUseCase(this._empleadoRepository, this._asignacionRepository);

  final EmpleadoRepository _empleadoRepository;
  final AsignacionRepository _asignacionRepository;

  Future<List<EmpleadoConAsignacionesPendientes>> ejecutar() async {
    final bajas = await _empleadoRepository.listarParaReporte(estatus: 'baja');
    if (bajas.isEmpty) return const [];

    final asignacionesActivas = await _asignacionRepository.listarTodasActivas();
    final cantidadPorEmpleado = <String, int>{};
    for (final asignacion in asignacionesActivas) {
      final empleadoId = asignacion.empleadoId;
      if (empleadoId == null) continue;
      cantidadPorEmpleado[empleadoId] = (cantidadPorEmpleado[empleadoId] ?? 0) + 1;
    }

    return [
      for (final empleado in bajas)
        if (cantidadPorEmpleado[empleado.id] case final cantidad?)
          EmpleadoConAsignacionesPendientes(empleado: empleado, cantidadAsignaciones: cantidad),
    ];
  }
}
