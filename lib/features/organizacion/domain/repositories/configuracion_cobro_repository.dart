import 'package:riseg_one/core/database/app_database.dart';

import '../usecases/configuracion_cobro_con_vigencia.dart';
import '../usecases/configuracion_cobro_regla_evento_validator.dart';
import '../usecases/configuracion_cobro_validator.dart';

/// Configuración de cobro de un Servicio (Etapa 4H.1, ciclo de
/// vigencias completo desde la Etapa 4H.2) — 1:1, deliberadamente
/// separado de `ServicioComercialRepository`: qué se cobra y cuánto
/// (Configuración comercial) es un dominio distinto de cómo se cobra
/// (Configuración de cobro), aunque ambos se validen cruzadamente.
abstract interface class ConfiguracionCobroRepository {
  /// Crea la configuración y su primera vigencia (con sus correos y
  /// reglas de evento, si los hay) en una sola transacción.
  Future<({ConfiguracionCobroData configuracion, ConfiguracionCobroVigenciaData vigencia})> crearConfiguracion({
    required String servicioId,
    required ConfiguracionCobroValidada datos,
    required List<ReglaEventoValidada> reglas,
  });

  /// La Configuración de cobro del Servicio, ya resuelta contra la fecha
  /// de hoy (vigente/programadas) — `null` si el Servicio todavía no
  /// tiene ninguna.
  Future<ConfiguracionCobroConVigencia?> obtenerConfiguracion(String servicioId);

  /// La Configuración de cobro misma (para resolver su `servicioId`,
  /// entre otros usos) — `null` si no existe. Espejo de
  /// `ServicioComercialRepository.obtenerLinea`.
  Future<ConfiguracionCobroData?> obtenerConfiguracionPorId(String configuracionCobroId);

  /// Una vigencia individual por su propio id — `null` si no existe.
  Future<ConfiguracionCobroVigenciaData?> obtenerVigencia(String vigenciaId);

  /// Todas las vigencias de la configuración, sin filtrar por
  /// `cicloVidaRegistro` — incluye las canceladas (Etapa 4H.2), en
  /// orden cronológico. Base del historial y de las validaciones de
  /// encadenamiento.
  Future<List<ConfiguracionCobroVigenciaData>> listarHistorial(String configuracionCobroId);

  /// Correos de envío de una vigencia específica — cada vigencia tiene
  /// su propia foto de correos, igual que sus reglas de evento.
  Future<List<String>> listarCorreos(String vigenciaId);

  /// Reglas de evento de una vigencia específica (Etapa 4H.2).
  Future<List<ConfiguracionCobroReglaEventoData>> listarReglas(String vigenciaId);

  /// Registra una nueva vigencia — mismo algoritmo único de
  /// predecesora/sucesora que `ServicioComercialRepository.cambiarVigencia`
  /// (Etapa 4G.2), aplicado aquí: trunca la predecesora, acota contra la
  /// sucesora si existe, todo en una transacción. Asume `datos`/`reglas`
  /// ya validados.
  Future<ConfiguracionCobroVigenciaData> cambiarVigencia({
    required String configuracionCobroId,
    required ConfiguracionCobroValidada datos,
    required List<ReglaEventoValidada> reglas,
  });

  /// Cierra sin reemplazo la vigencia vigente actual.
  Future<ConfiguracionCobroVigenciaData> cerrarVigencia({
    required String vigenciaId,
    required DateTime fechaEfectiva,
  });

  /// Cancela una vigencia programada — la marca `archivado` y repara la
  /// predecesora, restaurando su `fechaFinVigencia` original (Etapa
  /// 4G.2, Resolución F, aplicada aquí igual).
  Future<void> cancelarVigenciaProgramada(String vigenciaId);

  /// Edita únicamente `observaciones` de una vigencia — nunca sus
  /// condiciones ni sus reglas de evento (Configuración de cobro no
  /// tiene un campo `descripcion` propio como sí lo tiene línea
  /// comercial).
  Future<ConfiguracionCobroVigenciaData> actualizarObservaciones({
    required String vigenciaId,
    String? observaciones,
  });

  /// La vigencia `activo` efectiva en `fecha` — distinto de "vigente
  /// hoy" (Etapa 4I.1): busca por rango de fechas propio de cada
  /// vigencia, nunca por `Clock.now()`. Es lo que permite que generar la
  /// agenda de enero use la vigencia nueva y la de diciembre conserve la
  /// anterior, sin importar qué día se ejecute la generación. `null` si
  /// ninguna vigencia cubre esa fecha.
  Future<ConfiguracionCobroVigenciaData?> obtenerVigenciaEnFecha(String configuracionCobroId, DateTime fecha);

  /// Todas las Configuraciones de cobro del sistema, opcionalmente
  /// acotadas por Cliente o Servicio — insumo de `GenerarAgendaUseCase`
  /// para enumerar candidatos sin que el caso de uso conozca el detalle
  /// de cómo se relacionan Servicio/Cliente.
  Future<List<ConfiguracionCobroData>> listarConfiguraciones({String? clienteId, String? servicioId});
}
