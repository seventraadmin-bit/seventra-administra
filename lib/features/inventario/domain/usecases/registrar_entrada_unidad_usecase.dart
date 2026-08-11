import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/result.dart';

import '../repositories/articulo_repository.dart';
import '../repositories/inventario_repository.dart';

sealed class RegistrarEntradaUnidadResultado {}

class RegistrarEntradaUnidadExitoso extends RegistrarEntradaUnidadResultado {
  RegistrarEntradaUnidadExitoso(this.unidad);
  final ArticuloUnidadData unidad;
}

class RegistrarEntradaUnidadArticuloNoExiste extends RegistrarEntradaUnidadResultado {}

/// El Artículo no maneja unidades serializadas — una entrada de este
/// tipo se registra por cantidad (`RegistrarEntradaUseCase`).
class RegistrarEntradaUnidadArticuloNoManejaSerie extends RegistrarEntradaUnidadResultado {}

class RegistrarEntradaUnidadNumeroSerieRequerido extends RegistrarEntradaUnidadResultado {}

class RegistrarEntradaUnidadCostoInvalido extends RegistrarEntradaUnidadResultado {}

class RegistrarEntradaUnidadErrorInesperado extends RegistrarEntradaUnidadResultado {
  RegistrarEntradaUnidadErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra la entrada de una unidad serializada (Etapa 7A) — radios,
/// teléfonos: da de alta la `ArticuloUnidad` y su primer movimiento
/// `entrada` en una sola transacción. `imei`/`numeroTelefonico` solo
/// aplican si el Artículo es un teléfono (la UI decide cuándo
/// mostrarlos); ambos quedan en `ArticuloUnidadTelefono`, nunca en la
/// tabla genérica.
class RegistrarEntradaUnidadUseCase {
  RegistrarEntradaUnidadUseCase(this._inventarioRepository, this._articuloRepository, this._generarCodigo);

  final InventarioRepository _inventarioRepository;
  final ArticuloRepository _articuloRepository;
  final GenerarCodigoUseCase _generarCodigo;

  Future<RegistrarEntradaUnidadResultado> ejecutar({
    required String articuloId,
    required String numeroSerie,
    String? marca,
    String? modelo,
    String? imei,
    String? numeroTelefonico,
    int? costoUnitario,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    final articulo = await _articuloRepository.obtenerPorId(articuloId);
    if (articulo == null) return RegistrarEntradaUnidadArticuloNoExiste();
    if (!articulo.manejaSerie) return RegistrarEntradaUnidadArticuloNoManejaSerie();
    if (numeroSerie.trim().isEmpty) return RegistrarEntradaUnidadNumeroSerieRequerido();
    if (costoUnitario != null && costoUnitario < 0) return RegistrarEntradaUnidadCostoInvalido();

    try {
      final codigoResultado = await _generarCodigo.ejecutar('articulo_unidad');
      final String codigo;
      switch (codigoResultado) {
        case Ok<String>(value: final v):
          codigo = v;
        case Err<String>(failure: final f):
          return RegistrarEntradaUnidadErrorInesperado(f.message);
      }

      final unidad = await _inventarioRepository.registrarEntradaUnidad(
        articuloId: articuloId,
        codigo: codigo,
        numeroSerie: numeroSerie.trim(),
        marca: marca?.trim().isEmpty ?? true ? null : marca!.trim(),
        modelo: modelo?.trim().isEmpty ?? true ? null : modelo!.trim(),
        imei: imei?.trim().isEmpty ?? true ? null : imei!.trim(),
        numeroTelefonico: numeroTelefonico?.trim().isEmpty ?? true ? null : numeroTelefonico!.trim(),
        costoUnitario: costoUnitario,
        fecha: fecha,
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );
      return RegistrarEntradaUnidadExitoso(unidad);
    } catch (e) {
      return RegistrarEntradaUnidadErrorInesperado(e.toString());
    }
  }
}
