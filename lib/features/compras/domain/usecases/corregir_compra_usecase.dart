import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart' show EstatusDeuda, TipoDeuda;
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';
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

/// Etapa 3 (Compras — corrección financiera completa Cuenta↔TDC): se
/// pidieron simultáneamente [CorregirCompraUseCase.ejecutar]'s
/// `nuevaCuentaFinancieraId` Y `nuevaDeudaId` — el destino financiero
/// es ambiguo (¿Cuenta o TDC?). Nunca se infiere una prioridad
/// silenciosa entre los dos.
class CorregirCompraOrigenAmbiguo extends CorregirCompraResultado {}

/// La TDC destino (`nuevaDeudaId`) no existe, no es de tipo
/// `tarjetaCredito`, o no está `activa` — mismo criterio que
/// `RegistrarCompraTarjetaInvalida`.
class CorregirCompraTarjetaInvalida extends CorregirCompraResultado {}

/// El monto proyectado de la Compra excede `limiteCredito - saldoActual`
/// de la TDC destino — nada se muta. Si la Compra YA estaba en esa
/// misma TDC, `disponible` ya descuenta el efecto propio de la Compra
/// (ver el doc comment de `ejecutar`) — nunca compara contra un saldo
/// que todavía incluye el cargo viejo de esta misma corrección.
class CorregirCompraTarjetaExcedeLimite extends CorregirCompraResultado {
  CorregirCompraTarjetaExcedeLimite(this.disponible);
  final int disponible;
}

/// La TDC destino todavía no tiene `tarjetaLimiteCredito` capturado —
/// mismo criterio que `RegistrarCompraTarjetaSinLimiteConfigurado`:
/// nunca se asume `$0`.
class CorregirCompraTarjetaSinLimiteConfigurado extends CorregirCompraResultado {}

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

/// Etapa 2 (convención común de auditoría) — antes `motivo` se
/// aceptaba sin validar, incluida una cadena vacía o solo espacios.
/// Toda corrección sensible exige un motivo legible real.
class CorregirCompraMotivoRequerido extends CorregirCompraResultado {}

/// Corrige una Compra ya registrada (Etapa 15, ampliación real de
/// "Corregir datos") — campos administrativos y, opcionalmente,
/// [cambiosPartidas]: artículo/variante, cantidad, costo, o partidas
/// completas agregadas/quitadas. Bloqueada si la Compra ya está
/// cancelada, o si algún cambio de partida toca existencia ya
/// consumida (verificado por `CompraRepository.obtenerResumenCorreccion`
/// antes de aplicar nada — todo o nada).
class CorregirCompraUseCase {
  CorregirCompraUseCase(
    this._compraRepository,
    this._articuloRepository,
    this._inventarioRepository,
    this._deudaRepository,
  );

  final CompraRepository _compraRepository;
  final ArticuloRepository _articuloRepository;
  final InventarioRepository _inventarioRepository;
  final DeudaRepository _deudaRepository;

  Future<ResumenCorreccionCompra> obtenerResumen({
    required String compraId,
    List<CorreccionPartida> cambiosPartidas = const [],
  }) {
    return _compraRepository.obtenerResumenCorreccion(compraId: compraId, cambiosPartidas: cambiosPartidas);
  }

  /// Corrige una Compra ya registrada — campos administrativos,
  /// [cambiosPartidas], y/o su origen financiero completo (Etapa 3):
  /// pasa [nuevaCuentaFinancieraId] para mover la Compra a (o dentro
  /// de) una Cuenta financiera, o [nuevaDeudaId] para moverla a (o
  /// dentro de) una TDC — nunca ambos a la vez
  /// ([CorregirCompraOrigenAmbiguo]). Si ninguno de los dos se pasa, el
  /// origen financiero actual se conserva intacto (mismo
  /// comportamiento que antes de esta etapa).
  ///
  /// Validación de crédito (Sección 5): cuando el destino final es una
  /// TDC, se revalida contra `validarOrigenTarjeta` — la ÚNICA fuente
  /// de verdad, la misma que usa el registro inicial. Si la Compra YA
  /// estaba en esa misma TDC (transición "misma TDC, cambia monto"),
  /// el saldo de la tarjeta usado para validar se calcula SIN el
  /// efecto propio de la Compra (`DeudaRepository.netoAportadoPorCompra`)
  /// — de lo contrario, corregir una Compra de $2,000 a $2,500 en una
  /// tarjeta con $10,000 de límite y $9,000 de saldo (de los cuales
  /// $2,000 son de esta misma Compra) se rechazaría comparando contra
  /// solo $1,000 disponible, cuando en realidad la Compra libera su
  /// propio efecto anterior antes de aplicar el nuevo.
  Future<CorregirCompraResultado> ejecutar({
    required String compraId,
    DateTime? fecha,
    String? proveedor,
    String? formaPago,
    String? formaPagoOtroDescripcion,
    String? observaciones,
    List<CorreccionPartida> cambiosPartidas = const [],
    String? nuevaCuentaFinancieraId,
    String? nuevaDeudaId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    if (!motivoEsValido(motivo)) return CorregirCompraMotivoRequerido();
    if (nuevaCuentaFinancieraId != null && nuevaDeudaId != null) return CorregirCompraOrigenAmbiguo();

    final compra = await _compraRepository.obtenerPorId(compraId);
    if (compra == null) return CorregirCompraNoExiste();
    if (compra.estatus == 'cancelada') return CorregirCompraCancelada();

    for (var i = 0; i < cambiosPartidas.length; i++) {
      final error = await _validarCambio(cambiosPartidas[i]);
      if (error != null) return CorregirCompraPartidaInvalida(i, error);
    }

    ResumenCorreccionCompra? resumen;
    if (cambiosPartidas.isNotEmpty) {
      resumen = await _compraRepository.obtenerResumenCorreccion(compraId: compraId, cambiosPartidas: cambiosPartidas);
      if (resumen.bloqueado) return CorregirCompraTieneDependencias(resumen.detalleBloqueo!);
    }
    final montoProyectado = resumen?.totalNuevo ?? await _compraRepository.calcularTotal(compraId);

    // El destino final es TDC tanto si se pide explícitamente
    // (`nuevaDeudaId`) como si no se pide ningún cambio de origen y la
    // Compra YA estaba en una TDC (el monto pudo cambiar vía partidas).
    final deudaIdDestino = nuevaDeudaId ?? (nuevaCuentaFinancieraId == null ? compra.deudaId : null);
    if (deudaIdDestino != null) {
      final tarjeta = await _deudaRepository.obtenerPorId(deudaIdDestino);
      if (tarjeta == null || tarjeta.tipo != TipoDeuda.tarjetaCredito.name || tarjeta.estatus != EstatusDeuda.activa.name) {
        return CorregirCompraTarjetaInvalida();
      }

      var tarjetaParaValidar = tarjeta;
      if (compra.deudaId == deudaIdDestino) {
        final netoPropio = await _deudaRepository.netoAportadoPorCompra(deudaId: deudaIdDestino, compraId: compraId);
        tarjetaParaValidar = tarjeta.copyWith(saldoActual: tarjeta.saldoActual - netoPropio);
      }

      final validacion = validarOrigenTarjeta(tarjeta: tarjetaParaValidar, monto: montoProyectado);
      switch (validacion.error) {
        case ErrorOrigenTarjeta.sinLimiteConfigurado:
          return CorregirCompraTarjetaSinLimiteConfigurado();
        case ErrorOrigenTarjeta.excedeLimite:
          return CorregirCompraTarjetaExcedeLimite(validacion.disponible!);
        case ErrorOrigenTarjeta.noEsTarjetaActiva:
        case null:
          break;
      }
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
        nuevaCuentaFinancieraId: nuevaCuentaFinancieraId,
        nuevaDeudaId: nuevaDeudaId,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return CorregirCompraExitosa(actualizada);
    } on SaldoInsuficienteException {
      // Corregir también puede quedarse sin saldo (subir el importe, o
      // mover la salida a otra cuenta). No es un error inesperado: se
      // deja propagar para que la pantalla muestre los tres números.
      rethrow;
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
