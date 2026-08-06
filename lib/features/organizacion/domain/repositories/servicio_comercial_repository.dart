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

  /// Igual que `listarLineas`, pero la clasificación vigente/programada
  /// de cada línea se resuelve contra `fecha` en vez de `Clock.now()`
  /// (Etapa 4I.1) — necesario para generar la agenda de un periodo
  /// futuro o pasado usando exactamente la condición comercial que
  /// aplicaba (o aplicará) en esa fecha, no la de hoy.
  Future<List<LineaComercialConVigencia>> listarLineasEnFecha(String servicioId, DateTime fecha);

  /// La línea misma (para resolver su `servicioId`, entre otros usos) —
  /// `null` si no existe.
  Future<ServicioLineaComercialData?> obtenerLinea(String lineaComercialId);

  /// Una vigencia individual por su propio id — `null` si no existe.
  Future<ServicioLineaComercialVigenciaData?> obtenerVigencia(String vigenciaId);

  /// Todas las vigencias de la línea, sin filtrar por `cicloVidaRegistro`
  /// (a diferencia de `listarLineas`) — incluye las canceladas (Etapa
  /// 4G.2), en orden cronológico por `fechaInicioVigencia`. Es la base
  /// del historial de consulta y de las validaciones de encadenamiento
  /// (fecha duplicada, solapamiento).
  Future<List<ServicioLineaComercialVigenciaData>> listarHistorial(String lineaComercialId);

  /// Registra una nueva vigencia — trunca la predecesora (la vigencia
  /// `activo` cuyo rango contiene o antecede a la nueva fecha de inicio)
  /// a `fechaFinVigencia = nueva.fechaInicioVigencia - 1 día`, y si ya
  /// existe una sucesora (`activo`, fecha de inicio posterior), acota
  /// automáticamente la nueva vigencia para no solaparla. Todo en una
  /// sola transacción. Asume `datos` ya validados por
  /// `LineaComercialValidator.validarNuevaVigencia` — este método no
  /// vuelve a validar existencia/duplicados/solapamiento.
  Future<ServicioLineaComercialVigenciaData> cambiarVigencia({
    required String lineaComercialId,
    required LineaComercialValidada datos,
  });

  /// Cierra una vigencia (la vigente actual, ya identificada por el
  /// caso de uso) sin reemplazo — nunca crea una vigencia nueva, solo
  /// fija su `fechaFinVigencia`.
  Future<ServicioLineaComercialVigenciaData> cerrarVigencia({
    required String vigenciaId,
    required DateTime fechaEfectiva,
  });

  /// Cancela una vigencia programada — la marca `archivado` (nunca
  /// vuelve a participar en ningún cálculo ni puede reactivarse) pero
  /// permanece consultable en `listarHistorial` como "Cancelada" (Etapa
  /// 4G.2, Resolución F: la trazabilidad administrativa es más
  /// importante que ocultarla). Repara la predecesora, restaurando su
  /// `fechaFinVigencia` al valor que tenía la cancelada — como si nunca
  /// se hubiera registrado.
  Future<void> cancelarVigenciaProgramada(String vigenciaId);

  /// Edita únicamente descripción/observaciones de una vigencia — nunca
  /// sus condiciones comerciales. No valida si es histórica (eso vive en
  /// el caso de uso).
  Future<ServicioLineaComercialVigenciaData> actualizarAnotaciones({
    required String vigenciaId,
    String? descripcion,
    String? observaciones,
  });
}
