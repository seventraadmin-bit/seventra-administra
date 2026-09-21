import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/nomina_repository.dart';
import 'calcular_totales_renglon_nomina.dart';

sealed class ActualizarRenglonNominaResultado {}

class ActualizarRenglonNominaExitoso extends ActualizarRenglonNominaResultado {
  ActualizarRenglonNominaExitoso(this.renglon);
  final NominaEmpleadoData renglon;
}

class ActualizarRenglonNominaNoExiste extends ActualizarRenglonNominaResultado {}

/// La Nómina ya no está en Borrador — congelada, ver el doc comment de
/// `Nomina`.
class ActualizarRenglonNominaNominaCerrada extends ActualizarRenglonNominaResultado {}

class ActualizarRenglonNominaValorInvalido extends ActualizarRenglonNominaResultado {}

/// [distribucionManual] no suma exactamente el total a pagar
/// prospectivo (ya considerando los movimientos de esta misma
/// llamada) — nunca se escribe nada, ni movimientos ni distribución.
class ActualizarRenglonNominaNoBalancea extends ActualizarRenglonNominaResultado {}

/// Los movimientos capturados (faltas/préstamo/otros descuentos frente
/// a percepciones) producen un `totalAPagar` prospectivo negativo —
/// nunca se escribe nada (la fila tiene `CHECK (monto_fiscal >= 0)`,
/// que de otro modo rechazaría el `UPDATE` como una excepción no
/// manejada). Mismo criterio "bloquear y avisar, nunca un total
/// negativo silencioso" ya usado para descuentos de Inventario/
/// Programados pendientes.
class ActualizarRenglonNominaTotalNegativo extends ActualizarRenglonNominaResultado {}

/// Reservado para la frontera de autorización (Etapa 11C) — nunca lo
/// produce el propio caso de uso.
class ActualizarRenglonNominaErrorInesperado extends ActualizarRenglonNominaResultado {
  ActualizarRenglonNominaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Captura, en una sola operación atómica, los movimientos manuales de
/// un renglón de Nómina (Etapa 6C: préstamo, tiempo extra, bono,
/// faltas, otros descuentos, observaciones) y, opcionalmente, su
/// distribución Fiscal/No fiscal (Etapa 15, calculadora auditable) —
/// reemplaza los antiguos `ActualizarMovimientosNominaUseCase`/
/// `ActualizarDistribucionNominaUseCase`, que exigían dos escrituras
/// separadas ("Guardar movimientos" + "Guardar distribución") aunque
/// ambas afectan la misma fila y el mismo `totalAPagar`. Solo permitido
/// mientras la Nómina esté en Borrador.
///
/// `bono` marca `bonoModificadoManualmente` en cuanto se toca — evita
/// que `ActualizarNominaDesdePersonalUseCase` lo vuelva a proponer
/// automáticamente después (Resolución explícita de Marlon).
///
/// Si [distribucionManual] se provee, se valida contra el
/// `totalAPagar` PROSPECTIVO (ya con los movimientos de esta misma
/// llamada aplicados) antes de escribir nada — nunca contra el total
/// anterior. Si es `null`, la distribución se resuelve automáticamente
/// (preserva una distribución manual previa, o marca
/// `distribucionPendienteRevision` si el nuevo total ya no le cuadra —
/// nunca se ajusta en silencio).
class ActualizarRenglonNominaUseCase {
  ActualizarRenglonNominaUseCase(this._nominaRepository);

  final NominaRepository _nominaRepository;

  Future<ActualizarRenglonNominaResultado> ejecutar({
    required String nominaEmpleadoId,
    int? prestamo,
    int? tiempoExtra,
    int? bono,
    int? faltas,
    int? otrosDescuentos,
    String? observaciones,
    bool limpiarObservaciones = false,
    ({int montoFiscal, int montoNoFiscal})? distribucionManual,
    String? actorUsuarioId,
  }) async {
    final renglon = await _nominaRepository.obtenerEmpleado(nominaEmpleadoId);
    if (renglon == null) return ActualizarRenglonNominaNoExiste();

    final nomina = await _nominaRepository.obtenerPorId(renglon.nominaId);
    if (nomina == null || nomina.estatus != 'borrador') return ActualizarRenglonNominaNominaCerrada();

    final nuevoPrestamo = prestamo ?? renglon.prestamo;
    final nuevoTiempoExtra = tiempoExtra ?? renglon.tiempoExtra;
    final nuevoBono = bono ?? renglon.bono;
    final nuevoFaltas = faltas ?? renglon.faltas;
    final nuevoOtrosDescuentos = otrosDescuentos ?? renglon.otrosDescuentos;
    final nuevasObservaciones = limpiarObservaciones ? null : (observaciones ?? renglon.observaciones);

    if (nuevoPrestamo < 0 || nuevoTiempoExtra < 0 || nuevoBono < 0 || nuevoFaltas < 0 || nuevoOtrosDescuentos < 0) {
      return ActualizarRenglonNominaValorInvalido();
    }
    if (distribucionManual != null && (distribucionManual.montoFiscal < 0 || distribucionManual.montoNoFiscal < 0)) {
      return ActualizarRenglonNominaValorInvalido();
    }

    // Se calcula SIEMPRE (no solo cuando hay distribución manual) —
    // un total negativo debe bloquearse incluso cuando la distribución
    // se resuelve automáticamente (`_resolverDistribucionFiscal`
    // asignaría ese negativo directo a `montoFiscal`, violando su
    // `CHECK (monto_fiscal >= 0)` como una excepción de BD no manejada
    // en vez de un rechazo explícito).
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
      return ActualizarRenglonNominaTotalNegativo();
    }
    if (distribucionManual != null) {
      if (distribucionManual.montoFiscal + distribucionManual.montoNoFiscal != totales.totalAPagar) {
        return ActualizarRenglonNominaNoBalancea();
      }
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
      tipoEvento: distribucionManual != null ? 'distribucionModificada' : 'movimientoModificado',
      actorUsuarioId: actorUsuarioId,
    );
    return ActualizarRenglonNominaExitoso(actualizado);
  }
}
