import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/diagnostico_error_inesperado.dart';
import 'package:riseg_one/features/finanzas/data/tables/egreso_table.dart';

import '../repositories/egreso_repository.dart';
import 'obtener_origen_automatico_egreso_usecase.dart';

sealed class CancelarEgresoResultado {}

class CancelarEgresoExitoso extends CancelarEgresoResultado {
  CancelarEgresoExitoso(this.egreso);
  final EgresoData egreso;
}

class CancelarEgresoNoExiste extends CancelarEgresoResultado {}

class CancelarEgresoYaCancelado extends CancelarEgresoResultado {}

/// Un Egreso automático se cancela únicamente cancelando/corrigiendo
/// su entidad de origen (Compra, Pago de Nómina, Tiempo Extra, o el
/// flujo correspondiente de Deuda) — cancelarlo aquí directamente
/// dejaría Caja y bancos desincronizada de esa fuente de verdad (hueco
/// real de auditoría: antes de esta etapa, la propia documentación de
/// este archivo afirmaba erróneamente que "todo Egreso es de captura
/// manual"; ningún código verificaba el origen antes de cancelar).
class CancelarEgresoOrigenAutomatico extends CancelarEgresoResultado {
  CancelarEgresoOrigenAutomatico(this.origen);
  final OrigenAutomaticoEgreso origen;
}

class CancelarEgresoMotivoRequerido extends CancelarEgresoResultado {}

class CancelarEgresoErrorInesperado extends CancelarEgresoResultado {
  CancelarEgresoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cancela un Egreso MANUAL (Etapa 4K.1). Requiere `motivo` no vacío,
/// validado en dominio.
class CancelarEgresoUseCase {
  CancelarEgresoUseCase(this._repository, this._obtenerOrigenAutomatico);

  final EgresoRepository _repository;
  final ObtenerOrigenAutomaticoEgresoUseCase _obtenerOrigenAutomatico;

  Future<CancelarEgresoResultado> ejecutar({
    required String egresoId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final egreso = await _repository.obtenerPorId(egresoId);
    if (egreso == null) {
      return CancelarEgresoNoExiste();
    }
    if (EstatusEgreso.values.byName(egreso.estatus) == EstatusEgreso.cancelado) {
      return CancelarEgresoYaCancelado();
    }
    final origen = await _obtenerOrigenAutomatico.ejecutar(egresoId);
    if (origen != null) {
      return CancelarEgresoOrigenAutomatico(origen);
    }
    if (!motivoEsValido(motivo)) {
      return CancelarEgresoMotivoRequerido();
    }

    try {
      // `cancelarConOrigen` (Etapa "Origen financiero de Egresos
      // manuales") revierte el mecanismo que REALMENTE financió el
      // gasto: siempre el Egreso, y además el cargo a la tarjeta
      // cuando se financió con TDC — devolviendo crédito disponible
      // sin tocar Caja y bancos, que nunca se movió.
      final actualizado =
          await _repository.cancelarConOrigen(egresoId: egresoId, motivo: motivo, actorUsuarioId: actorUsuarioId);
      return CancelarEgresoExitoso(actualizado);
    } catch (e, s) {
      return CancelarEgresoErrorInesperado(diagnosticoErrorInesperado(e, s, contexto: 'CancelarEgresoUseCase'));
    }
  }
}
