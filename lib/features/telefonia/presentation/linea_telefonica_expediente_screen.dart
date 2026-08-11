import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/presentation/articulos/articulos_list_screen.dart' show formatoCosto;
import 'package:riseg_one/features/telefonia/data/tables/linea_telefonica_table.dart' show MotivoBajaLineaTelefonica;
import 'package:riseg_one/features/telefonia/domain/repositories/linea_telefonica_equipo_repository.dart'
    show CustodiaInventarioLineaTelefonica;
import 'package:riseg_one/features/telefonia/domain/usecases/cambiar_estatus_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/obtener_equipos_disponibles_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

import 'linea_telefonica_labels.dart';
import 'telefonia_controller.dart';
import '../telefonia_providers.dart';
import 'widgets/asignar_linea_telefonica_dialog.dart';
import 'widgets/asociar_equipo_linea_telefonica_dialog.dart';
import 'widgets/cambiar_asignacion_linea_telefonica_dialog.dart';
import 'widgets/cambiar_equipo_linea_telefonica_dialog.dart';
import 'widgets/dar_de_baja_linea_telefonica_dialog.dart';
import 'widgets/eliminar_linea_telefonica_fisicamente_dialog.dart';
import 'widgets/gestionar_linea_telefonica_dialog.dart';
import 'widgets/registrar_recarga_linea_telefonica_dialog.dart';
import 'widgets/retirar_asignacion_linea_telefonica_dialog.dart';
import 'widgets/retirar_equipo_linea_telefonica_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Expediente de una línea telefónica (Etapa 9B) — una sola pantalla
/// desplazable con secciones, sin pestañas internas (mismo criterio que
/// `VehiculoExpedienteScreen`). Documentos llega en la Etapa 9C.
class LineaTelefonicaExpedienteScreen extends ConsumerStatefulWidget {
  const LineaTelefonicaExpedienteScreen({required this.lineaTelefonicaId, super.key});

  final String lineaTelefonicaId;

  @override
  ConsumerState<LineaTelefonicaExpedienteScreen> createState() => _LineaTelefonicaExpedienteScreenState();
}

class _LineaTelefonicaExpedienteScreenState extends ConsumerState<LineaTelefonicaExpedienteScreen> {
  LineaTelefonicaData? _linea;
  RecargaLineaTelefonicaData? _ultimaRecarga;
  int _totalRecargas = 0;
  List<RecargaLineaTelefonicaData> _historialRecargas = const [];
  AsignacionLineaTelefonicaData? _asignacionVigente;
  List<AsignacionLineaTelefonicaData> _historialAsignaciones = const [];
  Map<String, String> _empleadosPorId = const {};
  Map<String, String> _serviciosPorId = const {};
  LineaTelefonicaEquipoData? _equipoVigente;
  List<LineaTelefonicaEquipoData> _historialEquipos = const [];
  Map<String, EquipoOpcionLineaTelefonica> _equipoInfoPorUnidadId = const {};
  CustodiaInventarioLineaTelefonica? _custodiaInventario;
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

    final recargaRepo = ref.read(recargaLineaTelefonicaRepositoryProvider);
    final historialRecargas = await recargaRepo.listarPorLinea(widget.lineaTelefonicaId);
    final ultimaRecarga = historialRecargas.isEmpty ? null : historialRecargas.first;
    final totalRecargas = await recargaRepo.totalPorLinea(widget.lineaTelefonicaId);

    final asignacionRepo = ref.read(asignacionLineaTelefonicaRepositoryProvider);
    final asignacionVigente = await asignacionRepo.obtenerActivaPorLinea(widget.lineaTelefonicaId);
    final historialAsignaciones = await asignacionRepo.listarPorLinea(widget.lineaTelefonicaId);
    final opciones = ref.read(obtenerOpcionesAsignacionLineaTelefonicaUseCaseProvider);
    final empleados = await opciones.obtenerEmpleados();
    final servicios = await opciones.obtenerServicios();

    final equipoRepo = ref.read(lineaTelefonicaEquipoRepositoryProvider);
    final equipoVigente = await equipoRepo.obtenerActualPorLinea(widget.lineaTelefonicaId);
    final historialEquipos = await equipoRepo.listarPorLinea(widget.lineaTelefonicaId);
    final equiposUseCase = ref.read(obtenerEquiposDisponiblesLineaTelefonicaUseCaseProvider);
    final equipoInfoPorUnidadId = <String, EquipoOpcionLineaTelefonica>{};
    for (final unidadId in historialEquipos.map((e) => e.unidadId).toSet()) {
      final info = await equiposUseCase.obtenerInfo(unidadId);
      if (info != null) equipoInfoPorUnidadId[unidadId] = info;
    }
    final custodiaInventario =
        equipoVigente == null ? null : await equipoRepo.obtenerCustodiaInventarioActual(equipoVigente.unidadId);

    if (!mounted) return;
    setState(() {
      _linea = linea;
      _ultimaRecarga = ultimaRecarga;
      _totalRecargas = totalRecargas;
      _historialRecargas = historialRecargas;
      _asignacionVigente = asignacionVigente;
      _historialAsignaciones = historialAsignaciones;
      _empleadosPorId = {for (final e in empleados) e.id: e.nombre};
      _serviciosPorId = {for (final s in servicios) s.id: s.nombre};
      _equipoVigente = equipoVigente;
      _historialEquipos = historialEquipos;
      _equipoInfoPorUnidadId = equipoInfoPorUnidadId;
      _custodiaInventario = custodiaInventario;
      _cargando = false;
    });
  }

  String _destinoAsignacion(AsignacionLineaTelefonicaData asignacion) {
    return destinoAsignacionLineaTelefonicaLabel(asignacion, empleadosPorId: _empleadosPorId, serviciosPorId: _serviciosPorId);
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

  Future<void> _eliminarFisicamente() async {
    final eliminado = await mostrarDialogoEliminarLineaTelefonicaFisicamente(context, ref, widget.lineaTelefonicaId);
    if (eliminado && mounted) context.pop();
  }

  Future<void> _registrarRecarga() async {
    final registrada = await mostrarDialogoRegistrarRecargaLineaTelefonica(context, ref, widget.lineaTelefonicaId);
    if (registrada) await _cargar();
  }

  Future<void> _asignar() async {
    final asignado = await mostrarDialogoAsignarLineaTelefonica(
      context,
      ref,
      widget.lineaTelefonicaId,
      tieneEquipoAsociado: _equipoVigente != null,
    );
    if (asignado) await _cargar();
  }

  Future<void> _cambiarAsignacion() async {
    final cambiado = await mostrarDialogoCambiarAsignacionLineaTelefonica(
      context,
      ref,
      _asignacionVigente!,
      tieneEquipoAsociado: _equipoVigente != null,
    );
    if (cambiado) await _cargar();
  }

  Future<void> _retirarAsignacion() async {
    final retirado = await mostrarDialogoRetirarAsignacionLineaTelefonica(
      context,
      ref,
      _asignacionVigente!,
      tieneEquipoAsociado: _equipoVigente != null,
    );
    if (retirado) await _cargar();
  }

  Future<void> _asociarEquipo() async {
    final asociado = await mostrarDialogoAsociarEquipoLineaTelefonica(context, ref, widget.lineaTelefonicaId);
    if (asociado) await _cargar();
  }

  Future<void> _cambiarEquipo() async {
    final cambiado = await mostrarDialogoCambiarEquipoLineaTelefonica(context, ref, widget.lineaTelefonicaId);
    if (cambiado) await _cargar();
  }

  Future<void> _retirarEquipo() async {
    final retirado = await mostrarDialogoRetirarEquipoLineaTelefonica(context, ref, widget.lineaTelefonicaId);
    if (retirado) await _cargar();
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
    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;

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
                    if (esMaestro)
                      RisegButton(
                        label: l10n.eliminacionFisicaAccionMenu,
                        variant: RisegButtonVariant.danger,
                        onPressed: _eliminarFisicamente,
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
                        title: l10n.lineaTelefonicaRecargaSeccionTitulo,
                        primaryAction: esBaja
                            ? null
                            : RisegButton(
                                label: l10n.lineaTelefonicaBotonRegistrarRecarga,
                                variant: RisegButtonVariant.secondary,
                                size: RisegButtonSize.compact,
                                onPressed: _registrarRecarga,
                              ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_ultimaRecarga == null)
                        Text(l10n.lineaTelefonicaRecargaVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else ...[
                        _campo(
                          l10n.lineaTelefonicaRecargaCampoUltima,
                          '${_formatoFecha.format(_ultimaRecarga!.fecha)} — ${formatoCosto(_ultimaRecarga!.importe)}',
                        ),
                        _campo(l10n.lineaTelefonicaRecargaCampoTotal, formatoCosto(_totalRecargas)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.lineaTelefonicaRecargaHistorialTitulo, style: AppTypography.heading3),
                      const SizedBox(height: AppSpacing.sm),
                      RisegTableBase<RecargaLineaTelefonicaData>(
                        rows: _historialRecargas,
                        emptyState: RisegEmptyState(title: l10n.lineaTelefonicaRecargaHistorialVacio, message: ''),
                        columns: [
                          RisegColumn<RecargaLineaTelefonicaData>(
                            label: l10n.lineaTelefonicaRecargaColumnaFecha,
                            width: 110,
                            cellBuilder: (r) => Text(_formatoFecha.format(r.fecha)),
                          ),
                          RisegColumn<RecargaLineaTelefonicaData>(
                            label: l10n.lineaTelefonicaRecargaColumnaImporte,
                            width: 110,
                            alignment: TextAlign.right,
                            cellBuilder: (r) => Text(formatoCosto(r.importe)),
                          ),
                          RisegColumn<RecargaLineaTelefonicaData>(
                            label: l10n.lineaTelefonicaRecargaColumnaObservaciones,
                            cellBuilder: (r) => Text(r.observaciones ?? '—'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RisegSectionHeader(
                        title: l10n.lineaTelefonicaAsignacionSeccionTitulo,
                        primaryAction: esBaja
                            ? null
                            : (_asignacionVigente == null
                                ? RisegButton(
                                    label: l10n.lineaTelefonicaBotonAsignar,
                                    variant: RisegButtonVariant.secondary,
                                    size: RisegButtonSize.compact,
                                    onPressed: _asignar,
                                  )
                                : null),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_asignacionVigente == null)
                        Text(l10n.lineaTelefonicaAsignacionVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else ...[
                        _campo(l10n.lineaTelefonicaAsignacionDestino, _destinoAsignacion(_asignacionVigente!)),
                        _campo(l10n.lineaTelefonicaAsignacionDesde, _formatoFecha.format(_asignacionVigente!.fechaInicio)),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            RisegButton(
                              label: l10n.lineaTelefonicaBotonCambiarAsignacion,
                              variant: RisegButtonVariant.ghost,
                              size: RisegButtonSize.compact,
                              onPressed: _cambiarAsignacion,
                            ),
                            RisegButton(
                              label: l10n.lineaTelefonicaBotonRetirarAsignacion,
                              variant: RisegButtonVariant.ghost,
                              size: RisegButtonSize.compact,
                              onPressed: _retirarAsignacion,
                            ),
                          ],
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
                      RisegSectionHeader(
                        title: l10n.lineaTelefonicaEquipoSeccionTitulo,
                        primaryAction: esBaja
                            ? null
                            : (_equipoVigente == null
                                ? RisegButton(
                                    label: l10n.lineaTelefonicaBotonAsociarEquipo,
                                    variant: RisegButtonVariant.secondary,
                                    size: RisegButtonSize.compact,
                                    onPressed: _asociarEquipo,
                                  )
                                : null),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_equipoVigente == null)
                        Text(l10n.lineaTelefonicaEquipoVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else ...[
                        _campo(l10n.lineaTelefonicaColumnaEquipo, _equipoLabel(_equipoVigente!.unidadId)),
                        _campo(l10n.lineaTelefonicaEquipoDesde, _formatoFecha.format(_equipoVigente!.fechaInicio)),
                        if (_divergenciaEquipo() case final advertencia?) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(advertencia, style: AppTypography.caption.copyWith(color: colors.error)),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            RisegButton(
                              label: l10n.lineaTelefonicaBotonCambiarEquipo,
                              variant: RisegButtonVariant.ghost,
                              size: RisegButtonSize.compact,
                              onPressed: _cambiarEquipo,
                            ),
                            RisegButton(
                              label: l10n.lineaTelefonicaBotonRetirarEquipo,
                              variant: RisegButtonVariant.ghost,
                              size: RisegButtonSize.compact,
                              onPressed: _retirarEquipo,
                            ),
                          ],
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
                      Text(l10n.lineaTelefonicaHistorialAsignacionesTitulo, style: AppTypography.heading3),
                      const SizedBox(height: AppSpacing.sm),
                      RisegTableBase<AsignacionLineaTelefonicaData>(
                        rows: _historialAsignaciones,
                        emptyState: RisegEmptyState(title: l10n.lineaTelefonicaHistorialAsignacionesVacio, message: ''),
                        columns: [
                          RisegColumn<AsignacionLineaTelefonicaData>(
                            label: l10n.lineaTelefonicaColumnaDestino,
                            cellBuilder: (a) => Text(_destinoAsignacion(a)),
                          ),
                          RisegColumn<AsignacionLineaTelefonicaData>(
                            label: l10n.lineaTelefonicaColumnaFechaInicio,
                            width: 110,
                            cellBuilder: (a) => Text(_formatoFecha.format(a.fechaInicio)),
                          ),
                          RisegColumn<AsignacionLineaTelefonicaData>(
                            label: l10n.lineaTelefonicaColumnaFechaTermino,
                            width: 110,
                            cellBuilder: (a) => Text(a.fechaTermino == null ? '—' : _formatoFecha.format(a.fechaTermino!)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.lineaTelefonicaHistorialEquiposTitulo, style: AppTypography.heading3),
                      const SizedBox(height: AppSpacing.sm),
                      RisegTableBase<LineaTelefonicaEquipoData>(
                        rows: _historialEquipos,
                        emptyState: RisegEmptyState(title: l10n.lineaTelefonicaHistorialEquiposVacio, message: ''),
                        columns: [
                          RisegColumn<LineaTelefonicaEquipoData>(
                            label: l10n.lineaTelefonicaColumnaEquipo,
                            cellBuilder: (e) => Text(_equipoLabel(e.unidadId)),
                          ),
                          RisegColumn<LineaTelefonicaEquipoData>(
                            label: l10n.lineaTelefonicaColumnaFechaInicio,
                            width: 110,
                            cellBuilder: (e) => Text(_formatoFecha.format(e.fechaInicio)),
                          ),
                          RisegColumn<LineaTelefonicaEquipoData>(
                            label: l10n.lineaTelefonicaColumnaFechaTermino,
                            width: 110,
                            cellBuilder: (e) => Text(e.fechaFin == null ? '—' : _formatoFecha.format(e.fechaFin!)),
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

  String _equipoLabel(String unidadId) {
    final info = _equipoInfoPorUnidadId[unidadId];
    if (info == null) return unidadId;
    return '${info.codigo} · ${info.descripcion}';
  }

  /// Advertencia de divergencia (Etapa 9B, punto 5) — `null` si no hay
  /// nada que advertir (sin equipo, o la custodia real en Inventario
  /// coincide con la asignación vigente de la línea). Nunca corrige
  /// nada automáticamente, solo informa.
  String? _divergenciaEquipo() {
    final l10n = AppLocalizations.of(context)!;
    final equipo = _equipoVigente;
    if (equipo == null) return null;

    final destinoLineaEmpleado = _asignacionVigente?.empleadoId;
    final destinoLineaServicio = _asignacionVigente?.servicioId;
    final custodia = _custodiaInventario;

    final coincide = custodia != null &&
        custodia.empleadoId == destinoLineaEmpleado &&
        custodia.servicioId == destinoLineaServicio;
    if (coincide) return null;
    if (custodia == null && destinoLineaEmpleado == null && destinoLineaServicio == null) return null;

    if (custodia == null) return l10n.lineaTelefonicaEquipoDivergenciaSinCustodia;

    final destino = custodia.empleadoId != null
        ? (_empleadosPorId[custodia.empleadoId] ?? custodia.empleadoId!)
        : (_serviciosPorId[custodia.servicioId] ?? custodia.servicioId ?? '—');
    return l10n.lineaTelefonicaEquipoDivergenciaAdvertencia(destino);
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
