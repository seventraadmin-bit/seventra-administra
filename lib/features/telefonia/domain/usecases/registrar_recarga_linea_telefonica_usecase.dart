import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'package:riseg_one/core/database/app_database.dart';

import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';

import '../repositories/linea_telefonica_repository.dart';
import '../repositories/recarga_linea_telefonica_repository.dart';

sealed class RegistrarRecargaLineaTelefonicaResultado {}

class RegistrarRecargaLineaTelefonicaExitoso extends RegistrarRecargaLineaTelefonicaResultado {
  RegistrarRecargaLineaTelefonicaExitoso(this.recarga);
  final RecargaLineaTelefonicaData recarga;
}

class RegistrarRecargaLineaTelefonicaLineaNoExiste extends RegistrarRecargaLineaTelefonicaResultado {}

/// Una línea dada de baja no admite nuevas recargas — sí una
/// suspendida (ver el doc comment de la clase, punto 5 de la
/// resolución de 9C: recargar es, en la operación real, la acción que
/// suele reactivar una línea suspendida).
class RegistrarRecargaLineaTelefonicaLineaDeBaja extends RegistrarRecargaLineaTelefonicaResultado {}

class RegistrarRecargaLineaTelefonicaImporteInvalido extends RegistrarRecargaLineaTelefonicaResultado {}

/// Una recarga NUEVA exige exactamente un origen financiero: o una
/// cuenta, o una tarjeta. Ni ambos, ni ninguno (§4 de la etapa).
class RegistrarRecargaLineaTelefonicaOrigenFinancieroRequerido extends RegistrarRecargaLineaTelefonicaResultado {}

/// Se mandaron cuenta Y tarjeta a la vez.
class RegistrarRecargaLineaTelefonicaOrigenFinancieroAmbiguo extends RegistrarRecargaLineaTelefonicaResultado {}

/// La tarjeta no existe, no es `tarjetaCredito` o no está activa.
class RegistrarRecargaLineaTelefonicaTarjetaInvalida extends RegistrarRecargaLineaTelefonicaResultado {}

/// La tarjeta todavía no tiene `tarjetaLimiteCredito` capturado.
class RegistrarRecargaLineaTelefonicaTarjetaSinLimiteConfigurado extends RegistrarRecargaLineaTelefonicaResultado {}

/// El importe excede el crédito disponible de la tarjeta.
class RegistrarRecargaLineaTelefonicaTarjetaExcedeLimite extends RegistrarRecargaLineaTelefonicaResultado {
  RegistrarRecargaLineaTelefonicaTarjetaExcedeLimite(this.disponible);
  final int disponible;
}



class RegistrarRecargaLineaTelefonicaErrorInesperado extends RegistrarRecargaLineaTelefonicaResultado {
  RegistrarRecargaLineaTelefonicaErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra una recarga prepago (Etapa 9C) — fecha, importe,
/// observaciones opcionales. Sin gigabytes/minutos/SMS/paquete/vigencia/
/// saldo (fuera de alcance confirmado por Marlon) y sin crear un Egreso
/// automático: Telefonía registra el contexto operativo, Finanzas sigue
/// siendo la única fuente de movimientos de dinero reales.
///
/// **Única regla de estatus**: `baja` bloquea, `suspendida` **no** —
/// una línea suspendida conserva asignación/equipo/historial y puede
/// seguir recargándose; en prepago real, recargar es frecuentemente la
/// acción que reactiva una línea suspendida.
class RegistrarRecargaLineaTelefonicaUseCase {
  RegistrarRecargaLineaTelefonicaUseCase(this._recargaRepository, this._lineaRepository, this._deudaRepository);

  final RecargaLineaTelefonicaRepository _recargaRepository;
  final LineaTelefonicaRepository _lineaRepository;
  final DeudaRepository _deudaRepository;

  Future<RegistrarRecargaLineaTelefonicaResultado> ejecutar({
    required String lineaTelefonicaId,
    required DateTime fecha,
    required int importe,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    final linea = await _lineaRepository.obtenerPorId(lineaTelefonicaId);
    if (linea == null) return RegistrarRecargaLineaTelefonicaLineaNoExiste();
    if (linea.estatus == 'baja') return RegistrarRecargaLineaTelefonicaLineaDeBaja();
    if (importe <= 0) return RegistrarRecargaLineaTelefonicaImporteInvalido();

    final importeFinal = importe;
    // --- Origen financiero (§4) ---------------------------------
    //
    // Exactamente uno. Se valida en DOMINIO, no sólo en el diálogo: un
    // caso de uso llamado desde otro lado tiene que toparse con la
    // misma regla.
    if (formaPago.trim().isEmpty) return RegistrarRecargaLineaTelefonicaOrigenFinancieroRequerido();
    final esTarjeta = formaPago == FormaPago.tarjeta.name;
    final tieneCuenta = (cuentaFinancieraId ?? '').isNotEmpty;
    final tieneTarjeta = (deudaIdTarjeta ?? '').isNotEmpty;

    if (tieneCuenta && tieneTarjeta) return RegistrarRecargaLineaTelefonicaOrigenFinancieroAmbiguo();
    if (esTarjeta) {
      if (!tieneTarjeta) return RegistrarRecargaLineaTelefonicaOrigenFinancieroRequerido();
      final tarjeta = await _deudaRepository.obtenerPorId(deudaIdTarjeta!);
      final validacion = validarOrigenTarjeta(tarjeta: tarjeta, monto: importeFinal);
      switch (validacion.error) {
        case ErrorOrigenTarjeta.noEsTarjetaActiva:
          return RegistrarRecargaLineaTelefonicaTarjetaInvalida();
        case ErrorOrigenTarjeta.sinLimiteConfigurado:
          return RegistrarRecargaLineaTelefonicaTarjetaSinLimiteConfigurado();
        case ErrorOrigenTarjeta.excedeLimite:
          return RegistrarRecargaLineaTelefonicaTarjetaExcedeLimite(validacion.disponible!);
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
      return RegistrarRecargaLineaTelefonicaOrigenFinancieroRequerido();
    }

    try {
      final recarga = await _recargaRepository.registrar(
        lineaTelefonicaId: lineaTelefonicaId,
        fecha: fecha,
        importe: importe,
        formaPago: formaPago,
        cuentaFinancieraId: esTarjeta ? null : cuentaFinancieraId,
        deudaIdTarjeta: esTarjeta ? deudaIdTarjeta : null,
        observaciones: observaciones?.trim().isEmpty ?? true ? null : observaciones!.trim(),
        actorUsuarioId: actorUsuarioId,
      );
      return RegistrarRecargaLineaTelefonicaExitoso(recarga);
    } on SaldoInsuficienteException {
      // Un saldo insuficiente NO es un error inesperado: es un
      // rechazo previsto y accionable. Se deja propagar para que la
      // pantalla muestre disponible/requerido/faltante en vez de un
      // mensaje genérico. La transacción ya quedó revertida entera.
      rethrow;
    } catch (e) {
      return RegistrarRecargaLineaTelefonicaErrorInesperado(e.toString());
    }
  }
}
