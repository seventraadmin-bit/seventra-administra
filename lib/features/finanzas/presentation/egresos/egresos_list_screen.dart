import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/egreso_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';

import '../../../organizacion/organizacion_providers.dart';
import '../pagos/pagos_list_screen.dart' show formaPagoLabel, formatoCentavosPago;
import 'egresos_controller.dart';
import 'widgets/egreso_detalle_dialog.dart';
import 'widgets/registrar_egreso_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

String egresoEstatusLabel(AppLocalizations l10n, String valor) {
  return switch (EstatusEgreso.values.byName(valor)) {
    EstatusEgreso.registrado => l10n.egresoEstatusRegistrado,
    EstatusEgreso.cancelado => l10n.egresoEstatusCancelado,
  };
}

RisegStatusTone egresoEstatusTono(String valor) {
  return switch (EstatusEgreso.values.byName(valor)) {
    EstatusEgreso.registrado => RisegStatusTone.success,
    EstatusEgreso.cancelado => RisegStatusTone.neutral,
  };
}

/// Listado de Egresos (Etapa 4K.1) — filtros por Servicio/estatus.
/// 100% captura manual: sin ninguna fuente automática todavía
/// (Nómina/Compras no existen).
class EgresosListScreen extends ConsumerStatefulWidget {
  const EgresosListScreen({super.key});

  @override
  ConsumerState<EgresosListScreen> createState() => _EgresosListScreenState();
}

class _EgresosListScreenState extends ConsumerState<EgresosListScreen> {
  List<ServicioListItem> _servicios = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final servicios = await ref.read(servicioRepositoryProvider).listar();
      if (mounted) setState(() => _servicios = servicios);
    });
  }

  String? _servicioNombre(String? servicioId) {
    if (servicioId == null) return null;
    for (final s in _servicios) {
      if (s.servicio.id == servicioId) return s.servicio.nombre;
    }
    return servicioId;
  }

  Future<void> _registrar() async {
    final registro = await mostrarDialogoRegistrarEgreso(context, ref, servicios: _servicios);
    if (registro) ref.read(egresosControllerProvider.notifier).recargar();
  }

  Future<void> _mostrarDetalle(EgresoData egreso) async {
    await showDialog<void>(context: context, builder: (_) => EgresoDetalleDialog(egresoId: egreso.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(egresosControllerProvider);
    final notifier = ref.read(egresosControllerProvider.notifier);

    if (state.errorCarga != null && state.egresos.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.egresosListadoCargaErrorTitulo,
        message: l10n.egresosListadoCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('egresos_boton_reintentar'),
          label: l10n.egresosListadoBotonReintentar,
          onPressed: notifier.reintentarCarga,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.egresosListadoTitulo,
            primaryAction: RisegButton(
              key: const Key('egresos_boton_registrar'),
              label: l10n.egresosListadoBotonRegistrar,
              onPressed: _registrar,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: RisegSelect<String?>(
                  label: l10n.egresosFiltroServicio,
                  value: state.servicioId,
                  items: [
                    RisegSelectItem(value: null, label: l10n.egresosFiltroServicioTodos),
                    for (final s in _servicios) RisegSelectItem(value: s.servicio.id, label: s.servicio.nombre),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(servicioId: valor, limpiarServicioId: valor == null),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: RisegSelect<String?>(
                  label: l10n.egresosFiltroEstatus,
                  value: state.estatus,
                  items: [
                    RisegSelectItem(value: null, label: l10n.egresosFiltroEstatusTodos),
                    for (final e in EstatusEgreso.values)
                      RisegSelectItem(value: e.name, label: egresoEstatusLabel(l10n, e.name)),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(estatus: valor, limpiarEstatus: valor == null),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<EgresoData>(
              loading: state.cargando,
              rows: state.egresos,
              onRowTap: _mostrarDetalle,
              emptyState: RisegEmptyState(
                title: l10n.egresosListadoVacioTitulo,
                message: l10n.egresosListadoVacioMensaje,
              ),
              columns: [
                RisegColumn<EgresoData>(
                  label: l10n.egresosColumnaFolio,
                  width: 110,
                  cellBuilder: (e) => Text(e.folioEgreso),
                ),
                RisegColumn<EgresoData>(
                  label: l10n.egresosColumnaFecha,
                  width: 110,
                  cellBuilder: (e) => Text(_formatoFecha.format(e.fecha)),
                ),
                RisegColumn<EgresoData>(
                  label: l10n.egresosColumnaServicio,
                  cellBuilder: (e) => Text(_servicioNombre(e.servicioId) ?? ''),
                ),
                RisegColumn<EgresoData>(label: l10n.egresosColumnaConcepto, cellBuilder: (e) => Text(e.concepto)),
                RisegColumn<EgresoData>(
                  label: l10n.egresosColumnaMonto,
                  width: 130,
                  alignment: TextAlign.right,
                  cellBuilder: (e) => Text(formatoCentavosPago(e.monto)),
                ),
                RisegColumn<EgresoData>(
                  label: l10n.egresosColumnaFormaPago,
                  width: 130,
                  cellBuilder: (e) => Text(formaPagoLabel(l10n, e.formaPago)),
                ),
                RisegColumn<EgresoData>(
                  label: l10n.egresosColumnaEstatus,
                  width: 130,
                  cellBuilder: (e) =>
                      RisegStatusBadge(label: egresoEstatusLabel(l10n, e.estatus), tone: egresoEstatusTono(e.estatus)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
