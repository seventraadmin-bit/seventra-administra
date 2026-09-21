import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/features/servicios_eventuales/domain/usecases/eliminar_servicio_eventual_fisicamente_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_financieras/cuentas_financieras_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/deudas_credito/deudas_credito_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/egresos_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/planeacion/planeacion_financiera_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_controller.dart';

import '../data/tables/servicio_eventual_table.dart';
import '../domain/repositories/servicio_eventual_repository.dart';
import '../domain/totales_venta_eventual.dart' show TratamientoIva;
import '../domain/usecases/agregar_cobertura_servicio_eventual_usecase.dart';
import '../domain/usecases/agregar_costo_servicio_eventual_usecase.dart';
import '../domain/usecases/agregar_participante_servicio_eventual_usecase.dart';
import '../domain/usecases/cancelar_cobertura_servicio_eventual_usecase.dart';
import '../domain/usecases/cancelar_costo_servicio_eventual_usecase.dart';
import '../domain/usecases/cancelar_servicio_eventual_usecase.dart';
import '../domain/usecases/corregir_cobertura_servicio_eventual_usecase.dart';
import '../domain/usecases/corregir_costo_servicio_eventual_usecase.dart';
import '../domain/usecases/corregir_servicio_eventual_usecase.dart';
import '../domain/usecases/crear_servicio_eventual_usecase.dart';
import '../domain/usecases/finalizar_servicio_eventual_usecase.dart';
import '../domain/usecases/pagar_cobertura_servicio_eventual_usecase.dart';
import '../domain/usecases/pagar_costo_servicio_eventual_usecase.dart';
import '../domain/usecases/retirar_participante_servicio_eventual_usecase.dart';
import '../domain/usecases/revertir_pago_cobertura_servicio_eventual_usecase.dart';
import '../domain/usecases/revertir_pago_costo_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_por_cobrar/cuentas_por_cobrar_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/ingresos/ingresos_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_controller.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart'
    show MetodoPagoCobro;

import '../domain/usecases/cancelar_documento_fiscal_eventual_usecase.dart';
import '../domain/usecases/corregir_documento_fiscal_eventual_usecase.dart';
import '../domain/usecases/registrar_cobro_servicio_eventual_usecase.dart';
import '../domain/usecases/registrar_documento_fiscal_eventual_usecase.dart';
import '../servicios_eventuales_providers.dart';
import 'servicios_eventuales_state.dart';

part 'servicios_eventuales_controller.g.dart';

/// Controlador de Comercial → Eventuales.
///
/// Todas las escrituras pasan por las fachadas `*Autorizado`: la
/// pantalla nunca llama a un caso de uso directamente, así que ninguna
/// ruta de UI puede saltarse la facultad.
///
/// Sólo las operaciones que mueven dinero (pagar y revertir pago)
/// invalidan Finanzas — programar una cobertura no crea ningún Egreso
/// ni ningún cargo, y hacer que Egresos se recargue por eso sería
/// mentirle al usuario sobre lo que acaba de pasar.
@riverpod
class ServiciosEventualesController extends _$ServiciosEventualesController {
  @override
  ServiciosEventualesState build() {
    Future.microtask(_cargar);
    return const ServiciosEventualesState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final renglones = await ref.read(listarServiciosEventualesUseCaseProvider).ejecutar(estatus: state.estatus);
      state = state.copyWith(cargando: false, renglones: renglones, errorCarga: null);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> filtrarPorEstatus(EstatusServicioEventual? estatus) async {
    state = state.copyWith(estatus: estatus, limpiarEstatus: estatus == null);
    await _cargar();
  }

  // --- Lecturas del expediente ------------------------------------

  Future<ServicioEventualData?> obtenerPorId(String id) =>
      ref.read(servicioEventualRepositoryProvider).obtenerPorId(id);

  Future<List<ServicioEventualParticipanteData>> listarParticipantes(String id) =>
      ref.read(servicioEventualRepositoryProvider).listarParticipantes(id);

  Future<List<ServicioEventualCoberturaData>> listarCoberturas(String id) =>
      ref.read(servicioEventualRepositoryProvider).listarCoberturas(id);

  Future<List<ServicioEventualCostoData>> listarCostos(String id) =>
      ref.read(servicioEventualRepositoryProvider).listarCostos(id);

  Future<List<ServicioEventualEventoData>> listarEventos(String id) =>
      ref.read(servicioEventualRepositoryProvider).listarEventos(id);

  Future<TotalesServicioEventual> totales(String id) async {
    final totales = await ref.read(servicioEventualRepositoryProvider).totalesPorEventual([id]);
    return totales[id] ?? const TotalesServicioEventual();
  }

  // --- Núcleo ------------------------------------------------------

  Future<CrearServicioEventualResultado> crear({
    required String nombre,
    required DateTime fechaHoraInicio,
    required DateTime fechaHoraFin,
    String? ubicacion,
    String? notas,
    required int importeAcordado,
    required TipoSolicitanteServicioEventual tipoSolicitante,
    String? clienteId,
    String? solicitanteNombre,
    String? solicitanteContacto,
    String? solicitanteTelefono,
    String? solicitanteCorreo,
    String? entidadFiscalId,
    String? solicitanteRazonSocial,
    String? solicitanteRfc,
    String? solicitanteCodigoPostalFiscal,
    bool requiereFactura = false,
    TratamientoIva tratamientoIva = TratamientoIva.noAplica,
    MetodoPagoCobro metodoCobro = MetodoPagoCobro.noAplica,
    DateTime? fechaVencimiento,
    CobroInmediatoServicioEventual? cobroInmediato,
  }) async {
    final resultado = await ref.read(crearServicioEventualAutorizadoProvider)(
      nombre: nombre,
      fechaHoraInicio: fechaHoraInicio,
      fechaHoraFin: fechaHoraFin,
      ubicacion: ubicacion,
      notas: notas,
      importeAcordado: importeAcordado,
      tipoSolicitante: tipoSolicitante,
      clienteId: clienteId,
      solicitanteNombre: solicitanteNombre,
      solicitanteContacto: solicitanteContacto,
      solicitanteTelefono: solicitanteTelefono,
      solicitanteCorreo: solicitanteCorreo,
      entidadFiscalId: entidadFiscalId,
      solicitanteRazonSocial: solicitanteRazonSocial,
      solicitanteRfc: solicitanteRfc,
      solicitanteCodigoPostalFiscal: solicitanteCodigoPostalFiscal,
      requiereFactura: requiereFactura,
      tratamientoIva: tratamientoIva,
      metodoCobro: metodoCobro,
      fechaVencimiento: fechaVencimiento,
      cobroInmediato: cobroInmediato,
    );
    if (resultado is CrearServicioEventualExitoso) {
      await _cargar();
      _invalidarCobranza(huboCobro: cobroInmediato != null);
    }
    return resultado;
  }

  Future<CorregirServicioEventualResultado> corregir({
    required String servicioEventualId,
    String? nombre,
    DateTime? fechaHoraInicio,
    DateTime? fechaHoraFin,
    String? ubicacion,
    String? notas,
    int? importeAcordado,
    TratamientoIva? tratamientoIva,
    bool? requiereFactura,
    required String motivo,
  }) async {
    final resultado = await ref.read(corregirServicioEventualAutorizadoProvider)(
      servicioEventualId: servicioEventualId,
      nombre: nombre,
      fechaHoraInicio: fechaHoraInicio,
      fechaHoraFin: fechaHoraFin,
      ubicacion: ubicacion,
      notas: notas,
      importeAcordado: importeAcordado,
      tratamientoIva: tratamientoIva,
      requiereFactura: requiereFactura,
      motivo: motivo,
    );
    if (resultado is CorregirServicioEventualExitoso) {
      await _cargar();
      // Corregir el importe o el tratamiento mueve el total de la
      // Cuenta por cobrar: la cobranza tiene que recargarse.
      _invalidarCobranza(huboCobro: false);
    }
    return resultado;
  }

  Future<FinalizarServicioEventualResultado> finalizar(String servicioEventualId) async {
    final resultado = await ref.read(finalizarServicioEventualAutorizadoProvider)(
      servicioEventualId: servicioEventualId,
    );
    if (resultado is FinalizarServicioEventualExitoso) await _cargar();
    return resultado;
  }

  Future<CancelarServicioEventualResultado> cancelar({
    required String servicioEventualId,
    required String motivo,
  }) async {
    final resultado = await ref.read(cancelarServicioEventualAutorizadoProvider)(
      servicioEventualId: servicioEventualId,
      motivo: motivo,
    );
    if (resultado is CancelarServicioEventualExitoso) {
      await _cargar();
      // Anular la venta revierte Pago, Ingreso y saldo de la cuenta:
      // sin esto, Finanzas seguiría mostrando dinero que ya volvió.
      _invalidarCobranza(huboCobro: true);
    }
    return resultado;
  }

  // --- Participantes ----------------------------------------------

  Future<AgregarParticipanteServicioEventualResultado> agregarParticipante({
    required String servicioEventualId,
    String? empleadoId,
    String? nombreExterno,
    String? telefonoExterno,
    String? observaciones,
  }) {
    return ref.read(agregarParticipanteServicioEventualAutorizadoProvider)(
      servicioEventualId: servicioEventualId,
      empleadoId: empleadoId,
      nombreExterno: nombreExterno,
      telefonoExterno: telefonoExterno,
      observaciones: observaciones,
    );
  }

  Future<RetirarParticipanteServicioEventualResultado> retirarParticipante(String participanteId) {
    return ref.read(retirarParticipanteServicioEventualAutorizadoProvider)(participanteId: participanteId);
  }

  // --- Coberturas ---------------------------------------------------

  Future<AgregarCoberturaServicioEventualResultado> agregarCobertura({
    required String servicioEventualId,
    required String participanteId,
    required DateTime fecha,
    required int horaInicioMinutos,
    required int horaFinMinutos,
    String? descripcionHorario,
    required int importeAcordado,
  }) async {
    final resultado = await ref.read(agregarCoberturaServicioEventualAutorizadoProvider)(
      servicioEventualId: servicioEventualId,
      participanteId: participanteId,
      fecha: fecha,
      horaInicioMinutos: horaInicioMinutos,
      horaFinMinutos: horaFinMinutos,
      descripcionHorario: descripcionHorario,
      importeAcordado: importeAcordado,
    );
    if (resultado is AgregarCoberturaServicioEventualExitoso) await _cargar();
    return resultado;
  }

  Future<CorregirCoberturaServicioEventualResultado> corregirCobertura({
    required String coberturaId,
    DateTime? fecha,
    int? horaInicioMinutos,
    int? horaFinMinutos,
    String? descripcionHorario,
    int? importeAcordado,
    required String motivo,
  }) async {
    final resultado = await ref.read(corregirCoberturaServicioEventualAutorizadoProvider)(
      coberturaId: coberturaId,
      fecha: fecha,
      horaInicioMinutos: horaInicioMinutos,
      horaFinMinutos: horaFinMinutos,
      descripcionHorario: descripcionHorario,
      importeAcordado: importeAcordado,
      motivo: motivo,
    );
    if (resultado is CorregirCoberturaServicioEventualExitoso) await _cargar();
    return resultado;
  }

  Future<CancelarCoberturaServicioEventualResultado> cancelarCobertura({
    required String coberturaId,
    required String motivo,
  }) async {
    final resultado = await ref.read(cancelarCoberturaServicioEventualAutorizadoProvider)(
      coberturaId: coberturaId,
      motivo: motivo,
    );
    if (resultado is CancelarCoberturaServicioEventualExitoso) await _cargar();
    return resultado;
  }

  Future<PagarCoberturaServicioEventualResultado> pagarCobertura({
    required String coberturaId,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
  }) async {
    final resultado = await ref.read(pagarCoberturaServicioEventualAutorizadoProvider)(
      coberturaId: coberturaId,
      formaPago: formaPago,
      cuentaFinancieraId: cuentaFinancieraId,
      deudaIdTarjeta: deudaIdTarjeta,
    );
    if (resultado is PagarCoberturaServicioEventualExitoso) {
      await _cargar();
      _invalidarFinanzas(cuentaFinancieraId: cuentaFinancieraId, deudaIdTarjeta: deudaIdTarjeta);
    }
    return resultado;
  }

  Future<RevertirPagoCoberturaServicioEventualResultado> revertirPagoCobertura({
    required String coberturaId,
    required String motivo,
  }) async {
    final resultado = await ref.read(revertirPagoCoberturaServicioEventualAutorizadoProvider)(
      coberturaId: coberturaId,
      motivo: motivo,
    );
    if (resultado is RevertirPagoCoberturaServicioEventualExitoso) {
      await _cargar();
      // Revertir toca cuenta O tarjeta según cómo se pagó, y aquí ya
      // no se sabe cuál era: se invalidan ambas, mismo criterio que
      // `TiemposExtraController.cancelar`.
      _invalidarFinanzas();
    }
    return resultado;
  }

  // --- Costos -------------------------------------------------------

  Future<AgregarCostoServicioEventualResultado> agregarCosto({
    required String servicioEventualId,
    required String concepto,
    required int monto,
    required DateTime fecha,
    String? observaciones,
  }) async {
    final resultado = await ref.read(agregarCostoServicioEventualAutorizadoProvider)(
      servicioEventualId: servicioEventualId,
      concepto: concepto,
      monto: monto,
      fecha: fecha,
      observaciones: observaciones,
    );
    if (resultado is AgregarCostoServicioEventualExitoso) await _cargar();
    return resultado;
  }

  Future<CorregirCostoServicioEventualResultado> corregirCosto({
    required String costoId,
    String? concepto,
    int? monto,
    DateTime? fecha,
    String? observaciones,
    required String motivo,
  }) async {
    final resultado = await ref.read(corregirCostoServicioEventualAutorizadoProvider)(
      costoId: costoId,
      concepto: concepto,
      monto: monto,
      fecha: fecha,
      observaciones: observaciones,
      motivo: motivo,
    );
    if (resultado is CorregirCostoServicioEventualExitoso) await _cargar();
    return resultado;
  }

  Future<CancelarCostoServicioEventualResultado> cancelarCosto({
    required String costoId,
    required String motivo,
  }) async {
    final resultado = await ref.read(cancelarCostoServicioEventualAutorizadoProvider)(
      costoId: costoId,
      motivo: motivo,
    );
    if (resultado is CancelarCostoServicioEventualExitoso) await _cargar();
    return resultado;
  }

  Future<PagarCostoServicioEventualResultado> pagarCosto({
    required String costoId,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
  }) async {
    final resultado = await ref.read(pagarCostoServicioEventualAutorizadoProvider)(
      costoId: costoId,
      formaPago: formaPago,
      cuentaFinancieraId: cuentaFinancieraId,
      deudaIdTarjeta: deudaIdTarjeta,
    );
    if (resultado is PagarCostoServicioEventualExitoso) {
      await _cargar();
      _invalidarFinanzas(cuentaFinancieraId: cuentaFinancieraId, deudaIdTarjeta: deudaIdTarjeta);
    }
    return resultado;
  }

  Future<RevertirPagoCostoServicioEventualResultado> revertirPagoCosto({
    required String costoId,
    required String motivo,
  }) async {
    final resultado = await ref.read(revertirPagoCostoServicioEventualAutorizadoProvider)(
      costoId: costoId,
      motivo: motivo,
    );
    if (resultado is RevertirPagoCostoServicioEventualExitoso) {
      await _cargar();
      _invalidarFinanzas();
    }
    return resultado;
  }

  // ================================================================
  // Cobranza y documento fiscal (schemaVersion 88)
  // ================================================================

  Future<CuentaPorCobrarData?> obtenerCuentaPorCobrar(String servicioEventualId) =>
      ref.read(servicioEventualRepositoryProvider).obtenerCuentaPorCobrar(servicioEventualId);

  Future<List<ServicioEventualDocumentoFiscalData>> listarDocumentosFiscales(String servicioEventualId) =>
      ref.read(servicioEventualDocumentoFiscalRepositoryProvider).listarPorEventual(servicioEventualId);

  /// Los Pagos aplicados a la Cuenta del eventual — se leen por las
  /// aplicaciones de esa Cuenta, nunca por la contraparte: un Cliente
  /// puede tener pagos de otras facturas que no son de este evento.
  Future<List<({AplicacionPagoData aplicacion, PagoData pago})>> listarPagosDeLaCuenta(
    String cuentaPorCobrarId,
  ) async {
    final aplicaciones = await ref.read(pagoRepositoryProvider).listarAplicacionesPorCuenta(cuentaPorCobrarId);
    final resultado = <({AplicacionPagoData aplicacion, PagoData pago})>[];
    for (final aplicacion in aplicaciones) {
      final pago = await ref.read(pagoRepositoryProvider).obtenerPorId(aplicacion.pagoId);
      if (pago != null) resultado.add((aplicacion: aplicacion, pago: pago));
    }
    return resultado;
  }

  Future<RegistrarCobroServicioEventualResultado> registrarCobro({
    required String servicioEventualId,
    required int monto,
    required DateTime fechaPago,
    required String formaPago,
    String? cuentaFinancieraId,
    String? referencia,
    String? observaciones,
  }) async {
    final resultado = await ref.read(registrarCobroServicioEventualAutorizadoProvider)(
      servicioEventualId: servicioEventualId,
      monto: monto,
      fechaPago: fechaPago,
      formaPago: formaPago,
      cuentaFinancieraId: cuentaFinancieraId,
      referencia: referencia,
      observaciones: observaciones,
    );
    if (resultado is RegistrarCobroServicioEventualExitoso) {
      await _cargar();
      _invalidarCobranza(huboCobro: true);
    }
    return resultado;
  }

  Future<RegistrarDocumentoFiscalEventualResultado> registrarDocumentoFiscal({
    required String servicioEventualId,
    required String folio,
    String? uuid,
    required DateTime fechaEmision,
    required MetodoPagoCobro metodo,
    String? entidadFiscalId,
    String? razonSocialManual,
    String? rfcManual,
    String? codigoPostalFiscalManual,
    String? observaciones,
  }) async {
    final resultado = await ref.read(registrarDocumentoFiscalEventualAutorizadoProvider)(
      servicioEventualId: servicioEventualId,
      folio: folio,
      uuid: uuid,
      fechaEmision: fechaEmision,
      metodo: metodo,
      entidadFiscalId: entidadFiscalId,
      razonSocialManual: razonSocialManual,
      rfcManual: rfcManual,
      codigoPostalFiscalManual: codigoPostalFiscalManual,
      observaciones: observaciones,
    );
    // Facturar cambia el método de la Cuenta (y con PPD, su obligación
    // de Complemento): la cobranza tiene que recargarse. No mueve
    // dinero, así que Cuentas financieras y Deudas no se tocan.
    if (resultado is RegistrarDocumentoFiscalEventualExitoso) _invalidarCobranza(huboCobro: false);
    return resultado;
  }

  Future<CorregirDocumentoFiscalEventualResultado> corregirDocumentoFiscal({
    required String documentoId,
    String? folio,
    String? uuid,
    DateTime? fechaEmision,
    MetodoPagoCobro? metodo,
    String? observaciones,
    required String motivo,
  }) async {
    final resultado = await ref.read(corregirDocumentoFiscalEventualAutorizadoProvider)(
      documentoId: documentoId,
      folio: folio,
      uuid: uuid,
      fechaEmision: fechaEmision,
      metodo: metodo,
      observaciones: observaciones,
      motivo: motivo,
    );
    if (resultado is CorregirDocumentoFiscalEventualExitoso) _invalidarCobranza(huboCobro: false);
    return resultado;
  }

  Future<CancelarDocumentoFiscalEventualResultado> cancelarDocumentoFiscal({
    required String documentoId,
    required String motivo,
  }) async {
    final resultado = await ref.read(cancelarDocumentoFiscalEventualAutorizadoProvider)(
      documentoId: documentoId,
      motivo: motivo,
    );
    if (resultado is CancelarDocumentoFiscalEventualExitoso) _invalidarCobranza(huboCobro: false);
    return resultado;
  }

  /// Cobranza y, si de verdad entró dinero, también la caja.
  void _invalidarCobranza({required bool huboCobro}) {
    ref.invalidate(cuentasPorCobrarControllerProvider);
    ref.invalidate(dashboardControllerProvider);
    ref.invalidate(resumenFinancieroControllerProvider);
    ref.invalidate(planeacionFinancieraControllerProvider);
    if (huboCobro) {
      ref.invalidate(pagosControllerProvider);
      ref.invalidate(ingresosControllerProvider);
      ref.invalidate(cuentasFinancierasControllerProvider);
    }
  }

  /// Eliminación física extraordinaria (Maestro). El guardia real es
  /// `exigirMaestro` en la fachada; aquí sólo se refresca lo que el
  /// borrado pudo mover: la cobranza (Cuenta, Pago, Ingreso) y el
  /// dinero derivado de ellos.
  Future<EliminarServicioEventualFisicamenteResultado> eliminarFisicamente({
    required String servicioEventualId,
    required String motivo,
  }) async {
    final resultado = await ref.read(eliminarServicioEventualFisicamenteAutorizadoProvider)(
      servicioEventualId: servicioEventualId,
      motivo: motivo,
    );
    if (resultado is EliminarServicioEventualFisicamenteExitoso) {
      await _cargar();
      _invalidarCobranza(huboCobro: true);
      // Sin origen conocido: el borrado pudo llevarse un Ingreso de
      // cualquier cuenta, así que se refrescan las dos vistas.
      _invalidarFinanzas();
    }
    return resultado;
  }

  /// Sin argumentos invalida las dos vistas de origen — el caso de una
  /// reversión, donde ya no se sabe con qué se había pagado.
  void _invalidarFinanzas({String? cuentaFinancieraId, String? deudaIdTarjeta}) {
    ref.invalidate(egresosControllerProvider);
    ref.invalidate(dashboardControllerProvider);
    ref.invalidate(resumenFinancieroControllerProvider);
    ref.invalidate(planeacionFinancieraControllerProvider);
    final sinOrigenConocido = cuentaFinancieraId == null && deudaIdTarjeta == null;
    if (sinOrigenConocido || cuentaFinancieraId != null) {
      ref.invalidate(cuentasFinancierasControllerProvider);
    }
    if (sinOrigenConocido || deudaIdTarjeta != null) {
      ref.invalidate(deudasCreditoControllerProvider);
    }
  }
}
