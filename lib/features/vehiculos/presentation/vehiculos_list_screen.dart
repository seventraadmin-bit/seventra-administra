import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

import 'vehiculo_labels.dart';
import 'vehiculos_controller.dart';
import 'widgets/gestionar_vehiculo_dialog.dart';

/// Listado de la flotilla (Etapa 8A) — la pantalla principal de
/// Vehículos. Sin pestañas todavía (mismo criterio que Inventario en
/// 7A: la subnavegación llega cuando exista más de una sección real).
class VehiculosListScreen extends ConsumerWidget {
  const VehiculosListScreen({super.key});

  Future<void> _nuevoVehiculo(BuildContext context, WidgetRef ref) async {
    await mostrarDialogoGestionarVehiculo(context, ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(vehiculosControllerProvider);
    final notifier = ref.read(vehiculosControllerProvider.notifier);

    if (state.errorCarga != null && state.vehiculos.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.vehiculosListadoCargaErrorTitulo,
        message: l10n.vehiculosListadoCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('vehiculos_boton_reintentar'),
          label: l10n.vehiculosListadoBotonReintentar,
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
            title: l10n.vehiculosListadoTitulo,
            primaryAction: RisegButton(
              key: const Key('vehiculos_boton_nuevo_vehiculo'),
              label: l10n.vehiculosBotonNuevoVehiculo,
              onPressed: () => _nuevoVehiculo(context, ref),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<VehiculoData>(
              loading: state.cargando,
              rows: state.vehiculos,
              onRowTap: (v) => context.go('/vehiculos/${v.id}'),
              emptyState: RisegEmptyState(
                title: l10n.vehiculosListadoVacioTitulo,
                message: l10n.vehiculosListadoVacioMensaje,
              ),
              columns: [
                RisegColumn<VehiculoData>(
                  label: l10n.vehiculosColumnaCodigo,
                  width: 110,
                  cellBuilder: (v) => Text(v.codigo),
                ),
                RisegColumn<VehiculoData>(
                  label: l10n.vehiculosColumnaVehiculo,
                  cellBuilder: (v) => Text(_descripcion(v.marca, v.modelo, v.anio)),
                ),
                RisegColumn<VehiculoData>(
                  label: l10n.vehiculosColumnaPlacas,
                  width: 120,
                  cellBuilder: (v) => Text(v.placas ?? '—'),
                ),
                RisegColumn<VehiculoData>(
                  label: l10n.vehiculosColumnaTipo,
                  width: 130,
                  cellBuilder: (v) => Text(tipoVehiculoLabel(l10n, v.tipoVehiculo)),
                ),
                RisegColumn<VehiculoData>(
                  label: l10n.vehiculosColumnaEstatus,
                  width: 150,
                  cellBuilder: (v) => RisegStatusBadge(
                    label: estatusVehiculoLabel(l10n, v.estatus),
                    tone: estatusVehiculoTono(v.estatus),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _descripcion(String marca, String modelo, int? anio) {
    return anio == null ? '$marca $modelo' : '$marca $modelo $anio';
  }
}
