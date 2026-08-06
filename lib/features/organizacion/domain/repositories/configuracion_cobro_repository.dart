import 'package:riseg_one/core/database/app_database.dart';

import '../usecases/configuracion_cobro_con_vigencia.dart';
import '../usecases/configuracion_cobro_validator.dart';

/// Configuración de cobro de un Servicio (Etapa 4H.1) — 1:1, deliberadamente
/// separado de `ServicioComercialRepository`: qué se cobra y cuánto
/// (Configuración comercial) es un dominio distinto de cómo se cobra
/// (Configuración de cobro), aunque ambos se validen cruzadamente.
abstract interface class ConfiguracionCobroRepository {
  /// Crea la configuración y su primera vigencia (con sus correos, si
  /// los hay) en una sola transacción.
  Future<({ConfiguracionCobroData configuracion, ConfiguracionCobroVigenciaData vigencia})> crearConfiguracion({
    required String servicioId,
    required ConfiguracionCobroValidada datos,
  });

  /// La Configuración de cobro del Servicio, ya resuelta contra la fecha
  /// de hoy (vigente/programadas) — `null` si el Servicio todavía no
  /// tiene ninguna.
  Future<ConfiguracionCobroConVigencia?> obtenerConfiguracion(String servicioId);
}
