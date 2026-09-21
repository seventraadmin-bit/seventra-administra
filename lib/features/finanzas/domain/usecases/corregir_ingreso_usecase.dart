import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/ingreso_table.dart';

import '../repositories/ingreso_repository.dart';

sealed class CorregirIngresoResultado {}

class CorregirIngresoExitoso extends CorregirIngresoResultado {
  CorregirIngresoExitoso(this.ingreso);
  final IngresoData ingreso;
}

class CorregirIngresoNoExiste extends CorregirIngresoResultado {}

class CorregirIngresoCancelado extends CorregirIngresoResultado {}

/// Un Ingreso automático (`pagoId != null`) solo se corrige a través
/// de `CorregirPagoUseCase` (Etapa 6, mismo criterio ya establecido por
/// `CancelarIngresoUseCase`) — corregirlo aquí directamente lo
/// desincronizaría en silencio de su Pago de origen.
class CorregirIngresoPagoAutomatico extends CorregirIngresoResultado {}

class CorregirIngresoMotivoRequerido extends CorregirIngresoResultado {}

class CorregirIngresoMontoInvalido extends CorregirIngresoResultado {}

class CorregirIngresoErrorInesperado extends CorregirIngresoResultado {
  CorregirIngresoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige un Ingreso MANUAL — incluye `monto` (etapa "Ingresos y
/// Egresos": antes solo metadatos, "nunca monto"; ahora el único campo
/// realmente frozen es el que un Ingreso automático de un Pago SIEMPRE
/// tiene bloqueado por completo, ver [CorregirIngresoPagoAutomatico]).
/// Requiere `motivo` no vacío, validado aquí en dominio (antes solo se
/// exigía como parámetro, nunca se validaba su contenido).
class CorregirIngresoUseCase {
  CorregirIngresoUseCase(this._repository);

  final IngresoRepository _repository;

  Future<CorregirIngresoResultado> ejecutar({
    required String ingresoId,
    int? monto,
    DateTime? fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    String? cuentaFinancieraId,
    bool limpiarCuentaFinancieraId = false,
    String? formaPago,
    String? concepto,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final ingreso = await _repository.obtenerPorId(ingresoId);
    if (ingreso == null) {
      return CorregirIngresoNoExiste();
    }
    if (EstatusIngreso.values.byName(ingreso.estatus) == EstatusIngreso.cancelado) {
      return CorregirIngresoCancelado();
    }
    if (ingreso.pagoId != null) {
      return CorregirIngresoPagoAutomatico();
    }
    if (!motivoEsValido(motivo)) {
      return CorregirIngresoMotivoRequerido();
    }
    if (monto != null && monto <= 0) {
      return CorregirIngresoMontoInvalido();
    }

    try {
      final actualizado = await _repository.corregir(
        ingresoId: ingresoId,
        monto: monto,
        fecha: fecha,
        categoriaFinancieraId: categoriaFinancieraId,
        servicioId: servicioId,
        sucursalId: sucursalId,
        areaId: areaId,
        cuentaCaja: cuentaCaja,
        cuentaFinancieraId: cuentaFinancieraId,
        limpiarCuentaFinancieraId: limpiarCuentaFinancieraId,
        formaPago: formaPago,
        concepto: concepto,
        observaciones: observaciones,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return CorregirIngresoExitoso(actualizado);
    } catch (e) {
      return CorregirIngresoErrorInesperado(e.toString());
    }
  }
}
