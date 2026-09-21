import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/nomina_repository.dart';
import '../repositories/pago_nomina_repository.dart';

/// Motivos de cancelación de una Nómina completa (Etapa 4) — mismo
/// shape que `MotivoCancelacionCompra`.
enum MotivoCancelacionNomina {
  errorDeCaptura,
  periodoDuplicado,
  periodoIncorrecto,
  otro,
}

/// Etiqueta traducida de cada [MotivoCancelacionNomina] — mismo
/// criterio que `MotivoCancelacionCompraLabel`.
extension MotivoCancelacionNominaLabel on MotivoCancelacionNomina {
  String get etiqueta => switch (this) {
        MotivoCancelacionNomina.errorDeCaptura => 'Error de captura',
        MotivoCancelacionNomina.periodoDuplicado => 'Periodo duplicado',
        MotivoCancelacionNomina.periodoIncorrecto => 'Periodo incorrecto',
        MotivoCancelacionNomina.otro => 'Otro',
      };
}

sealed class CancelarNominaResultado {}

class CancelarNominaExitoso extends CancelarNominaResultado {
  CancelarNominaExitoso(this.nomina);
  final NominaData nomina;
}

class CancelarNominaNoExiste extends CancelarNominaResultado {}

class CancelarNominaYaCancelada extends CancelarNominaResultado {}

/// Sección 18 (punto de decisión ya resuelto por Marlon): solo
/// Borrador o Cerrada-sin-ningún-`PagoNomina` real pueden cancelarse
/// por completo — Cerrada-con-pagos-parciales y Pagada nunca (ahí se
/// cancela pago por pago, ya soportado por `CancelarPagoNominaUseCase`).
class CancelarNominaTienePagos extends CancelarNominaResultado {}

class CancelarNominaDetalleRequerido extends CancelarNominaResultado {}

class CancelarNominaErrorInesperado extends CancelarNominaResultado {
  CancelarNominaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cancelación de una Nómina completa (Etapa 4, Sección 9 del pedido)
/// — a diferencia de la eliminación física (destructiva, Maestro-only,
/// solo Borrador), esta es una salida controlada y auditable
/// disponible también para Cerrada-sin-pagos, que conserva la fila
/// (`estatus = cancelada`) en vez de borrarla.
class CancelarNominaUseCase {
  CancelarNominaUseCase(this._nominaRepository, this._pagoNominaRepository);

  final NominaRepository _nominaRepository;
  final PagoNominaRepository _pagoNominaRepository;

  Future<CancelarNominaResultado> ejecutar({
    required String nominaId,
    required MotivoCancelacionNomina motivo,
    String? detalle,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    final detalleLimpio = detalle?.trim();
    if (motivo == MotivoCancelacionNomina.otro && (detalleLimpio == null || detalleLimpio.isEmpty)) {
      return CancelarNominaDetalleRequerido();
    }

    final nomina = await _nominaRepository.obtenerPorId(nominaId);
    if (nomina == null) return CancelarNominaNoExiste();
    if (nomina.estatus == 'cancelada') return CancelarNominaYaCancelada();
    if (nomina.estatus == 'pagada') return CancelarNominaTienePagos();

    if (nomina.estatus == 'cerrada') {
      final pagos = await _pagoNominaRepository.listarPorNomina(nominaId);
      if (pagos.isNotEmpty) return CancelarNominaTienePagos();
    }

    final cancelada = await _nominaRepository.cancelar(
      nominaId: nominaId,
      motivo: motivo.name,
      detalle: detalleLimpio,
      observaciones: observaciones,
      actorUsuarioId: actorUsuarioId,
    );
    return CancelarNominaExitoso(cancelada);
  }
}
