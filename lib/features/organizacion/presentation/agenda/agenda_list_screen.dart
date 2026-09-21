import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_por_cobrar/cuentas_por_cobrar_controller.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/documento_por_emitir_requiere_accion.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

import '../../organizacion_providers.dart';
import 'agenda_controller.dart';
import 'agenda_resumen_periodo.dart';
import 'agenda_state.dart';
import 'widgets/agenda_crear_manual_dialog.dart';
import 'widgets/agenda_detalle_dialog.dart';
import 'widgets/agenda_resumen_periodo_row.dart';
import 'widgets/eliminar_documento_por_emitir_fisicamente_dialog.dart';

final _formatoMes = DateFormat('MMMM yyyy', 'es_MX');
final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoMoneda = NumberFormat.currency(locale: 'es_MX', symbol: r'$');

String formatoCentavosAgenda(int centavos) => _formatoMoneda.format(centavos / 100);

/// Listado de la Agenda de documentos por emitir (Etapa 4I.1) — filtros
/// por Cliente/estatus/tipo de documento sobre un rango de fechas de
/// **emisión programada** (nunca "periodo iniciado en"), generación
/// automática del rango visible, creación manual y detalle por fila.
class AgendaListScreen extends ConsumerStatefulWidget {
  const AgendaListScreen({super.key});

  @override
  ConsumerState<AgendaListScreen> createState() => _AgendaListScreenState();
}

class _AgendaListScreenState extends ConsumerState<AgendaListScreen> {
  List<ClienteData> _clientes = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final clientes = await ref.read(clienteRepositoryProvider).listarActivos();
      if (mounted) setState(() => _clientes = clientes);
    });
  }

  String _clienteNombre(String clienteId) {
    for (final c in _clientes) {
      if (c.id == clienteId) return c.nombreComercial;
    }
    return clienteId;
  }

  String _estatusLabel(AppLocalizations l10n, String estatus) {
    return switch (EstatusDocumentoPorEmitir.values.byName(estatus)) {
      EstatusDocumentoPorEmitir.pendiente => l10n.agendaEstatusPendiente,
      EstatusDocumentoPorEmitir.enPreparacion => l10n.agendaEstatusEnPreparacion,
      EstatusDocumentoPorEmitir.cancelado => l10n.agendaEstatusCancelado,
      EstatusDocumentoPorEmitir.noRequerido => l10n.agendaEstatusNoRequerido,
      EstatusDocumentoPorEmitir.emitido => l10n.agendaEstatusEmitido,
      EstatusDocumentoPorEmitir.enviado => l10n.agendaEstatusEnviado,
      EstatusDocumentoPorEmitir.procesadoAceptado => l10n.agendaEstatusProcesadoAceptado,
    };
  }

  RisegStatusTone _estatusTono(String estatus) {
    return switch (EstatusDocumentoPorEmitir.values.byName(estatus)) {
      EstatusDocumentoPorEmitir.pendiente => RisegStatusTone.info,
      EstatusDocumentoPorEmitir.enPreparacion => RisegStatusTone.warning,
      EstatusDocumentoPorEmitir.cancelado => RisegStatusTone.neutral,
      EstatusDocumentoPorEmitir.noRequerido => RisegStatusTone.neutral,
      EstatusDocumentoPorEmitir.emitido => RisegStatusTone.info,
      EstatusDocumentoPorEmitir.enviado => RisegStatusTone.info,
      EstatusDocumentoPorEmitir.procesadoAceptado => RisegStatusTone.success,
    };
  }

  String _tipoDocumentoLabel(AppLocalizations l10n, String tipoDocumento) {
    return switch (TipoDocumentoCobro.values.byName(tipoDocumento)) {
      TipoDocumentoCobro.cfdi => l10n.servicioCobroTipoDocumentoCfdi,
      TipoDocumentoCobro.reciboDePago => l10n.servicioCobroTipoDocumentoReciboDePago,
    };
  }

  void _cambiarMes(AgendaState state, int delta) {
    final nuevoInicio = DateTime(state.rangoInicio.year, state.rangoInicio.month + delta, 1);
    final nuevoFin = DateTime(nuevoInicio.year, nuevoInicio.month + 1, 0);
    ref.read(agendaControllerProvider.notifier).aplicarFiltros(rangoInicio: nuevoInicio, rangoFin: nuevoFin);
  }

  Future<void> _generar(AgendaState state) async {
    final l10n = AppLocalizations.of(context)!;
    final resultado = await ref.read(agendaControllerProvider.notifier).generar();
    if (!mounted) return;
    if (resultado == null) {
      RisegFeedback.showError(context, l10n.accesoDenegadoAccionMensaje);
      return;
    }
    RisegFeedback.showSuccess(
      context,
      l10n.agendaGenerarExito(resultado.creados.length, resultado.yaExistian),
    );
  }

  Future<void> _mostrarDialogoCrearManual() async {
    final creado = await mostrarDialogoCrearDocumentoManual(context, ref);
    if (creado && mounted) {
      final l10n = AppLocalizations.of(context)!;
      RisegFeedback.showSuccess(context, l10n.agendaCrearManualExito);
    }
  }

  Future<void> _mostrarDetalle(DocumentoPorEmitirData documento) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AgendaDetalleDialog(documentoPorEmitirId: documento.id),
    );
  }

  /// Eliminación física individual directo desde la fila (pedido
  /// explícito: la única vía antes era abrir el detalle completo). Misma
  /// facultad exclusiva del Maestro, mismo diálogo de confirmación con
  /// motivo y mismo use case que `AgendaDetalleDialog._eliminarFisicamente`
  /// — nunca una segunda ruta de eliminación.
  Future<void> _eliminarFisicamenteDesdeFila(DocumentoPorEmitirData documento) async {
    final eliminado = await mostrarDialogoEliminarDocumentoPorEmitirFisicamente(context, ref, documento.id);
    if (!eliminado) return;
    ref.invalidate(agendaControllerProvider);
    ref.invalidate(cuentasPorCobrarControllerProvider);
    // Etapa 20 (hueco real encontrado): el Dashboard lee la misma
    // CuentaPorCobrar para Cobranza/"Requiere atención".
    ref.invalidate(dashboardControllerProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(agendaControllerProvider);
    final notifier = ref.read(agendaControllerProvider.notifier);
    final hoy = DateTime.now();
    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;

    if (state.errorCarga != null && state.documentos.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.agendaListadoCargaErrorTitulo,
        message: l10n.agendaListadoCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('agenda_boton_reintentar'),
          label: l10n.agendaListadoBotonReintentar,
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
            title: l10n.agendaListadoTitulo,
            description: l10n.agendaListadoSubtitulo,
            primaryAction: RisegButton(
              key: const Key('agenda_boton_generar'),
              label: l10n.agendaListadoBotonGenerar,
              loading: state.generando,
              onPressed: () => _generar(state),
            ),
            secondaryAction: RisegButton(
              key: const Key('agenda_boton_crear_manual'),
              label: l10n.agendaListadoBotonCrearManual,
              variant: RisegButtonVariant.secondary,
              onPressed: _mostrarDialogoCrearManual,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AgendaResumenPeriodoRow(resumen: calcularResumenPeriodoAgenda(state.documentos, hoy)),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: l10n.agendaListadoBotonMesAnterior,
                    onPressed: () => _cambiarMes(state, -1),
                  ),
                  SizedBox(
                    width: 160,
                    child: Text(
                      _tituloMesCapitalizado(state.rangoInicio),
                      textAlign: TextAlign.center,
                      style: AppTypography.label,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: l10n.agendaListadoBotonMesSiguiente,
                    onPressed: () => _cambiarMes(state, 1),
                  ),
                ],
              ),
              SizedBox(
                width: 200,
                child: RisegSelect<String?>(
                  label: l10n.agendaListadoFiltroCliente,
                  value: state.clienteId,
                  items: [
                    RisegSelectItem(value: null, label: l10n.agendaListadoFiltroClienteTodos),
                    for (final c in _clientes) RisegSelectItem(value: c.id, label: c.nombreComercial),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(clienteId: valor, limpiarClienteId: valor == null),
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegSelect<String?>(
                  label: l10n.agendaListadoFiltroTipoDocumento,
                  value: state.tipoDocumento,
                  items: [
                    RisegSelectItem(value: null, label: l10n.agendaListadoFiltroTipoDocumentoTodos),
                    RisegSelectItem(
                      value: TipoDocumentoCobro.cfdi.name,
                      label: l10n.servicioCobroTipoDocumentoCfdi,
                    ),
                    RisegSelectItem(
                      value: TipoDocumentoCobro.reciboDePago.name,
                      label: l10n.servicioCobroTipoDocumentoReciboDePago,
                    ),
                  ],
                  onChanged: (valor) =>
                      notifier.aplicarFiltros(tipoDocumento: valor, limpiarTipoDocumento: valor == null),
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegSelect<String?>(
                  label: l10n.agendaListadoFiltroEstatus,
                  value: state.estatus,
                  items: [
                    RisegSelectItem(value: null, label: l10n.agendaListadoFiltroEstatusTodos),
                    for (final e in EstatusDocumentoPorEmitir.values)
                      RisegSelectItem(value: e.name, label: _estatusLabel(l10n, e.name)),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(estatus: valor, limpiarEstatus: valor == null),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<DocumentoPorEmitirData>(
              loading: state.cargando,
              rows: state.documentos,
              onRowTap: _mostrarDetalle,
              emptyState: RisegEmptyState(
                title: l10n.agendaListadoVacioTitulo,
                message: l10n.agendaListadoVacioMensaje,
              ),
              // Eliminación física individual por fila (pedido explícito)
              // — Maestro-only, mismo criterio que el resto de la app:
              // el ítem de menú solo se muestra si `esMaestro`, pero la
              // protección real vive en el provider `exigirMaestro`.
              rowActionsBuilder: esMaestro
                  ? (d) => RisegActionsMenu(
                        menuKey: Key('agenda_fila_menu_acciones_${d.id}'),
                        actions: [
                          RisegMenuAction(
                            key: Key('agenda_fila_accion_eliminar_fisicamente_${d.id}'),
                            label: l10n.eliminacionFisicaAccionMenu,
                            icon: Icons.delete_forever_outlined,
                            destructive: true,
                            onTap: () => _eliminarFisicamenteDesdeFila(d),
                          ),
                        ],
                      )
                  : null,
              columns: [
                RisegColumn<DocumentoPorEmitirData>(
                  label: l10n.agendaColumnaDocumento,
                  width: 150,
                  cellBuilder: (d) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(d.codigo, style: AppTypography.bodyStrong.copyWith(color: context.colors.textPrimary)),
                      const SizedBox(height: 2),
                      RisegStatusBadge(label: _tipoDocumentoLabel(l10n, d.tipoDocumento), tone: RisegStatusTone.neutral),
                    ],
                  ),
                ),
                RisegColumn<DocumentoPorEmitirData>(
                  label: l10n.agendaColumnaCliente,
                  cellBuilder: (d) => Text(_clienteNombre(d.clienteId)),
                ),
                RisegColumn<DocumentoPorEmitirData>(
                  label: l10n.agendaColumnaPeriodo,
                  width: 190,
                  cellBuilder: (d) =>
                      Text('${_formatoFecha.format(d.periodoInicio)} - ${_formatoFecha.format(d.periodoFin)}'),
                ),
                RisegColumn<DocumentoPorEmitirData>(
                  label: l10n.agendaColumnaFechaEmision,
                  width: 150,
                  cellBuilder: (d) => Row(
                    children: [
                      // `Flexible` + elipsis — "Sin fecha calculable" (el
                      // texto de respaldo cuando la vigencia no tiene
                      // regla de Emisión, ej. Toluca 32/Tikal) es más
                      // largo que cualquier fecha real y desbordaba la
                      // columna fija de 150px (bug real encontrado).
                      Flexible(
                        child: Text(
                          d.fechaEmisionProgramada == null
                              ? l10n.agendaFechaSinCalcular
                              : _formatoFecha.format(d.fechaEmisionProgramada!),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (documentoPorEmitirRequiereAccion(d, hoy)) ...[
                        const SizedBox(width: AppSpacing.xxs),
                        Tooltip(
                          message: l10n.agendaEtiquetaAtrasado,
                          child: const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
                        ),
                      ],
                    ],
                  ),
                ),
                RisegColumn<DocumentoPorEmitirData>(
                  label: l10n.agendaColumnaImporte,
                  width: 130,
                  alignment: TextAlign.right,
                  cellBuilder: (d) => Text(formatoCentavosAgenda(d.importeFinalEsperado)),
                ),
                RisegColumn<DocumentoPorEmitirData>(
                  label: l10n.agendaColumnaEstatus,
                  width: 140,
                  cellBuilder: (d) => RisegStatusBadge(
                    label: _estatusLabel(l10n, d.estatus),
                    tone: _estatusTono(d.estatus),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _tituloMesCapitalizado(DateTime mes) {
    final texto = _formatoMes.format(mes);
    return texto[0].toUpperCase() + texto.substring(1);
  }
}
