import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_proyeccion_caja_usecase.dart';

import 'resumen_financiero_controller.dart';
import 'resumen_financiero_state.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoFechaCorta = DateFormat('dd/MM');
final _formatoMoneda = NumberFormat.currency(locale: 'es_MX', symbol: r'$');

String formatoCentavosResumen(int centavos) => _formatoMoneda.format(centavos / 100);

/// Portada ejecutiva de Finanzas (Etapa 17) — compone
/// `ResumenFinancieroController`, que a su vez reutiliza
/// `ObtenerResumenFinancieroUseCase`/`ClasificarEgresosPorOrigenUseCase`
/// (Reportes) y `calcularResumenCuentasPorCobrar` (Cuentas por cobrar);
/// esta pantalla no calcula nada por sí misma.
class ResumenFinancieroScreen extends ConsumerWidget {
  const ResumenFinancieroScreen({super.key});

  String _origenLabel(AppLocalizations l10n, String origen) {
    return switch (origen) {
      'pagoRecibido' => l10n.resumenFinancieroOrigenPagoRecibido,
      'compra' => l10n.resumenFinancieroOrigenCompra,
      'nomina' => l10n.resumenFinancieroOrigenNomina,
      'tiempoExtra' => l10n.resumenFinancieroOrigenTiempoExtra,
      'deuda' => l10n.resumenFinancieroOrigenDeuda,
      'descuentoProgramado' => l10n.resumenFinancieroOrigenDescuentoProgramado,
      // Telefonía y Vehículos generan Egresos automáticos desde las
      // schemaVersion 86 y 80, pero este `switch` nunca los nombró y
      // caían en el `_` de "Manual" — puro error de representación: la
      // clasificación y el origen automático siempre estuvieron bien.
      // Se reutilizan las mismas etiquetas que ya usa Reportes, para
      // que las dos pantallas digan exactamente la misma palabra.
      'telefonia' => l10n.recargaOrigenEtiquetaTelefonia,
      'vehiculo' => l10n.reportesFinanzasOrigenVehiculo,
      'servicioEventual' => l10n.egresosOrigenServicioEventual,
      _ => l10n.resumenFinancieroOrigenManual,
    };
  }

  /// Alertas puramente matemáticas (Etapa 19C, Parte H) — nunca un
  /// índice de salud inventado. Déficit proyectado solo tiene sentido
  /// si hay Cuentas financieras configuradas (si no, `saldoProyectado`
  /// no representa un dato real, ver Parte J). La fecha exacta (Etapa
  /// 19D, pedido §13) sale de la MISMA serie diaria que usa Planeación
  /// financiera — `puntoMinimoProyectado`, nunca un cálculo aparte.
  List<Widget> _alertas(BuildContext context, AppLocalizations l10n, ResumenFinancieroState state) {
    final minimo = state.puntoMinimoProyectado;
    final avisos = <Widget>[
      if (state.posicionDeCaja.configurada && state.proyeccionCaja.saldoProyectado < 0 && minimo != null)
        _AvisoResumen(
          mensaje: l10n.resumenFinancieroAlertaDeficitProyectado(
            formatoCentavosResumen(-state.proyeccionCaja.saldoProyectado),
            _formatoFechaCorta.format(minimo.fecha),
          ),
          tono: RisegStatusTone.error,
        ),
      if (state.deudasVencidasCount > 0)
        _AvisoResumen(mensaje: l10n.resumenFinancieroAlertaDeudasVencidas(state.deudasVencidasCount), tono: RisegStatusTone.warning),
    ];
    if (avisos.isEmpty) return const [];
    return [
      const SizedBox(height: AppSpacing.sm),
      for (final aviso in avisos) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.xs), child: aviso),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final state = ref.watch(resumenFinancieroControllerProvider);
    final notifier = ref.read(resumenFinancieroControllerProvider.notifier);

    if (state.errorCarga != null) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.resumenFinancieroCargaErrorTitulo,
        message: l10n.resumenFinancieroCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('resumen_financiero_boton_reintentar'),
          label: l10n.resumenFinancieroBotonReintentar,
          onPressed: notifier.reintentarCarga,
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(title: l10n.resumenFinancieroTitulo, description: l10n.resumenFinancieroSubtitulo),
          if (!state.cargando) ..._alertas(context, l10n, state),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                label: Text(l10n.resumenFinancieroPeriodoEsteMes),
                selected: state.periodo == PeriodoResumenFinanciero.esteMes,
                onSelected: (_) => notifier.cambiarPeriodo(PeriodoResumenFinanciero.esteMes),
              ),
              ChoiceChip(
                label: Text(l10n.resumenFinancieroPeriodoMesAnterior),
                selected: state.periodo == PeriodoResumenFinanciero.mesAnterior,
                onSelected: (_) => notifier.cambiarPeriodo(PeriodoResumenFinanciero.mesAnterior),
              ),
              ChoiceChip(
                label: Text(l10n.resumenFinancieroPeriodoPersonalizado),
                selected: state.periodo == PeriodoResumenFinanciero.personalizado,
                onSelected: (_) => notifier.cambiarPeriodo(PeriodoResumenFinanciero.personalizado),
              ),
              if (state.periodo == PeriodoResumenFinanciero.personalizado) ...[
                SizedBox(
                  width: 160,
                  child: RisegDateField(
                    label: l10n.reportesFiltroDesde,
                    value: state.rangoInicio,
                    onChanged: (valor) => notifier.aplicarRangoPersonalizado(inicio: valor, fin: state.rangoFin),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: RisegDateField(
                    label: l10n.reportesFiltroHasta,
                    value: state.rangoFin,
                    onChanged: (valor) => notifier.aplicarRangoPersonalizado(inicio: state.rangoInicio, fin: valor),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (state.cargando)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _KpisPrincipales(state: state),
            const SizedBox(height: AppSpacing.lg),
            if (state.posicionDeCaja.configurada) ...[
              _PosicionPorCuentaSection(state: state),
              const SizedBox(height: AppSpacing.lg),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final flujo = _FlujoDelPeriodoCard(state: state);
                final operativo = _ResultadoOperativoCard(state: state);
                if (constraints.maxWidth < AppBreakpoints.medium) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [flujo, const SizedBox(height: AppSpacing.lg), operativo],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: flujo),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: operativo),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            LayoutBuilder(
              builder: (context, constraints) {
                final porCobrar = _PorCobrarCard(state: state);
                final proximos = _ProximosCobrosCard(state: state);
                if (constraints.maxWidth < AppBreakpoints.medium) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [porCobrar, const SizedBox(height: AppSpacing.lg), proximos],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: porCobrar),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: proximos),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            _ProyeccionSection(state: state),
            const SizedBox(height: AppSpacing.lg),
            RisegCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.resumenFinancieroMovimientosTitulo, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                  const SizedBox(height: AppSpacing.sm),
                  if (state.movimientosRecientes.isEmpty)
                    Text(
                      l10n.resumenFinancieroMovimientosVacio,
                      style: AppTypography.body.copyWith(color: colors.textMuted, fontStyle: FontStyle.italic),
                    )
                  else
                    for (var i = 0; i < state.movimientosRecientes.length; i++) ...[
                      if (i > 0) const Divider(height: AppSpacing.lg),
                      _FilaMovimiento(movimiento: state.movimientosRecientes[i], origenLabel: _origenLabel(l10n, state.movimientosRecientes[i].origen)),
                    ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Los 5 KPIs principales del Resumen (Etapa 19C, Parte G) — liquidez
/// (Saldo disponible/proyectado) junto a las métricas de saldo ya
/// existentes (Por cobrar/Deuda actual). "Saldo disponible"/"Saldo
/// proyectado" muestran `—` (nunca `$0.00`) cuando no hay ninguna
/// Cuenta financiera configurada — ver `PosicionDeCaja.configurada`
/// (Parte J: jamás fingir un saldo real).
class _KpisPrincipales extends StatelessWidget {
  const _KpisPrincipales({required this.state});

  final ResumenFinancieroState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final resumenCxC = state.resumenCuentasPorCobrar;
    final configurada = state.posicionDeCaja.configurada;

    final tarjetas = [
      RisegStatCard(
        label: l10n.resumenFinancieroKpiSaldoDisponible,
        value: configurada ? formatoCentavosResumen(state.posicionDeCaja.saldoDisponible) : '—',
        dense: true,
      ),
      RisegStatCard(
        label: l10n.resumenFinancieroKpiPorCobrar,
        value: formatoCentavosResumen(resumenCxC.saldoPendiente),
        dense: true,
      ),
      RisegStatCard(
        label: l10n.resumenFinancieroKpiCompromisosProximos,
        value: formatoCentavosResumen(state.proyeccionCaja.salidasComprometidas),
        dense: true,
      ),
      RisegStatCard(
        label: l10n.resumenFinancieroKpiDeudaFinanciera,
        value: formatoCentavosResumen(state.deudaFinancieraTotal),
        dense: true,
        deltaTone: state.deudasVencidasCount > 0 ? RisegStatusTone.warning : null,
      ),
      RisegStatCard(
        label: l10n.resumenFinancieroKpiSaldoProyectado,
        value: configurada ? formatoCentavosResumen(state.proyeccionCaja.saldoProyectado) : '—',
        dense: true,
        deltaTone: configurada ? (state.proyeccionCaja.saldoProyectado < 0 ? RisegStatusTone.error : RisegStatusTone.success) : null,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnas = constraints.maxWidth < AppBreakpoints.compact
            ? 2
            : constraints.maxWidth < AppBreakpoints.wide
                ? 3
                : 5;
        final ancho = (constraints.maxWidth - (AppSpacing.md * (columnas - 1))) / columnas;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [for (final tarjeta in tarjetas) SizedBox(width: ancho, child: tarjeta)],
            ),
            if (!configurada) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(l10n.resumenFinancieroSaldoNoConfigurado, style: AppTypography.caption.copyWith(color: context.colors.textMuted)),
            ],
          ],
        );
      },
    );
  }
}

/// "Posición por cuenta" (Etapa 19C, Parte G) — tarjetas compactas por
/// Cuenta financiera activa. Solo se muestra cuando hay al menos una
/// cuenta configurada (`posicionDeCaja.configurada`).
class _PosicionPorCuentaSection extends StatelessWidget {
  const _PosicionPorCuentaSection({required this.state});

  final ResumenFinancieroState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final cuentas = state.posicionDeCaja.cuentas;

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.resumenFinancieroPosicionPorCuentaTitulo, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final columnas = constraints.maxWidth < AppBreakpoints.compact ? 1 : (constraints.maxWidth < AppBreakpoints.wide ? 2 : 3);
              final ancho = (constraints.maxWidth - (AppSpacing.md * (columnas - 1))) / columnas;
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  for (final cuenta in cuentas)
                    SizedBox(
                      width: ancho,
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          border: Border.all(color: colors.borderSubtle),
                          borderRadius: AppRadius.mdRadius,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(cuenta.nombre, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary), overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(
                              [
                                if (state.institucionNombrePorCuentaId[cuenta.id] != null) state.institucionNombrePorCuentaId[cuenta.id]!,
                                if (cuenta.ultimosDigitos != null) '****${cuenta.ultimosDigitos}',
                              ].join(' · '),
                              style: AppTypography.caption.copyWith(color: colors.textMuted),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              formatoCentavosResumen(state.posicionDeCaja.saldosPorCuenta[cuenta.id] ?? 0),
                              style: AppTypography.heading3.copyWith(color: colors.textPrimary),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// "Flujo del periodo" (Etapa 19C, Parte D/G) — entradas/salidas REALES
/// de caja, deliberadamente separado de "Resultado operativo": un pago
/// de deuda es salida de caja pero nunca gasto operativo.
class _FlujoDelPeriodoCard extends StatelessWidget {
  const _FlujoDelPeriodoCard({required this.state});

  final ResumenFinancieroState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final flujo = state.flujoEfectivoPeriodo;

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.resumenFinancieroFlujoTitulo, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: _EtiquetaMonto(label: l10n.resumenFinancieroFlujoEntradas, valor: formatoCentavosResumen(flujo.entradas), color: colors.success)),
              Expanded(child: _EtiquetaMonto(label: l10n.resumenFinancieroFlujoSalidas, valor: formatoCentavosResumen(flujo.salidas), color: colors.error)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${l10n.resumenFinancieroFlujoNeto}: ${formatoCentavosResumen(flujo.flujoNeto)}',
            style: AppTypography.bodyStrong.copyWith(color: flujo.flujoNeto < 0 ? colors.error : colors.success),
          ),
        ],
      ),
    );
  }
}

/// "Resultado operativo" (Etapa 19C, Parte G) — agrupa visualmente los
/// KPIs de resultado operativo ya construidos en la Etapa 17/19
/// (`resultadoOperativo`/`egresosOperativos`, nunca recalculados aquí),
/// con el margen derivado y la nota informativa de tarjeta (Etapa 19B).
class _ResultadoOperativoCard extends StatelessWidget {
  const _ResultadoOperativoCard({required this.state});

  final ResumenFinancieroState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final margen = state.ingresosPeriodo == 0 ? 0.0 : (state.resultadoOperativo / state.ingresosPeriodo) * 100;

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.resumenFinancieroResultadoOperativoTitulo, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: _EtiquetaMonto(label: l10n.resumenFinancieroResultadoOperativoIngresos, valor: formatoCentavosResumen(state.ingresosPeriodo), color: colors.success)),
              Expanded(child: _EtiquetaMonto(label: l10n.resumenFinancieroResultadoOperativoGastos, valor: formatoCentavosResumen(state.egresosOperativos), color: colors.error)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${l10n.resumenFinancieroResultadoOperativoResultado}: ${formatoCentavosResumen(state.resultadoOperativo)}',
            style: AppTypography.bodyStrong.copyWith(color: state.resultadoOperativo < 0 ? colors.error : colors.success),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.resumenFinancieroResultadoOperativoMargen('${margen.toStringAsFixed(1)}%'),
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
          if (state.cargosTarjetaPeriodo > 0 || state.pagosTarjetaPeriodo > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              [
                if (state.cargosTarjetaPeriodo > 0)
                  l10n.resumenFinancieroInfoCargosTarjeta(formatoCentavosResumen(state.cargosTarjetaPeriodo)),
                if (state.pagosTarjetaPeriodo > 0)
                  l10n.resumenFinancieroInfoPagosTarjeta(formatoCentavosResumen(state.pagosTarjetaPeriodo)),
              ].join(' · '),
              style: AppTypography.caption.copyWith(color: colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Proyección" (Etapa 19C, Parte E/F/G) — selector de horizonte +
/// tabla de "Próximos compromisos", ambos alimentados exclusivamente
/// por `ProyeccionCaja` (dato real, nunca inventado).
class _ProyeccionSection extends ConsumerWidget {
  const _ProyeccionSection({required this.state});

  final ResumenFinancieroState state;

  String _conceptoOrigenLabel(AppLocalizations l10n, OrigenCompromiso origen) {
    return switch (origen) {
      OrigenCompromiso.cuentaPorCobrar => l10n.resumenFinancieroCompromisoOrigenCuentaPorCobrar,
      OrigenCompromiso.nomina => l10n.resumenFinancieroCompromisoOrigenNomina,
      OrigenCompromiso.deuda => l10n.resumenFinancieroCompromisoOrigenDeuda,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final notifier = ref.read(resumenFinancieroControllerProvider.notifier);
    final compromisos = state.proyeccionCaja.compromisos;

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.resumenFinancieroProyeccionTitulo, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
          const SizedBox(height: 2),
          Text(l10n.resumenFinancieroProyeccionSubtitulo, style: AppTypography.caption.copyWith(color: colors.textMuted)),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                label: Text(l10n.resumenFinancieroProyeccion7Dias),
                selected: state.horizonteProyeccion == HorizonteProyeccion.dias7,
                onSelected: (_) => notifier.cambiarHorizonteProyeccion(HorizonteProyeccion.dias7),
              ),
              ChoiceChip(
                label: Text(l10n.resumenFinancieroProyeccion15Dias),
                selected: state.horizonteProyeccion == HorizonteProyeccion.dias15,
                onSelected: (_) => notifier.cambiarHorizonteProyeccion(HorizonteProyeccion.dias15),
              ),
              ChoiceChip(
                label: Text(l10n.resumenFinancieroProyeccion30Dias),
                selected: state.horizonteProyeccion == HorizonteProyeccion.dias30,
                onSelected: (_) => notifier.cambiarHorizonteProyeccion(HorizonteProyeccion.dias30),
              ),
              ChoiceChip(
                label: Text(l10n.resumenFinancieroProyeccionPersonalizado),
                selected: state.horizonteProyeccion == HorizonteProyeccion.personalizado,
                onSelected: (_) => notifier.cambiarHorizonteProyeccion(HorizonteProyeccion.personalizado),
              ),
              if (state.horizonteProyeccion == HorizonteProyeccion.personalizado)
                SizedBox(
                  width: 160,
                  child: RisegDateField(
                    label: l10n.reportesFiltroHasta,
                    value: state.horizontePersonalizadoHasta,
                    onChanged: notifier.aplicarHorizontePersonalizado,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(l10n.resumenFinancieroCompromisosTitulo, style: AppTypography.label.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          if (compromisos.isEmpty)
            Text(l10n.resumenFinancieroCompromisosVacio, style: AppTypography.body.copyWith(color: colors.textMuted, fontStyle: FontStyle.italic))
          else
            for (var i = 0; i < compromisos.length; i++) ...[
              if (i > 0) const Divider(height: AppSpacing.lg),
              _FilaCompromiso(compromiso: compromisos[i], origenLabel: _conceptoOrigenLabel(l10n, compromisos[i].origen)),
            ],
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: RisegButton(
              label: l10n.resumenFinancieroVerPlaneacionCompleta,
              variant: RisegButtonVariant.ghost,
              size: RisegButtonSize.compact,
              onPressed: () => context.push('/finanzas/planeacion'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaCompromiso extends StatelessWidget {
  const _FilaCompromiso({required this.compromiso, required this.origenLabel});

  final CompromisoFinanciero compromiso;
  final String origenLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final esEntrada = compromiso.tipo == TipoCompromiso.entrada;

    return Row(
      children: [
        SizedBox(width: 90, child: Text(_formatoFecha.format(compromiso.fecha), style: AppTypography.caption.copyWith(color: colors.textMuted))),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(child: Text(compromiso.concepto, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary), overflow: TextOverflow.ellipsis)),
                  if (compromiso.vencida) ...[
                    const SizedBox(width: AppSpacing.xs),
                    RisegStatusBadge(label: l10n.resumenFinancieroCompromisoVencida, tone: RisegStatusTone.error),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(origenLabel, style: AppTypography.caption.copyWith(color: colors.textMuted)),
            ],
          ),
        ),
        RisegStatusBadge(
          label: esEntrada ? l10n.resumenFinancieroCompromisoTipoEntrada : l10n.resumenFinancieroCompromisoTipoSalida,
          tone: esEntrada ? RisegStatusTone.success : RisegStatusTone.neutral,
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 110,
          child: Text(
            formatoCentavosResumen(compromiso.importe),
            textAlign: TextAlign.right,
            style: AppTypography.bodyStrong.copyWith(color: esEntrada ? colors.success : colors.textPrimary),
          ),
        ),
      ],
    );
  }
}

class _PorCobrarCard extends StatelessWidget {
  const _PorCobrarCard({required this.state});

  final ResumenFinancieroState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final resumen = state.resumenCuentasPorCobrar;
    final total = resumen.saldoPendiente == 0 ? 1 : resumen.saldoPendiente;
    final proporcionVencido = resumen.saldoVencido / total;

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.resumenFinancieroPorCobrarTitulo, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: AppRadius.smRadius,
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  if (resumen.saldoPorVencer > 0) Expanded(flex: (100 * (1 - proporcionVencido)).round().clamp(1, 100), child: ColoredBox(color: colors.success)),
                  if (resumen.saldoVencido > 0) Expanded(flex: (100 * proporcionVencido).round().clamp(1, 100), child: ColoredBox(color: colors.error)),
                  if (resumen.saldoPendiente == 0) Expanded(child: ColoredBox(color: colors.borderSubtle)),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _EtiquetaMonto(
                  label: l10n.resumenFinancieroPorCobrarAlCorriente,
                  valor: formatoCentavosResumen(resumen.saldoPorVencer),
                  color: colors.success,
                ),
              ),
              Expanded(
                child: _EtiquetaMonto(
                  label: l10n.resumenFinancieroPorCobrarVencido,
                  valor: formatoCentavosResumen(resumen.saldoVencido),
                  color: colors.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Aviso matemático del Resumen (Etapa 19C, Parte H) — mismo criterio
/// visual moderado que el resto de la pantalla: color solo en el
/// acento lateral y el icono, nunca una tarjeta completa pintada.
class _AvisoResumen extends StatelessWidget {
  const _AvisoResumen({required this.mensaje, required this.tono});

  final String mensaje;
  final RisegStatusTone tono;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = tono == RisegStatusTone.error ? colors.error : colors.warning;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: AppRadius.mdRadius,
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: AppSizes.iconSm, color: color),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(mensaje, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary))),
        ],
      ),
    );
  }
}

class _EtiquetaMonto extends StatelessWidget {
  const _EtiquetaMonto({required this.label, required this.valor, required this.color});

  final String label;
  final String valor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: AppSpacing.xxs),
            Flexible(
              child: Text(
                label,
                style: AppTypography.label.copyWith(color: context.colors.textMuted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(valor, style: AppTypography.bodyStrong.copyWith(color: context.colors.textPrimary)),
      ],
    );
  }
}

class _ProximosCobrosCard extends StatelessWidget {
  const _ProximosCobrosCard({required this.state});

  final ResumenFinancieroState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.resumenFinancieroProximosCobrosTitulo, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          if (state.proximosCobros.isEmpty)
            Text(
              l10n.resumenFinancieroProximosCobrosVacio,
              style: AppTypography.body.copyWith(color: colors.textMuted, fontStyle: FontStyle.italic),
            )
          else
            for (var i = 0; i < state.proximosCobros.length; i++) ...[
              if (i > 0) const Divider(height: AppSpacing.md),
              _FilaProximoCobro(proximo: state.proximosCobros[i]),
            ],
        ],
      ),
    );
  }
}

class _FilaProximoCobro extends StatelessWidget {
  const _FilaProximoCobro({required this.proximo});

  final ProximoCobro proximo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(proximo.clienteNombre, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
              const SizedBox(height: 2),
              Text(
                _formatoFecha.format(proximo.cuenta.fechaVencimiento!),
                style: AppTypography.caption.copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ),
        Text(
          formatoCentavosResumen(proximo.cuenta.saldoPendiente),
          style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
        ),
      ],
    );
  }
}

class _FilaMovimiento extends StatelessWidget {
  const _FilaMovimiento({required this.movimiento, required this.origenLabel});

  final MovimientoFinanciero movimiento;
  final String origenLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final esIngreso = movimiento.tipo == TipoMovimientoFinanciero.ingreso;

    return Row(
      children: [
        SizedBox(width: 90, child: Text(_formatoFecha.format(movimiento.fecha), style: AppTypography.caption.copyWith(color: colors.textMuted))),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(movimiento.concepto, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary), overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(origenLabel, style: AppTypography.caption.copyWith(color: colors.textMuted)),
            ],
          ),
        ),
        RisegStatusBadge(
          label: esIngreso ? 'Ingreso' : 'Egreso',
          tone: esIngreso ? RisegStatusTone.success : RisegStatusTone.neutral,
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 110,
          child: Text(
            formatoCentavosResumen(movimiento.importe),
            textAlign: TextAlign.right,
            style: AppTypography.bodyStrong.copyWith(color: esIngreso ? colors.success : colors.textPrimary),
          ),
        ),
      ],
    );
  }
}
