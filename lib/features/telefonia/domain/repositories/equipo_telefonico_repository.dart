import 'package:riseg_one/core/database/app_database.dart';

/// Credencial y bitácora del expediente de un teléfono físico (Etapa
/// 9D) — las dos tablas genuinamente nuevas de esta etapa
/// (`EquipoTelefonicoCredencial`, `EquipoTelefonicoEvento`). Todo lo
/// demás del expediente (marca/modelo/IMEI/estatus/asignación/línea) se
/// lee de Inventario/Telefonía existentes, nunca de aquí — ver
/// `ConfigurarEquipoTelefonicoUseCase` para esa composición cruzada.
///
/// Sin validación de negocio ni cifrado aquí — eso vive en los
/// UseCases (`CambiarContrasenaEquipoTelefonicoUseCase` cifra antes de
/// llamar a `guardarContrasena`; este repositorio solo persiste lo que
/// ya le llega).
abstract interface class EquipoTelefonicoRepository {
  Future<EquipoTelefonicoCredencialData?> obtenerCredencial(String unidadId);

  Future<EquipoTelefonicoCredencialData> guardarCorreo({
    required String unidadId,
    String? correo,
    String? observaciones,
  });

  /// [contrasenaCifrada] ya viene cifrada (autodescriptiva, ver
  /// `CredentialCipher`) — nunca texto plano en este método. Sin
  /// historial de contraseñas anteriores: sobreescribe la vigente.
  Future<EquipoTelefonicoCredencialData> guardarContrasena({
    required String unidadId,
    required String contrasenaCifrada,
    required DateTime fecha,
  });

  Future<void> registrarEvento({
    required String unidadId,
    required String tipoEvento,
    String? actorUsuarioId,
    String? observacion,
  });

  Future<List<EquipoTelefonicoEventoData>> listarEventos(String unidadId);
}
