import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;
import 'package:riseg_one/features/inventario/presentation/articulo_unidad_labels.dart';
import 'package:riseg_one/features/personal/data/tables/conciliacion_baja_table.dart';

import '../../domain/analitica/obtener_analisis_patrimonio_usecase.dart';
import '../../domain/export/exportar_reporte_resultado.dart';
import '../../reportes_providers.dart';
import '../widgets/analitica_labels.dart';
import '../widgets/construir_contexto_exportacion.dart';
import '../widgets/paneles_analiticos.dart';
import '../widgets/patrimonio_labels.dart';
import '../widgets/reporte_export_button.dart';
import '../widgets/reportes_filtro_bar.dart';
import 'reportes_patrimonio_controller.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoMes = DateFormat('MMM yyyy', 'es_MX');

/// Reporte de Patrimonio y bajas.
///
/// Responde qué pasó con cada bien al cerrar una relación laboral,
/// manteniendo separadas cuatro situaciones que se parecen y no son lo
/// mismo: pendiente de recuperar, perdido, pendiente de desecho y
/// recuperado-pero-fuera-de-disponibilidad.
class ReportesPatrimonioScreen extends ConsumerWidget {
  const ReportesPatrimonioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(reportesPatrimonioControllerProvider);
    final controller = ref.read(reportesPatrimonioControllerProvider.notifier);
    final analisis = state.analisis;

    Future<void> exportarXlsx() async {
      if (analisis == null) return;
      final contexto = construirContextoExportacion(
        ref,
        nombreReporte: l10n.reportesNombrePatrimonio,
        rangoInicio: state.rangoInicio,
        rangoFin: state.rangoFin,
      );
      // Se exporta el análisis YA filtrado: el archivo trae el mismo
      // universo que la pantalla.
      final resultado =
          await ref.read(exportarPatrimonioXlsxUseCaseProvider).ejecutar(contexto: contexto, analisis: analisis);
      if (!context.mounted) return;
      switch (resultado) {
        case ExportarReporteExitoso():
          RisegFeedback.showSuccess(context, l10n.reportesExportoExito);
        case ExportarReporteErrorInesperado():
          RisegFeedback.showError(context, l10n.reportesExportoError);
      }
    }

    Future<void> exportarPdf() async {
      if (analisis == null) return;
      final contexto = construirContextoExportacion(
        ref,
        nombreReporte: l10n.reportesNombrePatrimonio,
        rangoInicio: state.rangoInicio,
        rangoFin: state.rangoFin,
      );
      final resultado =
          await ref.read(exportarPatrimonioPdfUseCaseProvider).ejecutar(contexto: contexto, analisis: analisis);
      if (!context.mounted) return;
      switch (resultado) {
        case ExportarReporteExitoso():
          RisegFeedback.showSuccess(context, l10n.reportesExportoExito);
        case ExportarReporteErrorInesperado():
          RisegFeedback.showError(context, l10n.reportesExportoError);
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.reportesPatrimonioTitulo,
            description: l10n.reportesPatrimonioDescripcion,
            primaryAction: controller.sinAutorizacion || state.cargando || analisis == null
                ? null
                : Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      ReporteExportButton(
                        label: l10n.reportesExportarPdf,
                        icon: Icons.picture_as_pdf_outlined,
                        onExportar: exportarPdf,
                      ),
                      ReporteExportButton(
                        label: l10n.reportesExportarPatrimonio,
                        icon: Icons.grid_on_outlined,
                        onExportar: exportarXlsx,
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.md),
          const ReportesFiltroBar(),
          const SizedBox(height: AppSpacing.lg),
          if (state.cargando && analisis == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (state.errorCarga != null)
            RisegEmptyState(icon: Icons.error_outline, title: l10n.reportesErrorCargaTitulo, message: state.errorCarga!)
          else if (controller.sinAutorizacion)
            RisegEmptyState(
              icon: Icons.lock_outline,
              title: l10n.reportesSinSeccionesTitulo,
              message: l10n.reportesPatrimonioSinPermiso,
            )
          else if (analisis == null)
            const SizedBox.shrink()
          else
            _Contenido(analisis: analisis, filtro: state.filtro, onFiltrar: controller.cambiarFiltro),
        ],
      ),
    );
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido({required this.analisis, required this.filtro, required this.onFiltrar});

  final AnalisisPatrimonio analisis;
  final FiltroPatrimonio filtro;
  final ValueChanged<FiltroPatrimonio> onFiltrar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    final estados = analisis.unidadesPorEstatus.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final altoFila = alturaDeFila([
      RisegCompositionChart.alturaPara(estados.length),
      RisegAgingBars.alturaPara(analisis.impactoPorBaja.take(ObtenerAnalisisPatrimonioUseCase.topImpacto).length),
      alturaSerieTemporal,
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Kpis(analisis: analisis),
        const SizedBox(height: AppSpacing.md),
        FilaPaneles(
          paneles: [
            PanelAnalitico(minAncho: 300, child: _EstadosFisicos(analisis: analisis, altura: altoFila)),
            PanelAnalitico(minAncho: 300, child: _Impacto(analisis: analisis, altura: altoFila)),
            PanelAnalitico(minAncho: 320, child: _Serie(analisis: analisis, altura: altoFila)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _Filtros(filtro: filtro, catalogo: analisis.catalogo, onFiltrar: onFiltrar),
        const SizedBox(height: AppSpacing.xs),
        _ChipsFiltrosActivos(filtro: filtro, catalogo: analisis.catalogo, onFiltrar: onFiltrar),
        const SizedBox(height: AppSpacing.sm),
        Text(l10n.reportesPatrimonioDetalleTitulo, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
        const SizedBox(height: AppSpacing.sm),
        _TablaRenglones(renglones: analisis.renglones),
        const SizedBox(height: AppSpacing.md),
        _TablaServicios(analisis: analisis),
        const SizedBox(height: AppSpacing.md),
        FilaPaneles(
          paneles: [
            PanelAnalitico(minAncho: 380, child: _TablaDescuentos(analisis: analisis)),
            PanelAnalitico(minAncho: 340, child: _TablaAutorizadores(analisis: analisis)),
          ],
        ),
      ],
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.analisis});

  final AnalisisPatrimonio analisis;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tasa = analisis.tasaRecuperacion.tasa;
    final excluidos =
        analisis.tasaRecuperacion.excluidosTransferidos + analisis.tasaRecuperacion.excluidosAutorizados;

    return RisegKpiGrid(
      children: [
        RisegStatCard(
          label: l10n.reportesPatrimonioBajasConciliadas,
          value: '${analisis.bajasConciliadas}',
          icon: Icons.how_to_reg_outlined,
        ),
        RisegStatCard(
          label: l10n.reportesPatrimonioRecuperados,
          value: '${analisis.recuperados}',
          icon: Icons.assignment_turned_in_outlined,
          deltaTone: RisegStatusTone.success,
        ),
        // Pendiente y perdido son KPIs distintos a propósito: uno se
        // sigue esperando, el otro ya se declaró irrecuperable.
        RisegStatCard(
          label: l10n.reportesPatrimonioPendientes,
          value: '${analisis.pendientes}',
          icon: Icons.hourglass_bottom,
          deltaTone: analisis.pendientes > 0 ? RisegStatusTone.warning : RisegStatusTone.success,
        ),
        RisegStatCard(
          label: l10n.reportesPatrimonioPerdidos,
          value: '${analisis.perdidos}',
          icon: Icons.report_gmailerrorred_outlined,
          deltaTone: analisis.perdidos > 0 ? RisegStatusTone.error : null,
        ),
        // §16 — lo excluido del denominador se ve, no se sobreentiende:
        // un bien transferido pasó a otra persona y nunca debió volver
        // al almacén, así que no puede castigar la tasa en silencio.
        if (analisis.transferidos > 0)
          RisegStatCard(
            label: l10n.reportesPatrimonioTransferidos,
            value: '${analisis.transferidos}',
            icon: Icons.swap_horiz,
            delta: l10n.reportesPatrimonioTransferidosNota,
            deltaTone: RisegStatusTone.neutral,
          ),
        RisegStatCard(
          label: l10n.reportesPatrimonioImporteDescuentos,
          value: formatoCentavosPago(analisis.importeDescuentos),
          icon: Icons.request_quote_outlined,
        ),
        RisegStatCard(
          label: l10n.reportesPatrimonioSaldoDescuentos,
          value: formatoCentavosPago(analisis.saldoDescuentos),
          icon: Icons.pending_actions_outlined,
          deltaTone: analisis.saldoDescuentos > 0 ? RisegStatusTone.warning : null,
        ),
        RisegStatCard(
          label: l10n.reportesPatrimonioNoCobrado,
          value: formatoCentavosPago(analisis.importeNoCobrado),
          icon: Icons.money_off,
          delta: l10n.reportesPatrimonioNoCobradoNota,
          deltaTone: RisegStatusTone.neutral,
        ),
        RisegStatCard(
          label: l10n.reportesPatrimonioTasa,
          // Sin denominador no hay tasa: 0 % diría que no se recuperó
          // nada, cuando en realidad no había nada que recuperar.
          value: tasa == null ? '—' : '${(tasa * 100).toStringAsFixed(0)} %',
          icon: Icons.percent,
          // Cuando algo quedó fuera del denominador, la nota lo dice:
          // una tasa alta porque se excluyeron bienes no es lo mismo
          // que una tasa alta porque volvieron.
          delta: tasa == null
              ? l10n.reportesPatrimonioTasaSinBase
              : (excluidos > 0
                  ? l10n.reportesPatrimonioTasaExcluidos(
                      analisis.tasaRecuperacion.excluidosTransferidos,
                      analisis.tasaRecuperacion.excluidosAutorizados,
                    )
                  : l10n.reportesPatrimonioTasaNota),
          deltaTone: RisegStatusTone.neutral,
        ),
        if (analisis.valorEsParcial)
          RisegStatCard(
            label: l10n.reportesPatrimonioValorParcial(analisis.bienesSinValorConocido),
            value: formatoCentavosPago(analisis.valorPendiente + analisis.valorPerdido),
            icon: Icons.warning_amber_outlined,
            deltaTone: RisegStatusTone.warning,
          ),
      ],
    );
  }
}

class _EstadosFisicos extends StatelessWidget {
  const _EstadosFisicos({required this.analisis, required this.altura});

  final AnalisisPatrimonio analisis;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final estados = analisis.unidadesPorEstatus.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = estados.fold<int>(0, (a, e) => a + e.value);

    return RisegChartCard(
      title: l10n.reportesPatrimonioEstadosTitulo,
      subtitle: l10n.reportesPatrimonioEstadosPregunta,
      height: altura,
      vacio: estados.isEmpty,
      mensajeVacio: l10n.reportesPatrimonioEstadosVacia,
      iconoVacio: Icons.inventory_2_outlined,
      trailing: Text('$total', style: AppTypography.bodyStrong.copyWith(color: context.colors.textPrimary)),
      child: RisegCompositionChart(
        total: total,
        formatoValor: formatoCantidad,
        items: [
          for (final estado in estados)
            RisegComposicionItem(
              label: estatusArticuloUnidadLabel(l10n, estado.key),
              valor: estado.value,
              color: colorEstatusUnidad(context, estado.key),
            ),
        ],
      ),
    );
  }
}

class _Impacto extends StatelessWidget {
  const _Impacto({required this.analisis, required this.altura});

  final AnalisisPatrimonio analisis;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final top = analisis.impactoPorBaja
        .where((i) => i.bienesEnRiesgo > 0)
        .take(ObtenerAnalisisPatrimonioUseCase.topImpacto)
        .toList();

    return RisegChartCard(
      title: l10n.reportesPatrimonioImpactoTitulo,
      subtitle: l10n.reportesPatrimonioImpactoPregunta,
      height: altura,
      vacio: top.isEmpty,
      mensajeVacio: l10n.reportesPatrimonioImpactoVacia,
      iconoVacio: Icons.check_circle_outline,
      child: RisegAgingBars(
        formatoValor: formatoCantidad,
        cubetas: [
          for (final baja in top)
            RisegAgingCubeta(
              label: baja.nombre,
              valor: baja.bienesEnRiesgo,
              tono: baja.bienesPerdidos > 0 ? RisegStatusTone.error : RisegStatusTone.warning,
              detalle: baja.importeDescuentos > 0
                  ? formatoCentavosPago(baja.importeDescuentos)
                  : _formatoFecha.format(baja.fechaBaja),
            ),
        ],
      ),
    );
  }
}

class _Serie extends StatelessWidget {
  const _Serie({required this.analisis, required this.altura});

  final AnalisisPatrimonio analisis;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final serie = analisis.serieMensual;

    return RisegChartCard(
      title: l10n.reportesPatrimonioSerieTitulo,
      subtitle: l10n.reportesPatrimonioSeriePregunta,
      height: altura,
      vacio: serie.isEmpty,
      mensajeVacio: l10n.reportesPatrimonioSerieVacia,
      iconoVacio: Icons.stacked_line_chart,
      legend: [
        RisegChartLegendItem(label: l10n.reportesPatrimonioLeyendaBajas, color: context.colorCategorico(0)),
        RisegChartLegendItem(label: l10n.reportesPatrimonioLeyendaPendientes, color: colors.warning),
      ],
      // Sólo meses con bajas reales: no se rellena una serie continua
      // que fingiría meses que no ocurrieron en el universo filtrado.
      child: RisegBarChart(
        etiquetas: [for (final p in serie) _formatoMes.format(p.mes)],
        formatoValor: formatoCantidad,
        mostrarEjeY: false,
        series: [
          RisegBarSeries(
            label: l10n.reportesPatrimonioLeyendaBajas,
            color: context.colorCategorico(0),
            valores: [for (final p in serie) p.bajas],
          ),
          RisegBarSeries(
            label: l10n.reportesPatrimonioLeyendaPendientes,
            color: colors.warning,
            valores: [for (final p in serie) p.pendientesGenerados],
          ),
        ],
      ),
    );
  }
}

class _Filtros extends StatelessWidget {
  const _Filtros({required this.filtro, required this.catalogo, required this.onFiltrar});

  final FiltroPatrimonio filtro;

  /// Catálogo del periodo SIN filtrar: elegir a alguien no puede dejar
  /// la lista con una sola opción.
  final CatalogoFiltrosPatrimonio catalogo;

  final ValueChanged<FiltroPatrimonio> onFiltrar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 240,
          child: RisegSearchSelect<String>(
            key: const Key('patrimonio_filtro_empleado'),
            label: l10n.reportesPatrimonioFiltroEmpleado,
            hint: l10n.reportesPatrimonioFiltroEmpleadoHint,
            textoSinResultados: l10n.reportesPatrimonioFiltroSinCoincidencias,
            tooltipLimpiar: l10n.reportesPatrimonioFiltroQuitar,
            value: filtro.empleadoId,
            opciones: [
              for (final o in catalogo.empleados)
                RisegSearchOption(value: o.empleadoId, etiqueta: o.nombre, detalle: o.puesto),
            ],
            onChanged: (valor) => onFiltrar(
              valor == null ? filtro.copyWith(limpiarEmpleado: true) : filtro.copyWith(empleadoId: valor),
            ),
          ),
        ),
        SizedBox(
          width: 240,
          child: RisegSearchSelect<String>(
            key: const Key('patrimonio_filtro_autorizador'),
            label: l10n.reportesPatrimonioFiltroAutorizador,
            hint: l10n.reportesPatrimonioFiltroAutorizadorHint,
            textoSinResultados: l10n.reportesPatrimonioFiltroSinCoincidencias,
            tooltipLimpiar: l10n.reportesPatrimonioFiltroQuitar,
            value: filtro.autorizadorId,
            opciones: [
              for (final o in catalogo.autorizadores)
                RisegSearchOption(value: o.empleadoId, etiqueta: o.nombre, detalle: o.puesto),
            ],
            onChanged: (valor) => onFiltrar(
              valor == null ? filtro.copyWith(limpiarAutorizador: true) : filtro.copyWith(autorizadorId: valor),
            ),
          ),
        ),
        SizedBox(
          width: 240,
          child: RisegSearchSelect<String>(
            key: const Key('patrimonio_filtro_servicio'),
            label: l10n.reportesPatrimonioFiltroServicio,
            hint: l10n.reportesPatrimonioFiltroServicioHint,
            textoSinResultados: l10n.reportesPatrimonioFiltroSinServicios,
            tooltipLimpiar: l10n.reportesPatrimonioFiltroQuitar,
            value: filtro.servicioId,
            opciones: [
              for (final o in catalogo.servicios)
                RisegSearchOption(value: o.servicioId, etiqueta: o.nombre, detalle: o.cliente),
            ],
            onChanged: (valor) => onFiltrar(
              valor == null ? filtro.copyWith(limpiarServicio: true) : filtro.copyWith(servicioId: valor),
            ),
          ),
        ),
        SizedBox(
          width: 190,
          child: RisegSelect<String>(
            label: l10n.reportesPatrimonioFiltroTipo,
            value: filtro.tipoBien?.name,
            items: [
              RisegSelectItem(value: '', label: l10n.reportesPatrimonioFiltroTodos),
              for (final t in TipoBienConciliado.values)
                RisegSelectItem(value: t.name, label: etiquetaTipoBien(l10n, t)),
            ],
            onChanged: (valor) => onFiltrar(
              valor == null || valor.isEmpty
                  ? filtro.copyWith(limpiarTipoBien: true)
                  : filtro.copyWith(tipoBien: TipoBienConciliado.values.byName(valor)),
            ),
          ),
        ),
        SizedBox(
          width: 190,
          child: RisegSelect<String>(
            label: l10n.reportesPatrimonioFiltroResolucion,
            value: filtro.resolucion?.name,
            items: [
              RisegSelectItem(value: '', label: l10n.reportesPatrimonioFiltroTodos),
              for (final r in ResolucionResguardoBaja.values)
                RisegSelectItem(value: r.name, label: etiquetaResolucion(l10n, r)),
            ],
            onChanged: (valor) => onFiltrar(
              valor == null || valor.isEmpty
                  ? filtro.copyWith(limpiarResolucion: true)
                  : filtro.copyWith(resolucion: ResolucionResguardoBaja.values.byName(valor)),
            ),
          ),
        ),
        RisegCheckbox(
          label: l10n.reportesPatrimonioFiltroPendientes,
          value: filtro.soloPendientes,
          onChanged: (valor) => onFiltrar(filtro.copyWith(soloPendientes: valor)),
        ),
        RisegCheckbox(
          label: l10n.reportesPatrimonioFiltroConDescuento,
          value: filtro.conDescuento ?? false,
          onChanged: (valor) => onFiltrar(
            valor ? filtro.copyWith(conDescuento: true) : filtro.copyWith(limpiarConDescuento: true),
          ),
        ),
      ],
    );
  }
}

/// Resumen visible de lo que está recortando el reporte.
///
/// Sin esto, un filtro buscable es invisible en cuanto se pierde el
/// foco: el usuario ve cifras chicas y no sabe por qué. Cada chip se
/// quita por separado y hay un atajo para limpiar todo.
class _ChipsFiltrosActivos extends StatelessWidget {
  const _ChipsFiltrosActivos({required this.filtro, required this.catalogo, required this.onFiltrar});

  final FiltroPatrimonio filtro;
  final CatalogoFiltrosPatrimonio catalogo;
  final ValueChanged<FiltroPatrimonio> onFiltrar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    String nombrePersona(List<OpcionPersonaFiltro> donde, String id) {
      for (final o in donde) {
        if (o.empleadoId == id) return o.nombre;
      }
      return id;
    }

    String nombreServicio(String id) {
      for (final o in catalogo.servicios) {
        if (o.servicioId == id) return o.nombre;
      }
      return id;
    }

    final chips = <({String texto, FiltroPatrimonio sinEl})>[
      if (filtro.empleadoId != null)
        (
          texto: l10n.reportesPatrimonioFiltroChipEmpleado(nombrePersona(catalogo.empleados, filtro.empleadoId!)),
          sinEl: filtro.copyWith(limpiarEmpleado: true),
        ),
      if (filtro.autorizadorId != null)
        (
          texto:
              l10n.reportesPatrimonioFiltroChipAutorizador(nombrePersona(catalogo.autorizadores, filtro.autorizadorId!)),
          sinEl: filtro.copyWith(limpiarAutorizador: true),
        ),
      if (filtro.servicioId != null)
        (
          texto: l10n.reportesPatrimonioFiltroChipServicio(nombreServicio(filtro.servicioId!)),
          sinEl: filtro.copyWith(limpiarServicio: true),
        ),
      if (filtro.tipoBien != null)
        (
          texto: l10n.reportesPatrimonioFiltroChipTipo(etiquetaTipoBien(l10n, filtro.tipoBien!)),
          sinEl: filtro.copyWith(limpiarTipoBien: true),
        ),
      if (filtro.resolucion != null)
        (
          texto: l10n.reportesPatrimonioFiltroChipResolucion(etiquetaResolucion(l10n, filtro.resolucion!)),
          sinEl: filtro.copyWith(limpiarResolucion: true),
        ),
      if (filtro.soloPendientes)
        (
          texto: l10n.reportesPatrimonioFiltroPendientes,
          sinEl: filtro.copyWith(soloPendientes: false),
        ),
      if (filtro.conDescuento != null)
        (
          texto: l10n.reportesPatrimonioFiltroConDescuento,
          sinEl: filtro.copyWith(limpiarConDescuento: true),
        ),
    ];

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          l10n.reportesPatrimonioFiltrosActivos,
          style: AppTypography.caption.copyWith(color: colors.textMuted),
        ),
        for (final chip in chips)
          InputChip(
            label: Text(chip.texto, style: AppTypography.caption.copyWith(color: colors.textPrimary)),
            backgroundColor: colors.accentSoftBg,
            side: BorderSide(color: colors.borderSubtle),
            visualDensity: VisualDensity.compact,
            deleteIcon: const Icon(Icons.close, size: 14),
            onDeleted: () => onFiltrar(chip.sinEl),
          ),
        TextButton(
          onPressed: () => onFiltrar(const FiltroPatrimonio()),
          child: Text(l10n.reportesPatrimonioFiltrosLimpiar),
        ),
      ],
    );
  }
}

class _TablaRenglones extends StatelessWidget {
  const _TablaRenglones({required this.renglones});

  final List<RenglonPatrimonio> renglones;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return RisegTableBase<RenglonPatrimonio>(
      rows: renglones,
      emptyState: RisegEmptyState(
        icon: Icons.inventory_2_outlined,
        title: l10n.reportesSinDatosTitulo,
        message: l10n.reportesPatrimonioVacio,
      ),
      // Al expediente del ex empleado, por id. El destino conserva su
      // propia guardia de permiso.
      onRowTap: (r) => context.go('/personal/empleados/${r.conciliacion.empleadoId}'),
      columns: [
        RisegColumn<RenglonPatrimonio>(
          label: l10n.reportesPatrimonioColumnaEmpleado,
          width: 180,
          cellBuilder: (r) => Text(r.empleadoNombre, overflow: TextOverflow.ellipsis),
        ),
        RisegColumn<RenglonPatrimonio>(
          label: l10n.reportesPatrimonioColumnaFechaBaja,
          width: 110,
          cellBuilder: (r) => Text(_formatoFecha.format(r.fechaBaja)),
        ),
        // Servicio HISTÓRICO: el vigente a la fecha de baja. Cuando no
        // se puede resolver lo dice con todas sus letras; una celda en
        // blanco haría pensar que la persona no tenía servicio.
        RisegColumn<RenglonPatrimonio>(
          label: l10n.reportesPatrimonioServicioColumna,
          width: 190,
          cellBuilder: (r) => r.servicioHistorico.esResuelto
              ? Text(r.servicioHistorico.nombre!, overflow: TextOverflow.ellipsis)
              : RisegStatusBadge(
                  label: etiquetaServicioHistorico(l10n, r.servicioHistorico),
                  tone: tonoServicioHistorico(r.servicioHistorico.estado),
                ),
        ),
        RisegColumn<RenglonPatrimonio>(
          label: l10n.reportesPatrimonioColumnaBien,
          width: 200,
          cellBuilder: (r) => Text(r.bienDescripcion, overflow: TextOverflow.ellipsis),
        ),
        RisegColumn<RenglonPatrimonio>(
          label: l10n.reportesPatrimonioColumnaTipo,
          width: 110,
          cellBuilder: (r) => Text(etiquetaTipoBien(l10n, r.tipo)),
        ),
        RisegColumn<RenglonPatrimonio>(
          label: l10n.reportesPatrimonioColumnaResolucion,
          width: 130,
          cellBuilder: (r) => RisegStatusBadge(
            label: etiquetaResolucion(l10n, r.resolucion),
            tone: tonoResolucion(r.resolucion),
          ),
        ),
        RisegColumn<RenglonPatrimonio>(
          label: l10n.reportesPatrimonioColumnaMotivo,
          width: 180,
          cellBuilder: (r) => Text(
            r.motivoNoEntrega == null
                ? (r.renglon.motivoNoEntregaOtro ?? '—')
                : etiquetaMotivoNoEntrega(l10n, r.motivoNoEntrega!),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        RisegColumn<RenglonPatrimonio>(
          label: l10n.reportesPatrimonioColumnaPendienteDesde,
          width: 130,
          // La marca real. Un bien recuperado nunca muestra fecha aquí,
          // por mucho que esté en lavandería.
          cellBuilder: (r) => Text(
            r.pendienteDesde == null ? '—' : _formatoFecha.format(r.pendienteDesde!),
            style: AppTypography.body.copyWith(color: r.estaPendiente ? colors.warning : colors.textPrimary),
          ),
        ),
        RisegColumn<RenglonPatrimonio>(
          label: l10n.reportesPatrimonioColumnaCompromiso,
          width: 120,
          cellBuilder: (r) =>
              Text(r.fechaCompromiso == null ? '—' : _formatoFecha.format(r.fechaCompromiso!)),
        ),
        RisegColumn<RenglonPatrimonio>(
          label: l10n.reportesPatrimonioColumnaEstadoFisico,
          width: 150,
          cellBuilder: (r) => r.estatusUnidad == null
              ? const Text('—')
              : RisegStatusBadge(
                  label: estatusArticuloUnidadLabel(l10n, r.estatusUnidad!),
                  tone: tonoArticuloUnidad(r.estatusUnidad!),
                ),
        ),
        RisegColumn<RenglonPatrimonio>(
          label: l10n.reportesPatrimonioColumnaAutorizador,
          width: 160,
          cellBuilder: (r) => Text(r.autorizadorNombre ?? '—', overflow: TextOverflow.ellipsis),
        ),
        RisegColumn<RenglonPatrimonio>(
          label: l10n.reportesPatrimonioColumnaReceptor,
          width: 160,
          cellBuilder: (r) => Text(r.receptorNombre ?? '—', overflow: TextOverflow.ellipsis),
        ),
        RisegColumn<RenglonPatrimonio>(
          label: l10n.reportesPatrimonioColumnaDescuento,
          width: 130,
          alignment: TextAlign.right,
          cellBuilder: (r) => Text(r.descuento == null ? '—' : formatoCentavosPago(r.importeDescuento)),
        ),
        RisegColumn<RenglonPatrimonio>(
          label: l10n.reportesPatrimonioColumnaValor,
          width: 130,
          alignment: TextAlign.right,
          // Sin costo capturado se muestra un guion: nunca $0, que
          // significaría "vale cero".
          cellBuilder: (r) => Text(r.valorAproximado == null ? '—' : formatoCentavosPago(r.valorAproximado!)),
        ),
      ],
    );
  }
}

class _TablaDescuentos extends StatelessWidget {
  const _TablaDescuentos({required this.analisis});

  final AnalisisPatrimonio analisis;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    // Sólo obligaciones vinculadas por FK a un renglón de conciliación:
    // nunca préstamos personales ni otros descuentos.
    final conDescuento = analisis.renglones.where((r) => r.descuento != null).toList();

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.reportesPatrimonioDescuentosTitulo,
            style: AppTypography.heading3.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          RisegTableBase<RenglonPatrimonio>(
            rows: conDescuento,
            emptyState: RisegEmptyState(
              title: l10n.reportesSinDatosTitulo,
              message: l10n.reportesPatrimonioDescuentosVacia,
            ),
            onRowTap: (r) => context.go('/personal/descuentos/${r.descuento!.id}'),
            columns: [
              RisegColumn<RenglonPatrimonio>(
                label: l10n.reportesPatrimonioDescuentoColumnaFolio,
                width: 110,
                cellBuilder: (r) => Text(r.descuento!.folio),
              ),
              RisegColumn<RenglonPatrimonio>(
                label: l10n.reportesPatrimonioColumnaEmpleado,
                width: 170,
                cellBuilder: (r) => Text(r.empleadoNombre, overflow: TextOverflow.ellipsis),
              ),
              RisegColumn<RenglonPatrimonio>(
                label: l10n.reportesPatrimonioDescuentoColumnaConcepto,
                width: 190,
                cellBuilder: (r) => Text(r.descuento!.descripcion ?? '—', overflow: TextOverflow.ellipsis),
              ),
              RisegColumn<RenglonPatrimonio>(
                label: l10n.reportesPatrimonioDescuentoColumnaOrigen,
                width: 190,
                cellBuilder: (r) => Text(r.bienDescripcion, overflow: TextOverflow.ellipsis),
              ),
              RisegColumn<RenglonPatrimonio>(
                label: l10n.reportesPatrimonioDescuentoColumnaOriginal,
                width: 120,
                alignment: TextAlign.right,
                cellBuilder: (r) => Text(formatoCentavosPago(r.importeDescuento)),
              ),
              RisegColumn<RenglonPatrimonio>(
                label: l10n.reportesPatrimonioDescuentoColumnaCuotas,
                width: 80,
                alignment: TextAlign.right,
                cellBuilder: (r) => Text('${r.cuotasDescuento}'),
              ),
              RisegColumn<RenglonPatrimonio>(
                label: l10n.reportesPatrimonioDescuentoColumnaAplicado,
                width: 120,
                alignment: TextAlign.right,
                cellBuilder: (r) => Text(formatoCentavosPago(r.aplicadoDescuento)),
              ),
              RisegColumn<RenglonPatrimonio>(
                label: l10n.reportesPatrimonioDescuentoColumnaPendiente,
                width: 120,
                alignment: TextAlign.right,
                cellBuilder: (r) => Text(
                  formatoCentavosPago(r.saldoDescuento),
                  style: AppTypography.bodyStrong.copyWith(
                    color: r.saldoDescuento > 0 ? colors.warning : colors.textPrimary,
                  ),
                ),
              ),
              RisegColumn<RenglonPatrimonio>(
                label: l10n.reportesPatrimonioDescuentoColumnaEstatus,
                width: 110,
                cellBuilder: (r) => Text(r.descuento!.estatus),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ranking compacto, no una gráfica: son seis cifras por servicio y una
/// tabla las comunica mejor que cualquier barra.
class _TablaServicios extends StatelessWidget {
  const _TablaServicios({required this.analisis});

  final AnalisisPatrimonio analisis;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.reportesPatrimonioServiciosTitulo,
            style: AppTypography.heading3.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.reportesPatrimonioServiciosPregunta,
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          RisegTableBase<ProblemaPorServicio>(
            rows: analisis.problemasPorServicio,
            emptyState: RisegEmptyState(
              title: l10n.reportesSinDatosTitulo,
              message: l10n.reportesPatrimonioServiciosVacia,
            ),
            // Sólo los renglones resueltos llevan a un servicio real:
            // "sin servicio" e "inconsistencia" no son entidades.
            onRowTap: (s) => s.servicioId == null ? null : context.go('/comercial/servicios/${s.servicioId}'),
            columns: [
              RisegColumn<ProblemaPorServicio>(
                label: l10n.reportesPatrimonioServicioColumnaNombre,
                width: 200,
                cellBuilder: (s) => s.estado == EstadoServicioHistorico.resuelto
                    ? Text(s.nombre!, overflow: TextOverflow.ellipsis)
                    : RisegStatusBadge(
                        label: etiquetaServicioRanking(l10n, s),
                        tone: tonoServicioHistorico(s.estado),
                      ),
              ),
              RisegColumn<ProblemaPorServicio>(
                label: l10n.reportesPatrimonioServicioColumnaBajas,
                width: 80,
                alignment: TextAlign.right,
                cellBuilder: (s) => Text('${s.bajas}'),
              ),
              RisegColumn<ProblemaPorServicio>(
                label: l10n.reportesPatrimonioServicioColumnaPendientes,
                width: 105,
                alignment: TextAlign.right,
                cellBuilder: (s) => Text(
                  '${s.pendientes}',
                  style: AppTypography.bodyStrong.copyWith(
                    color: s.pendientes > 0 ? colors.warning : colors.textPrimary,
                  ),
                ),
              ),
              RisegColumn<ProblemaPorServicio>(
                label: l10n.reportesPatrimonioServicioColumnaPerdidos,
                width: 95,
                alignment: TextAlign.right,
                cellBuilder: (s) => Text(
                  '${s.perdidos}',
                  style: AppTypography.bodyStrong.copyWith(
                    color: s.perdidos > 0 ? colors.error : colors.textPrimary,
                  ),
                ),
              ),
              RisegColumn<ProblemaPorServicio>(
                label: l10n.reportesPatrimonioServicioColumnaDescuentos,
                width: 130,
                alignment: TextAlign.right,
                cellBuilder: (s) => Text(formatoCentavosPago(s.importeDescuentos)),
              ),
              RisegColumn<ProblemaPorServicio>(
                label: l10n.reportesPatrimonioServicioColumnaAutorizadas,
                width: 110,
                alignment: TextAlign.right,
                cellBuilder: (s) => Text('${s.decisionesAutorizadas}'),
              ),
              RisegColumn<ProblemaPorServicio>(
                label: l10n.reportesPatrimonioServicioColumnaSinCobro,
                width: 100,
                alignment: TextAlign.right,
                cellBuilder: (s) => Text('${s.decisionesSinCobro}'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TablaAutorizadores extends StatelessWidget {
  const _TablaAutorizadores({required this.analisis});

  final AnalisisPatrimonio analisis;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.reportesPatrimonioAutorizacionesTitulo,
            style: AppTypography.heading3.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.reportesPatrimonioAutorizacionesPregunta,
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          RisegTableBase<ActividadAutorizador>(
            rows: analisis.autorizadores,
            emptyState: RisegEmptyState(
              title: l10n.reportesSinDatosTitulo,
              message: l10n.reportesPatrimonioAutorizacionesVacia,
            ),
            // Al expediente del administrativo, por empleadoId.
            onRowTap: (a) => context.go('/personal/empleados/${a.empleadoId}'),
            columns: [
              RisegColumn<ActividadAutorizador>(
                label: l10n.reportesPatrimonioAutorizadorColumnaNombre,
                width: 190,
                cellBuilder: (a) => Text(a.nombre, overflow: TextOverflow.ellipsis),
              ),
              RisegColumn<ActividadAutorizador>(
                label: l10n.reportesPatrimonioAutorizadorColumnaDecisiones,
                width: 110,
                alignment: TextAlign.right,
                cellBuilder: (a) => Text('${a.decisiones}'),
              ),
              RisegColumn<ActividadAutorizador>(
                label: l10n.reportesPatrimonioAutorizadorColumnaSinCobro,
                width: 110,
                alignment: TextAlign.right,
                cellBuilder: (a) => Text(
                  '${a.decisionesSinCobro}',
                  style: AppTypography.bodyStrong.copyWith(
                    color: a.decisionesSinCobro > 0 ? colors.warning : colors.textPrimary,
                  ),
                ),
              ),
              RisegColumn<ActividadAutorizador>(
                label: l10n.reportesPatrimonioAutorizadorColumnaImporte,
                width: 150,
                alignment: TextAlign.right,
                cellBuilder: (a) => Text(formatoCentavosPago(a.importeInvolucrado)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
