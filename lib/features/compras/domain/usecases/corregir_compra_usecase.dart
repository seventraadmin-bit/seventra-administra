import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/domain/repositories/articulo_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';

import '../../data/tables/compra_partida_table.dart' show DestinoCompraPartida;
import '../repositories/compra_repository.dart';
import 'correccion_partida_compra.dart';

sealed class CorregirCompraResultado {}

class CorregirCompraExitosa extends CorregirCompraResultado {
  CorregirCompraExitosa(this.compra);
  final CompraData compra;
}

class CorregirCompraNoExiste extends CorregirCompraResultado {}

class CorregirCompraCancelada extends CorregirCompraResultado {}

/// El índice (0-based dentro de `cambiosPartidas`) señala cuál cambio
/// falló — mismo criterio que `RegistrarCompraPartidaXxx`.
class CorregirCompraPartidaInvalida extends CorregirCompraResultado {
  CorregirCompraPartidaInvalida(this.indice, this.motivo);
  final int indice;
  final String motivo;
}

/// Al menos uno de los cambios propuestos toca existencia ya
/// consumida (asignada, vinculada a telefonía, o con movimientos
/// ajenos) — `detalle` siempre nombra la dependencia real.
class CorregirCompraTieneDependencias extends CorregirCompraResultado {
  CorregirCompraTieneDependencias(this.detalle);
  final String detalle;
}

class CorregirCompraErrorInesperado extends CorregirCompraResultado {
  CorregirCompraErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige una Compra ya registrada (Etapa 15, ampliación real de
/// "Corregir datos") — campos administrativos y, opcionalmente,
/// [cambiosPartidas]: artículo/variante, cantidad, costo, o partidas
/// completas agregadas/quitadas. Bloqueada si la Compra ya está
/// cancelada, o si algún cambio de partida toca existencia ya
/// consumida (verificado por `CompraRepository.obtenerResumenCorreccion`
/// antes de aplicar nada — todo o nada).
class CorregirCompraUseCase {
  CorregirCompraUseCase(this._compraRepository, this._articuloRepository, this._inventarioRepository);

  final CompraRepository _compraRepository;
  final ArticuloRepository _articuloRepository;
  final InventarioRepository _inventarioRepository;

  Future<ResumenCorreccionCompra> obtenerResumen({
    required String compraId,
    List<CorreccionPartida> cambiosPartidas = const [],
  }) {
    return _compraRepository.obtenerResumenCorreccion(compraId: compraId, cambiosPartidas: cambiosPartidas);
  }

  Future<CorregirCompraResultado> ejecutar({
    required String compraId,
    DateTime? fecha,
    String? proveedor,
    String? formaPago,
    String? formaPagoOtroDescripcion,
    String? observaciones,
    List<CorreccionPartida> cambiosPartidas = const [],
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final compra = await _compraRepository.obtenerPorId(compraId);
    if (compra == null) return CorregirCompraNoExiste();
    if (compra.estatus == 'cancelada') return CorregirCompraCancelada();

    for (var i = 0; i < cambiosPartidas.length; i++) {
      final error = await _validarCambio(cambiosPartidas[i]);
      if (error != null) return CorregirCompraPartidaInvalida(i, error);
    }

    if (cambiosPartidas.isNotEmpty) {
      final resumen = await _compraRepository.obtenerResumenCorreccion(compraId: compraId, cambiosPartidas: cambiosPartidas);
      if (resumen.bloqueado) return CorregirCompraTieneDependencias(resumen.detalleBloqueo!);
    }

    try {
      final actualizada = await _compraRepository.corregir(
        compraId: compraId,
        fecha: fecha,
        proveedor: proveedor,
        formaPago: formaPago,
        formaPagoOtroDescripcion: formaPagoOtroDescripcion,
        observaciones: observaciones,
        cambiosPartidas: cambiosPartidas,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return CorregirCompraExitosa(actualizada);
    } catch (e) {
      return CorregirCompraErrorInesperado(e.toString());
    }
  }

  Future<String?> _validarCambio(CorreccionPartida cambio) async {
    switch (cambio) {
      case CorreccionPartidaCantidadCosto(:final nuevaCantidad, :final nuevoCostoUnitario):
        if (nuevaCantidad != null && nuevaCantidad <= 0) {
          return 'La cantidad debe ser mayor a cero — usa "Quitar partida" para eliminarla por completo.';
        }
        if (nuevoCostoUnitario != null && nuevoCostoUnitario < 0) return 'El costo unitario no puede ser negativo.';
      case CorreccionPartidaVariante(:final nuevoArticuloId, :final nuevaVarianteId, :final numerosSerieNuevos):
        final articulo = await _articuloRepository.obtenerPorId(nuevoArticuloId);
        if (articulo == null) return 'El artículo seleccionado no existe.';
        if (articulo.manejaVariante != (nuevaVarianteId != null)) {
          return 'La variante capturada no corresponde a la configuración del artículo.';
        }
        if (articulo.manejaSerie) {
          if (numerosSerieNuevos.isEmpty) return 'Captura al menos un número de serie para el artículo nuevo.';
          final seriesLimpias = numerosSerieNuevos.map((s) => s.trim()).toList();
          if (seriesLimpias.any((s) => s.isEmpty)) return 'Hay un número de serie vacío.';
          if (seriesLimpias.toSet().length != seriesLimpias.length) return 'Hay números de serie repetidos.';
          for (final serie in seriesLimpias) {
            if (await _inventarioRepository.obtenerUnidadPorNumeroSerie(serie) != null) {
              return 'El número de serie/IMEI "$serie" ya está registrado en otra unidad.';
            }
          }
        }
      case CorreccionPartidaAgregar(:final input):
        final esInventario = input.destino == DestinoCompraPartida.inventario.name;
        final esGastoDirecto = input.destino == DestinoCompraPartida.gastoDirecto.name;
        if (!esInventario && !esGastoDirecto) return 'Destino de partida inválido.';
        if (input.cantidad <= 0) return 'La cantidad debe ser mayor a cero.';
        if (input.costoUnitario < 0) return 'El costo unitario no puede ser negativo.';
        if (esGastoDirecto) {
          if (input.concepto == null || input.concepto!.trim().isEmpty) return 'El concepto es obligatorio.';
          break;
        }
        if (input.articuloId == null) return 'Selecciona un artículo.';
        final articulo = await _articuloRepository.obtenerPorId(input.articuloId!);
        if (articulo == null) return 'El artículo seleccionado no existe.';
        if (articulo.manejaVariante != (input.varianteId != null)) {
          return 'La variante capturada no corresponde a la configuración del artículo.';
        }
        if (articulo.manejaSerie) {
          final series = input.numerosSerie;
          if (series == null || series.length != input.cantidad) return 'Captura un número de serie por unidad.';
          final seriesLimpias = series.map((s) => s.trim()).toList();
          if (seriesLimpias.any((s) => s.isEmpty)) return 'Hay un número de serie vacío.';
          if (seriesLimpias.toSet().length != seriesLimpias.length) return 'Hay números de serie repetidos.';
          for (final serie in seriesLimpias) {
            if (await _inventarioRepository.obtenerUnidadPorNumeroSerie(serie) != null) {
              return 'El número de serie/IMEI "$serie" ya está registrado en otra unidad.';
            }
          }
        }
      case CorreccionPartidaQuitar():
        return null;
    }
    return null;
  }
}
