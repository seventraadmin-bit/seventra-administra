import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/auditoria/enmascarar_identificador.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/linea_telefonica_table.dart';
import '../repositories/linea_telefonica_repository.dart';

sealed class CorregirLineaTelefonicaResultado {}

class CorregirLineaTelefonicaExitoso extends CorregirLineaTelefonicaResultado {
  CorregirLineaTelefonicaExitoso(this.linea);
  final LineaTelefonicaData linea;
}

class CorregirLineaTelefonicaNoExiste extends CorregirLineaTelefonicaResultado {}

class CorregirLineaTelefonicaNumeroDuplicado extends CorregirLineaTelefonicaResultado {}

/// Corregir la identidad de una línea (número, ICCID, operador) exige
/// explicar por qué — mismo estándar que Vehículos, Compras, Personal,
/// Finanzas y Nómina. Era la excepción que quedaba.
class CorregirLineaTelefonicaMotivoRequerido extends CorregirLineaTelefonicaResultado {}

class CorregirLineaTelefonicaOperadorOtroNombreRequerido extends CorregirLineaTelefonicaResultado {}

class CorregirLineaTelefonicaErrorInesperado extends CorregirLineaTelefonicaResultado {
  CorregirLineaTelefonicaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige metadatos de una línea telefónica — nunca `codigo` (generado,
/// fijo desde la creación, mismo criterio que `Vehiculo.codigo`).
///
/// Desde la schemaVersion 81 sigue el estándar completo de corrección
/// del proyecto: `motivo` obligatorio, `actorUsuarioId`, y un evento
/// en `LineaTelefonicaEvento` con el diff de **solo** los campos que
/// realmente cambiaron. Antes cambiaba número e ICCID —la identidad de
/// la SIM— sin dejar ningún rastro.
///
/// PRIVACIDAD: `numero` e `iccid` entran al diff **enmascarados**
/// (`····3456`). El auditor puede verificar QUE cambiaron y distinguir
/// un valor de otro; la Auditoría no se convierte en un directorio de
/// SIMs. Ver `enmascararIdentificador`.
class CorregirLineaTelefonicaUseCase {
  CorregirLineaTelefonicaUseCase(this._repository);

  final LineaTelefonicaRepository _repository;

  Future<CorregirLineaTelefonicaResultado> ejecutar({
    required String lineaTelefonicaId,
    String? numero,
    String? operador,
    String? operadorOtroNombre,
    String? modalidadSim,
    String? iccid,
    DateTime? fechaActivacion,
    String? observaciones,
    bool limpiarNumero = false,
    bool limpiarOperadorOtroNombre = false,
    bool limpiarIccid = false,
    bool limpiarFechaActivacion = false,
    bool limpiarObservaciones = false,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    if (!motivoEsValido(motivo)) return CorregirLineaTelefonicaMotivoRequerido();

    final linea = await _repository.obtenerPorId(lineaTelefonicaId);
    if (linea == null) return CorregirLineaTelefonicaNoExiste();

    final operadorFinal = operador ?? linea.operador;
    if (operadorFinal == 'otro') {
      final nombreFinal = operadorOtroNombre ?? (limpiarOperadorOtroNombre ? null : linea.operadorOtroNombre);
      if (nombreFinal == null || nombreFinal.trim().isEmpty) {
        return CorregirLineaTelefonicaOperadorOtroNombreRequerido();
      }
    }

    final numeroNormalizado = numero?.trim().isEmpty ?? true ? null : numero!.trim();
    if (numeroNormalizado != null) {
      final existente = await _repository.obtenerPorNumero(numeroNormalizado);
      if (existente != null && existente.id != lineaTelefonicaId) return CorregirLineaTelefonicaNumeroDuplicado();
    }

    try {
      final actualizada = await _repository.corregir(
        lineaTelefonicaId: lineaTelefonicaId,
        numero: numeroNormalizado,
        operador: operador,
        operadorOtroNombre: operadorFinal == 'otro' ? operadorOtroNombre?.trim() : null,
        modalidadSim: modalidadSim,
        iccid: iccid,
        fechaActivacion: fechaActivacion,
        observaciones: observaciones,
        limpiarNumero: limpiarNumero,
        limpiarOperadorOtroNombre: operadorFinal != 'otro' || limpiarOperadorOtroNombre,
        limpiarIccid: limpiarIccid,
        limpiarFechaActivacion: limpiarFechaActivacion,
        limpiarObservaciones: limpiarObservaciones,
      );
      // Solo lo que cambió de verdad. Los dos identificadores
      // sensibles se anotan enmascarados; el resto, tal cual.
      final diff = DiffEvento()
        ..anotar('numero', enmascararIdentificador(linea.numero), enmascararIdentificador(actualizada.numero))
        ..anotar('iccid', enmascararIdentificador(linea.iccid), enmascararIdentificador(actualizada.iccid))
        ..anotar('operador', linea.operador, actualizada.operador)
        ..anotar('operadorOtroNombre', linea.operadorOtroNombre, actualizada.operadorOtroNombre)
        ..anotar('modalidadSim', linea.modalidadSim, actualizada.modalidadSim)
        ..anotar('fechaActivacion', linea.fechaActivacion, actualizada.fechaActivacion)
        ..anotar('observaciones', linea.observaciones, actualizada.observaciones);

      // Una "corrección" que no cambió nada no es una corrección: no
      // ensucia el historial con ruido.
      if (diff.hayCambios) {
        await _repository.registrarEvento(
          lineaTelefonicaId: lineaTelefonicaId,
          tipoEvento: TipoEventoLineaTelefonica.corregida,
          observacion: motivo,
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          actorUsuarioId: actorUsuarioId,
        );
      }

      return CorregirLineaTelefonicaExitoso(actualizada);
    } catch (e) {
      return CorregirLineaTelefonicaErrorInesperado(e.toString());
    }
  }
}
