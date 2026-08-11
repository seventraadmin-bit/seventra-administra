import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/inventario/domain/repositories/articulo_repository.dart';

import '../../data/tables/compra_partida_table.dart' show DestinoCompraPartida;
import '../repositories/compra_repository.dart';

sealed class RegistrarCompraResultado {}

class RegistrarCompraExitosa extends RegistrarCompraResultado {
  RegistrarCompraExitosa(this.compra);
  final CompraData compra;
}

class RegistrarCompraListaVacia extends RegistrarCompraResultado {}

class RegistrarCompraFormaPagoInvalida extends RegistrarCompraResultado {}

class RegistrarCompraFormaPagoOtroDescripcionRequerida extends RegistrarCompraResultado {}

/// El índice (0-based) señala cuál partida de la lista original falló —
/// la UI lo usa para resaltar el renglón exacto, nunca un mensaje
/// genérico "algo salió mal en alguna partida".
class RegistrarCompraPartidaDestinoInvalido extends RegistrarCompraResultado {
  RegistrarCompraPartidaDestinoInvalido(this.indice);
  final int indice;
}

class RegistrarCompraPartidaArticuloNoExiste extends RegistrarCompraResultado {
  RegistrarCompraPartidaArticuloNoExiste(this.indice);
  final int indice;
}

class RegistrarCompraPartidaVarianteInvalida extends RegistrarCompraResultado {
  RegistrarCompraPartidaVarianteInvalida(this.indice);
  final int indice;
}

class RegistrarCompraPartidaConceptoRequerido extends RegistrarCompraResultado {
  RegistrarCompraPartidaConceptoRequerido(this.indice);
  final int indice;
}

class RegistrarCompraPartidaCantidadInvalida extends RegistrarCompraResultado {
  RegistrarCompraPartidaCantidadInvalida(this.indice);
  final int indice;
}

class RegistrarCompraPartidaCostoInvalido extends RegistrarCompraResultado {
  RegistrarCompraPartidaCostoInvalido(this.indice);
  final int indice;
}

/// El Artículo maneja serie y `numerosSerie` no trae exactamente
/// `cantidad` números no vacíos y sin duplicados entre sí.
class RegistrarCompraPartidaNumerosSerieInvalidos extends RegistrarCompraResultado {
  RegistrarCompraPartidaNumerosSerieInvalidos(this.indice);
  final int indice;
}

class RegistrarCompraErrorInesperado extends RegistrarCompraResultado {
  RegistrarCompraErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra una Compra de contado completa (Etapa 10) — una o varias
/// partidas, cada una con destino independiente (Inventario/Gasto
/// directo). Valida todo antes de tocar la base de datos: artículo
/// real y existente, `manejaVariante`/`manejaSerie` coherentes con lo
/// capturado, números de serie completos para partidas serializadas
/// (ver el doc comment de `CompraRepository.crear` — no existe flujo
/// de "completar series después"), cantidad/costo válidos. Genera el
/// folio de la Compra y delega la composición completa (Egreso +
/// entradas de Inventario) a `CompraRepository.crear`.
class RegistrarCompraUseCase {
  RegistrarCompraUseCase(this._compraRepository, this._articuloRepository, this._generarCodigo);

  final CompraRepository _compraRepository;
  final ArticuloRepository _articuloRepository;
  final GenerarCodigoUseCase _generarCodigo;

  Future<RegistrarCompraResultado> ejecutar({
    required DateTime fecha,
    String? proveedor,
    required String formaPago,
    String? formaPagoOtroDescripcion,
    String? observaciones,
    required List<PartidaCompraInput> partidas,
    String? actor,
  }) async {
    if (partidas.isEmpty) return RegistrarCompraListaVacia();

    final formaPagoValida = FormaPago.values.any((f) => f.name == formaPago);
    if (!formaPagoValida) return RegistrarCompraFormaPagoInvalida();
    if (formaPago == FormaPago.otro.name && (formaPagoOtroDescripcion == null || formaPagoOtroDescripcion.trim().isEmpty)) {
      return RegistrarCompraFormaPagoOtroDescripcionRequerida();
    }

    for (var i = 0; i < partidas.length; i++) {
      final partida = partidas[i];
      final esInventario = partida.destino == DestinoCompraPartida.inventario.name;
      final esGastoDirecto = partida.destino == DestinoCompraPartida.gastoDirecto.name;
      if (!esInventario && !esGastoDirecto) return RegistrarCompraPartidaDestinoInvalido(i);
      if (partida.cantidad <= 0) return RegistrarCompraPartidaCantidadInvalida(i);
      if (partida.costoUnitario < 0) return RegistrarCompraPartidaCostoInvalido(i);

      if (esGastoDirecto) {
        if (partida.concepto == null || partida.concepto!.trim().isEmpty) {
          return RegistrarCompraPartidaConceptoRequerido(i);
        }
        continue;
      }

      // esInventario
      if (partida.articuloId == null) return RegistrarCompraPartidaArticuloNoExiste(i);
      final articulo = await _articuloRepository.obtenerPorId(partida.articuloId!);
      if (articulo == null) return RegistrarCompraPartidaArticuloNoExiste(i);
      if (articulo.manejaVariante != (partida.varianteId != null)) return RegistrarCompraPartidaVarianteInvalida(i);

      if (articulo.manejaSerie) {
        final series = partida.numerosSerie;
        if (series == null || series.length != partida.cantidad) return RegistrarCompraPartidaNumerosSerieInvalidos(i);
        final seriesLimpias = series.map((s) => s.trim()).toList();
        if (seriesLimpias.any((s) => s.isEmpty)) return RegistrarCompraPartidaNumerosSerieInvalidos(i);
        if (seriesLimpias.toSet().length != seriesLimpias.length) return RegistrarCompraPartidaNumerosSerieInvalidos(i);
      }
    }

    try {
      final folioResultado = await _generarCodigo.ejecutar('compra');
      final String folioCompra;
      switch (folioResultado) {
        case Ok<String>(value: final v):
          folioCompra = v;
        case Err<String>(failure: final f):
          return RegistrarCompraErrorInesperado(f.message);
      }

      final compra = await _compraRepository.crear(
        folioCompra: folioCompra,
        fecha: fecha,
        proveedor: proveedor?.trim().isEmpty ?? true ? null : proveedor!.trim(),
        formaPago: formaPago,
        formaPagoOtroDescripcion: formaPagoOtroDescripcion?.trim().isEmpty ?? true ? null : formaPagoOtroDescripcion!.trim(),
        observaciones: observaciones?.trim().isEmpty ?? true ? null : observaciones!.trim(),
        partidas: partidas,
        actor: actor,
      );
      return RegistrarCompraExitosa(compra);
    } catch (e) {
      return RegistrarCompraErrorInesperado(e.toString());
    }
  }
}
