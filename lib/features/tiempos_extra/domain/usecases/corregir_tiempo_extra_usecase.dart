import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';
import 'package:riseg_one/features/personal/presentation/empleados/empleados_list_screen.dart' show empleadoNombreCompleto;

import '../../data/tables/tiempo_extra_table.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/vacante_cobertura_reader.dart';

import '../repositories/tiempo_extra_repository.dart';
import 'tiempo_extra_validator.dart';

sealed class CorregirTiempoExtraResultado {}

class CorregirTiempoExtraExitoso extends CorregirTiempoExtraResultado {
  CorregirTiempoExtraExitoso(this.tiempoExtra);
  final TiempoExtraData tiempoExtra;
}

class CorregirTiempoExtraNoExiste extends CorregirTiempoExtraResultado {}

/// Solo un TiempoExtra `registrado` puede corregirse — mismo criterio
/// que `CorregirCompraUseCase` rechaza una Compra `cancelada`. La
/// estrategia soportada para una cobertura ya cancelada sigue siendo
/// cancelar + volver a registrar (esta etapa no cambia eso).
class CorregirTiempoExtraYaCancelado extends CorregirTiempoExtraResultado {}

class CorregirTiempoExtraCoberturaInvalida extends CorregirTiempoExtraResultado {
  CorregirTiempoExtraCoberturaInvalida(this.validacion);
  final TiempoExtraCoberturaValidacion validacion;
}

class CorregirTiempoExtraServicioNoExiste extends CorregirTiempoExtraResultado {}

class CorregirTiempoExtraEmpleadoAusenteNoExiste extends CorregirTiempoExtraResultado {}

class CorregirTiempoExtraEmpleadoCubreNoExiste extends CorregirTiempoExtraResultado {}

class CorregirTiempoExtraMontoInvalido extends CorregirTiempoExtraResultado {}

/// El conjunto (origen + sus campos) no es coherente — ver
/// `TiempoExtraValidator.validarOrigen`.
class CorregirTiempoExtraOrigenInvalido extends CorregirTiempoExtraResultado {
  CorregirTiempoExtraOrigenInvalido(this.validacion);
  final TiempoExtraOrigenValidacion validacion;
}

/// `origenCobertura == vacante` pero la vacante no existe.
class CorregirTiempoExtraVacanteNoExiste extends CorregirTiempoExtraResultado {}

/// La vacante elegida pertenece a OTRO Servicio — cubrir una plaza de
/// otro Servicio no es una cobertura de éste.
class CorregirTiempoExtraVacanteDeOtroServicio extends CorregirTiempoExtraResultado {}

/// La vacante ya no está abierta: no hay plaza que cubrir. Sólo
/// bloquea el REGISTRO/corrección nuevos; un TiempoExtra histórico
/// sigue resolviendo su vacante aunque después se cubra.
class CorregirTiempoExtraVacanteNoElegible extends CorregirTiempoExtraResultado {}

/// El mismo Empleado figura como quien falta y quien cubre.
class CorregirTiempoExtraAusenteYCubreSonElMismo extends CorregirTiempoExtraResultado {}

/// `descripcionOrigen` más larga que
/// `TiempoExtraValidator.maximoDescripcionOrigen`.
class CorregirTiempoExtraDescripcionOrigenMuyLarga extends CorregirTiempoExtraResultado {}



class CorregirTiempoExtraOrigenFinancieroRequerido extends CorregirTiempoExtraResultado {
  CorregirTiempoExtraOrigenFinancieroRequerido(this.item);
  final String item;
}

class CorregirTiempoExtraTarjetaInvalida extends CorregirTiempoExtraResultado {
  CorregirTiempoExtraTarjetaInvalida(this.item);
  final String item;
}

class CorregirTiempoExtraTarjetaSinLimiteConfigurado extends CorregirTiempoExtraResultado {
  CorregirTiempoExtraTarjetaSinLimiteConfigurado(this.item);
  final String item;
}

class CorregirTiempoExtraTarjetaExcedeLimite extends CorregirTiempoExtraResultado {
  CorregirTiempoExtraTarjetaExcedeLimite(this.item, this.disponible);
  final String item;
  final int disponible;
}

class CorregirTiempoExtraErrorInesperado extends CorregirTiempoExtraResultado {
  CorregirTiempoExtraErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige una cobertura ya registrada (Etapa "corrección real de
/// Tiempo Extra") — pedido explícito de Marlon: "cancelar y volver a
/// registrar" deja de ser la única estrategia. Reutiliza EXACTAMENTE
/// las mismas validaciones que `RegistrarTiempoExtraUseCase` (cobertura,
/// existencia, origen financiero de cada ítem) — a diferencia de
/// Compra, el origen financiero SÍ puede cambiar de tipo/contenedor
/// durante una corrección (ver el doc comment de
/// `TiempoExtraRepository.corregir`).
class CorregirTiempoExtraUseCase {
  CorregirTiempoExtraUseCase(
    this._repository,
    this._empleadoRepository,
    this._servicioRepository,
    this._deudaRepository,
    this._vacantes,
  );

  final TiempoExtraRepository _repository;
  final EmpleadoRepository _empleadoRepository;
  final ServicioRepository _servicioRepository;
  final DeudaRepository _deudaRepository;
  final VacanteCoberturaReader _vacantes;

  /// Mismo cuerpo exacto que `RegistrarTiempoExtraUseCase._validarOrigen`
  /// — no se duplica la regla, solo el tipo de resultado que envuelve.
  Future<CorregirTiempoExtraResultado?> _validarOrigenFinanciero({
    required String item,
    required String formaPago,
    required int monto,
    String? deudaIdTarjeta,
  }) async {
    if (formaPago != FormaPago.tarjeta.name) return null;

    if (deudaIdTarjeta == null) return CorregirTiempoExtraOrigenFinancieroRequerido(item);
    final tarjeta = await _deudaRepository.obtenerPorId(deudaIdTarjeta);
    final validacion = validarOrigenTarjeta(tarjeta: tarjeta, monto: monto);
    switch (validacion.error) {
      case ErrorOrigenTarjeta.noEsTarjetaActiva:
        return CorregirTiempoExtraTarjetaInvalida(item);
      case ErrorOrigenTarjeta.sinLimiteConfigurado:
        return CorregirTiempoExtraTarjetaSinLimiteConfigurado(item);
      case ErrorOrigenTarjeta.excedeLimite:
        return CorregirTiempoExtraTarjetaExcedeLimite(item, validacion.disponible!);
      case null:
        return null;
    }
  }

  Future<CorregirTiempoExtraResultado> ejecutar({
    required String tiempoExtraId,
    required DateTime fecha,
    required String servicioId,
    required String origenCobertura,
    String? empleadoAusenteId,
    String? motivoAusencia,
    String? vacanteOperativaId,
    String? descripcionOrigen,
    String? empleadoCubreId,
    String? nombreExternoCubre,
    required String turnoId,
    required int montoTiempoExtra,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
    String? observaciones,
    List<CorreccionCostoAdicional> cambiosCostos = const [],
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final actual = await _repository.obtenerPorId(tiempoExtraId);
    if (actual == null) return CorregirTiempoExtraNoExiste();
    if (actual.estatus == EstatusTiempoExtra.cancelado.name) return CorregirTiempoExtraYaCancelado();

    // --- Origen de la cobertura (Etapa "origen de cobertura") ---
    //
    // Se NORMALIZA antes de validar: al cambiar de origen, la pantalla
    // puede arrastrar la FK del origen anterior. Limpiarla aquí evita
    // que un residuo invisible haga fallar una corrección legítima —
    // y, sobre todo, que se persista. Corregir de Vacante a Ausencia
    // deja `vacanteOperativaId` en null, no "por si acaso".
    final origen = OrigenCoberturaTiempoExtra.values.asNameMap()[origenCobertura];
    if (origen == null) {
      return CorregirTiempoExtraOrigenInvalido(TiempoExtraOrigenValidacion.camposIncompatibles);
    }
    final campos = TiempoExtraValidator.normalizarSegunOrigen(
      origen: origen,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: motivoAusencia,
      vacanteOperativaId: vacanteOperativaId,
      descripcionOrigen: descripcionOrigen,
    );
    final validacionOrigen = TiempoExtraValidator.validarOrigen(
      origen: origen,
      empleadoAusenteId: campos.empleadoAusenteId,
      motivoAusencia: campos.motivoAusencia,
      vacanteOperativaId: campos.vacanteOperativaId,
      descripcionOrigen: campos.descripcionOrigen,
    );
    if (validacionOrigen != TiempoExtraOrigenValidacion.valida) {
      return CorregirTiempoExtraOrigenInvalido(validacionOrigen);
    }
    if (TiempoExtraValidator.descripcionOrigenExcedeLimite(campos.descripcionOrigen)) {
      return CorregirTiempoExtraDescripcionOrigenMuyLarga();
    }
    if (TiempoExtraValidator.ausenteYCubreSonElMismo(
      empleadoAusenteId: campos.empleadoAusenteId,
      empleadoCubreId: empleadoCubreId,
    )) {
      return CorregirTiempoExtraAusenteYCubreSonElMismo();
    }

    final validacionCobertura = TiempoExtraValidator.validarCobertura(
      empleadoCubreId: empleadoCubreId,
      nombreExternoCubre: nombreExternoCubre,
    );
    if (validacionCobertura != TiempoExtraCoberturaValidacion.valida) {
      return CorregirTiempoExtraCoberturaInvalida(validacionCobertura);
    }
    if (montoTiempoExtra <= 0 ||
        cambiosCostos.whereType<CorreccionCostoAdicionalEditar>().any((c) => c.monto <= 0) ||
        cambiosCostos.whereType<CorreccionCostoAdicionalAgregar>().any((c) => c.monto <= 0)) {
      return CorregirTiempoExtraMontoInvalido();
    }

    final servicio = await _servicioRepository.obtenerPorId(servicioId);
    if (servicio == null) return CorregirTiempoExtraServicioNoExiste();

    final empleadoAusenteResuelto = campos.empleadoAusenteId;
    if (empleadoAusenteResuelto != null) {
      final empleadoAusente = await _empleadoRepository.obtenerPorId(empleadoAusenteResuelto);
      if (empleadoAusente == null) return CorregirTiempoExtraEmpleadoAusenteNoExiste();
    }

    // La vacante tiene que ser de ESTE Servicio y seguir abierta.
    // Excepción: si la corrección conserva exactamente la misma vacante
    // que el TiempoExtra ya tenía, no se re-exige que siga abierta —
    // corregir el monto de una cobertura de marzo no puede quedar
    // bloqueado porque la plaza se llenó en abril.
    final vacanteResuelta = campos.vacanteOperativaId;
    if (vacanteResuelta != null) {
      final vacante = await _vacantes.porId(vacanteResuelta);
      if (vacante == null) return CorregirTiempoExtraVacanteNoExiste();
      if (vacante.servicioId != servicioId) return CorregirTiempoExtraVacanteDeOtroServicio();
      final esLaMisma = actual.vacanteOperativaId == vacanteResuelta;
      if (!esLaMisma && !vacante.estaAbierta) return CorregirTiempoExtraVacanteNoElegible();
    }

    String beneficiarioEgreso;
    if (empleadoCubreId != null) {
      final empleadoCubre = await _empleadoRepository.obtenerPorId(empleadoCubreId);
      if (empleadoCubre == null) return CorregirTiempoExtraEmpleadoCubreNoExiste();
      beneficiarioEgreso = empleadoNombreCompleto(empleadoCubre);
    } else {
      beneficiarioEgreso = nombreExternoCubre!;
    }

    final errorOrigenBase = await _validarOrigenFinanciero(
      item: 'Pago de tiempo extra',
      formaPago: formaPago,
      monto: montoTiempoExtra,
      deudaIdTarjeta: deudaIdTarjeta,
    );
    if (errorOrigenBase != null) return errorOrigenBase;

    for (final cambio in cambiosCostos) {
      switch (cambio) {
        case CorreccionCostoAdicionalEditar():
          final error = await _validarOrigenFinanciero(
            item: cambio.concepto, formaPago: cambio.formaPago, monto: cambio.monto, deudaIdTarjeta: cambio.deudaIdTarjeta);
          if (error != null) return error;
        case CorreccionCostoAdicionalAgregar():
          final error = await _validarOrigenFinanciero(
            item: cambio.concepto, formaPago: cambio.formaPago, monto: cambio.monto, deudaIdTarjeta: cambio.deudaIdTarjeta);
          if (error != null) return error;
        case CorreccionCostoAdicionalQuitar():
          break;
      }
    }

    // Normaliza el origen de cada costo según SU PROPIA `formaPago` —
    // mismo criterio que `RegistrarTiempoExtraUseCase`.
    final cambiosNormalizados = [
      for (final cambio in cambiosCostos)
        switch (cambio) {
          CorreccionCostoAdicionalEditar() => CorreccionCostoAdicionalEditar(
              costoAdicionalId: cambio.costoAdicionalId,
              concepto: cambio.concepto,
              monto: cambio.monto,
              formaPago: cambio.formaPago,
              cuentaFinancieraId: cambio.formaPago == FormaPago.tarjeta.name ? null : cambio.cuentaFinancieraId,
              deudaIdTarjeta: cambio.formaPago == FormaPago.tarjeta.name ? cambio.deudaIdTarjeta : null,
            ),
          CorreccionCostoAdicionalAgregar() => CorreccionCostoAdicionalAgregar(
              concepto: cambio.concepto,
              monto: cambio.monto,
              formaPago: cambio.formaPago,
              cuentaFinancieraId: cambio.formaPago == FormaPago.tarjeta.name ? null : cambio.cuentaFinancieraId,
              deudaIdTarjeta: cambio.formaPago == FormaPago.tarjeta.name ? cambio.deudaIdTarjeta : null,
            ),
          CorreccionCostoAdicionalQuitar() => cambio,
        },
    ];

    try {
      final tiempoExtra = await _repository.corregir(
        tiempoExtraId: tiempoExtraId,
        fecha: fecha,
        servicioId: servicioId,
        origenCobertura: origen.name,
        empleadoAusenteId: campos.empleadoAusenteId,
        motivoAusencia: campos.motivoAusencia,
        vacanteOperativaId: campos.vacanteOperativaId,
        descripcionOrigen: campos.descripcionOrigen,
        empleadoCubreId: empleadoCubreId,
        nombreExternoCubre: nombreExternoCubre,
        turnoId: turnoId,
        montoTiempoExtra: montoTiempoExtra,
        formaPago: formaPago,
        cuentaFinancieraId: formaPago == FormaPago.tarjeta.name ? null : cuentaFinancieraId,
        deudaIdTarjeta: formaPago == FormaPago.tarjeta.name ? deudaIdTarjeta : null,
        observaciones: observaciones,
        cambiosCostos: cambiosNormalizados,
        beneficiarioEgreso: beneficiarioEgreso,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );
      return CorregirTiempoExtraExitoso(tiempoExtra);
    } on SaldoInsuficienteException {
      // Corregir también puede quedarse sin saldo (subir el importe, o
      // mover la salida a otra cuenta). No es un error inesperado: se
      // deja propagar para que la pantalla muestre los tres números.
      rethrow;
    } catch (e) {
      return CorregirTiempoExtraErrorInesperado(e.toString());
    }
  }
}
