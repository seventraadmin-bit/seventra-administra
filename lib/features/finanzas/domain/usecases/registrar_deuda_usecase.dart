import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/result.dart';

import '../../data/tables/deuda_table.dart' show TipoDeuda;
import '../repositories/deuda_repository.dart';

sealed class RegistrarDeudaResultado {}

class RegistrarDeudaExitoso extends RegistrarDeudaResultado {
  RegistrarDeudaExitoso(this.deuda);
  final DeudaData deuda;
}

class RegistrarDeudaNombreRequerido extends RegistrarDeudaResultado {}

/// `importeOriginal` inválido — obligatorio y `> 0` solo para tipos de
/// deuda fija (`tipo != tarjetaCredito`); una tarjeta de crédito no
/// tiene un "importe original" real (es una línea de crédito, nunca un
/// monto fijo), así que jamás produce este resultado.
class RegistrarDeudaImporteInvalido extends RegistrarDeudaResultado {}

/// `fechaOrigen` faltante — obligatoria solo para tipos de deuda fija;
/// para una tarjeta de crédito es opcional ("si se conoce").
class RegistrarDeudaFechaOrigenRequerida extends RegistrarDeudaResultado {}

/// `saldoInicial < 0`, o supera `importeOriginal`/`tarjetaLimiteCredito`
/// (el que aplique) — el saldo con el que una Deuda se incorpora a
/// RISEG ONE nunca puede superar lo que originalmente se debía ni el
/// límite de crédito capturado.
class RegistrarDeudaSaldoInicialInvalido extends RegistrarDeudaResultado {}

/// `saldoInicial > 0` sin `fechaSaldoInicial` — un saldo de apertura
/// real necesita saber a qué fecha corresponde (nunca se asume "hoy"
/// en silencio).
class RegistrarDeudaFechaSaldoInicialRequerida extends RegistrarDeudaResultado {}

class RegistrarDeudaErrorInesperado extends RegistrarDeudaResultado {
  RegistrarDeudaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Alta de una `Deuda` (Etapa 19, ampliada por "tarjeta de crédito como
/// línea revolvente") — cubre tanto una deuda nueva
/// (`saldoInicial == importeOriginal`, deuda fija) como una histórica ya
/// en curso al incorporarse a RISEG ONE (`saldoInicial < importeOriginal`
/// para deuda fija, o cualquier saldo dentro del límite para una
/// tarjeta), con el mismo formulario: el movimiento de apertura
/// (`MovimientoDeuda` tipo `altaInicial`) registra el arranque real, sin
/// generar ningún `Egreso` — la deuda ya existía antes de este alta,
/// este alta no es un pago.
///
/// `importeOriginal`/`fechaOrigen` solo son obligatorios para deuda fija
/// (`tipo != tarjetaCredito`) — una tarjeta de crédito es una línea
/// revolvente, no tiene un "importe original" y puede no conocerse su
/// fecha de apertura real.
class RegistrarDeudaUseCase {
  RegistrarDeudaUseCase(this._repository, this._generarCodigo);

  final DeudaRepository _repository;
  final GenerarCodigoUseCase _generarCodigo;

  Future<RegistrarDeudaResultado> ejecutar({
    required String nombre,
    required String tipo,
    String? acreedor,
    DateTime? fechaOrigen,
    int? importeOriginal,
    required int saldoInicial,
    DateTime? fechaSaldoInicial,
    DateTime? fechaVencimiento,
    int? pagoProgramado,
    String? periodicidad,
    double? tasaInteres,
    String? referencia,
    String? observaciones,
    String? tarjetaUltimosDigitos,
    int? tarjetaLimiteCredito,
    int? tarjetaDiaCorte,
    int? tarjetaDiaPago,
    int? tarjetaPagoMinimo,
    String? tarjetaReglaFechaPago,
    int? tarjetaDiasDespuesCorte,
    String? tarjetaTipoTasa,
    String? tarjetaTasaReferencia,
    double? tarjetaTasaDiferencial,
    bool? tarjetaTasaMasIva,
    String? tarjetaTasaDescripcion,
    double? tarjetaCat,
    bool? tarjetaCatIncluyeIva,
    DateTime? tarjetaVencimientoCubiertoHasta,
    String? actorUsuarioId,
  }) async {
    if (nombre.trim().isEmpty) return RegistrarDeudaNombreRequerido();

    final esTarjeta = tipo == TipoDeuda.tarjetaCredito.name;
    if (!esTarjeta) {
      if (fechaOrigen == null) return RegistrarDeudaFechaOrigenRequerida();
      if (importeOriginal == null || importeOriginal <= 0) return RegistrarDeudaImporteInvalido();
    }

    if (saldoInicial < 0) return RegistrarDeudaSaldoInicialInvalido();
    if (importeOriginal != null && saldoInicial > importeOriginal) return RegistrarDeudaSaldoInicialInvalido();
    if (tarjetaLimiteCredito != null && tarjetaLimiteCredito > 0 && saldoInicial > tarjetaLimiteCredito) {
      return RegistrarDeudaSaldoInicialInvalido();
    }
    // Para deuda fija, `fechaOrigen` (ya validada arriba como
    // obligatoria) alimenta el `MovimientoDeuda.altaInicial` como
    // siempre lo ha hecho — nunca rompe el flujo existente exigiendo un
    // dato nuevo. Solo una TDC puede llegar aquí con `fechaOrigen ==
    // null`, y ahí sí hace falta `fechaSaldoInicial` explícita.
    if (esTarjeta && saldoInicial > 0 && fechaOrigen == null && fechaSaldoInicial == null) {
      return RegistrarDeudaFechaSaldoInicialRequerida();
    }

    try {
      final folioResultado = await _generarCodigo.ejecutar('deuda');
      final String folio;
      switch (folioResultado) {
        case Ok<String>(value: final v):
          folio = v;
        case Err<String>(failure: final f):
          return RegistrarDeudaErrorInesperado(f.message);
      }

      final deuda = await _repository.crear(
        folio: folio,
        nombre: nombre.trim(),
        tipo: tipo,
        acreedor: acreedor,
        fechaOrigen: fechaOrigen,
        importeOriginal: importeOriginal,
        saldoInicial: saldoInicial,
        fechaSaldoInicial: fechaSaldoInicial,
        fechaVencimiento: fechaVencimiento,
        pagoProgramado: pagoProgramado,
        periodicidad: periodicidad,
        tasaInteres: tasaInteres,
        referencia: referencia,
        observaciones: observaciones,
        tarjetaUltimosDigitos: tarjetaUltimosDigitos,
        tarjetaLimiteCredito: tarjetaLimiteCredito,
        tarjetaDiaCorte: tarjetaDiaCorte,
        tarjetaDiaPago: tarjetaDiaPago,
        tarjetaPagoMinimo: tarjetaPagoMinimo,
        tarjetaReglaFechaPago: tarjetaReglaFechaPago,
        tarjetaDiasDespuesCorte: tarjetaDiasDespuesCorte,
        tarjetaTipoTasa: tarjetaTipoTasa,
        tarjetaTasaReferencia: tarjetaTasaReferencia,
        tarjetaTasaDiferencial: tarjetaTasaDiferencial,
        tarjetaTasaMasIva: tarjetaTasaMasIva,
        tarjetaTasaDescripcion: tarjetaTasaDescripcion,
        tarjetaCat: tarjetaCat,
        tarjetaCatIncluyeIva: tarjetaCatIncluyeIva,
        tarjetaVencimientoCubiertoHasta: tarjetaVencimientoCubiertoHasta,
        actorUsuarioId: actorUsuarioId,
      );
      return RegistrarDeudaExitoso(deuda);
    } catch (e) {
      return RegistrarDeudaErrorInesperado(e.toString());
    }
  }
}
