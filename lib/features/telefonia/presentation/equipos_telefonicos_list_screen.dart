import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import 'equipo_telefonico_labels.dart';
import 'equipos_telefonicos_controller.dart';
import 'widgets/configurar_equipo_telefonico_dialog.dart';
import 'widgets/regularizar_articulo_serializado_dialog.dart';

/// Listado de equipos telefónicos (Etapa 9D) — "Equipo" nunca es una
/// tabla nueva de identidad, es una vista compuesta sobre
/// `ArticuloUnidad`/`ArticuloUnidadTelefono` (Inventario) +
/// `LineaTelefonicaEquipo`/`Asignacion` — esta pantalla solo lee y
/// combina lo que ya existe. Sin filtro de estatus (a diferencia del
/// picker de "equipo disponible" de la Etapa 9B): aquí sí interesa ver
/// también los dañados/perdidos/de baja.
///
/// Corrección de invalidación (Etapa 9D): antes esta pantalla cargaba
/// todo en estado local (`initState` + `setState`), por lo que ninguna
/// mutación real (Configurar equipo, editar IMEI, asignar/retirar,
/// asociar/cambiar/retirar equipo de una línea) refrescaba la fila
/// visible sin forzar un remount completo (cambiar de pestaña y
/// volver — el `switch` de `TelefoniaShellScreen` destruye/recrea el
/// widget). Ahora consume `equiposTelefonicosControllerProvider`
/// (`ref.watch`), el mismo patrón ya usado por Líneas
/// (`TelefoniaController`) — cada mutador real de Telefonía que
/// cambia algo visible aquí invalida ese provider explícitamente.
class EquiposTelefonicosListScreen extends ConsumerWidget {
  const EquiposTelefonicosListScreen({super.key});

  Future<void> _configurarEquipo(BuildContext context, WidgetRef ref) async {
    final unidadId = await mostrarDialogoConfigurarEquipoTelefonico(context, ref);
    if (unidadId == null || unidadId.isEmpty) return;
    ref.invalidate(equiposTelefonicosControllerProvider);
    if (!context.mounted) return;
    context.go('/telefonia/equipos/$unidadId');
  }

  Future<void> _regularizarArticulo(BuildContext context, WidgetRef ref) async {
    final regularizado = await mostrarDialogoRegularizarArticuloSerializado(context, ref);
    if (regularizado) ref.invalidate(equiposTelefonicosControllerProvider);
  }

  String _equipoLabel(ArticuloUnidadData unidad) {
    final descripcion = [unidad.marca, unidad.modelo].whereType<String>().where((p) => p.trim().isNotEmpty).join(' ');
    return descripcion.isEmpty ? '—' : descripcion;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;
    final state = ref.watch(equiposTelefonicosControllerProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.equiposTelefonicosListadoTitulo,
            primaryAction: RisegButton(
              label: l10n.equiposTelefonicosBotonConfigurar,
              onPressed: ref.watch(permissionServiceProvider).hasCode('telefonia.modificar')
                  ? () => _configurarEquipo(context, ref)
                  : null,
            ),
            secondaryAction: esMaestro
                ? RisegButton(
                    label: l10n.equiposTelefonicosBotonRegularizar,
                    variant: RisegButtonVariant.secondary,
                    onPressed: () => _regularizarArticulo(context, ref),
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<ArticuloUnidadData>(
              loading: state.cargando,
              rows: state.unidades,
              onRowTap: (u) => context.go('/telefonia/equipos/${u.id}'),
              emptyState: RisegEmptyState(
                title: l10n.equiposTelefonicosListadoVacioTitulo,
                message: l10n.equiposTelefonicosListadoVacioMensaje,
              ),
              columns: [
                RisegColumn<ArticuloUnidadData>(
                  label: l10n.equiposTelefonicosColumnaCodigo,
                  width: 110,
                  cellBuilder: (u) => Text(u.codigo),
                ),
                RisegColumn<ArticuloUnidadData>(
                  label: l10n.equiposTelefonicosColumnaEquipo,
                  cellBuilder: (u) => Text(_equipoLabel(u)),
                ),
                RisegColumn<ArticuloUnidadData>(
                  label: l10n.equiposTelefonicosColumnaImeiPrincipal,
                  width: 150,
                  cellBuilder: (u) => Text(state.telefonoPorUnidad[u.id]?.imei ?? '—'),
                ),
                RisegColumn<ArticuloUnidadData>(
                  label: l10n.equiposTelefonicosColumnaLineaActual,
                  width: 130,
                  cellBuilder: (u) => Text(state.lineaPorUnidad[u.id]?.numero ?? '—'),
                ),
                RisegColumn<ArticuloUnidadData>(
                  label: l10n.equiposTelefonicosColumnaAsignadoA,
                  width: 160,
                  cellBuilder: (u) {
                    final asignacion = state.asignacionPorUnidad[u.id];
                    if (asignacion == null) return const Text('—');
                    return Text(destinoAsignacionEquipoTelefonicoLabel(
                      asignacion,
                      empleadosPorId: state.empleadosPorId,
                      serviciosPorId: state.serviciosPorId,
                    ));
                  },
                ),
                RisegColumn<ArticuloUnidadData>(
                  label: l10n.equiposTelefonicosColumnaEstatus,
                  width: 120,
                  cellBuilder: (u) => RisegStatusBadge(
                    label: estatusEquipoTelefonicoLabel(l10n, u.estatus),
                    tone: estatusEquipoTelefonicoTono(u.estatus),
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
