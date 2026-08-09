import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_aplicacion_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/complemento_pago_derivado.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';

import '../../../../organizacion/organizacion_providers.dart';
import '../../../finanzas_providers.dart';
import '../../pagos/pagos_list_screen.dart' show formatoCentavosPago;
import '../../pagos/widgets/pago_detalle_dialog.dart';
import '../cuentas_por_cobrar_controller.dart';
import '../cuentas_por_cobrar_list_screen.dart' show formatoCentavosCuentaPorCobrar;
import 'cuenta_por_cobrar_definir_vencimiento_dialog.dart';
import 'registrar_pago_aplicado_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Detalle de una Cuenta por cobrar (Etapa 4J.1) — snapshot
/// administrativo completo (Marlon: "no quiero depender de joins para
/// reconstruir el documento años después") más antigüedad derivada e
/// historial append-only, mismo criterio que `AgendaDetalleDialog`.
class CuentaPorCobrarDetalleDialog extends ConsumerStatefulWidget {
  const CuentaPorCobrarDetalleDialog({required this.cuentaPorCobrarId, super.key});

  final String cuentaPorCobrarId;

  @override
  ConsumerState<CuentaPorCobrarDetalleDialog> createState() => _CuentaPorCobrarDetalleDialogState();
}

class _CuentaPorCobrarDetalleDialogState extends ConsumerState<CuentaPorCobrarDetalleDialog> {
  CuentaPorCobrarData? _cuenta;
  List<CuentaPorCobrarEventoData> _eventos = const [];
  List<AplicacionPagoData> _aplicacionesPago = const [];
  final Map<String, String> _folioPagoPorAplicacion = {};
  bool _algunPagoConComplementoPendiente = false;
  String? _clienteNombre;
  bool _cargando = true;
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final notifier = ref.read(cuentasPorCobrarControllerProvider.notifier);
    final cuenta = await notifier.obtenerPorId(widget.cuentaPorCobrarId);
    final eventos = await notifier.listarEventos(widget.cuentaPorCobrarId);
    final aplicacionesPago =
        await ref.read(pagoRepositoryProvider).listarAplicacionesPorCuenta(widget.cuentaPorCobrarId);

    String? clienteNombre;
    if (cuenta != null) {
      final cliente = await ref.read(clienteRepositoryProvider).obtenerPorId(cuenta.clienteId);
      clienteNombre = cliente?.nombreComercial;
    }
    for (final aplicacion in aplicacionesPago) {
      if (_folioPagoPorAplicacion.containsKey(aplicacion.id)) continue;
      final pago = await ref.read(pagoRepositoryProvider).obtenerPorId(aplicacion.pagoId);
      if (pago != null) _folioPagoPorAplicacion[aplicacion.id] = pago.folioPago;
    }

    // Cierre de cobranza (Etapa 4J.3): revisa, para cada aplicación
    // activa, si el Pago de origen ya tiene su Complemento vigente —
    // basta con que uno solo siga pendiente para que la Cuenta no
    // cuente como fiscalmente cerrada.
    var algunPendiente = false;
    for (final aplicacion in aplicacionesPago) {
      if (EstatusAplicacionPago.values.byName(aplicacion.estatus) != EstatusAplicacionPago.aplicada) continue;
      final complemento = await ref.read(complementoPagoRepositoryProvider).obtenerPorPagoId(aplicacion.pagoId);
      if (complementoPendiente(requiereComplemento: true, complemento: complemento)) {
        algunPendiente = true;
        break;
      }
    }

    if (!mounted) return;
    setState(() {
      _cuenta = cuenta;
      _eventos = eventos;
      _aplicacionesPago = aplicacionesPago;
      _algunPagoConComplementoPendiente = algunPendiente;
      _clienteNombre = clienteNombre;
      _cargando = false;
    });
  }

  String _tipoDocumentoLabel(AppLocalizations l10n, String valor) {
    return switch (TipoDocumentoCobro.values.byName(valor)) {
      TipoDocumentoCobro.cfdi => l10n.servicioCobroTipoDocumentoCfdi,
      TipoDocumentoCobro.reciboDePago => l10n.servicioCobroTipoDocumentoReciboDePago,
    };
  }

  String _metodoLabel(AppLocalizations l10n, String valor) {
    return switch (MetodoPagoCobro.values.byName(valor)) {
      MetodoPagoCobro.pue => l10n.servicioCobroMetodoPue,
      MetodoPagoCobro.ppd => l10n.servicioCobroMetodoPpd,
      MetodoPagoCobro.noAplica => l10n.servicioCobroMetodoNoAplica,
    };
  }

  String _estatusLabel(AppLocalizations l10n, String estatus) {
    return switch (EstatusCuentaPorCobrar.values.byName(estatus)) {
      EstatusCuentaPorCobrar.pendiente => l10n.cuentasPorCobrarEstatusPendiente,
      EstatusCuentaPorCobrar.parcial => l10n.cuentasPorCobrarEstatusParcial,
      EstatusCuentaPorCobrar.pagada => l10n.cuentasPorCobrarEstatusPagada,
    };
  }

  RisegStatusTone _estatusTono(String estatus) {
    return switch (EstatusCuentaPorCobrar.values.byName(estatus)) {
      EstatusCuentaPorCobrar.pendiente => RisegStatusTone.info,
      EstatusCuentaPorCobrar.parcial => RisegStatusTone.warning,
      EstatusCuentaPorCobrar.pagada => RisegStatusTone.success,
    };
  }

  String _antiguedadLabel(AppLocalizations l10n, RangoAntiguedadCuentaPorCobrar rango) {
    return switch (rango) {
      RangoAntiguedadCuentaPorCobrar.alCorriente => l10n.cuentaPorCobrarDetalleAntiguedadAlCorriente,
      RangoAntiguedadCuentaPorCobrar.dias0a30 => l10n.cuentaPorCobrarDetalleAntiguedad0a30,
      RangoAntiguedadCuentaPorCobrar.dias31a60 => l10n.cuentaPorCobrarDetalleAntiguedad31a60,
      RangoAntiguedadCuentaPorCobrar.dias61a90 => l10n.cuentaPorCobrarDetalleAntiguedad61a90,
      RangoAntiguedadCuentaPorCobrar.dias90Mas => l10n.cuentaPorCobrarDetalleAntiguedad90Mas,
    };
  }

  String _eventoLabel(AppLocalizations l10n, String tipoEvento) {
    return switch (TipoEventoCuentaPorCobrar.values.byName(tipoEvento)) {
      TipoEventoCuentaPorCobrar.creada => l10n.cuentaPorCobrarDetalleHistorialEventoCreada,
      TipoEventoCuentaPorCobrar.fechaVencimientoDefinida =>
        l10n.cuentaPorCobrarDetalleHistorialEventoFechaVencimientoDefinida,
      TipoEventoCuentaPorCobrar.pagoAplicado => l10n.cuentaPorCobrarDetalleHistorialEventoPagoAplicado,
      TipoEventoCuentaPorCobrar.pagoAplicacionCancelada =>
        l10n.cuentaPorCobrarDetalleHistorialEventoPagoAplicacionCancelada,
    };
  }

  Future<void> _definirVencimiento() async {
    final actualizo = await mostrarDialogoDefinirVencimientoCuentaPorCobrar(
      context,
      ref,
      widget.cuentaPorCobrarId,
      fechaActual: _cuenta?.fechaVencimiento,
    );
    if (actualizo) await _cargar();
  }

  Future<void> _registrarPago() async {
    final actualizo = await mostrarDialogoRegistrarPagoAplicado(
      context,
      ref,
      cuentaPorCobrarId: widget.cuentaPorCobrarId,
      saldoPendiente: _cuenta!.saldoPendiente,
    );
    if (actualizo) await _cargar();
  }

  Future<void> _verPago(AplicacionPagoData aplicacion) async {
    await showDialog<void>(context: context, builder: (_) => PagoDetalleDialog(pagoId: aplicacion.pagoId));
    await _cargar();
  }

  Future<void> _cancelarAplicacionPago(AplicacionPagoData aplicacion) async {
    final l10n = AppLocalizations.of(context)!;
    final motivoController = TextEditingController();
    final confirmado = await RisegDialog.showForm<bool>(
      context: context,
      title: l10n.cancelarAplicacionPagoConfirmacionTitulo,
      confirmLabel: l10n.cancelarAplicacionPagoConfirmacionConfirmar,
      cancelLabel: l10n.cancelarAplicacionPagoConfirmacionCancelar,
      contentBuilder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.cancelarAplicacionPagoConfirmacionMensaje, style: AppTypography.body),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(label: l10n.pagoMotivoCampo, controller: motivoController, autofocus: true),
        ],
      ),
      onConfirm: () async => true,
    );
    if (confirmado != true) {
      motivoController.dispose();
      return;
    }
    final motivo = motivoController.text.trim();
    motivoController.dispose();
    if (!mounted) return;

    setState(() => _procesando = true);
    final resultado = await ref
        .read(cancelarAplicacionPagoUseCaseProvider)
        .ejecutar(aplicacionPagoId: aplicacion.id, motivo: motivo);
    if (!mounted) return;
    setState(() => _procesando = false);

    switch (resultado) {
      case CancelarAplicacionPagoExitoso():
        RisegFeedback.showSuccess(context, l10n.cancelarAplicacionPagoExito);
        await _cargar();
      case CancelarAplicacionPagoNoExiste():
      case CancelarAplicacionPagoYaCancelada():
      case CancelarAplicacionPagoErrorInesperado():
        RisegFeedback.showError(context, l10n.cancelarAplicacionPagoErrorInesperado);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final hoy = DateTime.now();

    Widget content;
    if (_cargando) {
      content = const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    } else if (_cuenta == null) {
      content = Text(l10n.cuentasPorCobrarListadoCargaErrorMensaje);
    } else {
      final c = _cuenta!;
      final esCfdi = TipoDocumentoCobro.values.byName(c.tipoDocumento) == TipoDocumentoCobro.cfdi;
      final rango = calcularRangoAntiguedad(c, hoy);

      content = SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: CampoConsulta(
                    label: l10n.cuentasPorCobrarColumnaCliente,
                    value: _clienteNombre ?? c.clienteId,
                  ),
                ),
                RisegStatusBadge(label: _estatusLabel(l10n, c.estatus), tone: _estatusTono(c.estatus)),
                if (cuentaRequiereComplemento(c)) ...[
                  const SizedBox(width: AppSpacing.xs),
                  RisegStatusBadge(
                    label: cierreCobranzaCompleto(cuenta: c, algunPagoConComplementoPendiente: _algunPagoConComplementoPendiente)
                        ? l10n.cuentaPorCobrarDetalleCierreCobranzaCompleto
                        : l10n.cuentaPorCobrarDetalleCierreCobranzaPendiente,
                    tone: cierreCobranzaCompleto(cuenta: c, algunPagoConComplementoPendiente: _algunPagoConComplementoPendiente)
                        ? RisegStatusTone.success
                        : RisegStatusTone.warning,
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: CampoConsulta(
                    label: l10n.cuentaPorCobrarDetalleCampoFolioDocumento,
                    value: c.folioDocumento,
                  ),
                ),
                if (esCfdi) ...[
                  Expanded(
                    child: CampoConsulta(label: l10n.cuentaPorCobrarDetalleCampoSerieFiscal, value: c.serieFiscal),
                  ),
                  Expanded(
                    child: CampoConsulta(label: l10n.cuentaPorCobrarDetalleCampoFolioFiscal, value: c.folioFiscal),
                  ),
                ],
              ],
            ),
            if (esCfdi) ...[
              const SizedBox(height: AppSpacing.sm),
              CampoConsulta(label: l10n.cuentaPorCobrarDetalleCampoUuid, value: c.uuid),
            ],
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: CampoConsulta(
                    label: l10n.cuentaPorCobrarDetalleCampoTipoDocumento,
                    value: _tipoDocumentoLabel(l10n, c.tipoDocumento),
                  ),
                ),
                Expanded(
                  child: CampoConsulta(
                    label: l10n.cuentaPorCobrarDetalleCampoMetodo,
                    value: _metodoLabel(l10n, c.metodo),
                  ),
                ),
              ],
            ),
            // Mismo criterio que la ficha de Configuración de cobro
            // (`servicioCobroRequiereComplementoAviso`): solo aparece
            // cuando aplica, nunca un "No" ambiguo.
            if (c.requiereComplemento) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.cuentaPorCobrarDetalleCampoRequiereComplemento,
                style: AppTypography.caption.copyWith(color: colors.info),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: CampoConsulta(
                    label: l10n.cuentaPorCobrarDetalleCampoFechaEmisionReal,
                    value: _formatoFecha.format(c.fechaEmisionReal),
                  ),
                ),
                Expanded(
                  child: CampoConsulta(
                    label: l10n.cuentaPorCobrarDetalleCampoImporteEmitido,
                    value: formatoCentavosCuentaPorCobrar(c.importeEmitido),
                  ),
                ),
                Expanded(
                  child: CampoConsulta(label: l10n.cuentaPorCobrarDetalleCampoMoneda, value: c.moneda),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: CampoConsulta(
                    label: l10n.cuentaPorCobrarDetalleCampoSaldoOriginal,
                    value: formatoCentavosCuentaPorCobrar(c.saldoOriginal),
                  ),
                ),
                Expanded(
                  child: CampoConsulta(
                    label: l10n.cuentaPorCobrarDetalleCampoSaldoPendiente,
                    value: formatoCentavosCuentaPorCobrar(c.saldoPendiente),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: CampoConsulta(
                    label: l10n.cuentaPorCobrarDetalleCampoVencimiento,
                    value: c.fechaVencimiento == null
                        ? l10n.cuentasPorCobrarSinVencimiento
                        : _formatoFecha.format(c.fechaVencimiento!),
                  ),
                ),
                Expanded(
                  child: CampoConsulta(
                    label: l10n.cuentaPorCobrarDetalleCampoAntiguedad,
                    value: _antiguedadLabel(l10n, rango),
                  ),
                ),
              ],
            ),
            if (c.observaciones != null && c.observaciones!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              CampoConsulta(label: l10n.agendaDetalleCampoObservaciones, value: c.observaciones),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.cuentaPorCobrarDetalleSeccionPagos,
                    style: AppTypography.heading3.copyWith(color: colors.textPrimary),
                  ),
                ),
                if (EstatusCuentaPorCobrar.values.byName(c.estatus) != EstatusCuentaPorCobrar.pagada)
                  RisegButton(
                    label: l10n.cuentaPorCobrarDetalleBotonRegistrarPago,
                    variant: RisegButtonVariant.ghost,
                    onPressed: _registrarPago,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_aplicacionesPago.isEmpty)
              Text(
                l10n.cuentaPorCobrarDetallePagosSinPagos,
                style: AppTypography.body.copyWith(color: colors.textMuted),
              )
            else
              for (final aplicacion in _aplicacionesPago)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(_folioPagoPorAplicacion[aplicacion.id] ?? aplicacion.pagoId),
                      ),
                      SizedBox(width: 110, child: Text(formatoCentavosPago(aplicacion.monto))),
                      SizedBox(
                        width: 100,
                        child: RisegStatusBadge(
                          label: EstatusAplicacionPago.values.byName(aplicacion.estatus) ==
                                  EstatusAplicacionPago.aplicada
                              ? l10n.aplicacionPagoEstatusAplicada
                              : l10n.aplicacionPagoEstatusCancelada,
                          tone: EstatusAplicacionPago.values.byName(aplicacion.estatus) ==
                                  EstatusAplicacionPago.aplicada
                              ? RisegStatusTone.success
                              : RisegStatusTone.neutral,
                        ),
                      ),
                      RisegButton(
                        label: l10n.pagoDetalleDialogoTitulo,
                        variant: RisegButtonVariant.ghost,
                        onPressed: () => _verPago(aplicacion),
                      ),
                      if (EstatusAplicacionPago.values.byName(aplicacion.estatus) == EstatusAplicacionPago.aplicada)
                        RisegButton(
                          label: l10n.cuentaPorCobrarDetalleBotonCancelarAplicacion,
                          variant: RisegButtonVariant.ghost,
                          loading: _procesando,
                          onPressed: () => _cancelarAplicacionPago(aplicacion),
                        ),
                    ],
                  ),
                ),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.cuentaPorCobrarDetalleSeccionHistorial,
              style: AppTypography.heading3.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_eventos.isEmpty)
              Text(
                l10n.cuentaPorCobrarDetalleHistorialSinEventos,
                style: AppTypography.body.copyWith(color: colors.textMuted),
              )
            else
              for (final evento in _eventos)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _formatoFechaHora.format(evento.fechaHora),
                            style: AppTypography.caption.copyWith(color: colors.textMuted),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(_eventoLabel(l10n, evento.tipoEvento), style: AppTypography.label),
                        ],
                      ),
                      if (evento.actor != null)
                        Text(
                          '${l10n.cuentaPorCobrarDetalleHistorialCampoActor}: ${evento.actor}',
                          style: AppTypography.caption.copyWith(color: colors.textMuted),
                        ),
                      if (evento.observacion != null && evento.observacion!.trim().isNotEmpty)
                        Text(evento.observacion!, style: AppTypography.body.copyWith(color: colors.textMuted)),
                    ],
                  ),
                ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                RisegButton(
                  label: c.fechaVencimiento == null
                      ? l10n.cuentaPorCobrarDetalleBotonDefinirVencimiento
                      : l10n.cuentaPorCobrarDetalleBotonCorregirVencimiento,
                  variant: RisegButtonVariant.secondary,
                  onPressed: _definirVencimiento,
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.cuentaPorCobrarDetalleDialogoTitulo,
                      style: AppTypography.heading2.copyWith(color: colors.textPrimary),
                    ),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                content,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
