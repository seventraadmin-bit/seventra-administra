import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart';
import 'package:riseg_one/features/inventario/domain/usecases/obtener_empleados_responsables_servicio_usecase.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';

import 'adjuntar_resguardo_firmado_dialog.dart';
import 'asignar_articulo_dialog.dart';
import 'cerrar_asignacion_dialog.dart';
import 'generar_resguardo_dialog.dart';
import 'reemplazar_asignacion_dialog.dart';

final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

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
/// personal actualmente asignado a este Servicio — resuelta vía
/// `ObtenerEmpleadosResponsablesServicioUseCase` (Inventario), nunca
/// leyendo repositorios de Personal directamente desde esta UI
/// (corrección de cierre de 7B: antes de este ajuste, este archivo
/// importaba `personal_providers.dart` de forma directa, creando una
/// dependencia de dominio adicional evitable).
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
  List<AttachmentData> _resguardos = const [];

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

    final empleadosParaResponsable =
        await ref.read(obtenerEmpleadosResponsablesServicioUseCaseProvider).ejecutar(widget.servicioId);

    // Resguardos (Etapa 7C) — agregado sobre el historial completo,
    // deduplicado por Attachment, mismo criterio que el lado Empleado.
    final historialInventario = await asignacionRepo.listarHistorialPorServicio(widget.servicioId);
    final resguardosPorId = <String, AttachmentData>{};
    for (final asignacion in historialInventario) {
      final adjuntos = await ref.read(attachmentRepositoryProvider).listarActivosPorAsignacion(asignacion.id);
      for (final adjunto in adjuntos) {
        resguardosPorId[adjunto.id] = adjunto;
      }
    }
    final resguardos = resguardosPorId.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (!mounted) return;
    setState(() {
      _inventarioAsignado = inventarioAsignado;
      _articulosPorId = articulosPorId;
      _variantesPorId = variantesPorId;
      _unidadesPorId = unidadesPorId;
      _empleadosParaResponsable = empleadosParaResponsable;
      _resguardos = resguardos;
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

  Future<void> _generarResguardo() async {
    await mostrarDialogoGenerarResguardo(context, ref, asignaciones: _inventarioAsignado, detalleBuilder: _detalle);
  }

  Future<void> _adjuntarResguardoFirmado() async {
    final adjunto = await mostrarDialogoAdjuntarResguardoFirmado(
      context,
      ref,
      asignaciones: _inventarioAsignado,
      detalleBuilder: _detalle,
    );
    if (adjunto) await _cargar();
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
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            RisegButton(
              label: l10n.generarResguardoDialogoTitulo,
              variant: RisegButtonVariant.secondary,
              size: RisegButtonSize.compact,
              onPressed: _inventarioAsignado.isEmpty ? null : _generarResguardo,
            ),
            RisegButton(
              label: l10n.adjuntarResguardoDialogoTitulo,
              variant: RisegButtonVariant.secondary,
              size: RisegButtonSize.compact,
              onPressed: _inventarioAsignado.isEmpty ? null : _adjuntarResguardoFirmado,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
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
        if (_resguardos.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(l10n.resguardoSeccionTitulo, style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
          for (final resguardo in _resguardos)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_formatoFechaHora.format(resguardo.createdAt), style: AppTypography.body.copyWith(color: colors.textMuted)),
                  ),
                  RisegButton(
                    label: l10n.resguardoBotonAbrir,
                    variant: RisegButtonVariant.ghost,
                    size: RisegButtonSize.compact,
                    onPressed: () => ref.read(attachmentStorageProvider).abrir(resguardo.path),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
