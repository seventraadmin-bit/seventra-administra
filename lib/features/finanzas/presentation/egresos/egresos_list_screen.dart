import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/egreso_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/reportes/domain/usecases/clasificar_egresos_por_origen_usecase.dart' show OrigenEgreso;
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../../organizacion/organizacion_providers.dart';
import '../../finanzas_providers.dart';
import '../cuentas_financieras/cuentas_financieras_controller.dart';
import '../pagos/pagos_list_screen.dart' show formaPagoLabel, formatoCentavosPago;
import '../planeacion/planeacion_financiera_controller.dart';
import '../resumen/resumen_financiero_controller.dart';
import 'egresos_controller.dart';
import 'egresos_state.dart';
import 'widgets/egreso_detalle_dialog.dart';
import 'widgets/egreso_identidad.dart';
import 'widgets/egresos_resumen_row.dart';
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

String _origenLabel(AppLocalizations l10n, OrigenEgreso? origen) {
  return switch (origen) {
    OrigenEgreso.nomina => l10n.egresosOrigenNomina,
    OrigenEgreso.compra => l10n.egresosOrigenCompra,
    OrigenEgreso.tiempoExtra => l10n.egresosOrigenTiempoExtra,
    OrigenEgreso.deuda => l10n.egresosOrigenDeuda,
    OrigenEgreso.descuentoProgramado => l10n.egresosOrigenDescuentoProgramado,
    OrigenEgreso.vehiculo => l10n.egresosOrigenVehiculo,
    // Sin este caso, una recarga de Telefonía caía en el `_` y se leía
    // como "Manual" — justo lo contrario de lo que es.
    OrigenEgreso.telefonia => l10n.egresosOrigenTelefonia,
    _ => l10n.egresosOrigenManual,
  };
}

/// Listado de Egresos (Etapa 4K.1) — filtros por Servicio/Categoría/
/// Origen/Forma de pago/periodo/estatus. La captura manual sigue
/// siendo el único flujo desde ESTA pantalla, pero Nómina (Etapa 6D) y
/// Compras (Etapa 10) ya generan sus propios Egresos automáticos desde
/// hace varias etapas — el origen se deriva vía
/// `ClasificarEgresosPorOrigenUseCase` (Etapa 17), nunca almacenado.
class EgresosListScreen extends ConsumerStatefulWidget {
  const EgresosListScreen({super.key});

  @override
  ConsumerState<EgresosListScreen> createState() => _EgresosListScreenState();
}

class _EgresosListScreenState extends ConsumerState<EgresosListScreen> {
  List<ServicioListItem> _servicios = const [];
  List<CategoriaFinancieraData> _categorias = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final servicios = await ref.read(servicioRepositoryProvider).listar();
      final categorias = await ref.read(categoriaFinancieraRepositoryProvider).listar();
      if (mounted) {
        setState(() {
          _servicios = servicios;
          _categorias = categorias;
        });
      }
    });
  }

  String? _servicioNombre(String? servicioId) {
    if (servicioId == null) return null;
    for (final s in _servicios) {
      if (s.servicio.id == servicioId) return s.servicio.nombre;
    }
    return servicioId;
  }

  String _categoriaNombre(AppLocalizations l10n, String? categoriaId) {
    if (categoriaId == null) return l10n.egresosSinCategoria;
    for (final c in _categorias) {
      if (c.id == categoriaId) return c.nombre;
    }
    return categoriaId;
  }

  Future<void> _registrar() async {
    final registro = await mostrarDialogoRegistrarEgreso(context, ref, servicios: _servicios);
    if (registro) {
      ref.read(egresosControllerProvider.notifier).recargar();
      // Etapa 19C: un Egreso manual puede llevar una Cuenta financiera
      // y siempre afecta el Resumen (Egresos del periodo) — mismo
      // hallazgo ya corregido para Ingresos/Deudas/Compras.
      ref.invalidate(cuentasFinancierasControllerProvider);
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
    }
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

    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.egresosListadoTitulo,
            description: l10n.egresosListadoSubtitulo,
            primaryAction: RisegButton(
              key: const Key('egresos_boton_registrar'),
              label: l10n.egresosListadoBotonRegistrar,
              icon: Icons.add,
              onPressed: ref.watch(permissionServiceProvider).hasCode('egresos.crear') ? _registrar : null,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          EgresosResumenRow(state: state),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 190,
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
              SizedBox(
                width: 190,
                child: RisegSelect<String?>(
                  label: l10n.egresosFiltroCategoria,
                  value: state.categoriaFinancieraId,
                  items: [
                    RisegSelectItem(value: null, label: l10n.egresosFiltroCategoriaTodas),
                    for (final c in _categorias) RisegSelectItem(value: c.id, label: c.nombre),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(categoriaFinancieraId: valor, limpiarCategoria: valor == null),
                ),
              ),
              SizedBox(
                width: 170,
                child: RisegSelect<FiltroOrigenEgreso>(
                  label: l10n.egresosFiltroOrigen,
                  value: state.origen,
                  items: [
                    RisegSelectItem(value: FiltroOrigenEgreso.todos, label: l10n.egresosFiltroOrigenTodos),
                    RisegSelectItem(value: FiltroOrigenEgreso.nomina, label: l10n.egresosOrigenNomina),
                    RisegSelectItem(value: FiltroOrigenEgreso.compra, label: l10n.egresosOrigenCompra),
                    RisegSelectItem(value: FiltroOrigenEgreso.tiempoExtra, label: l10n.egresosOrigenTiempoExtra),
                    RisegSelectItem(value: FiltroOrigenEgreso.deuda, label: l10n.egresosOrigenDeuda),
                    RisegSelectItem(value: FiltroOrigenEgreso.descuentoProgramado, label: l10n.egresosOrigenDescuentoProgramado),
                    RisegSelectItem(value: FiltroOrigenEgreso.vehiculo, label: l10n.egresosOrigenVehiculo),
                    RisegSelectItem(value: FiltroOrigenEgreso.telefonia, label: l10n.egresosOrigenTelefonia),
                    RisegSelectItem(value: FiltroOrigenEgreso.manual, label: l10n.egresosOrigenManual),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltrosLocales(origen: valor ?? FiltroOrigenEgreso.todos),
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegSelect<String?>(
                  label: l10n.egresosFiltroFormaPago,
                  value: state.formaPago,
                  items: [
                    RisegSelectItem(value: null, label: l10n.egresosFiltroFormaPagoTodas),
                    for (final f in FormaPago.values) RisegSelectItem(value: f.name, label: formaPagoLabel(l10n, f.name)),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltrosLocales(formaPago: valor, limpiarFormaPago: valor == null),
                ),
              ),
              SizedBox(
                width: 160,
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
              SizedBox(
                width: 150,
                child: RisegDateField(
                  label: l10n.egresosFiltroDesde,
                  value: state.rangoInicio,
                  onChanged: (valor) => notifier.aplicarFiltros(rangoInicio: valor),
                ),
              ),
              SizedBox(
                width: 150,
                child: RisegDateField(
                  label: l10n.egresosFiltroHasta,
                  value: state.rangoFin,
                  onChanged: (valor) => notifier.aplicarFiltros(rangoFin: valor),
                ),
              ),
              RisegButton(
                label: l10n.personalActivoLimpiarFiltros,
                variant: RisegButtonVariant.ghost,
                onPressed: state.hayFiltrosActivos
                    ? () => notifier
                        .aplicarFiltros(limpiarEstatus: true, limpiarServicioId: true, limpiarCategoria: true, limpiarRango: true)
                        .then((_) => notifier.aplicarFiltrosLocales(origen: FiltroOrigenEgreso.todos, limpiarFormaPago: true))
                    : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<EgresoData>(
              loading: state.cargando,
              rows: state.egresosFiltrados,
              onRowTap: _mostrarDetalle,
              emptyState: RisegEmptyState(
                title: l10n.egresosListadoVacioTitulo,
                message: l10n.egresosListadoVacioMensaje,
              ),
              hoverColor: colors.accentSoftBg,
              rowVerticalPadding: AppSpacing.sm + AppSpacing.xxs,
              rowActionsBuilder: (_) => Icon(Icons.chevron_right, size: AppSizes.iconMd, color: colors.textMuted),
              actionsWidth: 40,
              columns: [
                RisegColumn<EgresoData>(
                  label: l10n.egresosColumnaFolio,
                  width: 100,
                  cellBuilder: (e) => Text(e.folioEgreso),
                ),
                RisegColumn<EgresoData>(
                  label: l10n.egresosColumnaFecha,
                  width: 100,
                  cellBuilder: (e) => Text(_formatoFecha.format(e.fecha)),
                ),
                RisegColumn<EgresoData>(
                  label: l10n.egresosColumnaConcepto,
                  width: 200,
                  cellBuilder: (e) {
                    final identidad = identidadEgreso(e.concepto);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          identidad.primario,
                          style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          identidad.secundario ?? e.folioEgreso,
                          style: AppTypography.caption.copyWith(color: colors.textMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    );
                  },
                ),
                RisegColumn<EgresoData>(
                  label: l10n.egresosColumnaCategoria,
                  width: 150,
                  cellBuilder: (e) => Text(_categoriaNombre(l10n, e.categoriaFinancieraId)),
                ),
                RisegColumn<EgresoData>(
                  label: l10n.egresosColumnaServicio,
                  cellBuilder: (e) => Text(_servicioNombre(e.servicioId) ?? ''),
                ),
                RisegColumn<EgresoData>(
                  label: l10n.egresosColumnaOrigen,
                  width: 110,
                  cellBuilder: (e) => RisegStatusBadge(
                    label: _origenLabel(l10n, state.origenPorEgreso[e.id]),
                    tone: RisegStatusTone.neutral,
                  ),
                ),
                RisegColumn<EgresoData>(
                  label: l10n.egresosColumnaFormaPago,
                  width: 130,
                  cellBuilder: (e) => Text(formaPagoLabel(l10n, e.formaPago)),
                ),
                RisegColumn<EgresoData>(
                  label: l10n.egresosColumnaMonto,
                  width: 130,
                  alignment: TextAlign.right,
                  cellBuilder: (e) => Text(
                    formatoCentavosPago(e.monto),
                    style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
                  ),
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
