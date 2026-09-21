import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/cliente_repository.dart';

import '../repositories/pago_repository.dart';

sealed class RegistrarPagoResultado {}

class RegistrarPagoExitoso extends RegistrarPagoResultado {
  RegistrarPagoExitoso(this.pago);
  final PagoData pago;
}

class RegistrarPagoClienteNoExiste extends RegistrarPagoResultado {}

class RegistrarPagoMontoInvalido extends RegistrarPagoResultado {}

class RegistrarPagoErrorInesperado extends RegistrarPagoResultado {
  RegistrarPagoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra un Pago (dinero recibido) sin aplicarlo a ninguna Cuenta
/// por cobrar todavía — Etapa 4J.2, Resolución 8 de Marlon: el modelo
/// debe permitir un Pago con `montoAplicado == 0`, aunque la interfaz
/// de esta etapa no exponga este flujo por sí solo (usa
/// `RegistrarPagoAplicadoUseCase` en su lugar). Existe para que una
/// futura pantalla de distribución pueda registrar el dinero primero y
/// aplicarlo después, sin requerir ningún cambio de modelo.
class RegistrarPagoUseCase {
  RegistrarPagoUseCase(this._repository, this._clienteRepository, this._generarCodigo);

  final PagoRepository _repository;
  final ClienteRepository _clienteRepository;
  final GenerarCodigoUseCase _generarCodigo;

  Future<RegistrarPagoResultado> ejecutar({
    required String clienteId,
    required int montoTotal,
    required DateTime fechaPago,
    required String formaPago,
    String? referencia,
    String? bancoOrigen,
    String? cuentaBancariaDestino,
    String? cuentaFinancieraId,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    final cliente = await _clienteRepository.obtenerPorId(clienteId);
    if (cliente == null) {
      return RegistrarPagoClienteNoExiste();
    }
    if (montoTotal <= 0) {
      return RegistrarPagoMontoInvalido();
    }

    try {
      final codigoResultado = await _generarCodigo.ejecutar('pago');
      final folioPago = codigoResultado.when(ok: (c) => c, failure: (f) => throw StateError(f.message));

      final pago = await _repository.crear(
        folioPago: folioPago,
        clienteId: clienteId,
        montoTotal: montoTotal,
        fechaPago: fechaPago,
        formaPago: formaPago,
        referencia: referencia,
        bancoOrigen: bancoOrigen,
        cuentaBancariaDestino: cuentaBancariaDestino,
        cuentaFinancieraId: cuentaFinancieraId,
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );
      return RegistrarPagoExitoso(pago);
    } catch (e) {
      return RegistrarPagoErrorInesperado(e.toString());
    }
  }
}
