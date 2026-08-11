import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/presentation/articulos/articulos_list_screen.dart' show formatoCosto;
import 'package:riseg_one/features/telefonia/data/tables/linea_telefonica_table.dart' show MotivoBajaLineaTelefonica;
import 'package:riseg_one/features/telefonia/domain/usecases/cambiar_estatus_linea_telefonica_usecase.dart';

import 'linea_telefonica_labels.dart';
import 'telefonia_controller.dart';
import '../telefonia_providers.dart';
import 'widgets/dar_de_baja_linea_telefonica_dialog.dart';
import 'widgets/gestionar_linea_telefonica_dialog.dart';
import 'widgets/registrar_plan_linea_telefonica_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Expediente de una línea telefónica (Etapa 9A) — una sola pantalla
/// desplazable con secciones, sin pestañas internas (mismo criterio que
/// `VehiculoExpedienteScreen`). Asignación/Equipo/Documentos llegan en
/// etapas futuras (9B/9C).
class LineaTelefonicaExpedienteScreen extends ConsumerStatefulWidget {
  const LineaTelefonicaExpedienteScreen({required this.lineaTelefonicaId, super.key});

  final String lineaTelefonicaId;

  @override
  ConsumerState<LineaTelefonicaExpedienteScreen> createState() => _LineaTelefonicaExpedienteScreenState();
}

class _LineaTelefonicaExpedienteScreenState extends ConsumerState<LineaTelefonicaExpedienteScreen> {
  LineaTelefonicaData? _linea;
  LineaTelefonicaPlanData? _planVigente;
  List<LineaTelefonicaPlanData> _historialPlanes = const [];
  bool _cargando = true;
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final linea = await ref.read(telefoniaControllerProvider.notifier).obtenerLinea(widget.lineaTelefonicaId);

    final planRepo = ref.read(lineaTelefonicaPlanRepositoryProvider);
    final planVigente = await planRepo.obtenerVigentePorLinea(widget.lineaTelefonicaId);
    final historialPlanes = await planRepo.listarPorLinea(widget.lineaTelefonicaId);

    if (!mounted) return;
    setState(() {
      _linea = linea;
      _planVigente = planVigente;
      _historialPlanes = historialPlanes;
      _cargando = false;
    });
  }

  Future<void> _editar() async {
    final editado = await mostrarDialogoGestionarLineaTelefonica(context, ref, linea: _linea);
    if (editado) await _cargar();
  }

  Future<void> _cambiarEstatus(String estatus) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _procesando = true);
    final resultado = await ref
        .read(telefoniaControllerProvider.notifier)
        .cambiarEstatus(lineaTelefonicaId: widget.lineaTelefonicaId, estatus: estatus);
    if (!mounted) return;
    setState(() => _procesando = false);
    switch (resultado) {
      case CambiarEstatusLineaTelefonicaExitoso():
        RisegFeedback.showSuccess(context, l10n.lineaTelefonicaExpedienteEstatusActualizado);
        await _cargar();
      case CambiarEstatusLineaTelefonicaNoExiste():
      case CambiarEstatusLineaTelefonicaDestinoInvalido():
      case CambiarEstatusLineaTelefonicaYaDeBaja():
      case CambiarEstatusLineaTelefonicaErrorInesperado():
        RisegFeedback.showError(context, l10n.lineaTelefonicaErrorInesperado);
    }
  }

  Future<void> _darDeBaja() async {
    final linea = _linea!;
    final dada = await mostrarDialogoDarDeBajaLineaTelefonica(context, ref, linea);
    if (dada) await _cargar();
  }

  Future<void> _registrarPlan() async {
    final registrado = await mostrarDialogoRegistrarPlanLineaTelefonica(context, ref, widget.lineaTelefonicaId);
    if (registrado) await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final linea = _linea;
    if (linea == null) {
      return Scaffold(appBar: AppBar(), body: RisegEmptyState(title: l10n.telefoniaListadoCargaErrorTitulo, message: ''));
    }

    final esBaja = linea.estatus == 'baja';

    return Scaffold(
      appBar: AppBar(title: Text(linea.numero ?? linea.codigo)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(linea.numero ?? '—', style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
                          Text(linea.codigo, style: AppTypography.body.copyWith(color: colors.textMuted)),
                        ],
                      ),
                    ),
                    RisegStatusBadge(
                      label: estatusLineaTelefonicaLabel(l10n, linea.estatus),
                      tone: estatusLineaTelefonicaTono(linea.estatus),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    RisegButton(
                      label: l10n.lineaTelefonicaExpedienteBotonEditar,
                      variant: RisegButtonVariant.secondary,
                      onPressed: esBaja || _procesando ? null : _editar,
                    ),
                    if (!esBaja && linea.estatus != 'suspendida')
                      RisegButton(
                        label: l10n.lineaTelefonicaExpedienteBotonSuspender,
                        variant: RisegButtonVariant.ghost,
                        onPressed: _procesando ? null : () => _cambiarEstatus('suspendida'),
                      ),
                    if (!esBaja && linea.estatus != 'activa')
                      RisegButton(
                        label: l10n.lineaTelefonicaExpedienteBotonActivar,
                        variant: RisegButtonVariant.ghost,
                        onPressed: _procesando ? null : () => _cambiarEstatus('activa'),
                      ),
                    if (!esBaja)
                      RisegButton(
                        label: l10n.lineaTelefonicaExpedienteBotonDarDeBaja,
                        variant: RisegButtonVariant.danger,
                        onPressed: _procesando ? null : _darDeBaja,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.lineaTelefonicaExpedienteSeccionDatos, style: AppTypography.heading3),
                      const SizedBox(height: AppSpacing.sm),
                      _campo(l10n.lineaTelefonicaCampoOperador, operadorLineaTelefonicaLabel(l10n, linea)),
                      _campo(l10n.lineaTelefonicaCampoModalidadSim, modalidadSimLabel(l10n, linea.modalidadSim)),
                      _campo(l10n.lineaTelefonicaCampoIccid, linea.iccid ?? '—'),
                      _campo(
                        l10n.lineaTelefonicaCampoFechaActivacion,
                        linea.fechaActivacion == null ? '—' : _formatoFecha.format(linea.fechaActivacion!),
                      ),
                      _campo(l10n.lineaTelefonicaCampoObservaciones, linea.observaciones ?? '—'),
                      if (esBaja) ...[
                        const Divider(height: AppSpacing.xl),
                        _campo(l10n.lineaTelefonicaBajaCampoFecha, _formatoFecha.format(linea.fechaBaja!)),
                        _campo(
                          l10n.lineaTelefonicaBajaCampoMotivo,
                          linea.motivoBaja == null
                              ? '—'
                              : motivoBajaLineaTelefonicaLabel(l10n, MotivoBajaLineaTelefonica.values.byName(linea.motivoBaja!)),
                        ),
                        _campo(l10n.lineaTelefonicaBajaCampoObservaciones, linea.observacionesBaja ?? '—'),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RisegSectionHeader(
                        title: l10n.lineaTelefonicaPlanSeccionTitulo,
                        primaryAction: esBaja
                            ? null
                            : RisegButton(
                                label: l10n.lineaTelefonicaBotonRegistrarPlan,
                                variant: RisegButtonVariant.secondary,
                                size: RisegButtonSize.compact,
                                onPressed: _registrarPlan,
                              ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_planVigente == null)
                        Text(l10n.lineaTelefonicaPlanVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else ...[
                        _campo(l10n.lineaTelefonicaPlanCampoNombre, _planVigente!.nombre),
                        _campo(l10n.lineaTelefonicaPlanCampoCostoMensual, formatoCosto(_planVigente!.costoMensual)),
                        _campo(
                          l10n.lineaTelefonicaPlanCampoFechaInicioVigencia,
                          _formatoFecha.format(_planVigente!.fechaInicioVigencia),
                        ),
                        if (_planVigente!.fechaFinPermanencia != null)
                          _campo(
                            l10n.lineaTelefonicaPlanCampoFechaFinPermanencia,
                            _formatoFecha.format(_planVigente!.fechaFinPermanencia!),
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.lineaTelefonicaPlanHistorialTitulo, style: AppTypography.heading3),
                      const SizedBox(height: AppSpacing.sm),
                      RisegTableBase<LineaTelefonicaPlanData>(
                        rows: _historialPlanes,
                        emptyState: RisegEmptyState(title: l10n.lineaTelefonicaPlanHistorialVacio, message: ''),
                        columns: [
                          RisegColumn<LineaTelefonicaPlanData>(
                            label: l10n.lineaTelefonicaPlanColumnaNombre,
                            cellBuilder: (p) => Text(p.nombre),
                          ),
                          RisegColumn<LineaTelefonicaPlanData>(
                            label: l10n.lineaTelefonicaPlanColumnaCosto,
                            width: 110,
                            alignment: TextAlign.right,
                            cellBuilder: (p) => Text(formatoCosto(p.costoMensual)),
                          ),
                          RisegColumn<LineaTelefonicaPlanData>(
                            label: l10n.lineaTelefonicaPlanColumnaVigenciaDesde,
                            width: 110,
                            cellBuilder: (p) => Text(_formatoFecha.format(p.fechaInicioVigencia)),
                          ),
                          RisegColumn<LineaTelefonicaPlanData>(
                            label: l10n.lineaTelefonicaPlanColumnaVigenciaHasta,
                            width: 110,
                            cellBuilder: (p) => Text(p.fechaFinVigencia == null ? '—' : _formatoFecha.format(p.fechaFinVigencia!)),
                          ),
                        ],
                      ),
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

  Widget _campo(String etiqueta, String valor) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 180, child: Text(etiqueta, style: AppTypography.label.copyWith(color: colors.textMuted))),
          Expanded(child: Text(valor, style: AppTypography.body)),
        ],
      ),
    );
  }
}
