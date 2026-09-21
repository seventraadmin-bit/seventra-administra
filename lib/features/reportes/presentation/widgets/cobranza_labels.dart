/// Traducción código→texto de la Etapa B — cartera, pagos y deuda.
///
/// Mismo criterio que `analitica_labels.dart`: el dominio entrega
/// enums estables y aquí se decide cómo se llaman en pantalla, una sola
/// vez para pantalla, tabla y exportación.
library;

import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';

import '../../domain/analitica/obtener_analisis_cobranza_usecase.dart';
import '../../domain/analitica/obtener_analisis_deuda_usecase.dart';
import '../../domain/analitica/obtener_analisis_pagos_usecase.dart';

String etiquetaEstatusCuenta(AppLocalizations l10n, String estatus) {
  return switch (EstatusCuentaPorCobrar.values.where((e) => e.name == estatus).firstOrNull) {
    EstatusCuentaPorCobrar.pendiente => l10n.reportesCxcEstatusPendiente,
    EstatusCuentaPorCobrar.parcial => l10n.reportesCxcEstatusParcial,
    EstatusCuentaPorCobrar.pagada => l10n.reportesCxcEstatusPagada,
    EstatusCuentaPorCobrar.cancelada => l10n.reportesCxcEstatusCancelada,
    // Un estatus desconocido se muestra crudo en vez de romper: es dato
    // real que alguien tiene que ver para corregirlo.
    null => estatus,
  };
}

RisegStatusTone tonoEstatusCuenta(String estatus) {
  return switch (EstatusCuentaPorCobrar.values.where((e) => e.name == estatus).firstOrNull) {
    EstatusCuentaPorCobrar.pendiente => RisegStatusTone.info,
    EstatusCuentaPorCobrar.parcial => RisegStatusTone.warning,
    EstatusCuentaPorCobrar.pagada => RisegStatusTone.success,
    EstatusCuentaPorCobrar.cancelada => RisegStatusTone.neutral,
    null => RisegStatusTone.neutral,
  };
}

String etiquetaHorizonteCobranza(AppLocalizations l10n, HorizonteCobranza horizonte) => switch (horizonte) {
      HorizonteCobranza.proximos7 => l10n.reportesCxcEsperada7,
      HorizonteCobranza.dias8a15 => l10n.reportesCxcEsperada8a15,
      HorizonteCobranza.dias16a30 => l10n.reportesCxcEsperada16a30,
      HorizonteCobranza.posterior => l10n.reportesCxcEsperadaPosterior,
    };

/// Mientras más lejos está el cobro, menos inmediato es el alivio. No
/// es una alarma: es una escala de proximidad.
RisegStatusTone tonoHorizonteCobranza(HorizonteCobranza horizonte) => switch (horizonte) {
      HorizonteCobranza.proximos7 => RisegStatusTone.success,
      HorizonteCobranza.dias8a15 => RisegStatusTone.info,
      HorizonteCobranza.dias16a30 => RisegStatusTone.warning,
      HorizonteCobranza.posterior => RisegStatusTone.neutral,
    };

String etiquetaEstadoComplemento(AppLocalizations l10n, EstadoComplementoPago estado) => switch (estado) {
      EstadoComplementoPago.noAplica => l10n.reportesPagosComplementoNoAplica,
      EstadoComplementoPago.pendiente => l10n.complementosEstadoPendiente,
      EstadoComplementoPago.registrado => l10n.complementoPagoEstatusRegistrado,
    };

RisegStatusTone tonoEstadoComplemento(EstadoComplementoPago estado) => switch (estado) {
      EstadoComplementoPago.noAplica => RisegStatusTone.neutral,
      // Una obligación fiscal sin cumplir es un riesgo real, no un
      // pendiente administrativo cualquiera.
      EstadoComplementoPago.pendiente => RisegStatusTone.error,
      EstadoComplementoPago.registrado => RisegStatusTone.success,
    };

String etiquetaTipoMovimientoDeuda(AppLocalizations l10n, TipoMovimientoDeuda tipo) => switch (tipo) {
      TipoMovimientoDeuda.altaInicial => l10n.reportesDeudaTipoAltaInicial,
      TipoMovimientoDeuda.cargoCompra => l10n.reportesDeudaTipoCargoCompra,
      TipoMovimientoDeuda.pago => l10n.reportesDeudaTipoPago,
      TipoMovimientoDeuda.ajustePositivo => l10n.reportesDeudaTipoAjustePositivo,
      TipoMovimientoDeuda.ajusteNegativo => l10n.reportesDeudaTipoAjusteNegativo,
      TipoMovimientoDeuda.cancelacion => l10n.reportesDeudaTipoCancelacion,
      TipoMovimientoDeuda.reversionPago => l10n.reportesDeudaTipoReversionPago,
    };

String etiquetaOrigenMovimientoDeuda(AppLocalizations l10n, OrigenMovimientoDeuda origen) => switch (origen) {
      OrigenMovimientoDeuda.compra => l10n.reportesDeudaOrigenCompra,
      OrigenMovimientoDeuda.tiempoExtra => l10n.reportesDeudaOrigenTiempoExtra,
      OrigenMovimientoDeuda.costoAdicionalTiempoExtra => l10n.reportesDeudaOrigenCostoAdicional,
      OrigenMovimientoDeuda.vehiculo => l10n.reportesDeudaOrigenVehiculo,
      OrigenMovimientoDeuda.egreso => l10n.reportesDeudaOrigenEgreso,
      OrigenMovimientoDeuda.pago => l10n.reportesDeudaOrigenPago,
      OrigenMovimientoDeuda.apertura => l10n.reportesDeudaOrigenApertura,
      OrigenMovimientoDeuda.sinOrigen => l10n.reportesDeudaOrigenSinOrigen,
    };

/// Umbrales de utilización de crédito — **decisión de UX, no regla de
/// negocio**.
///
/// Sólo tiñen la celda; nada en el dominio los lee, ningún cálculo
/// depende de ellos y ninguna operación se bloquea por cruzarlos. Se
/// documentan aquí para que quede claro que son convención visual y
/// pueden moverse sin tocar ninguna regla financiera.
const double utilizacionAdvertencia = 0.70;
const double utilizacionCritica = 0.90;

RisegStatusTone tonoUtilizacionCredito(double? utilizacion) {
  if (utilizacion == null) return RisegStatusTone.neutral;
  if (utilizacion >= utilizacionCritica) return RisegStatusTone.error;
  if (utilizacion >= utilizacionAdvertencia) return RisegStatusTone.warning;
  return RisegStatusTone.success;
}
