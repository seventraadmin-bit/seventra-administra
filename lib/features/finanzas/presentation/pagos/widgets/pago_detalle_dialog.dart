import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/adjuntar_comprobante_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_aplicacion_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/complemento_pago_derivado.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../../../organizacion/organizacion_providers.dart';
import '../../../finanzas_providers.dart';
import '../../complementos/widgets/complemento_detalle_dialog.dart';
import '../../cuentas_por_cobrar/cuentas_por_cobrar_controller.dart';
import '../../cuentas_por_cobrar/cuentas_por_cobrar_list_screen.dart' show formatoCentavosCuentaPorCobrar;
import '../pagos_controller.dart';
import '../pagos_list_screen.dart' show formaPagoLabel, formatoCentavosPago, pagoEstatusLabel, pagoEstatusTono;
import 'corregir_pago_dialog.dart';
import 'eliminar_pago_fisicamente_dialog.dart';
import 'registrar_complemento_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Detalle de un Pago (Etapa 4J.2) — dinero recibido, sus aplicaciones
/// a Cuentas por cobrar (modelo N:M), comprobantes adjuntos (mismo
/// mecanismo que cualquier otro `Attachment`) e historial
/// administrativo propio (`PagoEvento`).
class PagoDetalleDialog extends ConsumerStatefulWidget {
  const PagoDetalleDialog({required this.pagoId, super.key});

  final String pagoId;

  @override
  ConsumerState<PagoDetalleDialog> createState() => _PagoDetalleDialogState();
}

class _PagoDetalleDialogState extends ConsumerState<PagoDetalleDialog> {
  PagoData? _pago;
  List<AplicacionPagoData> _aplicaciones = const [];
  List<PagoEventoData> _eventos = const [];
  List<AttachmentData> _comprobantes = const [];
  final Map<String, String> _folioPorCuenta = {};
  final List<CuentaPorCobrarData> _cuentasDeAplicacionesActivas = [];
  ComplementoPagoData? _complemento;
  String? _clienteNombre;
  Map<String, String> _usuariosPorId = const {};
  bool _cargando = true;
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final notifier = ref.read(pagosControllerProvider.notifier);
    final pago = await notifier.obtenerPorId(widget.pagoId);
    final aplicaciones = await notifier.listarAplicaciones(widget.pagoId);
    final eventos = await notifier.listarEventos(widget.pagoId);
    final comprobantes = await notifier.listarComprobantes(widget.pagoId);
    final complemento = await ref.read(complementoPagoRepositoryProvider).obtenerPorPagoId(widget.pagoId);
    final usuarios = await ref.read(usuarioRepositoryProvider).listar();
    final usuariosPorId = {for (final u in usuarios) u.id: u.nombre};

    String? clienteNombre;
    if (pago != null) {
      final cliente = await ref.read(clienteRepositoryProvider).obtenerPorId(pago.clienteId);
      clienteNombre = cliente?.nombreComercial;
    }
    _cuentasDeAplicacionesActivas.clear();
    for (final aplicacion in aplicaciones) {
      final cuenta = await ref.read(cuentaPorCobrarRepositoryProvider).obtenerPorId(aplicacion.cuentaPorCobrarId);
      if (cuenta == null) continue;
      _folioPorCuenta[aplicacion.cuentaPorCobrarId] = cuenta.folioDocumento ?? cuenta.documentoPorEmitirId;
      if (EstatusAplicacionPago.values.byName(aplicacion.estatus) == EstatusAplicacionPago.aplicada) {
        _cuentasDeAplicacionesActivas.add(cuenta);
      }
    }

    if (!mounted) return;
    setState(() {
      _pago = pago;
      _aplicaciones = aplicaciones;
      _eventos = eventos;
      _comprobantes = comprobantes;
      _complemento = complemento;
      _clienteNombre = clienteNombre;
      _usuariosPorId = usuariosPorId;
      _cargando = false;
    });
  }

  Future<void> _registrarComplemento() async {
    final actualizo = await mostrarDialogoRegistrarComplemento(context, ref, widget.pagoId);
    if (actualizo) await _cargar();
  }

  Future<void> _verComplemento() async {
    await showDialog<void>(
      context: context,
      builder: (_) => ComplementoDetalleDialog(complementoPagoId: _complemento!.id),
    );
    await _cargar();
  }

  String _eventoLabel(AppLocalizations l10n, String tipoEvento) {
    return switch (TipoEventoPago.values.byName(tipoEvento)) {
      TipoEventoPago.registrado => l10n.pagoDetalleHistorialEventoRegistrado,
      TipoEventoPago.corregido => l10n.pagoDetalleHistorialEventoCorregido,
      TipoEventoPago.cancelado => l10n.pagoDetalleHistorialEventoCancelado,
      TipoEventoPago.comprobanteAdjuntado => l10n.pagoDetalleHistorialEventoComprobanteAdjuntado,
    };
  }

  Future<void> _corregir() async {
    final actualizo = await mostrarDialogoCorregirPago(context, ref, _pago!);
    if (actualizo) await _cargar();
  }

  Future<void> _cancelarPago() async {
    final l10n = AppLocalizations.of(context)!;
    final motivoController = TextEditingController();
    final confirmado = await RisegDialog.showForm<bool>(
      context: context,
      title: l10n.cancelarPagoConfirmacionTitulo,
      confirmLabel: l10n.cancelarPagoConfirmacionConfirmar,
      cancelLabel: l10n.cancelarPagoConfirmacionCancelar,
      contentBuilder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.cancelarPagoConfirmacionMensaje, style: AppTypography.body),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(label: l10n.pagoMotivoCampo, controller: motivoController, autofocus: true),
        ],
      ),
      onConfirm: () async => true,
    );
    // Diferido con `addPostFrameCallback` — el diálogo de confirmación
    // sigue en su transición de cierre cuando este `await` regresa
    // (Etapa 15, mismo hallazgo real de `egreso_detalle_dialog.dart`;
    // destruir el controller de forma síncrona aquí producía "A
    // TextEditingController was used after being disposed").
    if (confirmado != true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => motivoController.dispose());
      return;
    }
    final motivo = motivoController.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) => motivoController.dispose());
    if (!mounted) return;

    setState(() => _procesando = true);
    final resultado = await ref.read(pagosControllerProvider.notifier).cancelar(pagoId: widget.pagoId, motivo: motivo);
    if (!mounted) return;
    setState(() => _procesando = false);

    switch (resultado) {
      case CancelarPagoExitoso():
        RisegFeedback.showSuccess(context, l10n.cancelarPagoExito);
        await _cargar();
      case CancelarPagoNoExiste():
      case CancelarPagoYaCancelado():
      case CancelarPagoErrorInesperado():
        RisegFeedback.showError(context, l10n.cancelarPagoErrorInesperado);
    }
  }

  Future<void> _cancelarAplicacion(AplicacionPagoData aplicacion) async {
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
      WidgetsBinding.instance.addPostFrameCallback((_) => motivoController.dispose());
      return;
    }
    final motivo = motivoController.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) => motivoController.dispose());
    if (!mounted) return;

    setState(() => _procesando = true);
    final resultado = await ref
        .read(pagosControllerProvider.notifier)
        .cancelarAplicacion(aplicacionPagoId: aplicacion.id, motivo: motivo);
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

  Future<void> _adjuntarComprobante() async {
    final l10n = AppLocalizations.of(context)!;
    final seleccion = await FilePicker.platform.pickFiles();
    final archivo = seleccion?.files.singleOrNull;
    if (archivo?.path == null) return;
    if (!mounted) return;

    final resultado = await ref.read(pagosControllerProvider.notifier).adjuntarComprobante(
          pagoId: widget.pagoId,
          sourceFilePath: archivo!.path!,
          originalFileName: archivo.name,
          mimeType: _mimeTypeParaExtension(archivo.extension),
        );
    if (!mounted) return;

    switch (resultado) {
      case AdjuntarComprobantePagoExitoso():
        await _cargar();
      case AdjuntarComprobantePagoNoExiste():
      case AdjuntarComprobantePagoErrorInesperado():
        RisegFeedback.showError(context, l10n.pagoAplicadoErrorInesperado);
    }
  }

  String _mimeTypeParaExtension(String? extension) {
    return switch (extension?.toLowerCase()) {
      'pdf' => 'application/pdf',
      'xml' => 'text/xml',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      _ => 'application/octet-stream',
    };
  }

  Future<void> _eliminarFisicamente() async {
    final eliminado = await mostrarDialogoEliminarPagoFisicamente(context, ref, widget.pagoId);
    if (!eliminado) return;
    ref.invalidate(pagosControllerProvider);
    // Un Pago cancelado sin Complemento no puede tener aplicaciones
    // activas (garantizado por el bloqueo del propio use case), pero
    // sus aplicaciones canceladas dejan de existir junto con él — el
    // listado de Cuentas por cobrar no depende de esto para su saldo
    // (ya se revirtió al cancelar), pero sí puede depender de esta
    // eliminación para dejar de estar bloqueado (Etapa 15).
    ref.invalidate(cuentasPorCobrarControllerProvider);
    if (mounted) Navigator.of(context).pop();
  }

  String _aplicacionEstatusLabel(AppLocalizations l10n, String estatus) {
    return switch (EstatusAplicacionPago.values.byName(estatus)) {
      EstatusAplicacionPago.aplicada => l10n.aplicacionPagoEstatusAplicada,
      EstatusAplicacionPago.cancelada => l10n.aplicacionPagoEstatusCancelada,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;

    Widget content;
    if (_cargando) {
      content = const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    } else if (_pago == null) {
      content = Text(l10n.pagosListadoCargaErrorMensaje);
    } else {
      final p = _pago!;
      final cancelado = EstatusPago.values.byName(p.estatus) == EstatusPago.cancelado;
      final montoSinAplicar = p.montoTotal - p.montoAplicado;

      content = SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: CampoConsulta(label: l10n.pagoDetalleCampoFolio, value: p.folioPago)),
                RisegStatusBadge(label: pagoEstatusLabel(l10n, p.estatus), tone: pagoEstatusTono(p.estatus)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            CampoConsulta(label: l10n.pagoDetalleCampoCliente, value: _clienteNombre ?? p.clienteId),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: CampoConsulta(label: l10n.pagoDetalleCampoMontoTotal, value: formatoCentavosPago(p.montoTotal))),
                Expanded(child: CampoConsulta(label: l10n.pagoDetalleCampoMontoAplicado, value: formatoCentavosPago(p.montoAplicado))),
                Expanded(child: CampoConsulta(label: l10n.pagoDetalleCampoMontoSinAplicar, value: formatoCentavosPago(montoSinAplicar))),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: CampoConsulta(label: l10n.pagoDetalleCampoFecha, value: _formatoFecha.format(p.fechaPago))),
                Expanded(child: CampoConsulta(label: l10n.pagoDetalleCampoFormaPago, value: formaPagoLabel(l10n, p.formaPago))),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: CampoConsulta(label: l10n.pagoDetalleCampoReferencia, value: p.referencia)),
                Expanded(child: CampoConsulta(label: l10n.pagoDetalleCampoBancoOrigen, value: p.bancoOrigen)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            CampoConsulta(label: l10n.pagoDetalleCampoCuentaBancariaDestino, value: p.cuentaBancariaDestino),
            if (p.observaciones != null && p.observaciones!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              CampoConsulta(label: l10n.pagoDetalleCampoObservaciones, value: p.observaciones),
            ],
            const SizedBox(height: AppSpacing.md),
            Text(l10n.pagoDetalleSeccionAplicaciones, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            if (_aplicaciones.isEmpty)
              Text(l10n.pagoDetalleAplicacionesSinAplicaciones, style: AppTypography.body.copyWith(color: colors.textMuted))
            else
              for (final aplicacion in _aplicaciones)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(_folioPorCuenta[aplicacion.cuentaPorCobrarId] ?? aplicacion.cuentaPorCobrarId),
                      ),
                      SizedBox(width: 110, child: Text(formatoCentavosCuentaPorCobrar(aplicacion.monto))),
                      SizedBox(
                        width: 110,
                        child: RisegStatusBadge(
                          label: _aplicacionEstatusLabel(l10n, aplicacion.estatus),
                          tone: EstatusAplicacionPago.values.byName(aplicacion.estatus) ==
                                  EstatusAplicacionPago.aplicada
                              ? RisegStatusTone.success
                              : RisegStatusTone.neutral,
                        ),
                      ),
                      if (EstatusAplicacionPago.values.byName(aplicacion.estatus) == EstatusAplicacionPago.aplicada)
                        RisegButton(
                          label: l10n.cuentaPorCobrarDetalleBotonCancelarAplicacion,
                          variant: RisegButtonVariant.ghost,
                          loading: _procesando,
                          onPressed: () => _cancelarAplicacion(aplicacion),
                        ),
                    ],
                  ),
                ),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.pagoDetalleSeccionComplemento,
              style: AppTypography.heading3.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Builder(builder: (context) {
              final requiere = pagoRequiereComplemento(_cuentasDeAplicacionesActivas);
              if (!requiere) {
                return Text(
                  l10n.pagoDetalleComplementoNoAplica,
                  style: AppTypography.body.copyWith(color: colors.textMuted),
                );
              }
              final pendiente = complementoPendiente(requiereComplemento: true, complemento: _complemento);
              if (pendiente) {
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.pagoDetalleComplementoSinRegistrar,
                        style: AppTypography.body.copyWith(color: colors.textMuted),
                      ),
                    ),
                    RisegStatusBadge(label: l10n.pagoDetalleComplementoPendienteEtiqueta, tone: RisegStatusTone.warning),
                    const SizedBox(width: AppSpacing.xs),
                    RisegButton(
                      label: l10n.pagoDetalleBotonRegistrarComplemento,
                      variant: RisegButtonVariant.secondary,
                      onPressed: _registrarComplemento,
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: Text(_complemento!.uuid)),
                  RisegButton(
                    label: l10n.pagoDetalleBotonVerComplemento,
                    variant: RisegButtonVariant.ghost,
                    onPressed: _verComplemento,
                  ),
                ],
              );
            }),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.pagoDetalleSeccionComprobantes,
                    style: AppTypography.heading3.copyWith(color: colors.textPrimary),
                  ),
                ),
                RisegButton(
                  label: l10n.pagoDetalleBotonAdjuntarComprobante,
                  variant: RisegButtonVariant.ghost,
                  onPressed: _adjuntarComprobante,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_comprobantes.isEmpty)
              Text(
                l10n.pagoDetalleComprobantesSinComprobantes,
                style: AppTypography.body.copyWith(color: colors.textMuted),
              )
            else
              for (final comprobante in _comprobantes)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${comprobante.originalFileName} · ${l10n.agendaAdjuntoTamano((comprobante.sizeBytes / 1024).toStringAsFixed(1))}',
                        ),
                      ),
                      RisegButton(
                        label: l10n.agendaAdjuntoBotonAbrir,
                        variant: RisegButtonVariant.ghost,
                        onPressed: () => ref.read(pagosControllerProvider.notifier).abrirArchivo(comprobante.path),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.pagoDetalleSeccionHistorial, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            if (_eventos.isEmpty)
              Text(l10n.pagoDetalleHistorialSinEventos, style: AppTypography.body.copyWith(color: colors.textMuted))
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
                      if (evento.actorUsuarioId != null)
                        Text(
                          '${l10n.pagoDetalleHistorialCampoActor}: '
                          '${_usuariosPorId[evento.actorUsuarioId] ?? evento.actorUsuarioId}',
                          style: AppTypography.caption.copyWith(color: colors.textMuted),
                        ),
                      if (evento.observacion != null && evento.observacion!.trim().isNotEmpty)
                        Text(evento.observacion!, style: AppTypography.body.copyWith(color: colors.textMuted)),
                    ],
                  ),
                ),
            const SizedBox(height: AppSpacing.lg),
            if (!cancelado || esMaestro)
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (!cancelado) ...[
                    RisegButton(
                      label: l10n.pagoDetalleBotonCorregir,
                      variant: RisegButtonVariant.secondary,
                      onPressed: _corregir,
                    ),
                    RisegButton(
                      label: l10n.pagoDetalleBotonCancelar,
                      variant: RisegButtonVariant.danger,
                      loading: _procesando,
                      onPressed: _cancelarPago,
                    ),
                  ],
                  // Extraordinaria (Maestro) — nunca depende del
                  // estatus: un Pago ya cancelado (captura de prueba)
                  // sigue siendo elegible para limpiar por completo,
                  // salvo que tenga un Complemento real (Etapa 15).
                  if (esMaestro)
                    RisegActionsMenu(
                      menuKey: const Key('pago_menu_acciones'),
                      actions: [
                        RisegMenuAction(
                          key: const Key('pago_accion_eliminar_fisicamente'),
                          label: l10n.eliminacionFisicaAccionMenu,
                          icon: Icons.delete_forever_outlined,
                          destructive: true,
                          onTap: _eliminarFisicamente,
                        ),
                      ],
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
                    Text(l10n.pagoDetalleDialogoTitulo, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
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
