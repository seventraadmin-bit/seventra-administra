import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formaPagoLabel;
import 'package:riseg_one/features/inventario/inventario_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/egresos_controller.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart'
    show attachmentRepositoryProvider, attachmentStorageProvider;
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

import '../../inventario/presentation/articulos/articulos_controller.dart';
import '../../inventario/presentation/articulos/articulos_list_screen.dart' show formatoCosto;
import '../data/tables/compra_partida_table.dart' show DestinoCompraPartida;
import 'compras_controller.dart';
import 'compras_list_screen.dart' show compraEstatusLabel, compraEstatusTono;
import 'widgets/cancelar_compra_dialog.dart';
import 'widgets/eliminar_compra_fisicamente_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Expediente de una Compra (Etapa 10) — una sola pantalla desplazable
/// con secciones, sin pestañas internas (mismo criterio que
/// `LineaTelefonicaExpedienteScreen`).
class CompraExpedienteScreen extends ConsumerStatefulWidget {
  const CompraExpedienteScreen({required this.compraId, super.key});

  final String compraId;

  @override
  ConsumerState<CompraExpedienteScreen> createState() => _CompraExpedienteScreenState();
}

class _CompraExpedienteScreenState extends ConsumerState<CompraExpedienteScreen> {
  CompraData? _compra;
  List<CompraPartidaData> _partidas = const [];
  List<MovimientoInventarioData> _movimientos = const [];
  Map<String, String> _articulosPorId = const {};
  Map<String, ArticuloUnidadData> _unidadesPorId = const {};
  Set<String> _unidadesTelefono = const {};
  AttachmentData? _comprobante;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final notifier = ref.read(comprasControllerProvider.notifier);
    final compra = await notifier.obtenerCompra(widget.compraId);
    final partidas = await notifier.obtenerPartidas(widget.compraId);
    final movimientos = await notifier.obtenerMovimientosGenerados(widget.compraId);

    final articulos = await ref.read(articuloRepositoryProvider).listar();
    final articulosPorId = {for (final a in articulos) a.id: a.nombre};

    final comprobantes = await ref.read(attachmentRepositoryProvider).listarActivosPorCompra(widget.compraId);

    // Unidades generadas por partidas serializadas — para mostrar
    // "SMARTPHONE / UNI-000001 · Serie ..." con enlace directo a su
    // expediente, en vez de solo "Ver artículo" (que llevaba al
    // Artículo completo, sin distinguir la unidad exacta que generó
    // esta Compra).
    final inventarioRepo = ref.read(inventarioRepositoryProvider);
    final unidadesPorId = <String, ArticuloUnidadData>{};
    final unidadesTelefono = <String>{};
    for (final m in movimientos) {
      final unidadId = m.unidadId;
      if (unidadId == null) continue;
      final unidad = await inventarioRepo.obtenerUnidadPorId(unidadId);
      if (unidad != null) unidadesPorId[unidadId] = unidad;
      if (await inventarioRepo.obtenerTelefono(unidadId) != null) unidadesTelefono.add(unidadId);
    }

    if (!mounted) return;
    setState(() {
      _compra = compra;
      _partidas = partidas;
      _movimientos = movimientos;
      _articulosPorId = articulosPorId;
      _unidadesPorId = unidadesPorId;
      _unidadesTelefono = unidadesTelefono;
      _comprobante = comprobantes.firstOrNull;
      _cargando = false;
    });
  }

  String _partidaDescripcion(CompraPartidaData p) {
    if (p.destino == DestinoCompraPartida.gastoDirecto.name) return p.concepto ?? '—';
    return _articulosPorId[p.articuloId] ?? p.articuloId ?? '—';
  }

  // Una Compra cancelada trae, además de su entrada original, la baja
  // de reversa vinculada a la misma partida (Etapa 15) — sin el signo
  // correcto, esa fila se leía como una segunda entrada.
  String _signoMovimiento(String tipoMovimiento) => tipoMovimiento == 'baja' ? '-' : '+';

  Future<void> _corregir() async {
    final corregida = await context.push<bool>('/compras/${widget.compraId}/corregir');
    if (corregida ?? false) await _cargar();
  }

  Future<void> _cancelar() async {
    final cancelada = await mostrarDialogoCancelarCompra(context, ref, widget.compraId);
    if (cancelada) await _cargar();
  }

  Future<void> _eliminarFisicamente() async {
    final eliminada = await mostrarDialogoEliminarCompraFisicamente(context, ref, widget.compraId);
    if (!eliminada) return;
    // La eliminación pasa por `eliminarCompraFisicamenteAutorizadoProvider`
    // directo, nunca por `ComprasController` — a diferencia de
    // registrar/cancelar, esta pantalla es responsable de invalidar
    // los tres providers afectados (Compras, Egresos por su Egreso
    // propio, Inventario por las entradas que revierte).
    ref.invalidate(comprasControllerProvider);
    ref.invalidate(egresosControllerProvider);
    ref.invalidate(articulosControllerProvider);
    ref.invalidate(dashboardControllerProvider);
    if (mounted) context.pop();
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final compra = _compra;
    if (compra == null) {
      return Scaffold(appBar: AppBar(), body: RisegEmptyState(title: l10n.compraExpedienteCargaErrorTitulo, message: ''));
    }

    final esCancelada = compra.estatus == 'cancelada';
    final total = _partidas.fold<int>(0, (s, p) => s + p.cantidad * p.costoUnitario);
    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(compra.folioCompra)),
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
                          Text(compra.folioCompra, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
                          Text(formatoCosto(total), style: AppTypography.body.copyWith(color: colors.textMuted)),
                        ],
                      ),
                    ),
                    RisegStatusBadge(label: compraEstatusLabel(l10n, compra.estatus), tone: compraEstatusTono(compra.estatus)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    RisegButton(
                      label: l10n.compraExpedienteBotonCorregir,
                      variant: RisegButtonVariant.secondary,
                      onPressed: esCancelada ? null : _corregir,
                    ),
                    RisegButton(
                      label: l10n.compraExpedienteBotonCancelar,
                      variant: RisegButtonVariant.danger,
                      onPressed: esCancelada ? null : _cancelar,
                    ),
                    // Extraordinaria (Maestro) — nunca depende del
                    // estatus: una Compra ya cancelada (captura de
                    // prueba) sigue siendo elegible para limpiar por
                    // completo (Etapa 15).
                    if (esMaestro)
                      RisegButton(
                        key: const Key('compra_expediente_boton_eliminar_fisicamente'),
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
                      Text(l10n.compraExpedienteSeccionDatos, style: AppTypography.heading3),
                      const SizedBox(height: AppSpacing.sm),
                      _campo(l10n.compraCampoFecha, _formatoFecha.format(compra.fecha)),
                      _campo(l10n.compraCampoProveedor, compra.proveedor ?? '—'),
                      _campo(
                        l10n.compraCampoFormaPago,
                        compra.formaPago == 'otro' && compra.formaPagoOtroDescripcion != null
                            ? '${formaPagoLabel(l10n, compra.formaPago)} · ${compra.formaPagoOtroDescripcion}'
                            : formaPagoLabel(l10n, compra.formaPago),
                      ),
                      if (esCancelada) _campo(l10n.compraCancelarCampoMotivo, compra.motivoCancelacion ?? '—'),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.compraExpedienteSeccionPartidas, style: AppTypography.heading3),
                      const SizedBox(height: AppSpacing.sm),
                      RisegTableBase<CompraPartidaData>(
                        rows: _partidas,
                        emptyState: const RisegEmptyState(title: '', message: ''),
                        columns: [
                          RisegColumn<CompraPartidaData>(
                            label: l10n.compraPartidaColumnaDestino,
                            width: 120,
                            cellBuilder: (p) => Text(
                              p.destino == DestinoCompraPartida.inventario.name
                                  ? l10n.compraPartidaOpcionInventario
                                  : l10n.compraPartidaOpcionGastoDirecto,
                            ),
                          ),
                          RisegColumn<CompraPartidaData>(
                            label: l10n.compraPartidaColumnaArticulo,
                            cellBuilder: (p) => Text(_partidaDescripcion(p)),
                          ),
                          RisegColumn<CompraPartidaData>(
                            label: l10n.compraPartidaColumnaCantidad,
                            width: 90,
                            alignment: TextAlign.right,
                            cellBuilder: (p) => Text('${p.cantidad}'),
                          ),
                          RisegColumn<CompraPartidaData>(
                            label: l10n.compraPartidaColumnaCostoUnitario,
                            width: 110,
                            alignment: TextAlign.right,
                            cellBuilder: (p) => Text(formatoCosto(p.costoUnitario)),
                          ),
                          RisegColumn<CompraPartidaData>(
                            label: l10n.compraPartidaColumnaSubtotal,
                            width: 110,
                            alignment: TextAlign.right,
                            cellBuilder: (p) => Text(formatoCosto(p.cantidad * p.costoUnitario)),
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
                      Text(l10n.compraExpedienteSeccionIntegraciones, style: AppTypography.heading3),
                      const SizedBox(height: AppSpacing.sm),
                      Text(l10n.compraIntegracionesEntradasTitulo, style: AppTypography.label),
                      const SizedBox(height: AppSpacing.xs),
                      if (_movimientos.isEmpty)
                        Text(l10n.compraIntegracionesEntradasVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else
                        for (final m in _movimientos)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    m.unidadId == null
                                        ? '${_articulosPorId[m.articuloId] ?? m.articuloId} · ${_signoMovimiento(m.tipoMovimiento)}${m.cantidad} · ${m.costoUnitario == null ? '—' : formatoCosto(m.costoUnitario!)}'
                                        : '${_articulosPorId[m.articuloId] ?? m.articuloId}\n'
                                            '${_unidadesPorId[m.unidadId]?.codigo ?? m.unidadId} · Serie ${_unidadesPorId[m.unidadId]?.numeroSerie ?? '—'} '
                                            '(${_signoMovimiento(m.tipoMovimiento)}1)',
                                  ),
                                ),
                                if (m.unidadId != null)
                                  RisegButton(
                                    label: l10n.compraIntegracionesVerUnidad,
                                    variant: RisegButtonVariant.ghost,
                                    size: RisegButtonSize.compact,
                                    onPressed: () => context.go(
                                      _unidadesTelefono.contains(m.unidadId)
                                          ? '/telefonia/equipos/${m.unidadId}'
                                          : '/inventario/articulos/${m.articuloId}',
                                    ),
                                  )
                                else
                                  RisegButton(
                                    label: l10n.compraIntegracionesVerArticulo,
                                    variant: RisegButtonVariant.ghost,
                                    size: RisegButtonSize.compact,
                                    onPressed: () => context.go('/inventario/articulos/${m.articuloId}'),
                                  ),
                              ],
                            ),
                          ),
                      const SizedBox(height: AppSpacing.md),
                      Text(l10n.compraIntegracionesEgresoTitulo, style: AppTypography.label),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          Expanded(child: Text(formatoCosto(total))),
                          RisegButton(
                            label: l10n.compraIntegracionesVerEgreso,
                            variant: RisegButtonVariant.ghost,
                            size: RisegButtonSize.compact,
                            onPressed: () => context.go('/finanzas'),
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
                      Text(l10n.compraExpedienteSeccionDocumento, style: AppTypography.heading3),
                      const SizedBox(height: AppSpacing.sm),
                      if (_comprobante == null)
                        Text(l10n.compraDocumentoSinComprobante, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else
                        RisegButton(
                          label: l10n.compraDocumentoBotonAbrir,
                          variant: RisegButtonVariant.secondary,
                          onPressed: () => ref.read(attachmentStorageProvider).abrir(_comprobante!.path),
                        ),
                    ],
                  ),
                ),
                if ((compra.observaciones ?? '').isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  RisegCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.compraExpedienteSeccionObservaciones, style: AppTypography.heading3),
                        const SizedBox(height: AppSpacing.sm),
                        Text(compra.observaciones!, style: AppTypography.body),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
