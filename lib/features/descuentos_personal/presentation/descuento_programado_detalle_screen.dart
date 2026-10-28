import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/widgets/egreso_detalle_dialog.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart'
    show formatoCentavosPago;
import 'package:riseg_one/features/personal/personal_providers.dart';
import 'package:riseg_one/features/personal/presentation/empleados/empleados_list_screen.dart'
    show empleadoNombreCompleto;
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

import 'descuentos_personal_controller.dart';
import 'descuentos_personal_list_screen.dart'
    show
        descuentoProgramadoTipoLabel,
        descuentoProgramadoEstatusLabel,
        descuentoProgramadoEstatusTono;
import 'widgets/cancelar_saldo_descuento_programado_dialog.dart';
import 'widgets/corregir_descuento_programado_dialog.dart';
import 'widgets/eliminar_descuento_programado_fisicamente_dialog.dart';
import 'widgets/reprogramar_cuotas_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

String _cuotaEstatusLabel(AppLocalizations l10n, String estatus) {
  return switch (estatus) {
    'reservada' => l10n.descuentoProgramadoCuotaEstatusReservada,
    'aplicada' => l10n.descuentoProgramadoCuotaEstatusAplicada,
    'cancelada' => l10n.descuentoProgramadoCuotaEstatusCancelada,
    _ => l10n.descuentoProgramadoCuotaEstatusPendiente,
  };
}

String _movimientoLabel(AppLocalizations l10n, String tipo) {
  return switch (tipo) {
    'cuotaReservada' => l10n.descuentoProgramadoMovimientoCuotaReservada,
    'cuotaAplicada' => l10n.descuentoProgramadoMovimientoCuotaAplicada,
    'cuotaRevertida' => l10n.descuentoProgramadoMovimientoCuotaRevertida,
    'reprogramacion' => l10n.descuentoProgramadoMovimientoReprogramacion,
    'cancelacion' => l10n.descuentoProgramadoMovimientoCancelacion,
    'correccion' => l10n.descuentoProgramadoMovimientoCorreccion,
    _ => l10n.descuentoProgramadoMovimientoOtorgamiento,
  };
}

/// Origen financiero real del desembolso (Etapa "Cierre del ciclo
/// financiero de Descuentos Programados") — Cuenta-only (préstamo no
/// admite TDC, ver el plan de esa etapa), resuelto por FK real
/// (`egresoId → Egreso.cuentaFinancieraId → CuentaFinanciera.nombre`),
/// nunca por texto. `null` (sin `egresoId`) cuando el descuento es una
/// recuperación de un costo ya pagado en otro módulo (ej. botas) — no
/// es un caso de error, es el comportamiento esperado.
class _OrigenFinancieroTexto extends ConsumerWidget {
  const _OrigenFinancieroTexto({required this.egresoId});

  final String? egresoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    if (egresoId == null) {
      return Text(
        l10n.descuentoProgramadoDetalleOrigenNoEspecificado,
        style: AppTypography.caption.copyWith(color: context.colors.textMuted),
      );
    }
    return InkWell(
      key: const Key('descuento_programado_boton_ver_origen'),
      onTap: () => showDialog<void>(context: context, builder: (_) => EgresoDetalleDialog(egresoId: egresoId!)),
      child: FutureBuilder<CuentaFinancieraData?>(
        future: () async {
          final egreso = await ref.read(egresoRepositoryProvider).obtenerPorId(egresoId!);
          if (egreso?.cuentaFinancieraId == null) return null;
          return ref.read(cuentaFinancieraRepositoryProvider).obtenerPorId(egreso!.cuentaFinancieraId!);
        }(),
        builder: (context, snapshot) {
          final cuenta = snapshot.data;
          return Text(
            cuenta?.nombre ?? l10n.descuentoProgramadoDetalleOrigenNoEspecificado,
            style: AppTypography.caption.copyWith(color: context.colors.accentText, decoration: TextDecoration.underline),
          );
        },
      ),
    );
  }
}

/// Expediente de un descuento programado (Etapa 15) — folio, saldo,
/// plan de pagos completo (✓/○ por cuota, con folio de Nómina cuando
/// ya se aplicó) e historial cronológico — auditable de punta a punta.
class DescuentoProgramadoDetalleScreen extends ConsumerWidget {
  const DescuentoProgramadoDetalleScreen({
    required this.descuentoProgramadoId,
    super.key,
  });

  final String descuentoProgramadoId;

  Future<void> _eliminarFisicamente(BuildContext context, WidgetRef ref) async {
    final eliminado =
        await mostrarDialogoEliminarDescuentoProgramadoFisicamente(
          context,
          ref,
          descuentoProgramadoId,
        );
    if (!eliminado) return;
    // Pop primero: este `context` viene de un `FutureBuilder` interno
    // que vuelve a construirse (y podría desmontarse) en cuanto se
    // invalida el provider más abajo — invalidar antes arriesgaría
    // saltarse el `pop` por un `context.mounted` ya falso.
    if (context.mounted) context.pop();
    ref.invalidate(descuentosPersonalControllerProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final notifier = ref.read(descuentosPersonalControllerProvider.notifier);
    // Se re-observa el controlador global para reaccionar a invalidaciones
    // tras reprogramar/cancelar (mismo criterio que `NominaDetalleScreen`).
    ref.watch(descuentosPersonalControllerProvider);
    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;

    return FutureBuilder<DescuentoProgramadoEmpleadoData?>(
      future: notifier.obtenerPorId(descuentoProgramadoId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final descuento = snapshot.data;
        if (descuento == null) {
          return RisegEmptyState(
            icon: Icons.error_outline,
            title: l10n.descuentoProgramadoDetalleNoExiste,
            message: '',
          );
        }

        return Scaffold(
          appBar: AppBar(title: Text(descuento.folio)),
          body: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: RisegSectionHeader(
                          title: descuentoProgramadoTipoLabel(
                            l10n,
                            descuento.tipo,
                          ),
                        ),
                      ),
                      RisegStatusBadge(
                        label: descuentoProgramadoEstatusLabel(
                          l10n,
                          descuento.estatus,
                        ),
                        tone: descuentoProgramadoEstatusTono(descuento.estatus),
                      ),
                      if (esMaestro && descuento.estatus == 'cancelado') ...[
                        const SizedBox(width: AppSpacing.sm),
                        RisegActionsMenu(
                          menuKey: const Key(
                            'descuento_programado_detalle_menu_acciones',
                          ),
                          actions: [
                            RisegMenuAction(
                              key: const Key(
                                'descuento_programado_boton_eliminar_fisicamente',
                              ),
                              label: l10n.eliminacionFisicaAccionMenu,
                              icon: Icons.delete_forever_outlined,
                              destructive: true,
                              onTap: () => _eliminarFisicamente(context, ref),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // Navegación cruzada (Etapa 17): el folio identifica el
                  // descuento, pero el empleado es la identidad principal
                  // — un enlace real hacia su expediente (`empleadoId` es
                  // FK real, nunca inferido).
                  FutureBuilder<EmpleadoData?>(
                    future: ref
                        .read(empleadoRepositoryProvider)
                        .obtenerPorId(descuento.empleadoId),
                    builder: (context, empleadoSnapshot) {
                      final empleado = empleadoSnapshot.data;
                      if (empleado == null) return const SizedBox.shrink();
                      return InkWell(
                        key: const Key(
                          'descuento_programado_boton_ver_empleado',
                        ),
                        onTap:
                            () => context.push(
                              '/personal/empleados/${empleado.id}',
                            ),
                        child: Text(
                          '${empleadoNombreCompleto(empleado)} · ${l10n.personalActivoNumeroEmpleado(empleado.numeroEmpleado)}',
                          style: AppTypography.body.copyWith(
                            color: context.colors.accentText,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Text('${l10n.descuentoProgramadoDetalleOrigenFinanciero}: ', style: AppTypography.caption.copyWith(color: context.colors.textMuted)),
                      Expanded(child: _OrigenFinancieroTexto(egresoId: descuento.egresoId)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FutureBuilder<List<DescuentoProgramadoCuotaData>>(
                    future: notifier.listarCuotas(descuentoProgramadoId),
                    builder: (context, statsCuotasSnapshot) {
                      final cuotasParaStats =
                          statsCuotasSnapshot.data ??
                          const <DescuentoProgramadoCuotaData>[];
                      final reservado = cuotasParaStats
                          .where((c) => c.estatus == 'reservada')
                          .fold<int>(0, (s, c) => s + c.importeProgramado);
                      return Wrap(
                        spacing: AppSpacing.md,
                        runSpacing: AppSpacing.md,
                        children: [
                          SizedBox(
                            width: 220,
                            child: RisegStatCard(
                              label:
                                  l10n.descuentoProgramadoDetalleImporteOriginal,
                              value: formatoCentavosPago(
                                descuento.importeOriginal,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: RisegStatCard(
                              label: l10n.descuentoProgramadoDetalleRecuperado,
                              value: formatoCentavosPago(
                                descuento.importeOriginal -
                                    descuento.saldoPendiente,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: RisegStatCard(
                              label: l10n.descuentoProgramadoDetalleReservado,
                              value: formatoCentavosPago(reservado),
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: RisegStatCard(
                              label: l10n.descuentoProgramadoDetalleSaldo,
                              value: formatoCentavosPago(
                                descuento.saldoPendiente,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  if (descuento.estatus == 'activo') ...[
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        RisegButton(
                          key: const Key('descuento_programado_boton_corregir'),
                          label: l10n.descuentoProgramadoDetalleBotonCorregir,
                          variant: RisegButtonVariant.secondary,
                          onPressed:
                              () => mostrarDialogoCorregirDescuentoProgramado(
                                context,
                                ref,
                                descuento,
                              ),
                        ),
                        RisegButton(
                          key: const Key(
                            'descuento_programado_boton_reprogramar',
                          ),
                          label:
                              l10n.descuentoProgramadoDetalleBotonReprogramar,
                          variant: RisegButtonVariant.secondary,
                          onPressed:
                              () => mostrarDialogoReprogramarCuotas(
                                context,
                                ref,
                                descuento,
                              ),
                        ),
                        RisegButton(
                          key: const Key('descuento_programado_boton_cancelar'),
                          label: l10n.descuentoProgramadoDetalleBotonCancelar,
                          variant: RisegButtonVariant.secondary,
                          onPressed:
                              () =>
                                  mostrarDialogoCancelarSaldoDescuentoProgramado(
                                    context,
                                    ref,
                                    descuento,
                                  ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    l10n.descuentoProgramadoDetallePlanDePagos,
                    style: AppTypography.heading3,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FutureBuilder<List<DescuentoProgramadoCuotaData>>(
                    future: notifier.listarCuotas(descuentoProgramadoId),
                    builder: (context, cuotasSnapshot) {
                      final cuotas =
                          cuotasSnapshot.data ??
                          const <DescuentoProgramadoCuotaData>[];
                      if (cuotas.isEmpty) return const SizedBox.shrink();
                      return RisegCard(
                        child: Column(
                          children: [
                            for (final cuota in cuotas)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.xs,
                                ),
                                // `Wrap` (no `Row`) — hallazgo real de la
                                // pasada Etapa 17: con icono+número+fecha+
                                // importe+badge en un `Row` rígido, un
                                // ancho angosto (~500px) producía
                                // RenderFlex overflow; nunca se había
                                // probado antes en un breakpoint estrecho.
                                child: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: AppSpacing.sm,
                                  runSpacing: AppSpacing.xs,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          cuota.estatus == 'aplicada'
                                              ? Icons.check_circle
                                              : Icons.circle_outlined,
                                          size: AppSizes.iconSm,
                                          color:
                                              cuota.estatus == 'aplicada'
                                                  ? Colors.green
                                                  : null,
                                        ),
                                        const SizedBox(width: AppSpacing.xs),
                                        Text(
                                          l10n.descuentoProgramadoDetalleCuotaNumero(
                                            cuota.numeroCuota,
                                            cuotas.length,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      _formatoFecha.format(
                                        cuota.fechaProgramada,
                                      ),
                                    ),
                                    Text(
                                      formatoCentavosPago(
                                        cuota.importeProgramado,
                                      ),
                                    ),
                                    RisegStatusBadge(
                                      label: _cuotaEstatusLabel(
                                        l10n,
                                        cuota.estatus,
                                      ),
                                      tone:
                                          cuota.estatus == 'aplicada'
                                              ? RisegStatusTone.success
                                              : cuota.estatus == 'cancelada'
                                              ? RisegStatusTone.neutral
                                              : RisegStatusTone.info,
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    l10n.descuentoProgramadoDetalleHistorial,
                    style: AppTypography.heading3,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FutureBuilder<List<DescuentoProgramadoMovimientoData>>(
                    future: notifier.listarMovimientos(descuentoProgramadoId),
                    builder: (context, movSnapshot) {
                      final movimientos =
                          movSnapshot.data ??
                          const <DescuentoProgramadoMovimientoData>[];
                      if (movimientos.isEmpty) return const SizedBox.shrink();
                      return RisegCard(
                        child: Column(
                          children: [
                            for (final m in movimientos)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.xs,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _movimientoLabel(
                                              l10n,
                                              m.tipoMovimiento,
                                            ),
                                            style: AppTypography.body,
                                          ),
                                          if (m.observacion != null)
                                            Text(
                                              m.observacion!,
                                              style: AppTypography.caption,
                                            ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      _formatoFechaHora.format(m.fechaHora),
                                      style: AppTypography.caption,
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
