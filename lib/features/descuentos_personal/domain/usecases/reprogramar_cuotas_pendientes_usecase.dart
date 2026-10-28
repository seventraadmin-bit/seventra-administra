import 'package:riseg_one/features/descuentos_personal/data/tables/descuento_programado_cuota_table.dart'
    show EstatusDescuentoProgramadoCuota;
import 'package:riseg_one/features/descuentos_personal/data/tables/descuento_programado_empleado_table.dart'
    show EstatusDescuentoProgramado;

import '../repositories/descuento_programado_repository.dart';
import 'generar_plan_cuotas.dart';

sealed class ReprogramarCuotasPendientesResultado {}

class ReprogramarCuotasPendientesExitoso
    extends ReprogramarCuotasPendientesResultado {}

class ReprogramarCuotasPendientesNoExiste
    extends ReprogramarCuotasPendientesResultado {}

/// Solo se reprograma un descuento `activo` — uno ya `liquidado`/
/// `cancelado` no tiene cuotas futuras que mover.
class ReprogramarCuotasPendientesNoActivo
    extends ReprogramarCuotasPendientesResultado {}

/// El saldo pendiente ya está completamente cubierto por cuotas
/// `aplicada` — no queda nada por reprogramar.
class ReprogramarCuotasPendientesSinSaldoPendiente
    extends ReprogramarCuotasPendientesResultado {}

class ReprogramarCuotasPendientesNumeroCuotasInvalido
    extends ReprogramarCuotasPendientesResultado {}

class ReprogramarCuotasPendientesMotivoRequerido
    extends ReprogramarCuotasPendientesResultado {}

class ReprogramarCuotasPendientesErrorInesperado
    extends ReprogramarCuotasPendientesResultado {
  ReprogramarCuotasPendientesErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Reemplaza el plan de recuperación FUTURO de una obligación (Etapa
/// 15) — nunca toca una cuota ya `aplicada`. El importe a redistribuir
/// es siempre el `saldoPendiente` real (nunca un importe libre —
/// evita que Maestro reprograme un total distinto al que realmente se
/// debe). La numeración de las cuotas nuevas continúa donde se quedó
/// el plan anterior (nunca reinicia en 1), para que "Cuota N/M" en la
/// UI no confunda dos cuotas con el mismo número.
class ReprogramarCuotasPendientesUseCase {
  ReprogramarCuotasPendientesUseCase(this._repository);

  final DescuentoProgramadoRepository _repository;

  Future<ReprogramarCuotasPendientesResultado> ejecutar({
    required String descuentoProgramadoId,
    required int numeroCuotas,
    required DateTime fechaPrimeraCuota,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final descuento = await _repository.obtenerPorId(descuentoProgramadoId);
    if (descuento == null) return ReprogramarCuotasPendientesNoExiste();
    if (descuento.estatus != EstatusDescuentoProgramado.activo.name) {
      return ReprogramarCuotasPendientesNoActivo();
    }
    if (motivo.trim().isEmpty) {
      return ReprogramarCuotasPendientesMotivoRequerido();
    }
    if (numeroCuotas <= 0) {
      return ReprogramarCuotasPendientesNumeroCuotasInvalido();
    }

    final cuotas = await _repository.listarCuotas(descuentoProgramadoId);
    final reprogramables =
        cuotas
            .where(
              (c) =>
                  c.estatus == EstatusDescuentoProgramadoCuota.pendiente.name ||
                  c.estatus == EstatusDescuentoProgramadoCuota.reservada.name,
            )
            .toList();
    if (reprogramables.isEmpty || descuento.saldoPendiente <= 0) {
      return ReprogramarCuotasPendientesSinSaldoPendiente();
    }

    final numeroInicial = reprogramables
        .map((c) => c.numeroCuota)
        .reduce((a, b) => a < b ? a : b);
    final plan = generarPlanCuotas(
      importeOriginal: descuento.saldoPendiente,
      numeroCuotas: numeroCuotas,
      fechaPrimera: fechaPrimeraCuota,
    );

    try {
      await _repository.reprogramarCuotasPendientes(
        descuentoProgramadoId: descuentoProgramadoId,
        nuevoPlan: [
          for (final c in plan)
            (
              numeroCuota: numeroInicial + c.numeroCuota - 1,
              fechaProgramada: c.fechaProgramada,
              importe: c.importe,
            ),
        ],
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return ReprogramarCuotasPendientesExitoso();
    } catch (e) {
      return ReprogramarCuotasPendientesErrorInesperado(e.toString());
    }
  }
}
