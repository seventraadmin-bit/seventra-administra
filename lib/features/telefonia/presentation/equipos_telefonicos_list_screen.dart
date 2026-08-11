import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import 'equipo_telefonico_labels.dart';
import 'widgets/configurar_equipo_telefonico_dialog.dart';
import 'widgets/regularizar_articulo_serializado_dialog.dart';
import '../telefonia_providers.dart';

/// Listado de equipos telefónicos (Etapa 9D) — "Equipo" nunca es una
/// tabla nueva de identidad, es una vista compuesta sobre
/// `ArticuloUnidad`/`ArticuloUnidadTelefono` (Inventario) +
/// `LineaTelefonicaEquipo`/`Asignacion` — esta pantalla solo lee y
/// combina lo que ya existe. Sin filtro de estatus (a diferencia del
/// picker de "equipo disponible" de la Etapa 9B): aquí sí interesa ver
/// también los dañados/perdidos/de baja.
class EquiposTelefonicosListScreen extends ConsumerStatefulWidget {
  const EquiposTelefonicosListScreen({super.key});

  @override
  ConsumerState<EquiposTelefonicosListScreen> createState() => _EquiposTelefonicosListScreenState();
}

class _EquiposTelefonicosListScreenState extends ConsumerState<EquiposTelefonicosListScreen> {
  bool _cargando = true;
  List<ArticuloUnidadData> _unidades = const [];
  Map<String, ArticuloUnidadTelefonoData> _telefonoPorUnidad = const {};
  Map<String, LineaTelefonicaData> _lineaPorUnidad = const {};
  Map<String, AsignacionData> _asignacionPorUnidad = const {};
  Map<String, String> _empleadosPorId = const {};
  Map<String, String> _serviciosPorId = const {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final inventarioRepo = ref.read(inventarioRepositoryProvider);
    final lineaEquipoRepo = ref.read(lineaTelefonicaEquipoRepositoryProvider);
    final lineaRepo = ref.read(lineaTelefonicaRepositoryProvider);
    final asignacionRepo = ref.read(asignacionRepositoryProvider);
    final opciones = ref.read(obtenerOpcionesAsignacionLineaTelefonicaUseCaseProvider);

    final unidades = await inventarioRepo.listarUnidadesTelefono();

    final telefonoPorUnidad = <String, ArticuloUnidadTelefonoData>{};
    final lineaPorUnidad = <String, LineaTelefonicaData>{};
    final asignacionPorUnidad = <String, AsignacionData>{};
    for (final unidad in unidades) {
      final telefono = await inventarioRepo.obtenerTelefono(unidad.id);
      if (telefono != null) telefonoPorUnidad[unidad.id] = telefono;

      final equipoActual = await lineaEquipoRepo.obtenerActualPorUnidad(unidad.id);
      if (equipoActual != null) {
        final linea = await lineaRepo.obtenerPorId(equipoActual.lineaTelefonicaId);
        if (linea != null) lineaPorUnidad[unidad.id] = linea;
      }

      final asignacion = await asignacionRepo.obtenerActivaPorUnidad(unidad.id);
      if (asignacion != null) asignacionPorUnidad[unidad.id] = asignacion;
    }

    final empleados = await opciones.obtenerEmpleados();
    final servicios = await opciones.obtenerServicios();

    if (!mounted) return;
    setState(() {
      _unidades = unidades;
      _telefonoPorUnidad = telefonoPorUnidad;
      _lineaPorUnidad = lineaPorUnidad;
      _asignacionPorUnidad = asignacionPorUnidad;
      _empleadosPorId = {for (final e in empleados) e.id: e.nombre};
      _serviciosPorId = {for (final s in servicios) s.id: s.nombre};
      _cargando = false;
    });
  }

  Future<void> _configurarEquipo() async {
    final unidadId = await mostrarDialogoConfigurarEquipoTelefonico(context, ref);
    if (unidadId == null || unidadId.isEmpty) return;
    if (!mounted) return;
    context.go('/telefonia/equipos/$unidadId');
  }

  Future<void> _regularizarArticulo() async {
    final regularizado = await mostrarDialogoRegularizarArticuloSerializado(context, ref);
    if (regularizado) await _cargar();
  }

  String _equipoLabel(ArticuloUnidadData unidad) {
    final descripcion = [unidad.marca, unidad.modelo].whereType<String>().where((p) => p.trim().isNotEmpty).join(' ');
    return descripcion.isEmpty ? '—' : descripcion;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.equiposTelefonicosListadoTitulo,
            primaryAction: RisegButton(
              label: l10n.equiposTelefonicosBotonConfigurar,
              onPressed: ref.watch(permissionServiceProvider).hasCode('telefonia.modificar') ? _configurarEquipo : null,
            ),
            secondaryAction: esMaestro
                ? RisegButton(
                    label: l10n.equiposTelefonicosBotonRegularizar,
                    variant: RisegButtonVariant.secondary,
                    onPressed: _regularizarArticulo,
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<ArticuloUnidadData>(
              loading: _cargando,
              rows: _unidades,
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
                  cellBuilder: (u) => Text(_telefonoPorUnidad[u.id]?.imei ?? '—'),
                ),
                RisegColumn<ArticuloUnidadData>(
                  label: l10n.equiposTelefonicosColumnaLineaActual,
                  width: 130,
                  cellBuilder: (u) => Text(_lineaPorUnidad[u.id]?.numero ?? '—'),
                ),
                RisegColumn<ArticuloUnidadData>(
                  label: l10n.equiposTelefonicosColumnaAsignadoA,
                  width: 160,
                  cellBuilder: (u) {
                    final asignacion = _asignacionPorUnidad[u.id];
                    if (asignacion == null) return const Text('—');
                    return Text(destinoAsignacionEquipoTelefonicoLabel(
                      asignacion,
                      empleadosPorId: _empleadosPorId,
                      serviciosPorId: _serviciosPorId,
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
