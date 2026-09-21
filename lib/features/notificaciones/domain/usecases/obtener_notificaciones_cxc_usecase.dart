import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/cuenta_por_cobrar_repository.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/resolver_nombres_contraparte_usecase.dart';

import 'formato_moneda_notificacion.dart';
import 'resultado_notificacion.dart';
import 'package:riseg_one/features/finanzas/domain/contraparte_cobro.dart';

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
  ObtenerNotificacionesCxcUseCase(this._cuentaRepository, this._resolverNombres);

  final CuentaPorCobrarRepository _cuentaRepository;

  /// schemaVersion 88 — la contraparte ya puede ser un Servicio
  /// Eventual. Resolver sólo Clientes dejaba esas notificaciones sin
  /// título.
  final ResolverNombresContraparteUseCase _resolverNombres;

  Future<NotificacionesCxc> ejecutar({DateTime? hoy}) async {
    final referencia = hoy ?? DateTime.now();
    final cuentas = await _cuentaRepository.listar();
    final nombres = await _resolverNombres.paraCuentas(cuentas);

    final proximas = <ResultadoNotificacion>[];
    final vencidas = <ResultadoNotificacion>[];

    for (final cuenta in cuentas) {
      if (estaVencida(cuenta, referencia)) {
        vencidas.add(_fila(cuenta, nombres, urgente: true));
        continue;
      }
      final dias = diasParaVencerCxc(cuenta, referencia);
      if (dias != null && dias >= 0 && dias <= umbralDiasCxcProximaAVencer) {
        proximas.add(_fila(cuenta, nombres, urgente: false));
      }
    }

    return NotificacionesCxc(proximasAVencer: proximas, vencidas: vencidas);
  }

  ResultadoNotificacion _fila(CuentaPorCobrarData cuenta, NombresContraparte nombres, {required bool urgente}) {
    return ResultadoNotificacion(
      id: cuenta.id,
      titulo: nombres.de(contraparteDeCuenta(cuenta)),
      subtitulo: formatoMonedaNotificacion(cuenta.saldoPendiente),
      ruta: '/finanzas/cuentas-por-cobrar',
      urgente: urgente,
    );
  }
}
