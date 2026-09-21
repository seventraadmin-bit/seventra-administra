import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/descuentos_personal/data/tables/descuento_programado_empleado_table.dart'
    show EstatusDescuentoProgramado;

import '../repositories/descuento_programado_repository.dart';
import 'generar_plan_cuotas.dart';

sealed class CorregirDescuentoProgramadoResultado {}

class CorregirDescuentoProgramadoExitoso
    extends CorregirDescuentoProgramadoResultado {
  CorregirDescuentoProgramadoExitoso(this.descuento);
  final DescuentoProgramadoEmpleadoData descuento;
}

class CorregirDescuentoProgramadoNoExiste
    extends CorregirDescuentoProgramadoResultado {}

/// Solo se corrige un descuento `activo` — uno `liquidado`/`cancelado`
/// ya cerró su historia; una corrección ahí reabriría una obligación
/// que el propio sistema ya declaró resuelta.
class CorregirDescuentoProgramadoNoActivo
    extends CorregirDescuentoProgramadoResultado {}

class CorregirDescuentoProgramadoMotivoRequerido
    extends CorregirDescuentoProgramadoResultado {}

class CorregirDescuentoProgramadoValorInvalido
    extends CorregirDescuentoProgramadoResultado {}

/// El nuevo monto total cambia y el saldo resultante (`nuevoTotal −
/// totalAplicadoHistorico`) queda por encima de cero — hace falta un
/// plan de cuotas futuro nuevo (mismo requisito que
/// `ReprogramarCuotasPendientesUseCase`).
class CorregirDescuentoProgramadoRequiereNuevoPlan
    extends CorregirDescuentoProgramadoResultado {}

/// Sección 3 (el punto más importante del pedido): el nuevo monto total
/// caería por debajo de lo que YA se aplicó a Nómina — igual que
/// `CorregirRenglonNominaExcedeLoPagado`, nunca se inventa un reembolso/
/// crédito/descuento futuro para cuadrar la diferencia. `totalAplicado`
/// es el monto real ya descontado (`importeOriginal − saldoPendiente`
/// antes de esta corrección).
class CorregirDescuentoProgramadoExcedeLoAplicado
    extends CorregirDescuentoProgramadoResultado {
  CorregirDescuentoProgramadoExcedeLoAplicado(this.totalAplicado);
  final int totalAplicado;
}

class CorregirDescuentoProgramadoErrorInesperado
    extends CorregirDescuentoProgramadoResultado {
  CorregirDescuentoProgramadoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrección administrativa y/o de monto total de un
/// `DescuentoProgramadoEmpleado` (Etapa 5) — nunca reescribe lo ya
/// aplicado a Nómina (`DescuentoProgramadoCuota.estatus == 'aplicada'`
/// es inmutable), siempre auditada con `estadoAnterior`/`estadoNuevo`
/// (`DiffEvento`) y motivo obligatorio.
///
/// [empleadoId]/folio son permanentemente inmutables — reasignar la
/// obligación a otro empleado siempre rompe identidad, sin importar si
/// ya tiene o no historial (ningún parámetro los acepta).
///
/// Cuando [importeOriginal] cambia, el nuevo saldo pendiente
/// (`importeOriginal − totalAplicadoHistorico`) se redistribuye en un
/// plan de cuotas futuro completamente nuevo — mismo mecanismo exacto
/// que [ReprogramarCuotasPendientesUseCase] reutiliza en
/// `DescuentoProgramadoRepository.corregir` (liberar cuotas
/// `reservada`, cancelar — nunca borrar — las reprogramables viejas,
/// insertar el plan nuevo, todo en una transacción). Si el nuevo saldo
/// llega a exactamente 0, no hace falta ningún plan nuevo y el
/// descuento pasa a `liquidado`.
class CorregirDescuentoProgramadoUseCase {
  CorregirDescuentoProgramadoUseCase(this._repository);

  final DescuentoProgramadoRepository _repository;

  Future<CorregirDescuentoProgramadoResultado> ejecutar({
    required String descuentoProgramadoId,
    String? tipo,
    String? descripcion,
    bool limpiarDescripcion = false,
    String? observaciones,
    bool limpiarObservaciones = false,
    DateTime? fechaRegistro,
    int? importeOriginal,
    int? numeroCuotas,
    DateTime? fechaPrimeraCuota,
    String? cuentaFinancieraId,
    bool limpiarCuentaFinancieraId = false,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    if (!motivoEsValido(motivo)) {
      return CorregirDescuentoProgramadoMotivoRequerido();
    }

    final descuento = await _repository.obtenerPorId(descuentoProgramadoId);
    if (descuento == null) return CorregirDescuentoProgramadoNoExiste();
    if (descuento.estatus != EstatusDescuentoProgramado.activo.name) {
      return CorregirDescuentoProgramadoNoActivo();
    }

    if (tipo != null && tipo.trim().isEmpty) {
      return CorregirDescuentoProgramadoValorInvalido();
    }

    int? nuevoSaldoPendiente;
    List<({int numeroCuota, DateTime fechaProgramada, int importe})>?
    nuevoPlanCuotas;

    final importeOriginalCambia =
        importeOriginal != null && importeOriginal != descuento.importeOriginal;
    if (importeOriginalCambia) {
      if (importeOriginal <= 0) {
        return CorregirDescuentoProgramadoValorInvalido();
      }
      final totalAplicadoHistorico =
          descuento.importeOriginal - descuento.saldoPendiente;
      if (importeOriginal < totalAplicadoHistorico) {
        return CorregirDescuentoProgramadoExcedeLoAplicado(
          totalAplicadoHistorico,
        );
      }

      nuevoSaldoPendiente = importeOriginal - totalAplicadoHistorico;
      if (nuevoSaldoPendiente > 0) {
        if (numeroCuotas == null ||
            numeroCuotas <= 0 ||
            fechaPrimeraCuota == null) {
          return CorregirDescuentoProgramadoRequiereNuevoPlan();
        }

        final cuotas = await _repository.listarCuotas(descuentoProgramadoId);
        final reprogramables =
            cuotas
                .where(
                  (c) => c.estatus == 'pendiente' || c.estatus == 'reservada',
                )
                .toList();
        final numeroInicial =
            reprogramables.isEmpty
                ? 1
                : reprogramables
                    .map((c) => c.numeroCuota)
                    .reduce((a, b) => a < b ? a : b);

        final plan = generarPlanCuotas(
          importeOriginal: nuevoSaldoPendiente,
          numeroCuotas: numeroCuotas,
          fechaPrimera: fechaPrimeraCuota,
        );
        nuevoPlanCuotas = [
          for (final c in plan)
            (
              numeroCuota: numeroInicial + c.numeroCuota - 1,
              fechaProgramada: c.fechaProgramada,
              importe: c.importe,
            ),
        ];
      } else {
        // Saldo llega a exactamente 0: nada que programar, pero las
        // reprogramables viejas (si las hay) todavía deben cancelarse
        // — una lista vacía (nunca `null`) se lo indica al repositorio.
        nuevoPlanCuotas = const [];
      }
    }

    try {
      final actualizado = await _repository.corregir(
        descuentoProgramadoId: descuentoProgramadoId,
        tipo: tipo,
        descripcion: descripcion,
        limpiarDescripcion: limpiarDescripcion,
        observaciones: observaciones,
        limpiarObservaciones: limpiarObservaciones,
        fechaRegistro: fechaRegistro,
        nuevoImporteOriginal: importeOriginal,
        nuevoSaldoPendiente: nuevoSaldoPendiente,
        nuevoPlanCuotas: nuevoPlanCuotas,
        nuevoCuentaFinancieraId: cuentaFinancieraId,
        limpiarCuentaFinancieraId: limpiarCuentaFinancieraId,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return CorregirDescuentoProgramadoExitoso(actualizado);
    } catch (e) {
      return CorregirDescuentoProgramadoErrorInesperado(e.toString());
    }
  }
}
