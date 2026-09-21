import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/complemento_pago_table.dart';

import '../../../organizacion/organizacion_providers.dart';
import '../pagos/pagos_list_screen.dart' show formatoCentavosPago;
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/tokens/app_color_scheme.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_complementos_pendientes_usecase.dart';

import 'complementos_controller.dart';
import 'complementos_state.dart';
import 'widgets/complemento_detalle_dialog.dart';
import 'package:riseg_one/features/finanzas/domain/contraparte_cobro.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

String complementoEstatusLabel(AppLocalizations l10n, String valor) {
  return switch (EstatusComplementoPago.values.byName(valor)) {
    EstatusComplementoPago.registrado => l10n.complementoPagoEstatusRegistrado,
    EstatusComplementoPago.cancelado => l10n.complementoPagoEstatusCancelado,
  };
}

RisegStatusTone complementoEstatusTono(String valor) {
  return switch (EstatusComplementoPago.values.byName(valor)) {
    EstatusComplementoPago.registrado => RisegStatusTone.success,
    EstatusComplementoPago.cancelado => RisegStatusTone.neutral,
  };
}

/// UUID abreviado (Etapa 17) — primeros 8 y últimos 4 caracteres; el
/// valor completo sigue disponible vía `Tooltip`/detalle, nunca se
/// pierde, solo deja de dominar visualmente la tabla.
String _uuidAbreviado(String uuid) {
  if (uuid.length <= 14) return uuid;
  return '${uuid.substring(0, 8)}…${uuid.substring(uuid.length - 4)}';
}

/// Listado de Complementos de pago (Etapa 4J.3) — filtros por Cliente/
/// estatus. Sin acción de creación aquí: se registra desde el detalle
/// del Pago que liquida (mismo criterio que Cuentas por cobrar/Pagos).
class ComplementosListScreen extends ConsumerStatefulWidget {
  const ComplementosListScreen({super.key});

  @override
  ConsumerState<ComplementosListScreen> createState() => _ComplementosListScreenState();
}

class _ComplementosListScreenState extends ConsumerState<ComplementosListScreen> {
  List<ClienteData> _clientes = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final clientes = await ref.read(clienteRepositoryProvider).listarActivos();
      if (mounted) setState(() => _clientes = clientes);
    });
  }

  Future<void> _mostrarDetalle(ComplementoPagoData complemento) async {
    await showDialog<void>(context: context, builder: (_) => ComplementoDetalleDialog(complementoPagoId: complemento.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(complementosControllerProvider);
    final notifier = ref.read(complementosControllerProvider.notifier);

    if (state.errorCarga != null && state.complementos.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.complementosListadoCargaErrorTitulo,
        message: l10n.complementosListadoCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('complementos_boton_reintentar'),
          label: l10n.complementosListadoBotonReintentar,
          onPressed: notifier.reintentarCarga,
        ),
      );
    }

    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(title: l10n.complementosListadoTitulo, description: l10n.complementosListadoSubtitulo),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: RisegSelect<String?>(
                  label: l10n.complementosFiltroCliente,
                  value: state.clienteId,
                  items: [
                    RisegSelectItem(value: null, label: l10n.complementosFiltroClienteTodos),
                    for (final c in _clientes) RisegSelectItem(value: c.id, label: c.nombreComercial),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(clienteId: valor, limpiarClienteId: valor == null),
                ),
              ),
              // "Pendientes" NO es un estatus del repositorio: no existe
              // ninguna fila `ComplementoPago` pendiente. Es una vista
              // sobre una proyección derivada de Pagos reales, y por eso
              // sustituye al viejo filtro de estatus en vez de sumarse a
              // él (dos controles que se contradicen serían peor).
              SizedBox(
                width: 220,
                child: RisegSelect<VistaComplementos>(
                  key: const Key('complementos_selector_vista'),
                  label: l10n.complementosFiltroEstatus,
                  value: state.vista,
                  items: [
                    RisegSelectItem(
                      value: VistaComplementos.pendientes,
                      label: '${l10n.complementosFiltroVistaPendientes} (${state.totalPendientes})',
                    ),
                    RisegSelectItem(value: VistaComplementos.registrados, label: l10n.complementosFiltroVistaRegistrados),
                    RisegSelectItem(value: VistaComplementos.cancelados, label: l10n.complementosFiltroVistaCancelados),
                    RisegSelectItem(value: VistaComplementos.todos, label: l10n.complementosFiltroVistaTodos),
                  ],
                  onChanged: (valor) => valor == null ? null : notifier.cambiarVista(valor),
                ),
              ),
              // Contador SIEMPRE visible, no sólo al desplegar el
              // selector: "¿qué complementos me faltan?" es la pregunta
              // que la pantalla debe responder de un vistazo, se esté
              // mirando la vista que se esté mirando.
              RisegStatusBadge(
                key: const Key('complementos_contador_pendientes'),
                label: l10n.complementosPendientesConteo(state.totalPendientes),
                tone: state.totalPendientes == 0 ? RisegStatusTone.success : RisegStatusTone.warning,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: state.vista == VistaComplementos.pendientes
                ? _tablaPendientes(context, state, l10n, colors)
                : _tablaRegistrados(context, state, l10n, colors),
          ),
        ],
      ),
    );
  }

  /// Proyección: cada fila es un **Pago real** que exige Complemento y
  /// no lo tiene. Nunca una fila persistida.
  Widget _tablaPendientes(BuildContext context, ComplementosState state, AppLocalizations l10n, AppColorScheme colors) {
    return RisegTableBase<ComplementoPendiente>(
      key: const Key('complementos_tabla_pendientes'),
      loading: state.cargando,
      rows: state.pendientes,
      onRowTap: (p) => _abrirPago(p.pago.id),
      emptyState: RisegEmptyState(
        title: l10n.complementosPendientesVacio,
        message: l10n.complementosPendientesAyuda,
      ),
      hoverColor: colors.accentSoftBg,
      rowVerticalPadding: AppSpacing.sm + AppSpacing.xxs,
      rowActionsBuilder: (_) => Icon(Icons.chevron_right, size: AppSizes.iconMd, color: colors.textMuted),
      actionsWidth: 40,
      columns: [
        RisegColumn<ComplementoPendiente>(
          label: l10n.complementosColumnaCliente,
          cellBuilder: (p) => Text(
            state.nombres.de(contraparteDePago(p.pago)),
            style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        RisegColumn<ComplementoPendiente>(
          label: l10n.complementosColumnaFolioPago,
          width: 120,
          cellBuilder: (p) => Text(p.pago.folioPago),
        ),
        RisegColumn<ComplementoPendiente>(
          label: l10n.complementosColumnaFechaPago,
          width: 130,
          cellBuilder: (p) => Text(_formatoFecha.format(p.pago.fechaPago)),
        ),
        RisegColumn<ComplementoPendiente>(
          label: l10n.complementosColumnaMontoPago,
          width: 130,
          alignment: TextAlign.right,
          cellBuilder: (p) => Text(
            formatoCentavosPago(p.pago.montoTotal),
            style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
          ),
        ),
        RisegColumn<ComplementoPendiente>(
          label: l10n.complementosColumnaCuentas,
          cellBuilder: (p) => Text(_cuentasResumen(p.cuentas), overflow: TextOverflow.ellipsis),
        ),
        RisegColumn<ComplementoPendiente>(
          label: l10n.complementosColumnaEstatus,
          width: 130,
          // Sin noción de "vencido": el sistema no tiene regla de plazo
          // fiscal, así que sólo se afirma lo que es cierto.
          cellBuilder: (_) => RisegStatusBadge(
            label: l10n.complementosEstadoPendiente,
            tone: RisegStatusTone.warning,
          ),
        ),
      ],
    );
  }

  Widget _tablaRegistrados(BuildContext context, ComplementosState state, AppLocalizations l10n, AppColorScheme colors) {
    return RisegTableBase<ComplementoConContexto>(
      key: const Key('complementos_tabla_registrados'),
      loading: state.cargando,
      rows: state.complementos,
      onRowTap: (c) => _mostrarDetalle(c.complemento),
      emptyState: RisegEmptyState(
        title: l10n.complementosListadoVacioTitulo,
        message: l10n.complementosListadoVacioMensaje,
      ),
      hoverColor: colors.accentSoftBg,
      rowVerticalPadding: AppSpacing.sm + AppSpacing.xxs,
      rowActionsBuilder: (_) => Icon(Icons.chevron_right, size: AppSizes.iconMd, color: colors.textMuted),
      actionsWidth: 40,
      columns: [
        RisegColumn<ComplementoConContexto>(
          label: l10n.complementosColumnaUuid,
          width: 150,
          cellBuilder: (c) => Tooltip(
            message: c.complemento.uuid,
            child: Text(
              _uuidAbreviado(c.complemento.uuid),
              style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
            ),
          ),
        ),
        RisegColumn<ComplementoConContexto>(
          label: l10n.complementosColumnaCliente,
          cellBuilder: (c) => Text(
            c.pago == null ? '—' : state.nombres.de(contraparteDePago(c.pago!)),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        RisegColumn<ComplementoConContexto>(
          label: l10n.complementosColumnaFolioPago,
          width: 110,
          cellBuilder: (c) => Text(c.pago?.folioPago ?? c.complemento.pagoId),
        ),
        // Fecha REAL del Pago junto a la de timbrado: son dos hechos
        // distintos y la pantalla debe poder distinguirlos.
        RisegColumn<ComplementoConContexto>(
          label: l10n.complementosColumnaFechaPago,
          width: 120,
          cellBuilder: (c) => Text(c.pago == null ? '' : _formatoFecha.format(c.pago!.fechaPago)),
        ),
        RisegColumn<ComplementoConContexto>(
          label: l10n.complementosColumnaFechaTimbrado,
          width: 120,
          cellBuilder: (c) => Text(_formatoFecha.format(c.complemento.fechaTimbrado)),
        ),
        RisegColumn<ComplementoConContexto>(
          label: l10n.complementosColumnaMontoTotal,
          width: 120,
          alignment: TextAlign.right,
          cellBuilder: (c) => Text(
            formatoCentavosPago(c.complemento.montoTotal),
            style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
          ),
        ),
        RisegColumn<ComplementoConContexto>(
          label: l10n.complementosColumnaCuentas,
          cellBuilder: (c) => Text(_cuentasResumen(c.cuentas), overflow: TextOverflow.ellipsis),
        ),
        RisegColumn<ComplementoConContexto>(
          label: l10n.complementosColumnaEstatus,
          width: 120,
          cellBuilder: (c) => RisegStatusBadge(
            label: complementoEstatusLabel(l10n, c.complemento.estatus),
            tone: complementoEstatusTono(c.complemento.estatus),
          ),
        ),
      ],
    );
  }

  /// Las facturas/CxC cubiertas — derivadas de las aplicaciones activas
  /// del Pago, nunca copiadas dentro de `ComplementoPago`. Un Pago
  /// aplicado a varias Cuentas las muestra todas, sin duplicar el Pago
  /// ni crear dos obligaciones.
  String _cuentasResumen(List<CuentaPorCobrarData> cuentas) {
    if (cuentas.isEmpty) return '—';
    return [for (final c in cuentas) c.folioDocumento ?? c.uuid ?? c.id.substring(0, 8)].join(', ');
  }

  void _abrirPago(String pagoId) => context.go('/finanzas/pagos');
}
