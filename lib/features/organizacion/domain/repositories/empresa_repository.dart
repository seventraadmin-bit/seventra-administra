import 'package:riseg_one/core/database/app_database.dart';

/// Acceso a la Empresa operadora de RISEG ONE.
///
/// Encapsula el invariante de singleton: [obtenerActiva] siempre espera
/// exactamente una fila con `cicloVidaRegistro = activo` (garantizado a
/// nivel de base por un índice único parcial) — si no hay ninguna o hay
/// más de una, es una violación del invariante y debe fallar de forma
/// ruidosa, nunca elegir en silencio.
abstract interface class EmpresaRepository {
  Future<EmpresaData> obtenerActiva();

  Future<void> actualizarDatosGenerales(EmpresaCompanion cambios);

  /// Impide archivar la única Empresa activa — no existe todavía una
  /// operación administrativa que permita reemplazarla, así que esta es
  /// la única forma de dar de baja una Empresa en esta etapa.
  Future<void> archivar(String id);
}
