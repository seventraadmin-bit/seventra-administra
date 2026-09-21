import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/calcular_serie_disponibilidad_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_proyeccion_caja_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_por_cobrar/widgets/cuenta_por_cobrar_detalle_dialog.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;

import 'planeacion_financiera_controller.dart';
import 'planeacion_financiera_state.dart';
import 'widgets/calendario_financiero_mes.dart';
import 'widgets/detalle_dia_card.dart';
import 'widgets/grafica_disponibilidad_proyectada.dart';
import 'widgets/reprogramar_cobro_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoMes = DateFormat('MMMM yyyy', 'es_MX');
final _formatoFechaCorta = DateFormat('d/MM');

String _capitalizar(String texto) => texto.isEmpty ? texto : '${texto[0].toUpperCase()}${texto.substring(1)}';

/// Planeación financiera (Etapa 19D, "Calendario financiero y
/// planeación de liquidez") — calendario + gráfica de disponibilidad +
/// resumen semanal + pendientes vencidos. Consume EXACTAMENTE la misma
/// `ObtenerProyeccionCajaUseCase` que el Resumen financiero (ver
/// `PlaneacionFinancieraController`) — esta pantalla no recalcula
/// ningún compromiso, solo los presenta de otra forma.
class PlaneacionFinancieraScreen extends ConsumerWidget {
  const PlaneacionFinancieraScreen({super.key});

  Future<void> _abrirCompromiso(BuildContext context, CompromisoFinanciero compromiso) async {
    switch (compromiso.origen) {
      case OrigenCompromiso.cuentaPorCobrar:
        await showDialog<void>(context: context, builder: (_) => CuentaPorCobrarDetalleDialog(cuentaPorCobrarId: compromiso.origenId));
      case OrigenCompromiso.nomina:
        context.push('/personal/nomina/${compromiso.origenId}');
      case OrigenCompromiso.deuda:
        context.push('/finanzas/deudas-y-credito/${compromiso.origenId}');
    }
  }

  Future<void> _abrirPendiente(BuildContext context, WidgetRef ref, PendienteVencido pendiente) async {
    if (pendiente.tipo == TipoPendienteVencido.cobro) {
      await showDialog<void>(context: context, builder: (_) => CuentaPorCobrarDetalleDialog(cuentaPorCobrarId: pendiente.origenId));
      return;
    }
    if (pendiente.origen == OrigenCompromiso.nomina) {
      context.push('/personal/nomina/${pendiente.origenId}');
    } else {
      context.push('/finanzas/deudas-y-credito/${pendiente.origenId}');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final state = ref.watch(planeacionFinancieraControllerProvider);
    final notifier = ref.read(planeacionFinancieraControllerProvider.notifier);

    if (state.errorCarga != null) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.planeacionCargaErrorTitulo,
        message: l10n.planeacionCargaErrorMensaje,
        primaryAction: RisegButton(label: l10n.resumenFinancieroBotonReintentar, onPressed: notifier.reintentarCarga),
      );
    }

    final hoy = DateTime.now();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(title: l10n.planeacionTitulo, description: l10n.planeacionSubtitulo),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                label: Text(l10n.planeacionPeriodoMesAnterior),
                selected: state.periodo == PeriodoPlaneacion.mesAnterior,
                onSelected: (_) => notifier.cambiarPeriodo(PeriodoPlaneacion.mesAnterior),
              ),
              ChoiceChip(
                label: Text(l10n.planeacionPeriodoEsteMes),
                selected: state.periodo == PeriodoPlaneacion.esteMes,
                onSelected: (_) => notifier.cambiarPeriodo(PeriodoPlaneacion.esteMes),
              ),
              ChoiceChip(
                label: Text(l10n.planeacionPeriodoMesSiguiente),
                selected: state.periodo == PeriodoPlaneacion.mesSiguiente,
                onSelected: (_) => notifier.cambiarPeriodo(PeriodoPlaneacion.mesSiguiente),
              ),
              ChoiceChip(
                label: Text(l10n.planeacionPeriodoPersonalizado),
                selected: state.periodo == PeriodoPlaneacion.personalizado,
                onSelected: (_) => notifier.cambiarPeriodo(PeriodoPlaneacion.personalizado),
              ),
              if (state.periodo == PeriodoPlaneacion.personalizado)
                SizedBox(
                  width: 170,
                  child: RisegDateField(
                    label: l10n.planeacionPersonalizadoCampoMes,
                    value: state.mesVisible,
                    onChanged: notifier.elegirMesPersonalizado,
                  ),
                ),
              Text(_capitalizar(_formatoMes.format(state.mesVisible)), style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (state.cargando)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _KpisPlaneacion(state: state),
            const SizedBox(height: AppSpacing.lg),
            RisegCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.planeacionGraficaTitulo, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                  const SizedBox(height: AppSpacing.sm),
                  if (!state.proyeccionCaja.cuentasConfiguradas)
                    Text(l10n.resumenFinancieroSaldoNoConfigurado, style: AppTypography.body.copyWith(color: colors.textMuted, fontStyle: FontStyle.italic))
                  else
                    GraficaDisponibilidadProyectada(
                      serie: state.serie,
                      onDiaSeleccionado: (punto) => notifier.seleccionarDia(punto.fecha),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            LayoutBuilder(
              builder: (context, constraints) {
                final calendario = RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.planeacionCalendarioTitulo, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                      const SizedBox(height: AppSpacing.sm),
                      CalendarioFinancieroMes(
                        mesVisible: state.mesVisible,
                        compromisos: state.proyeccionCaja.compromisos,
                        hoy: hoy,
                        diaSeleccionado: state.diaSeleccionado,
                        onDiaSeleccionado: notifier.seleccionarDia,
                      ),
                    ],
                  ),
                );
                final detalle = DetalleDiaCard(
                  dia: state.diaSeleccionado ?? hoy,
                  compromisosDelDia: state.proyeccionCaja.compromisos
                      .where((c) =>
                          state.diaSeleccionado != null &&
                          c.fecha.year == state.diaSeleccionado!.year &&
                          c.fecha.month == state.diaSeleccionado!.month &&
                          c.fecha.day == state.diaSeleccionado!.day)
                      .toList(),
                  onAbrirCompromiso: (c) => _abrirCompromiso(context, c),
                );
                if (constraints.maxWidth < AppBreakpoints.medium) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [calendario, const SizedBox(height: AppSpacing.lg), detalle],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: calendario),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(flex: 2, child: detalle),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            RisegCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.planeacionResumenSemanalTitulo, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                  const SizedBox(height: AppSpacing.sm),
                  if (state.resumenSemanal.isEmpty)
                    Text(l10n.planeacionGraficaVaciaMensaje, style: AppTypography.body.copyWith(color: colors.textMuted, fontStyle: FontStyle.italic))
                  else
                    RisegTableBase<ResumenSemanal>(
                      rows: state.resumenSemanal,
                      emptyState: const SizedBox.shrink(),
                      columns: [
                        RisegColumn<ResumenSemanal>(
                          label: l10n.planeacionResumenSemanalColumnaSemana,
                          cellBuilder: (s) => Text('${_formatoFechaCorta.format(s.inicio)} – ${_formatoFechaCorta.format(s.fin)}'),
                        ),
                        RisegColumn<ResumenSemanal>(
                          label: l10n.planeacionResumenSemanalColumnaEntradas,
                          alignment: TextAlign.right,
                          cellBuilder: (s) => Text(formatoCentavosPago(s.entradas), style: TextStyle(color: colors.success)),
                        ),
                        RisegColumn<ResumenSemanal>(
                          label: l10n.planeacionResumenSemanalColumnaSalidas,
                          alignment: TextAlign.right,
                          cellBuilder: (s) => Text(formatoCentavosPago(s.salidas), style: TextStyle(color: colors.error)),
                        ),
                        RisegColumn<ResumenSemanal>(
                          label: l10n.planeacionResumenSemanalColumnaBalance,
                          alignment: TextAlign.right,
                          cellBuilder: (s) => Text(
                            formatoCentavosPago(s.balance),
                            style: AppTypography.bodyStrong.copyWith(color: s.balance < 0 ? colors.error : colors.success),
                          ),
                        ),
                        RisegColumn<ResumenSemanal>(
                          label: l10n.planeacionResumenSemanalColumnaSaldoFinal,
                          alignment: TextAlign.right,
                          cellBuilder: (s) => Text(formatoCentavosPago(s.saldoFinal), style: AppTypography.bodyStrong),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _PendientesVencidosSection(
              pendientes: state.proyeccionCaja.pendientesVencidos,
              onAbrir: (p) => _abrirPendiente(context, ref, p),
              onReprogramar: (p) => mostrarDialogoReprogramarCobro(context, ref, pendiente: p),
            ),
          ],
        ],
      ),
    );
  }
}

class _KpisPlaneacion extends StatelessWidget {
  const _KpisPlaneacion({required this.state});

  final PlaneacionFinancieraState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final proyeccion = state.proyeccionCaja;
    final configurada = proyeccion.cuentasConfiguradas;
    final saldoFinal = state.serie.isEmpty ? proyeccion.saldoActual : state.serie.last.saldo;
    final minimo = state.puntoMinimo;

    final tarjetas = [
      RisegStatCard(label: l10n.planeacionKpiDisponibleHoy, value: configurada ? formatoCentavosPago(proyeccion.saldoActual) : '—', dense: true),
      RisegStatCard(label: l10n.planeacionKpiCobrosPrevistos, value: formatoCentavosPago(proyeccion.entradasPrevistas), dense: true),
      RisegStatCard(label: l10n.planeacionKpiPagosComprometidos, value: formatoCentavosPago(proyeccion.salidasComprometidas), dense: true),
      RisegStatCard(label: l10n.planeacionKpiSaldoFinalPeriodo, value: configurada ? formatoCentavosPago(saldoFinal) : '—', dense: true),
      RisegStatCard(
        label: l10n.planeacionKpiSaldoMinimo,
        value: configurada && minimo != null ? formatoCentavosPago(minimo.saldo) : '—',
        dense: true,
        deltaTone: minimo != null && minimo.saldo < 0 ? RisegStatusTone.error : null,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columnas = constraints.maxWidth < AppBreakpoints.compact
                ? 2
                : constraints.maxWidth < AppBreakpoints.wide
                    ? 3
                    : 5;
            final ancho = (constraints.maxWidth - (AppSpacing.md * (columnas - 1))) / columnas;
            return Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [for (final t in tarjetas) SizedBox(width: ancho, child: t)],
            );
          },
        ),
        if (configurada && minimo != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            minimo.saldo < 0
                ? l10n.planeacionDeficitMaximo(formatoCentavosPago(-minimo.saldo), _formatoFecha.format(minimo.fecha))
                : l10n.planeacionSaldoMinimoFecha(_formatoFecha.format(minimo.fecha)),
            style: AppTypography.caption.copyWith(color: minimo.saldo < 0 ? Theme.of(context).colorScheme.error : context.colors.textMuted),
          ),
        ],
      ],
    );
  }
}

class _PendientesVencidosSection extends StatelessWidget {
  const _PendientesVencidosSection({required this.pendientes, required this.onAbrir, required this.onReprogramar});

  final List<PendienteVencido> pendientes;
  final void Function(PendienteVencido) onAbrir;
  final void Function(PendienteVencido) onReprogramar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final cobros = pendientes.where((p) => p.tipo == TipoPendienteVencido.cobro).toList();
    final pagos = pendientes.where((p) => p.tipo == TipoPendienteVencido.pago).toList();

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.planeacionPendientesVencidosTitulo, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          if (pendientes.isEmpty)
            Text(l10n.planeacionPendientesVencidosVacio, style: AppTypography.body.copyWith(color: colors.textMuted, fontStyle: FontStyle.italic))
          else ...[
            if (cobros.isNotEmpty) ...[
              Text(l10n.planeacionCobrosVencidosTitulo, style: AppTypography.label.copyWith(color: colors.textMuted)),
              const SizedBox(height: AppSpacing.xs),
              for (final p in cobros) _FilaPendiente(pendiente: p, onAbrir: () => onAbrir(p), onReprogramar: () => onReprogramar(p)),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (pagos.isNotEmpty) ...[
              Text(l10n.planeacionPagosVencidosTitulo, style: AppTypography.label.copyWith(color: colors.textMuted)),
              const SizedBox(height: AppSpacing.xs),
              for (final p in pagos) _FilaPendiente(pendiente: p, onAbrir: () => onAbrir(p), onReprogramar: null),
            ],
          ],
        ],
      ),
    );
  }
}

class _FilaPendiente extends StatelessWidget {
  const _FilaPendiente({required this.pendiente, required this.onAbrir, required this.onReprogramar});

  final PendienteVencido pendiente;
  final VoidCallback onAbrir;
  final VoidCallback? onReprogramar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: InkWell(
              onTap: onAbrir,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(pendiente.concepto, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary), overflow: TextOverflow.ellipsis),
                  Text(l10n.planeacionVencioHaceDias(pendiente.diasVencido), style: AppTypography.caption.copyWith(color: colors.warning)),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Monto y botón apilados (no en la misma línea): un nombre de
          // Cliente/Deuda largo ya se recorta con `Expanded`, pero el
          // monto + "Reprogramar fecha esperada" juntos en una sola
          // fila desbordan a anchos angostos (~500px) sin importar
          // cuánto se comprima el lado izquierdo.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(formatoCentavosPago(pendiente.importe), style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
              if (onReprogramar != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                RisegButton(
                  label: l10n.planeacionBotonReprogramar,
                  variant: RisegButtonVariant.ghost,
                  size: RisegButtonSize.compact,
                  onPressed: onReprogramar,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
