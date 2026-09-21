import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';

import '../repositories/complemento_pago_repository.dart';
import '../repositories/pago_repository.dart';
import 'complemento_pago_validator.dart';

sealed class RegistrarComplementoPagoResultado {}

class RegistrarComplementoPagoExitoso extends RegistrarComplementoPagoResultado {
  RegistrarComplementoPagoExitoso(this.complemento);
  final ComplementoPagoData complemento;
}

class RegistrarComplementoPagoPagoNoExiste extends RegistrarComplementoPagoResultado {}

class RegistrarComplementoPagoPagoCancelado extends RegistrarComplementoPagoResultado {}

/// Ese Pago ya tiene un Complemento **vigente**. No impide registrar un
/// sustituto cuando el anterior está cancelado (schemaVersion 79): el
/// invariante es "a lo más uno vigente", no "a lo más uno histórico".
class RegistrarComplementoPagoYaExiste extends RegistrarComplementoPagoResultado {}

class RegistrarComplementoPagoUuidFormatoInvalido extends RegistrarComplementoPagoResultado {}

class RegistrarComplementoPagoUuidYaRegistrado extends RegistrarComplementoPagoResultado {}

class RegistrarComplementoPagoMontoInvalido extends RegistrarComplementoPagoResultado {}

/// `fechaTimbrado` anterior a `Pago.fechaPago` — un Complemento no
/// puede timbrarse antes de recibir el dinero que reporta (Resolución
/// de Marlon, confirmada explícitamente).
class RegistrarComplementoPagoFechaTimbradoAnteriorAlPago extends RegistrarComplementoPagoResultado {}

class RegistrarComplementoPagoErrorInesperado extends RegistrarComplementoPagoResultado {
  RegistrarComplementoPagoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra administrativamente un Complemento de pago ya generado y
/// timbrado externamente (Etapa 4J.3) — nunca lo genera ni lo timbra
/// el sistema, mismo criterio que `RegistrarEmisionDocumentoPorEmitirUseCase`.
class RegistrarComplementoPagoUseCase {
  RegistrarComplementoPagoUseCase(this._complementoRepository, this._pagoRepository);

  final ComplementoPagoRepository _complementoRepository;
  final PagoRepository _pagoRepository;

  Future<RegistrarComplementoPagoResultado> ejecutar({
    required String pagoId,
    required String uuid,
    String? serieFiscal,
    String? folioFiscal,
    required DateTime fechaTimbrado,
    required int montoTotal,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    final pago = await _pagoRepository.obtenerPorId(pagoId);
    if (pago == null) {
      return RegistrarComplementoPagoPagoNoExiste();
    }
    if (EstatusPago.values.byName(pago.estatus) == EstatusPago.cancelado) {
      return RegistrarComplementoPagoPagoCancelado();
    }

    // Sólo bloquea un Complemento VIGENTE (schemaVersion 79). Antes se
    // consultaba el histórico completo, así que una fila CANCELADA
    // seguía ocupando el lugar y el sustituto se rechazaba: el Pago
    // quedaba pendiente sin forma de cumplir la obligación. El índice
    // único parcial `complemento_pago_vigente_por_pago` es el candado
    // final si alguien se saltara esta validación.
    final vigente = await _complementoRepository.obtenerVigentePorPagoId(pagoId);
    if (vigente != null) {
      return RegistrarComplementoPagoYaExiste();
    }

    if (!esUuidFormatoValido(uuid)) {
      return RegistrarComplementoPagoUuidFormatoInvalido();
    }
    final uuidRepetido = await _complementoRepository.obtenerPorUuid(uuid);
    if (uuidRepetido != null) {
      return RegistrarComplementoPagoUuidYaRegistrado();
    }

    if (montoTotal <= 0) {
      return RegistrarComplementoPagoMontoInvalido();
    }

    if (fechaTimbrado.isBefore(pago.fechaPago)) {
      return RegistrarComplementoPagoFechaTimbradoAnteriorAlPago();
    }

    try {
      final complemento = await _complementoRepository.crear(
        pagoId: pagoId,
        uuid: uuid,
        serieFiscal: serieFiscal,
        folioFiscal: folioFiscal,
        fechaTimbrado: fechaTimbrado,
        montoTotal: montoTotal,
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );
      return RegistrarComplementoPagoExitoso(complemento);
    } catch (e) {
      return RegistrarComplementoPagoErrorInesperado(e.toString());
    }
  }
}
