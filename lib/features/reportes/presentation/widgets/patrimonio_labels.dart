/// Traducción código→texto de Patrimonio y bajas.
///
/// Mismo criterio que el resto de Reportes: el dominio entrega enums
/// estables y aquí se decide cómo se llaman en pantalla, una sola vez
/// para tabla, gráfica y exportación.
library;

import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/personal/data/tables/conciliacion_baja_table.dart';

import '../../domain/analitica/obtener_analisis_patrimonio_usecase.dart';

/// Cómo se nombra el Servicio histórico de una baja.
///
/// Los tres resultados tienen texto propio: "no se pudo resolver" y "el
/// dato está roto" NO son lo mismo, y ninguno se muestra como celda
/// vacía.
String etiquetaServicioHistorico(AppLocalizations l10n, ServicioHistorico servicio) => switch (servicio.estado) {
      EstadoServicioHistorico.resuelto => servicio.nombre!,
      EstadoServicioHistorico.sinAsignacion => l10n.reportesPatrimonioServicioSinResolver,
      EstadoServicioHistorico.inconsistente => l10n.reportesPatrimonioServicioInconsistente,
    };

/// Mismo criterio para un renglón del ranking por servicio.
String etiquetaServicioRanking(AppLocalizations l10n, ProblemaPorServicio fila) => switch (fila.estado) {
      EstadoServicioHistorico.resuelto => fila.nombre!,
      EstadoServicioHistorico.sinAsignacion => l10n.reportesPatrimonioServicioSinResolver,
      EstadoServicioHistorico.inconsistente => l10n.reportesPatrimonioServicioInconsistente,
    };

/// El tono avisa que hay un dato que arreglar, no un problema
/// patrimonial: una inconsistencia de asignación es un pendiente de
/// captura en Personal.
RisegStatusTone tonoServicioHistorico(EstadoServicioHistorico estado) => switch (estado) {
      EstadoServicioHistorico.resuelto => RisegStatusTone.neutral,
      EstadoServicioHistorico.sinAsignacion => RisegStatusTone.neutral,
      EstadoServicioHistorico.inconsistente => RisegStatusTone.warning,
    };

String etiquetaTipoBien(AppLocalizations l10n, TipoBienConciliado tipo) => switch (tipo) {
      TipoBienConciliado.inventario => l10n.reportesPatrimonioTipoInventario,
      TipoBienConciliado.vehiculo => l10n.reportesPatrimonioTipoVehiculo,
    };

String etiquetaResolucion(AppLocalizations l10n, ResolucionResguardoBaja resolucion) => switch (resolucion) {
      ResolucionResguardoBaja.devuelto => l10n.reportesPatrimonioResolucionDevuelto,
      ResolucionResguardoBaja.noEntregado => l10n.reportesPatrimonioResolucionNoEntregado,
      ResolucionResguardoBaja.transferido => l10n.reportesPatrimonioResolucionTransferido,
      ResolucionResguardoBaja.perdido => l10n.reportesPatrimonioResolucionPerdido,
      ResolucionResguardoBaja.desecho => l10n.reportesPatrimonioResolucionDesecho,
    };

/// El tono comunica la situación patrimonial, no un juicio sobre la
/// persona: lo devuelto está resuelto, lo no entregado sigue abierto y
/// lo perdido es una pérdida real.
RisegStatusTone tonoResolucion(ResolucionResguardoBaja resolucion) => switch (resolucion) {
      ResolucionResguardoBaja.devuelto => RisegStatusTone.success,
      ResolucionResguardoBaja.desecho => RisegStatusTone.info,
      ResolucionResguardoBaja.transferido => RisegStatusTone.neutral,
      ResolucionResguardoBaja.noEntregado => RisegStatusTone.warning,
      ResolucionResguardoBaja.perdido => RisegStatusTone.error,
    };

String etiquetaMotivoNoEntrega(AppLocalizations l10n, MotivoNoEntregaResguardo motivo) => switch (motivo) {
      MotivoNoEntregaResguardo.abandonoServicio => l10n.reportesPatrimonioMotivoAbandono,
      MotivoNoEntregaResguardo.noLocalizado => l10n.reportesPatrimonioMotivoNoLocalizado,
      MotivoNoEntregaResguardo.seNegoAEntregar => l10n.reportesPatrimonioMotivoSeNego,
      MotivoNoEntregaResguardo.entregaAcordadaPosteriormente => l10n.reportesPatrimonioMotivoEntregaAcordada,
      MotivoNoEntregaResguardo.perdida => l10n.reportesPatrimonioMotivoPerdida,
      MotivoNoEntregaResguardo.robo => l10n.reportesPatrimonioMotivoRobo,
      MotivoNoEntregaResguardo.noSeSolicitoDevolucion => l10n.reportesPatrimonioMotivoNoSeSolicito,
      MotivoNoEntregaResguardo.autorizadoAConservarlo => l10n.reportesPatrimonioMotivoAutorizadoConservar,
      MotivoNoEntregaResguardo.otro => l10n.reportesPatrimonioMotivoOtro,
    };
