import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';

import '../../data/tables/vehiculo_mantenimiento_table.dart';
import '../../data/tables/vehiculo_table.dart';
import '../repositories/vehiculo_mantenimiento_repository.dart';
import '../repositories/vehiculo_repository.dart';

sealed class CorregirMantenimientoVehiculoResultado {}

class CorregirMantenimientoVehiculoExitoso extends CorregirMantenimientoVehiculoResultado {
  CorregirMantenimientoVehiculoExitoso(this.registro);
  final VehiculoMantenimientoData registro;
}

class CorregirMantenimientoVehiculoNoExiste extends CorregirMantenimientoVehiculoResultado {}

/// Un registro anulado no se corrige — se registra uno nuevo. Mismo
/// criterio que Compra/Tiempo Extra cancelados.
class CorregirMantenimientoVehiculoCancelado extends CorregirMantenimientoVehiculoResultado {}

class CorregirMantenimientoVehiculoMotivoRequerido extends CorregirMantenimientoVehiculoResultado {}

class CorregirMantenimientoVehiculoDescripcionRequerida extends CorregirMantenimientoVehiculoResultado {}

class CorregirMantenimientoVehiculoCostoInvalido extends CorregirMantenimientoVehiculoResultado {}

class CorregirMantenimientoVehiculoOrigenFinancieroRequerido extends CorregirMantenimientoVehiculoResultado {}

class CorregirMantenimientoVehiculoTarjetaInvalida extends CorregirMantenimientoVehiculoResultado {
  CorregirMantenimientoVehiculoTarjetaInvalida(this.error, {this.disponible});
  final ErrorOrigenTarjeta error;
  final int? disponible;
}

class CorregirMantenimientoVehiculoErrorInesperado extends CorregirMantenimientoVehiculoResultado {
  CorregirMantenimientoVehiculoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige un mantenimiento/incidencia, incluida cualquier transición de
/// origen financiero (schemaVersion 80).
///
/// Soporta las 8 combinaciones que pidió Marlon, todas por el MISMO
/// camino (revertir lo vigente + aplicar lo nuevo, en una transacción):
/// cuenta→misma cuenta, cuenta→otra cuenta, cuenta→TDC, TDC→cuenta,
/// TDC→misma TDC, TDC→otra TDC, cambio de monto, y todo simultáneo.
///
/// La única variante es TDC→misma TDC, que emite un ajuste por la
/// diferencia en vez de revertir y recargar — así el ledger de la
/// tarjeta muestra la corrección como corrección, igual que en Compras
/// y Tiempos Extra.
///
/// **Nunca queda un movimiento huérfano ni doble gasto**: el repositorio
/// revierte el origen anterior antes de aplicar el nuevo, dentro de la
/// misma transacción.
class CorregirMantenimientoVehiculoUseCase {
  CorregirMantenimientoVehiculoUseCase(
    this._mantenimientoRepository,
    this._vehiculoRepository,
    this._deudaRepository,
  );

  final VehiculoMantenimientoRepository _mantenimientoRepository;
  final VehiculoRepository _vehiculoRepository;
  final DeudaRepository _deudaRepository;

  Future<CorregirMantenimientoVehiculoResultado> ejecutar({
    required String vehiculoMantenimientoId,
    DateTime? fecha,
    String? tipo,
    String? descripcion,
    String? tallerProveedor,
    int? costo,
    bool limpiarCosto = false,
    DateTime? proximoMantenimientoFecha,
    int? proximoMantenimientoKilometraje,
    String? observaciones,
    OrigenFinancieroGasto? origen,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    if (!motivoEsValido(motivo)) return CorregirMantenimientoVehiculoMotivoRequerido();

    final actual = await _mantenimientoRepository.obtenerPorId(vehiculoMantenimientoId);
    if (actual == null) return CorregirMantenimientoVehiculoNoExiste();
    if (EstatusMantenimientoVehiculo.values.byName(actual.estatus) == EstatusMantenimientoVehiculo.cancelado) {
      return CorregirMantenimientoVehiculoCancelado();
    }

    if (descripcion != null && descripcion.trim().isEmpty) {
      return CorregirMantenimientoVehiculoDescripcionRequerida();
    }
    if (costo != null && costo < 0) return CorregirMantenimientoVehiculoCostoInvalido();

    final costoFinal = limpiarCosto ? 0 : (costo ?? actual.costo ?? 0);
    final hayCosto = costoFinal > 0;
    if (hayCosto && origen == null) {
      return CorregirMantenimientoVehiculoOrigenFinancieroRequerido();
    }

    String? cuentaFinancieraId;
    String? deudaIdTarjeta;
    if (origen is OrigenFinancieroCuenta) {
      cuentaFinancieraId = origen.cuentaFinancieraId;
    } else if (origen is OrigenFinancieroTarjeta) {
      final tarjeta = await _deudaRepository.obtenerPorId(origen.deudaId);
      // Si sigue en la MISMA tarjeta, el disponible ya incluye el cargo
      // vigente de este mantenimiento — validar el monto completo contra
      // él rechazaría correcciones legítimas. Se valida sólo el
      // incremento real.
      final netoActual = actual.deudaId == origen.deudaId
          ? await _deudaRepository.netoAportadoPorMantenimientoVehiculo(
              deudaId: origen.deudaId,
              vehiculoMantenimientoId: vehiculoMantenimientoId,
            )
          : 0;
      final aValidar = costoFinal - netoActual;
      if (aValidar > 0) {
        final validacion = validarOrigenTarjeta(tarjeta: tarjeta, monto: aValidar);
        if (!validacion.esValida) {
          return CorregirMantenimientoVehiculoTarjetaInvalida(validacion.error!, disponible: validacion.disponible);
        }
      } else if (tarjeta == null) {
        return CorregirMantenimientoVehiculoTarjetaInvalida(ErrorOrigenTarjeta.noEsTarjetaActiva);
      }
      deudaIdTarjeta = origen.deudaId;
    }

    try {
      final actualizado = await _mantenimientoRepository.corregir(
        vehiculoMantenimientoId: vehiculoMantenimientoId,
        fecha: fecha,
        tipo: tipo,
        descripcion: descripcion?.trim(),
        tallerProveedor: tallerProveedor?.trim().isEmpty ?? true ? null : tallerProveedor!.trim(),
        costo: costo,
        limpiarCosto: limpiarCosto,
        proximoMantenimientoFecha: proximoMantenimientoFecha,
        proximoMantenimientoKilometraje: proximoMantenimientoKilometraje,
        observaciones: observaciones?.trim().isEmpty ?? true ? null : observaciones!.trim(),
        cuentaFinancieraId: cuentaFinancieraId,
        deudaIdTarjeta: deudaIdTarjeta,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );

      // Solo lo que cambió de verdad — incluido el origen financiero,
      // que es exactamente lo que un auditor querría ver.
      final diff = DiffEvento()
        ..anotar('fecha', actual.fecha, actualizado.fecha)
        ..anotar('tipo', actual.tipo, actualizado.tipo)
        ..anotar('descripcion', actual.descripcion, actualizado.descripcion)
        ..anotar('tallerProveedor', actual.tallerProveedor, actualizado.tallerProveedor)
        ..anotar('costo', actual.costo, actualizado.costo)
        ..anotar('egresoId', actual.egresoId, actualizado.egresoId)
        ..anotar('deudaId', actual.deudaId, actualizado.deudaId)
        ..anotar('observaciones', actual.observaciones, actualizado.observaciones);

      if (diff.hayCambios) {
        await _vehiculoRepository.registrarEvento(
          vehiculoId: actual.vehiculoId,
          tipoEvento: TipoEventoVehiculo.mantenimientoCorregido,
          observacion: motivo,
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          actorUsuarioId: actorUsuarioId,
        );
      }

      return CorregirMantenimientoVehiculoExitoso(actualizado);
    } on SaldoInsuficienteException {
      // Corregir también puede quedarse sin saldo (subir el importe, o
      // mover la salida a otra cuenta). No es un error inesperado: se
      // deja propagar para que la pantalla muestre los tres números.
      rethrow;
    } catch (e) {
      return CorregirMantenimientoVehiculoErrorInesperado(e.toString());
    }
  }
}
