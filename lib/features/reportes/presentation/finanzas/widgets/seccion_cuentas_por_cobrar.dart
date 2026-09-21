import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;

import '../../../domain/analitica/obtener_analisis_cobranza_usecase.dart';
import '../../widgets/analitica_labels.dart';
import '../../widgets/cobranza_labels.dart';
import '../../widgets/paneles_analiticos.dart';
import '../reportes_finanzas_controller.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Sección Cuentas por cobrar.
///
/// Todo lo que se ve aquí es **a la fecha de hoy**, no del periodo
/// seleccionado arriba — y la pantalla lo dice, en vez de dejar que el
/// usuario asuma que el rango recorta la cartera.
class SeccionCuentasPorCobrar extends ConsumerWidget {
  const SeccionCuentasPorCobrar({required this.cobranza, super.key});

  final AnalisisCobranza cobranza;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final controller = ref.read(reportesFinanzasControllerProvider.notifier);
    final filtro = ref.watch(reportesFinanzasControllerProvider).filtroCobranza;

    final cubetasConSaldo = cobranza.aging.where((c) => c.importe != 0).toList();
    final altoFila = alturaDeFila([
      RisegAgingBars.alturaPara(cubetasConSaldo.length),
      RisegCompositionChart.alturaPara(cobranza.concentracion.length),
      RisegAgingBars.alturaPara(cobranza.cobranzaEsperada.where((t) => t.importe != 0).length, conDetalle: false),
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AvisoUniverso(texto: l10n.reportesAvisoALaFecha),
        const SizedBox(height: AppSpacing.sm),
        _Kpis(cobranza: cobranza),
        const SizedBox(height: AppSpacing.md),
        FilaPaneles(
          paneles: [
            PanelAnalitico(minAncho: 300, child: _Aging(cobranza: cobranza, altura: altoFila)),
            PanelAnalitico(minAncho: 300, child: _Concentracion(cobranza: cobranza, altura: altoFila)),
            PanelAnalitico(minAncho: 280, child: _CobranzaEsperada(cobranza: cobranza, altura: altoFila)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _FiltrosCartera(filtro: filtro, onCambiar: controller.cambiarFiltroCobranza),
        const SizedBox(height: AppSpacing.sm),
        Text(l10n.reportesCxcDetalleTitulo, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
        const SizedBox(height: AppSpacing.sm),
        _TablaCuentas(cuentas: cobranza.cuentas),
      ],
    );
  }
}

/// Cartel que dice a qué universo temporal pertenece lo que sigue.
class _AvisoUniverso extends StatelessWidget {
  const _AvisoUniverso({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Icon(Icons.schedule, size: AppSizes.iconSm, color: colors.textMuted),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(
            texto,
            style: AppTypography.caption.copyWith(color: colors.textMuted),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.cobranza});

  final AnalisisCobranza cobranza;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final porcentaje = cobranza.porcentajeVencido;
    final atraso = cobranza.diasAtrasoPromedio;

    return RisegKpiGrid(
      children: [
        RisegStatCard(
          label: l10n.reportesCxcSaldoPendiente,
          value: formatoCentavosPago(cobranza.saldoPendiente),
          icon: Icons.receipt_long_outlined,
        ),
        RisegStatCard(
          label: l10n.reportesCxcSaldoVencido,
          value: formatoCentavosPago(cobranza.saldoVencido),
          icon: Icons.schedule,
          deltaTone: cobranza.saldoVencido > 0 ? RisegStatusTone.error : RisegStatusTone.success,
        ),
        RisegStatCard(
          label: l10n.reportesCxcPorcentajeVencido,
          // Sin saldo no hay porcentaje: 0 % diría "nada vencido"
          // cuando en realidad no hay base.
          value: porcentaje == null ? '—' : '${(porcentaje * 100).toStringAsFixed(1)} %',
          icon: Icons.percent,
          deltaTone: porcentaje == null
              ? RisegStatusTone.neutral
              : (porcentaje > 0 ? RisegStatusTone.warning : RisegStatusTone.success),
        ),
        RisegStatCard(
          label: l10n.reportesCxcAlCorriente,
          value: formatoCentavosPago(cobranza.saldoAlCorriente),
          icon: Icons.verified_outlined,
        ),
        RisegStatCard(
          label: l10n.reportesCxcCuentasConSaldo,
          value: '${cobranza.cuentasConSaldo}',
          icon: Icons.description_outlined,
        ),
        RisegStatCard(
          label: l10n.reportesCxcClientesConSaldo,
          value: '${cobranza.clientesConSaldo}',
          icon: Icons.groups_outlined,
        ),
        RisegStatCard(
          label: l10n.reportesCxcDiasAtrasoPromedio,
          value: atraso == null ? '—' : l10n.reportesCxcDias(atraso.toStringAsFixed(0)),
          icon: Icons.hourglass_bottom,
          delta: atraso == null ? l10n.reportesCxcSinAtraso : l10n.reportesCxcDiasAtrasoPromedioNota,
          deltaTone: RisegStatusTone.neutral,
        ),
      ],
    );
  }
}

class _Aging extends StatelessWidget {
  const _Aging({required this.cobranza, required this.altura});

  final AnalisisCobranza cobranza;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return RisegChartCard(
      title: l10n.reportesCxcAgingTitulo,
      subtitle: l10n.reportesCxcAgingPregunta,
      height: altura,
      vacio: cobranza.saldoPendiente == 0,
      mensajeVacio: l10n.reportesCxcAgingVacia,
      iconoVacio: Icons.receipt_long_outlined,
      trailing: Text(
        formatoCentavosPago(cobranza.totalAging),
        style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
      ),
      child: RisegAgingBars(
        formatoValor: formatoCentavosPago,
        cubetas: [
          for (final cubeta in cobranza.aging)
            if (cubeta.importe != 0)
              RisegAgingCubeta(
                label: etiquetaCubetaAntiguedad(l10n, cubeta.cubeta),
                valor: cubeta.importe,
                tono: tonoCubetaAntiguedad(cubeta.cubeta),
                detalle: cubeta.porcentaje == null
                    ? l10n.reportesFinanzasAntiguedadConteo(cubeta.cuentas)
                    : '${l10n.reportesFinanzasAntiguedadConteo(cubeta.cuentas)} · '
                        '${(cubeta.porcentaje! * 100).toStringAsFixed(0)} %',
              ),
        ],
      ),
    );
  }
}

class _Concentracion extends StatelessWidget {
  const _Concentracion({required this.cobranza, required this.altura});

  final AnalisisCobranza cobranza;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return RisegChartCard(
      title: l10n.reportesCxcConcentracionTitulo,
      subtitle: l10n.reportesCxcConcentracionPregunta,
      height: altura,
      vacio: cobranza.concentracion.isEmpty,
      mensajeVacio: l10n.reportesCxcConcentracionVacia,
      iconoVacio: Icons.groups_outlined,
      trailing: Text(
        formatoCentavosPago(cobranza.saldoPendiente),
        style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
      ),
      child: RisegCompositionChart(
        total: cobranza.saldoPendiente,
        formatoValor: formatoCentavosPago,
        items: [
          for (final (indice, cliente) in cobranza.concentracion.indexed)
            RisegComposicionItem(
              label: cliente.esOtros ? l10n.reportesCxcConcentracionOtros : cliente.nombre,
              valor: cliente.saldo,
              // "Otros" siempre en gris: no es un cliente, es una
              // agrupación.
              color: cliente.esOtros ? colors.neutralText : context.colorCategorico(indice),
            ),
        ],
      ),
    );
  }
}

class _CobranzaEsperada extends StatelessWidget {
  const _CobranzaEsperada({required this.cobranza, required this.altura});

  final AnalisisCobranza cobranza;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final tramos = cobranza.cobranzaEsperada.where((t) => t.importe != 0).toList();
    final total = tramos.fold<int>(0, (a, t) => a + t.importe);

    return RisegChartCard(
      title: l10n.reportesCxcEsperadaTitulo,
      subtitle: l10n.reportesCxcEsperadaPregunta,
      height: altura,
      vacio: tramos.isEmpty,
      // Dos vacíos distintos: "no hay nada proyectado" y "no se puede
      // proyectar porque faltan cuentas financieras". No son lo mismo.
      mensajeVacio:
          cobranza.proyeccionDisponible ? l10n.reportesCxcEsperadaVacia : l10n.reportesCxcEsperadaSinCuentas,
      iconoVacio: Icons.event_available_outlined,
      trailing: Text(
        formatoCentavosPago(total),
        style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: RisegAgingBars(
              formatoValor: formatoCentavosPago,
              cubetas: [
                for (final tramo in tramos)
                  RisegAgingCubeta(
                    label: etiquetaHorizonteCobranza(l10n, tramo.horizonte),
                    valor: tramo.importe,
                    tono: tonoHorizonteCobranza(tramo.horizonte),
                  ),
              ],
            ),
          ),
          if (cobranza.cobranzaSinFechaEsperada > 0)
            Text(
              l10n.reportesCxcSinFechaEsperada(formatoCentavosPago(cobranza.cobranzaSinFechaEsperada)),
              style: AppTypography.caption.copyWith(color: colors.warning),
            ),
        ],
      ),
    );
  }
}

class _FiltrosCartera extends StatelessWidget {
  const _FiltrosCartera({required this.filtro, required this.onCambiar});

  final FiltroCobranza filtro;
  final ValueChanged<FiltroCobranza> onCambiar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 190,
          child: RisegSelect<String>(
            label: l10n.reportesCxcFiltroEstado,
            value: filtro.estatus?.name,
            items: [
              RisegSelectItem(value: '', label: l10n.reportesCxcFiltroTodos),
              for (final e in EstatusCuentaPorCobrar.values)
                RisegSelectItem(value: e.name, label: etiquetaEstatusCuenta(l10n, e.name)),
            ],
            onChanged: (valor) => onCambiar(
              valor == null || valor.isEmpty
                  ? filtro.copyWith(limpiarEstatus: true)
                  : filtro.copyWith(estatus: EstatusCuentaPorCobrar.values.byName(valor)),
            ),
          ),
        ),
        SizedBox(
          width: 190,
          child: RisegSelect<String>(
            label: l10n.reportesCxcFiltroCubeta,
            value: filtro.cubeta?.name,
            items: [
              RisegSelectItem(value: '', label: l10n.reportesCxcFiltroTodos),
              for (final c in RangoAntiguedadCuentaPorCobrar.values)
                RisegSelectItem(value: c.name, label: etiquetaCubetaAntiguedad(l10n, c)),
            ],
            onChanged: (valor) => onCambiar(
              valor == null || valor.isEmpty
                  ? filtro.copyWith(limpiarCubeta: true)
                  : filtro.copyWith(cubeta: RangoAntiguedadCuentaPorCobrar.values.byName(valor)),
            ),
          ),
        ),
        RisegCheckbox(
          label: l10n.reportesCxcFiltroConSaldo,
          value: filtro.soloConSaldo,
          onChanged: (valor) => onCambiar(filtro.copyWith(soloConSaldo: valor)),
        ),
        RisegCheckbox(
          label: l10n.reportesCxcFiltroVencidas,
          value: filtro.soloVencidas,
          onChanged: (valor) => onCambiar(filtro.copyWith(soloVencidas: valor)),
        ),
      ],
    );
  }
}

class _TablaCuentas extends StatelessWidget {
  const _TablaCuentas({required this.cuentas});

  final List<CuentaPorCobrarProyectada> cuentas;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return RisegTableBase<CuentaPorCobrarProyectada>(
      rows: cuentas,
      emptyState: RisegEmptyState(
        icon: Icons.receipt_long_outlined,
        title: l10n.reportesSinDatosTitulo,
        message: l10n.reportesCxcVacia,
      ),
      // Navegación por id real al expediente de la Cuenta. El destino
      // tiene su propia guardia de permiso: entrar a Reportes no
      // concede acceso a Finanzas.
      onRowTap: (c) => context.go('/finanzas/cuentas-por-cobrar/${c.cuenta.id}'),
      columns: [
        RisegColumn<CuentaPorCobrarProyectada>(
          label: l10n.reportesCxcColumnaCliente,
          width: 170,
          cellBuilder: (c) => Text(c.clienteNombre, overflow: TextOverflow.ellipsis),
        ),
        RisegColumn<CuentaPorCobrarProyectada>(
          label: l10n.reportesCxcColumnaEntidad,
          width: 160,
          cellBuilder: (c) => Text(c.entidadFiscalNombre ?? '—', overflow: TextOverflow.ellipsis),
        ),
        RisegColumn<CuentaPorCobrarProyectada>(
          label: l10n.reportesCxcColumnaServicio,
          width: 150,
          // Un documento puede facturar varios Servicios: se dice
          // "Varios" en vez de elegir uno al azar.
          cellBuilder: (c) => Text(
            switch (c.serviciosNombres.length) {
              0 => '—',
              1 => c.serviciosNombres.single,
              _ => l10n.reportesCxcVariosServicios,
            },
            overflow: TextOverflow.ellipsis,
          ),
        ),
        RisegColumn<CuentaPorCobrarProyectada>(
          label: l10n.reportesCxcColumnaFolio,
          width: 120,
          cellBuilder: (c) => Text(c.cuenta.folioDocumento ?? '—', overflow: TextOverflow.ellipsis),
        ),
        RisegColumn<CuentaPorCobrarProyectada>(
          label: l10n.reportesCxcColumnaEmision,
          width: 110,
          cellBuilder: (c) => Text(_formatoFecha.format(c.cuenta.fechaEmisionReal)),
        ),
        RisegColumn<CuentaPorCobrarProyectada>(
          label: l10n.reportesCxcColumnaVencimiento,
          width: 120,
          cellBuilder: (c) => Text(
            c.cuenta.fechaVencimiento == null ? '—' : _formatoFecha.format(c.cuenta.fechaVencimiento!),
          ),
        ),
        RisegColumn<CuentaPorCobrarProyectada>(
          label: l10n.reportesCxcColumnaTotal,
          width: 120,
          alignment: TextAlign.right,
          cellBuilder: (c) => Text(formatoCentavosPago(c.cuenta.importeEmitido)),
        ),
        RisegColumn<CuentaPorCobrarProyectada>(
          label: l10n.reportesCxcColumnaAplicado,
          width: 120,
          alignment: TextAlign.right,
          cellBuilder: (c) => Text(formatoCentavosPago(c.aplicado)),
        ),
        RisegColumn<CuentaPorCobrarProyectada>(
          label: l10n.reportesCxcColumnaSaldo,
          width: 120,
          alignment: TextAlign.right,
          cellBuilder: (c) => Text(
            formatoCentavosPago(c.saldo),
            style: AppTypography.bodyStrong.copyWith(
              color: c.estaVencidaHoy && c.saldo > 0 ? colors.error : colors.textPrimary,
            ),
          ),
        ),
        RisegColumn<CuentaPorCobrarProyectada>(
          label: l10n.reportesCxcColumnaAtraso,
          width: 100,
          alignment: TextAlign.right,
          cellBuilder: (c) => Text(c.diasAtraso == null ? '—' : l10n.reportesCxcDias('${c.diasAtraso}')),
        ),
        RisegColumn<CuentaPorCobrarProyectada>(
          label: l10n.reportesCxcColumnaMetodo,
          width: 90,
          cellBuilder: (c) => Text(c.cuenta.metodo.toUpperCase()),
        ),
        RisegColumn<CuentaPorCobrarProyectada>(
          label: l10n.reportesCxcColumnaEstado,
          width: 120,
          cellBuilder: (c) => RisegStatusBadge(
            label: etiquetaEstatusCuenta(l10n, c.cuenta.estatus),
            tone: tonoEstatusCuenta(c.cuenta.estatus),
          ),
        ),
        RisegColumn<CuentaPorCobrarProyectada>(
          label: l10n.reportesCxcColumnaComplemento,
          width: 120,
          cellBuilder: (c) => c.complementoPendiente
              ? RisegStatusBadge(label: l10n.complementosEstadoPendiente, tone: RisegStatusTone.error)
              : const Text('—'),
        ),
      ],
    );
  }
}
