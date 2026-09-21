import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/finanzas/data/tables/egreso_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/adjuntar_comprobante_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_origen_automatico_egreso_usecase.dart';
import 'package:riseg_one/features/nomina/presentation/nominas/widgets/pago_nomina_detalle_dialog.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../../finanzas_providers.dart';
import '../../cuentas_financieras/cuentas_financieras_controller.dart';
import '../../pagos/pagos_list_screen.dart' show formaPagoLabel, formatoCentavosPago;
import '../../planeacion/planeacion_financiera_controller.dart';
import '../../resumen/resumen_financiero_controller.dart';
import '../egresos_controller.dart';
import '../egresos_list_screen.dart' show egresoEstatusLabel, egresoEstatusTono;
import 'corregir_egreso_dialog.dart';
import 'eliminar_egreso_fisicamente_dialog.dart';
import 'corregir_origen_financiero_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Detalle de un Egreso (Etapa 4K.1) — datos administrativos,
/// comprobante adjunto e historial (`EgresoEvento`).
class EgresoDetalleDialog extends ConsumerStatefulWidget {
  const EgresoDetalleDialog({required this.egresoId, super.key});

  final String egresoId;

  @override
  ConsumerState<EgresoDetalleDialog> createState() => _EgresoDetalleDialogState();
}

class _EgresoDetalleDialogState extends ConsumerState<EgresoDetalleDialog> {
  EgresoData? _egreso;
  List<EgresoEventoData> _eventos = const [];
  List<AttachmentData> _comprobantes = const [];
  OrigenAutomaticoEgreso? _origen;

  /// Nombre legible del ORIGEN FINANCIERO (Etapa "Origen financiero de
  /// Egresos manuales") — de dónde salió el dinero. No confundir con
  /// [_origen], que es qué MÓDULO generó este Egreso. `null` cuando el
  /// gasto no tiene origen capturado (todo Egreso histórico).
  String? _origenFinancieroNombre;

  /// Poblado solo cuando el gasto se financió con una TDC — habilita
  /// navegar a su expediente, la mitad "gasto → Deuda/TDC" de la
  /// trazabilidad que pide el punto 11.
  String? _origenFinancieroDeudaId;

  bool _cargando = true;
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final notifier = ref.read(egresosControllerProvider.notifier);
    final egreso = await notifier.obtenerPorId(widget.egresoId);
    final eventos = await notifier.listarEventos(widget.egresoId);
    final comprobantes = await notifier.listarComprobantes(widget.egresoId);
    final origen = await notifier.obtenerOrigenAutomatico(widget.egresoId);

    // Origen financiero resuelto por FK real, nunca por `formaPago` ni
    // por texto (Etapa "Origen financiero de Egresos manuales").
    String? origenFinancieroNombre;
    String? origenFinancieroDeudaId;
    if (egreso?.deudaId != null) {
      final tarjeta = await ref.read(deudaRepositoryProvider).obtenerPorId(egreso!.deudaId!);
      origenFinancieroNombre = tarjeta?.nombre;
      origenFinancieroDeudaId = egreso.deudaId;
    } else if (egreso?.cuentaFinancieraId != null) {
      final cuenta = await ref.read(cuentaFinancieraRepositoryProvider).obtenerPorId(egreso!.cuentaFinancieraId!);
      origenFinancieroNombre = cuenta?.nombre;
    }

    if (!mounted) return;
    setState(() {
      _egreso = egreso;
      _eventos = eventos;
      _comprobantes = comprobantes;
      _origen = origen;
      _origenFinancieroNombre = origenFinancieroNombre;
      _origenFinancieroDeudaId = origenFinancieroDeudaId;
      _cargando = false;
    });
  }

  String _origenLabel(AppLocalizations l10n, OrigenAutomaticoEgreso origen) {
    return switch (origen) {
      OrigenAutomaticoEgresoCompra() => l10n.egresosOrigenCompra,
      OrigenAutomaticoEgresoNomina() => l10n.egresosOrigenNomina,
      OrigenAutomaticoEgresoTiempoExtra() => l10n.egresosOrigenTiempoExtra,
      OrigenAutomaticoEgresoDeuda() => l10n.egresosOrigenDeuda,
      OrigenAutomaticoEgresoDescuentoProgramado() => l10n.egresosOrigenDescuentoProgramado,
      OrigenAutomaticoEgresoVehiculo() => l10n.egresosOrigenVehiculo,
      OrigenAutomaticoEgresoTelefonia() => l10n.egresosOrigenTelefonia,
      OrigenAutomaticoEgresoServicioEventual() => l10n.egresosOrigenServicioEventual,
    };
  }

  String _origenFolio(OrigenAutomaticoEgreso origen) {
    return switch (origen) {
      OrigenAutomaticoEgresoCompra(:final folio) => folio,
      OrigenAutomaticoEgresoNomina(:final folio) => folio,
      OrigenAutomaticoEgresoTiempoExtra(:final folio) => folio,
      OrigenAutomaticoEgresoDeuda(:final folio) => folio,
      OrigenAutomaticoEgresoDescuentoProgramado(:final folio) => folio,
      OrigenAutomaticoEgresoVehiculo(:final folio) => folio,
      OrigenAutomaticoEgresoTelefonia(:final folio) => folio,
      OrigenAutomaticoEgresoServicioEventual(:final folio) => folio,
    };
  }

  Future<void> _verOrigen() async {
    final origen = _origen;
    if (origen == null) return;
    switch (origen) {
      case OrigenAutomaticoEgresoCompra():
        Navigator.of(context).pop();
        context.push('/compras/${origen.compraId}');
      case OrigenAutomaticoEgresoNomina():
        await showDialog<void>(context: context, builder: (_) => PagoNominaDetalleDialog(pagoNominaId: origen.pagoNominaId));
        await _cargar();
      case OrigenAutomaticoEgresoTiempoExtra():
        Navigator.of(context).pop();
        context.push('/personal/tiempos-extra/${origen.tiempoExtraId}');
      case OrigenAutomaticoEgresoDeuda():
        Navigator.of(context).pop();
        context.push('/finanzas/deudas-y-credito/${origen.deudaId}');
      case OrigenAutomaticoEgresoTelefonia():
        // Por FK real (`RecargaLineaTelefonica.egresoId`), nunca por
        // concepto, folio textual, importe ni fecha.
        Navigator.of(context).pop();
        context.push('/telefonia/lineas/${origen.lineaTelefonicaId}');
      case OrigenAutomaticoEgresoVehiculo():
        Navigator.of(context).pop();
        // La ruta del expediente es `/vehiculos/flotilla/:id` — la
        // pestaña forma parte de la ruta desde la Etapa 8C.
        context.push('/vehiculos/flotilla/${origen.vehiculoId}');
      case OrigenAutomaticoEgresoDescuentoProgramado():
        Navigator.of(context).pop();
        context.push('/personal/descuentos/${origen.descuentoProgramadoId}');
      case OrigenAutomaticoEgresoServicioEventual():
        // Por FK real (`ServicioEventualCobertura.egresoId` o
        // `ServicioEventualCosto.egresoId`), nunca por concepto.
        Navigator.of(context).pop();
        context.push('/comercial/eventuales/${origen.servicioEventualId}');
    }
  }

  String _eventoLabel(AppLocalizations l10n, String tipoEvento) {
    return switch (TipoEventoEgreso.values.byName(tipoEvento)) {
      TipoEventoEgreso.registrado => l10n.egresoDetalleHistorialEventoRegistrado,
      TipoEventoEgreso.corregido => l10n.egresoDetalleHistorialEventoCorregido,
      TipoEventoEgreso.cancelado => l10n.egresoDetalleHistorialEventoCancelado,
      TipoEventoEgreso.comprobanteAdjuntado => l10n.egresoDetalleHistorialEventoComprobanteAdjuntado,
    };
  }

  Future<void> _adjuntarComprobante() async {
    final l10n = AppLocalizations.of(context)!;
    final seleccion = await FilePicker.platform.pickFiles();
    final archivo = seleccion?.files.singleOrNull;
    if (archivo?.path == null) return;
    if (!mounted) return;

    final resultado = await ref.read(egresosControllerProvider.notifier).adjuntarComprobante(
          egresoId: widget.egresoId,
          sourceFilePath: archivo!.path!,
          originalFileName: archivo.name,
          mimeType: 'application/octet-stream',
        );
    if (!mounted) return;

    switch (resultado) {
      case AdjuntarComprobanteEgresoExitoso():
        await _cargar();
      case AdjuntarComprobanteEgresoNoExiste():
      case AdjuntarComprobanteEgresoErrorInesperado():
        RisegFeedback.showError(context, l10n.egresoDetalleErrorAdjuntar);
    }
  }

  Future<void> _corregir() async {
    final actualizo = await mostrarDialogoCorregirEgreso(context, ref, _egreso!);
    if (actualizo) {
      await _cargar();
      ref.invalidate(egresosControllerProvider);
      ref.invalidate(cuentasFinancierasControllerProvider);
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
    }
  }

  Future<void> _cancelar() async {
    final l10n = AppLocalizations.of(context)!;
    final motivoController = TextEditingController();
    String? errorMotivo;
    final confirmado = await RisegDialog.showForm<bool>(
      context: context,
      title: l10n.cancelarEgresoConfirmacionTitulo,
      confirmLabel: l10n.cancelarEgresoConfirmacionConfirmar,
      cancelLabel: l10n.cancelarEgresoConfirmacionCancelar,
      contentBuilder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.cancelarEgresoConfirmacionMensaje, style: AppTypography.body),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.corregirEgresoCampoMotivo,
              controller: motivoController,
              autofocus: true,
              errorText: errorMotivo,
              onChanged: (_) => setState(() => errorMotivo = null),
            ),
          ],
        ),
      ),
      onConfirm: () async {
        if (motivoController.text.trim().isEmpty) {
          errorMotivo = l10n.cancelarEgresoErrorMotivoRequerido;
          return null;
        }
        return true;
      },
    );
    // El diálogo de confirmación todavía está en su transición de
    // cierre (fade/scale) cuando este `await` regresa — su
    // `RisegTextField` sigue montado y usando `motivoController` en
    // esos últimos frames. Destruirlo aquí mismo, de forma síncrona,
    // producía "A TextEditingController was used after being disposed"
    // (Etapa 15, pantalla roja real reproducida en prueba). Se difiere
    // con `addPostFrameCallback` — mismo patrón ya usado y probado en
    // `riseg_eliminar_fisicamente_dialog.dart:86` — nunca `Future.delayed`.
    if (confirmado != true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => motivoController.dispose());
      return;
    }
    final motivo = motivoController.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) => motivoController.dispose());
    if (!mounted) return;

    setState(() => _procesando = true);
    final resultado =
        await ref.read(egresosControllerProvider.notifier).cancelar(egresoId: widget.egresoId, motivo: motivo);
    if (!mounted) return;
    setState(() => _procesando = false);

    switch (resultado) {
      case CancelarEgresoExitoso():
        RisegFeedback.showSuccess(context, l10n.cancelarEgresoExito);
        await _cargar();
        ref.invalidate(egresosControllerProvider);
        ref.invalidate(cuentasFinancierasControllerProvider);
        ref.invalidate(resumenFinancieroControllerProvider);
        ref.invalidate(planeacionFinancieraControllerProvider);
      case CancelarEgresoNoExiste():
      case CancelarEgresoYaCancelado():
      case CancelarEgresoErrorInesperado():
        RisegFeedback.showError(context, l10n.cancelarEgresoErrorInesperado);
      case CancelarEgresoOrigenAutomatico():
        RisegFeedback.showError(context, l10n.cancelarEgresoErrorOrigenAutomatico);
      case CancelarEgresoMotivoRequerido():
        RisegFeedback.showError(context, l10n.cancelarEgresoErrorMotivoRequerido);
    }
  }

  Future<void> _eliminarFisicamente() async {
    final eliminado = await mostrarDialogoEliminarEgresoFisicamente(context, ref, widget.egresoId);
    if (!eliminado) return;
    ref.invalidate(egresosControllerProvider);
    ref.invalidate(dashboardControllerProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;

    Widget content;
    if (_cargando) {
      content = const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    } else if (_egreso == null) {
      content = Text(l10n.egresosListadoCargaErrorMensaje);
    } else {
      final e = _egreso!;
      final cancelado = EstatusEgreso.values.byName(e.estatus) == EstatusEgreso.cancelado;
      final origen = _origen;
      final automatico = origen != null;

      // Contingencia del Maestro. "Corregir origen financiero" NO es
      // editar el Egreso: el aviso de movimiento automático se
      // conserva, y monto/fecha/concepto siguen corrigiéndose desde su
      // módulo. Por eso sí se ofrece en Egresos automáticos —es justo
      // el caso que lo motiva— pero nunca en uno cancelado (ya no
      // afecta saldos) ni en uno pagado con tarjeta (su salida de
      // efectivo ocurre al pagar la tarjeta).
      final accionesMaestro = <RisegMenuAction>[
        if (esMaestro && !cancelado && e.deudaId == null)
          RisegMenuAction(
            key: const Key('egreso_accion_corregir_origen_financiero'),
            label: l10n.egresoAccionCorregirOrigenFinanciero,
            icon: Icons.account_balance_outlined,
            onTap: () async {
              final corregido = await mostrarDialogoCorregirOrigenFinanciero(
                context,
                ref,
                egreso: e,
                descripcionOrigen: automatico ? _origenLabel(l10n, origen) : l10n.egresoCampoSinAsignar,
              );
              if (corregido) await _cargar();
            },
          ),
        if (esMaestro && !automatico)
          RisegMenuAction(
            key: const Key('egreso_accion_eliminar_fisicamente'),
            label: l10n.eliminacionFisicaAccionMenu,
            icon: Icons.delete_forever_outlined,
            destructive: true,
            onTap: _eliminarFisicamente,
          ),
      ];

      content = SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: CampoConsulta(label: l10n.egresoDetalleCampoFolio, value: e.folioEgreso)),
                RisegStatusBadge(label: egresoEstatusLabel(l10n, e.estatus), tone: egresoEstatusTono(e.estatus)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            CampoConsulta(
              label: l10n.egresoDetalleCampoOrigen,
              value: automatico ? '${_origenLabel(l10n, origen)} · ${_origenFolio(origen)}' : l10n.egresosOrigenManual,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: CampoConsulta(label: l10n.egresoDetalleCampoFecha, value: _formatoFecha.format(e.fecha))),
                Expanded(child: CampoConsulta(label: l10n.egresoDetalleCampoMonto, value: formatoCentavosPago(e.monto))),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            CampoConsulta(label: l10n.egresoDetalleCampoConcepto, value: e.concepto),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: CampoConsulta(label: l10n.egresoDetalleCampoBeneficiario, value: e.beneficiario)),
                Expanded(child: CampoConsulta(label: l10n.egresoDetalleCampoFormaPago, value: formaPagoLabel(l10n, e.formaPago))),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Trazabilidad "gasto → origen financiero" (punto 11 de la
            // Etapa "Origen financiero de Egresos manuales"): siempre
            // por FK real, nunca deducido de `formaPago`. Con TDC, el
            // botón lleva al expediente de esa Deuda, donde el cargo
            // apunta de vuelta a este mismo Egreso.
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: CampoConsulta(
                    label: l10n.egresoCampoOrigenFinanciero,
                    value: _origenFinancieroNombre,
                  ),
                ),
                if (_origenFinancieroDeudaId != null)
                  RisegButton(
                    label: l10n.egresoDetalleBotonVerTarjeta,
                    variant: RisegButtonVariant.ghost,
                    size: RisegButtonSize.compact,
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.push('/finanzas/deudas-y-credito/$_origenFinancieroDeudaId');
                    },
                  ),
              ],
            ),
            if (e.observaciones != null && e.observaciones!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              CampoConsulta(label: l10n.egresoDetalleCampoObservaciones, value: e.observaciones),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.egresoDetalleSeccionComprobante,
                    style: AppTypography.heading3.copyWith(color: colors.textPrimary),
                  ),
                ),
                RisegButton(
                  label: l10n.egresoDetalleBotonAdjuntar,
                  variant: RisegButtonVariant.ghost,
                  onPressed: _adjuntarComprobante,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_comprobantes.isEmpty)
              Text(
                l10n.complementoDetalleArchivosSinArchivos,
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
                        onPressed: () => ref.read(egresosControllerProvider.notifier).abrirArchivo(comprobante.path),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.complementoDetalleSeccionHistorial,
              style: AppTypography.heading3.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_eventos.isEmpty)
              Text(
                l10n.complementoDetalleHistorialSinEventos,
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
                          Expanded(
                            child: Text(
                              _eventoLabel(l10n, evento.tipoEvento),
                              style: AppTypography.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (evento.observacion != null && evento.observacion!.trim().isNotEmpty)
                        Text(evento.observacion!, style: AppTypography.body.copyWith(color: colors.textMuted)),
                    ],
                  ),
                ),
            const SizedBox(height: AppSpacing.lg),
            // Etapa "Ingresos y Egresos" (hallazgo real de auditoría):
            // antes de esta etapa, NINGÚN código verificaba el origen
            // antes de mostrar/permitir Corregir/Cancelar — un Egreso
            // automático (Compra/Nómina/Tiempo Extra/pago de Deuda)
            // podía corregirse o cancelarse aquí directamente,
            // desincronizándolo en silencio de su fuente de verdad. La
            // defensa real vive en el caso de uso
            // (`CorregirEgresoUseCase`/`CancelarEgresoUseCase`, ver
            // `ObtenerOrigenAutomaticoEgresoUseCase`) — ocultar el
            // botón aquí es solo UX, nunca la única protección.
            if (automatico)
              Text(
                l10n.egresoDetalleAvisoAutomatico(_origenLabel(l10n, origen)),
                style: AppTypography.caption.copyWith(color: colors.textMuted),
              ),
            if (!cancelado || accionesMaestro.isNotEmpty || automatico)
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (automatico)
                    RisegButton(
                      label: l10n.egresoDetalleBotonVerOrigen,
                      variant: RisegButtonVariant.secondary,
                      onPressed: _verOrigen,
                    ),
                  if (!cancelado && !automatico) ...[
                    RisegButton(
                      label: l10n.egresoDetalleBotonCorregir,
                      variant: RisegButtonVariant.secondary,
                      onPressed: ref.watch(permissionServiceProvider).hasCode('egresos.corregir') ? _corregir : null,
                    ),
                    RisegButton(
                      label: l10n.egresoDetalleBotonCancelar,
                      variant: RisegButtonVariant.danger,
                      loading: _procesando,
                      onPressed: ref.watch(permissionServiceProvider).hasCode('egresos.cancelar') ? _cancelar : null,
                    ),
                  ],
                  // Extraordinaria (Maestro) — nunca depende del
                  // estatus: un Egreso ya cancelado (captura de prueba)
                  // sigue siendo elegible para limpiar por completo. Sí
                  // depende del origen: la eliminación física de un
                  // Egreso automático se rechaza con el folio real
                  // (`obtenerResumenEliminacionFisica`) — se oculta
                  // aquí para no ofrecer una acción que sabemos de
                  // antemano que será rechazada.
                  // El menú se arma primero y sólo se dibuja si quedó
                  // con algo dentro.
                  if (accionesMaestro.isNotEmpty)
                    RisegActionsMenu(
                      menuKey: const Key('egreso_menu_acciones'),
                      actions: accionesMaestro,
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
                    Expanded(
                      child: Text(
                        l10n.egresoDetalleDialogoTitulo,
                        style: AppTypography.heading2.copyWith(color: colors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
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
