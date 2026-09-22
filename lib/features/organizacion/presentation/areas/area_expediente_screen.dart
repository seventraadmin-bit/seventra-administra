import 'areas_list_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

import '../../organizacion_providers.dart';
import 'widgets/area_acciones.dart';
import 'widgets/area_form_dialog.dart';
import 'widgets/eliminar_area_fisicamente_dialog.dart';

/// Expediente de Área (Etapa 16, tercera pasada visual) — experiencia
/// ligera: nombre/código/estado + Puestos realmente asociados (nunca
/// solo un nombre guardado en BD). Las acciones destructivas/edición
/// viven aquí (nunca como iconos permanentes en el listado): "Editar
/// área" es la acción principal; Activar/Desactivar/Eliminar viven en
/// un menú "⋯", sin competir visualmente con el contenido.
class AreaExpedienteScreen extends ConsumerStatefulWidget {
  const AreaExpedienteScreen({required this.areaId, super.key});

  final String areaId;

  @override
  ConsumerState<AreaExpedienteScreen> createState() => _AreaExpedienteScreenState();
}

class _AreaExpedienteScreenState extends ConsumerState<AreaExpedienteScreen> {
  bool _cargando = true;
  AreaData? _area;
  List<PuestoData> _puestos = const [];
  String? _errorCarga;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _errorCarga = null;
    });
    try {
      final area = await ref.read(areaRepositoryProvider).obtenerPorId(widget.areaId);
      // Reutiliza el mismo listado completo de Puestos activos ya usado
      // por el listado de Áreas (Etapa 16) — filtrado en memoria por
      // esta Área, nunca una consulta nueva por Puesto.
      final todosPuestos = await ref.read(puestoRepositoryProvider).listarActivos();
      final puestos = [for (final p in todosPuestos) if (p.areaId == widget.areaId) p]
        ..sort((a, b) => a.nivelJerarquico.compareTo(b.nivelJerarquico));

      if (!mounted) return;
      setState(() {
        _area = area;
        _puestos = puestos;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorCarga = e.toString();
        _cargando = false;
      });
    }
  }

  Future<void> _editar() async {
    await mostrarDialogoAreaAltaEdicion(context, ref, area: _area);
    if (mounted) _cargar();
  }

  Future<void> _activarODesactivar() async {
    final area = _area!;
    if (area.activo) {
      await desactivarArea(context, ref, area);
    } else {
      await activarArea(context, ref, area);
    }
    if (mounted) _cargar();
  }

  Future<void> _eliminarFisicamente() async {
    final eliminado = await mostrarDialogoEliminarAreaFisicamente(context, ref, widget.areaId);
    if (!eliminado) return;
    // La eliminacion fisica no pasa por ningun controlador: sin esto el
    // renglon sobrevive en el listado de Areas hasta que algo ajeno (cambiar de
    // pestana) reconstruya el provider. Navegar no es refrescar.
    ref.invalidate(areasListControllerProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.areasListadoTitulo)),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : (_area == null || _errorCarga != null)
              ? RisegEmptyState(
                  icon: Icons.error_outline,
                  title: l10n.areasListadoCargaErrorTitulo,
                  message: l10n.areasListadoCargaErrorMensaje,
                  primaryAction: RisegButton(label: l10n.areasListadoBotonReintentar, onPressed: _cargar),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: AppBreakpoints.wide),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      spacing: AppSpacing.sm,
                                      runSpacing: AppSpacing.xs,
                                      children: [
                                        Text(_area!.nombre, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
                                        RisegStatusBadge(
                                          label: _area!.activo ? l10n.areaEstadoActivo : l10n.areaEstadoInactivo,
                                          tone: _area!.activo ? RisegStatusTone.success : RisegStatusTone.neutral,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(_area!.codigo, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                                  ],
                                ),
                              ),
                              RisegButton(
                                key: const Key('area_expediente_boton_editar'),
                                label: l10n.empresaExpedienteBotonEditar,
                                icon: Icons.edit_outlined,
                                onPressed: _editar,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              PopupMenuButton<String>(
                                key: const Key('area_expediente_menu'),
                                icon: Icon(Icons.more_vert, color: colors.textMuted),
                                onSelected: (valor) {
                                  if (valor == 'ciclo_vida') _activarODesactivar();
                                  if (valor == 'eliminar') _eliminarFisicamente();
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'ciclo_vida',
                                    child: Text(_area!.activo ? l10n.areaBotonDesactivar : l10n.areaBotonActivar),
                                  ),
                                  if (esMaestro)
                                    PopupMenuItem(value: 'eliminar', child: Text(l10n.eliminacionFisicaAccionMenu)),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          Text(
                            l10n.areaCantidadPuestos(_puestos.length),
                            style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          if (_puestos.isEmpty)
                            Text(l10n.areaSinPuestosAsociados, style: AppTypography.body.copyWith(color: colors.textMuted))
                          else
                            RisegCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (var i = 0; i < _puestos.length; i++) ...[
                                    if (i > 0) const SizedBox(height: AppSpacing.sm),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(_puestos[i].nombre, style: AppTypography.body.copyWith(color: colors.textPrimary)),
                                        ),
                                        RisegStatusBadge(label: 'N${_puestos[i].nivelJerarquico}', tone: RisegStatusTone.neutral),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }
}
