import 'package:riseg_one/core/database/app_database.dart';

/// Si un renglón de Nómina tiene algún movimiento manual o una
/// distribución Fiscal/No fiscal ya capturada a mano — independiente
/// de sus días pagables. Único filtro barato para saber qué renglones
/// vale la pena re-evaluar contra Personal
/// (`EvaluarRenglonesRequierenRevisionUseCase`) y el mismo que usa
/// `ActualizarNominaDesdePersonalUseCase` para decidir si conservar un
/// renglón que se quedó sin días.
bool renglonNominaTieneMovimientosManuales(NominaEmpleadoData renglon) {
  return renglon.prestamo != 0 ||
      renglon.tiempoExtra != 0 ||
      renglon.faltas != 0 ||
      renglon.otrosDescuentos != 0 ||
      (renglon.observaciones != null && renglon.observaciones!.trim().isNotEmpty) ||
      renglon.bonoModificadoManualmente ||
      renglon.distribucionModificadaManualmente;
}
