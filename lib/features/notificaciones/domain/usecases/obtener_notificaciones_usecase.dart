import 'obtener_notificaciones_cxc_usecase.dart';
import 'obtener_notificaciones_documentos_por_emitir_usecase.dart';
import 'obtener_notificaciones_pagos_usecase.dart';
import 'obtener_notificaciones_vehiculos_usecase.dart';
import 'resultado_notificacion.dart';

/// Resultado del Centro de notificaciones (Etapa 14B) — cada campo es
/// `null` cuando la sesión no tiene el permiso de esa sección (nunca
/// se calcula ni se consulta en ese caso), lista vacía `[]` cuando sí
/// tiene el permiso pero no hay nada pendiente — mismo criterio
/// `null` vs. `[]` que el resto del proyecto.
class ResultadosNotificaciones {
  const ResultadosNotificaciones({
    this.verificacionVehiculos,
    this.tenenciaRefrendoVehiculos,
    this.documentosPorEmitir,
    this.cxcProximasAVencer,
    this.cxcVencidas,
    this.pagosRecientes,
  });

  final List<ResultadoNotificacion>? verificacionVehiculos;
  final List<ResultadoNotificacion>? tenenciaRefrendoVehiculos;
  final List<ResultadoNotificacion>? documentosPorEmitir;
  final List<ResultadoNotificacion>? cxcProximasAVencer;
  final List<ResultadoNotificacion>? cxcVencidas;
  final List<ResultadoNotificacion>? pagosRecientes;

  int get total => [
        verificacionVehiculos,
        tenenciaRefrendoVehiculos,
        documentosPorEmitir,
        cxcProximasAVencer,
        cxcVencidas,
        pagosRecientes,
      ].fold(0, (suma, grupo) => suma + (grupo?.length ?? 0));
}

/// Compone los 4 use cases de notificaciones — nunca importa un
/// repositorio directamente. Cada `incluirXxx` la resuelve el llamador
/// consultando `PermissionService` antes de invocar `ejecutar` (mismo
/// criterio que `ObtenerResumenGeneralUseCase` de Reportes) — este use
/// case solo confía en lo que se le pide.
class ObtenerNotificacionesUseCase {
  ObtenerNotificacionesUseCase(
    this._obtenerNotificacionesVehiculos,
    this._obtenerNotificacionesDocumentosPorEmitir,
    this._obtenerNotificacionesCxc,
    this._obtenerNotificacionesPagos,
  );

  final ObtenerNotificacionesVehiculosUseCase _obtenerNotificacionesVehiculos;
  final ObtenerNotificacionesDocumentosPorEmitirUseCase _obtenerNotificacionesDocumentosPorEmitir;
  final ObtenerNotificacionesCxcUseCase _obtenerNotificacionesCxc;
  final ObtenerNotificacionesPagosUseCase _obtenerNotificacionesPagos;

  Future<ResultadosNotificaciones> ejecutar({
    required bool incluirVehiculos,
    required bool incluirComercial,
    required bool incluirFinanzas,
    DateTime? hoy,
  }) async {
    final notificacionesVehiculos = incluirVehiculos ? await _obtenerNotificacionesVehiculos.ejecutar(hoy: hoy) : null;
    final documentosPorEmitir =
        incluirComercial ? await _obtenerNotificacionesDocumentosPorEmitir.ejecutar(hoy: hoy) : null;
    final notificacionesCxc = incluirFinanzas ? await _obtenerNotificacionesCxc.ejecutar(hoy: hoy) : null;
    final pagosRecientes = incluirFinanzas ? await _obtenerNotificacionesPagos.ejecutar(hoy: hoy) : null;

    return ResultadosNotificaciones(
      verificacionVehiculos: notificacionesVehiculos?.verificacion,
      tenenciaRefrendoVehiculos: notificacionesVehiculos?.tenenciaRefrendo,
      documentosPorEmitir: documentosPorEmitir,
      cxcProximasAVencer: notificacionesCxc?.proximasAVencer,
      cxcVencidas: notificacionesCxc?.vencidas,
      pagosRecientes: pagosRecientes,
    );
  }
}
