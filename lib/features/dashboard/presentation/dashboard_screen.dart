import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/permissions/permission_service.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;
import 'package:riseg_one/features/inventario/presentation/movimiento_tipo_label.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import 'dashboard_controller.dart';
import 'dashboard_state.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Pantalla inicial dinámica por permisos (Etapa 13, rediseño visual
/// Etapa 15) — centro de control: Requiere atención (compacto cuando no
/// hay pendientes), zona financiera con jerarquía real (Resultado
/// operativo por encima de Ingresos/Egresos), indicadores operativos
/// compactos, y una sola Actividad reciente unificada en vez de 8
/// tarjetas fragmentadas. Cada zona se omite por completo si no tiene
/// contenido real que mostrar — nunca un hueco vacío ni una cifra
/// inventada (sin datos históricos para comparar contra el periodo
/// anterior hoy, así que ninguna tendencia se muestra).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(dashboardControllerProvider);
    final permissionService = ref.watch(permissionServiceProvider);

    final huboAlgunaCarga = state.resumenGeneral != null ||
        state.resumenPersonal != null ||
        state.resumenNomina != null ||
        state.resumenInventario != null ||
        state.resumenVehiculos != null ||
        state.resumenTelefonia != null;

    final secciones = <Widget>[
      _SeccionAtencion(l10n: l10n, state: state),
      if (_construirFinanciera(context, l10n, state) case final w?) w,
      if (_construirIndicadores(context, l10n, state) case final w?) w,
      if (_construirActividad(context, l10n, state) case final w?) w,
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        key: const Key('dashboard_screen'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.dashboardTitulo,
            description: l10n.dashboardDescripcion,
            primaryAction: _AccesosRapidos(l10n: l10n, permissionService: permissionService),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (state.cargando && !huboAlgunaCarga)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (state.errorCarga != null)
            RisegEmptyState(icon: Icons.error_outline, title: l10n.reportesErrorCargaTitulo, message: state.errorCarga!)
          else
            for (var i = 0; i < secciones.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.xl),
              secciones[i],
            ],
        ],
      ),
    );
  }
}

class _AccesosRapidos extends StatelessWidget {
  const _AccesosRapidos({required this.l10n, required this.permissionService});

  final AppLocalizations l10n;
  final PermissionService permissionService;

  @override
  Widget build(BuildContext context) {
    final botones = <Widget>[
      if (permissionService.hasCode('personal.crear'))
        RisegButton(
          label: l10n.dashboardAccesoAltaPersonal,
          variant: RisegButtonVariant.secondary,
          size: RisegButtonSize.compact,
          icon: Icons.person_add_outlined,
          onPressed: () => context.go('/personal/empleados'),
        ),
      if (permissionService.hasCode('compras.crear'))
        RisegButton(
          label: l10n.dashboardAccesoRegistrarCompra,
          variant: RisegButtonVariant.secondary,
          size: RisegButtonSize.compact,
          icon: Icons.shopping_cart_outlined,
          onPressed: () => context.go('/compras/nueva'),
        ),
      if (permissionService.hasCode('nomina.crear'))
        RisegButton(
          label: l10n.dashboardAccesoGenerarNomina,
          variant: RisegButtonVariant.secondary,
          size: RisegButtonSize.compact,
          icon: Icons.payments_outlined,
          onPressed: () => context.go('/personal/nomina'),
        ),
      if (permissionService.hasCode('inventario.ver'))
        RisegButton(
          label: l10n.dashboardAccesoInventario,
          variant: RisegButtonVariant.ghost,
          size: RisegButtonSize.compact,
          icon: Icons.inventory_2_outlined,
          onPressed: () => context.go('/inventario/articulos'),
        ),
    ];

    if (botones.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: botones);
  }
}

class _SeccionAtencion extends StatelessWidget {
  const _SeccionAtencion({required this.l10n, required this.state});

  final AppLocalizations l10n;
  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tarjetas = <Widget>[];

    final cxc = state.alertas?.cxcVencida;
    if (cxc != null && cxc.cantidadCuentas > 0) {
      tarjetas.add(RisegStatCard(
        label: l10n.dashboardAlertaCxcVencida,
        value: l10n.dashboardAlertaCxcVencidaDetalle(cxc.cantidadCuentas, formatoCentavosPago(cxc.montoTotal)),
        icon: Icons.receipt_long_outlined,
        deltaTone: RisegStatusTone.error,
        onTap: () => context.go('/finanzas/cuentas-por-cobrar'),
      ));
    }

    final nomina = state.resumenNomina;
    if (nomina != null && nomina.totalPendienteGlobal > 0) {
      tarjetas.add(RisegStatCard(
        label: l10n.dashboardAlertaNominaPendiente,
        value: formatoCentavosPago(nomina.totalPendienteGlobal),
        icon: Icons.pending_actions_outlined,
        deltaTone: RisegStatusTone.warning,
        onTap: () => context.go('/personal/nomina'),
      ));
    }

    final inventario = state.resumenInventario;
    if (inventario != null && inventario.descuentosPendientes > 0) {
      tarjetas.add(RisegStatCard(
        label: l10n.dashboardAlertaDescuentosPendientes,
        value: '${inventario.descuentosPendientes}',
        icon: Icons.remove_circle_outline,
        deltaTone: RisegStatusTone.warning,
        onTap: () => context.go('/inventario/articulos'),
      ));
    }
    if (inventario != null && inventario.danadosPerdidos > 0) {
      tarjetas.add(RisegStatCard(
        label: l10n.dashboardAlertaInventarioDanado,
        value: '${inventario.danadosPerdidos}',
        icon: Icons.report_problem_outlined,
        deltaTone: RisegStatusTone.error,
        onTap: () => context.go('/inventario/articulos'),
      ));
    }

    final empleadosBajaConPendiente = state.alertas?.empleadosBajaConPendiente;
    if (empleadosBajaConPendiente != null && empleadosBajaConPendiente.isNotEmpty) {
      tarjetas.add(RisegStatCard(
        label: l10n.dashboardAlertaEmpleadosBajaPendiente,
        value: '${empleadosBajaConPendiente.length}',
        icon: Icons.person_off_outlined,
        deltaTone: RisegStatusTone.error,
        onTap: () => context.go('/personal/empleados'),
      ));
    }

    final vehiculos = state.resumenVehiculos;
    if (vehiculos != null && vehiculos.mantenimientosVencidos > 0) {
      tarjetas.add(RisegStatCard(
        label: l10n.dashboardAlertaMantenimientoVencido,
        value: '${vehiculos.mantenimientosVencidos}',
        icon: Icons.build_outlined,
        deltaTone: RisegStatusTone.error,
        onTap: () => context.go('/vehiculos/alertas'),
      ));
    }
    if (vehiculos != null && vehiculos.mantenimientosProximos > 0) {
      tarjetas.add(RisegStatCard(
        label: l10n.dashboardAlertaMantenimientoProximo,
        value: '${vehiculos.mantenimientosProximos}',
        icon: Icons.build_outlined,
        deltaTone: RisegStatusTone.warning,
        onTap: () => context.go('/vehiculos/alertas'),
      ));
    }
    if (vehiculos != null && vehiculos.documentosVencidos > 0) {
      tarjetas.add(RisegStatCard(
        label: l10n.dashboardAlertaDocumentoVencido,
        value: '${vehiculos.documentosVencidos}',
        icon: Icons.description_outlined,
        deltaTone: RisegStatusTone.error,
        onTap: () => context.go('/vehiculos/alertas'),
      ));
    }
    if (vehiculos != null && vehiculos.documentosPorVencer > 0) {
      tarjetas.add(RisegStatCard(
        label: l10n.dashboardAlertaDocumentoProximo,
        value: '${vehiculos.documentosPorVencer}',
        icon: Icons.description_outlined,
        deltaTone: RisegStatusTone.warning,
        onTap: () => context.go('/vehiculos/alertas'),
      ));
    }

    final telefonia = state.resumenTelefonia;
    final lineasSuspendidas = telefonia?.lineasPorEstatus['suspendida'] ?? 0;
    if (telefonia != null && lineasSuspendidas > 0) {
      tarjetas.add(RisegStatCard(
        label: l10n.dashboardAlertaLineasSuspendidas,
        value: '$lineasSuspendidas',
        icon: Icons.phonelink_erase_outlined,
        deltaTone: RisegStatusTone.warning,
        onTap: () => context.go('/telefonia/lineas'),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.dashboardSeccionAtencion, style: AppTypography.heading2),
        const SizedBox(height: AppSpacing.sm),
        if (tarjetas.isEmpty)
          // Estado compacto — una sola fila, nunca la zona vacía grande
          // de antes (Etapa 15, hallazgo real de Marlon).
          RisegCard(
            variant: RisegCardVariant.subtle,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, size: AppSizes.iconMd, color: colors.success),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.dashboardSinPendientesTitulo, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
                      Text(l10n.dashboardSinPendientesMensaje, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.md, children: tarjetas),
      ],
    );
  }
}

/// `null` cuando no hay ningún dato financiero autorizado que mostrar —
/// el llamador la omite por completo (nunca una sección vacía).
Widget? _construirFinanciera(BuildContext context, AppLocalizations l10n, DashboardState state) {
  final general = state.resumenGeneral;
  if (general == null) return null;

  final resultado = general.resultadoOperativo;
  final ingresos = general.totalIngresos;
  final egresos = general.totalEgresos;
  final compras = general.totalComprasPeriodo;
  final nominaPagada = general.totalNominaPagadaPeriodo;
  if (resultado == null && ingresos == null && egresos == null && compras == null && nominaPagada == null) {
    return null;
  }

  final colors = context.colors;
  final positivo = (resultado ?? 0) >= 0;
  final tono = positivo ? colors.success : colors.error;
  final tonoBg = positivo ? colors.successBg : colors.errorBg;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(l10n.dashboardSeccionResumen, style: AppTypography.heading2),
      const SizedBox(height: AppSpacing.sm),
      RisegCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (resultado != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(color: tonoBg, shape: BoxShape.circle),
                    child: Icon(Icons.account_balance_outlined, size: AppSizes.iconMd, color: tono),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.reportesGeneralResultadoOperativo,
                          style: AppTypography.label.copyWith(color: colors.textMuted),
                        ),
                        Text(
                          formatoCentavosPago(resultado),
                          style: AppTypography.heading1.copyWith(color: tono),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            if (ingresos != null || egresos != null) ...[
              if (resultado != null) ...[
                const SizedBox(height: AppSpacing.md),
                Divider(height: 1, color: colors.borderSubtle),
                const SizedBox(height: AppSpacing.md),
              ],
              Row(
                children: [
                  if (ingresos != null)
                    Expanded(
                      child: _MetricaFinancieraSecundaria(
                        icon: Icons.trending_up,
                        label: l10n.reportesGeneralIngresos,
                        valor: formatoCentavosPago(ingresos),
                      ),
                    ),
                  if (ingresos != null && egresos != null) const SizedBox(width: AppSpacing.lg),
                  if (egresos != null)
                    Expanded(
                      child: _MetricaFinancieraSecundaria(
                        icon: Icons.trending_down,
                        label: l10n.reportesGeneralEgresos,
                        valor: formatoCentavosPago(egresos),
                      ),
                    ),
                ],
              ),
            ],
            if (compras != null || nominaPagada != null) ...[
              const SizedBox(height: AppSpacing.md),
              Divider(height: 1, color: colors.borderSubtle),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xl,
                runSpacing: AppSpacing.xs,
                children: [
                  if (compras != null)
                    _MetricaFinancieraTerciaria(label: l10n.reportesGeneralCompras, valor: formatoCentavosPago(compras)),
                  if (nominaPagada != null)
                    _MetricaFinancieraTerciaria(label: l10n.reportesGeneralNominaPagada, valor: formatoCentavosPago(nominaPagada)),
                ],
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

class _MetricaFinancieraSecundaria extends StatelessWidget {
  const _MetricaFinancieraSecundaria({required this.icon, required this.label, required this.valor});

  final IconData icon;
  final String label;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Icon(icon, size: AppSizes.iconSm, color: colors.textMuted),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: AppTypography.label.copyWith(color: colors.textMuted)),
              Text(valor, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricaFinancieraTerciaria extends StatelessWidget {
  const _MetricaFinancieraTerciaria({required this.label, required this.valor});

  final String label;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label · $valor', style: AppTypography.body.copyWith(color: colors.textPrimary)),
        Text(
          AppLocalizations.of(context)!.reportesGeneralIndicadorInformativo,
          style: AppTypography.caption.copyWith(color: colors.textMuted),
        ),
      ],
    );
  }
}

/// `null` cuando ningún indicador operativo está autorizado.
Widget? _construirIndicadores(BuildContext context, AppLocalizations l10n, DashboardState state) {
  final general = state.resumenGeneral;
  final personal = state.resumenPersonal;
  final inventario = state.resumenInventario;
  final telefonia = state.resumenTelefonia;

  final chips = <Widget>[
    if (personal != null)
      _ChipIndicador(icon: Icons.people_outline, label: l10n.reportesGeneralPersonalActivo, valor: '${personal.totalActivos}'),
    if (general?.serviciosActivosActual != null)
      _ChipIndicador(
        icon: Icons.handshake_outlined,
        label: l10n.reportesGeneralServiciosActivos,
        valor: '${general!.serviciosActivosActual}',
      ),
    if (inventario != null)
      _ChipIndicador(
        icon: Icons.inventory_2_outlined,
        label: l10n.reportesInventarioExistencia,
        valor: '${inventario.existenciaTotal}',
      ),
    if (inventario != null)
      _ChipIndicador(
        icon: Icons.assignment_turned_in_outlined,
        label: l10n.reportesInventarioAsignaciones,
        valor: '${inventario.asignacionesVigentes}',
      ),
    if (telefonia != null)
      _ChipIndicador(
        icon: Icons.phone_iphone_outlined,
        label: l10n.dashboardResumenLineasActivas,
        valor: '${telefonia.lineasPorEstatus['activa'] ?? 0}',
      ),
  ];

  if (chips.isEmpty) return null;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(l10n.dashboardSeccionIndicadores, style: AppTypography.heading2),
      const SizedBox(height: AppSpacing.sm),
      Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: chips),
    ],
  );
}

class _ChipIndicador extends StatelessWidget {
  const _ChipIndicador({required this.icon, required this.label, required this.valor});

  final IconData icon;
  final String label;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 172),
      child: RisegCard(
        variant: RisegCardVariant.subtle,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppSizes.iconMd, color: colors.accentText),
            const SizedBox(width: AppSpacing.xs),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(valor, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                Text(label, style: AppTypography.caption.copyWith(color: colors.textMuted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Un renglón de la Actividad reciente unificada — presentación pura,
/// nunca persistida (Etapa 15: sustituye 8 mini-listas fragmentadas por
/// una sola lista ordenada). `fecha` es siempre la única precisión real
/// disponible en el dominio de origen (nunca se inventa una hora).
class _ActividadItem {
  const _ActividadItem({
    required this.icon,
    required this.titulo,
    required this.detalle,
    required this.fecha,
    this.valor,
    this.onTap,
  });

  final IconData icon;
  final String titulo;
  final String detalle;
  final DateTime fecha;
  final String? valor;
  final VoidCallback? onTap;
}

/// `null` cuando ninguna fuente de actividad está autorizada.
Widget? _construirActividad(BuildContext context, AppLocalizations l10n, DashboardState state) {
  final huboAlgunaFuente = state.actividad != null || state.resumenPersonal != null ||
      state.resumenNomina != null || state.resumenVehiculos != null;
  if (!huboAlgunaFuente) return null;

  final items = <_ActividadItem>[];

  for (final c in state.actividad?.comprasRecientes ?? const []) {
    items.add(_ActividadItem(
      icon: Icons.shopping_cart_outlined,
      titulo: l10n.dashboardActividadItemCompra,
      detalle: '${c.folioCompra} · ${c.proveedor ?? '—'}',
      fecha: c.fecha,
      onTap: () => context.go('/compras/${c.id}'),
    ));
  }
  for (final p in state.actividad?.pagosRecientes ?? const []) {
    items.add(_ActividadItem(
      icon: Icons.payments_outlined,
      titulo: l10n.dashboardActividadItemPago,
      detalle: '${p.pago.folioPago} · ${p.clienteNombre}',
      fecha: p.pago.fechaPago,
      valor: formatoCentavosPago(p.pago.montoTotal),
    ));
  }
  for (final m in state.actividad?.movimientosRecientes ?? const []) {
    items.add(_ActividadItem(
      icon: Icons.swap_horiz_outlined,
      titulo: movimientoTipoLabel(l10n, m.movimiento.tipoMovimiento),
      detalle: m.articuloNombre,
      fecha: m.movimiento.fecha,
      valor: '${m.movimiento.cantidad}',
    ));
  }
  for (final e in state.resumenPersonal?.altasEnPeriodo ?? const []) {
    items.add(_ActividadItem(
      icon: Icons.person_add_outlined,
      titulo: l10n.dashboardActividadItemAltaPersonal,
      detalle: e.nombreCompleto,
      fecha: e.fechaIngreso,
      onTap: () => context.go('/personal/empleados/${e.id}'),
    ));
  }
  for (final b in state.resumenPersonal?.bajasEnPeriodo ?? const []) {
    items.add(_ActividadItem(
      icon: Icons.person_off_outlined,
      titulo: l10n.dashboardActividadItemBajaPersonal,
      detalle: b.nombreCompleto,
      fecha: b.fechaBaja,
      onTap: () => context.go('/personal/empleados/${b.empleadoId}'),
    ));
  }
  for (final n in state.resumenNomina?.nominas ?? const []) {
    items.add(_ActividadItem(
      icon: Icons.badge_outlined,
      titulo: l10n.dashboardActividadItemNomina,
      detalle: n.nomina.folio,
      fecha: n.nomina.fechaFinPeriodo,
      valor: formatoCentavosPago(n.totalGenerado),
      onTap: () => context.go('/personal/nomina/${n.nomina.id}'),
    ));
  }
  for (final m in state.resumenVehiculos?.detalleMantenimientos ?? const []) {
    items.add(_ActividadItem(
      icon: Icons.build_outlined,
      titulo: l10n.dashboardActividadItemMantenimiento,
      detalle: m.vehiculoLabel,
      fecha: m.registro.fecha,
    ));
  }
  for (final r in state.actividad?.recargasRecientes ?? const []) {
    items.add(_ActividadItem(
      icon: Icons.sim_card_outlined,
      titulo: l10n.dashboardActividadItemRecarga,
      detalle: r.lineaCodigo,
      fecha: r.recarga.fecha,
      valor: formatoCentavosPago(r.recarga.importe),
    ));
  }

  items.sort((a, b) => b.fecha.compareTo(a.fecha));

  final colors = context.colors;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(l10n.dashboardSeccionActividad, style: AppTypography.heading2),
      const SizedBox(height: AppSpacing.sm),
      if (items.isEmpty)
        Text(l10n.dashboardActividadVacia, style: AppTypography.body.copyWith(color: colors.textMuted))
      else
        RisegCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) Divider(height: 1, color: colors.borderSubtle),
                _FilaActividadUnificada(item: items[i]),
              ],
            ],
          ),
        ),
    ],
  );
}

class _FilaActividadUnificada extends StatelessWidget {
  const _FilaActividadUnificada({required this.item});

  final _ActividadItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fila = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(item.icon, size: AppSizes.iconMd, color: colors.textMuted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.titulo, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
                Text(
                  item.detalle,
                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.valor != null) Text(item.valor!, style: AppTypography.data.copyWith(color: colors.textPrimary)),
              Text(_formatoFecha.format(item.fecha), style: AppTypography.caption.copyWith(color: colors.textMuted)),
            ],
          ),
        ],
      ),
    );

    if (item.onTap == null) return fila;
    return InkWell(onTap: item.onTap, child: fila);
  }
}
