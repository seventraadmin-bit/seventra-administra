import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_compras_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_inventario_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_telefonia_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_vehiculos_usecase.dart';
import 'package:riseg_one/features/telefonia/presentation/equipo_telefonico_labels.dart' show estatusEquipoTelefonicoLabel;
import 'package:riseg_one/features/telefonia/presentation/linea_telefonica_labels.dart' show estatusLineaTelefonicaLabel;
import 'package:riseg_one/features/vehiculos/presentation/vehiculo_labels.dart' show estatusVehiculoLabel;

import '../widgets/reportes_filtro_bar.dart';
import 'reportes_operacion_controller.dart';

/// Pestaña Operación de Reportes (Etapa 12C) — 4 bloques compactos,
/// cada uno omitido por completo si falta su permiso. Nunca reconstruye
/// las pantallas de Inventario/Vehículos — enlaza a ellas.
class ReportesOperacionScreen extends ConsumerWidget {
  const ReportesOperacionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(reportesOperacionControllerProvider);
    final controller = ref.read(reportesOperacionControllerProvider.notifier);

    final sinNinguno = !controller.tieneCompras && !controller.tieneInventario && !controller.tieneVehiculos && !controller.tieneTelefonia;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(title: l10n.reportesOperacionTitulo, description: l10n.reportesOperacionDescripcion),
          const SizedBox(height: AppSpacing.md),
          ReportesFiltroBar(
            rangoInicio: state.rangoInicio,
            rangoFin: state.rangoFin,
            onRangoInicioChanged: (fecha) => controller.cambiarRango(rangoInicio: fecha, rangoFin: state.rangoFin),
            onRangoFinChanged: (fecha) => controller.cambiarRango(rangoInicio: state.rangoInicio, rangoFin: fecha),
          ),
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
              _SeccionCompras(l10n: l10n, resumen: state.resumenCompras!),
              const SizedBox(height: AppSpacing.xl),
            ],
            if (controller.tieneInventario && state.resumenInventario != null) ...[
              _SeccionInventario(l10n: l10n, resumen: state.resumenInventario!),
              const SizedBox(height: AppSpacing.xl),
            ],
            if (controller.tieneVehiculos && state.resumenVehiculos != null) ...[
              _SeccionVehiculos(l10n: l10n, resumen: state.resumenVehiculos!),
              const SizedBox(height: AppSpacing.xl),
            ],
            if (controller.tieneTelefonia && state.resumenTelefonia != null)
              _SeccionTelefonia(l10n: l10n, resumen: state.resumenTelefonia!),
          ],
        ],
      ),
    );
  }
}

class _SeccionCompras extends StatelessWidget {
  const _SeccionCompras({required this.l10n, required this.resumen});

  final AppLocalizations l10n;
  final ResumenComprasReportes resumen;

  @override
  Widget build(BuildContext context) {
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
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            RisegStatCard(label: l10n.reportesComprasTotal, value: formatoCentavosPago(resumen.totalComprado)),
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
      ],
    );
  }
}

class _SeccionInventario extends StatelessWidget {
  const _SeccionInventario({required this.l10n, required this.resumen});

  final AppLocalizations l10n;
  final ResumenInventarioReportes resumen;

  @override
  Widget build(BuildContext context) {
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
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            RisegStatCard(
              label: l10n.reportesInventarioExistencia,
              value: '${resumen.existenciaTotal}',
              delta: l10n.reportesGeneralIndicadorSnapshot,
              deltaTone: RisegStatusTone.neutral,
            ),
            RisegStatCard(label: l10n.reportesInventarioAsignaciones, value: '${resumen.asignacionesVigentes}'),
            RisegStatCard(label: l10n.reportesInventarioDanadosPerdidos, value: '${resumen.danadosPerdidos}'),
            RisegStatCard(label: l10n.reportesInventarioDescuentos, value: '${resumen.descuentosPendientes}'),
            RisegStatCard(label: l10n.reportesInventarioMovimientos, value: '${resumen.movimientosEnPeriodo}'),
            RisegStatCard(
              label: l10n.reportesInventarioValorAproximado,
              value: formatoCentavosPago(resumen.valorAproximado),
              delta: l10n.reportesInventarioValorAproximadoNota(resumen.articulosConValorExcluido),
              deltaTone: RisegStatusTone.neutral,
            ),
          ],
        ),
      ],
    );
  }
}

class _SeccionVehiculos extends StatelessWidget {
  const _SeccionVehiculos({required this.l10n, required this.resumen});

  final AppLocalizations l10n;
  final ResumenVehiculosReportes resumen;

  @override
  Widget build(BuildContext context) {
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
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final entrada in resumen.vehiculosPorEstatus.entries)
              RisegStatCard(
                label: estatusVehiculoLabel(l10n, entrada.key),
                value: '${entrada.value}',
                delta: l10n.reportesGeneralIndicadorSnapshot,
                deltaTone: RisegStatusTone.neutral,
              ),
            RisegStatCard(label: l10n.reportesVehiculosCostoMantenimiento, value: formatoCentavosPago(resumen.totalMantenimientoEnPeriodo)),
            RisegStatCard(label: l10n.reportesVehiculosCostoIncidencias, value: formatoCentavosPago(resumen.totalIncidenciasEnPeriodo)),
            RisegStatCard(
              label: l10n.reportesVehiculosMantenimientoProximo,
              value: '${resumen.mantenimientosProximos}',
              deltaTone: resumen.mantenimientosProximos == 0 ? null : RisegStatusTone.warning,
            ),
            RisegStatCard(
              label: l10n.reportesVehiculosMantenimientoVencido,
              value: '${resumen.mantenimientosVencidos}',
              deltaTone: resumen.mantenimientosVencidos == 0 ? null : RisegStatusTone.error,
            ),
            RisegStatCard(
              label: l10n.reportesVehiculosDocumentoProximo,
              value: '${resumen.documentosPorVencer}',
              deltaTone: resumen.documentosPorVencer == 0 ? null : RisegStatusTone.warning,
            ),
            RisegStatCard(
              label: l10n.reportesVehiculosDocumentoVencido,
              value: '${resumen.documentosVencidos}',
              deltaTone: resumen.documentosVencidos == 0 ? null : RisegStatusTone.error,
            ),
          ],
        ),
      ],
    );
  }
}

class _SeccionTelefonia extends StatelessWidget {
  const _SeccionTelefonia({required this.l10n, required this.resumen});

  final AppLocalizations l10n;
  final ResumenTelefoniaReportes resumen;

  @override
  Widget build(BuildContext context) {
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
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final entrada in resumen.equiposPorEstatus.entries)
              RisegStatCard(label: estatusEquipoTelefonicoLabel(l10n, entrada.key), value: '${entrada.value}'),
            for (final entrada in resumen.lineasPorEstatus.entries)
              RisegStatCard(label: estatusLineaTelefonicaLabel(l10n, entrada.key), value: '${entrada.value}'),
            RisegStatCard(label: l10n.reportesTelefoniaLineasSinEquipo, value: '${resumen.lineasSinEquipo}'),
            RisegStatCard(label: l10n.reportesTelefoniaLineasSinAsignacion, value: '${resumen.lineasSinAsignacion}'),
            RisegStatCard(label: l10n.reportesTelefoniaTotalRecargas, value: formatoCentavosPago(resumen.totalRecargasEnPeriodo)),
          ],
        ),
        if (resumen.recargasPorServicio.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(l10n.reportesTelefoniaRecargasPorServicio, style: AppTypography.heading3),
          const SizedBox(height: AppSpacing.sm),
          RisegTableBase<RecargaPorClave>(
            rows: resumen.recargasPorServicio,
            columns: [
              RisegColumn<RecargaPorClave>(label: l10n.reportesTelefoniaColumnaServicio, cellBuilder: (r) => Text(r.clave)),
              RisegColumn<RecargaPorClave>(
                label: l10n.reportesTelefoniaColumnaTotal,
                width: 140,
                alignment: TextAlign.right,
                cellBuilder: (r) => Text(formatoCentavosPago(r.total)),
              ),
            ],
          ),
        ],
        if (resumen.recargasPorEmpleado.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(l10n.reportesTelefoniaRecargasPorEmpleado, style: AppTypography.heading3),
          const SizedBox(height: AppSpacing.sm),
          RisegTableBase<RecargaPorClave>(
            rows: resumen.recargasPorEmpleado,
            columns: [
              RisegColumn<RecargaPorClave>(label: l10n.reportesTelefoniaColumnaEmpleado, cellBuilder: (r) => Text(r.clave)),
              RisegColumn<RecargaPorClave>(
                label: l10n.reportesTelefoniaColumnaTotal,
                width: 140,
                alignment: TextAlign.right,
                cellBuilder: (r) => Text(formatoCentavosPago(r.total)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
