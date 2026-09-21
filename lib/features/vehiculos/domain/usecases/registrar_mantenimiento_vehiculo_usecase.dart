import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'dart:convert';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';

import '../../data/tables/vehiculo_table.dart';
import '../repositories/vehiculo_kilometraje_repository.dart';
import '../repositories/vehiculo_mantenimiento_repository.dart';
import '../repositories/vehiculo_repository.dart';

sealed class RegistrarMantenimientoVehiculoResultado {}

class RegistrarMantenimientoVehiculoExitoso extends RegistrarMantenimientoVehiculoResultado {
  RegistrarMantenimientoVehiculoExitoso(this.registro);
  final VehiculoMantenimientoData registro;
}

class RegistrarMantenimientoVehiculoVehiculoNoExiste extends RegistrarMantenimientoVehiculoResultado {}

class RegistrarMantenimientoVehiculoDescripcionRequerida extends RegistrarMantenimientoVehiculoResultado {}

/// `proximoMantenimientoFecha`/`proximoMantenimientoKilometraje`
/// inconsistentes con esta captura (fecha anterior a `fecha`, o
/// kilometraje programado menor al capturado ahora).
class RegistrarMantenimientoVehiculoProximoInvalido extends RegistrarMantenimientoVehiculoResultado {}

/// Mismo criterio que `AsignarVehiculoUseCase`/
/// `RegistrarKilometrajeVehiculoUseCase`: nunca se acepta un decremento
/// silencioso del kilometraje. Sin flujo de corrección aquí — si
/// realmente hace falta corregir el odómetro, se usa el flujo dedicado
/// (`RegistrarKilometrajeVehiculoUseCase` con `origen = correccion`).
class RegistrarMantenimientoVehiculoKilometrajeMenorAlActual extends RegistrarMantenimientoVehiculoResultado {
  RegistrarMantenimientoVehiculoKilometrajeMenorAlActual(this.actual);
  final int actual;
}

/// schemaVersion 80 — hay `costo > 0` pero no se dijo de dónde salió el
/// dinero. Todo gasto monetario de Vehículos exige origen financiero,
/// mismo criterio que Compras y Tiempos Extra.
///
/// NO aplica a los registros históricos anteriores a esta etapa: sus
/// filas conservan `costo` sin origen y siguen siendo válidas (decisión
/// de Marlon — sin backfill heurístico).
class RegistrarMantenimientoVehiculoOrigenFinancieroRequerido extends RegistrarMantenimientoVehiculoResultado {}

/// El origen es una TDC que no puede cargar el monto — reutiliza
/// `validarOrigenTarjeta`, la misma validación de Compras/Tiempos Extra
/// (existe, es tarjeta, está activa, tiene límite y le alcanza).
class RegistrarMantenimientoVehiculoTarjetaInvalida extends RegistrarMantenimientoVehiculoResultado {
  RegistrarMantenimientoVehiculoTarjetaInvalida(this.error, {this.disponible});
  final ErrorOrigenTarjeta error;
  final int? disponible;
}

class RegistrarMantenimientoVehiculoErrorInesperado extends RegistrarMantenimientoVehiculoResultado {
  RegistrarMantenimientoVehiculoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra un evento de mantenimiento o incidencia (Etapa 8D) — ver el
/// doc comment de `VehiculoMantenimiento` para el criterio de una sola
/// tabla para ambos conceptos. El comprobante es opcional y se adjunta
/// después, vía `AdjuntarComprobanteMantenimientoVehiculoUseCase` —
/// mismo patrón de composición segura ya usado para documentos (8C) y
/// fotografía (5D.1/8A).
class RegistrarMantenimientoVehiculoUseCase {
  RegistrarMantenimientoVehiculoUseCase(
    this._mantenimientoRepository,
    this._vehiculoRepository,
    this._kilometrajeRepository,
    this._deudaRepository,
  );

  final VehiculoMantenimientoRepository _mantenimientoRepository;
  final VehiculoRepository _vehiculoRepository;
  final VehiculoKilometrajeRepository _kilometrajeRepository;

  /// Solo para VALIDAR la tarjeta antes de escribir
  /// (`validarOrigenTarjeta`) — el cargo lo aplica el repositorio,
  /// dentro de su transacción.
  final DeudaRepository _deudaRepository;

  Future<RegistrarMantenimientoVehiculoResultado> ejecutar({
    required String vehiculoId,
    required DateTime fecha,
    int? kilometraje,
    required String tipo,
    required String descripcion,
    String? tallerProveedor,
    int? costo,
    DateTime? proximoMantenimientoFecha,
    int? proximoMantenimientoKilometraje,
    String? observaciones,
    /// Origen financiero (schemaVersion 80) — exactamente uno cuando
    /// `costo > 0`. `OrigenFinancieroGasto` es la abstracción vigente,
    /// compartida con Compras y Tiempos Extra.
    OrigenFinancieroGasto? origen,
    String? actorUsuarioId,
  }) async {
    if (await _vehiculoRepository.obtenerPorId(vehiculoId) == null) {
      return RegistrarMantenimientoVehiculoVehiculoNoExiste();
    }
    if (descripcion.trim().isEmpty) return RegistrarMantenimientoVehiculoDescripcionRequerida();

    if (proximoMantenimientoFecha != null && proximoMantenimientoFecha.isBefore(fecha)) {
      return RegistrarMantenimientoVehiculoProximoInvalido();
    }
    if (kilometraje != null && proximoMantenimientoKilometraje != null && proximoMantenimientoKilometraje < kilometraje) {
      return RegistrarMantenimientoVehiculoProximoInvalido();
    }

    if (kilometraje != null) {
      final actual = await _kilometrajeRepository.obtenerActual(vehiculoId);
      if (actual != null && kilometraje < actual.kilometraje) {
        return RegistrarMantenimientoVehiculoKilometrajeMenorAlActual(actual.kilometraje);
      }
    }

    // Todo gasto monetario pregunta de dónde salió el dinero. Sin costo
    // (o con costo 0) el registro es puramente documental y no exige
    // nada — un cambio de aceite sin importe capturado sigue siendo
    // historial válido del vehículo.
    final hayCosto = costo != null && costo > 0;
    if (hayCosto && origen == null) {
      return RegistrarMantenimientoVehiculoOrigenFinancieroRequerido();
    }

    String? cuentaFinancieraId;
    String? deudaIdTarjeta;
    if (origen is OrigenFinancieroCuenta) {
      cuentaFinancieraId = origen.cuentaFinancieraId;
    } else if (origen is OrigenFinancieroTarjeta) {
      final tarjeta = await _deudaRepository.obtenerPorId(origen.deudaId);
      final validacion = validarOrigenTarjeta(tarjeta: tarjeta, monto: costo!);
      if (!validacion.esValida) {
        return RegistrarMantenimientoVehiculoTarjetaInvalida(validacion.error!, disponible: validacion.disponible);
      }
      deudaIdTarjeta = origen.deudaId;
    }

    try {
      final registro = await _mantenimientoRepository.crear(
        vehiculoId: vehiculoId,
        fecha: fecha,
        kilometraje: kilometraje,
        tipo: tipo,
        descripcion: descripcion.trim(),
        tallerProveedor: tallerProveedor?.trim().isEmpty ?? true ? null : tallerProveedor!.trim(),
        costo: costo,
        proximoMantenimientoFecha: proximoMantenimientoFecha,
        proximoMantenimientoKilometraje: proximoMantenimientoKilometraje,
        observaciones: observaciones?.trim().isEmpty ?? true ? null : observaciones!.trim(),
        cuentaFinancieraId: cuentaFinancieraId,
        deudaIdTarjeta: deudaIdTarjeta,
        actorUsuarioId: actorUsuarioId,
      );

      await _vehiculoRepository.registrarEvento(
        vehiculoId: vehiculoId,
        tipoEvento: TipoEventoVehiculo.mantenimientoRegistrado,
        observacion: '$tipo: ${descripcion.trim()}',
        estadoNuevo: registro.costo == null ? null : jsonEncode({'costo': registro.costo}),
        actorUsuarioId: actorUsuarioId,
      );

      return RegistrarMantenimientoVehiculoExitoso(registro);
    } on SaldoInsuficienteException {
      // Un saldo insuficiente NO es un error inesperado: es un
      // rechazo previsto y accionable. Se deja propagar para que la
      // pantalla muestre disponible/requerido/faltante en vez de un
      // mensaje genérico. La transacción ya quedó revertida entera.
      rethrow;
    } catch (e) {
      return RegistrarMantenimientoVehiculoErrorInesperado(e.toString());
    }
  }
}
