import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formaPagoLabel, formatoCentavosPago;
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/personal/personal_providers.dart';
import 'package:riseg_one/features/personal/presentation/empleados/empleados_list_screen.dart' show empleadoNombreCompleto;
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

import '../data/repositories/vacante_cobertura_reader.dart';
import '../data/tables/tiempo_extra_table.dart';
import '../tiempos_extra_providers.dart';
import 'tiempos_extra_controller.dart';
import 'widgets/cancelar_tiempo_extra_dialog.dart';
import 'widgets/eliminar_tiempo_extra_fisicamente_dialog.dart';
import 'widgets/registrar_tiempo_extra_dialog.dart';
import 'widgets/tiempo_extra_labels.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Trazabilidad del origen financiero (Etapa "origen financiero
/// unificado") — resuelto por FK real (`Egreso.cuentaFinancieraId` o
/// `Deuda.id` directo), nunca por texto de concepto. `null` cuando la
/// fila es histórica y nunca capturó un origen estructurado.
typedef _OrigenResuelto = ({String nombre, String ruta})?;

Future<_OrigenResuelto> _resolverOrigenFinanciero(WidgetRef ref, {String? egresoId, String? deudaId}) async {
  if (deudaId != null) {
    final deuda = await ref.read(deudaRepositoryProvider).obtenerPorId(deudaId);
    if (deuda == null) return null;
    return (nombre: deuda.nombre, ruta: '/finanzas/deudas-y-credito/${deuda.id}');
  }
  if (egresoId != null) {
    final egreso = await ref.read(egresoRepositoryProvider).obtenerPorId(egresoId);
    if (egreso?.cuentaFinancieraId == null) return null;
    final cuenta = await ref.read(cuentaFinancieraRepositoryProvider).obtenerPorId(egreso!.cuentaFinancieraId!);
    if (cuenta == null) return null;
    return (nombre: cuenta.nombre, ruta: '/finanzas/cuentas-financieras/${cuenta.id}');
  }
  return null;
}

/// Widget compartido: resuelve y muestra el origen financiero de un
/// ítem (pago base o costo adicional) — nunca reimplementado por
/// separado para cada uno.
/// Qué se cubrió, según el origen (§21): el titular que faltó, la
/// plaza vacante, o el motivo escrito a mano. Cada origen muestra SÓLO
/// lo suyo — nunca un "—" donde el campo simplemente no aplica.
class _ContextoOrigen extends ConsumerWidget {
  const _ContextoOrigen({required this.tiempoExtra});

  final TiempoExtraData tiempoExtra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final origen = OrigenCoberturaTiempoExtra.values.asNameMap()[tiempoExtra.origenCobertura];

    switch (origen) {
      case OrigenCoberturaTiempoExtra.ausenciaEmpleado:
        final empleadoId = tiempoExtra.empleadoAusenteId;
        if (empleadoId == null) return const SizedBox.shrink();
        return FutureBuilder<EmpleadoData?>(
          future: ref.read(empleadoRepositoryProvider).obtenerPorId(empleadoId),
          builder: (context, snapshot) {
            final empleado = snapshot.data;
            if (empleado == null) return const SizedBox.shrink();
            return InkWell(
              key: const Key('tiempo_extra_boton_ver_empleado_ausente'),
              onTap: () => context.push('/personal/empleados/${empleado.id}'),
              child: Text(
                l10n.tiempoExtraDetalleAusenteDe(empleadoNombreCompleto(empleado)),
                style: AppTypography.body
                    .copyWith(color: context.colors.accentText, decoration: TextDecoration.underline),
              ),
            );
          },
        );

      case OrigenCoberturaTiempoExtra.vacante:
        final vacanteId = tiempoExtra.vacanteOperativaId;
        if (vacanteId == null) return const SizedBox.shrink();
        // Se resuelve incluso si la vacante ya se cubrió después: el
        // histórico tiene que seguir diciendo qué plaza cubrió.
        return FutureBuilder<VacanteCobertura?>(
          future: ref.read(vacanteCoberturaReaderProvider).porId(vacanteId),
          builder: (context, snapshot) {
            final vacante = snapshot.data;
            if (vacante == null) return const SizedBox.shrink();
            return Column(
              key: const Key('tiempo_extra_contexto_vacante'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${l10n.tiempoExtraDetalleVacanteCubierta}: ${vacante.etiqueta}',
                  style: AppTypography.body,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  l10n.tiempoExtraDetalleVacanteEsTemporal,
                  style: AppTypography.caption.copyWith(color: context.colors.textMuted),
                ),
              ],
            );
          },
        );

      case OrigenCoberturaTiempoExtra.otro:
        final descripcion = tiempoExtra.descripcionOrigen;
        if (descripcion == null) return const SizedBox.shrink();
        return Text(
          '${l10n.tiempoExtraDetalleMotivoCobertura}: $descripcion',
          key: const Key('tiempo_extra_contexto_otro'),
          style: AppTypography.body,
        );

      case null:
        return const SizedBox.shrink();
    }
  }
}

class _OrigenFinancieroTexto extends ConsumerWidget {
  const _OrigenFinancieroTexto({this.egresoId, this.deudaId});

  final String? egresoId;
  final String? deudaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<_OrigenResuelto>(
      future: _resolverOrigenFinanciero(ref, egresoId: egresoId, deudaId: deudaId),
      builder: (context, snapshot) {
        final origen = snapshot.data;
        if (origen == null) {
          return Text(l10n.tiempoExtraDetalleOrigenNoEspecificado, style: AppTypography.caption.copyWith(color: context.colors.textMuted));
        }
        return InkWell(
          onTap: () => context.push(origen.ruta),
          child: Text(
            origen.nombre,
            style: AppTypography.caption.copyWith(color: context.colors.accentText, decoration: TextDecoration.underline),
          ),
        );
      },
    );
  }
}

/// Diff "antes → después" de un evento `corregido` (Etapa "corrección
/// real de Tiempo Extra") — `estadoAnterior`/`estadoNuevo` son JSON con
/// SOLO los campos que cambiaron (ver `TiempoExtraRepositoryImpl.
/// corregir`). `null`/vacío en eventos `registrado`/`cancelado`
/// preexistentes — no se muestra nada en ese caso.
class _DiffCorreccion extends StatelessWidget {
  const _DiffCorreccion({required this.estadoAnterior, required this.estadoNuevo});

  final String? estadoAnterior;
  final String? estadoNuevo;

  @override
  Widget build(BuildContext context) {
    if (estadoAnterior == null || estadoNuevo == null) return const SizedBox.shrink();
    Map<String, dynamic> antes;
    Map<String, dynamic> despues;
    try {
      antes = jsonDecode(estadoAnterior!) as Map<String, dynamic>;
      despues = jsonDecode(estadoNuevo!) as Map<String, dynamic>;
    } catch (_) {
      return const SizedBox.shrink();
    }
    if (antes.isEmpty && despues.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final campo in antes.keys)
            Text('$campo: ${antes[campo]} → ${despues[campo]}', style: AppTypography.caption),
        ],
      ),
    );
  }
}

/// Expediente de una cobertura de Tiempo Extra — folio, montos, costos
/// adicionales, historial, cancelar. Mismo patrón que
/// `DescuentoProgramadoDetalleScreen` (`Scaffold`/`AppBar` propio para
/// la flecha de regreso automática).
class TiempoExtraDetalleScreen extends ConsumerWidget {
  const TiempoExtraDetalleScreen({required this.tiempoExtraId, super.key});

  final String tiempoExtraId;

  Future<void> _cancelar(BuildContext context, WidgetRef ref) async {
    final cancelado = await mostrarDialogoCancelarTiempoExtra(context, ref, tiempoExtraId);
    if (!cancelado) return;
    if (context.mounted) context.pop();
  }

  Future<void> _editar(BuildContext context, WidgetRef ref, TiempoExtraData tiempoExtra) async {
    await mostrarDialogoRegistrarTiempoExtra(context, ref, existente: tiempoExtra);
  }

  Future<void> _eliminarFisicamente(BuildContext context, WidgetRef ref) async {
    final eliminado = await mostrarDialogoEliminarTiempoExtraFisicamente(context, ref, tiempoExtraId);
    if (!eliminado) return;
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final notifier = ref.read(tiemposExtraControllerProvider.notifier);
    ref.watch(tiemposExtraControllerProvider);
    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;

    return FutureBuilder<TiempoExtraData?>(
      future: notifier.obtenerPorId(tiempoExtraId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final tiempoExtra = snapshot.data;
        if (tiempoExtra == null) {
          return RisegEmptyState(icon: Icons.error_outline, title: l10n.tiempoExtraDetalleNoExiste, message: '');
        }

        return Scaffold(
          appBar: AppBar(title: Text(tiempoExtra.folio)),
          body: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: RisegSectionHeader(title: _formatoFecha.format(tiempoExtra.fecha))),
                      RisegStatusBadge(
                        label: tiempoExtraEstatusLabel(l10n, tiempoExtra.estatus),
                        tone: tiempoExtraEstatusTono(tiempoExtra.estatus),
                      ),
                      if (tiempoExtra.estatus == 'registrado') ...[
                        const SizedBox(width: AppSpacing.sm),
                        RisegButton(
                          key: const Key('tiempo_extra_boton_editar'),
                          label: l10n.tiempoExtraDetalleBotonEditar,
                          variant: RisegButtonVariant.secondary,
                          onPressed: () => _editar(context, ref, tiempoExtra),
                        ),
                      ],
                      const SizedBox(width: AppSpacing.sm),
                      RisegActionsMenu(
                        menuKey: const Key('tiempo_extra_menu_acciones'),
                        tooltip: l10n.tiempoExtraDetalleMenuAcciones,
                        actions: [
                          if (tiempoExtra.estatus == 'registrado')
                            RisegMenuAction(
                              key: const Key('tiempo_extra_boton_cancelar'),
                              label: l10n.tiempoExtraDetalleBotonCancelar,
                              icon: Icons.cancel_outlined,
                              destructive: true,
                              onTap: () => _cancelar(context, ref),
                            ),
                          if (esMaestro && tiempoExtra.estatus == 'cancelado')
                            RisegMenuAction(
                              key: const Key('tiempo_extra_boton_eliminar_fisicamente'),
                              label: l10n.eliminacionFisicaAccionMenu,
                              icon: Icons.delete_forever_outlined,
                              destructive: true,
                              onTap: () => _eliminarFisicamente(context, ref),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _ContextoOrigen(tiempoExtra: tiempoExtra),
                  const SizedBox(height: AppSpacing.xs),
                  FutureBuilder(
                    future: ref.read(servicioRepositoryProvider).obtenerPorId(tiempoExtra.servicioId),
                    builder: (context, servicioSnapshot) {
                      final servicio = servicioSnapshot.data;
                      if (servicio == null) return const SizedBox.shrink();
                      return InkWell(
                        key: const Key('tiempo_extra_boton_ver_servicio'),
                        onTap: () => context.push('/comercial/servicios/${servicio.id}'),
                        child: Text(
                          l10n.tiempoExtraDetalleServicioCubierto(servicio.nombre),
                          style: AppTypography.body.copyWith(color: context.colors.accentText, decoration: TextDecoration.underline),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.md,
                    children: [
                      SizedBox(
                        width: 220,
                        child: RisegStatCard(
                          label: l10n.origenCoberturaSeccion,
                          value: origenCoberturaTiempoExtraLabelCorto(l10n, tiempoExtra.origenCobertura),
                        ),
                      ),
                      if (tiempoExtra.motivoAusencia != null)
                        SizedBox(
                          width: 220,
                          child: RisegStatCard(
                            label: l10n.tiempoExtraDetalleMotivoAusencia,
                            value: motivoAusenciaTiempoExtraLabel(
                              l10n,
                              MotivoAusenciaTiempoExtra.values.byName(tiempoExtra.motivoAusencia!),
                            ),
                          ),
                        ),
                      if (tiempoExtra.descripcionOrigen != null)
                        SizedBox(
                          width: 220,
                          child: RisegStatCard(
                            label: l10n.tiempoExtraDetalleMotivoCobertura,
                            value: tiempoExtra.descripcionOrigen!,
                          ),
                        ),
                      SizedBox(
                        width: 220,
                        child: RisegStatCard(label: l10n.tiempoExtraDetalleMontoTiempoExtra, value: formatoCentavosPago(tiempoExtra.montoTiempoExtra)),
                      ),
                      SizedBox(width: 220, child: RisegStatCard(label: l10n.tiempoExtraDetalleFormaPago, value: formaPagoLabel(l10n, tiempoExtra.formaPago))),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Text('${l10n.tiempoExtraDetalleOrigenFinanciero}: ', style: AppTypography.caption.copyWith(color: context.colors.textMuted)),
                      Expanded(child: _OrigenFinancieroTexto(egresoId: tiempoExtra.egresoId, deudaId: tiempoExtra.deudaId)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(l10n.tiempoExtraDetalleSeccionCostosAdicionales, style: AppTypography.heading3),
                  const SizedBox(height: AppSpacing.sm),
                  FutureBuilder<List<TiempoExtraCostoAdicionalData>>(
                    future: notifier.listarCostosAdicionales(tiempoExtraId),
                    builder: (context, costosSnapshot) {
                      final costos = costosSnapshot.data ?? const <TiempoExtraCostoAdicionalData>[];
                      if (costos.isEmpty) return Text(l10n.tiempoExtraDetalleSinCostosAdicionales, style: AppTypography.caption);
                      return RisegCard(
                        child: Column(
                          children: [
                            for (final costo in costos)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(costo.concepto),
                                          _OrigenFinancieroTexto(egresoId: costo.egresoId, deudaId: costo.deudaId),
                                        ],
                                      ),
                                    ),
                                    Text(formatoCentavosPago(costo.monto)),
                                  ],
                                ),
                              ),
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(l10n.tiempoExtraDetalleTotal, style: AppTypography.label),
                                Text(
                                  formatoCentavosPago(tiempoExtra.montoTiempoExtra + costos.fold<int>(0, (s, c) => s + c.monto)),
                                  style: AppTypography.label,
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(l10n.tiempoExtraDetalleHistorial, style: AppTypography.heading3),
                  const SizedBox(height: AppSpacing.sm),
                  FutureBuilder<List<TiempoExtraEventoData>>(
                    future: notifier.listarEventos(tiempoExtraId),
                    builder: (context, eventosSnapshot) {
                      final eventos = eventosSnapshot.data ?? const <TiempoExtraEventoData>[];
                      if (eventos.isEmpty) return const SizedBox.shrink();
                      return RisegCard(
                        child: Column(
                          children: [
                            for (final evento in eventos)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(evento.tipoEvento, style: AppTypography.body),
                                          if (evento.observacion != null) Text(evento.observacion!, style: AppTypography.caption),
                                          _DiffCorreccion(estadoAnterior: evento.estadoAnterior, estadoNuevo: evento.estadoNuevo),
                                        ],
                                      ),
                                    ),
                                    Text(_formatoFechaHora.format(evento.fechaHora), style: AppTypography.caption),
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
