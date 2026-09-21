import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/linea_telefonica_table.dart';
import '../../data/tables/recarga_linea_telefonica_table.dart';
import 'package:riseg_one/core/auditoria/enmascarar_identificador.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';

import '../repositories/linea_telefonica_repository.dart';
import '../repositories/recarga_linea_telefonica_repository.dart';

sealed class CorregirRecargaLineaTelefonicaResultado {}

class CorregirRecargaLineaTelefonicaExitoso extends CorregirRecargaLineaTelefonicaResultado {
  CorregirRecargaLineaTelefonicaExitoso(this.recarga);
  final RecargaLineaTelefonicaData recarga;
}

class CorregirRecargaLineaTelefonicaNoExiste extends CorregirRecargaLineaTelefonicaResultado {}

/// Una recarga anulada no se corrige — se registra una nueva. Mismo
/// criterio que un mantenimiento de Vehículo o un Tiempo Extra
/// cancelados.
class CorregirRecargaLineaTelefonicaCancelada extends CorregirRecargaLineaTelefonicaResultado {}

class CorregirRecargaLineaTelefonicaMotivoRequerido extends CorregirRecargaLineaTelefonicaResultado {}

class CorregirRecargaLineaTelefonicaImporteInvalido extends CorregirRecargaLineaTelefonicaResultado {}

/// Una recarga NUEVA exige exactamente un origen financiero: o una
/// cuenta, o una tarjeta. Ni ambos, ni ninguno (§4 de la etapa).
class CorregirRecargaLineaTelefonicaOrigenFinancieroRequerido extends CorregirRecargaLineaTelefonicaResultado {}

/// Se mandaron cuenta Y tarjeta a la vez.
class CorregirRecargaLineaTelefonicaOrigenFinancieroAmbiguo extends CorregirRecargaLineaTelefonicaResultado {}

/// La tarjeta no existe, no es `tarjetaCredito` o no está activa.
class CorregirRecargaLineaTelefonicaTarjetaInvalida extends CorregirRecargaLineaTelefonicaResultado {}

/// La tarjeta todavía no tiene `tarjetaLimiteCredito` capturado.
class CorregirRecargaLineaTelefonicaTarjetaSinLimiteConfigurado extends CorregirRecargaLineaTelefonicaResultado {}

/// El importe excede el crédito disponible de la tarjeta.
class CorregirRecargaLineaTelefonicaTarjetaExcedeLimite extends CorregirRecargaLineaTelefonicaResultado {
  CorregirRecargaLineaTelefonicaTarjetaExcedeLimite(this.disponible);
  final int disponible;
}



class CorregirRecargaLineaTelefonicaErrorInesperado extends CorregirRecargaLineaTelefonicaResultado {
  CorregirRecargaLineaTelefonicaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige una recarga ya registrada (schemaVersion 81) — el gap
/// operativo principal del módulo: hasta aquí una recarga solo podía
/// registrarse, y un importe mal capturado obligaba a borrar la fila.
///
/// Corrige la MISMA fila, nunca crea una "recarga sustituta": una
/// recarga no tiene identidad contable propia que obligue a preservar
/// la errónea (a diferencia de un Complemento de pago ya timbrado), y
/// duplicarla inflaría todos los totalizadores del módulo.
///
/// **Sí toca dinero** (schemaVersion 86): corregir una recarga MUEVE su
/// efecto financiero — las seis transiciones Cuenta/TDC—, nunca deja
/// dos efectos vivos ni ninguno. Todo dentro de la misma transacción
/// del repositorio.
class CorregirRecargaLineaTelefonicaUseCase {
  CorregirRecargaLineaTelefonicaUseCase(this._recargaRepository, this._lineaRepository, this._deudaRepository);

  final RecargaLineaTelefonicaRepository _recargaRepository;
  final LineaTelefonicaRepository _lineaRepository;
  final DeudaRepository _deudaRepository;

  /// "BBVA Empresarial" / "Tarjeta corporativa ···· 1234" / "Origen
  /// financiero no registrado" — nunca un UUID ni el número completo de
  /// la tarjeta (§20).
  Future<String> _etiquetaOrigen({String? egresoId, String? deudaId}) async {
    if (deudaId != null) {
      final tarjeta = await _deudaRepository.obtenerPorId(deudaId);
      if (tarjeta == null) return 'Tarjeta de crédito';
      final ultimos = tarjeta.tarjetaUltimosDigitos;
      return ultimos == null || ultimos.isEmpty
          ? tarjeta.nombre
          : '${tarjeta.nombre} ${enmascararIdentificador(ultimos)}';
    }
    if (egresoId != null) {
      final cuenta = await _recargaRepository.nombreCuentaDeEgreso(egresoId);
      return cuenta ?? 'Cuenta financiera';
    }
    return 'Origen financiero no registrado';
  }

  Future<CorregirRecargaLineaTelefonicaResultado> ejecutar({
    required String recargaLineaTelefonicaId,
    DateTime? fecha,
    int? importe,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
    String? observaciones,
    bool limpiarObservaciones = false,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    if (!motivoEsValido(motivo)) return CorregirRecargaLineaTelefonicaMotivoRequerido();

    final actual = await _recargaRepository.obtenerPorId(recargaLineaTelefonicaId);
    if (actual == null) return CorregirRecargaLineaTelefonicaNoExiste();
    if (actual.estatus == EstatusRecargaLineaTelefonica.cancelada.name) {
      return CorregirRecargaLineaTelefonicaCancelada();
    }
    if (importe != null && importe <= 0) return CorregirRecargaLineaTelefonicaImporteInvalido();

    final importeFinal = importe ?? actual.importe;

    // --- Origen financiero (§4) ---------------------------------
    //
    // Exactamente uno. Se valida en DOMINIO, no sólo en el diálogo: un
    // caso de uso llamado desde otro lado tiene que toparse con la
    // misma regla.
    if (formaPago.trim().isEmpty) return CorregirRecargaLineaTelefonicaOrigenFinancieroRequerido();
    final esTarjeta = formaPago == FormaPago.tarjeta.name;
    final tieneCuenta = (cuentaFinancieraId ?? '').isNotEmpty;
    final tieneTarjeta = (deudaIdTarjeta ?? '').isNotEmpty;

    if (tieneCuenta && tieneTarjeta) return CorregirRecargaLineaTelefonicaOrigenFinancieroAmbiguo();
    if (esTarjeta) {
      if (!tieneTarjeta) return CorregirRecargaLineaTelefonicaOrigenFinancieroRequerido();
      final tarjeta = await _deudaRepository.obtenerPorId(deudaIdTarjeta!);
      // Al corregir sobre la MISMA tarjeta lo que consume crédito es el
      // delta, no el importe completo: el cargo anterior ya está
      // aplicado. Cobrar el total de nuevo rechazaría correcciones
      // legítimas a la baja.
      final montoAValidar =
          deudaIdTarjeta == actual.deudaId ? (importeFinal - actual.importe) : importeFinal;
      final validacion = validarOrigenTarjeta(tarjeta: tarjeta, monto: montoAValidar > 0 ? montoAValidar : 0);
      switch (validacion.error) {
        case ErrorOrigenTarjeta.noEsTarjetaActiva:
          return CorregirRecargaLineaTelefonicaTarjetaInvalida();
        case ErrorOrigenTarjeta.sinLimiteConfigurado:
          return CorregirRecargaLineaTelefonicaTarjetaSinLimiteConfigurado();
        case ErrorOrigenTarjeta.excedeLimite:
          return CorregirRecargaLineaTelefonicaTarjetaExcedeLimite(validacion.disponible!);
        case null:
          break;
      }
    } else if (!tieneCuenta) {
      // Con Cuenta, `cuentaFinancieraId` es OBLIGATORIA en dominio.
      //
      // Deliberadamente MÁS estricto que Compras/Tiempos Extra, que sí
      // aceptan "cuenta no especificada": que ellos lo permitan no es
      // razón para permitirlo aquí. Una recarga corporativa nueva no
      // puede existir sin saber de qué cuenta salió el dinero, y que la
      // UI lo impida no basta — el caso de uso se puede llamar desde
      // otro lado.
      //
      // Nunca se rellena con una cuenta ficticia ni con un "Sin
      // especificar": o se sabe, o no se registra.
      return CorregirRecargaLineaTelefonicaOrigenFinancieroRequerido();
    }

    try {
      final actualizada = await _recargaRepository.corregir(
        recargaLineaTelefonicaId: recargaLineaTelefonicaId,
        fecha: fecha,
        importe: importe,
        formaPago: formaPago,
        cuentaFinancieraId: esTarjeta ? null : cuentaFinancieraId,
        deudaIdTarjeta: esTarjeta ? deudaIdTarjeta : null,
        observaciones: observaciones?.trim().isEmpty ?? true ? null : observaciones!.trim(),
        limpiarObservaciones: limpiarObservaciones,
        motivo: motivo.trim(),
        actorUsuarioId: actorUsuarioId,
      );

      // El diff financiero muestra NOMBRES legibles, nunca UUIDs ni el
      // número completo de una tarjeta (§20).
      final diff = DiffEvento()
        ..anotar('fecha', actual.fecha, actualizada.fecha)
        ..anotar('importe', actual.importe, actualizada.importe)
        ..anotar(
          'origenFinanciero',
          await _etiquetaOrigen(egresoId: actual.egresoId, deudaId: actual.deudaId),
          await _etiquetaOrigen(egresoId: actualizada.egresoId, deudaId: actualizada.deudaId),
        )
        ..anotar('observaciones', actual.observaciones, actualizada.observaciones);

      if (diff.hayCambios) {
        await _lineaRepository.registrarEvento(
          lineaTelefonicaId: actual.lineaTelefonicaId,
          tipoEvento: TipoEventoLineaTelefonica.recargaCorregida,
          recargaId: recargaLineaTelefonicaId,
          observacion: motivo,
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          actorUsuarioId: actorUsuarioId,
        );
      }

      return CorregirRecargaLineaTelefonicaExitoso(actualizada);
    } on SaldoInsuficienteException {
      // Corregir también puede quedarse sin saldo (subir el importe, o
      // mover la salida a otra cuenta). No es un error inesperado: se
      // deja propagar para que la pantalla muestre los tres números.
      rethrow;
    } catch (e) {
      return CorregirRecargaLineaTelefonicaErrorInesperado(e.toString());
    }
  }
}
