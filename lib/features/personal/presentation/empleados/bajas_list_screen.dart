import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart' show MotivoBajaEmpleado;
import 'package:riseg_one/features/personal/domain/usecases/analitica_bajas.dart';
import 'package:riseg_one/features/personal/domain/usecases/construir_eventos_baja.dart';

import 'bajas_controller.dart';
import 'empleados_list_screen.dart' show lineaPuestoServicioTurno;
import 'bajas_state.dart';
import 'widgets/baja_evento_detalle_dialog.dart';
import 'widgets/motivo_baja_empleado_labels.dart' show motivoBajaEmpleadoLabel;
import 'widgets/graficas_bajas.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
const _mesesCortos = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
const _mesesLargos = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

String _permanenciaTexto(AppLocalizations l10n, BajaEvento e) {
  final c = e.permanencia;
  if (c.antiguedadAnios > 0) return l10n.personalActivoAntiguedadAniosMeses(c.antiguedadAnios, c.antiguedadMeses);
  if (c.antiguedadMeses > 0) return l10n.personalActivoAntiguedadMeses(c.antiguedadMeses);
  return l10n.bajaPermanenciaDias(c.diasLaborados);
}

String _segmentoLabel(AppLocalizations l10n, SegmentoPermanencia s) {
  return switch (s) {
    SegmentoPermanencia.menos30Dias => l10n.bajaSegmentoMenos30Dias,
    SegmentoPermanencia.uno3Meses => l10n.bajaSegmentoUno3Meses,
    SegmentoPermanencia.tres6Meses => l10n.bajaSegmentoTres6Meses,
    SegmentoPermanencia.seis12Meses => l10n.bajaSegmentoSeis12Meses,
    SegmentoPermanencia.masDeUnAnio => l10n.bajaSegmentoMasDeUnAnio,
  };
}

String _periodoLabel(AppLocalizations l10n, PeriodoAnaliticaBajas p) {
  return switch (p) {
    PeriodoAnaliticaBajas.esteMes => l10n.bajaPeriodoEsteMes,
    PeriodoAnaliticaBajas.ultimos3Meses => l10n.bajaPeriodoUltimos3Meses,
    PeriodoAnaliticaBajas.esteAnio => l10n.bajaPeriodoEsteAnio,
    PeriodoAnaliticaBajas.personalizado => l10n.bajaPeriodoPersonalizado,
  };
}

/// "Bajas de personal" (Etapa 15, densidad Etapa 17) — vista de
/// analítica de rotación y permanencia, no solo tabla histórica.
/// `Bajas` representa EVENTOS (un periodo laboral terminado), no
/// Empleados únicos — un mismo Empleado puede aparecer más de una vez
/// si tuvo Ingreso→Baja→Reingreso→Baja (Resolución explícita de
/// Marlon).
///
/// Etapa 17: se retiran las 4 etiquetas de "zona" en mayúsculas
/// (Resumen/Tendencia/Análisis/Detalle) — cada tarjeta ya lleva su
/// propio título en Title Case; mismo criterio de densidad plana que
/// el nuevo Resumen de Finanzas (`resumen_financiero_screen.dart`):
/// una secuencia de bloques, sin una segunda capa de encabezado
/// encima de cada `RisegCard`.
class BajasListScreen extends ConsumerStatefulWidget {
  const BajasListScreen({super.key});

  @override
  ConsumerState<BajasListScreen> createState() => _BajasListScreenState();
}

class _BajasListScreenState extends ConsumerState<BajasListScreen> {
  final _buscarCtrl = TextEditingController();

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(bajasControllerProvider);
    final notifier = ref.read(bajasControllerProvider.notifier);

    if (state.errorCarga != null && state.eventos.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.empleadosListadoCargaErrorTitulo,
        message: l10n.empleadosListadoCargaErrorMensaje,
        primaryAction: RisegButton(label: l10n.empleadosListadoBotonReintentar, onPressed: notifier.reintentarCarga),
      );
    }
    if (state.cargando) return const Center(child: CircularProgressIndicator());

    final eventosPeriodo = state.eventosDelPeriodo;
    final rango = state.rango;
    final permanenciaPromedio = calcularPermanenciaPromedioDias(eventosPeriodo);
    final rotacionTemprana = filtrarRotacionTemprana(eventosPeriodo);
    final motivos = calcularMotivosBaja(eventosPeriodo);
    final segmentos = calcularSegmentosPermanencia(eventosPeriodo);
    final servicios = calcularServiciosConMayorRotacion(eventosPeriodo);
    final bajasPorMes = calcularBajasPorMes(eventosPeriodo, rango.inicio, rango.fin);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(title: l10n.bajaTitulo, description: l10n.bajaSubtitulo),
          const SizedBox(height: AppSpacing.md),
          _selectorPeriodo(context, l10n, state, notifier),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              SizedBox(width: 190, child: RisegStatCard(dense: true, label: l10n.bajaKpiBajasPeriodo, value: '${eventosPeriodo.length}')),
              SizedBox(
                width: 190,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.bajaKpiPermanenciaPromedio,
                  value: eventosPeriodo.isEmpty ? '—' : l10n.bajaPermanenciaMesesDecimal((permanenciaPromedio / 30.44).toStringAsFixed(1)),
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.bajaKpiRotacionTemprana,
                  value: '${rotacionTemprana.length}',
                  deltaTone: rotacionTemprana.isNotEmpty ? RisegStatusTone.warning : RisegStatusTone.success,
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.bajaKpiMotivoPrincipal,
                  value: motivos.isEmpty ? '—' : motivoBajaEmpleadoLabel(l10n, motivos.first.motivo.name),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (eventosPeriodo.isEmpty)
            RisegEmptyState(title: l10n.bajaVacioTitulo, message: l10n.bajaVacioMensaje)
          else ...[
            _tarjetaTendencia(context, l10n, bajasPorMes),
            const SizedBox(height: AppSpacing.lg),
            _tarjetaAnalisis(context, l10n, motivos, segmentos),
            const SizedBox(height: AppSpacing.lg),
            if (servicios.isNotEmpty) ...[
              _tarjetaServicios(context, l10n, servicios),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (rotacionTemprana.isNotEmpty) ...[
              _tarjetaRotacionTemprana(context, l10n, rotacionTemprana),
              const SizedBox(height: AppSpacing.lg),
            ],
          ],
          _seccionFiltrosYTabla(context, l10n, state, notifier),
        ],
      ),
    );
  }

  Widget _selectorPeriodo(BuildContext context, AppLocalizations l10n, BajasState state, BajasController notifier) {
    return Wrap(
      spacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final p in PeriodoAnaliticaBajas.values)
          ChoiceChip(
            label: Text(_periodoLabel(l10n, p)),
            selected: state.periodo == p,
            onSelected: (_) async {
              if (p != PeriodoAnaliticaBajas.personalizado) {
                notifier.cambiarPeriodo(p);
                return;
              }
              final rango = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 1)),
                initialDateRange: DateTimeRange(start: state.rango.inicio, end: state.rango.fin),
              );
              if (rango != null) {
                notifier.cambiarPeriodo(p, inicioPersonalizado: rango.start, finPersonalizado: rango.end);
              }
            },
          ),
      ],
    );
  }

  /// Etapa 16, evolución visual — "Bajas por mes" con tendencia
  /// adaptativa (pedido explícito, item 7): con un solo mes con datos
  /// dentro del periodo seleccionado, un `GraficaBarrasVerticales`
  /// completo es una gráfica casi vacía ocupando un bloque grande;
  /// se sustituye por una representación compacta mes/cantidad. Con 2+
  /// meses con datos se mantiene la gráfica de barras existente, sin
  /// cambios. Solo llamado cuando `eventosPeriodo` NO está vacío (ver
  /// `build`), así que siempre hay al menos un mes con `cantidad > 0`.
  Widget _tarjetaTendencia(BuildContext context, AppLocalizations l10n, List<BajasPorMes> bajasPorMes) {
    final colors = context.colors;
    final mesesConDatos = bajasPorMes.where((m) => m.cantidad > 0).toList();

    if (mesesConDatos.length <= 1) {
      final mes = mesesConDatos.first;
      return RisegCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.bajaSeccionBajasPorMes, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text(
                  l10n.bajaTendenciaCompactaMes(_mesesLargos[mes.mes - 1], mes.anio),
                  style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(l10n.bajaTendenciaCompactaCantidad(mes.cantidad), style: AppTypography.body.copyWith(color: colors.textMuted)),
              ],
            ),
          ],
        ),
      );
    }

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.bajaSeccionBajasPorMes, style: AppTypography.label.copyWith(color: colors.textMuted)),
          const SizedBox(height: AppSpacing.sm),
          GraficaBarrasVerticales(
            datos: [
              for (final m in bajasPorMes)
                (_mesesCortos[m.mes - 1], m.cantidad, l10n.bajaTooltipMes(_mesesCortos[m.mes - 1], m.anio, m.cantidad)),
            ],
          ),
        ],
      ),
    );
  }

  /// "Motivos de baja" + "Permanencia al momento de la baja" en UNA sola
  /// tarjeta (Etapa 15, rediseño visual) — antes eran 2 `RisegCard`
  /// separadas; fusionarlas reduce la sensación de bloques blancos
  /// independientes sin quitar ningún análisis.
  Widget _tarjetaAnalisis(
    BuildContext context,
    AppLocalizations l10n,
    List<MotivoBajaConteo> motivos,
    List<SegmentoPermanenciaConteo> segmentos,
  ) {
    final colors = context.colors;

    final motivosCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.bajaSeccionMotivos, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.sm),
        if (motivos.isEmpty)
          Text(l10n.bajaVacioMensaje, style: AppTypography.body.copyWith(color: colors.textMuted))
        else
          for (final m in motivos)
            BarraHorizontalConteo(etiqueta: motivoBajaEmpleadoLabel(l10n, m.motivo.name), cantidad: m.cantidad, porcentaje: m.porcentaje),
      ],
    );

    final permanenciaCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.bajaSeccionPermanencia, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.sm),
        for (final s in segmentos)
          BarraHorizontalConteo(
            etiqueta: _segmentoLabel(l10n, s.segmento),
            cantidad: s.cantidad,
            porcentaje: s.porcentaje,
            tone: s.segmento == SegmentoPermanencia.menos30Dias ? RisegStatusTone.warning : RisegStatusTone.info,
          ),
      ],
    );

    return RisegCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= AppBreakpoints.medium) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: motivosCol),
                const Padding(padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg), child: SizedBox(height: 1)),
                Expanded(child: permanenciaCol),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [motivosCol, const SizedBox(height: AppSpacing.lg), permanenciaCol],
          );
        },
      ),
    );
  }

  Widget _tarjetaServicios(BuildContext context, AppLocalizations l10n, List<ServicioRotacion> servicios) {
    final colors = context.colors;
    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.bajaSeccionServicios, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          for (final s in servicios)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                children: [
                  Expanded(flex: 2, child: Text(s.servicioNombre, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary))),
                  SizedBox(width: 60, child: Text('${s.cantidad}', textAlign: TextAlign.right)),
                  SizedBox(width: 120, child: Text(l10n.bajaPermanenciaMesesDecimal((s.permanenciaPromedioDias / 30.44).toStringAsFixed(1)), textAlign: TextAlign.right)),
                  Expanded(child: Text(motivoBajaEmpleadoLabel(l10n, s.motivoPrincipal.name), textAlign: TextAlign.right, style: AppTypography.caption.copyWith(color: colors.textMuted))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tarjetaRotacionTemprana(BuildContext context, AppLocalizations l10n, List<BajaEvento> rotacionTemprana) {
    final colors = context.colors;
    return RisegCard(
      borderColor: colors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_outlined, color: colors.warning, size: AppSizes.iconSm),
              const SizedBox(width: AppSpacing.xs),
              Text(l10n.bajaSeccionRotacionTemprana, style: AppTypography.heading3.copyWith(color: colors.warning)),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(l10n.bajaRotacionTempranaResumen(rotacionTemprana.length), style: AppTypography.body.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          for (final e in rotacionTemprana)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                children: [
                  Expanded(flex: 2, child: Text(e.nombreCompleto)),
                  Expanded(child: Text(e.servicioNombre ?? '—', style: AppTypography.caption.copyWith(color: colors.textMuted))),
                  SizedBox(width: 90, child: Text(_formatoFecha.format(e.fechaIngreso), style: AppTypography.caption)),
                  SizedBox(width: 90, child: Text(_formatoFecha.format(e.fechaBaja), style: AppTypography.caption)),
                  SizedBox(width: 70, child: Text(l10n.bajaDiasLaborados(e.permanenciaDias), textAlign: TextAlign.right, style: AppTypography.caption)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _seccionFiltrosYTabla(BuildContext context, AppLocalizations l10n, BajasState state, BajasController notifier) {
    final colors = context.colors;
    final filas = state.filasTabla;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.bajaSeccionTabla, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: RisegSearchField(
                hint: l10n.personalActivoBuscar,
                controller: _buscarCtrl,
                onChanged: (v) => notifier.aplicarFiltros(texto: v, limpiarTexto: v.isEmpty),
              ),
            ),
            SizedBox(
              width: 170,
              child: RisegSelect<String?>(
                label: l10n.personalActivoFiltroServicio,
                value: state.servicioFiltro,
                items: [
                  RisegSelectItem(value: null, label: l10n.empleadosFiltroPuestoTodos),
                  for (final s in state.servicios) RisegSelectItem(value: s.servicio.nombre, label: s.servicio.nombre),
                ],
                onChanged: (v) => notifier.aplicarFiltros(servicioFiltro: v, limpiarServicioFiltro: v == null),
              ),
            ),
            SizedBox(
              width: 170,
              child: RisegSelect<String?>(
                label: l10n.empleadosFiltroPuesto,
                value: state.puestoFiltro,
                items: [
                  RisegSelectItem(value: null, label: l10n.empleadosFiltroPuestoTodos),
                  for (final p in state.puestos) RisegSelectItem(value: p.nombre, label: p.nombre),
                ],
                onChanged: (v) => notifier.aplicarFiltros(puestoFiltro: v, limpiarPuestoFiltro: v == null),
              ),
            ),
            SizedBox(
              width: 170,
              child: RisegSelect<MotivoBajaEmpleado?>(
                label: l10n.bajaDetalleMotivo,
                value: state.motivoFiltro,
                items: [
                  RisegSelectItem(value: null, label: l10n.empleadosFiltroPuestoTodos),
                  for (final m in MotivoBajaEmpleado.values) RisegSelectItem(value: m, label: motivoBajaEmpleadoLabel(l10n, m.name)),
                ],
                onChanged: (v) => notifier.aplicarFiltros(motivoFiltro: v, limpiarMotivoFiltro: v == null),
              ),
            ),
            SizedBox(
              width: 170,
              child: RisegSelect<SegmentoPermanencia?>(
                label: l10n.bajaSeccionPermanencia,
                value: state.segmentoFiltro,
                items: [
                  RisegSelectItem(value: null, label: l10n.empleadosFiltroPuestoTodos),
                  for (final s in SegmentoPermanencia.values) RisegSelectItem(value: s, label: _segmentoLabel(l10n, s)),
                ],
                onChanged: (v) => notifier.aplicarFiltros(segmentoFiltro: v, limpiarSegmentoFiltro: v == null),
              ),
            ),
            SizedBox(
              width: 170,
              child: RisegSelect<OrdenBajas>(
                label: l10n.bajaOrdenarPor,
                value: state.orden,
                items: [
                  RisegSelectItem(value: OrdenBajas.fechaBajaDesc, label: l10n.bajaOrdenFechaBaja),
                  RisegSelectItem(value: OrdenBajas.permanencia, label: l10n.bajaOrdenPermanencia),
                  RisegSelectItem(value: OrdenBajas.empleado, label: l10n.bajaOrdenEmpleado),
                  RisegSelectItem(value: OrdenBajas.servicio, label: l10n.personalActivoColumnaServicio),
                ],
                onChanged: (v) => notifier.cambiarOrden(v ?? OrdenBajas.fechaBajaDesc),
              ),
            ),
            RisegButton(
              label: l10n.personalActivoLimpiarFiltros,
              variant: RisegButtonVariant.ghost,
              onPressed: state.hayFiltrosActivos
                  ? () {
                      _buscarCtrl.clear();
                      notifier.limpiarTodosLosFiltros();
                    }
                  : null,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        RisegTableBase<BajaEvento>(
          rows: filas,
          onRowTap: (e) => mostrarDialogoDetalleBaja(context, e),
          emptyState: RisegEmptyState(title: l10n.bajaVacioTitulo, message: l10n.bajaVacioMensaje),
          hoverColor: colors.accentSoftBg,
          rowActionsBuilder: (_) => Icon(Icons.chevron_right, size: AppSizes.iconMd, color: colors.textMuted),
          actionsWidth: 40,
          columns: [
            // Etapa 16, evolución visual: identidad del Empleado igual
            // que "Plantilla activa" — foto/iniciales + nombre + No. de
            // empleado. La fotografía es identidad VIGENTE de la
            // persona (item 12 del pedido); nunca representa el puesto
            // de este periodo en particular.
            RisegColumn<BajaEvento>(
              label: l10n.bajaDetalleEmpleado,
              cellBuilder: (e) => RisegEntityIdentity(
                primario: e.nombreCompleto,
                secundario: l10n.personalActivoNumeroEmpleado(e.numeroEmpleado),
                imagenPath: state.fotografiaPathPorEmpleadoId[e.empleadoId],
              ),
            ),
            // Puesto/Servicio/Turno en una sola línea compuesta, SIEMPRE
            // del snapshot histórico de este periodo laboral
            // (`BajaEvento.puestoNombre/servicioNombre/turnoNombre`),
            // nunca del Servicio/puesto actual del Empleado — crítico
            // para un empleado reingresado con una baja previa.
            RisegColumn<BajaEvento>(
              label: l10n.personalActivoColumnaServicio,
              cellBuilder: (e) => Text(
                lineaPuestoServicioTurno(puesto: e.puestoNombre, servicio: e.servicioNombre, turno: e.turnoNombre) ??
                    l10n.bajaSinInformacion,
              ),
            ),
            RisegColumn<BajaEvento>(label: l10n.empleadosColumnaFechaIngreso, width: 100, cellBuilder: (e) => Text(_formatoFecha.format(e.fechaIngreso))),
            RisegColumn<BajaEvento>(label: l10n.bajaColumnaFechaBaja, width: 100, cellBuilder: (e) => Text(_formatoFecha.format(e.fechaBaja))),
            RisegColumn<BajaEvento>(label: l10n.bajaDetallePermanencia, width: 110, cellBuilder: (e) => Text(_permanenciaTexto(l10n, e))),
            RisegColumn<BajaEvento>(
              label: l10n.bajaDetalleMotivo,
              width: 160,
              cellBuilder: (e) => RisegStatusBadge(
                label: motivoBajaEmpleadoLabel(l10n, e.motivoBaja),
                tone: e.esRotacionTemprana ? RisegStatusTone.warning : RisegStatusTone.neutral,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
