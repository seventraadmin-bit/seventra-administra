import 'package:riseg_one/features/personal/domain/repositories/asignacion_servicio_repository.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';

/// Par id/nombre mínimo para el picker de "empleado responsable" de un
/// `DescuentoInventario` — la UI de Inventario (diálogos/secciones)
/// nunca conoce el tipo real `EmpleadoData`; solo consume este par ya
/// resuelto, siempre a través de
/// `ObtenerEmpleadosResponsablesServicioUseCase`.
class EmpleadoOpcion {
  const EmpleadoOpcion({required this.id, required this.nombre});
  final String id;
  final String nombre;
}

/// Candidatos a "empleado responsable" cuando se reporta daño/pérdida
/// de un bien de Inventario asignado a un Servicio (Etapa 7B, ajuste
/// de cierre) — el personal actualmente asignado a ese Servicio vía
/// `AsignacionServicio`.
///
/// Dependencia cruzada al dominio `personal` (lectura, vía
/// constructor) — mismo patrón exacto ya establecido por
/// `ObtenerExpedienteServicioUseCase` (Organización), que inyecta
/// estos mismos dos repositorios para la sección "Personal asignado"
/// del expediente de Servicio. Vive en Inventario (no en Organización
/// ni en Personal) porque "a quién atribuirle un descuento de
/// Inventario" es una pregunta de Inventario, no de esos otros
/// dominios — la UI de Inventario (`InventarioAsignadoServicioSection`
/// y los diálogos de cierre/reemplazo) solo conoce este caso de uso,
/// nunca los repositorios de Personal directamente.
class ObtenerEmpleadosResponsablesServicioUseCase {
  ObtenerEmpleadosResponsablesServicioUseCase(this._asignacionServicioRepository, this._empleadoRepository);

  final AsignacionServicioRepository _asignacionServicioRepository;
  final EmpleadoRepository _empleadoRepository;

  Future<List<EmpleadoOpcion>> ejecutar(String servicioId) async {
    final asignaciones = await _asignacionServicioRepository.listarActivasPorServicio(servicioId);
    final opciones = <EmpleadoOpcion>[];
    for (final asignacion in asignaciones) {
      final empleado = await _empleadoRepository.obtenerPorId(asignacion.empleadoId);
      if (empleado == null) continue;
      final nombre = [empleado.nombres, empleado.apellidoPaterno, empleado.apellidoMaterno]
          .whereType<String>()
          .where((p) => p.trim().isNotEmpty)
          .join(' ');
      opciones.add(EmpleadoOpcion(id: empleado.id, nombre: nombre));
    }
    return opciones;
  }
}
