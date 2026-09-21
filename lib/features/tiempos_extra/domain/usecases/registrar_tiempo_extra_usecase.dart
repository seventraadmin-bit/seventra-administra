import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';
import 'package:riseg_one/features/personal/presentation/empleados/empleados_list_screen.dart' show empleadoNombreCompleto;

import 'package:riseg_one/features/tiempos_extra/data/repositories/vacante_cobertura_reader.dart';
import 'package:riseg_one/features/tiempos_extra/data/tables/tiempo_extra_table.dart';

import '../repositories/tiempo_extra_repository.dart';
import 'tiempo_extra_validator.dart';

sealed class RegistrarTiempoExtraResultado {}

class RegistrarTiempoExtraExitoso extends RegistrarTiempoExtraResultado {
  RegistrarTiempoExtraExitoso(this.tiempoExtra);
  final TiempoExtraData tiempoExtra;
}

class RegistrarTiempoExtraCoberturaInvalida extends RegistrarTiempoExtraResultado {
  RegistrarTiempoExtraCoberturaInvalida(this.validacion);
  final TiempoExtraCoberturaValidacion validacion;
}

class RegistrarTiempoExtraServicioNoExiste extends RegistrarTiempoExtraResultado {}

class RegistrarTiempoExtraEmpleadoAusenteNoExiste extends RegistrarTiempoExtraResultado {}

class RegistrarTiempoExtraEmpleadoCubreNoExiste extends RegistrarTiempoExtraResultado {}

class RegistrarTiempoExtraMontoInvalido extends RegistrarTiempoExtraResultado {}

/// El conjunto (origen + sus campos) no es coherente — ver
/// `TiempoExtraValidator.validarOrigen`.
class RegistrarTiempoExtraOrigenInvalido extends RegistrarTiempoExtraResultado {
  RegistrarTiempoExtraOrigenInvalido(this.validacion);
  final TiempoExtraOrigenValidacion validacion;
}

/// `origenCobertura == vacante` pero la vacante no existe.
class RegistrarTiempoExtraVacanteNoExiste extends RegistrarTiempoExtraResultado {}

/// La vacante elegida pertenece a OTRO Servicio — cubrir una plaza de
/// otro Servicio no es una cobertura de éste.
class RegistrarTiempoExtraVacanteDeOtroServicio extends RegistrarTiempoExtraResultado {}

/// La vacante ya no está abierta: no hay plaza que cubrir. Sólo
/// bloquea el REGISTRO/corrección nuevos; un TiempoExtra histórico
/// sigue resolviendo su vacante aunque después se cubra.
class RegistrarTiempoExtraVacanteNoElegible extends RegistrarTiempoExtraResultado {}

/// El mismo Empleado figura como quien falta y quien cubre.
class RegistrarTiempoExtraAusenteYCubreSonElMismo extends RegistrarTiempoExtraResultado {}

/// `descripcionOrigen` más larga que
/// `TiempoExtraValidator.maximoDescripcionOrigen`.
class RegistrarTiempoExtraDescripcionOrigenMuyLarga extends RegistrarTiempoExtraResultado {}



/// Etapa "origen financiero unificado" — `formaPago != tarjeta` sin
/// `cuentaFinancieraId`, o `formaPago == tarjeta` sin `deudaIdTarjeta`.
/// [item] identifica cuál (el pago base o el concepto del costo
/// adicional) para que la UI señale exactamente dónde falta.
class RegistrarTiempoExtraOrigenFinancieroRequerido extends RegistrarTiempoExtraResultado {
  RegistrarTiempoExtraOrigenFinancieroRequerido(this.item);
  final String item;
}

/// La tarjeta seleccionada para [item] no existe, no es de tipo
/// `tarjetaCredito`, o no está `activa`.
class RegistrarTiempoExtraTarjetaInvalida extends RegistrarTiempoExtraResultado {
  RegistrarTiempoExtraTarjetaInvalida(this.item);
  final String item;
}

/// La tarjeta seleccionada para [item] todavía no tiene
/// `tarjetaLimiteCredito` capturado.
class RegistrarTiempoExtraTarjetaSinLimiteConfigurado extends RegistrarTiempoExtraResultado {
  RegistrarTiempoExtraTarjetaSinLimiteConfigurado(this.item);
  final String item;
}

/// El monto de [item] excede el crédito disponible de la tarjeta
/// seleccionada — [disponible] viaja para que el mensaje cite el monto
/// exacto.
class RegistrarTiempoExtraTarjetaExcedeLimite extends RegistrarTiempoExtraResultado {
  RegistrarTiempoExtraTarjetaExcedeLimite(this.item, this.disponible);
  final String item;
  final int disponible;
}

class RegistrarTiempoExtraErrorInesperado extends RegistrarTiempoExtraResultado {
  RegistrarTiempoExtraErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra una cobertura operativa por ausencia (pedido explícito de
/// Marlon) — valida cobertura/existencia y delega la escritura completa
/// (cobertura + costos adicionales + Egreso automático) a
/// `TiempoExtraRepository.crear`, dentro de una sola transacción.
class RegistrarTiempoExtraUseCase {
  RegistrarTiempoExtraUseCase(
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

  /// Valida el origen financiero de un ítem (pago base o un costo
  /// adicional) cuando `formaPago == tarjeta` — reutilizando
  /// `validarOrigenTarjeta` (misma regla que ya usa
  /// `RegistrarCompraUseCase`, nunca una segunda copia). Mismo criterio
  /// EXACTO que `RegistrarCompraUseCase`: `cuentaFinancieraId` para
  /// cualquier otra forma de pago es opcional a nivel de dominio (una
  /// fila con `cuentaFinancieraId == null` es "cuenta no especificada",
  /// un estado honesto ya existente para `Egreso`) — el diálogo real es
  /// el que lo exige en la práctica (no se puede enviar el formulario
  /// sin elegir un origen), sin forzar a cada prueba/fixture de dominio
  /// que jamás toca la UI a inventarse una CuentaFinanciera. Devuelve
  /// `null` si es válido, o el resultado de error correspondiente.
  Future<RegistrarTiempoExtraResultado?> _validarOrigenFinanciero({
    required String item,
    required String formaPago,
    required int monto,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
  }) async {
    if (formaPago != FormaPago.tarjeta.name) return null;

    if (deudaIdTarjeta == null) return RegistrarTiempoExtraOrigenFinancieroRequerido(item);
    final tarjeta = await _deudaRepository.obtenerPorId(deudaIdTarjeta);
    final validacion = validarOrigenTarjeta(tarjeta: tarjeta, monto: monto);
    switch (validacion.error) {
      case ErrorOrigenTarjeta.noEsTarjetaActiva:
        return RegistrarTiempoExtraTarjetaInvalida(item);
      case ErrorOrigenTarjeta.sinLimiteConfigurado:
        return RegistrarTiempoExtraTarjetaSinLimiteConfigurado(item);
      case ErrorOrigenTarjeta.excedeLimite:
        return RegistrarTiempoExtraTarjetaExcedeLimite(item, validacion.disponible!);
      case null:
        return null;
    }
  }

  Future<RegistrarTiempoExtraResultado> ejecutar({
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
    List<CostoAdicionalInput> costosAdicionales = const [],
    String? actorUsuarioId,
  }) async {
    // --- Origen de la cobertura (Etapa "origen de cobertura") ---
    //
    // En un ALTA se valida lo que llega TAL CUAL: no existe un origen
    // anterior del que arrastrar residuos, así que mandar una vacante
    // y además un empleado ausente es una contradicción del llamador
    // —no un descuido de la pantalla— y se rechaza en vez de
    // silenciarse. La CORRECCIÓN sí normaliza antes de validar, porque
    // ahí limpiar el residuo del origen previo es justo el requisito.
    final origen = OrigenCoberturaTiempoExtra.values.asNameMap()[origenCobertura];
    if (origen == null) {
      return RegistrarTiempoExtraOrigenInvalido(TiempoExtraOrigenValidacion.camposIncompatibles);
    }
    final validacionOrigen = TiempoExtraValidator.validarOrigen(
      origen: origen,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: motivoAusencia,
      vacanteOperativaId: vacanteOperativaId,
      descripcionOrigen: descripcionOrigen,
    );
    if (validacionOrigen != TiempoExtraOrigenValidacion.valida) {
      return RegistrarTiempoExtraOrigenInvalido(validacionOrigen);
    }
    // Ya validado: aquí sólo recorta espacios y vacíos.
    final campos = TiempoExtraValidator.normalizarSegunOrigen(
      origen: origen,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: motivoAusencia,
      vacanteOperativaId: vacanteOperativaId,
      descripcionOrigen: descripcionOrigen,
    );
    if (TiempoExtraValidator.descripcionOrigenExcedeLimite(campos.descripcionOrigen)) {
      return RegistrarTiempoExtraDescripcionOrigenMuyLarga();
    }
    if (TiempoExtraValidator.ausenteYCubreSonElMismo(
      empleadoAusenteId: campos.empleadoAusenteId,
      empleadoCubreId: empleadoCubreId,
    )) {
      return RegistrarTiempoExtraAusenteYCubreSonElMismo();
    }

    final validacion = TiempoExtraValidator.validarCobertura(
      empleadoCubreId: empleadoCubreId,
      nombreExternoCubre: nombreExternoCubre,
    );
    if (validacion != TiempoExtraCoberturaValidacion.valida) {
      return RegistrarTiempoExtraCoberturaInvalida(validacion);
    }
    if (montoTiempoExtra <= 0 || costosAdicionales.any((c) => c.monto <= 0)) {
      return RegistrarTiempoExtraMontoInvalido();
    }

    final servicio = await _servicioRepository.obtenerPorId(servicioId);
    if (servicio == null) return RegistrarTiempoExtraServicioNoExiste();

    final empleadoAusenteResuelto = campos.empleadoAusenteId;
    if (empleadoAusenteResuelto != null) {
      final empleadoAusente = await _empleadoRepository.obtenerPorId(empleadoAusenteResuelto);
      if (empleadoAusente == null) return RegistrarTiempoExtraEmpleadoAusenteNoExiste();
    }

    // La vacante tiene que ser de ESTE Servicio y seguir abierta.
    // Registrar el TiempoExtra no la cierra: sólo dice que alguien
    // cubrió ese turno una vez.
    final vacanteResuelta = campos.vacanteOperativaId;
    if (vacanteResuelta != null) {
      final vacante = await _vacantes.porId(vacanteResuelta);
      if (vacante == null) return RegistrarTiempoExtraVacanteNoExiste();
      if (vacante.servicioId != servicioId) return RegistrarTiempoExtraVacanteDeOtroServicio();
      if (!vacante.estaAbierta) return RegistrarTiempoExtraVacanteNoElegible();
    }

    String beneficiarioEgreso;
    if (empleadoCubreId != null) {
      final empleadoCubre = await _empleadoRepository.obtenerPorId(empleadoCubreId);
      if (empleadoCubre == null) return RegistrarTiempoExtraEmpleadoCubreNoExiste();
      beneficiarioEgreso = empleadoNombreCompleto(empleadoCubre);
    } else {
      beneficiarioEgreso = nombreExternoCubre!;
    }

    final errorOrigenBase = await _validarOrigenFinanciero(
      item: 'Pago de tiempo extra',
      formaPago: formaPago,
      monto: montoTiempoExtra,
      cuentaFinancieraId: cuentaFinancieraId,
      deudaIdTarjeta: deudaIdTarjeta,
    );
    if (errorOrigenBase != null) return errorOrigenBase;

    for (final costo in costosAdicionales) {
      final errorOrigenCosto = await _validarOrigenFinanciero(
        item: costo.concepto,
        formaPago: costo.formaPago,
        monto: costo.monto,
        cuentaFinancieraId: costo.cuentaFinancieraId,
        deudaIdTarjeta: costo.deudaIdTarjeta,
      );
      if (errorOrigenCosto != null) return errorOrigenCosto;
    }

    // Normaliza el origen de cada costo según SU PROPIA `formaPago`
    // (nunca la del pago base) — mismo criterio que `RegistrarCompraUseCase`
    // nulea `cuentaFinancieraId` cuando `formaPago == tarjeta`, para que
    // el repositorio nunca reciba ambos campos poblados por error.
    final costosNormalizados = [
      for (final costo in costosAdicionales)
        CostoAdicionalInput(
          concepto: costo.concepto,
          monto: costo.monto,
          formaPago: costo.formaPago,
          cuentaFinancieraId: costo.formaPago == FormaPago.tarjeta.name ? null : costo.cuentaFinancieraId,
          deudaIdTarjeta: costo.formaPago == FormaPago.tarjeta.name ? costo.deudaIdTarjeta : null,
        ),
    ];

    try {
      final tiempoExtra = await _repository.crear(
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
        costosAdicionales: costosNormalizados,
        beneficiarioEgreso: beneficiarioEgreso,
        actorUsuarioId: actorUsuarioId,
      );
      return RegistrarTiempoExtraExitoso(tiempoExtra);
    } on SaldoInsuficienteException {
      // Un saldo insuficiente NO es un error inesperado: es un
      // rechazo previsto y accionable. Se deja propagar para que la
      // pantalla muestre disponible/requerido/faltante en vez de un
      // mensaje genérico. La transacción ya quedó revertida entera.
      rethrow;
    } catch (e) {
      return RegistrarTiempoExtraErrorInesperado(e.toString());
    }
  }
}
