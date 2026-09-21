import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/nomina_repository.dart';
import '../repositories/pago_nomina_repository.dart';
import 'calcular_totales_renglon_nomina.dart';

sealed class CorregirRenglonNominaResultado {}

class CorregirRenglonNominaExitoso extends CorregirRenglonNominaResultado {
  CorregirRenglonNominaExitoso(this.renglon);
  final NominaEmpleadoData renglon;
}

class CorregirRenglonNominaNoExiste extends CorregirRenglonNominaResultado {}

/// La Nómina todavía está en Borrador — usa
/// `ActualizarRenglonNominaUseCase`, la edición operativa normal
/// (nunca exige motivo, nunca puede exceder lo ya pagado porque en
/// Borrador nunca hay un pago real).
class CorregirRenglonNominaNominaBorrador extends CorregirRenglonNominaResultado {}

class CorregirRenglonNominaNominaCancelada extends CorregirRenglonNominaResultado {}

class CorregirRenglonNominaMotivoRequerido extends CorregirRenglonNominaResultado {}

class CorregirRenglonNominaValorInvalido extends CorregirRenglonNominaResultado {}

class CorregirRenglonNominaNoBalancea extends CorregirRenglonNominaResultado {}

class CorregirRenglonNominaTotalNegativo extends CorregirRenglonNominaResultado {}

/// Sección 18 (punto de decisión ya resuelto por Marlon): el total
/// corregido caería por debajo de lo que YA se pagó — la arquitectura
/// actual no tiene ninguna figura de "saldo a favor"/sobrepago, así
/// que la corrección se rechaza en vez de dejar un saldo pendiente
/// negativo. [totalPagadoHistorico] es el monto real ya aplicado
/// (`AplicacionPagoNomina` activa) — el usuario debe cancelar el pago
/// excedente primero.
class CorregirRenglonNominaExcedeLoPagado extends CorregirRenglonNominaResultado {
  CorregirRenglonNominaExcedeLoPagado(this.totalPagadoHistorico);
  final int totalPagadoHistorico;
}

class CorregirRenglonNominaErrorInesperado extends CorregirRenglonNominaResultado {
  CorregirRenglonNominaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrección de un renglón de una Nómina ya `cerrada`/`pagada` (Etapa
/// 4) — operación explícita, autorizada (`nomina.corregir`, distinto
/// de `nomina.modificar` que solo alcanza a Borrador) y siempre
/// auditada con `estadoAnterior`/`estadoNuevo` (`DiffEvento`) y motivo
/// obligatorio.
///
/// Nunca reescribe lo ya pagado: `AplicacionPagoNomina` (el pago
/// histórico) es inmutable — la corrección solo cambia `totalAPagar`
/// prospectivo, y el saldo pendiente se recalcula (`nuevoTotal −
/// totalPagadoHistorico`) reutilizando `PagoNominaRepository.
/// sincronizarEstatusPago` (llamado internamente por
/// `NominaRepository.actualizarRenglon`), que también decide, con la
/// MISMA lógica que ya usa un pago real, si la Nómina debe demoverse
/// de `pagada` a `cerrada` cuando la corrección reabre saldo
/// pendiente (Sección 6 del pedido) — cero lógica nueva duplicada.
class CorregirRenglonNominaUseCase {
  CorregirRenglonNominaUseCase(this._nominaRepository, this._pagoNominaRepository);

  final NominaRepository _nominaRepository;
  final PagoNominaRepository _pagoNominaRepository;

  Future<CorregirRenglonNominaResultado> ejecutar({
    required String nominaEmpleadoId,
    int? prestamo,
    int? tiempoExtra,
    int? bono,
    int? faltas,
    int? otrosDescuentos,
    String? observaciones,
    bool limpiarObservaciones = false,
    ({int montoFiscal, int montoNoFiscal})? distribucionManual,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    if (!motivoEsValido(motivo)) return CorregirRenglonNominaMotivoRequerido();

    final renglon = await _nominaRepository.obtenerEmpleado(nominaEmpleadoId);
    if (renglon == null) return CorregirRenglonNominaNoExiste();

    final nomina = await _nominaRepository.obtenerPorId(renglon.nominaId);
    if (nomina == null) return CorregirRenglonNominaNoExiste();
    if (nomina.estatus == 'borrador') return CorregirRenglonNominaNominaBorrador();
    if (nomina.estatus == 'cancelada') return CorregirRenglonNominaNominaCancelada();

    final nuevoPrestamo = prestamo ?? renglon.prestamo;
    final nuevoTiempoExtra = tiempoExtra ?? renglon.tiempoExtra;
    final nuevoBono = bono ?? renglon.bono;
    final nuevoFaltas = faltas ?? renglon.faltas;
    final nuevoOtrosDescuentos = otrosDescuentos ?? renglon.otrosDescuentos;
    final nuevasObservaciones = limpiarObservaciones ? null : (observaciones ?? renglon.observaciones);

    if (nuevoPrestamo < 0 || nuevoTiempoExtra < 0 || nuevoBono < 0 || nuevoFaltas < 0 || nuevoOtrosDescuentos < 0) {
      return CorregirRenglonNominaValorInvalido();
    }
    if (distribucionManual != null && (distribucionManual.montoFiscal < 0 || distribucionManual.montoNoFiscal < 0)) {
      return CorregirRenglonNominaValorInvalido();
    }

    final totales = calcularTotalesRenglonNomina(
      importeBase: renglon.importeBase,
      pagoPorDia: renglon.pagoPorDia,
      bono: nuevoBono,
      tiempoExtra: nuevoTiempoExtra,
      prestamo: nuevoPrestamo,
      faltas: nuevoFaltas,
      otrosDescuentos: nuevoOtrosDescuentos,
      descuentosInventario: renglon.descuentosInventario,
      descuentosProgramados: renglon.descuentosProgramados,
    );
    if (totales.totalAPagar < 0) {
      return CorregirRenglonNominaTotalNegativo();
    }
    if (distribucionManual != null) {
      if (distribucionManual.montoFiscal + distribucionManual.montoNoFiscal != totales.totalAPagar) {
        return CorregirRenglonNominaNoBalancea();
      }
    }

    // Sección 18: bloquear en vez de dejar un sobrepago sin figura
    // contable — nunca reescribe lo ya pagado.
    final saldoActual = await _pagoNominaRepository.saldoPendientePago(nominaEmpleadoId);
    final totalPagadoHistorico = renglon.totalAPagar - saldoActual;
    if (totales.totalAPagar < totalPagadoHistorico) {
      return CorregirRenglonNominaExcedeLoPagado(totalPagadoHistorico);
    }

    final bonoModificadoManualmente = bono != null ? true : renglon.bonoModificadoManualmente;

    final actualizado = await _nominaRepository.actualizarRenglon(
      nominaEmpleadoId: nominaEmpleadoId,
      prestamo: nuevoPrestamo,
      tiempoExtra: nuevoTiempoExtra,
      bono: nuevoBono,
      bonoModificadoManualmente: bonoModificadoManualmente,
      faltas: nuevoFaltas,
      otrosDescuentos: nuevoOtrosDescuentos,
      observaciones: nuevasObservaciones,
      distribucionManual: distribucionManual,
      tipoEvento: 'corregida',
      motivo: motivo,
      actorUsuarioId: actorUsuarioId,
    );
    return CorregirRenglonNominaExitoso(actualizado);
  }
}
