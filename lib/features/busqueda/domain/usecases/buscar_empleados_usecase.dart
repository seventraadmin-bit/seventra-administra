import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';

import 'busqueda_utils.dart';
import 'resultado_busqueda_entidad.dart';

/// Busca por nombre/apellidos/número de empleado — nunca CURP/RFC/NSS/
/// bancarios/sueldo/psicológico/socioeconómico/antidoping, mismo
/// criterio de proyección mínima que `EmpleadoReporteRow` (Reportes).
class BuscarEmpleadosUseCase {
  BuscarEmpleadosUseCase(this._empleadoRepository);

  final EmpleadoRepository _empleadoRepository;

  Future<List<ResultadoBusquedaEntidad>> ejecutar(String texto) async {
    final empleados = await _empleadoRepository.listarParaReporte();
    final coincidencias = empleados.where(
      (e) => coincideBusqueda(texto, [e.nombres, e.apellidoPaterno, e.apellidoMaterno, '${e.numeroEmpleado}']),
    );

    return [
      for (final e in coincidencias.take(maximoResultadosPorGrupo))
        ResultadoBusquedaEntidad(
          id: e.id,
          titulo: e.nombreCompleto,
          subtitulo: 'No. ${e.numeroEmpleado}',
          ruta: '/personal/empleados/${e.id}',
        ),
    ];
  }
}
