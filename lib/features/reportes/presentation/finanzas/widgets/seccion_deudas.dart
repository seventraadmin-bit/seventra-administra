import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;

import '../../../domain/analitica/obtener_analisis_deuda_usecase.dart';
import '../../widgets/cobranza_labels.dart';
import '../../widgets/paneles_analiticos.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Sección Deudas y TDC.
///
/// Mezcla deliberada de dos universos, siempre etiquetados: los saldos y
/// la utilización de crédito son **a la fecha**; los cargos, pagos y
/// ajustes son **del periodo**.
class SeccionDeudas extends StatelessWidget {
  const SeccionDeudas({required this.deuda, super.key});

  final AnalisisDeuda deuda;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    if (deuda.deudas.isEmpty) {
      return RisegEmptyState(
        icon: Icons.credit_card_off_outlined,
        title: l10n.reportesSinDatosTitulo,
        message: l10n.reportesDeudaVacia,
      );
    }

    final utilizacion = deuda.utilizacionGlobal;
    final altoFila = alturaDeFila([
      RisegCompositionChart.alturaPara(deuda.tarjetas.isEmpty ? 1 : 2),
      alturaCifraDestacada + alturaDatosCompactos(2),
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegKpiGrid(
          children: [
            RisegStatCard(
              label: l10n.reportesDeudaTotal,
              value: formatoCentavosPago(deuda.saldoTotal),
              icon: Icons.account_balance_outlined,
              delta: l10n.reportesAvisoALaFecha,
              deltaTone: RisegStatusTone.neutral,
            ),
            RisegStatCard(
              label: l10n.reportesDeudaSaldoTarjetas,
              value: formatoCentavosPago(deuda.saldoTarjetas),
              icon: Icons.credit_card_outlined,
            ),
            RisegStatCard(
              label: l10n.reportesDeudaOtras,
              value: formatoCentavosPago(deuda.saldoOtrasDeudas),
              icon: Icons.request_quote_outlined,
            ),
            RisegStatCard(
              label: l10n.reportesDeudaCreditoDisponible,
              // Sin ninguna tarjeta, "$0 disponible" sería falso: no es
              // que no haya crédito, es que no hay tarjetas.
              value: deuda.hayTarjetas ? formatoCentavosPago(deuda.creditoDisponible) : '—',
              icon: Icons.credit_score_outlined,
              delta: deuda.hayTarjetas ? null : l10n.reportesDeudaSinTarjetas,
              deltaTone: deuda.hayTarjetas ? null : RisegStatusTone.neutral,
            ),
            RisegStatCard(
              label: l10n.reportesDeudaCargosPeriodo,
              value: formatoCentavosPago(deuda.cargosDelPeriodo),
              icon: Icons.add_card_outlined,
              delta: l10n.reportesAvisoEnElPeriodo,
              deltaTone: RisegStatusTone.neutral,
            ),
            RisegStatCard(
              label: l10n.reportesDeudaPagosPeriodo,
              value: formatoCentavosPago(deuda.pagosDelPeriodo),
              icon: Icons.price_check,
              delta: l10n.reportesAvisoEnElPeriodo,
              deltaTone: RisegStatusTone.neutral,
            ),
            RisegStatCard(
              label: l10n.reportesDeudaAjustesPeriodo,
              value: formatoCentavosPago(deuda.ajustesDelPeriodo),
              icon: Icons.tune,
              deltaTone: deuda.ajustesDelPeriodo != 0 ? RisegStatusTone.warning : null,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        FilaPaneles(
          paneles: [
            PanelAnalitico(minAncho: 300, child: _Composicion(deuda: deuda, altura: altoFila)),
            PanelAnalitico(minAncho: 260, child: _Utilizacion(deuda: deuda, altura: altoFila, utilizacion: utilizacion)),
          ],
        ),
        if (deuda.tarjetas.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(l10n.reportesDeudaTarjetasTitulo, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppSpacing.xxs),
          Text(l10n.reportesDeudaTarjetasPregunta, style: AppTypography.caption.copyWith(color: colors.textMuted)),
          const SizedBox(height: AppSpacing.sm),
          _TablaTarjetas(tarjetas: deuda.tarjetas),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(l10n.reportesDeudaMovimientosTitulo, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
        const SizedBox(height: AppSpacing.sm),
        _TablaMovimientos(movimientos: deuda.movimientos),
      ],
    );
  }
}

class _Composicion extends StatelessWidget {
  const _Composicion({required this.deuda, required this.altura});

  final AnalisisDeuda deuda;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return RisegChartCard(
      title: l10n.reportesDeudaComposicionTitulo,
      subtitle: l10n.reportesDeudaComposicionPregunta,
      height: altura,
      vacio: deuda.saldoTotal == 0,
      mensajeVacio: l10n.reportesDeudaVacia,
      iconoVacio: Icons.account_balance_outlined,
      trailing: Text(
        formatoCentavosPago(deuda.saldoTotal),
        style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
      ),
      child: RisegCompositionChart(
        total: deuda.saldoTotal,
        formatoValor: formatoCentavosPago,
        items: [
          if (deuda.saldoTarjetas != 0)
            RisegComposicionItem(
              label: l10n.reportesDeudaSaldoTarjetas,
              valor: deuda.saldoTarjetas,
              color: context.colorCategorico(0),
            ),
          if (deuda.saldoOtrasDeudas != 0)
            RisegComposicionItem(
              label: l10n.reportesDeudaOtras,
              valor: deuda.saldoOtrasDeudas,
              color: context.colorCategorico(1),
            ),
        ],
      ),
    );
  }
}

class _Utilizacion extends StatelessWidget {
  const _Utilizacion({required this.deuda, required this.altura, required this.utilizacion});

  final AnalisisDeuda deuda;
  final double altura;
  final double? utilizacion;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return RisegChartCard(
      title: l10n.reportesDeudaUtilizacion,
      subtitle: l10n.reportesAvisoALaFecha,
      height: altura,
      // Sin límite capturado en ninguna tarjeta no hay utilización que
      // calcular — y un 0 % diría que no se está usando el crédito.
      vacio: utilizacion == null,
      mensajeVacio: deuda.hayTarjetas ? l10n.reportesDeudaSinLimite : l10n.reportesDeudaSinTarjetas,
      iconoVacio: Icons.credit_card_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${((utilizacion ?? 0) * 100).toStringAsFixed(0)} %',
            style: AppTypography.heading1.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          RisegProgressBar(
            porcentaje: (utilizacion ?? 0) * 100,
            tone: tonoUtilizacionCredito(utilizacion),
          ),
          const SizedBox(height: AppSpacing.md),
          DatoCompacto(
            etiqueta: l10n.reportesDeudaColumnaLimite,
            valor: formatoCentavosPago(deuda.limiteTotal),
          ),
          DatoCompacto(
            etiqueta: l10n.reportesDeudaCreditoDisponible,
            valor: formatoCentavosPago(deuda.creditoDisponible),
          ),
        ],
      ),
    );
  }
}

class _TablaTarjetas extends StatelessWidget {
  const _TablaTarjetas({required this.tarjetas});

  final List<TarjetaProyectada> tarjetas;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    Color tono(RisegStatusTone t) => switch (t) {
          RisegStatusTone.success => colors.success,
          RisegStatusTone.warning => colors.warning,
          RisegStatusTone.error => colors.error,
          RisegStatusTone.info => colors.info,
          RisegStatusTone.neutral => colors.neutralText,
        };

    return RisegTableBase<TarjetaProyectada>(
      rows: tarjetas,
      emptyState: RisegEmptyState(title: l10n.reportesSinDatosTitulo, message: l10n.reportesDeudaSinTarjetas),
      onRowTap: (t) => context.go('/finanzas/deudas/${t.deuda.id}'),
      columns: [
        RisegColumn<TarjetaProyectada>(
          label: l10n.reportesDeudaColumnaTarjeta,
          width: 200,
          cellBuilder: (t) => Text(
            t.deuda.tarjetaUltimosDigitos == null
                ? t.deuda.nombre
                : '${t.deuda.nombre} ····${t.deuda.tarjetaUltimosDigitos}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
        RisegColumn<TarjetaProyectada>(
          label: l10n.reportesDeudaColumnaLimite,
          width: 130,
          alignment: TextAlign.right,
          cellBuilder: (t) => Text(t.limite == null ? '—' : formatoCentavosPago(t.limite!)),
        ),
        RisegColumn<TarjetaProyectada>(
          label: l10n.reportesDeudaColumnaSaldo,
          width: 130,
          alignment: TextAlign.right,
          cellBuilder: (t) => Text(formatoCentavosPago(t.saldo)),
        ),
        RisegColumn<TarjetaProyectada>(
          label: l10n.reportesDeudaColumnaDisponible,
          width: 130,
          alignment: TextAlign.right,
          cellBuilder: (t) => Text(t.disponible == null ? '—' : formatoCentavosPago(t.disponible!)),
        ),
        RisegColumn<TarjetaProyectada>(
          label: l10n.reportesDeudaColumnaUtilizacion,
          width: 110,
          alignment: TextAlign.right,
          cellBuilder: (t) => Text(
            t.utilizacion == null ? '—' : '${(t.utilizacion! * 100).toStringAsFixed(0)} %',
            style: AppTypography.bodyStrong.copyWith(color: tono(tonoUtilizacionCredito(t.utilizacion))),
          ),
        ),
        RisegColumn<TarjetaProyectada>(
          label: l10n.reportesDeudaColumnaCorte,
          width: 110,
          cellBuilder: (t) => Text(t.proximoCorte == null ? '—' : _formatoFecha.format(t.proximoCorte!)),
        ),
        RisegColumn<TarjetaProyectada>(
          label: l10n.reportesDeudaColumnaLimitePago,
          width: 130,
          cellBuilder: (t) => Text(t.proximaFechaLimite == null ? '—' : _formatoFecha.format(t.proximaFechaLimite!)),
        ),
      ],
    );
  }
}

class _TablaMovimientos extends StatelessWidget {
  const _TablaMovimientos({required this.movimientos});

  final List<MovimientoDeudaProyectado> movimientos;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return RisegTableBase<MovimientoDeudaProyectado>(
      rows: movimientos,
      emptyState: RisegEmptyState(
        icon: Icons.receipt_long_outlined,
        title: l10n.reportesSinDatosTitulo,
        message: l10n.reportesDeudaMovimientosVacia,
      ),
      onRowTap: (m) => context.go('/finanzas/deudas/${m.deudaId}'),
      columns: [
        RisegColumn<MovimientoDeudaProyectado>(
          label: l10n.reportesDeudaColumnaFecha,
          width: 110,
          cellBuilder: (m) => Text(_formatoFecha.format(m.fecha)),
        ),
        RisegColumn<MovimientoDeudaProyectado>(
          label: l10n.reportesDeudaColumnaDeuda,
          width: 180,
          cellBuilder: (m) => Text(m.deudaNombre, overflow: TextOverflow.ellipsis),
        ),
        RisegColumn<MovimientoDeudaProyectado>(
          label: l10n.reportesDeudaColumnaTipo,
          width: 140,
          cellBuilder: (m) => Text(etiquetaTipoMovimientoDeuda(l10n, m.tipo)),
        ),
        RisegColumn<MovimientoDeudaProyectado>(
          label: l10n.reportesDeudaColumnaOrigen,
          width: 180,
          // Resuelto por FK, nunca por el texto de la observación.
          cellBuilder: (m) => Text(etiquetaOrigenMovimientoDeuda(l10n, m.origen), overflow: TextOverflow.ellipsis),
        ),
        RisegColumn<MovimientoDeudaProyectado>(
          label: l10n.reportesDeudaColumnaEfecto,
          width: 140,
          alignment: TextAlign.right,
          cellBuilder: (m) => Text(
            formatoCentavosPago(m.efectoEnSaldo),
            style: AppTypography.bodyStrong.copyWith(
              color: m.efectoEnSaldo >= 0 ? colors.textPrimary : colors.success,
            ),
          ),
        ),
      ],
    );
  }
}
