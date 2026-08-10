import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';

/// Par id/nombre mínimo para el selector "asignar a un Empleado" — la
/// UI de Vehículos nunca conoce el tipo real `EmpleadoData`, siempre
/// vía `ObtenerOpcionesAsignacionVehiculoUseCase`. Clase propia de
/// Vehículos (no se reutiliza `EmpleadoOpcion` de Inventario, aunque
/// tenga la misma forma) — son dominios distintos, cada uno con su
/// propio contrato hacia Personal.
class EmpleadoOpcionVehiculo {
  const EmpleadoOpcionVehiculo({required this.id, required this.nombre});
  final String id;
  final String nombre;
}

class ServicioOpcionVehiculo {
  const ServicioOpcionVehiculo({required this.id, required this.nombre});
  final String id;
  final String nombre;
}

/// Candidatos para "asignar a" (Etapa 8B) — todos los Empleados y
/// Servicios activos, sin filtrar (a diferencia de
/// `ObtenerEmpleadosResponsablesServicioUseCase` de Inventario, que
/// solo lista el personal ya asignado a un Servicio: aquí cualquier
/// Empleado/Servicio activo puede recibir un Vehículo).
///
/// Dependencia cruzada a `personal`/`organizacion` (lectura) — mismo
/// patrón ya establecido por `ObtenerEmpleadosResponsablesServicioUseCase`/
/// `BuscarInventarioUseCase`: vive en Vehículos porque "a quién se le
/// puede asignar un vehículo" es una pregunta de Vehículos, la UI
/// nunca importa los repositorios de Personal/Organización
/// directamente.
class ObtenerOpcionesAsignacionVehiculoUseCase {
  ObtenerOpcionesAsignacionVehiculoUseCase(this._empleadoRepository, this._servicioRepository);

  final EmpleadoRepository _empleadoRepository;
  final ServicioRepository _servicioRepository;

  Future<List<EmpleadoOpcionVehiculo>> obtenerEmpleados() async {
    final empleados = await _empleadoRepository.listar();
    return [
      for (final e in empleados)
        EmpleadoOpcionVehiculo(
          id: e.id,
          nombre: [e.nombres, e.apellidoPaterno, e.apellidoMaterno]
              .whereType<String>()
              .where((p) => p.trim().isNotEmpty)
              .join(' '),
        ),
    ];
  }

  Future<List<ServicioOpcionVehiculo>> obtenerServicios() async {
    final servicios = await _servicioRepository.listar();
    return [for (final s in servicios) ServicioOpcionVehiculo(id: s.servicio.id, nombre: s.servicio.nombre)];
  }
}
