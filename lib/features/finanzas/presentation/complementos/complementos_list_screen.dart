import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/complemento_pago_table.dart';

import '../../../organizacion/organizacion_providers.dart';
import '../../finanzas_providers.dart';
import '../pagos/pagos_list_screen.dart' show formatoCentavosPago;
import 'complementos_controller.dart';
import 'widgets/complemento_detalle_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

String complementoEstatusLabel(AppLocalizations l10n, String valor) {
  return switch (EstatusComplementoPago.values.byName(valor)) {
    EstatusComplementoPago.registrado => l10n.complementoPagoEstatusRegistrado,
    EstatusComplementoPago.cancelado => l10n.complementoPagoEstatusCancelado,
  };
}

RisegStatusTone complementoEstatusTono(String valor) {
  return switch (EstatusComplementoPago.values.byName(valor)) {
    EstatusComplementoPago.registrado => RisegStatusTone.success,
    EstatusComplementoPago.cancelado => RisegStatusTone.neutral,
  };
}

/// Listado de Complementos de pago (Etapa 4J.3) — filtros por Cliente/
/// estatus. Sin acción de creación aquí: se registra desde el detalle
/// del Pago que liquida (mismo criterio que Cuentas por cobrar/Pagos).
class ComplementosListScreen extends ConsumerStatefulWidget {
  const ComplementosListScreen({super.key});

  @override
  ConsumerState<ComplementosListScreen> createState() => _ComplementosListScreenState();
}

class _ComplementosListScreenState extends ConsumerState<ComplementosListScreen> {
  List<ClienteData> _clientes = const [];
  final Map<String, String> _folioPagoPorComplemento = {};
  final Map<String, String> _clienteNombrePorComplemento = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final clientes = await ref.read(clienteRepositoryProvider).listarActivos();
      if (mounted) setState(() => _clientes = clientes);
    });
  }

  Future<void> _cargarDatosPago(List<ComplementoPagoData> complementos) async {
    for (final complemento in complementos) {
      if (_folioPagoPorComplemento.containsKey(complemento.id)) continue;
      final pago = await ref.read(pagoRepositoryProvider).obtenerPorId(complemento.pagoId);
      if (pago == null) continue;
      _folioPagoPorComplemento[complemento.id] = pago.folioPago;
      final cliente = await ref.read(clienteRepositoryProvider).obtenerPorId(pago.clienteId);
      if (cliente != null) _clienteNombrePorComplemento[complemento.id] = cliente.nombreComercial;
    }
    if (mounted) setState(() {});
  }

  Future<void> _mostrarDetalle(ComplementoPagoData complemento) async {
    await showDialog<void>(context: context, builder: (_) => ComplementoDetalleDialog(complementoPagoId: complemento.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(complementosControllerProvider);
    final notifier = ref.read(complementosControllerProvider.notifier);

    if (!state.cargando) {
      // Carga perezosa de folio de Pago / nombre de Cliente para las filas
      // visibles — mismo patrón ya usado en CuentasPorCobrarListScreen.
      unawaited(_cargarDatosPago(state.complementos));
    }

    if (state.errorCarga != null && state.complementos.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.complementosListadoCargaErrorTitulo,
        message: l10n.complementosListadoCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('complementos_boton_reintentar'),
          label: l10n.complementosListadoBotonReintentar,
          onPressed: notifier.reintentarCarga,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(title: l10n.complementosListadoTitulo),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: RisegSelect<String?>(
                  label: l10n.complementosFiltroCliente,
                  value: state.clienteId,
                  items: [
                    RisegSelectItem(value: null, label: l10n.complementosFiltroClienteTodos),
                    for (final c in _clientes) RisegSelectItem(value: c.id, label: c.nombreComercial),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(clienteId: valor, limpiarClienteId: valor == null),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: RisegSelect<String?>(
                  label: l10n.complementosFiltroEstatus,
                  value: state.estatus,
                  items: [
                    RisegSelectItem(value: null, label: l10n.complementosFiltroEstatusTodos),
                    for (final e in EstatusComplementoPago.values)
                      RisegSelectItem(value: e.name, label: complementoEstatusLabel(l10n, e.name)),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(estatus: valor, limpiarEstatus: valor == null),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<ComplementoPagoData>(
              loading: state.cargando,
              rows: state.complementos,
              onRowTap: _mostrarDetalle,
              emptyState: RisegEmptyState(
                title: l10n.complementosListadoVacioTitulo,
                message: l10n.complementosListadoVacioMensaje,
              ),
              columns: [
                RisegColumn<ComplementoPagoData>(
                  label: l10n.complementosColumnaUuid,
                  cellBuilder: (c) => Text(c.uuid),
                ),
                RisegColumn<ComplementoPagoData>(
                  label: l10n.complementosColumnaCliente,
                  cellBuilder: (c) => Text(_clienteNombrePorComplemento[c.id] ?? ''),
                ),
                RisegColumn<ComplementoPagoData>(
                  label: l10n.complementosColumnaFolioPago,
                  width: 120,
                  cellBuilder: (c) => Text(_folioPagoPorComplemento[c.id] ?? c.pagoId),
                ),
                RisegColumn<ComplementoPagoData>(
                  label: l10n.complementosColumnaFechaTimbrado,
                  width: 130,
                  cellBuilder: (c) => Text(_formatoFecha.format(c.fechaTimbrado)),
                ),
                RisegColumn<ComplementoPagoData>(
                  label: l10n.complementosColumnaMontoTotal,
                  width: 130,
                  alignment: TextAlign.right,
                  cellBuilder: (c) => Text(formatoCentavosPago(c.montoTotal)),
                ),
                RisegColumn<ComplementoPagoData>(
                  label: l10n.complementosColumnaEstatus,
                  width: 130,
                  cellBuilder: (c) => RisegStatusBadge(
                    label: complementoEstatusLabel(l10n, c.estatus),
                    tone: complementoEstatusTono(c.estatus),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
