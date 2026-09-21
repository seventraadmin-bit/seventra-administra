import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart' show deudaRepositoryProvider, egresoRepositoryProvider;
import 'package:riseg_one/features/finanzas/presentation/cuentas_financieras/cuentas_financieras_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/deudas_credito/deudas_credito_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formaPagoLabel;
import 'package:riseg_one/features/finanzas/presentation/planeacion/planeacion_financiera_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_controller.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/egresos_controller.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart'
    show attachmentRepositoryProvider, attachmentStorageProvider;
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

import '../../inventario/presentation/articulos/articulos_controller.dart';
import '../../inventario/presentation/articulos/articulos_list_screen.dart' show formatoCosto;
import '../compras_providers.dart';
import '../data/tables/compra_partida_table.dart' show DestinoCompraPartida;
import '../domain/usecases/cancelar_compra_usecase.dart' show MotivoCancelacionCompra, MotivoCancelacionCompraLabel;
import 'compras_controller.dart';
import 'compras_list_screen.dart' show compraEstatusLabel, compraEstatusTono;
import 'widgets/cancelar_compra_dialog.dart';
import 'widgets/eliminar_cadena_prueba_compra_dialog.dart';
import 'widgets/eliminar_compra_fisicamente_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Etiqueta a mostrar para el motivo de cancelación — resuelve el
/// código estructurado (Etapa 15) a su etiqueta traducida; para
/// Compras canceladas antes de ese cambio, cae de vuelta a
/// `motivoCancelacion` (legacy, ver el doc comment de esa columna en
/// `compra_table.dart`).
String _motivoCancelacionLabel(CompraData compra) {
  final codigo = compra.motivoCancelacionCodigo;
  if (codigo != null) {
    final motivo = MotivoCancelacionCompra.values.where((m) => m.name == codigo).firstOrNull;
    if (motivo != null) return motivo.etiqueta;
    return codigo;
  }
  return compra.motivoCancelacion ?? '—';
}

/// Expediente de una Compra (Etapa 10, pasada UX/UI Etapa 19) — una
/// sola pantalla desplazable con secciones, sin pestañas internas
/// (mismo criterio que `LineaTelefonicaExpedienteScreen`).
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
  Map<String, ArticuloData> _articulosPorId = const {};
  Map<String, ArticuloUnidadData> _unidadesPorId = const {};
  Set<String> _unidadesTelefono = const {};
  EgresoData? _egreso;
  DeudaData? _tarjeta;
  AttachmentData? _comprobante;
  bool _cargando = true;
  bool _bloqueadaEliminacionNormal = false;

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
    final articulosPorId = {for (final a in articulos) a.id: a};

    final comprobantes = await ref.read(attachmentRepositoryProvider).listarActivosPorCompra(widget.compraId);

    // El Egreso es el mismo generado en la transacción de `crear()`
    // (Compra.egresoId → Egreso.id, FK única) — nunca un segundo
    // registro ni un cálculo aparte.
    final egreso = compra?.egresoId == null ? null : await ref.read(egresoRepositoryProvider).obtenerPorId(compra!.egresoId!);

    // Etapa 19B — la tarjeta que financió esta Compra (`egresoId` y
    // `deudaId` son mutuamente excluyentes, ver el doc comment de
    // `Compra`).
    final tarjeta = compra?.deudaId == null ? null : await ref.read(deudaRepositoryProvider).obtenerPorId(compra!.deudaId!);

    // Solo relevante para el Usuario Maestro — determina si se ofrece
    // "Eliminar cadena de prueba" como alternativa (Etapa 15): esa
    // acción NUNCA se muestra si la eliminación física normal todavía
    // es posible (ver el doc comment de `mostrarDialogoEliminarCadenaPruebaCompra`).
    final esMaestro = ref.read(sesionControllerProvider)?.esMaestro ?? false;
    final bloqueadaNormal = esMaestro
        ? (await ref.read(compraRepositoryProvider).obtenerResumenEliminacionFisica(widget.compraId)).bloqueado
        : false;

    // Unidades generadas por partidas serializadas — para mostrar
    // "SMARTPHONE / UNI-000001 · Serie ..." con enlace directo a su
    // expediente. Etapa 19: bulk (2 consultas totales, nunca una por
    // movimiento) — antes era `obtenerUnidadPorId`/`obtenerTelefono`
    // dentro de un loop, un N+1 real acotado al número de movimientos
    // de esta Compra.
    final inventarioRepo = ref.read(inventarioRepositoryProvider);
    final unidadIdsNecesarias = movimientos.map((m) => m.unidadId).whereType<String>().toSet();
    final unidadesPorId = <String, ArticuloUnidadData>{};
    if (unidadIdsNecesarias.isNotEmpty) {
      for (final u in await inventarioRepo.listarTodasUnidades()) {
        if (unidadIdsNecesarias.contains(u.id)) unidadesPorId[u.id] = u;
      }
    }
    final unidadesTelefono = unidadIdsNecesarias.isEmpty
        ? <String>{}
        : (await inventarioRepo.listarUnidadesTelefono()).map((u) => u.id).where(unidadIdsNecesarias.contains).toSet();

    if (!mounted) return;
    setState(() {
      _compra = compra;
      _partidas = partidas;
      _movimientos = movimientos;
      _articulosPorId = articulosPorId;
      _unidadesPorId = unidadesPorId;
      _unidadesTelefono = unidadesTelefono;
      _egreso = egreso;
      _tarjeta = tarjeta;
      _comprobante = comprobantes.firstOrNull;
      _bloqueadaEliminacionNormal = bloqueadaNormal;
      _cargando = false;
    });
  }

  ArticuloData? _articuloDe(CompraPartidaData p) => p.articuloId == null ? null : _articulosPorId[p.articuloId];

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
    // todos los providers afectados: Compras, Egresos por su Egreso
    // propio, Inventario por las entradas que revierte, y (auditoría
    // integral 19A-19D) Deudas/Resumen/Planeación/Cuentas financieras,
    // ya que `CompraRepositoryImpl.eliminarFisicamente` revierte un
    // cargo a tarjeta o borra el Egreso ligado en la misma transacción.
    ref.invalidate(comprasControllerProvider);
    ref.invalidate(egresosControllerProvider);
    ref.invalidate(articulosControllerProvider);
    ref.invalidate(dashboardControllerProvider);
    ref.invalidate(deudasCreditoControllerProvider);
    ref.invalidate(resumenFinancieroControllerProvider);
    ref.invalidate(planeacionFinancieraControllerProvider);
    ref.invalidate(cuentasFinancierasControllerProvider);
    if (mounted) context.pop();
  }

  Future<void> _eliminarCadenaPrueba() async {
    final eliminada = await mostrarDialogoEliminarCadenaPruebaCompra(context, ref, widget.compraId);
    if (!eliminada) return;
    ref.invalidate(comprasControllerProvider);
    ref.invalidate(egresosControllerProvider);
    ref.invalidate(articulosControllerProvider);
    ref.invalidate(dashboardControllerProvider);
    ref.invalidate(deudasCreditoControllerProvider);
    ref.invalidate(resumenFinancieroControllerProvider);
    ref.invalidate(planeacionFinancieraControllerProvider);
    ref.invalidate(cuentasFinancierasControllerProvider);
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
    final articulosRenglones = _partidas.where((p) => p.destino == DestinoCompraPartida.inventario.name).length;
    final unidadesCompradas = _partidas
        .where((p) => p.destino == DestinoCompraPartida.inventario.name)
        .fold<int>(0, (s, p) => s + p.cantidad);
    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;
    final unidadesIncorporadas = _movimientos
        .where((m) => m.tipoMovimiento == 'entrada')
        .fold<int>(0, (s, m) => s + m.cantidad);

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
                Text(compra.folioCompra, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  (compra.proveedor ?? '').trim().isEmpty
                      ? _formatoFecha.format(compra.fecha)
                      : '${compra.proveedor} · ${_formatoFecha.format(compra.fecha)}',
                  style: AppTypography.body.copyWith(color: colors.textMuted),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    RisegStatusBadge(label: compraEstatusLabel(l10n, compra.estatus), tone: compraEstatusTono(compra.estatus)),
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
                    // Etapa 19: Eliminar físicamente / Eliminar cadena de
                    // prueba (extraordinarias, Maestro-only) se
                    // consolidan en un solo menú ⋯ — antes eran hasta 2
                    // botones rojos permanentes junto a Corregir/Cancelar.
                    if (esMaestro)
                      RisegActionsMenu(
                        menuKey: const Key('compra_expediente_menu_acciones'),
                        tooltip: l10n.compraExpedienteMenuAcciones,
                        actions: [
                          RisegMenuAction(
                            key: const Key('compra_expediente_boton_eliminar_fisicamente'),
                            label: l10n.eliminacionFisicaAccionMenu,
                            icon: Icons.delete_forever_outlined,
                            destructive: true,
                            onTap: _eliminarFisicamente,
                          ),
                          // Alternativa (Etapa 15) — solo ofrecida cuando
                          // la eliminación física normal ya está
                          // bloqueada por historia posterior (ver
                          // `_bloqueadaEliminacionNormal`, calculado en
                          // `_cargar`).
                          if (_bloqueadaEliminacionNormal)
                            RisegMenuAction(
                              key: const Key('compra_expediente_boton_eliminar_cadena_prueba'),
                              label: l10n.compraCadenaPruebaBoton,
                              icon: Icons.delete_forever_outlined,
                              destructive: true,
                              onTap: _eliminarCadenaPrueba,
                            ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                // Resumen — únicamente información real: Total,
                // Artículos/renglones y Unidades derivados de las
                // propias partidas, Forma de pago tal cual se capturó.
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    SizedBox(
                      width: 170,
                      child: RisegStatCard(dense: true, label: l10n.compraExpedienteResumenTotal, value: formatoCosto(total)),
                    ),
                    SizedBox(
                      width: 170,
                      child: RisegStatCard(
                        dense: true,
                        label: l10n.compraExpedienteResumenArticulos,
                        value: '$articulosRenglones',
                      ),
                    ),
                    SizedBox(
                      width: 170,
                      child: RisegStatCard(dense: true, label: l10n.compraExpedienteResumenUnidades, value: '$unidadesCompradas'),
                    ),
                    SizedBox(
                      width: 170,
                      child: RisegStatCard(
                        dense: true,
                        label: l10n.compraExpedienteResumenFormaPago,
                        value: formaPagoLabel(l10n, compra.formaPago),
                      ),
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
                      if (_tarjeta != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 180,
                                child: Text(l10n.compraFinanciamientoEtiqueta, style: AppTypography.label.copyWith(color: context.colors.textMuted)),
                              ),
                              Expanded(
                                child: InkWell(
                                  onTap: () => context.push('/finanzas/deudas-y-credito/${_tarjeta!.id}'),
                                  child: Text(
                                    l10n.compraFinanciamientoValor(_tarjeta!.nombre, _tarjeta!.tarjetaUltimosDigitos ?? '----'),
                                    style: AppTypography.body.copyWith(color: context.colors.accent, decoration: TextDecoration.underline),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (esCancelada) ...[
                        _campo(l10n.compraCancelarCampoMotivo, _motivoCancelacionLabel(compra)),
                        if (compra.motivoCancelacionDetalle != null)
                          _campo(l10n.compraCancelarCampoDetalle, compra.motivoCancelacionDetalle!),
                        if (compra.motivoCancelacionObservaciones != null)
                          _campo(l10n.compraCancelarCampoObservaciones, compra.motivoCancelacionObservaciones!),
                      ],
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
                        onRowTap: (p) {
                          final articulo = _articuloDe(p);
                          if (articulo != null) context.push('/inventario/articulos/${articulo.id}');
                        },
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
                          // Etapa 19: identidad Nombre+Folio (mismo
                          // criterio que Inventario/Nómina) cuando hay un
                          // Artículo real; texto plano para renglones de
                          // Gasto directo (sin Artículo, no hay nada que
                          // fusionar).
                          RisegColumn<CompraPartidaData>(
                            label: l10n.compraPartidaColumnaArticulo,
                            cellBuilder: (p) {
                              final articulo = _articuloDe(p);
                              if (articulo == null) return Text(p.concepto ?? '—');
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(articulo.nombre, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
                                  const SizedBox(height: 2),
                                  Text(articulo.folio, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                                ],
                              );
                            },
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
                      Text(l10n.compraIntegracionesSeccionInventario, style: AppTypography.label),
                      const SizedBox(height: AppSpacing.xs),
                      if (_movimientos.isEmpty)
                        Text(l10n.compraIntegracionesEntradasVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else ...[
                        if (!esCancelada && unidadesIncorporadas > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                            child: Text(
                              l10n.compraIntegracionesEntradasResumen(unidadesIncorporadas),
                              style: AppTypography.body.copyWith(color: colors.textMuted),
                            ),
                          ),
                        for (final m in _movimientos)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _articulosPorId[m.articuloId]?.nombre ?? m.articuloId,
                                        style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
                                      ),
                                      Text(
                                        m.unidadId == null
                                            ? '${_signoMovimiento(m.tipoMovimiento)}${m.cantidad} · ${m.costoUnitario == null ? '—' : formatoCosto(m.costoUnitario!)}'
                                            : '${_unidadesPorId[m.unidadId]?.codigo ?? m.unidadId} · Serie ${_unidadesPorId[m.unidadId]?.numeroSerie ?? '—'} '
                                                '(${_signoMovimiento(m.tipoMovimiento)}1)',
                                        style: AppTypography.caption.copyWith(color: colors.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                if (m.unidadId != null)
                                  RisegButton(
                                    label: l10n.compraIntegracionesVerUnidad,
                                    variant: RisegButtonVariant.ghost,
                                    size: RisegButtonSize.compact,
                                    onPressed: () => context.push(
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
                                    onPressed: () => context.push('/inventario/articulos/${m.articuloId}'),
                                  ),
                              ],
                            ),
                          ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      Text(l10n.compraIntegracionesSeccionFinanzas, style: AppTypography.label),
                      const SizedBox(height: AppSpacing.xs),
                      if (_egreso == null)
                        Text(l10n.compraIntegracionesEgresoVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(l10n.compraIntegracionesEgresoRegistrado, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
                                  Text(
                                    '${_egreso!.folioEgreso} · ${formatoCosto(_egreso!.monto)}',
                                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                                  ),
                                ],
                              ),
                            ),
                            // Finanzas no tiene todavía un expediente de
                            // Egreso navegable (el detalle vive solo en
                            // un diálogo dentro de la lista) — este
                            // botón lleva al módulo, nunca a un enlace
                            // roto con un id que no tiene ruta propia.
                            RisegButton(
                              label: l10n.compraIntegracionesVerEgreso,
                              variant: RisegButtonVariant.ghost,
                              size: RisegButtonSize.compact,
                              onPressed: () => context.push('/finanzas'),
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
