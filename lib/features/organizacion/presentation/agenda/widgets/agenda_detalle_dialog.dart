import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_por_cobrar/cuentas_por_cobrar_controller.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_etapa_table.dart' show TipoEventoCobro;
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/documento_por_emitir_detalle.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/generar_recibo_pago_pdf_usecase.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/resumen_iva_documento_por_emitir.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../../organizacion_providers.dart';
import '../agenda_controller.dart';
import '../agenda_list_screen.dart' show formatoCentavosAgenda;
import 'agenda_adjuntos_section.dart';
import 'agenda_ajuste_manual_dialog.dart';
import 'agenda_corregir_datos_emision_dialog.dart';
import 'agenda_registrar_emision_dialog.dart';
import 'agenda_registrar_envio_dialog.dart';
import 'agenda_versiones_archivadas_dialog.dart';
import 'eliminar_documento_por_emitir_fisicamente_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Nombre visible de un hito ya generado (Etapa 15) — snapshot: de
/// sistema vía l10n (nunca cambia retroactivamente lo que ya se
/// generó), o el texto libre capturado si era una etapa personalizada.
String _hitoLabel(AppLocalizations l10n, DocumentoPorEmitirHitoData hito) {
  final tipoSistema = hito.tipoSistema;
  if (tipoSistema == null) return hito.nombre ?? '';
  return switch (TipoEventoCobro.values.byName(tipoSistema)) {
    TipoEventoCobro.emision => l10n.servicioCobroEventoEmision,
    TipoEventoCobro.procesamiento => l10n.servicioCobroEventoProcesamiento,
    TipoEventoCobro.pagoEsperado => l10n.servicioCobroEventoPagoEsperado,
    TipoEventoCobro.complementoPago => l10n.servicioCobroEventoComplementoPago,
  };
}

/// Detalle de un `DocumentoPorEmitir` (Etapa 4I.1) — expediente completo
/// de solo consulta salvo la máquina de estados de 4 estados. El ajuste
/// manual se muestra de solo lectura: su interfaz de captura completa
/// se difiere a la Etapa 4I.2 (autorización explícita de Marlon).
class AgendaDetalleDialog extends ConsumerStatefulWidget {
  const AgendaDetalleDialog({required this.documentoPorEmitirId, super.key});

  final String documentoPorEmitirId;

  @override
  ConsumerState<AgendaDetalleDialog> createState() => _AgendaDetalleDialogState();
}

class _AgendaDetalleDialogState extends ConsumerState<AgendaDetalleDialog> {
  DocumentoPorEmitirDetalle? _detalle;
  bool _cargando = true;
  bool _procesando = false;
  bool _generandoPdf = false;
  final Map<String, String> _nombresServicio = {};
  Map<String, String> _usuariosPorId = const {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final detalle = await ref.read(agendaControllerProvider.notifier).obtenerDetalle(widget.documentoPorEmitirId);
    if (!mounted) return;

    if (detalle != null) {
      for (final servicioId in detalle.servicioIds) {
        if (_nombresServicio.containsKey(servicioId)) continue;
        final servicio = await ref.read(servicioRepositoryProvider).obtenerPorId(servicioId);
        if (servicio != null) _nombresServicio[servicioId] = '${servicio.codigo} — ${servicio.nombre}';
      }
    }
    final usuarios = await ref.read(usuarioRepositoryProvider).listar();
    final usuariosPorId = {for (final u in usuarios) u.id: u.nombre};

    if (!mounted) return;
    setState(() {
      _detalle = detalle;
      _usuariosPorId = usuariosPorId;
      _cargando = false;
    });
  }

  String _tipoDocumentoLabel(AppLocalizations l10n, String valor) {
    return switch (TipoDocumentoCobro.values.byName(valor)) {
      TipoDocumentoCobro.cfdi => l10n.servicioCobroTipoDocumentoCfdi,
      TipoDocumentoCobro.reciboDePago => l10n.servicioCobroTipoDocumentoReciboDePago,
    };
  }

  String _agrupacionLabel(AppLocalizations l10n, String valor) {
    return switch (AgrupacionCobro.values.byName(valor)) {
      AgrupacionCobro.porServicio => l10n.servicioCobroAgrupacionPorServicio,
      AgrupacionCobro.porEntidadFiscal => l10n.servicioCobroAgrupacionPorEntidadFiscal,
      AgrupacionCobro.porCliente => l10n.servicioCobroAgrupacionPorCliente,
      AgrupacionCobro.manual => l10n.servicioCobroAgrupacionManual,
    };
  }

  String _metodoLabel(AppLocalizations l10n, String valor) {
    return switch (MetodoPagoCobro.values.byName(valor)) {
      MetodoPagoCobro.pue => l10n.servicioCobroMetodoPue,
      MetodoPagoCobro.ppd => l10n.servicioCobroMetodoPpd,
      MetodoPagoCobro.noAplica => l10n.servicioCobroMetodoNoAplica,
    };
  }

  String _tratamientoIvaLabel(AppLocalizations l10n, String valor) {
    return switch (TratamientoIva.values.byName(valor)) {
      TratamientoIva.masIva => l10n.servicioComercialTratamientoIvaMasIva,
      TratamientoIva.ivaIncluido => l10n.servicioComercialTratamientoIvaIvaIncluido,
      TratamientoIva.noAplica => l10n.servicioComercialTratamientoIvaNoAplica,
    };
  }

  String _ajusteLabel(AppLocalizations l10n, int? ajuste) {
    if (ajuste == null || ajuste == 0) return l10n.agendaAjusteEtiquetaSinAjuste;
    final monto = formatoCentavosAgenda(ajuste.abs());
    return ajuste < 0 ? l10n.agendaAjusteEtiquetaDescuento(monto) : l10n.agendaAjusteEtiquetaIncremento(monto);
  }

  String _eventoLabel(AppLocalizations l10n, String tipoEvento) {
    return switch (TipoEventoDocumentoPorEmitir.values.byName(tipoEvento)) {
      TipoEventoDocumentoPorEmitir.creadoAutomatico => l10n.agendaDetalleHistorialEventoCreadoAutomatico,
      TipoEventoDocumentoPorEmitir.creadoManual => l10n.agendaDetalleHistorialEventoCreadoManual,
      TipoEventoDocumentoPorEmitir.marcadoEnPreparacion => l10n.agendaDetalleHistorialEventoMarcadoEnPreparacion,
      TipoEventoDocumentoPorEmitir.ajusteRegistrado => l10n.agendaDetalleHistorialEventoAjusteRegistrado,
      TipoEventoDocumentoPorEmitir.emisionRegistrada => l10n.agendaDetalleHistorialEventoEmisionRegistrada,
      TipoEventoDocumentoPorEmitir.correccionDatosEmision => l10n.agendaDetalleHistorialEventoCorreccionDatosEmision,
      TipoEventoDocumentoPorEmitir.archivoAdjuntado => l10n.agendaDetalleHistorialEventoArchivoAdjuntado,
      TipoEventoDocumentoPorEmitir.archivoReemplazado => l10n.agendaDetalleHistorialEventoArchivoReemplazado,
      TipoEventoDocumentoPorEmitir.envioRegistrado => l10n.agendaDetalleHistorialEventoEnvioRegistrado,
      TipoEventoDocumentoPorEmitir.correccionEnviadoAEmitido => l10n.agendaDetalleHistorialEventoCorreccionEnviadoAEmitido,
      TipoEventoDocumentoPorEmitir.procesadoAceptado => l10n.agendaDetalleHistorialEventoProcesadoAceptado,
      TipoEventoDocumentoPorEmitir.cancelado => l10n.agendaDetalleHistorialEventoCancelado,
      TipoEventoDocumentoPorEmitir.marcadoNoRequerido => l10n.agendaDetalleHistorialEventoMarcadoNoRequerido,
      TipoEventoDocumentoPorEmitir.edicionObservaciones => l10n.agendaDetalleHistorialEventoEdicionObservaciones,
    };
  }

  /// Traduce el JSON de `datosRelevantes` de un evento a líneas
  /// legibles — nunca se muestra el JSON crudo en pantalla. Claves no
  /// reconocidas se ignoran silenciosamente (el JSON es un log
  /// heterogéneo por diseño, distintos eventos traen distintas claves).
  List<String> _datosRelevantesLegibles(AppLocalizations l10n, String? datosJson) {
    if (datosJson == null) return const [];
    final Map<String, dynamic> datos;
    try {
      datos = jsonDecode(datosJson) as Map<String, dynamic>;
    } catch (_) {
      return const [];
    }

    final lineas = <String>[];
    void agregar(String etiqueta, Object? valor) {
      if (valor == null) return;
      lineas.add('$etiqueta: $valor');
    }

    agregar(l10n.agendaDetalleHistorialDatoCategoria, datos['categoria']);
    agregar(l10n.agendaDetalleHistorialDatoArchivoAnterior, datos['archivoAnterior']);
    agregar(l10n.agendaDetalleHistorialDatoArchivoNuevo, datos['archivoNuevo']);
    agregar(l10n.agendaDetalleHistorialDatoFolioAnterior, datos['folioDocumentoAnterior']);
    final ajusteAnterior = datos['ajusteAnterior'];
    if (ajusteAnterior is int) agregar(l10n.agendaDetalleHistorialDatoAjusteAnterior, formatoCentavosAgenda(ajusteAnterior));
    final ajusteNuevo = datos['ajusteNuevo'];
    if (ajusteNuevo is int) agregar(l10n.agendaDetalleHistorialDatoAjusteNuevo, formatoCentavosAgenda(ajusteNuevo));

    return lineas;
  }

  String _resumenIvaLabel(AppLocalizations l10n, ResumenIvaDocumento resumen) {
    return switch (resumen) {
      ResumenIvaDocumento.masIva => l10n.agendaDetalleResumenIvaMasIva,
      ResumenIvaDocumento.ivaIncluido => l10n.agendaDetalleResumenIvaIvaIncluido,
      ResumenIvaDocumento.noAplica => l10n.agendaDetalleResumenIvaNoAplica,
      ResumenIvaDocumento.mixto => l10n.agendaDetalleResumenIvaMixto,
    };
  }

  String _estatusLabel(AppLocalizations l10n, String valor) {
    return switch (EstatusDocumentoPorEmitir.values.byName(valor)) {
      EstatusDocumentoPorEmitir.pendiente => l10n.agendaEstatusPendiente,
      EstatusDocumentoPorEmitir.enPreparacion => l10n.agendaEstatusEnPreparacion,
      EstatusDocumentoPorEmitir.cancelado => l10n.agendaEstatusCancelado,
      EstatusDocumentoPorEmitir.noRequerido => l10n.agendaEstatusNoRequerido,
      EstatusDocumentoPorEmitir.emitido => l10n.agendaEstatusEmitido,
      EstatusDocumentoPorEmitir.enviado => l10n.agendaEstatusEnviado,
      EstatusDocumentoPorEmitir.procesadoAceptado => l10n.agendaEstatusProcesadoAceptado,
    };
  }

  RisegStatusTone _estatusTono(EstatusDocumentoPorEmitir estatus) {
    return switch (estatus) {
      EstatusDocumentoPorEmitir.pendiente => RisegStatusTone.info,
      EstatusDocumentoPorEmitir.enPreparacion => RisegStatusTone.warning,
      EstatusDocumentoPorEmitir.cancelado => RisegStatusTone.neutral,
      EstatusDocumentoPorEmitir.noRequerido => RisegStatusTone.neutral,
      EstatusDocumentoPorEmitir.emitido => RisegStatusTone.info,
      EstatusDocumentoPorEmitir.enviado => RisegStatusTone.info,
      EstatusDocumentoPorEmitir.procesadoAceptado => RisegStatusTone.success,
    };
  }

  Future<String?> _pedirMotivo(AppLocalizations l10n) async {
    final controller = TextEditingController();
    final motivo = await RisegDialog.showForm<String>(
      context: context,
      title: l10n.agendaDetalleMotivoDialogoTitulo,
      confirmLabel: l10n.agendaDetalleMotivoBotonConfirmar,
      cancelLabel: l10n.agendaDetalleMotivoBotonCancelar,
      contentBuilder: (_) => RisegTextField(
        label: l10n.agendaDetalleMotivoCampo,
        controller: controller,
        autofocus: true,
      ),
      onConfirm: () async => controller.text,
    );
    controller.dispose();
    return motivo;
  }

  Future<void> _cambiarEstatus(EstatusDocumentoPorEmitir nuevo, {bool requiereMotivo = false}) async {
    final l10n = AppLocalizations.of(context)!;
    String? motivo;
    if (requiereMotivo) {
      motivo = await _pedirMotivo(l10n);
      if (motivo == null || motivo.trim().isEmpty) return;
    }
    if (!mounted) return;

    setState(() => _procesando = true);
    final resultado = await ref.read(agendaControllerProvider.notifier).cambiarEstatus(
          documentoPorEmitirId: widget.documentoPorEmitirId,
          nuevo: nuevo,
          motivo: motivo,
        );
    if (!mounted) return;
    setState(() => _procesando = false);

    switch (resultado) {
      case CambiarEstatusDocumentoPorEmitirExitoso():
        RisegFeedback.showSuccess(context, l10n.agendaDetalleCambiarEstatusExito);
        await _cargar();
      case CambiarEstatusDocumentoPorEmitirMotivoRequerido():
        RisegFeedback.showError(context, l10n.agendaDetalleCambiarEstatusErrorMotivoRequerido);
      case CambiarEstatusDocumentoPorEmitirTransicionInvalida():
      case CambiarEstatusDocumentoPorEmitirNoExiste():
      case CambiarEstatusDocumentoPorEmitirErrorInesperado():
      case null:
        RisegFeedback.showError(context, l10n.agendaDetalleCambiarEstatusErrorInesperado);
    }
  }

  Future<void> _registrarEmision(DocumentoPorEmitirData documento) async {
    final actualizo = await mostrarDialogoRegistrarEmision(context, ref, documento, _detalle!.resumenIva);
    if (actualizo) await _cargar();
  }

  Future<void> _corregirDatosEmision(DocumentoPorEmitirData documento) async {
    final actualizo = await mostrarDialogoCorregirDatosEmision(context, ref, documento);
    if (actualizo) await _cargar();
  }

  Future<void> _registrarEnvio(String documentoPorEmitirId) async {
    final actualizo = await mostrarDialogoRegistrarEnvio(context, ref, documentoPorEmitirId);
    if (actualizo) await _cargar();
  }

  Future<void> _ajusteManual(DocumentoPorEmitirData documento) async {
    final actualizo = await mostrarDialogoAjusteManual(context, ref, documento);
    if (actualizo) await _cargar();
  }

  Future<void> _verVersionesArchivadas() async {
    await mostrarDialogoVersionesArchivadas(context, ref, widget.documentoPorEmitirId);
  }

  Future<void> _generarReciboPdf() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _generandoPdf = true);

    // Fallback si Empresa no tiene logotipo propio configurado (hoy
    // siempre el caso — no existe todavía esa pantalla): el mismo
    // asset oficial que ya usa el resto de la app, nunca uno distinto
    // ni duplicado (Etapa 15). El use case es dominio puro y no conoce
    // `rootBundle`, así que se resuelve aquí, en la UI.
    Uint8List? logoFallbackBytes;
    try {
      final datosLogo = await rootBundle.load('assets/images/logo.png');
      logoFallbackBytes = datosLogo.buffer.asUint8List();
    } catch (_) {
      // Sin logotipo de respaldo disponible — el PDF se genera sin
      // logo, nunca se bloquea la generación por esto.
    }

    final resultado = await ref.read(agendaControllerProvider.notifier).generarReciboPagoPdf(
          widget.documentoPorEmitirId,
          logoFallbackBytes: logoFallbackBytes,
        );
    if (!mounted) return;
    setState(() => _generandoPdf = false);

    switch (resultado) {
      case GenerarReciboPagoPdfExitoso():
        RisegFeedback.showSuccess(context, l10n.agendaDetalleReciboPdfExito);
      case GenerarReciboPagoPdfNoExiste():
      case GenerarReciboPagoPdfTipoDocumentoInvalido():
      case GenerarReciboPagoPdfErrorInesperado():
        RisegFeedback.showError(context, l10n.agendaDetalleReciboPdfError);
    }
  }

  Future<void> _eliminarFisicamente() async {
    final eliminado = await mostrarDialogoEliminarDocumentoPorEmitirFisicamente(context, ref, widget.documentoPorEmitirId);
    if (!eliminado) return;
    // A diferencia del resto de las mutaciones (que pasan por
    // `AgendaController` y recargan su propia lista internamente), la
    // eliminación física la ejecuta un provider aparte — sin esta
    // invalidación explícita, la Agenda detrás de este diálogo sigue
    // mostrando el documento ya eliminado hasta que su `autoDispose` se
    // dispare por otro motivo (Etapa 15, hallazgo real).
    ref.invalidate(agendaControllerProvider);
    // El repositorio borra físicamente la `CuentaPorCobrar` asociada
    // junto con el Documento (mismo agregado) — sin esto, el listado de
    // Cuentas por cobrar seguía mostrando una cuenta ya eliminada.
    ref.invalidate(cuentasPorCobrarControllerProvider);
    if (mounted) Navigator.of(context).pop();
  }

  /// `Emitido → Procesado/Aceptado` directo omite el paso de envío —
  /// se confirma explícitamente antes de aplicarlo (Resolución 5 de
  /// Marlon: la interfaz debe confirmar claramente cuando se omita
  /// Enviado).
  Future<void> _marcarProcesadoAceptadoOmitiendoEnvio() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: l10n.agendaDetalleOmitirEnvioConfirmacionTitulo,
      message: l10n.agendaDetalleOmitirEnvioConfirmacionMensaje,
      confirmLabel: l10n.agendaDetalleOmitirEnvioConfirmacionConfirmar,
      cancelLabel: l10n.agendaDetalleOmitirEnvioConfirmacionCancelar,
    );
    if (confirmado != true) return;
    await _cambiarEstatus(EstatusDocumentoPorEmitir.procesadoAceptado);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    Widget content;
    if (_cargando) {
      content = const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    } else if (_detalle == null) {
      content = Text(l10n.agendaListadoCargaErrorMensaje);
    } else {
      final d = _detalle!.documento;
      final estatusActual = EstatusDocumentoPorEmitir.values.byName(d.estatus);
      final tipoDocumento = TipoDocumentoCobro.values.byName(d.tipoDocumento);
      final esCfdi = tipoDocumento == TipoDocumentoCobro.cfdi;
      final esReciboDePago = tipoDocumento == TipoDocumentoCobro.reciboDePago;
      final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;

      content = SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                CampoConsulta(label: l10n.agendaDetalleCampoCodigo, value: d.codigo),
                RisegStatusBadge(
                  label: _estatusLabel(l10n, d.estatus),
                  tone: _estatusTono(estatusActual),
                ),
                if (esMaestro)
                  RisegActionsMenu(
                    menuKey: const Key('agenda_detalle_menu_acciones'),
                    actions: [
                      // El estatus ya no gatea esta acción (Etapa 15,
                      // ampliación explícita de Marlon) — el único
                      // bloqueo real (dinero real aplicado) se revisa
                      // dentro del propio diálogo, con un mensaje
                      // específico, antes de pedir el motivo.
                      RisegMenuAction(
                        key: const Key('agenda_detalle_accion_eliminar_fisicamente'),
                        label: l10n.eliminacionFisicaAccionMenu,
                        icon: Icons.delete_forever_outlined,
                        destructive: true,
                        onTap: _eliminarFisicamente,
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: CampoConsulta(label: l10n.agendaDetalleCampoTipoDocumento, value: _tipoDocumentoLabel(l10n, d.tipoDocumento))),
                Expanded(child: CampoConsulta(label: l10n.agendaDetalleCampoAgrupacion, value: _agrupacionLabel(l10n, d.agrupacion))),
                Expanded(child: CampoConsulta(label: l10n.agendaDetalleCampoMetodo, value: _metodoLabel(l10n, d.metodo))),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            CampoConsulta(
              label: l10n.agendaDetalleCampoPeriodo,
              value: '${_formatoFecha.format(d.periodoInicio)} - ${_formatoFecha.format(d.periodoFin)}',
            ),
            const SizedBox(height: AppSpacing.sm),
            // Etapa 15: solo los hitos realmente configurados y activos
            // para este documento — nunca los 3 slots fijos de antes.
            // `_detalle!.hitos` es el snapshot tomado al generar (nunca
            // se recalcula), ya en orden.
            if (_detalle!.hitos.isEmpty)
              CampoConsulta(
                label: l10n.agendaDetalleCampoFechaEmision,
                value: d.fechaEmisionProgramada == null ? l10n.agendaFechaSinCalcular : _formatoFecha.format(d.fechaEmisionProgramada!),
              )
            else
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final hito in _detalle!.hitos)
                    SizedBox(
                      width: 160,
                      child: CampoConsulta(
                        label: _hitoLabel(l10n, hito),
                        value: _formatoFecha.format(hito.fechaProgramada),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.agendaDetalleSeccionComparacionImportes, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            if (_detalle!.resumenIva == ResumenIvaDocumento.masIva && _detalle!.totalesEsperados != null)
              Row(
                children: [
                  Expanded(
                    child: CampoConsulta(
                      label: l10n.agendaDetalleComparacionImporteBaseEsperado,
                      value: formatoCentavosAgenda(_detalle!.totalesEsperados!.base),
                    ),
                  ),
                  Expanded(
                    child: CampoConsulta(
                      label: l10n.agendaDetalleComparacionIvaEsperado,
                      value: formatoCentavosAgenda(_detalle!.totalesEsperados!.ivaEsperado),
                    ),
                  ),
                  Expanded(
                    child: CampoConsulta(
                      label: l10n.agendaDetalleComparacionTotalEsperado,
                      value: formatoCentavosAgenda(_detalle!.totalesEsperados!.totalEsperado),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(child: CampoConsulta(label: l10n.agendaDetalleComparacionImporteCalculado, value: formatoCentavosAgenda(d.importeBaseEsperado))),
                  Expanded(child: CampoConsulta(label: l10n.agendaDetalleComparacionAjuste, value: _ajusteLabel(l10n, d.ajusteManual))),
                  Expanded(child: CampoConsulta(label: l10n.agendaDetalleComparacionImporteFinalEsperado, value: formatoCentavosAgenda(d.importeFinalEsperado))),
                ],
              ),
            if (d.importeEmitido != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(child: CampoConsulta(label: l10n.agendaDetalleComparacionImporteEmitido, value: formatoCentavosAgenda(d.importeEmitido!))),
                  Expanded(child: CampoConsulta(label: l10n.agendaDetalleComparacionDiferencia, value: formatoCentavosAgenda(_detalle!.diferenciaEmision!))),
                  const Expanded(child: SizedBox.shrink()),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            CampoConsulta(label: l10n.agendaDetalleCampoResumenIva, value: _resumenIvaLabel(l10n, _detalle!.resumenIva)),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.agendaDetalleCampoServicios, style: AppTypography.label.copyWith(color: colors.textMuted)),
            const SizedBox(height: AppSpacing.xxs),
            for (final servicioId in _detalle!.servicioIds)
              Text(_nombresServicio[servicioId] ?? servicioId, style: AppTypography.body),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.agendaDetalleSeccionLineas, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            RisegTableBase<DocumentoPorEmitirLineaData>(
              rows: _detalle!.lineas,
              columns: [
                RisegColumn(label: l10n.agendaDetalleLineaColumnaPuesto, cellBuilder: (l) => Text(l.puestoNombre)),
                RisegColumn(
                  label: l10n.agendaDetalleLineaColumnaModalidad,
                  cellBuilder: (l) => Text(l.modalidadTurnoNombre),
                ),
                RisegColumn(
                  label: l10n.agendaDetalleLineaColumnaCantidad,
                  width: 70,
                  alignment: TextAlign.right,
                  cellBuilder: (l) => Text('${l.cantidadElementos}'),
                ),
                RisegColumn(
                  label: l10n.agendaDetalleLineaColumnaPrecio,
                  width: 100,
                  alignment: TextAlign.right,
                  cellBuilder: (l) => Text(formatoCentavosAgenda(l.precioUnitario)),
                ),
                RisegColumn(
                  label: l10n.agendaDetalleLineaColumnaIva,
                  width: 100,
                  cellBuilder: (l) => Text(_tratamientoIvaLabel(l10n, l.tratamientoIva)),
                ),
                RisegColumn(
                  label: l10n.agendaDetalleLineaColumnaDias,
                  width: 60,
                  alignment: TextAlign.right,
                  cellBuilder: (l) => Text('${l.diasAplicables}'),
                ),
                RisegColumn(
                  label: l10n.agendaDetalleLineaColumnaSubtotal,
                  width: 100,
                  alignment: TextAlign.right,
                  cellBuilder: (l) => Text(formatoCentavosAgenda(l.subtotalProporcional)),
                ),
              ],
            ),
            if (_detalle!.correos.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              CampoConsulta(label: l10n.agendaDetalleCampoCorreos, value: _detalle!.correos.join(', ')),
            ],
            if (d.observaciones != null && d.observaciones!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              CampoConsulta(label: l10n.agendaDetalleCampoObservaciones, value: d.observaciones),
            ],
            if (estatusActual == EstatusDocumentoPorEmitir.emitido ||
                estatusActual == EstatusDocumentoPorEmitir.enviado ||
                estatusActual == EstatusDocumentoPorEmitir.procesadoAceptado) ...[
              const SizedBox(height: AppSpacing.md),
              Text(l10n.agendaDetalleSeccionDatosEmision, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(child: CampoConsulta(label: l10n.agendaDetalleCampoFolioDocumento, value: d.folioDocumento)),
                  if (esCfdi) Expanded(child: CampoConsulta(label: l10n.agendaDetalleCampoUuid, value: d.uuid)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              CampoConsulta(
                label: l10n.agendaDetalleCampoFechaEmisionReal,
                value: d.fechaEmisionReal == null ? null : _formatoFecha.format(d.fechaEmisionReal!),
              ),
              if (d.observacionesEmision != null && d.observacionesEmision!.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                CampoConsulta(label: l10n.agendaDetalleCampoObservacionesEmision, value: d.observacionesEmision),
              ],
            ],
            if (estatusActual == EstatusDocumentoPorEmitir.enviado ||
                estatusActual == EstatusDocumentoPorEmitir.procesadoAceptado) ...[
              const SizedBox(height: AppSpacing.md),
              Text(l10n.agendaDetalleSeccionDatosEnvio, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
              const SizedBox(height: AppSpacing.xs),
              CampoConsulta(
                label: l10n.agendaDetalleCampoFechaEnvio,
                value: d.fechaEnvio == null ? null : _formatoFecha.format(d.fechaEnvio!),
              ),
              const SizedBox(height: AppSpacing.sm),
              CampoConsulta(
                label: l10n.agendaDetalleCampoCorreosUtilizados,
                value: _detalle!.correosEnvio.isEmpty ? null : _detalle!.correosEnvio.join(', '),
              ),
              if (d.observacionesEnvio != null && d.observacionesEnvio!.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                CampoConsulta(label: l10n.agendaDetalleCampoObservacionesEnvio, value: d.observacionesEnvio),
              ],
            ],
            const SizedBox(height: AppSpacing.md),
            AgendaAdjuntosSection(documento: d),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                Text(
                  l10n.agendaDetalleSeccionHistorial,
                  style: AppTypography.heading3.copyWith(color: colors.textPrimary),
                ),
                RisegButton(
                  label: l10n.agendaDetalleHistorialBotonVersionesArchivadas,
                  variant: RisegButtonVariant.ghost,
                  onPressed: _verVersionesArchivadas,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_detalle!.eventos.isEmpty)
              Text(l10n.agendaDetalleHistorialSinEventos, style: AppTypography.body.copyWith(color: colors.textMuted))
            else
              for (final evento in _detalle!.eventos)
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
                      // `actorUsuarioId` se omite por completo mientras sea
                      // `null` (Resolución de Marlon: ausencia limpia,
                      // nunca un placeholder) — solo aparece cuando exista.
                      if (evento.actorUsuarioId != null)
                        Text(
                          '${l10n.agendaDetalleHistorialCampoActor}: '
                          '${_usuariosPorId[evento.actorUsuarioId] ?? evento.actorUsuarioId}',
                          style: AppTypography.caption.copyWith(color: colors.textMuted),
                        ),
                      if (evento.observacion != null && evento.observacion!.trim().isNotEmpty)
                        Text(evento.observacion!, style: AppTypography.body.copyWith(color: colors.textMuted)),
                      for (final linea in _datosRelevantesLegibles(l10n, evento.datosRelevantes))
                        Text(linea, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                    ],
                  ),
                ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                if (esReciboDePago)
                  RisegButton(
                    key: const Key('agenda_detalle_boton_generar_recibo_pdf'),
                    label: l10n.agendaDetalleBotonGenerarReciboPdf,
                    variant: RisegButtonVariant.secondary,
                    loading: _generandoPdf,
                    onPressed: _generarReciboPdf,
                  ),
                if (estatusActual == EstatusDocumentoPorEmitir.pendiente)
                  RisegButton(
                    label: l10n.agendaDetalleBotonMarcarEnPreparacion,
                    variant: RisegButtonVariant.secondary,
                    loading: _procesando,
                    onPressed: () => _cambiarEstatus(EstatusDocumentoPorEmitir.enPreparacion),
                  ),
                if (estatusActual == EstatusDocumentoPorEmitir.pendiente ||
                    estatusActual == EstatusDocumentoPorEmitir.enPreparacion) ...[
                  RisegButton(
                    label: l10n.agendaDetalleBotonRegistrarEmision,
                    variant: RisegButtonVariant.primary,
                    onPressed: () => _registrarEmision(d),
                  ),
                  RisegButton(
                    label: l10n.agendaDetalleBotonCancelar,
                    variant: RisegButtonVariant.danger,
                    loading: _procesando,
                    onPressed: () => _cambiarEstatus(EstatusDocumentoPorEmitir.cancelado, requiereMotivo: true),
                  ),
                  RisegButton(
                    label: l10n.agendaDetalleBotonMarcarNoRequerido,
                    variant: RisegButtonVariant.ghost,
                    loading: _procesando,
                    onPressed: () => _cambiarEstatus(EstatusDocumentoPorEmitir.noRequerido, requiereMotivo: true),
                  ),
                ],
                if (estatusActual == EstatusDocumentoPorEmitir.emitido) ...[
                  RisegButton(
                    label: l10n.agendaDetalleBotonRegistrarEnvio,
                    variant: RisegButtonVariant.primary,
                    onPressed: () => _registrarEnvio(d.id),
                  ),
                  RisegButton(
                    label: l10n.agendaDetalleBotonMarcarProcesadoAceptado,
                    variant: RisegButtonVariant.secondary,
                    loading: _procesando,
                    onPressed: _marcarProcesadoAceptadoOmitiendoEnvio,
                  ),
                ],
                if (estatusActual == EstatusDocumentoPorEmitir.enviado) ...[
                  RisegButton(
                    label: l10n.agendaDetalleBotonMarcarProcesadoAceptado,
                    variant: RisegButtonVariant.primary,
                    loading: _procesando,
                    onPressed: () => _cambiarEstatus(EstatusDocumentoPorEmitir.procesadoAceptado),
                  ),
                  RisegButton(
                    label: l10n.agendaDetalleBotonCorregirEnviadoAEmitido,
                    variant: RisegButtonVariant.ghost,
                    loading: _procesando,
                    onPressed: () => _cambiarEstatus(EstatusDocumentoPorEmitir.emitido, requiereMotivo: true),
                  ),
                ],
                if (estatusActual == EstatusDocumentoPorEmitir.emitido ||
                    estatusActual == EstatusDocumentoPorEmitir.enviado)
                  RisegButton(
                    label: l10n.agendaDetalleBotonCorregirDatosEmision,
                    variant: RisegButtonVariant.ghost,
                    onPressed: () => _corregirDatosEmision(d),
                  ),
                if (estatusActual != EstatusDocumentoPorEmitir.cancelado &&
                    estatusActual != EstatusDocumentoPorEmitir.noRequerido)
                  RisegButton(
                    label: l10n.agendaDetalleBotonAjusteManual,
                    variant: RisegButtonVariant.ghost,
                    onPressed: () => _ajusteManual(d),
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
                        l10n.agendaDetalleDialogoTitulo,
                        style: AppTypography.heading2.copyWith(color: colors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
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
