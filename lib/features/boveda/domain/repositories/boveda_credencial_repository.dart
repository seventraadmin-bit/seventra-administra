import 'package:riseg_one/core/database/app_database.dart';

/// Credenciales internas de la Bóveda de Accesos del Maestro (Etapa
/// 14D) y su bitácora — las dos tablas genuinamente nuevas de esta
/// etapa (`BovedaCredencial`, `BovedaCredencialEvento`).
///
/// Sin validación de negocio ni cifrado aquí — eso vive en los
/// UseCases (`CambiarSecretoCredencialBovedaUseCase` cifra antes de
/// llamar a [cambiarSecreto]; este repositorio solo persiste lo que ya
/// le llega).
abstract interface class BovedaCredencialRepository {
  Future<BovedaCredencialData?> obtenerPorId(String id);

  Future<List<BovedaCredencialData>> listar({String? tipo, bool? soloActivos, String? texto});

  Future<BovedaCredencialData> crear({
    required String nombre,
    required String tipo,
    String? usuarioAcceso,
    String? correo,
    String? secretoCifrado,
    DateTime? fechaActualizacionSecreto,
    String? url,
    String? observaciones,
  });

  /// Nunca toca el secreto — ver [cambiarSecreto].
  Future<BovedaCredencialData> actualizar({
    required String id,
    required String nombre,
    required String tipo,
    String? usuarioAcceso,
    String? correo,
    String? url,
    String? observaciones,
    bool limpiarUsuarioAcceso = false,
    bool limpiarCorreo = false,
    bool limpiarUrl = false,
    bool limpiarObservaciones = false,
  });

  /// [secretoCifrado] ya viene cifrado (autodescriptivo, ver
  /// `CredentialCipher`) o `null` para limpiarlo — nunca texto plano en
  /// este método. Sin historial de secretos anteriores: sobreescribe el
  /// vigente.
  Future<BovedaCredencialData> cambiarSecreto({required String id, String? secretoCifrado, required DateTime fecha});

  Future<BovedaCredencialData> darDeBaja(String id);

  Future<BovedaCredencialData> reactivar(String id);

  Future<void> registrarEvento({
    required String credencialId,
    required String tipoEvento,
    String? actorUsuarioId,
    String? observacion,
  });

  Future<List<BovedaCredencialEventoData>> listarEventos(String credencialId);
}
