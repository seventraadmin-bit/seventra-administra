import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';

/// Par id/nombre mínimo para el selector de nuevo responsable — la UI
/// de Inventario nunca conoce el tipo real `EmpleadoData`, siempre vía
/// este caso de uso. Clase propia (no `EmpleadoOpcion` de
/// `obtener_empleados_responsables_servicio_usecase.dart`, que está
/// acotada a un Servicio en particular — aquí se listan todos).
class EmpleadoOpcionResponsable {
  const EmpleadoOpcionResponsable({required this.id, required this.nombre});
  final String id;
  final String nombre;
}

class ServicioOpcionResponsable {
  const ServicioOpcionResponsable({required this.id, required this.nombre});
  final String id;
  final String nombre;
}

/// Candidatos a nuevo responsable al "cambiar responsable" de una
/// `Asignacion` (Etapa 9D, ajuste aprobado por Marlon) — todos los
/// Empleados y Servicios, sin acotar a uno en particular. Dependencia
/// cruzada a `personal`/`organizacion` (lectura), mismo patrón ya
/// establecido por `ObtenerOpcionesAsignacionLineaTelefonicaUseCase`
/// (Telefonía) y `ObtenerEmpleadosResponsablesServicioUseCase`
/// (Inventario, acotado).
class ObtenerOpcionesResponsableAsignacionUseCase {
  ObtenerOpcionesResponsableAsignacionUseCase(this._empleadoRepository, this._servicioRepository);

  final EmpleadoRepository _empleadoRepository;
  final ServicioRepository _servicioRepository;

  Future<List<EmpleadoOpcionResponsable>> obtenerEmpleados() async {
    final empleados = await _empleadoRepository.listar();
    return [
      for (final e in empleados)
        EmpleadoOpcionResponsable(
          id: e.id,
          nombre: [e.nombres, e.apellidoPaterno, e.apellidoMaterno]
              .whereType<String>()
              .where((p) => p.trim().isNotEmpty)
              .join(' '),
        ),
    ];
  }

  Future<List<ServicioOpcionResponsable>> obtenerServicios() async {
    final servicios = await _servicioRepository.listar();
    return [for (final s in servicios) ServicioOpcionResponsable(id: s.servicio.id, nombre: s.servicio.nombre)];
  }
}
