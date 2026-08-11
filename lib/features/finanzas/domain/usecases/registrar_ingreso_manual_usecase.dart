import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/ingreso_repository.dart';

sealed class RegistrarIngresoManualResultado {}

class RegistrarIngresoManualExitoso extends RegistrarIngresoManualResultado {
  RegistrarIngresoManualExitoso(this.ingreso);
  final IngresoData ingreso;
}

class RegistrarIngresoManualMontoInvalido extends RegistrarIngresoManualResultado {}

class RegistrarIngresoManualConceptoRequerido extends RegistrarIngresoManualResultado {}

class RegistrarIngresoManualErrorInesperado extends RegistrarIngresoManualResultado {
  RegistrarIngresoManualErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra un Ingreso que nunca pasó por una Cuenta por cobrar (Etapa
/// 4K.1) — el Ingreso automático desde un `Pago` no usa este caso de
/// uso, se compone dentro de `PagoRepositoryImpl` (ver la nota de
/// arquitectura ahí).
class RegistrarIngresoManualUseCase {
  RegistrarIngresoManualUseCase(this._repository, this._generarCodigo);

  final IngresoRepository _repository;
  final GenerarCodigoUseCase _generarCodigo;

  Future<RegistrarIngresoManualResultado> ejecutar({
    required int monto,
    required DateTime fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    required String formaPago,
    required String concepto,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    if (monto <= 0) {
      return RegistrarIngresoManualMontoInvalido();
    }
    if (concepto.trim().isEmpty) {
      return RegistrarIngresoManualConceptoRequerido();
    }

    try {
      final codigoResultado = await _generarCodigo.ejecutar('ingreso');
      final folioIngreso = codigoResultado.when(ok: (c) => c, failure: (f) => throw StateError(f.message));

      final ingreso = await _repository.crear(
        folioIngreso: folioIngreso,
        monto: monto,
        fecha: fecha,
        categoriaFinancieraId: categoriaFinancieraId,
        servicioId: servicioId,
        sucursalId: sucursalId,
        areaId: areaId,
        cuentaCaja: cuentaCaja,
        formaPago: formaPago,
        concepto: concepto.trim(),
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );
      return RegistrarIngresoManualExitoso(ingreso);
    } catch (e) {
      return RegistrarIngresoManualErrorInesperado(e.toString());
    }
  }
}
