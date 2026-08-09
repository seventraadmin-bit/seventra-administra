import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/ingreso_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';

import '../../../organizacion/organizacion_providers.dart';
import '../pagos/pagos_list_screen.dart' show formaPagoLabel, formatoCentavosPago;
import 'ingresos_controller.dart';
import 'widgets/ingreso_detalle_dialog.dart';
import 'widgets/registrar_ingreso_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

String ingresoEstatusLabel(AppLocalizations l10n, String valor) {
  return switch (EstatusIngreso.values.byName(valor)) {
    EstatusIngreso.registrado => l10n.ingresoEstatusRegistrado,
    EstatusIngreso.cancelado => l10n.ingresoEstatusCancelado,
  };
}

RisegStatusTone ingresoEstatusTono(String valor) {
  return switch (EstatusIngreso.values.byName(valor)) {
    EstatusIngreso.registrado => RisegStatusTone.success,
    EstatusIngreso.cancelado => RisegStatusTone.neutral,
  };
}

/// Listado de Ingresos (Etapa 4K.1) — filtros por Servicio/estatus. El
/// botón "Registrar" crea un Ingreso manual (sin `Pago` de por medio);
/// el Ingreso automático de un Pago se ve aquí pero nunca se crea desde
/// esta pantalla (Resolución de Marlon).
class IngresosListScreen extends ConsumerStatefulWidget {
  const IngresosListScreen({super.key});

  @override
  ConsumerState<IngresosListScreen> createState() => _IngresosListScreenState();
}

class _IngresosListScreenState extends ConsumerState<IngresosListScreen> {
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
    final registro = await mostrarDialogoRegistrarIngreso(context, ref, servicios: _servicios);
    if (registro) ref.read(ingresosControllerProvider.notifier).recargar();
  }

  Future<void> _mostrarDetalle(IngresoData ingreso) async {
    await showDialog<void>(context: context, builder: (_) => IngresoDetalleDialog(ingresoId: ingreso.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(ingresosControllerProvider);
    final notifier = ref.read(ingresosControllerProvider.notifier);

    if (state.errorCarga != null && state.ingresos.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.ingresosListadoCargaErrorTitulo,
        message: l10n.ingresosListadoCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('ingresos_boton_reintentar'),
          label: l10n.ingresosListadoBotonReintentar,
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
            title: l10n.ingresosListadoTitulo,
            primaryAction: RisegButton(
              key: const Key('ingresos_boton_registrar'),
              label: l10n.ingresosListadoBotonRegistrar,
              onPressed: _registrar,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: RisegSelect<String?>(
                  label: l10n.ingresosFiltroServicio,
                  value: state.servicioId,
                  items: [
                    RisegSelectItem(value: null, label: l10n.ingresosFiltroServicioTodos),
                    for (final s in _servicios) RisegSelectItem(value: s.servicio.id, label: s.servicio.nombre),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(servicioId: valor, limpiarServicioId: valor == null),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: RisegSelect<String?>(
                  label: l10n.ingresosFiltroEstatus,
                  value: state.estatus,
                  items: [
                    RisegSelectItem(value: null, label: l10n.ingresosFiltroEstatusTodos),
                    for (final e in EstatusIngreso.values)
                      RisegSelectItem(value: e.name, label: ingresoEstatusLabel(l10n, e.name)),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(estatus: valor, limpiarEstatus: valor == null),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<IngresoData>(
              loading: state.cargando,
              rows: state.ingresos,
              onRowTap: _mostrarDetalle,
              emptyState: RisegEmptyState(
                title: l10n.ingresosListadoVacioTitulo,
                message: l10n.ingresosListadoVacioMensaje,
              ),
              columns: [
                RisegColumn<IngresoData>(
                  label: l10n.ingresosColumnaFolio,
                  width: 110,
                  cellBuilder: (i) => Text(i.folioIngreso),
                ),
                RisegColumn<IngresoData>(
                  label: l10n.ingresosColumnaFecha,
                  width: 110,
                  cellBuilder: (i) => Text(_formatoFecha.format(i.fecha)),
                ),
                RisegColumn<IngresoData>(
                  label: l10n.ingresosColumnaServicio,
                  cellBuilder: (i) => Text(_servicioNombre(i.servicioId) ?? ''),
                ),
                RisegColumn<IngresoData>(label: l10n.ingresosColumnaConcepto, cellBuilder: (i) => Text(i.concepto)),
                RisegColumn<IngresoData>(
                  label: l10n.ingresosColumnaMonto,
                  width: 130,
                  alignment: TextAlign.right,
                  cellBuilder: (i) => Text(formatoCentavosPago(i.monto)),
                ),
                RisegColumn<IngresoData>(
                  label: l10n.ingresosColumnaFormaPago,
                  width: 130,
                  cellBuilder: (i) => Text(formaPagoLabel(l10n, i.formaPago)),
                ),
                RisegColumn<IngresoData>(
                  label: l10n.ingresosColumnaOrigen,
                  width: 110,
                  cellBuilder: (i) => Text(
                    i.pagoId != null ? l10n.ingresosOrigenAutomatico : l10n.ingresosOrigenManual,
                  ),
                ),
                RisegColumn<IngresoData>(
                  label: l10n.ingresosColumnaEstatus,
                  width: 130,
                  cellBuilder: (i) =>
                      RisegStatusBadge(label: ingresoEstatusLabel(l10n, i.estatus), tone: ingresoEstatusTono(i.estatus)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
