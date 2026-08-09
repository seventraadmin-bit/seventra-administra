import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';

import '../../../organizacion/organizacion_providers.dart';
import 'empleados_list_controller.dart';
import 'widgets/crear_empleado_dialog.dart';

String empleadoNombreCompleto(EmpleadoData empleado) {
  final materno = empleado.apellidoMaterno;
  return '${empleado.nombres} ${empleado.apellidoPaterno}${materno == null ? '' : ' $materno'}';
}

String empleadoEstatusLabel(AppLocalizations l10n, String valor) {
  return switch (EstatusEmpleado.values.byName(valor)) {
    EstatusEmpleado.activo => l10n.empleadoEstatusActivo,
    EstatusEmpleado.baja => l10n.empleadoEstatusBaja,
  };
}

RisegStatusTone empleadoEstatusTono(String valor) {
  return switch (EstatusEmpleado.values.byName(valor)) {
    EstatusEmpleado.activo => RisegStatusTone.success,
    EstatusEmpleado.baja => RisegStatusTone.neutral,
  };
}

/// Listado del expediente de empleados (Etapa 5A) — filtros por Puesto/
/// estatus. "Registrar empleado" abre el formulario completo de alta.
class EmpleadosListScreen extends ConsumerStatefulWidget {
  const EmpleadosListScreen({super.key});

  @override
  ConsumerState<EmpleadosListScreen> createState() => _EmpleadosListScreenState();
}

class _EmpleadosListScreenState extends ConsumerState<EmpleadosListScreen> {
  List<PuestoData> _puestos = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final puestos = await ref.read(puestoRepositoryProvider).listarActivos();
      if (mounted) setState(() => _puestos = puestos);
    });
  }

  String? _puestoNombre(String? puestoId) {
    if (puestoId == null) return null;
    for (final p in _puestos) {
      if (p.id == puestoId) return p.nombre;
    }
    return puestoId;
  }

  Future<void> _registrar() async {
    final empleadoId = await mostrarDialogoCrearEmpleado(context, ref);
    if (empleadoId == null) return;
    ref.read(empleadosListControllerProvider.notifier).recargar();
    if (mounted) context.push('/personal/empleados/$empleadoId');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(empleadosListControllerProvider);
    final notifier = ref.read(empleadosListControllerProvider.notifier);

    if (state.errorCarga != null && state.empleados.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.empleadosListadoCargaErrorTitulo,
        message: l10n.empleadosListadoCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('empleados_boton_reintentar'),
          label: l10n.empleadosListadoBotonReintentar,
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
            title: l10n.empleadosListadoTitulo,
            primaryAction: RisegButton(
              key: const Key('empleados_boton_registrar'),
              label: l10n.empleadosListadoBotonRegistrar,
              onPressed: _registrar,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: RisegSelect<String?>(
                  label: l10n.empleadosFiltroPuesto,
                  value: state.puestoId,
                  items: [
                    RisegSelectItem(value: null, label: l10n.empleadosFiltroPuestoTodos),
                    for (final p in _puestos) RisegSelectItem(value: p.id, label: p.nombre),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(puestoId: valor, limpiarPuestoId: valor == null),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: RisegSelect<String?>(
                  label: l10n.empleadosFiltroEstatus,
                  value: state.estatus,
                  items: [
                    RisegSelectItem(value: null, label: l10n.empleadosFiltroEstatusTodos),
                    for (final e in EstatusEmpleado.values)
                      RisegSelectItem(value: e.name, label: empleadoEstatusLabel(l10n, e.name)),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(estatus: valor, limpiarEstatus: valor == null),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<EmpleadoData>(
              loading: state.cargando,
              rows: state.empleados,
              onRowTap: (empleado) => context.push('/personal/empleados/${empleado.id}'),
              emptyState: RisegEmptyState(
                title: l10n.empleadosListadoVacioTitulo,
                message: l10n.empleadosListadoVacioMensaje,
              ),
              columns: [
                RisegColumn<EmpleadoData>(
                  label: l10n.empleadosColumnaCodigo,
                  width: 110,
                  cellBuilder: (e) => Text(e.codigoEmpleado),
                ),
                RisegColumn<EmpleadoData>(
                  label: l10n.empleadosColumnaNombre,
                  cellBuilder: (e) => Text(empleadoNombreCompleto(e)),
                ),
                RisegColumn<EmpleadoData>(
                  label: l10n.empleadosColumnaPuesto,
                  cellBuilder: (e) => Text(_puestoNombre(e.puestoId) ?? ''),
                ),
                RisegColumn<EmpleadoData>(
                  label: l10n.empleadosColumnaEstatus,
                  width: 130,
                  cellBuilder: (e) =>
                      RisegStatusBadge(label: empleadoEstatusLabel(l10n, e.estatus), tone: empleadoEstatusTono(e.estatus)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
