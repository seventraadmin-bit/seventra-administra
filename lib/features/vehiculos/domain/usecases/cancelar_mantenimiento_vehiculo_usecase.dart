import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/vehiculo_mantenimiento_table.dart';
import '../../data/tables/vehiculo_table.dart';
import '../repositories/vehiculo_mantenimiento_repository.dart';
import '../repositories/vehiculo_repository.dart';

sealed class CancelarMantenimientoVehiculoResultado {}

class CancelarMantenimientoVehiculoExitoso extends CancelarMantenimientoVehiculoResultado {
  CancelarMantenimientoVehiculoExitoso(this.registro);
  final VehiculoMantenimientoData registro;
}

class CancelarMantenimientoVehiculoNoExiste extends CancelarMantenimientoVehiculoResultado {}

/// Ya estaba anulado — nunca se ejecuta una segunda reversión.
class CancelarMantenimientoVehiculoYaCancelado extends CancelarMantenimientoVehiculoResultado {}

class CancelarMantenimientoVehiculoMotivoRequerido extends CancelarMantenimientoVehiculoResultado {}

class CancelarMantenimientoVehiculoErrorInesperado extends CancelarMantenimientoVehiculoResultado {
  CancelarMantenimientoVehiculoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Anula un mantenimiento/incidencia y revierte EXACTAMENTE su efecto
/// financiero (schemaVersion 80).
///
///  - origen Cuenta → el `Egreso` pasa a `cancelado` y la cuenta
///    recupera el importe exacto;
///  - origen TDC → `revertirCargoMantenimientoVehiculo` emite un
///    `ajusteNegativo` por el neto aportado, liberando el crédito.
///
/// **Nunca borra nada**: el registro conserva su `egresoId`/`deudaId`
/// como evidencia de qué se revirtió. Un error de captura no obliga a
/// destruir historial (pedido explícito de Marlon).
///
/// Doble candado contra la doble reversión: este caso de uso rechaza un
/// registro ya `cancelado`, y aun si se llamara al repositorio directo,
/// el neto aportado a la tarjeta ya sería 0 y no se escribiría nada.
class CancelarMantenimientoVehiculoUseCase {
  CancelarMantenimientoVehiculoUseCase(this._mantenimientoRepository, this._vehiculoRepository);

  final VehiculoMantenimientoRepository _mantenimientoRepository;
  final VehiculoRepository _vehiculoRepository;

  Future<CancelarMantenimientoVehiculoResultado> ejecutar({
    required String vehiculoMantenimientoId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    if (!motivoEsValido(motivo)) return CancelarMantenimientoVehiculoMotivoRequerido();

    final actual = await _mantenimientoRepository.obtenerPorId(vehiculoMantenimientoId);
    if (actual == null) return CancelarMantenimientoVehiculoNoExiste();
    if (EstatusMantenimientoVehiculo.values.byName(actual.estatus) == EstatusMantenimientoVehiculo.cancelado) {
      return CancelarMantenimientoVehiculoYaCancelado();
    }

    try {
      final cancelado = await _mantenimientoRepository.cancelar(
        vehiculoMantenimientoId: vehiculoMantenimientoId,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );

      await _vehiculoRepository.registrarEvento(
        vehiculoId: actual.vehiculoId,
        tipoEvento: TipoEventoVehiculo.mantenimientoCancelado,
        observacion: motivo,
        estadoAnterior: EstatusMantenimientoVehiculo.registrado.name,
        estadoNuevo: EstatusMantenimientoVehiculo.cancelado.name,
        actorUsuarioId: actorUsuarioId,
      );

      return CancelarMantenimientoVehiculoExitoso(cancelado);
    } catch (e) {
      return CancelarMantenimientoVehiculoErrorInesperado(e.toString());
    }
  }
}
