import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/utils/clock.dart';

import '../repositories/catalogo_repository.dart';
import '../repositories/configuracion_cobro_repository.dart';
import '../repositories/entidad_fiscal_repository.dart';
import 'configuracion_cobro_con_vigencia.dart';

/// Una fila del historial de una Configuración de cobro, ya resuelta
/// contra la fecha de hoy y con nombres/reglas listos para mostrar —
/// incluye vigencias canceladas (Etapa 4H.2, mismo criterio que
/// `VigenciaHistorial` de línea comercial).
class VigenciaHistorialCobro {
  const VigenciaHistorialCobro({
    required this.vigencia,
    required this.estado,
    required this.correos,
    required this.reglasEventos,
    this.entidadFiscalRazonSocial,
    this.frecuenciaNombre,
  });

  final ConfiguracionCobroVigenciaData vigencia;
  final EstadoVigenciaCobro estado;
  final List<String> correos;
  final List<ConfiguracionCobroReglaEventoData> reglasEventos;
  final String? entidadFiscalRazonSocial;
  final String? frecuenciaNombre;
}

/// Consulta de solo lectura de todo el historial de una Configuración
/// de cobro — cronológico, con la clasificación de 4 estados (Etapa
/// 4H.2, mismo criterio que `ObtenerHistorialLineaComercialUseCase`).
class ObtenerHistorialConfiguracionCobroUseCase {
  ObtenerHistorialConfiguracionCobroUseCase(
    this._repository,
    this._entidadFiscalRepository,
    this._catalogoRepository,
    this._clock,
  );

  final ConfiguracionCobroRepository _repository;
  final EntidadFiscalRepository _entidadFiscalRepository;
  final CatalogoRepository _catalogoRepository;
  final Clock _clock;

  Future<List<VigenciaHistorialCobro>> ejecutar(String configuracionCobroId) async {
    final historial = await _repository.listarHistorial(configuracionCobroId);
    final hoy = _clock.now();
    final frecuencias = await _catalogoRepository.listarFrecuenciasCobro();

    final resultado = <VigenciaHistorialCobro>[];
    for (final v in historial) {
      final correos = await _repository.listarCorreos(v.id);
      final reglas = await _repository.listarReglas(v.id);

      String? entidadFiscalRazonSocial;
      final entidadFiscalId = v.entidadFiscalId;
      if (entidadFiscalId != null) {
        final entidad = await _entidadFiscalRepository.obtenerPorId(entidadFiscalId);
        entidadFiscalRazonSocial = entidad?.razonSocial;
      }

      CatalogoItem? frecuencia;
      for (final f in frecuencias) {
        if (f.id == v.frecuenciaId) {
          frecuencia = f;
          break;
        }
      }

      resultado.add(
        VigenciaHistorialCobro(
          vigencia: v,
          estado: clasificarParaHistorialCobro(v, hoy),
          correos: correos,
          reglasEventos: reglas,
          entidadFiscalRazonSocial: entidadFiscalRazonSocial,
          frecuenciaNombre: frecuencia?.nombre,
        ),
      );
    }

    return resultado;
  }
}
