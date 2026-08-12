import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_documento_table.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/calcular_estado_vigencia_documento.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/obtener_alertas_vehiculos_usecase.dart';

import 'resultado_notificacion.dart';

/// Verificación y Tenencia/Refrendo próximas a vencer o vencidas —
/// Etapa 14B, alcance deliberadamente acotado a estos 2 tipos (nunca
/// mantenimiento, nunca los otros tipos de `VehiculoDocumento`).
class NotificacionesVehiculos {
  const NotificacionesVehiculos({required this.verificacion, required this.tenenciaRefrendo});

  final List<ResultadoNotificacion> verificacion;
  final List<ResultadoNotificacion> tenenciaRefrendo;
}

/// Reutiliza `ObtenerAlertasVehiculosUseCase` (ya existente, ya usado
/// por Reportes 12C y Dashboard 13) — cero queries nuevas. Solo filtra
/// su `alertasDocumentos` (que ya excluye vehículos en `baja` y ya
/// viene acotado a `vencido`/`proximoAVencer`) por `tipo`.
class ObtenerNotificacionesVehiculosUseCase {
  ObtenerNotificacionesVehiculosUseCase(this._obtenerAlertas);

  final ObtenerAlertasVehiculosUseCase _obtenerAlertas;

  Future<NotificacionesVehiculos> ejecutar({DateTime? hoy}) async {
    final alertas = await _obtenerAlertas.ejecutar(hoy: hoy);

    List<ResultadoNotificacion> filtrarPorTipo(TipoDocumentoVehiculo tipo) {
      return [
        for (final alerta in alertas.alertasDocumentos)
          if (alerta.documento.tipo == tipo.name)
            ResultadoNotificacion(
              id: alerta.documento.id,
              titulo: '${alerta.vehiculo.marca} ${alerta.vehiculo.modelo}',
              subtitulo: alerta.vehiculo.placas ?? alerta.vehiculo.codigo,
              ruta: '/vehiculos/flotilla/${alerta.vehiculo.id}',
              urgente: alerta.estado == EstadoVigenciaDocumento.vencido,
            ),
      ];
    }

    return NotificacionesVehiculos(
      verificacion: filtrarPorTipo(TipoDocumentoVehiculo.verificacion),
      tenenciaRefrendo: filtrarPorTipo(TipoDocumentoVehiculo.tenenciaRefrendo),
    );
  }
}
