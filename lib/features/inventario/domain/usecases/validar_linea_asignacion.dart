import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/articulo_unidad_table.dart' show EstatusArticuloUnidad;
import '../repositories/articulo_repository.dart';
import '../repositories/inventario_repository.dart';

/// Validación de un renglón "artículo + variante/unidad + cantidad"
/// contra el catálogo/existencia real — compartida entre
/// `CrearAsignacionUseCase` (un solo renglón) y `EntregarEquipoUseCase`
/// (varios renglones en un carrito), para que una regla nueva no tenga
/// que mantenerse en dos sitios. Sin efectos secundarios: solo lee.
sealed class ValidacionLineaAsignacion {}

class LineaAsignacionValida extends ValidacionLineaAsignacion {
  LineaAsignacionValida(this.articulo);
  final ArticuloData articulo;
}

class LineaAsignacionArticuloNoExiste extends ValidacionLineaAsignacion {}

class LineaAsignacionCantidadInvalida extends ValidacionLineaAsignacion {}

class LineaAsignacionVarianteInvalida extends ValidacionLineaAsignacion {}

class LineaAsignacionUnidadInvalida extends ValidacionLineaAsignacion {}

class LineaAsignacionUnidadNoDisponible extends ValidacionLineaAsignacion {}

class LineaAsignacionSobrepasaDisponible extends ValidacionLineaAsignacion {
  LineaAsignacionSobrepasaDisponible(this.disponible);
  final int disponible;
}

/// [cantidadYaComprometidaEnLote] — Etapa "Entrega múltiple": cuando
/// varias líneas del mismo carrito piden el mismo artículo+variante,
/// el llamador debe sumar antes de validar (nunca comparar cada línea
/// por separado contra `disponible`, eso permitiría 2×disponible entre
/// dos líneas que individualmente caben). Para una asignación
/// individual, siempre `0`.
Future<ValidacionLineaAsignacion> validarLineaAsignacion({
  required ArticuloRepository articuloRepository,
  required InventarioRepository inventarioRepository,
  required String articuloId,
  String? varianteId,
  String? unidadId,
  required int cantidad,
  int cantidadYaComprometidaEnLote = 0,
}) async {
  final articulo = await articuloRepository.obtenerPorId(articuloId);
  if (articulo == null) return LineaAsignacionArticuloNoExiste();

  if (cantidad <= 0) return LineaAsignacionCantidadInvalida();

  if (articulo.manejaSerie) {
    if (unidadId == null || cantidad != 1) return LineaAsignacionUnidadInvalida();
    final unidad = await inventarioRepository.obtenerUnidadPorId(unidadId);
    if (unidad == null || unidad.articuloId != articuloId) return LineaAsignacionUnidadInvalida();
    if (EstatusArticuloUnidad.values.byName(unidad.estatus) != EstatusArticuloUnidad.disponible) {
      return LineaAsignacionUnidadNoDisponible();
    }
  } else {
    if (unidadId != null) return LineaAsignacionUnidadInvalida();
    if (articulo.manejaVariante != (varianteId != null)) return LineaAsignacionVarianteInvalida();

    final existencia = await inventarioRepository.calcularExistencia(articuloId: articuloId, varianteId: varianteId);
    final totalComprometido = cantidad + cantidadYaComprometidaEnLote;
    if (totalComprometido > existencia.disponible) return LineaAsignacionSobrepasaDisponible(existencia.disponible);
  }

  return LineaAsignacionValida(articulo);
}
