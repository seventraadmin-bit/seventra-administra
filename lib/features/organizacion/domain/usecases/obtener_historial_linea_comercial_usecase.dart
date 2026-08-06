import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/utils/clock.dart';

import '../repositories/catalogo_repository.dart';
import '../repositories/puesto_repository.dart';
import '../repositories/servicio_comercial_repository.dart';
import 'linea_comercial_con_vigencia.dart';

/// Una fila del historial de una línea comercial, ya resuelta contra la
/// fecha de hoy y con nombres listos para mostrar — incluye vigencias
/// canceladas (Etapa 4G.2, Resolución F), a diferencia de
/// `LineaComercialConVigencia` (que solo ve la vigente/programadas para
/// cálculos).
class VigenciaHistorial {
  const VigenciaHistorial({
    required this.vigencia,
    required this.estado,
    required this.puestoNombre,
    required this.modalidadTurnoNombre,
  });

  final ServicioLineaComercialVigenciaData vigencia;
  final EstadoVigencia estado;
  final String puestoNombre;
  final String modalidadTurnoNombre;
}

/// Consulta de solo lectura de todo el historial de una línea —
/// cronológico, con la clasificación de 4 estados (vigente/programada/
/// histórica/cancelada) que el historial necesita mostrar.
class ObtenerHistorialLineaComercialUseCase {
  ObtenerHistorialLineaComercialUseCase(
    this._repository,
    this._puestoRepository,
    this._catalogoRepository,
    this._clock,
  );

  final ServicioComercialRepository _repository;
  final PuestoRepository _puestoRepository;
  final CatalogoRepository _catalogoRepository;
  final Clock _clock;

  Future<List<VigenciaHistorial>> ejecutar(String lineaComercialId) async {
    final historial = await _repository.listarHistorial(lineaComercialId);
    final hoy = _clock.now();
    final modalidades = await _catalogoRepository.listarModalidadesTurno();

    final resultado = <VigenciaHistorial>[];
    for (final v in historial) {
      final puesto = await _puestoRepository.obtenerPorId(v.puestoId);
      CatalogoItem? modalidad;
      for (final m in modalidades) {
        if (m.id == v.modalidadTurnoId) {
          modalidad = m;
          break;
        }
      }

      resultado.add(
        VigenciaHistorial(
          vigencia: v,
          estado: clasificarParaHistorial(v, hoy),
          puestoNombre: puesto?.nombre ?? '',
          modalidadTurnoNombre: modalidad?.nombre ?? '',
        ),
      );
    }

    return resultado;
  }
}
