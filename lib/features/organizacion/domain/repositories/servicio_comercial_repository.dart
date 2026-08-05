import 'package:riseg_one/core/database/app_database.dart';

import '../usecases/linea_comercial_con_vigencia.dart';
import '../usecases/linea_comercial_validator.dart';

/// Configuración comercial de Servicio (Etapa 4G.1) — deliberadamente
/// separado de `ServicioRepository`, que ya administra Vinculaciones y
/// Dirección operativa: una línea comercial con su historial de
/// vigencias es un dominio propio, no una columna más de `Servicio`.
abstract interface class ServicioComercialRepository {
  /// Crea la línea y su primera vigencia en una sola transacción — nunca
  /// se crea una línea sin al menos una vigencia (no tendría condiciones
  /// que mostrar).
  Future<({ServicioLineaComercialData linea, ServicioLineaComercialVigenciaData vigencia})> crearLinea({
    required String servicioId,
    required LineaComercialValidada datos,
  });

  /// Todas las líneas comerciales del Servicio (cualquier
  /// `cicloVidaRegistro` de la línea misma — ver la nota en
  /// `ServicioLineaComercial` sobre por qué ese eje casi no se usa), cada
  /// una ya resuelta contra la fecha de hoy (vigente/programadas) y con
  /// el nombre de Puesto/modalidad de turno listo para mostrar.
  Future<List<LineaComercialConVigencia>> listarLineas(String servicioId);
}
