import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/articulo_repository.dart';
import '../repositories/inventario_repository.dart';

sealed class RegistrarEntradaResultado {}

class RegistrarEntradaExitoso extends RegistrarEntradaResultado {
  RegistrarEntradaExitoso(this.movimiento);
  final MovimientoInventarioData movimiento;
}

class RegistrarEntradaArticuloNoExiste extends RegistrarEntradaResultado {}

/// El Artículo maneja unidades serializadas — una entrada de este tipo
/// se registra unidad por unidad (`RegistrarEntradaUnidadUseCase`),
/// nunca como cantidad.
class RegistrarEntradaArticuloManejaSerie extends RegistrarEntradaResultado {}

/// El Artículo maneja variante y no se indicó cuál, o se indicó una
/// variante para un Artículo que no las maneja.
class RegistrarEntradaVarianteInvalida extends RegistrarEntradaResultado {}

class RegistrarEntradaCantidadInvalida extends RegistrarEntradaResultado {}

class RegistrarEntradaCostoInvalido extends RegistrarEntradaResultado {}

class RegistrarEntradaErrorInesperado extends RegistrarEntradaResultado {
  RegistrarEntradaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra una entrada de Inventario por cantidad (Etapa 7A) — la
/// única forma de aumentar la existencia de un Artículo que no maneja
/// unidades serializadas. `costoTotal` nunca se guarda, se deriva
/// (`cantidad × costoUnitario`) donde se necesite mostrarlo.
class RegistrarEntradaUseCase {
  RegistrarEntradaUseCase(this._inventarioRepository, this._articuloRepository);

  final InventarioRepository _inventarioRepository;
  final ArticuloRepository _articuloRepository;

  Future<RegistrarEntradaResultado> ejecutar({
    required String articuloId,
    String? varianteId,
    required int cantidad,
    int? costoUnitario,
    required DateTime fecha,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    final articulo = await _articuloRepository.obtenerPorId(articuloId);
    if (articulo == null) return RegistrarEntradaArticuloNoExiste();
    if (articulo.manejaSerie) return RegistrarEntradaArticuloManejaSerie();
    if (articulo.manejaVariante != (varianteId != null)) return RegistrarEntradaVarianteInvalida();
    if (cantidad <= 0) return RegistrarEntradaCantidadInvalida();
    if (costoUnitario != null && costoUnitario < 0) return RegistrarEntradaCostoInvalido();

    try {
      final movimiento = await _inventarioRepository.registrarEntrada(
        articuloId: articuloId,
        varianteId: varianteId,
        cantidad: cantidad,
        costoUnitario: costoUnitario,
        fecha: fecha,
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );
      return RegistrarEntradaExitoso(movimiento);
    } catch (e) {
      return RegistrarEntradaErrorInesperado(e.toString());
    }
  }
}
