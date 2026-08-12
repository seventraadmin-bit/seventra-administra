import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/permissions/permission_service.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;
import 'package:riseg_one/features/inventario/presentation/movimiento_tipo_label.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import 'dashboard_controller.dart';
import 'dashboard_state.dart';

/// Pantalla inicial dinámica por permisos (Etapa 13) — 3 zonas:
/// Requiere atención (prioridad visual, primero), Resumen, Actividad
/// reciente. Cada tarjeta se omite por completo si su sección llegó en
/// `null` — nunca un hueco vacío ni un placeholder.
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
          else ...[
            _SeccionAtencion(l10n: l10n, state: state),
            const SizedBox(height: AppSpacing.xl),
            _SeccionResumen(l10n: l10n, state: state),
            const SizedBox(height: AppSpacing.xl),
            _SeccionActividad(l10n: l10n, state: state),
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
          RisegEmptyState(
            icon: Icons.check_circle_outline,
            title: l10n.dashboardSinPendientesTitulo,
            message: l10n.dashboardSinPendientesMensaje,
          )
        else
          Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.md, children: tarjetas),
      ],
    );
  }
}

class _SeccionResumen extends StatelessWidget {
  const _SeccionResumen({required this.l10n, required this.state});

  final AppLocalizations l10n;
  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final general = state.resumenGeneral;
    final personal = state.resumenPersonal;
    final inventario = state.resumenInventario;
    final telefonia = state.resumenTelefonia;

    final tarjetas = <Widget>[
      if (general?.totalIngresos != null)
        RisegStatCard(label: l10n.reportesGeneralIngresos, value: formatoCentavosPago(general!.totalIngresos!), icon: Icons.trending_up),
      if (general?.totalEgresos != null)
        RisegStatCard(label: l10n.reportesGeneralEgresos, value: formatoCentavosPago(general!.totalEgresos!), icon: Icons.trending_down),
      if (general?.resultadoOperativo != null)
        RisegStatCard(
          label: l10n.reportesGeneralResultadoOperativo,
          value: formatoCentavosPago(general!.resultadoOperativo!),
          icon: Icons.balance,
          deltaTone: general.resultadoOperativo! >= 0 ? RisegStatusTone.success : RisegStatusTone.error,
        ),
      if (general?.totalComprasPeriodo != null)
        RisegStatCard(
          label: l10n.reportesGeneralCompras,
          value: formatoCentavosPago(general!.totalComprasPeriodo!),
          delta: l10n.reportesGeneralIndicadorInformativo,
          deltaTone: RisegStatusTone.neutral,
        ),
      if (general?.totalNominaPagadaPeriodo != null)
        RisegStatCard(
          label: l10n.reportesGeneralNominaPagada,
          value: formatoCentavosPago(general!.totalNominaPagadaPeriodo!),
          delta: l10n.reportesGeneralIndicadorInformativo,
          deltaTone: RisegStatusTone.neutral,
        ),
      if (personal != null)
        RisegStatCard(label: l10n.reportesGeneralPersonalActivo, value: '${personal.totalActivos}', icon: Icons.people_outline),
      if (general?.serviciosActivosActual != null)
        RisegStatCard(label: l10n.reportesGeneralServiciosActivos, value: '${general!.serviciosActivosActual}', icon: Icons.handshake_outlined),
      if (inventario != null) ...[
        RisegStatCard(label: l10n.reportesInventarioExistencia, value: '${inventario.existenciaTotal}'),
        RisegStatCard(label: l10n.reportesInventarioAsignaciones, value: '${inventario.asignacionesVigentes}'),
      ],
      if (telefonia != null)
        RisegStatCard(label: l10n.dashboardResumenLineasActivas, value: '${telefonia.lineasPorEstatus['activa'] ?? 0}'),
    ];

    if (tarjetas.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.dashboardSeccionResumen, style: AppTypography.heading2),
        const SizedBox(height: AppSpacing.sm),
        Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.md, children: tarjetas),
      ],
    );
  }
}

class _SeccionActividad extends StatelessWidget {
  const _SeccionActividad({required this.l10n, required this.state});

  final AppLocalizations l10n;
  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final listas = <Widget>[];

    final compras = state.actividad?.comprasRecientes;
    if (compras != null) {
      listas.add(_MiniLista(
        titulo: l10n.dashboardActividadCompras,
        filas: [
          for (final c in compras)
            _FilaActividad('${c.folioCompra} · ${c.proveedor ?? '—'}', _fechaCorta(c.fecha), onTap: () => context.go('/compras/${c.id}')),
        ],
      ));
    }

    final pagos = state.actividad?.pagosRecientes;
    if (pagos != null) {
      listas.add(_MiniLista(
        titulo: l10n.dashboardActividadPagos,
        filas: [for (final p in pagos) _FilaActividad('${p.pago.folioPago} · ${p.clienteNombre}', formatoCentavosPago(p.pago.montoTotal))],
      ));
    }

    final personal = state.resumenPersonal;
    if (personal != null) {
      final altas = [...personal.altasEnPeriodo]..sort((a, b) => b.fechaIngreso.compareTo(a.fechaIngreso));
      final bajas = [...personal.bajasEnPeriodo]..sort((a, b) => b.fechaBaja.compareTo(a.fechaBaja));
      listas.add(_MiniLista(
        titulo: l10n.dashboardActividadAltas,
        filas: [for (final e in altas.take(3)) _FilaActividad(e.nombreCompleto, _fechaCorta(e.fechaIngreso))],
      ));
      listas.add(_MiniLista(
        titulo: l10n.dashboardActividadBajas,
        filas: [for (final b in bajas.take(3)) _FilaActividad(b.nombreCompleto, _fechaCorta(b.fechaBaja))],
      ));
    }

    final movimientos = state.actividad?.movimientosRecientes;
    if (movimientos != null) {
      listas.add(_MiniLista(
        titulo: l10n.dashboardActividadMovimientos,
        filas: [
          for (final m in movimientos)
            _FilaActividad('${m.articuloNombre} · ${movimientoTipoLabel(l10n, m.movimiento.tipoMovimiento)}', '${m.movimiento.cantidad}'),
        ],
      ));
    }

    final nomina = state.resumenNomina;
    if (nomina != null) {
      final nominas = [...nomina.nominas]..sort((a, b) => b.nomina.fechaFinPeriodo.compareTo(a.nomina.fechaFinPeriodo));
      listas.add(_MiniLista(
        titulo: l10n.dashboardActividadNominas,
        filas: [
          for (final n in nominas.take(5))
            _FilaActividad(n.nomina.folio, formatoCentavosPago(n.totalGenerado), onTap: () => context.go('/personal/nomina/${n.nomina.id}')),
        ],
      ));
    }

    final vehiculos = state.resumenVehiculos;
    if (vehiculos != null) {
      final mantenimientos = [...vehiculos.detalleMantenimientos]..sort((a, b) => b.registro.fecha.compareTo(a.registro.fecha));
      listas.add(_MiniLista(
        titulo: l10n.dashboardActividadMantenimientos,
        filas: [for (final m in mantenimientos.take(5)) _FilaActividad(m.vehiculoLabel, _fechaCorta(m.registro.fecha))],
      ));
    }

    final recargas = state.actividad?.recargasRecientes;
    if (recargas != null) {
      listas.add(_MiniLista(
        titulo: l10n.dashboardActividadRecargas,
        filas: [for (final r in recargas) _FilaActividad(r.lineaCodigo, formatoCentavosPago(r.recarga.importe))],
      ));
    }

    if (listas.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.dashboardSeccionActividad, style: AppTypography.heading2),
        const SizedBox(height: AppSpacing.sm),
        Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.md, children: listas),
      ],
    );
  }

  String _fechaCorta(DateTime fecha) =>
      '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
}

class _FilaActividad {
  const _FilaActividad(this.titulo, this.valor, {this.onTap});
  final String titulo;
  final String valor;
  final VoidCallback? onTap;
}

class _MiniLista extends StatelessWidget {
  const _MiniLista({required this.titulo, required this.filas});

  final String titulo;
  final List<_FilaActividad> filas;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: RisegCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: AppTypography.heading3),
            const SizedBox(height: AppSpacing.sm),
            if (filas.isEmpty)
              Text(AppLocalizations.of(context)!.dashboardActividadSinRegistros, style: AppTypography.caption)
            else
              for (final fila in filas)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                  child: InkWell(
                    onTap: fila.onTap,
                    child: Row(
                      children: [
                        Expanded(child: Text(fila.titulo, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: AppSpacing.sm),
                        Text(fila.valor),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
