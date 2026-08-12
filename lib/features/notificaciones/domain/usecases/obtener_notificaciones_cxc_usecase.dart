import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/cuenta_por_cobrar_repository.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/cliente_repository.dart';

import 'formato_moneda_notificacion.dart';
import 'resultado_notificacion.dart';

/// Umbral de "próxima a vencer" para Cuentas por cobrar (Etapa 14B) —
/// deliberadamente más corto que los 30 días de Vehículos: un aviso de
/// pago es más urgente/cercano que un documento vehicular.
const umbralDiasCxcProximaAVencer = 7;

class NotificacionesCxc {
  const NotificacionesCxc({required this.proximasAVencer, required this.vencidas});

  final List<ResultadoNotificacion> proximasAVencer;
  final List<ResultadoNotificacion> vencidas;
}

/// Cuentas por cobrar próximas a vencer o ya vencidas — Etapa 14B.
/// "Vencida" reutiliza `estaVencida` tal cual (mismo cálculo que ya
/// usa Dashboard); "próxima" es la única lógica genuinamente nueva
/// (`diasParaVencerCxc`, agregada en esta misma etapa). Una cuenta
/// nunca aparece en ambos grupos — son mutuamente excluyentes por
/// construcción (`estaVencida` es una u otra).
class ObtenerNotificacionesCxcUseCase {
  ObtenerNotificacionesCxcUseCase(this._cuentaRepository, this._clienteRepository);

  final CuentaPorCobrarRepository _cuentaRepository;
  final ClienteRepository _clienteRepository;

  Future<NotificacionesCxc> ejecutar({DateTime? hoy}) async {
    final referencia = hoy ?? DateTime.now();
    final cuentas = await _cuentaRepository.listar();
    final clientes = await _clienteRepository.listarActivos();
    final nombrePorCliente = {for (final c in clientes) c.id: c.nombreComercial};

    final proximas = <ResultadoNotificacion>[];
    final vencidas = <ResultadoNotificacion>[];

    for (final cuenta in cuentas) {
      if (estaVencida(cuenta, referencia)) {
        vencidas.add(_fila(cuenta, nombrePorCliente, urgente: true));
        continue;
      }
      final dias = diasParaVencerCxc(cuenta, referencia);
      if (dias != null && dias >= 0 && dias <= umbralDiasCxcProximaAVencer) {
        proximas.add(_fila(cuenta, nombrePorCliente, urgente: false));
      }
    }

    return NotificacionesCxc(proximasAVencer: proximas, vencidas: vencidas);
  }

  ResultadoNotificacion _fila(CuentaPorCobrarData cuenta, Map<String, String> nombrePorCliente, {required bool urgente}) {
    return ResultadoNotificacion(
      id: cuenta.id,
      titulo: nombrePorCliente[cuenta.clienteId] ?? cuenta.clienteId,
      subtitulo: formatoMonedaNotificacion(cuenta.saldoPendiente),
      ruta: '/finanzas/cuentas-por-cobrar',
      urgente: urgente,
    );
  }
}
