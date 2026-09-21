import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';

import '../repositories/tiempo_extra_repository.dart';

/// KPIs propios de la pantalla "Tiempos Extra" (nunca los mismos que el
/// resumen del Dashboard, aunque comparten la misma fuente) — sobre el
/// rango de fechas filtrado en pantalla.
class ResumenTiemposExtraDetalle {
  const ResumenTiemposExtraDetalle({
    required this.totalRegistros,
    required this.gastoTotal,
    required this.porServicio,
  });

  final int totalRegistros;
  final int gastoTotal;

  /// Ya ordenado descendente por gasto.
  final List<({String servicioId, String servicioNombre, int gastoTotal, int cantidad})> porServicio;
}

class ObtenerResumenTiemposExtraUseCase {
  ObtenerResumenTiemposExtraUseCase(this._repository, this._servicioRepository);

  final TiempoExtraRepository _repository;
  final ServicioRepository _servicioRepository;

  Future<ResumenTiemposExtraDetalle> ejecutar({DateTime? rangoInicio, DateTime? rangoFin}) async {
    final registros = await _repository.listar(rangoInicio: rangoInicio, rangoFin: rangoFin, estatus: 'registrado');
    final costosPorRegistro = await _repository.totalCostosAdicionalesPorTiempoExtra([for (final r in registros) r.id]);

    var gastoTotal = 0;
    final porServicio = <String, ({int gastoTotal, int cantidad})>{};
    for (final r in registros) {
      final total = r.montoTiempoExtra + (costosPorRegistro[r.id] ?? 0);
      gastoTotal += total;
      final previo = porServicio[r.servicioId];
      porServicio[r.servicioId] = (gastoTotal: (previo?.gastoTotal ?? 0) + total, cantidad: (previo?.cantidad ?? 0) + 1);
    }

    // Nombres resueltos en una sola consulta en lote — nunca una
    // consulta por Servicio.
    final servicios = await _servicioRepository.listar();
    final nombrePorServicio = {for (final s in servicios) s.servicio.id: s.servicio.nombre};

    final lista = [
      for (final entrada in porServicio.entries)
        (
          servicioId: entrada.key,
          servicioNombre: nombrePorServicio[entrada.key] ?? '—',
          gastoTotal: entrada.value.gastoTotal,
          cantidad: entrada.value.cantidad,
        ),
    ]..sort((a, b) => b.gastoTotal.compareTo(a.gastoTotal));

    return ResumenTiemposExtraDetalle(totalRegistros: registros.length, gastoTotal: gastoTotal, porServicio: lista);
  }
}
