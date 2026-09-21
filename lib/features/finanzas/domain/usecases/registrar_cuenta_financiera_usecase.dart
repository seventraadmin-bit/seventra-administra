import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';

import '../repositories/cuenta_financiera_repository.dart';

sealed class RegistrarCuentaFinancieraResultado {}

class RegistrarCuentaFinancieraExitoso extends RegistrarCuentaFinancieraResultado {
  RegistrarCuentaFinancieraExitoso(this.cuenta);
  final CuentaFinancieraData cuenta;
}

class RegistrarCuentaFinancieraNombreRequerido extends RegistrarCuentaFinancieraResultado {}

class RegistrarCuentaFinancieraTipoInvalido extends RegistrarCuentaFinancieraResultado {}

class RegistrarCuentaFinancieraSaldoInicialInvalido extends RegistrarCuentaFinancieraResultado {}

class RegistrarCuentaFinancieraErrorInesperado extends RegistrarCuentaFinancieraResultado {
  RegistrarCuentaFinancieraErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Alta de una `CuentaFinanciera` (Etapa 19C) — el punto de partida de
/// la posición de caja. `saldoInicial` es "lo que había" a
/// [fechaSaldoInicial]; a partir de ahí, el saldo se deriva siempre de
/// los `Ingreso`/`Egreso` que se vinculen (nunca se vuelve a capturar a
/// mano).
class RegistrarCuentaFinancieraUseCase {
  RegistrarCuentaFinancieraUseCase(this._repository, this._generarCodigo);

  final CuentaFinancieraRepository _repository;
  final GenerarCodigoUseCase _generarCodigo;

  Future<RegistrarCuentaFinancieraResultado> ejecutar({
    required String nombre,
    required String tipo,
    String? institucionId,
    String? ultimosDigitos,
    required int saldoInicial,
    required DateTime fechaSaldoInicial,
    String? observaciones,
  }) async {
    if (nombre.trim().isEmpty) return RegistrarCuentaFinancieraNombreRequerido();
    if (!TipoCuentaFinanciera.values.any((t) => t.name == tipo)) return RegistrarCuentaFinancieraTipoInvalido();
    if (saldoInicial < 0) return RegistrarCuentaFinancieraSaldoInicialInvalido();

    try {
      final codigoResultado = await _generarCodigo.ejecutar('cuenta_financiera');
      final String codigo;
      switch (codigoResultado) {
        case Ok<String>(value: final v):
          codigo = v;
        case Err<String>(failure: final f):
          return RegistrarCuentaFinancieraErrorInesperado(f.message);
      }

      final cuenta = await _repository.crear(
        codigo: codigo,
        nombre: nombre.trim(),
        tipo: tipo,
        institucionId: tipo == TipoCuentaFinanciera.banco.name ? institucionId : null,
        ultimosDigitos: tipo == TipoCuentaFinanciera.banco.name ? ultimosDigitos : null,
        saldoInicial: saldoInicial,
        fechaSaldoInicial: fechaSaldoInicial,
        observaciones: observaciones,
      );
      return RegistrarCuentaFinancieraExitoso(cuenta);
    } catch (e) {
      return RegistrarCuentaFinancieraErrorInesperado(e.toString());
    }
  }
}
