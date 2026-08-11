import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';

import '../repositories/equipo_telefonico_repository.dart';
import '../tipo_evento_equipo_telefonico.dart';

sealed class ActualizarCorreoEquipoTelefonicoResultado {}

class ActualizarCorreoEquipoTelefonicoExitoso extends ActualizarCorreoEquipoTelefonicoResultado {
  ActualizarCorreoEquipoTelefonicoExitoso(this.credencial);
  final EquipoTelefonicoCredencialData credencial;
}

class ActualizarCorreoEquipoTelefonicoUnidadNoExiste extends ActualizarCorreoEquipoTelefonicoResultado {}

class ActualizarCorreoEquipoTelefonicoErrorInesperado extends ActualizarCorreoEquipoTelefonicoResultado {
  ActualizarCorreoEquipoTelefonicoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Correo/observaciones de configuración de la credencial de un
/// teléfono (Etapa 9D) — nunca la contraseña, eso vive en
/// `CambiarContrasenaEquipoTelefonicoUseCase`. Gateado por
/// `telefonia.modificar` en la fachada (no `telefonia.verCredenciales`
/// — ese permiso es solo para REVELAR el secreto, no para escribir
/// datos de contacto no sensibles).
class ActualizarCorreoEquipoTelefonicoUseCase {
  ActualizarCorreoEquipoTelefonicoUseCase(this._inventarioRepository, this._equipoRepository);

  final InventarioRepository _inventarioRepository;
  final EquipoTelefonicoRepository _equipoRepository;

  Future<ActualizarCorreoEquipoTelefonicoResultado> ejecutar({
    required String unidadId,
    String? correo,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    final unidad = await _inventarioRepository.obtenerUnidadPorId(unidadId);
    if (unidad == null) return ActualizarCorreoEquipoTelefonicoUnidadNoExiste();

    try {
      final correoLimpio = (correo?.trim().isEmpty ?? true) ? null : correo!.trim();
      final observacionesLimpias = (observaciones?.trim().isEmpty ?? true) ? null : observaciones!.trim();

      final credencial = await _equipoRepository.guardarCorreo(
        unidadId: unidadId,
        correo: correoLimpio,
        observaciones: observacionesLimpias,
      );
      await _equipoRepository.registrarEvento(
        unidadId: unidadId,
        tipoEvento: TipoEventoEquipoTelefonico.correoActualizado.name,
        actorUsuarioId: actorUsuarioId,
        observacion: correoLimpio == null ? 'Correo eliminado.' : 'Correo actualizado a $correoLimpio.',
      );
      return ActualizarCorreoEquipoTelefonicoExitoso(credencial);
    } catch (e) {
      return ActualizarCorreoEquipoTelefonicoErrorInesperado(e.toString());
    }
  }
}
