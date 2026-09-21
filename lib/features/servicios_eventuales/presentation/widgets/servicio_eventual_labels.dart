import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../../data/tables/servicio_eventual_table.dart';

String servicioEventualEstatusLabel(AppLocalizations l10n, String estatus) {
  return switch (EstatusServicioEventual.values.where((e) => e.name == estatus).firstOrNull) {
    EstatusServicioEventual.programado => l10n.serviciosEventualesEstatusProgramado,
    EstatusServicioEventual.finalizado => l10n.serviciosEventualesEstatusFinalizado,
    EstatusServicioEventual.cancelado => l10n.serviciosEventualesEstatusCancelado,
    null => estatus,
  };
}

/// `finalizado` es `success` porque el evento ocurrió; `programado` es
/// neutro, no una advertencia: que algo esté por pasar no es un
/// problema.
RisegStatusTone servicioEventualEstatusTono(String estatus) {
  return switch (EstatusServicioEventual.values.where((e) => e.name == estatus).firstOrNull) {
    EstatusServicioEventual.programado => RisegStatusTone.info,
    EstatusServicioEventual.finalizado => RisegStatusTone.success,
    EstatusServicioEventual.cancelado => RisegStatusTone.neutral,
    null => RisegStatusTone.neutral,
  };
}

/// Cómo se le dice al usuario cada hecho del historial.
///
/// El valor persistido (`costoAgregado`, `cuentaPorCobrarCreada`, ...)
/// es un identificador técnico y nunca debe llegar a la pantalla; la
/// prueba manual lo encontró crudo en el expediente. Éste es el ÚNICO
/// mapper: lo usan tanto el historial del eventual como la Auditoría
/// central, para que el mismo hecho no se lea de dos maneras.
///
/// Un tipo desconocido cae de vuelta al valor crudo a propósito: es
/// preferible una etiqueta fea a esconder un evento que sí ocurrió.
String servicioEventualEventoLabel(AppLocalizations l10n, String tipoEvento) {
  return switch (TipoEventoServicioEventual.values.where((e) => e.name == tipoEvento).firstOrNull) {
    TipoEventoServicioEventual.creado => l10n.servicioEventualEventoCreado,
    TipoEventoServicioEventual.corregido => l10n.servicioEventualEventoCorregido,
    TipoEventoServicioEventual.finalizado => l10n.servicioEventualEventoFinalizado,
    TipoEventoServicioEventual.cancelado => l10n.servicioEventualEventoCancelado,
    TipoEventoServicioEventual.participanteAgregado => l10n.servicioEventualEventoParticipanteAgregado,
    TipoEventoServicioEventual.participanteCorregido => l10n.servicioEventualEventoParticipanteCorregido,
    TipoEventoServicioEventual.participanteRetirado => l10n.servicioEventualEventoParticipanteRetirado,
    TipoEventoServicioEventual.coberturaAgregada => l10n.servicioEventualEventoCoberturaAgregada,
    TipoEventoServicioEventual.coberturaCorregida => l10n.servicioEventualEventoCoberturaCorregida,
    TipoEventoServicioEventual.coberturaCancelada => l10n.servicioEventualEventoCoberturaCancelada,
    TipoEventoServicioEventual.coberturaPagada => l10n.servicioEventualEventoCoberturaPagada,
    TipoEventoServicioEventual.coberturaPagoRevertido => l10n.servicioEventualEventoCoberturaPagoRevertido,
    TipoEventoServicioEventual.costoAgregado => l10n.servicioEventualEventoCostoAgregado,
    TipoEventoServicioEventual.costoCorregido => l10n.servicioEventualEventoCostoCorregido,
    TipoEventoServicioEventual.costoCancelado => l10n.servicioEventualEventoCostoCancelado,
    TipoEventoServicioEventual.costoPagado => l10n.servicioEventualEventoCostoPagado,
    TipoEventoServicioEventual.costoPagoRevertido => l10n.servicioEventualEventoCostoPagoRevertido,
    TipoEventoServicioEventual.cuentaPorCobrarCreada => l10n.servicioEventualEventoCuentaPorCobrarCreada,
    TipoEventoServicioEventual.cuentaPorCobrarSincronizada =>
      l10n.servicioEventualEventoCuentaPorCobrarSincronizada,
    TipoEventoServicioEventual.documentoFiscalRegistrado =>
      l10n.servicioEventualEventoDocumentoFiscalRegistrado,
    TipoEventoServicioEventual.documentoFiscalCorregido => l10n.servicioEventualEventoDocumentoFiscalCorregido,
    TipoEventoServicioEventual.documentoFiscalCancelado => l10n.servicioEventualEventoDocumentoFiscalCancelado,
    TipoEventoServicioEventual.ventaAnulada => l10n.servicioEventualEventoVentaAnulada,
    TipoEventoServicioEventual.cobroRevertido => l10n.servicioEventualEventoCobroRevertido,
    null => tipoEvento,
  };
}

String ejecucionServicioEventualLabel(AppLocalizations l10n, String estatus) {
  return switch (EstatusEjecucionServicioEventual.values.where((e) => e.name == estatus).firstOrNull) {
    EstatusEjecucionServicioEventual.programada => l10n.servicioEventualEjecucionProgramada,
    EstatusEjecucionServicioEventual.pagada => l10n.servicioEventualEjecucionPagada,
    EstatusEjecucionServicioEventual.cancelada => l10n.servicioEventualEjecucionCancelada,
    null => estatus,
  };
}

/// Mismo estado persistido, otra palabra.
///
/// Para una cobertura, "programada" es exacto: un turno se programa.
/// Para el estacionamiento o los alimentos del evento, "programado" es
/// absurdo — eso es un gasto **pendiente de pagar**. El enum no cambia
/// (ni la base ni las reglas), sólo cómo se le dice al usuario.
String ejecucionCostoServicioEventualLabel(AppLocalizations l10n, String estatus) {
  return switch (EstatusEjecucionServicioEventual.values.where((e) => e.name == estatus).firstOrNull) {
    EstatusEjecucionServicioEventual.programada => l10n.servicioEventualEjecucionPendiente,
    EstatusEjecucionServicioEventual.pagada => l10n.servicioEventualEjecucionPagada,
    EstatusEjecucionServicioEventual.cancelada => l10n.servicioEventualEjecucionCancelada,
    null => estatus,
  };
}

RisegStatusTone ejecucionServicioEventualTono(String estatus) {
  return switch (EstatusEjecucionServicioEventual.values.where((e) => e.name == estatus).firstOrNull) {
    EstatusEjecucionServicioEventual.programada => RisegStatusTone.info,
    EstatusEjecucionServicioEventual.pagada => RisegStatusTone.success,
    EstatusEjecucionServicioEventual.cancelada => RisegStatusTone.neutral,
    null => RisegStatusTone.neutral,
  };
}

/// `510` → `08:30`. Los minutos desde medianoche se guardan como
/// entero, nunca como texto: así un turno se puede ordenar y medir.
String horaDesdeMinutos(int minutos) {
  final hora = (minutos ~/ 60).toString().padLeft(2, '0');
  final minuto = (minutos % 60).toString().padLeft(2, '0');
  return '$hora:$minuto';
}

/// `08:30 - 20:30`. Cuando el turno cruza la medianoche lo dice en
/// palabras: leer `20:00 - 06:00` sin más deja la duda de si son 10
/// horas o 14.
String rangoHorarioServicioEventual(
  AppLocalizations l10n, {
  required int horaInicioMinutos,
  required int horaFinMinutos,
}) {
  final base = '${horaDesdeMinutos(horaInicioMinutos)} - ${horaDesdeMinutos(horaFinMinutos)}';
  return horaFinMinutos <= horaInicioMinutos ? '$base (${l10n.servicioEventualHorarioCruzaMedianoche})' : base;
}

/// `'08:30'` → minutos desde medianoche. `null` si el texto no es una
/// hora válida — el llamador decide qué hacer, nunca se adivina.
int? minutosDesdeTextoHora(String texto) {
  final partes = texto.trim().split(':');
  if (partes.length != 2) return null;
  final hora = int.tryParse(partes[0]);
  final minuto = int.tryParse(partes[1]);
  if (hora == null || minuto == null) return null;
  if (hora < 0 || hora > 23 || minuto < 0 || minuto > 59) return null;
  return hora * 60 + minuto;
}
