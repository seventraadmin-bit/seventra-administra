import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/security/credential_cipher.dart';
import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';

import '../repositories/equipo_telefonico_repository.dart';
import '../tipo_evento_equipo_telefonico.dart';

sealed class CambiarContrasenaEquipoTelefonicoResultado {}

class CambiarContrasenaEquipoTelefonicoExitoso extends CambiarContrasenaEquipoTelefonicoResultado {
  CambiarContrasenaEquipoTelefonicoExitoso(this.credencial);
  final EquipoTelefonicoCredencialData credencial;
}

class CambiarContrasenaEquipoTelefonicoUnidadNoExiste extends CambiarContrasenaEquipoTelefonicoResultado {}

class CambiarContrasenaEquipoTelefonicoContrasenaRequerida extends CambiarContrasenaEquipoTelefonicoResultado {}

class CambiarContrasenaEquipoTelefonicoErrorInesperado extends CambiarContrasenaEquipoTelefonicoResultado {
  CambiarContrasenaEquipoTelefonicoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cambia la contraseña de la cuenta de un teléfono (Etapa 9D) —
/// **cifra antes de persistir**, nunca guarda texto plano. Sin
/// historial de contraseñas anteriores (pedido explícito de Marlon):
/// `guardarContrasena` sobreescribe la vigente. Gateado por
/// `telefonia.modificar` en la fachada — rotar la contraseña es una
/// escritura normal, no requiere `telefonia.verCredenciales` (ese
/// permiso es solo para REVELAR la vigente, no para reemplazarla).
class CambiarContrasenaEquipoTelefonicoUseCase {
  CambiarContrasenaEquipoTelefonicoUseCase(this._inventarioRepository, this._equipoRepository, this._cipher);

  final InventarioRepository _inventarioRepository;
  final EquipoTelefonicoRepository _equipoRepository;
  final CredentialCipher _cipher;

  Future<CambiarContrasenaEquipoTelefonicoResultado> ejecutar({
    required String unidadId,
    required String contrasena,
    String? actorUsuarioId,
  }) async {
    final unidad = await _inventarioRepository.obtenerUnidadPorId(unidadId);
    if (unidad == null) return CambiarContrasenaEquipoTelefonicoUnidadNoExiste();
    if (contrasena.isEmpty) return CambiarContrasenaEquipoTelefonicoContrasenaRequerida();

    try {
      final cifrada = await _cipher.cifrar(contrasena);
      final ahora = DateTime.now();
      final credencial = await _equipoRepository.guardarContrasena(
        unidadId: unidadId,
        contrasenaCifrada: cifrada,
        fecha: ahora,
      );
      await _equipoRepository.registrarEvento(
        unidadId: unidadId,
        tipoEvento: TipoEventoEquipoTelefonico.contrasenaActualizada.name,
        actorUsuarioId: actorUsuarioId,
      );
      return CambiarContrasenaEquipoTelefonicoExitoso(credencial);
    } catch (e) {
      return CambiarContrasenaEquipoTelefonicoErrorInesperado(e.toString());
    }
  }
}
