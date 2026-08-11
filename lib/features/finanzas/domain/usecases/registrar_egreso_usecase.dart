import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/egreso_repository.dart';

sealed class RegistrarEgresoResultado {}

class RegistrarEgresoExitoso extends RegistrarEgresoResultado {
  RegistrarEgresoExitoso(this.egreso);
  final EgresoData egreso;
}

class RegistrarEgresoMontoInvalido extends RegistrarEgresoResultado {}

class RegistrarEgresoConceptoRequerido extends RegistrarEgresoResultado {}

class RegistrarEgresoErrorInesperado extends RegistrarEgresoResultado {
  RegistrarEgresoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra un Egreso (Etapa 4K.1) — 100% captura manual, sin ninguna
/// fuente automática todavía (Nómina/Compras no existen).
class RegistrarEgresoUseCase {
  RegistrarEgresoUseCase(this._repository, this._generarCodigo);

  final EgresoRepository _repository;
  final GenerarCodigoUseCase _generarCodigo;

  Future<RegistrarEgresoResultado> ejecutar({
    required int monto,
    required DateTime fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    required String formaPago,
    String? beneficiario,
    required String concepto,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    if (monto <= 0) {
      return RegistrarEgresoMontoInvalido();
    }
    if (concepto.trim().isEmpty) {
      return RegistrarEgresoConceptoRequerido();
    }

    try {
      final codigoResultado = await _generarCodigo.ejecutar('egreso');
      final folioEgreso = codigoResultado.when(ok: (c) => c, failure: (f) => throw StateError(f.message));

      final egreso = await _repository.crear(
        folioEgreso: folioEgreso,
        monto: monto,
        fecha: fecha,
        categoriaFinancieraId: categoriaFinancieraId,
        servicioId: servicioId,
        sucursalId: sucursalId,
        areaId: areaId,
        cuentaCaja: cuentaCaja,
        formaPago: formaPago,
        beneficiario: beneficiario,
        concepto: concepto.trim(),
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );
      return RegistrarEgresoExitoso(egreso);
    } catch (e) {
      return RegistrarEgresoErrorInesperado(e.toString());
    }
  }
}
