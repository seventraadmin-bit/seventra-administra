import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';

import '../../core/di/providers.dart';
import '../../core/permissions/authorization_service.dart';
import '../finanzas/finanzas_providers.dart';
import '../organizacion/organizacion_providers.dart';
import '../personal/personal_providers.dart';
import '../usuarios/presentation/sesion_controller.dart';
import '../usuarios/usuarios_providers.dart';
import 'data/repositories/servicio_eventual_repository_impl.dart';
import 'data/tables/servicio_eventual_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart'
    show MetodoPagoCobro;

import 'domain/totales_venta_eventual.dart' show TratamientoIva;

import 'data/repositories/servicio_eventual_documento_fiscal_repository_impl.dart';
import 'domain/repositories/servicio_eventual_documento_fiscal_repository.dart';
import 'domain/repositories/servicio_eventual_repository.dart';
import 'domain/usecases/cancelar_documento_fiscal_eventual_usecase.dart';
import 'domain/usecases/corregir_documento_fiscal_eventual_usecase.dart';
import 'domain/usecases/registrar_cobro_servicio_eventual_usecase.dart';
import 'domain/usecases/registrar_documento_fiscal_eventual_usecase.dart';
import 'domain/usecases/agregar_cobertura_servicio_eventual_usecase.dart';
import 'domain/usecases/agregar_costo_servicio_eventual_usecase.dart';
import 'domain/usecases/agregar_participante_servicio_eventual_usecase.dart';
import 'domain/usecases/cancelar_cobertura_servicio_eventual_usecase.dart';
import 'domain/usecases/cancelar_costo_servicio_eventual_usecase.dart';
import 'domain/usecases/cancelar_servicio_eventual_usecase.dart';
import 'domain/usecases/corregir_cobertura_servicio_eventual_usecase.dart';
import 'domain/usecases/corregir_costo_servicio_eventual_usecase.dart';
import 'domain/usecases/corregir_servicio_eventual_usecase.dart';
import 'domain/usecases/crear_servicio_eventual_usecase.dart';
import 'domain/usecases/eliminar_servicio_eventual_fisicamente_usecase.dart';
import 'domain/usecases/finalizar_servicio_eventual_usecase.dart';
import 'domain/usecases/listar_servicios_eventuales_usecase.dart';
import 'domain/usecases/pagar_cobertura_servicio_eventual_usecase.dart';
import 'domain/usecases/pagar_costo_servicio_eventual_usecase.dart';
import 'domain/usecases/retirar_participante_servicio_eventual_usecase.dart';
import 'domain/usecases/revertir_pago_cobertura_servicio_eventual_usecase.dart';
import 'domain/usecases/revertir_pago_costo_servicio_eventual_usecase.dart';

/// Providers del dominio Servicios Eventuales (schemaVersion 87).
///
/// El repositorio compone `EgresoRepository`/`DeudaRepository` por el
/// camino oficial de escritura de Finanzas — nunca escribe un Egreso ni
/// un `MovimientoDeuda` a mano, mismo criterio que Compras, Tiempos
/// Extra y las Recargas de Telefonía.
final servicioEventualRepositoryProvider = Provider<ServicioEventualRepository>((ref) {
  return ServicioEventualRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(egresoRepositoryProvider),
    ref.watch(deudaRepositoryProvider),
    CodigoSecuenciaService(ref.watch(appDatabaseProvider)),
    ref.watch(cuentaPorCobrarRepositoryProvider),
    ref.watch(pagoRepositoryProvider),
  );
});

// --- Núcleo -------------------------------------------------------

final crearServicioEventualUseCaseProvider = Provider<CrearServicioEventualUseCase>((ref) {
  return CrearServicioEventualUseCase(
    ref.watch(servicioEventualRepositoryProvider),
    ref.watch(clienteRepositoryProvider),
    ref.watch(entidadFiscalRepositoryProvider),
  );
});

final corregirServicioEventualUseCaseProvider = Provider<CorregirServicioEventualUseCase>((ref) {
  return CorregirServicioEventualUseCase(
    ref.watch(servicioEventualRepositoryProvider),
    ref.watch(cuentaPorCobrarRepositoryProvider),
    ref.watch(pagoRepositoryProvider),
  );
});

// --- Cobranza y documento fiscal (schemaVersion 88) ---------------

final servicioEventualDocumentoFiscalRepositoryProvider =
    Provider<ServicioEventualDocumentoFiscalRepository>((ref) {
  return ServicioEventualDocumentoFiscalRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(cuentaPorCobrarRepositoryProvider),
    ref.watch(servicioEventualRepositoryProvider),
  );
});

final registrarDocumentoFiscalEventualUseCaseProvider =
    Provider<RegistrarDocumentoFiscalEventualUseCase>((ref) {
  return RegistrarDocumentoFiscalEventualUseCase(
    ref.watch(servicioEventualDocumentoFiscalRepositoryProvider),
    ref.watch(servicioEventualRepositoryProvider),
    ref.watch(cuentaPorCobrarRepositoryProvider),
    ref.watch(entidadFiscalRepositoryProvider),
  );
});

final corregirDocumentoFiscalEventualUseCaseProvider =
    Provider<CorregirDocumentoFiscalEventualUseCase>((ref) {
  return CorregirDocumentoFiscalEventualUseCase(
    ref.watch(servicioEventualDocumentoFiscalRepositoryProvider),
  );
});

final cancelarDocumentoFiscalEventualUseCaseProvider =
    Provider<CancelarDocumentoFiscalEventualUseCase>((ref) {
  return CancelarDocumentoFiscalEventualUseCase(
    ref.watch(servicioEventualDocumentoFiscalRepositoryProvider),
  );
});

final registrarCobroServicioEventualUseCaseProvider =
    Provider<RegistrarCobroServicioEventualUseCase>((ref) {
  return RegistrarCobroServicioEventualUseCase(
    ref.watch(servicioEventualRepositoryProvider),
    ref.watch(registrarPagoAplicadoUseCaseProvider),
  );
});

final finalizarServicioEventualUseCaseProvider = Provider<FinalizarServicioEventualUseCase>((ref) {
  return FinalizarServicioEventualUseCase(ref.watch(servicioEventualRepositoryProvider));
});

final cancelarServicioEventualUseCaseProvider = Provider<CancelarServicioEventualUseCase>((ref) {
  return CancelarServicioEventualUseCase(
    ref.watch(servicioEventualRepositoryProvider),
    ref.watch(servicioEventualDocumentoFiscalRepositoryProvider),
    ref.watch(complementoPagoRepositoryProvider),
  );
});

/// Qué se revertirá y qué permanecerá si se anula la venta. Sólo
/// lectura, así que no pasa por `autorizarUseCase`: no cambia nada, y
/// el usuario que ya tiene abierto el expediente puede verlo.
///
/// Vive en este archivo —y no en la pantalla— porque el provider del
/// caso de uso está protegido: leerlo crudo desde Presentation sería
/// una violación del auditor.
typedef PrevisualizarAnulacionServicioEventual = Future<ResumenAnulacionServicioEventual> Function(String);

final previsualizarAnulacionServicioEventualProvider =
    Provider<PrevisualizarAnulacionServicioEventual>((ref) {
  return (servicioEventualId) =>
      ref.read(cancelarServicioEventualUseCaseProvider).previsualizar(servicioEventualId);
});

final listarServiciosEventualesUseCaseProvider = Provider<ListarServiciosEventualesUseCase>((ref) {
  return ListarServiciosEventualesUseCase(
    ref.watch(servicioEventualRepositoryProvider),
    ref.watch(clienteRepositoryProvider),
    ref.watch(cuentaPorCobrarRepositoryProvider),
  );
});

// --- Participantes ------------------------------------------------

final agregarParticipanteServicioEventualUseCaseProvider =
    Provider<AgregarParticipanteServicioEventualUseCase>((ref) {
  return AgregarParticipanteServicioEventualUseCase(
    ref.watch(servicioEventualRepositoryProvider),
    ref.watch(empleadoRepositoryProvider),
  );
});

final retirarParticipanteServicioEventualUseCaseProvider =
    Provider<RetirarParticipanteServicioEventualUseCase>((ref) {
  return RetirarParticipanteServicioEventualUseCase(ref.watch(servicioEventualRepositoryProvider));
});

// --- Coberturas ---------------------------------------------------

final agregarCoberturaServicioEventualUseCaseProvider =
    Provider<AgregarCoberturaServicioEventualUseCase>((ref) {
  return AgregarCoberturaServicioEventualUseCase(ref.watch(servicioEventualRepositoryProvider));
});

final corregirCoberturaServicioEventualUseCaseProvider =
    Provider<CorregirCoberturaServicioEventualUseCase>((ref) {
  return CorregirCoberturaServicioEventualUseCase(ref.watch(servicioEventualRepositoryProvider));
});

final cancelarCoberturaServicioEventualUseCaseProvider =
    Provider<CancelarCoberturaServicioEventualUseCase>((ref) {
  return CancelarCoberturaServicioEventualUseCase(ref.watch(servicioEventualRepositoryProvider));
});

final pagarCoberturaServicioEventualUseCaseProvider = Provider<PagarCoberturaServicioEventualUseCase>((ref) {
  return PagarCoberturaServicioEventualUseCase(
    ref.watch(servicioEventualRepositoryProvider),
    ref.watch(deudaRepositoryProvider),
  );
});

final revertirPagoCoberturaServicioEventualUseCaseProvider =
    Provider<RevertirPagoCoberturaServicioEventualUseCase>((ref) {
  return RevertirPagoCoberturaServicioEventualUseCase(ref.watch(servicioEventualRepositoryProvider));
});

// --- Costos -------------------------------------------------------

final agregarCostoServicioEventualUseCaseProvider = Provider<AgregarCostoServicioEventualUseCase>((ref) {
  return AgregarCostoServicioEventualUseCase(ref.watch(servicioEventualRepositoryProvider));
});

final corregirCostoServicioEventualUseCaseProvider = Provider<CorregirCostoServicioEventualUseCase>((ref) {
  return CorregirCostoServicioEventualUseCase(ref.watch(servicioEventualRepositoryProvider));
});

final cancelarCostoServicioEventualUseCaseProvider = Provider<CancelarCostoServicioEventualUseCase>((ref) {
  return CancelarCostoServicioEventualUseCase(ref.watch(servicioEventualRepositoryProvider));
});

final pagarCostoServicioEventualUseCaseProvider = Provider<PagarCostoServicioEventualUseCase>((ref) {
  return PagarCostoServicioEventualUseCase(
    ref.watch(servicioEventualRepositoryProvider),
    ref.watch(deudaRepositoryProvider),
  );
});

final revertirPagoCostoServicioEventualUseCaseProvider =
    Provider<RevertirPagoCostoServicioEventualUseCase>((ref) {
  return RevertirPagoCostoServicioEventualUseCase(ref.watch(servicioEventualRepositoryProvider));
});

// ==================================================================
// Fachadas autorizadas
// ==================================================================
//
// Ninguna pantalla llama a un caso de uso directamente: la facultad se
// exige aquí, en el único punto por el que pasa la operación.
// `pagar`/`revertirPago` son facultades propias, distintas de `crear`,
// porque son las únicas de este dominio que mueven dinero real.

typedef CrearServicioEventualAutorizado = Future<CrearServicioEventualResultado> Function({
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
  bool requiereFactura,
  TratamientoIva tratamientoIva,
  MetodoPagoCobro metodoCobro,
  DateTime? fechaVencimiento,
  CobroInmediatoServicioEventual? cobroInmediato,
});

final crearServicioEventualAutorizadoProvider = Provider<CrearServicioEventualAutorizado>((ref) {
  return ({
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
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      // Vender y cobrar en el mismo acto exige las dos facultades: la
      // de crear el eventual y la de registrar cobranza. Se comprueban
      // aquí, antes de abrir la transacción.
      cobroInmediato == null ? 'serviciosEventuales.crear' : 'serviciosEventuales.cobrar',
      () => ref.read(crearServicioEventualUseCaseProvider).ejecutar(
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
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      CrearServicioEventualErrorInesperado.new,
    );
  };
});

typedef CorregirServicioEventualAutorizado = Future<CorregirServicioEventualResultado> Function({
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
});

final corregirServicioEventualAutorizadoProvider = Provider<CorregirServicioEventualAutorizado>((ref) {
  return ({
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
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'serviciosEventuales.corregir',
      () => ref.read(corregirServicioEventualUseCaseProvider).ejecutar(
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
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      CorregirServicioEventualErrorInesperado.new,
    );
  };
});

typedef FinalizarServicioEventualAutorizado = Future<FinalizarServicioEventualResultado> Function({
  required String servicioEventualId,
});

final finalizarServicioEventualAutorizadoProvider = Provider<FinalizarServicioEventualAutorizado>((ref) {
  return ({required String servicioEventualId}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'serviciosEventuales.corregir',
      () => ref.read(finalizarServicioEventualUseCaseProvider).ejecutar(
            servicioEventualId: servicioEventualId,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      FinalizarServicioEventualErrorInesperado.new,
    );
  };
});

typedef CancelarServicioEventualAutorizado = Future<CancelarServicioEventualResultado> Function({
  required String servicioEventualId,
  required String motivo,
});

final cancelarServicioEventualAutorizadoProvider = Provider<CancelarServicioEventualAutorizado>((ref) {
  return ({required String servicioEventualId, required String motivo}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'serviciosEventuales.cancelar',
      () => ref.read(cancelarServicioEventualUseCaseProvider).ejecutar(
            servicioEventualId: servicioEventualId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      CancelarServicioEventualErrorInesperado.new,
    );
  };
});

typedef AgregarParticipanteServicioEventualAutorizado
    = Future<AgregarParticipanteServicioEventualResultado> Function({
  required String servicioEventualId,
  String? empleadoId,
  String? nombreExterno,
  String? telefonoExterno,
  String? observaciones,
});

final agregarParticipanteServicioEventualAutorizadoProvider =
    Provider<AgregarParticipanteServicioEventualAutorizado>((ref) {
  return ({
    required String servicioEventualId,
    String? empleadoId,
    String? nombreExterno,
    String? telefonoExterno,
    String? observaciones,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'serviciosEventuales.corregir',
      () => ref.read(agregarParticipanteServicioEventualUseCaseProvider).ejecutar(
            servicioEventualId: servicioEventualId,
            empleadoId: empleadoId,
            nombreExterno: nombreExterno,
            telefonoExterno: telefonoExterno,
            observaciones: observaciones,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      AgregarParticipanteServicioEventualErrorInesperado.new,
    );
  };
});

typedef RetirarParticipanteServicioEventualAutorizado
    = Future<RetirarParticipanteServicioEventualResultado> Function({required String participanteId});

final retirarParticipanteServicioEventualAutorizadoProvider =
    Provider<RetirarParticipanteServicioEventualAutorizado>((ref) {
  return ({required String participanteId}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'serviciosEventuales.corregir',
      () => ref.read(retirarParticipanteServicioEventualUseCaseProvider).ejecutar(
            participanteId: participanteId,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      RetirarParticipanteServicioEventualErrorInesperado.new,
    );
  };
});

typedef AgregarCoberturaServicioEventualAutorizado
    = Future<AgregarCoberturaServicioEventualResultado> Function({
  required String servicioEventualId,
  required String participanteId,
  required DateTime fecha,
  required int horaInicioMinutos,
  required int horaFinMinutos,
  String? descripcionHorario,
  required int importeAcordado,
});

final agregarCoberturaServicioEventualAutorizadoProvider =
    Provider<AgregarCoberturaServicioEventualAutorizado>((ref) {
  return ({
    required String servicioEventualId,
    required String participanteId,
    required DateTime fecha,
    required int horaInicioMinutos,
    required int horaFinMinutos,
    String? descripcionHorario,
    required int importeAcordado,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'serviciosEventuales.corregir',
      () => ref.read(agregarCoberturaServicioEventualUseCaseProvider).ejecutar(
            servicioEventualId: servicioEventualId,
            participanteId: participanteId,
            fecha: fecha,
            horaInicioMinutos: horaInicioMinutos,
            horaFinMinutos: horaFinMinutos,
            descripcionHorario: descripcionHorario,
            importeAcordado: importeAcordado,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      AgregarCoberturaServicioEventualErrorInesperado.new,
    );
  };
});

typedef CorregirCoberturaServicioEventualAutorizado
    = Future<CorregirCoberturaServicioEventualResultado> Function({
  required String coberturaId,
  DateTime? fecha,
  int? horaInicioMinutos,
  int? horaFinMinutos,
  String? descripcionHorario,
  int? importeAcordado,
  required String motivo,
});

final corregirCoberturaServicioEventualAutorizadoProvider =
    Provider<CorregirCoberturaServicioEventualAutorizado>((ref) {
  return ({
    required String coberturaId,
    DateTime? fecha,
    int? horaInicioMinutos,
    int? horaFinMinutos,
    String? descripcionHorario,
    int? importeAcordado,
    required String motivo,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'serviciosEventuales.corregir',
      () => ref.read(corregirCoberturaServicioEventualUseCaseProvider).ejecutar(
            coberturaId: coberturaId,
            fecha: fecha,
            horaInicioMinutos: horaInicioMinutos,
            horaFinMinutos: horaFinMinutos,
            descripcionHorario: descripcionHorario,
            importeAcordado: importeAcordado,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      CorregirCoberturaServicioEventualErrorInesperado.new,
    );
  };
});

typedef CancelarCoberturaServicioEventualAutorizado
    = Future<CancelarCoberturaServicioEventualResultado> Function({
  required String coberturaId,
  required String motivo,
});

final cancelarCoberturaServicioEventualAutorizadoProvider =
    Provider<CancelarCoberturaServicioEventualAutorizado>((ref) {
  return ({required String coberturaId, required String motivo}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'serviciosEventuales.cancelar',
      () => ref.read(cancelarCoberturaServicioEventualUseCaseProvider).ejecutar(
            coberturaId: coberturaId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      CancelarCoberturaServicioEventualErrorInesperado.new,
    );
  };
});

typedef PagarCoberturaServicioEventualAutorizado = Future<PagarCoberturaServicioEventualResultado> Function({
  required String coberturaId,
  required String formaPago,
  String? cuentaFinancieraId,
  String? deudaIdTarjeta,
});

final pagarCoberturaServicioEventualAutorizadoProvider =
    Provider<PagarCoberturaServicioEventualAutorizado>((ref) {
  return ({
    required String coberturaId,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'serviciosEventuales.pagar',
      () => ref.read(pagarCoberturaServicioEventualUseCaseProvider).ejecutar(
            coberturaId: coberturaId,
            formaPago: formaPago,
            cuentaFinancieraId: cuentaFinancieraId,
            deudaIdTarjeta: deudaIdTarjeta,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      PagarCoberturaServicioEventualErrorInesperado.new,
    );
  };
});

typedef RevertirPagoCoberturaServicioEventualAutorizado
    = Future<RevertirPagoCoberturaServicioEventualResultado> Function({
  required String coberturaId,
  required String motivo,
});

final revertirPagoCoberturaServicioEventualAutorizadoProvider =
    Provider<RevertirPagoCoberturaServicioEventualAutorizado>((ref) {
  return ({required String coberturaId, required String motivo}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'serviciosEventuales.revertirPago',
      () => ref.read(revertirPagoCoberturaServicioEventualUseCaseProvider).ejecutar(
            coberturaId: coberturaId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      RevertirPagoCoberturaServicioEventualErrorInesperado.new,
    );
  };
});

typedef AgregarCostoServicioEventualAutorizado = Future<AgregarCostoServicioEventualResultado> Function({
  required String servicioEventualId,
  required String concepto,
  required int monto,
  required DateTime fecha,
  String? observaciones,
});

final agregarCostoServicioEventualAutorizadoProvider =
    Provider<AgregarCostoServicioEventualAutorizado>((ref) {
  return ({
    required String servicioEventualId,
    required String concepto,
    required int monto,
    required DateTime fecha,
    String? observaciones,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'serviciosEventuales.corregir',
      () => ref.read(agregarCostoServicioEventualUseCaseProvider).ejecutar(
            servicioEventualId: servicioEventualId,
            concepto: concepto,
            monto: monto,
            fecha: fecha,
            observaciones: observaciones,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      AgregarCostoServicioEventualErrorInesperado.new,
    );
  };
});

typedef CorregirCostoServicioEventualAutorizado = Future<CorregirCostoServicioEventualResultado> Function({
  required String costoId,
  String? concepto,
  int? monto,
  DateTime? fecha,
  String? observaciones,
  required String motivo,
});

final corregirCostoServicioEventualAutorizadoProvider =
    Provider<CorregirCostoServicioEventualAutorizado>((ref) {
  return ({
    required String costoId,
    String? concepto,
    int? monto,
    DateTime? fecha,
    String? observaciones,
    required String motivo,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'serviciosEventuales.corregir',
      () => ref.read(corregirCostoServicioEventualUseCaseProvider).ejecutar(
            costoId: costoId,
            concepto: concepto,
            monto: monto,
            fecha: fecha,
            observaciones: observaciones,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      CorregirCostoServicioEventualErrorInesperado.new,
    );
  };
});

typedef CancelarCostoServicioEventualAutorizado = Future<CancelarCostoServicioEventualResultado> Function({
  required String costoId,
  required String motivo,
});

final cancelarCostoServicioEventualAutorizadoProvider =
    Provider<CancelarCostoServicioEventualAutorizado>((ref) {
  return ({required String costoId, required String motivo}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'serviciosEventuales.cancelar',
      () => ref.read(cancelarCostoServicioEventualUseCaseProvider).ejecutar(
            costoId: costoId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      CancelarCostoServicioEventualErrorInesperado.new,
    );
  };
});

typedef PagarCostoServicioEventualAutorizado = Future<PagarCostoServicioEventualResultado> Function({
  required String costoId,
  required String formaPago,
  String? cuentaFinancieraId,
  String? deudaIdTarjeta,
});

final pagarCostoServicioEventualAutorizadoProvider = Provider<PagarCostoServicioEventualAutorizado>((ref) {
  return ({
    required String costoId,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'serviciosEventuales.pagar',
      () => ref.read(pagarCostoServicioEventualUseCaseProvider).ejecutar(
            costoId: costoId,
            formaPago: formaPago,
            cuentaFinancieraId: cuentaFinancieraId,
            deudaIdTarjeta: deudaIdTarjeta,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      PagarCostoServicioEventualErrorInesperado.new,
    );
  };
});

typedef RevertirPagoCostoServicioEventualAutorizado
    = Future<RevertirPagoCostoServicioEventualResultado> Function({
  required String costoId,
  required String motivo,
});

final revertirPagoCostoServicioEventualAutorizadoProvider =
    Provider<RevertirPagoCostoServicioEventualAutorizado>((ref) {
  return ({required String costoId, required String motivo}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'serviciosEventuales.revertirPago',
      () => ref.read(revertirPagoCostoServicioEventualUseCaseProvider).ejecutar(
            costoId: costoId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      RevertirPagoCostoServicioEventualErrorInesperado.new,
    );
  };
});

typedef RegistrarDocumentoFiscalEventualAutorizado
    = Future<RegistrarDocumentoFiscalEventualResultado> Function({
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
});

final registrarDocumentoFiscalEventualAutorizadoProvider =
    Provider<RegistrarDocumentoFiscalEventualAutorizado>((ref) {
  return ({
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
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'serviciosEventuales.facturar',
      () => ref.read(registrarDocumentoFiscalEventualUseCaseProvider).ejecutar(
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
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      RegistrarDocumentoFiscalEventualErrorInesperado.new,
    );
  };
});

typedef CorregirDocumentoFiscalEventualAutorizado
    = Future<CorregirDocumentoFiscalEventualResultado> Function({
  required String documentoId,
  String? folio,
  String? uuid,
  DateTime? fechaEmision,
  MetodoPagoCobro? metodo,
  String? observaciones,
  required String motivo,
});

final corregirDocumentoFiscalEventualAutorizadoProvider =
    Provider<CorregirDocumentoFiscalEventualAutorizado>((ref) {
  return ({
    required String documentoId,
    String? folio,
    String? uuid,
    DateTime? fechaEmision,
    MetodoPagoCobro? metodo,
    String? observaciones,
    required String motivo,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'serviciosEventuales.facturar',
      () => ref.read(corregirDocumentoFiscalEventualUseCaseProvider).ejecutar(
            documentoId: documentoId,
            folio: folio,
            uuid: uuid,
            fechaEmision: fechaEmision,
            metodo: metodo,
            observaciones: observaciones,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      CorregirDocumentoFiscalEventualErrorInesperado.new,
    );
  };
});

typedef CancelarDocumentoFiscalEventualAutorizado
    = Future<CancelarDocumentoFiscalEventualResultado> Function({
  required String documentoId,
  required String motivo,
});

final cancelarDocumentoFiscalEventualAutorizadoProvider =
    Provider<CancelarDocumentoFiscalEventualAutorizado>((ref) {
  return ({required String documentoId, required String motivo}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      // Cancelar un CFDI es una facultad fiscal, no de cobranza: va con
      // `facturar`, no con `cancelar` (que anula el evento comercial).
      'serviciosEventuales.facturar',
      () => ref.read(cancelarDocumentoFiscalEventualUseCaseProvider).ejecutar(
            documentoId: documentoId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      CancelarDocumentoFiscalEventualErrorInesperado.new,
    );
  };
});

typedef RegistrarCobroServicioEventualAutorizado
    = Future<RegistrarCobroServicioEventualResultado> Function({
  required String servicioEventualId,
  required int monto,
  required DateTime fechaPago,
  required String formaPago,
  String? cuentaFinancieraId,
  String? referencia,
  String? observaciones,
});

final registrarCobroServicioEventualAutorizadoProvider =
    Provider<RegistrarCobroServicioEventualAutorizado>((ref) {
  return ({
    required String servicioEventualId,
    required int monto,
    required DateTime fechaPago,
    required String formaPago,
    String? cuentaFinancieraId,
    String? referencia,
    String? observaciones,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'serviciosEventuales.cobrar',
      () => ref.read(registrarCobroServicioEventualUseCaseProvider).ejecutar(
            servicioEventualId: servicioEventualId,
            monto: monto,
            fechaPago: fechaPago,
            formaPago: formaPago,
            cuentaFinancieraId: cuentaFinancieraId,
            referencia: referencia,
            observaciones: observaciones,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      RegistrarCobroServicioEventualErrorInesperado.new,
    );
  };
});

// --- Eliminación física extraordinaria (Etapa 11D) ---
//
// Facultad exclusiva del Usuario Maestro — `exigirMaestro` nunca
// consulta `PermisoUsuario`, así que ningún permiso dinámico puede
// otorgarla.

final eliminarServicioEventualFisicamenteUseCaseProvider =
    Provider<EliminarServicioEventualFisicamenteUseCase>((ref) {
  return EliminarServicioEventualFisicamenteUseCase(ref.watch(servicioEventualRepositoryProvider));
});

typedef EliminarServicioEventualFisicamenteAutorizado
    = Future<EliminarServicioEventualFisicamenteResultado> Function({
  required String servicioEventualId,
  required String motivo,
});

final eliminarServicioEventualFisicamenteAutorizadoProvider =
    Provider<EliminarServicioEventualFisicamenteAutorizado>((ref) {
  return ({required String servicioEventualId, required String motivo}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(eliminarServicioEventualFisicamenteUseCaseProvider).ejecutar(
            servicioEventualId: servicioEventualId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      EliminarServicioEventualFisicamenteErrorInesperado.new,
    );
  };
});
