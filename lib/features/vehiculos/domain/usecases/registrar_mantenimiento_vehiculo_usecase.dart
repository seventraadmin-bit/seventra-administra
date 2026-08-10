import 'package:riseg_one/core/database/app_database.dart';

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
  RegistrarMantenimientoVehiculoUseCase(this._mantenimientoRepository, this._vehiculoRepository, this._kilometrajeRepository);

  final VehiculoMantenimientoRepository _mantenimientoRepository;
  final VehiculoRepository _vehiculoRepository;
  final VehiculoKilometrajeRepository _kilometrajeRepository;

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
      );
      return RegistrarMantenimientoVehiculoExitoso(registro);
    } catch (e) {
      return RegistrarMantenimientoVehiculoErrorInesperado(e.toString());
    }
  }
}
