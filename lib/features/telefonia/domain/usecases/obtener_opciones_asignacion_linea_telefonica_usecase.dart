import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';

/// Par id/nombre mínimo para el selector "asignar a un Empleado" — la
/// UI de Telefonía nunca conoce el tipo real `EmpleadoData`, siempre
/// vía este caso de uso. Clase propia de Telefonía, mismo criterio que
/// `EmpleadoOpcionVehiculo` (cada dominio con su propio contrato hacia
/// Personal, aunque tengan la misma forma).
class EmpleadoOpcionLineaTelefonica {
  const EmpleadoOpcionLineaTelefonica({required this.id, required this.nombre});
  final String id;
  final String nombre;
}

class ServicioOpcionLineaTelefonica {
  const ServicioOpcionLineaTelefonica({required this.id, required this.nombre});
  final String id;
  final String nombre;
}

/// Candidatos para "asignar a" (Etapa 9B) — todos los Empleados y
/// Servicios activos, sin filtrar. Dependencia cruzada a `personal`/
/// `organizacion` (lectura) — mismo patrón ya establecido por
/// `ObtenerOpcionesAsignacionVehiculoUseCase`: vive en Telefonía, la UI
/// nunca importa los repositorios de Personal/Organización
/// directamente.
class ObtenerOpcionesAsignacionLineaTelefonicaUseCase {
  ObtenerOpcionesAsignacionLineaTelefonicaUseCase(this._empleadoRepository, this._servicioRepository);

  final EmpleadoRepository _empleadoRepository;
  final ServicioRepository _servicioRepository;

  Future<List<EmpleadoOpcionLineaTelefonica>> obtenerEmpleados() async {
    final empleados = await _empleadoRepository.listar();
    return [
      for (final e in empleados)
        EmpleadoOpcionLineaTelefonica(
          id: e.id,
          nombre: [e.nombres, e.apellidoPaterno, e.apellidoMaterno]
              .whereType<String>()
              .where((p) => p.trim().isNotEmpty)
              .join(' '),
        ),
    ];
  }

  Future<List<ServicioOpcionLineaTelefonica>> obtenerServicios() async {
    final servicios = await _servicioRepository.listar();
    return [for (final s in servicios) ServicioOpcionLineaTelefonica(id: s.servicio.id, nombre: s.servicio.nombre)];
  }
}
