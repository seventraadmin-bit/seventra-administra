import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;
import 'package:riseg_one/features/inventario/presentation/articulo_unidad_labels.dart';
import 'package:riseg_one/features/reportes/domain/export/exportar_reporte_resultado.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_compras_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_inventario_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_telefonia_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_vehiculos_usecase.dart';
import 'package:riseg_one/features/reportes/reportes_providers.dart';
import 'package:riseg_one/features/telefonia/presentation/equipo_telefonico_labels.dart' show estatusEquipoTelefonicoLabel;
import 'package:riseg_one/features/telefonia/presentation/linea_telefonica_labels.dart' show estatusLineaTelefonicaLabel;
import 'package:riseg_one/features/vehiculos/presentation/vehiculo_labels.dart' show estatusVehiculoLabel;

import '../widgets/analitica_labels.dart';
import '../widgets/construir_contexto_exportacion.dart';
import '../widgets/paneles_analiticos.dart';
import '../widgets/reporte_export_button.dart';
import '../widgets/reportes_filtro_bar.dart';
import 'reportes_operacion_controller.dart';
import 'reportes_operacion_state.dart';

/// Pestaña Operación de Reportes — cuatro bloques, cada uno omitido por
/// completo si falta su permiso. Nunca reconstruye las pantallas de
/// Inventario/Vehículos: enlaza a ellas.
class ReportesOperacionScreen extends ConsumerWidget {
  const ReportesOperacionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(reportesOperacionControllerProvider);
    final controller = ref.read(reportesOperacionControllerProvider.notifier);

    final sinNinguno =
        !controller.tieneCompras && !controller.tieneInventario && !controller.tieneVehiculos && !controller.tieneTelefonia;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(title: l10n.reportesOperacionTitulo, description: l10n.reportesOperacionDescripcion),
          const SizedBox(height: AppSpacing.md),
          const ReportesFiltroBar(),
          const SizedBox(height: AppSpacing.lg),
          if (state.cargando)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (state.errorCarga != null)
            RisegEmptyState(icon: Icons.error_outline, title: l10n.reportesErrorCargaTitulo, message: state.errorCarga!)
          else if (sinNinguno)
            RisegEmptyState(
              icon: Icons.lock_outline,
              title: l10n.reportesSinSeccionesTitulo,
              message: l10n.reportesSinSeccionesMensaje,
            )
          else ...[
            if (controller.tieneCompras && state.resumenCompras != null) ...[
              _SeccionCompras(
                resumen: state.resumenCompras!,
                onExportar: () => _exportarCompras(context, ref, l10n, state, state.resumenCompras!),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
            if (controller.tieneInventario && state.resumenInventario != null) ...[
              _SeccionInventario(resumen: state.resumenInventario!),
              const SizedBox(height: AppSpacing.xl),
            ],
            if (controller.tieneVehiculos && state.resumenVehiculos != null) ...[
              _SeccionVehiculos(
                resumen: state.resumenVehiculos!,
                onExportar: () => _exportarVehiculos(context, ref, l10n, state, state.resumenVehiculos!),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
            if (controller.tieneTelefonia && state.resumenTelefonia != null)
              _SeccionTelefonia(
                resumen: state.resumenTelefonia!,
                onExportar: () => _exportarTelefonia(context, ref, l10n, state, state.resumenTelefonia!),
              ),
          ],
        ],
      ),
    );
  }
}

Future<void> _exportarCompras(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
  ReportesOperacionState state,
  ResumenComprasReportes resumen,
) async {
  final contexto = construirContextoExportacion(
    ref,
    nombreReporte: l10n.reportesNombreComprasPeriodo,
    rangoInicio: state.rangoInicio,
    rangoFin: state.rangoFin,
  );
  final resultado =
      await ref.read(exportarComprasPeriodoXlsxUseCaseProvider).ejecutar(contexto: contexto, resumen: resumen);
  if (!context.mounted) return;
  switch (resultado) {
    case ExportarReporteExitoso():
      RisegFeedback.showSuccess(context, l10n.reportesExportoExito);
    case ExportarReporteErrorInesperado():
      RisegFeedback.showError(context, l10n.reportesExportoError);
  }
}

Future<void> _exportarVehiculos(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
  ReportesOperacionState state,
  ResumenVehiculosReportes resumen,
) async {
  final contexto = construirContextoExportacion(
    ref,
    nombreReporte: l10n.reportesNombreVehiculosMantenimiento,
    rangoInicio: state.rangoInicio,
    rangoFin: state.rangoFin,
  );
  final resultado =
      await ref.read(exportarVehiculosMantenimientoXlsxUseCaseProvider).ejecutar(contexto: contexto, resumen: resumen);
  if (!context.mounted) return;
  switch (resultado) {
    case ExportarReporteExitoso():
      RisegFeedback.showSuccess(context, l10n.reportesExportoExito);
    case ExportarReporteErrorInesperado():
      RisegFeedback.showError(context, l10n.reportesExportoError);
  }
}

Future<void> _exportarTelefonia(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
  ReportesOperacionState state,
  ResumenTelefoniaReportes resumen,
) async {
  final contexto = construirContextoExportacion(
    ref,
    nombreReporte: l10n.reportesNombreTelefoniaRecargas,
    rangoInicio: state.rangoInicio,
    rangoFin: state.rangoFin,
  );
  final resultado =
      await ref.read(exportarTelefoniaRecargasXlsxUseCaseProvider).ejecutar(contexto: contexto, resumen: resumen);
  if (!context.mounted) return;
  switch (resultado) {
    case ExportarReporteExitoso():
      RisegFeedback.showSuccess(context, l10n.reportesExportoExito);
    case ExportarReporteErrorInesperado():
      RisegFeedback.showError(context, l10n.reportesExportoError);
  }
}

class _SeccionCompras extends StatelessWidget {
  const _SeccionCompras({required this.resumen, required this.onExportar});

  final ResumenComprasReportes resumen;
  final Future<void> Function() onExportar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final proveedores = resumen.porProveedor.take(6).toList();
    final altoFila = alturaDeFila([
      RisegCompositionChart.alturaPara(2), // inventario + gasto directo
      RisegCompositionChart.alturaPara(proveedores.length),
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegSectionHeader(
          title: l10n.reportesComprasSeccionTitulo,
          primaryAction: RisegButton(
            label: l10n.reportesVerCompras,
            variant: RisegButtonVariant.ghost,
            onPressed: () => context.go('/compras'),
          ),
          secondaryAction: ReporteExportButton(
            label: l10n.reportesExportarExcel,
            icon: Icons.grid_on_outlined,
            onExportar: onExportar,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        RisegKpiGrid(
          maxColumnas: 4,
          children: [
            RisegStatCard(
              label: l10n.reportesComprasTotal,
              value: formatoCentavosPago(resumen.totalComprado),
              icon: Icons.shopping_cart_outlined,
            ),
            RisegStatCard(label: l10n.reportesComprasInventario, value: formatoCentavosPago(resumen.totalInventario)),
            RisegStatCard(label: l10n.reportesComprasGastoDirecto, value: formatoCentavosPago(resumen.totalGastoDirecto)),
            RisegStatCard(
              label: l10n.reportesComprasCanceladas,
              value: formatoCentavosPago(resumen.totalCanceladas),
              delta: l10n.reportesGeneralIndicadorInformativo,
              deltaTone: RisegStatusTone.neutral,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        FilaPaneles(
          paneles: [
            PanelAnalitico(
              minAncho: 300,
              child: RisegChartCard(
                title: l10n.reportesComprasDestinoTitulo,
                subtitle: l10n.reportesComprasDestinoPregunta,
                height: altoFila,
                vacio: resumen.totalComprado == 0,
                mensajeVacio: l10n.reportesComprasDestinoVacia,
                iconoVacio: Icons.shopping_cart_outlined,
                child: RisegCompositionChart(
                  total: resumen.totalComprado,
                  formatoValor: formatoCentavosPago,
                  items: [
                    RisegComposicionItem(
                      label: l10n.reportesComprasInventario,
                      valor: resumen.totalInventario,
                      color: colors.info,
                    ),
                    RisegComposicionItem(
                      label: l10n.reportesComprasGastoDirecto,
                      valor: resumen.totalGastoDirecto,
                      color: colors.accent,
                    ),
                  ],
                ),
              ),
            ),
            PanelAnalitico(
              minAncho: 300,
              child: RisegChartCard(
                title: l10n.reportesComprasProveedoresTitulo,
                subtitle: l10n.reportesComprasProveedoresPregunta,
                height: altoFila,
                vacio: proveedores.isEmpty,
                mensajeVacio: l10n.reportesComprasProveedoresVacia,
                iconoVacio: Icons.store_outlined,
                child: RisegCompositionChart(
                  total: resumen.totalComprado,
                  formatoValor: formatoCentavosPago,
                  items: [
                    for (final (indice, proveedor) in proveedores.indexed)
                      RisegComposicionItem(
                        label: proveedor.clave,
                        valor: proveedor.total,
                        color: context.colorCategorico(indice),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SeccionInventario extends StatelessWidget {
  const _SeccionInventario({required this.resumen});

  final ResumenInventarioReportes resumen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    final porEstatus = resumen.unidadesPorEstatus.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalUnidades = porEstatus.fold<int>(0, (a, e) => a + e.value);
    final altoFila = alturaDeFila([
      RisegCompositionChart.alturaPara(porEstatus.length),
      alturaCifraDestacada,
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegSectionHeader(
          title: l10n.reportesInventarioSeccionTitulo,
          primaryAction: RisegButton(
            label: l10n.reportesVerInventarioCompleto,
            variant: RisegButtonVariant.ghost,
            onPressed: () => context.go('/inventario/reportes'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        RisegKpiGrid(
          children: [
            // El delta dice de qué universo habla esta cifra. No
            // coincide con el panel de estados de abajo —y no tiene por
            // qué—: aquí se suman también los artículos por cantidad, y
            // `ExistenciaArticulo.total` deja fuera las unidades dadas de
            // baja, que el panel sí muestra. Lo que está en
            // lavandería/reparación SÍ cuenta en ambos desde la
            // corrección semántica de existencia.
            RisegStatCard(
              label: l10n.reportesInventarioExistencia,
              value: '${resumen.existenciaTotal}',
              icon: Icons.inventory_2_outlined,
              delta: l10n.reportesInventarioExistenciaNota,
              deltaTone: RisegStatusTone.neutral,
            ),
            RisegStatCard(
              label: l10n.reportesInventarioAsignaciones,
              value: '${resumen.asignacionesVigentes}',
              icon: Icons.assignment_ind_outlined,
            ),
            RisegStatCard(
              label: l10n.reportesInventarioDanadosPerdidos,
              value: '${resumen.danadosPerdidos}',
              deltaTone: resumen.danadosPerdidos == 0 ? null : RisegStatusTone.warning,
            ),
            RisegStatCard(label: l10n.reportesInventarioDescuentos, value: '${resumen.descuentosPendientes}'),
            RisegStatCard(
              label: l10n.reportesInventarioValorAproximado,
              value: formatoCentavosPago(resumen.valorAproximado),
              delta: l10n.reportesInventarioValorAproximadoNota(resumen.articulosConValorExcluido),
              deltaTone: RisegStatusTone.neutral,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        FilaPaneles(
          paneles: [
            PanelAnalitico(
              flex: 3,
              minAncho: 340,
              child: RisegChartCard(
                title: l10n.reportesInventarioEstadosTitulo,
                subtitle: l10n.reportesInventarioEstadosPregunta,
                height: altoFila,
                vacio: porEstatus.isEmpty,
                mensajeVacio: l10n.reportesInventarioEstadosVacia,
                iconoVacio: Icons.inventory_2_outlined,
                trailing: Text(
                  '$totalUnidades',
                  style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
                ),
                child: RisegCompositionChart(
                  total: totalUnidades,
                  formatoValor: formatoCantidad,
                  items: [
                    for (final entrada in porEstatus)
                      RisegComposicionItem(
                        label: estatusArticuloUnidadLabel(l10n, entrada.key),
                        valor: entrada.value,
                        color: colorEstatusUnidad(context, entrada.key),
                      ),
                  ],
                ),
              ),
            ),
            PanelAnalitico(
              flex: 2,
              minAncho: 260,
              child: RisegChartCard(
                title: l10n.reportesInventarioMovimientos,
                subtitle: l10n.reportesOperacionDescripcion,
                height: altoFila,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${resumen.movimientosEnPeriodo}',
                      style: AppTypography.heading1.copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      l10n.reportesInventarioMovimientos,
                      style: AppTypography.caption.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SeccionVehiculos extends StatelessWidget {
  const _SeccionVehiculos({required this.resumen, required this.onExportar});

  final ResumenVehiculosReportes resumen;
  final Future<void> Function() onExportar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final flotilla = resumen.vehiculosPorEstatus.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final totalFlotilla = flotilla.fold<int>(0, (a, e) => a + e.value);

    final alertas = <Widget>[
      if (resumen.mantenimientosVencidos > 0)
        RenglonHecho(
          texto: '${l10n.reportesVehiculosMantenimientoVencido}: ${resumen.mantenimientosVencidos}',
          tono: RisegStatusTone.error,
          icono: Icons.build_circle_outlined,
        ),
      if (resumen.documentosVencidos > 0)
        RenglonHecho(
          texto: '${l10n.reportesVehiculosDocumentoVencido}: ${resumen.documentosVencidos}',
          tono: RisegStatusTone.error,
          icono: Icons.description_outlined,
        ),
      if (resumen.mantenimientosProximos > 0)
        RenglonHecho(
          texto: '${l10n.reportesVehiculosMantenimientoProximo}: ${resumen.mantenimientosProximos}',
          tono: RisegStatusTone.warning,
          icono: Icons.build_outlined,
        ),
      if (resumen.documentosPorVencer > 0)
        RenglonHecho(
          texto: '${l10n.reportesVehiculosDocumentoProximo}: ${resumen.documentosPorVencer}',
          tono: RisegStatusTone.warning,
          icono: Icons.event_outlined,
        ),
    ];

    final altoFila = alturaDeFila([
      RisegCompositionChart.alturaPara(flotilla.length),
      alturaRenglonesHecho(alertas.length),
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegSectionHeader(
          title: l10n.reportesVehiculosSeccionTitulo,
          primaryAction: RisegButton(
            label: l10n.reportesVerVehiculos,
            variant: RisegButtonVariant.ghost,
            onPressed: () => context.go('/vehiculos/flotilla'),
          ),
          secondaryAction: ReporteExportButton(
            label: l10n.reportesExportarExcel,
            icon: Icons.grid_on_outlined,
            onExportar: onExportar,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        RisegKpiGrid(
          maxColumnas: 3,
          children: [
            RisegStatCard(
              label: l10n.reportesVehiculosCostoMantenimiento,
              value: formatoCentavosPago(resumen.totalMantenimientoEnPeriodo),
              icon: Icons.build_outlined,
            ),
            RisegStatCard(
              label: l10n.reportesVehiculosCostoIncidencias,
              value: formatoCentavosPago(resumen.totalIncidenciasEnPeriodo),
              icon: Icons.car_crash_outlined,
            ),
            RisegStatCard(
              label: l10n.reportesVehiculosFlotillaTotal,
              value: '$totalFlotilla',
              icon: Icons.directions_car_outlined,
              delta: l10n.reportesGeneralIndicadorSnapshot,
              deltaTone: RisegStatusTone.neutral,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        FilaPaneles(
          paneles: [
            PanelAnalitico(
              minAncho: 300,
              child: RisegChartCard(
                title: l10n.reportesVehiculosFlotillaTitulo,
                subtitle: l10n.reportesVehiculosFlotillaPregunta,
                height: altoFila,
                vacio: flotilla.isEmpty,
                mensajeVacio: l10n.reportesVehiculosFlotillaVacia,
                iconoVacio: Icons.directions_car_outlined,
                child: RisegCompositionChart(
                  total: totalFlotilla,
                  formatoValor: formatoCantidad,
                  items: [
                    for (final (indice, entrada) in flotilla.indexed)
                      RisegComposicionItem(
                        label: estatusVehiculoLabel(l10n, entrada.key),
                        valor: entrada.value,
                        color: context.colorCategorico(indice),
                      ),
                  ],
                ),
              ),
            ),
            PanelAnalitico(
              minAncho: 280,
              child: RisegChartCard(
                title: l10n.reportesVehiculosAlertasTitulo,
                subtitle: l10n.reportesVehiculosAlertasPregunta,
                height: altoFila,
                vacio: alertas.isEmpty,
                mensajeVacio: l10n.reportesVehiculosAlertasNinguna,
                iconoVacio: Icons.check_circle_outline,
                child: ListView(padding: EdgeInsets.zero, children: alertas),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SeccionTelefonia extends StatelessWidget {
  const _SeccionTelefonia({required this.resumen, required this.onExportar});

  final ResumenTelefoniaReportes resumen;
  final Future<void> Function() onExportar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    final lineas = resumen.lineasPorEstatus.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final equipos = resumen.equiposPorEstatus.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final totalLineas = lineas.fold<int>(0, (a, e) => a + e.value);
    final totalEquipos = equipos.fold<int>(0, (a, e) => a + e.value);

    // Utilización sobre el MISMO universo que cuenta `lineasSinAsignacion`
    // (todas las líneas, activas o no) — no se recorta el denominador
    // para que el porcentaje se vea mejor.
    final conAsignacion = totalLineas - resumen.lineasSinAsignacion;
    final utilizacion = totalLineas == 0 ? null : (conAsignacion / totalLineas) * 100;

    final altoFila = alturaDeFila([
      alturaCifraDestacada + alturaDatosCompactos(1),
      RisegCompositionChart.alturaPara(lineas.length),
      RisegCompositionChart.alturaPara(equipos.length),
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegSectionHeader(
          title: l10n.reportesTelefoniaSeccionTitulo,
          primaryAction: RisegButton(
            label: l10n.reportesVerTelefonia,
            variant: RisegButtonVariant.ghost,
            onPressed: () => context.go('/telefonia/equipos'),
          ),
          secondaryAction: ReporteExportButton(
            label: l10n.reportesExportarExcel,
            icon: Icons.grid_on_outlined,
            onExportar: onExportar,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        RisegKpiGrid(
          maxColumnas: 4,
          children: [
            RisegStatCard(
              label: l10n.reportesTelefoniaTotalRecargas,
              value: formatoCentavosPago(resumen.totalRecargasEnPeriodo),
              icon: Icons.sim_card_outlined,
            ),
            RisegStatCard(
              label: l10n.reportesTelefoniaLineasAsignadas,
              value: '$conAsignacion',
              icon: Icons.person_pin_outlined,
            ),
            RisegStatCard(
              label: l10n.reportesTelefoniaLineasSinAsignacion,
              value: '${resumen.lineasSinAsignacion}',
              deltaTone: resumen.lineasSinAsignacion == 0 ? null : RisegStatusTone.warning,
            ),
            RisegStatCard(
              label: l10n.reportesTelefoniaLineasSinEquipo,
              value: '${resumen.lineasSinEquipo}',
              deltaTone: resumen.lineasSinEquipo == 0 ? null : RisegStatusTone.warning,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        FilaPaneles(
          paneles: [
            PanelAnalitico(
              minAncho: 260,
              child: RisegChartCard(
                title: l10n.reportesTelefoniaUtilizacionTitulo,
                subtitle: l10n.reportesTelefoniaUtilizacionPregunta,
                height: altoFila,
                vacio: utilizacion == null,
                mensajeVacio: l10n.reportesTelefoniaUtilizacionVacia,
                iconoVacio: Icons.sim_card_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      l10n.reportesTelefoniaUtilizacionPorcentaje('${(utilizacion ?? 0).toStringAsFixed(0)} %'),
                      style: AppTypography.heading2.copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    RisegProgressBar(
                      porcentaje: utilizacion ?? 0,
                      tone: (utilizacion ?? 0) >= 80 ? RisegStatusTone.success : RisegStatusTone.warning,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DatoCompacto(
                      etiqueta: l10n.reportesTelefoniaLineasConEquipo,
                      valor: '${totalLineas - resumen.lineasSinEquipo}',
                    ),
                  ],
                ),
              ),
            ),
            PanelAnalitico(
              minAncho: 280,
              child: RisegChartCard(
                title: l10n.reportesTelefoniaEstadoLineasTitulo,
                subtitle: l10n.reportesTelefoniaEstadoLineasPregunta,
                height: altoFila,
                vacio: lineas.isEmpty,
                mensajeVacio: l10n.reportesTelefoniaEstadoVacia,
                iconoVacio: Icons.sim_card_outlined,
                child: RisegCompositionChart(
                  total: totalLineas,
                  formatoValor: formatoCantidad,
                  items: [
                    for (final (indice, entrada) in lineas.indexed)
                      RisegComposicionItem(
                        label: estatusLineaTelefonicaLabel(l10n, entrada.key),
                        valor: entrada.value,
                        color: context.colorCategorico(indice),
                      ),
                  ],
                ),
              ),
            ),
            PanelAnalitico(
              minAncho: 280,
              child: RisegChartCard(
                title: l10n.reportesTelefoniaEstadoEquiposTitulo,
                subtitle: l10n.reportesTelefoniaEstadoEquiposPregunta,
                height: altoFila,
                vacio: equipos.isEmpty,
                mensajeVacio: l10n.reportesTelefoniaEstadoVacia,
                iconoVacio: Icons.smartphone_outlined,
                child: RisegCompositionChart(
                  total: totalEquipos,
                  formatoValor: formatoCantidad,
                  items: [
                    for (final (indice, entrada) in equipos.indexed)
                      RisegComposicionItem(
                        label: estatusEquipoTelefonicoLabel(l10n, entrada.key),
                        valor: entrada.value,
                        color: context.colorCategorico(indice),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (resumen.recargasPorServicio.isNotEmpty || resumen.recargasPorEmpleado.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          FilaPaneles(
            paneles: [
              if (resumen.recargasPorServicio.isNotEmpty)
                PanelAnalitico(
                  minAncho: 320,
                  child: _TablaRecargas(
                    titulo: l10n.reportesTelefoniaRecargasPorServicio,
                    etiquetaClave: l10n.reportesTelefoniaColumnaServicio,
                    filas: resumen.recargasPorServicio,
                  ),
                ),
              if (resumen.recargasPorEmpleado.isNotEmpty)
                PanelAnalitico(
                  minAncho: 320,
                  child: _TablaRecargas(
                    titulo: l10n.reportesTelefoniaRecargasPorEmpleado,
                    etiquetaClave: l10n.reportesTelefoniaColumnaEmpleado,
                    filas: resumen.recargasPorEmpleado,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _TablaRecargas extends StatelessWidget {
  const _TablaRecargas({required this.titulo, required this.etiquetaClave, required this.filas});

  final String titulo;
  final String etiquetaClave;
  final List<RecargaPorClave> filas;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(titulo, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          RisegTableBase<RecargaPorClave>(
            rows: filas,
            emptyState: RisegEmptyState(title: l10n.reportesSinDatosTitulo, message: l10n.reportesSinDatosMensaje),
            columns: [
              RisegColumn<RecargaPorClave>(label: etiquetaClave, cellBuilder: (r) => Text(r.clave)),
              RisegColumn<RecargaPorClave>(
                label: l10n.reportesTelefoniaColumnaTotal,
                width: 130,
                alignment: TextAlign.right,
                cellBuilder: (r) => Text(formatoCentavosPago(r.total)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
