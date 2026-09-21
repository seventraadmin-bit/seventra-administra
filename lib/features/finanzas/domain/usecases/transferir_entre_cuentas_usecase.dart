import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/error/result.dart';

import '../../data/repositories/transferencia_cuenta_repository_impl.dart';
import '../politica_saldo_cuenta.dart';

sealed class TransferirEntreCuentasResultado {}

class TransferirEntreCuentasExitoso extends TransferirEntreCuentasResultado {
  TransferirEntreCuentasExitoso(this.transferencia);
  final TransferenciaCuentaData transferencia;
}

class TransferirEntreCuentasMismaCuenta extends TransferirEntreCuentasResultado {}

class TransferirEntreCuentasImporteInvalido extends TransferirEntreCuentasResultado {}

/// La cuenta de origen no alcanza. Lleva los tres números que la
/// pantalla necesita mostrar —disponible, requerido y faltante— para
/// que la UI no tenga que recalcular ninguno.
class TransferirEntreCuentasSaldoInsuficiente extends TransferirEntreCuentasResultado {
  TransferirEntreCuentasSaldoInsuficiente(this.detalle);
  final SaldoInsuficiente detalle;
}

/// La fecha es anterior al saldo inicial de alguna de las dos cuentas.
class TransferirEntreCuentasFechaAnteriorAlSaldoInicial extends TransferirEntreCuentasResultado {
  TransferirEntreCuentasFechaAnteriorAlSaldoInicial(this.detalle);
  final FechaAnteriorAlSaldoInicial detalle;
}

class TransferirEntreCuentasCuentaNoDisponible extends TransferirEntreCuentasResultado {}

class TransferirEntreCuentasErrorInesperado extends TransferirEntreCuentasResultado {
  TransferirEntreCuentasErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Mover dinero entre dos cuentas propias.
///
/// **No genera Ingreso ni Egreso**, y por tanto no toca ingresos,
/// gasto operativo ni resultado: el dinero no entró ni salió de la
/// empresa, sólo cambió de cuenta. El único efecto es sobre la posición
/// de caja por cuenta, y "Caja y bancos" global queda idéntico.
class TransferirEntreCuentasUseCase {
  TransferirEntreCuentasUseCase(this._repository, this._generarCodigo);

  final TransferenciaCuentaRepositoryImpl _repository;
  final GenerarCodigoUseCase _generarCodigo;

  Future<TransferirEntreCuentasResultado> ejecutar({
    required String cuentaOrigenId,
    required String cuentaDestinoId,
    required int importe,
    required DateTime fecha,
    String? concepto,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    if (cuentaOrigenId == cuentaDestinoId) return TransferirEntreCuentasMismaCuenta();
    if (importe <= 0) return TransferirEntreCuentasImporteInvalido();

    try {
      final codigo = await _generarCodigo.ejecutar('transferenciaCuenta');
      final String folio;
      switch (codigo) {
        case Ok<String>(value: final v):
          folio = v;
        case Err<String>(failure: final f):
          return TransferirEntreCuentasErrorInesperado(f.message);
      }

      final transferencia = await _repository.crear(
        folioTransferencia: folio,
        cuentaOrigenId: cuentaOrigenId,
        cuentaDestinoId: cuentaDestinoId,
        importe: importe,
        fecha: fecha,
        concepto: concepto,
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );
      return TransferirEntreCuentasExitoso(transferencia);
    } on SaldoInsuficienteException catch (e) {
      return _desdeVeredicto(e.veredicto);
    } catch (e) {
      return TransferirEntreCuentasErrorInesperado(e.toString());
    }
  }
}

/// Traduce el veredicto de la política al resultado sellado del caso de
/// uso — compartido por transferir y corregir.
TransferirEntreCuentasResultado _desdeVeredicto(VeredictoSaldo veredicto) {
  return switch (veredicto) {
    SaldoInsuficiente() => TransferirEntreCuentasSaldoInsuficiente(veredicto),
    FechaAnteriorAlSaldoInicial() => TransferirEntreCuentasFechaAnteriorAlSaldoInicial(veredicto),
    CuentaNoDisponible() => TransferirEntreCuentasCuentaNoDisponible(),
    SaldoSuficiente() => TransferirEntreCuentasErrorInesperado('Veredicto inesperado.'),
  };
}

/// Corrige importe, fecha, concepto u observaciones de una
/// transferencia vigente. Cambiar las cuentas exige cancelar y crear
/// otra: eso ya no es la misma transferencia.
class CorregirTransferenciaUseCase {
  CorregirTransferenciaUseCase(this._repository);

  final TransferenciaCuentaRepositoryImpl _repository;

  Future<TransferirEntreCuentasResultado> ejecutar({
    required String transferenciaId,
    int? importe,
    DateTime? fecha,
    String? concepto,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    if (importe != null && importe <= 0) return TransferirEntreCuentasImporteInvalido();
    try {
      final transferencia = await _repository.corregir(
        transferenciaId: transferenciaId,
        importe: importe,
        fecha: fecha,
        concepto: concepto,
        observaciones: observaciones,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return TransferirEntreCuentasExitoso(transferencia);
    } on SaldoInsuficienteException catch (e) {
      return _desdeVeredicto(e.veredicto);
    } catch (e) {
      return TransferirEntreCuentasErrorInesperado(e.toString());
    }
  }
}

/// Cancelar devuelve el dinero a la cuenta de origen sin ningún
/// movimiento compensatorio: la fila deja de sumarse y se conserva como
/// historia.
class CancelarTransferenciaUseCase {
  CancelarTransferenciaUseCase(this._repository);

  final TransferenciaCuentaRepositoryImpl _repository;

  Future<TransferirEntreCuentasResultado> ejecutar({
    required String transferenciaId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    try {
      final transferencia = await _repository.cancelar(
        transferenciaId: transferenciaId,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return TransferirEntreCuentasExitoso(transferencia);
    } catch (e) {
      return TransferirEntreCuentasErrorInesperado(e.toString());
    }
  }
}
