import 'package:riseg_one/core/security/credential_cipher.dart';
import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';

import '../repositories/equipo_telefonico_repository.dart';
import '../tipo_evento_equipo_telefonico.dart';

/// Qué acción del usuario disparó la revelación — cada una registra su
/// propio `tipoEvento` (punto 4/11 de la Etapa 9D: "mostrar o copiar
/// una contraseña sea una acción auditable" — ambas por separado, no
/// una sola "reveló").
enum AccionRevelacionCredencial { mostrar, copiar }

sealed class RevelarCredencialEquipoTelefonicoResultado {}

class RevelarCredencialEquipoTelefonicoExitoso extends RevelarCredencialEquipoTelefonicoResultado {
  RevelarCredencialEquipoTelefonicoExitoso(this.contrasena);

  /// Texto plano, transitorio — solo vive en memoria el tiempo que la
  /// UI lo necesite (mostrar en pantalla o copiar al portapapeles);
  /// nunca se persiste ni se registra en el evento de auditoría.
  final String contrasena;
}

class RevelarCredencialEquipoTelefonicoSinContrasena extends RevelarCredencialEquipoTelefonicoResultado {}

/// La clave de cifrado de este equipo no está disponible: el dato
/// viaja cifrado dentro de la base, pero la llave vive en el Almacén de
/// Credenciales de Windows y no forma parte de ningún respaldo. Es lo
/// que ocurre al restaurar en otra computadora. No es corrupción: es
/// información que aquí no puede recuperarse, y hay que capturarla de
/// nuevo.
class RevelarCredencialEquipoTelefonicoClaveNoDisponible extends RevelarCredencialEquipoTelefonicoResultado {}

class RevelarCredencialEquipoTelefonicoErrorInesperado extends RevelarCredencialEquipoTelefonicoResultado {
  RevelarCredencialEquipoTelefonicoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Descifra la contraseña vigente de un teléfono para mostrarla o
/// copiarla (Etapa 9D) — gateado exclusivamente por
/// `telefonia.verCredenciales` en la fachada (nunca `telefonia.ver`
/// solo, ver punto 4: "un usuario puede tener permiso para ver
/// Telefonía y NO tener permiso para revelar/copiar contraseñas").
/// Cada llamada (mostrar o copiar) descifra de nuevo y registra su
/// propio evento — nunca se reutiliza un texto plano ya descifrado
/// entre las dos acciones, para minimizar cuánto tiempo vive el
/// secreto en memoria.
class RevelarCredencialEquipoTelefonicoUseCase {
  RevelarCredencialEquipoTelefonicoUseCase(this._inventarioRepository, this._equipoRepository, this._cipher);

  final InventarioRepository _inventarioRepository;
  final EquipoTelefonicoRepository _equipoRepository;
  final CredentialCipher _cipher;

  Future<RevelarCredencialEquipoTelefonicoResultado> ejecutar({
    required String unidadId,
    required AccionRevelacionCredencial accion,
    String? actorUsuarioId,
  }) async {
    final unidad = await _inventarioRepository.obtenerUnidadPorId(unidadId);
    if (unidad == null) return RevelarCredencialEquipoTelefonicoErrorInesperado('El equipo no existe.');

    final credencial = await _equipoRepository.obtenerCredencial(unidadId);
    final cifrada = credencial?.contrasenaCifrada;
    if (cifrada == null) return RevelarCredencialEquipoTelefonicoSinContrasena();

    try {
      final contrasena = await _cipher.descifrar(cifrada);
      final tipoEvento = switch (accion) {
        AccionRevelacionCredencial.mostrar => TipoEventoEquipoTelefonico.contrasenaRevelada,
        AccionRevelacionCredencial.copiar => TipoEventoEquipoTelefonico.contrasenaCopiada,
      };
      await _equipoRepository.registrarEvento(
        unidadId: unidadId,
        tipoEvento: tipoEvento.name,
        actorUsuarioId: actorUsuarioId,
      );
      return RevelarCredencialEquipoTelefonicoExitoso(contrasena);
    } on ClaveCifradoNoDisponible {
      // Deliberadamente ANTES del catch general: no es un fallo
      // inesperado, es una respuesta del dominio.
      return RevelarCredencialEquipoTelefonicoClaveNoDisponible();
    } catch (e) {
      return RevelarCredencialEquipoTelefonicoErrorInesperado(e.toString());
    }
  }
}
