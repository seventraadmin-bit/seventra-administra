import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart' show TipoPuesto;
import 'package:riseg_one/features/organizacion/domain/repositories/puesto_repository.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart' show EstatusEmpleado;

import '../plantilla_personal.dart';
import '../repositories/asignacion_servicio_repository.dart';
import '../repositories/empleado_repository.dart';

/// Fuente de verdad ÚNICA de la composición de la plantilla activa
/// (Etapa "Plantilla operativa vs. administrativa") — Dashboard,
/// Personal y Reportes la consumen; ninguno reimplementa la regla.
///
/// Es un SNAPSHOT: responde "cómo está la plantilla HOY", nunca "cómo
/// estuvo durante un periodo". Las métricas de periodo (altas, bajas,
/// rotación) viven en `ObtenerRotacionPersonalUseCase`, separadas a
/// propósito para no mezclar las dos semánticas.
///
/// Tres consultas fijas, sin N+1: todos los empleados activos, todas
/// las asignaciones vigentes y el catálogo de puestos.
class ObtenerPlantillaPersonalUseCase {
  ObtenerPlantillaPersonalUseCase(
    this._empleadoRepository,
    this._asignacionServicioRepository,
    this._puestoRepository,
  );

  final EmpleadoRepository _empleadoRepository;
  final AsignacionServicioRepository _asignacionServicioRepository;
  final PuestoRepository _puestoRepository;

  Future<PlantillaPersonalResumen> ejecutar() async {
    final activos = await _empleadoRepository.listar(estatus: EstatusEmpleado.activo.name);
    final asignacionesVigentes = await _asignacionServicioRepository.listarTodasActivas();
    // `listarActivos` basta: un Puesto archivado ya no se asigna, y un
    // empleado que conserve uno archivado cae en "plantilla
    // desconocida" en vez de clasificarse con un catálogo retirado.
    final puestos = await _puestoRepository.listarActivos();

    final servicioPorEmpleado = {for (final a in asignacionesVigentes) a.empleadoId: a.servicioId};
    final tipoPorPuesto = <String, TipoPuesto>{};
    for (final p in puestos) {
      final tipo = TipoPuesto.values.where((t) => t.name == p.tipo).firstOrNull;
      if (tipo != null) tipoPorPuesto[p.id] = tipo;
    }

    return PlantillaPersonalResumen(
      clasificaciones: [
        for (final empleado in activos)
          clasificarEmpleado(
            empleado: empleado,
            servicioIdVigente: servicioPorEmpleado[empleado.id],
            tipoPuesto: empleado.puestoId == null ? null : tipoPorPuesto[empleado.puestoId],
          ),
      ],
    );
  }
}
