import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';
import 'package:riseg_one/features/personal/personal_providers.dart';
import 'package:riseg_one/features/personal/presentation/empleados/empleados_list_screen.dart' show empleadoNombreCompleto;

import 'asignar_articulo_dialog.dart';
import 'cerrar_asignacion_dialog.dart';
import 'reemplazar_asignacion_dialog.dart';

/// Sección "Inventario asignado" para el expediente de un Servicio
/// (Etapa 7B) — autocontenida (carga y estado propios) para no tocar
/// `ServicioExpedienteController`, mismo criterio de aislamiento que
/// `UbicacionesArbolWidget` en el expediente de Sucursal. Un teléfono/
/// radio puede pertenecer administrativamente al Servicio sin que
/// ningún guardia en particular lo tenga asignado hoy — este es el
/// destino "Servicio" de `Asignacion`, distinto del de Empleado.
///
/// Para "empleado responsable" del descuento (cuando se reporta daño/
/// pérdida de un bien del Servicio), la lista de candidatos es el
/// personal actualmente asignado a este Servicio (`AsignacionServicio`
/// vigente) — el operador elige a quién atribuir, nunca se infiere.
class InventarioAsignadoServicioSection extends ConsumerStatefulWidget {
  const InventarioAsignadoServicioSection({required this.servicioId, super.key});

  final String servicioId;

  @override
  ConsumerState<InventarioAsignadoServicioSection> createState() => _InventarioAsignadoServicioSectionState();
}

class _InventarioAsignadoServicioSectionState extends ConsumerState<InventarioAsignadoServicioSection> {
  bool _cargando = true;
  List<AsignacionData> _inventarioAsignado = const [];
  Map<String, ArticuloData> _articulosPorId = const {};
  Map<String, String> _variantesPorId = const {};
  Map<String, String> _unidadesPorId = const {};
  List<EmpleadoOpcion> _empleadosParaResponsable = const [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final asignacionRepo = ref.read(asignacionRepositoryProvider);
    final articuloRepo = ref.read(articuloRepositoryProvider);

    final inventarioAsignado = await asignacionRepo.listarActivasPorServicio(widget.servicioId);

    final articulosPorId = <String, ArticuloData>{};
    for (final articuloId in inventarioAsignado.map((a) => a.articuloId).toSet()) {
      final articulo = await articuloRepo.obtenerPorId(articuloId);
      if (articulo != null) articulosPorId[articuloId] = articulo;
    }
    final variantesPorId = <String, String>{};
    for (final varianteId in inventarioAsignado.map((a) => a.varianteId).whereType<String>().toSet()) {
      final articuloId = inventarioAsignado.firstWhere((a) => a.varianteId == varianteId).articuloId;
      final variantes = await articuloRepo.listarVariantes(articuloId, soloActivas: false);
      final variante = variantes.where((v) => v.id == varianteId).firstOrNull;
      if (variante != null) variantesPorId[varianteId] = variante.valor;
    }
    final unidadesPorId = <String, String>{};
    for (final unidadId in inventarioAsignado.map((a) => a.unidadId).whereType<String>().toSet()) {
      final unidad = await ref.read(inventarioRepositoryProvider).obtenerUnidadPorId(unidadId);
      if (unidad != null) unidadesPorId[unidadId] = '${unidad.codigo} · ${unidad.numeroSerie}';
    }

    final asignacionesServicio = await ref.read(asignacionServicioRepositoryProvider).listarActivasPorServicio(widget.servicioId);
    final empleadosParaResponsable = <EmpleadoOpcion>[];
    for (final a in asignacionesServicio) {
      final empleado = await ref.read(empleadoRepositoryProvider).obtenerPorId(a.empleadoId);
      if (empleado != null) empleadosParaResponsable.add(EmpleadoOpcion(id: empleado.id, nombre: empleadoNombreCompleto(empleado)));
    }

    if (!mounted) return;
    setState(() {
      _inventarioAsignado = inventarioAsignado;
      _articulosPorId = articulosPorId;
      _variantesPorId = variantesPorId;
      _unidadesPorId = unidadesPorId;
      _empleadosParaResponsable = empleadosParaResponsable;
      _cargando = false;
    });
  }

  String _detalle(AsignacionData asignacion) {
    final articulo = _articulosPorId[asignacion.articuloId];
    final nombre = articulo?.nombre ?? asignacion.articuloId;
    final variante = asignacion.varianteId == null ? null : _variantesPorId[asignacion.varianteId];
    final unidad = asignacion.unidadId == null ? null : _unidadesPorId[asignacion.unidadId];
    if (unidad != null) return '$nombre · $unidad';
    if (variante != null) return '${asignacion.cantidad} × $nombre ($variante)';
    return '${asignacion.cantidad} × $nombre';
  }

  Future<void> _asignar() async {
    final asignado = await mostrarDialogoAsignarArticulo(context, ref, servicioId: widget.servicioId);
    if (asignado) await _cargar();
  }

  Future<void> _devolver(AsignacionData asignacion) async {
    final l10n = AppLocalizations.of(context)!;
    final cerrado = await mostrarDialogoCerrarAsignacion(
      context,
      ref,
      asignacion: asignacion,
      titulo: l10n.cerrarAsignacionDialogoTituloDevolver,
      motivosDisponibles: const [
        MotivoCierreAsignacion.desgaste,
        MotivoCierreAsignacion.cambioTalla,
        MotivoCierreAsignacion.defecto,
        MotivoCierreAsignacion.otro,
      ],
      empleadosParaResponsable: _empleadosParaResponsable,
    );
    if (cerrado) await _cargar();
  }

  Future<void> _reportarDanoPerdida(AsignacionData asignacion) async {
    final l10n = AppLocalizations.of(context)!;
    final cerrado = await mostrarDialogoCerrarAsignacion(
      context,
      ref,
      asignacion: asignacion,
      titulo: l10n.cerrarAsignacionDialogoTituloDanoPerdida,
      motivosDisponibles: const [MotivoCierreAsignacion.dano, MotivoCierreAsignacion.perdida],
      empleadosParaResponsable: _empleadosParaResponsable,
    );
    if (cerrado) await _cargar();
  }

  Future<void> _reemplazar(AsignacionData asignacion) async {
    final reemplazado = await mostrarDialogoReemplazarAsignacion(
      context,
      ref,
      asignacion: asignacion,
      empleadosParaResponsable: _empleadosParaResponsable,
    );
    if (reemplazado) await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegSectionHeader(
          title: l10n.asignacionSeccionTitulo,
          primaryAction: RisegButton(
            label: l10n.asignacionBotonAsignar,
            variant: RisegButtonVariant.ghost,
            size: RisegButtonSize.compact,
            onPressed: _asignar,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (_cargando)
          const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.md), child: Center(child: CircularProgressIndicator()))
        else if (_inventarioAsignado.isEmpty)
          Text(l10n.asignacionSeccionVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
        else
          for (final asignacion in _inventarioAsignado)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(child: Text(_detalle(asignacion), style: AppTypography.body)),
                  Wrap(
                    spacing: AppSpacing.xxs,
                    children: [
                      RisegButton(
                        label: l10n.asignacionBotonDevolver,
                        variant: RisegButtonVariant.ghost,
                        size: RisegButtonSize.compact,
                        onPressed: () => _devolver(asignacion),
                      ),
                      RisegButton(
                        label: l10n.asignacionBotonReemplazar,
                        variant: RisegButtonVariant.ghost,
                        size: RisegButtonSize.compact,
                        onPressed: () => _reemplazar(asignacion),
                      ),
                      RisegButton(
                        label: l10n.asignacionBotonReportarDanoPerdida,
                        variant: RisegButtonVariant.ghost,
                        size: RisegButtonSize.compact,
                        onPressed: () => _reportarDanoPerdida(asignacion),
                      ),
                    ],
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
