import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/articulo_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';

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

/// Uno de los números de serie capturados ya pertenece a otra unidad
/// existente — mismo mensaje al usuario sin importar si viene de esta
/// validación o de la corrección de identidad (Etapa 9D, tercer ajuste
/// posterior): "El número de serie/IMEI ya está registrado en otra
/// unidad." Se valida *antes* de tocar la base de datos — sin esto, la
/// restricción `UNIQUE` de `ArticuloUnidad.numeroSerie` lanzaba una
/// excepción que caía en `RegistrarCompraErrorInesperado`, un mensaje
/// genérico que no explicaba la causa real.
class RegistrarCompraPartidaNumeroSerieDuplicado extends RegistrarCompraResultado {
  RegistrarCompraPartidaNumeroSerieDuplicado(this.indice, this.numeroSerie);
  final int indice;
  final String numeroSerie;
}

class RegistrarCompraErrorInesperado extends RegistrarCompraResultado {
  RegistrarCompraErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Etapa 19B — `formaPago == tarjeta` sin seleccionar una tarjeta.
class RegistrarCompraTarjetaRequerida extends RegistrarCompraResultado {}

/// La tarjeta seleccionada no existe, no es de tipo `tarjetaCredito`, o
/// no está `activa` — nunca se llega a construir el selector con una
/// opción inválida, pero el dominio revalida siempre (mismo criterio
/// que el resto de esta clase: nunca confiar solo en la UI).
class RegistrarCompraTarjetaInvalida extends RegistrarCompraResultado {}

/// `monto` de la Compra excede `limiteCredito - saldoActual` de la
/// tarjeta seleccionada — nada se muta. `disponible` viaja en el
/// resultado para que el mensaje al usuario cite el monto exacto.
class RegistrarCompraTarjetaExcedeLimite extends RegistrarCompraResultado {
  RegistrarCompraTarjetaExcedeLimite(this.disponible);
  final int disponible;
}

/// La tarjeta seleccionada todavía no tiene `tarjetaLimiteCredito`
/// capturado — nunca se asume `0` (eso rechazaría cualquier compra
/// como si "excediera el límite", un mensaje engañoso: el problema real
/// es que el límite no se ha configurado, no que la compra sea
/// demasiado grande).
class RegistrarCompraTarjetaSinLimiteConfigurado extends RegistrarCompraResultado {}

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
  RegistrarCompraUseCase(
    this._compraRepository,
    this._articuloRepository,
    this._inventarioRepository,
    this._deudaRepository,
    this._generarCodigo,
  );

  final CompraRepository _compraRepository;
  final ArticuloRepository _articuloRepository;
  final InventarioRepository _inventarioRepository;
  final DeudaRepository _deudaRepository;
  final GenerarCodigoUseCase _generarCodigo;

  Future<RegistrarCompraResultado> ejecutar({
    required DateTime fecha,
    String? proveedor,
    required String formaPago,
    String? formaPagoOtroDescripcion,
    String? observaciones,
    required List<PartidaCompraInput> partidas,
    String? deudaId,
    String? cuentaFinancieraId,
    String? actorUsuarioId,
  }) async {
    if (partidas.isEmpty) return RegistrarCompraListaVacia();

    final formaPagoValida = FormaPago.values.any((f) => f.name == formaPago);
    if (!formaPagoValida) return RegistrarCompraFormaPagoInvalida();
    if (formaPago == FormaPago.otro.name && (formaPagoOtroDescripcion == null || formaPagoOtroDescripcion.trim().isEmpty)) {
      return RegistrarCompraFormaPagoOtroDescripcionRequerida();
    }

    DeudaData? tarjeta;
    if (formaPago == FormaPago.tarjeta.name) {
      if (deudaId == null) return RegistrarCompraTarjetaRequerida();
      tarjeta = await _deudaRepository.obtenerPorId(deudaId);
      if (tarjeta == null ||
          tarjeta.tipo != TipoDeuda.tarjetaCredito.name ||
          tarjeta.estatus != EstatusDeuda.activa.name) {
        return RegistrarCompraTarjetaInvalida();
      }
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

        for (final serie in seriesLimpias) {
          final existente = await _inventarioRepository.obtenerUnidadPorNumeroSerie(serie);
          if (existente != null) return RegistrarCompraPartidaNumeroSerieDuplicado(i, serie);
        }
      }
    }

    if (tarjeta != null) {
      final montoTotal = partidas.fold<int>(0, (s, p) => s + p.cantidad * p.costoUnitario);
      final validacion = validarOrigenTarjeta(tarjeta: tarjeta, monto: montoTotal);
      switch (validacion.error) {
        case ErrorOrigenTarjeta.sinLimiteConfigurado:
          return RegistrarCompraTarjetaSinLimiteConfigurado();
        case ErrorOrigenTarjeta.excedeLimite:
          return RegistrarCompraTarjetaExcedeLimite(validacion.disponible!);
        case ErrorOrigenTarjeta.noEsTarjetaActiva:
        case null:
          break;
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
        deudaId: tarjeta?.id,
        cuentaFinancieraId: formaPago == FormaPago.tarjeta.name ? null : cuentaFinancieraId,
        actorUsuarioId: actorUsuarioId,
      );
      return RegistrarCompraExitosa(compra);
    } on SaldoInsuficienteException {
      // Un saldo insuficiente NO es un error inesperado: es un
      // rechazo previsto y accionable. Se deja propagar para que la
      // pantalla muestre disponible/requerido/faltante en vez de un
      // mensaje genérico. La transacción ya quedó revertida entera.
      rethrow;
    } catch (e) {
      return RegistrarCompraErrorInesperado(e.toString());
    }
  }
}
