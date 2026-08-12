import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/boveda_credencial_repository.dart';

sealed class ActualizarCredencialBovedaResultado {}

class ActualizarCredencialBovedaExitoso extends ActualizarCredencialBovedaResultado {
  ActualizarCredencialBovedaExitoso(this.credencial);
  final BovedaCredencialData credencial;
}

class ActualizarCredencialBovedaNombreRequerido extends ActualizarCredencialBovedaResultado {}

class ActualizarCredencialBovedaNoExiste extends ActualizarCredencialBovedaResultado {}

class ActualizarCredencialBovedaErrorInesperado extends ActualizarCredencialBovedaResultado {
  ActualizarCredencialBovedaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Edita nombre/tipo/usuarioAcceso/correo/url/observaciones — **nunca
/// el secreto**, ver `CambiarSecretoCredencialBovedaUseCase` (Etapa
/// 14D), mismo split que Telefonía entre "configurar" y "cambiar
/// contraseña".
class ActualizarCredencialBovedaUseCase {
  ActualizarCredencialBovedaUseCase(this._repository);

  final BovedaCredencialRepository _repository;

  Future<ActualizarCredencialBovedaResultado> ejecutar({
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
    String? actorUsuarioId,
  }) async {
    final nombreLimpio = nombre.trim();
    if (nombreLimpio.isEmpty) return ActualizarCredencialBovedaNombreRequerido();

    try {
      final existente = await _repository.obtenerPorId(id);
      if (existente == null) return ActualizarCredencialBovedaNoExiste();

      final actualizado = await _repository.actualizar(
        id: id,
        nombre: nombreLimpio,
        tipo: tipo,
        usuarioAcceso: usuarioAcceso,
        correo: correo,
        url: url,
        observaciones: observaciones,
        limpiarUsuarioAcceso: limpiarUsuarioAcceso,
        limpiarCorreo: limpiarCorreo,
        limpiarUrl: limpiarUrl,
        limpiarObservaciones: limpiarObservaciones,
      );
      await _repository.registrarEvento(credencialId: id, tipoEvento: 'editada', actorUsuarioId: actorUsuarioId);
      return ActualizarCredencialBovedaExitoso(actualizado);
    } catch (e) {
      return ActualizarCredencialBovedaErrorInesperado(e.toString());
    }
  }
}
