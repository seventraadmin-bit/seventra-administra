import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

import '../repositories/entidad_fiscal_repository.dart';
import '../repositories/servicio_repository.dart';

/// Resultado de [AsignarEntidadFiscalAServicioUseCase] — tipos propios
/// para que la pantalla muestre un mensaje específico, mismo patrón que
/// `CambiarEstatusServicioResultado`.
sealed class AsignarEntidadFiscalAServicioResultado {}

class AsignarEntidadFiscalAServicioExitoso extends AsignarEntidadFiscalAServicioResultado {
  AsignarEntidadFiscalAServicioExitoso(this.servicio);
  final ServicioData servicio;
}

/// La Entidad fiscal no existe o pertenece a un Cliente distinto del
/// Servicio.
class AsignarEntidadFiscalAServicioNoPerteneceAlCliente extends AsignarEntidadFiscalAServicioResultado {}

/// Solo posible al asignar una Entidad fiscal *nueva*: está archivada.
/// Una Entidad fiscal ya asignada que se archiva después nunca pasa por
/// aquí — la relación se conserva y el expediente solo advierte (ver
/// `ServicioExpedienteData.entidadFiscalArchivada`).
class AsignarEntidadFiscalAServicioNoDisponible extends AsignarEntidadFiscalAServicioResultado {}

/// Cambiar o retirar una Entidad fiscal YA asignada puede mover a quién
/// se le factura: exige explicar por qué. La PRIMERA asignación no —
/// es parte de la configuración inicial normal del Servicio.
class AsignarEntidadFiscalAServicioMotivoRequerido extends AsignarEntidadFiscalAServicioResultado {}

class AsignarEntidadFiscalAServicioErrorInesperado extends AsignarEntidadFiscalAServicioResultado {
  AsignarEntidadFiscalAServicioErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Asigna o quita la Entidad fiscal de un Servicio — acción
/// independiente del formulario general de datos generales (Etapa
/// 4F.2, punto 1). `entidadFiscalId: null` siempre quita la asignación
/// sin ninguna validación (quitar nunca puede fallar por reglas de
/// negocio). Asignar una nueva sí exige pertenencia al mismo Cliente y
/// estar activa — ambas solo en el momento de la asignación, nunca
/// reevaluadas retroactivamente.
class AsignarEntidadFiscalAServicioUseCase {
  AsignarEntidadFiscalAServicioUseCase(this._servicioRepository, this._entidadFiscalRepository);

  final ServicioRepository _servicioRepository;
  final EntidadFiscalRepository _entidadFiscalRepository;

  /// [motivo] sólo es obligatorio cuando ya había una Entidad fiscal
  /// asignada y ésta cambia o se retira — ver
  /// [exigeMotivoAsignacionEntidadFiscal].
  Future<AsignarEntidadFiscalAServicioResultado> ejecutar({
    required String servicioId,
    required String? entidadFiscalId,
    String? motivo,
    String? actorUsuarioId,
  }) async {
    final servicioActual = await _servicioRepository.obtenerPorId(servicioId);
    if (servicioActual == null) {
      return AsignarEntidadFiscalAServicioErrorInesperado('Servicio no encontrado: $servicioId');
    }

    final exigeMotivo = exigeMotivoAsignacionEntidadFiscal(
      anterior: servicioActual.entidadFiscalId,
      nueva: entidadFiscalId,
    );
    if (exigeMotivo && !motivoEsValido(motivo)) {
      return AsignarEntidadFiscalAServicioMotivoRequerido();
    }
    final motivoNormalizado = exigeMotivo ? motivo!.trim() : null;

    if (entidadFiscalId == null) {
      try {
        final servicio = await _servicioRepository.asignarEntidadFiscal(
          servicioId: servicioId,
          entidadFiscalId: null,
          motivo: motivoNormalizado,
          actorUsuarioId: actorUsuarioId,
        );
        return AsignarEntidadFiscalAServicioExitoso(servicio);
      } catch (e) {
        return AsignarEntidadFiscalAServicioErrorInesperado(e.toString());
      }
    }

    final entidad = await _entidadFiscalRepository.obtenerPorId(entidadFiscalId);
    if (entidad == null || entidad.clienteId != servicioActual.clienteId) {
      return AsignarEntidadFiscalAServicioNoPerteneceAlCliente();
    }
    if (entidad.cicloVidaRegistro != CicloVidaRegistro.activo.name) {
      return AsignarEntidadFiscalAServicioNoDisponible();
    }

    try {
      final servicio = await _servicioRepository.asignarEntidadFiscal(
        servicioId: servicioId,
        entidadFiscalId: entidadFiscalId,
        motivo: motivoNormalizado,
        actorUsuarioId: actorUsuarioId,
      );
      return AsignarEntidadFiscalAServicioExitoso(servicio);
    } catch (e) {
      return AsignarEntidadFiscalAServicioErrorInesperado(e.toString());
    }
  }
}

/// Única definición de cuándo asignar una Entidad fiscal exige
/// motivo: sólo si YA había una y el destino es distinto (cambio
/// A→B o retiro A→null). La primera asignación (null→A) y un
/// reasignar el mismo valor no lo exigen. La pantalla consulta esta
/// función para saber si abrir el diálogo de motivo; el caso de uso
/// la vuelve a aplicar como guardia real.
bool exigeMotivoAsignacionEntidadFiscal({required String? anterior, required String? nueva}) {
  if (anterior == null) return false;
  return anterior != nueva;
}
