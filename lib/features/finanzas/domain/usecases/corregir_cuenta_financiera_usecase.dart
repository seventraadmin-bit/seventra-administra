import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/cuenta_financiera_repository.dart';

sealed class CorregirCuentaFinancieraResultado {}

class CorregirCuentaFinancieraExitoso extends CorregirCuentaFinancieraResultado {
  CorregirCuentaFinancieraExitoso(this.cuenta);
  final CuentaFinancieraData cuenta;
}

class CorregirCuentaFinancieraNoExiste extends CorregirCuentaFinancieraResultado {}

class CorregirCuentaFinancieraErrorInesperado extends CorregirCuentaFinancieraResultado {
  CorregirCuentaFinancieraErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige metadata de una `CuentaFinanciera` (Etapa 19C) — nunca
/// `tipo`/`saldoInicial`/`fechaSaldoInicial` (esos son el punto de
/// partida de la posición de caja; cambiarlos libremente
/// desincronizaría cualquier saldo ya derivado) — mismo criterio que
/// `CorregirDeudaUseCase` nunca toca `importeOriginal`.
class CorregirCuentaFinancieraUseCase {
  CorregirCuentaFinancieraUseCase(this._repository);

  final CuentaFinancieraRepository _repository;

  Future<CorregirCuentaFinancieraResultado> ejecutar({
    required String cuentaId,
    String? nombre,
    String? institucionId,
    bool limpiarInstitucionId = false,
    String? ultimosDigitos,
    bool limpiarUltimosDigitos = false,
    String? observaciones,
  }) async {
    final existente = await _repository.obtenerPorId(cuentaId);
    if (existente == null) return CorregirCuentaFinancieraNoExiste();

    try {
      final cuenta = await _repository.corregir(
        cuentaId: cuentaId,
        nombre: nombre,
        institucionId: institucionId,
        limpiarInstitucionId: limpiarInstitucionId,
        ultimosDigitos: ultimosDigitos,
        limpiarUltimosDigitos: limpiarUltimosDigitos,
        observaciones: observaciones,
      );
      return CorregirCuentaFinancieraExitoso(cuenta);
    } catch (e) {
      return CorregirCuentaFinancieraErrorInesperado(e.toString());
    }
  }
}
