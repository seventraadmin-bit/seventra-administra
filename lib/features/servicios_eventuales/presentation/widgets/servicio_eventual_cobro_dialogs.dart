import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_aplicado_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart'
    show formaPagoLabel, formatoCentavosPago;
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart'
    show MetodoPagoCobro;
import 'package:riseg_one/features/organizacion/domain/repositories/entidad_fiscal_repository.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';

import '../../domain/usecases/corregir_documento_fiscal_eventual_usecase.dart';
import '../../domain/usecases/registrar_cobro_servicio_eventual_usecase.dart';
import '../../domain/usecases/registrar_documento_fiscal_eventual_usecase.dart';
import '../servicios_eventuales_controller.dart';
import 'servicio_eventual_dialogs.dart' show centavosDesdeTexto;

// ==================================================================
// Cobro posterior
// ==================================================================

/// Cobra un eventual ya vendido. No implementa cobranza: delega en el
/// flujo real de Pagos, que ya sabe de saldos, parcialidades y
/// sobrepagos.
///
/// Una GlobalKey por formulario: es como el pie del diálogo alcanza el
/// `guardar()` del State sin que el formulario dibuje su propio botón.
final _claveCobro = GlobalKey<_FormularioCobroState>();
final _claveDocumento = GlobalKey<_FormularioDocumentoFiscalState>();

Future<bool> mostrarDialogoCobrarEventual(
  BuildContext context,
  WidgetRef ref, {
  required String servicioEventualId,
  required int saldoPendiente,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final cuentas = await ref.read(cuentaFinancieraRepositoryProvider).listar(soloActivas: true);
  if (!context.mounted) return false;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.servicioEventualDialogoCobroTitulo,
    confirmLabel: l10n.servicioEventualBotonRegistrarCobroAccion,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (_) => _FormularioCobro(
      key: _claveCobro,
      servicioEventualId: servicioEventualId,
      saldoPendiente: saldoPendiente,
      cuentas: cuentas,
    ),
    onConfirm: () async => _claveCobro.currentState?.guardar(),
  );
  return resultado ?? false;
}

class _FormularioCobro extends ConsumerStatefulWidget {
  const _FormularioCobro({
    super.key,
    required this.servicioEventualId,
    required this.saldoPendiente,
    required this.cuentas,
  });

  final String servicioEventualId;
  final int saldoPendiente;
  final List<CuentaFinancieraData> cuentas;

  @override
  ConsumerState<_FormularioCobro> createState() => _FormularioCobroState();
}

class _FormularioCobroState extends ConsumerState<_FormularioCobro> {
  late final TextEditingController _montoCtrl;
  final _referenciaCtrl = TextEditingController();

  var _formaPago = FormaPago.transferencia.name;
  String? _cuentaId;
  DateTime _fecha = DateTime.now();
  String? _error;

  @override
  void initState() {
    super.initState();
    // Se propone el saldo completo: cobrar menos es válido (pago
    // parcial), pero el caso normal es liquidar.
    _montoCtrl = TextEditingController(text: (widget.saldoPendiente / 100).toStringAsFixed(2));
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    _referenciaCtrl.dispose();
    super.dispose();
  }

  /// `true` si guardó (el marco cierra), `null` si hay que
  /// corregir algo (el marco se queda abierto con el error a la vista).
  Future<bool?> guardar() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _error = null);
    final resultado = await ref.read(serviciosEventualesControllerProvider.notifier).registrarCobro(
          servicioEventualId: widget.servicioEventualId,
          monto: centavosDesdeTexto(_montoCtrl.text) ?? 0,
          fechaPago: _fecha,
          formaPago: _formaPago,
          cuentaFinancieraId: _cuentaId,
          referencia: _referenciaCtrl.text.trim().isEmpty ? null : _referenciaCtrl.text.trim(),
        );
    if (!mounted) return null;
    if (resultado is RegistrarCobroServicioEventualExitoso) return true;
    setState(() => _error = _mensajeCobro(l10n, resultado));
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${l10n.servicioEventualCobroPendiente}: ${formatoCentavosPago(widget.saldoPendiente)}',
              style: AppTypography.bodyStrong,
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              key: const Key('servicio_eventual_cobro_monto'),
              label: l10n.servicioEventualCampoMontoCobro,
              controller: _montoCtrl,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppSpacing.md),
            RisegDateField(
              label: l10n.servicioEventualColumnaFecha,
              value: _fecha,
              onChanged: (valor) => setState(() => _fecha = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<String?>(
              label: l10n.servicioEventualCampoFormaPago,
              value: _formaPago,
              items: [
                for (final forma in FormaPago.values)
                  RisegSelectItem(value: forma.name, label: formaPagoLabel(l10n, forma.name)),
              ],
              onChanged: (valor) => setState(() => _formaPago = valor ?? FormaPago.transferencia.name),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<String?>(
              key: const Key('servicio_eventual_cobro_cuenta'),
              label: l10n.servicioEventualCampoCuentaDestino,
              value: _cuentaId,
              items: [for (final c in widget.cuentas) RisegSelectItem(value: c.id, label: c.nombre)],
              onChanged: (valor) => setState(() => _cuentaId = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.servicioEventualCampoReferencia, controller: _referenciaCtrl),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: AppTypography.caption.copyWith(color: context.colors.error)),
            ],
          ],
        ),
      ),
    );
  }
}

/// El motivo real lo da el flujo de Pagos; aquí sólo se nombra.
String _mensajeCobro(AppLocalizations l10n, RegistrarCobroServicioEventualResultado resultado) {
  if (resultado is RegistrarCobroServicioEventualSinCuenta) return l10n.servicioEventualErrorSinCuenta;
  if (resultado is RegistrarCobroServicioEventualRechazado) {
    return switch (resultado.motivo) {
      RegistrarPagoAplicadoMontoInvalido() => l10n.servicioEventualErrorMontoInvalido,
      RegistrarPagoAplicadoSobrepago(:final saldoDisponible) =>
        '${l10n.servicioEventualErrorCobroInvalido} (${formatoCentavosPago(saldoDisponible)})',
      RegistrarPagoAplicadoCuentaYaPagada() => l10n.servicioEventualErrorYaPagada,
      RegistrarPagoAplicadoCuentaCancelada() => l10n.servicioEventualErrorCancelado,
      _ => l10n.servicioEventualErrorPermiso,
    };
  }
  return l10n.servicioEventualErrorPermiso;
}

// ==================================================================
// Documento fiscal
// ==================================================================

/// Registra o corrige el CFDI emitido por fuera de RISEG.
Future<bool> mostrarDialogoDocumentoFiscal(
  BuildContext context,
  WidgetRef ref, {
  required ServicioEventualData eventual,
  ServicioEventualDocumentoFiscalData? existente,
}) async {
  final l10n = AppLocalizations.of(context)!;
  // Sólo un eventual de Cliente tiene entidades fiscales que elegir; el
  // solicitante eventual captura sus datos a mano y NO se le crea
  // Cliente ni EntidadFiscal permanente.
  final entidades = eventual.clienteId == null
      ? const <EntidadFiscalConDomicilio>[]
      : await ref.read(entidadFiscalRepositoryProvider).listarPorCliente(eventual.clienteId!);
  if (!context.mounted) return false;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: existente == null
        ? l10n.servicioEventualDialogoFacturaTitulo
        : l10n.servicioEventualDialogoFacturaCorregirTitulo,
    confirmLabel: existente == null
        ? l10n.servicioEventualBotonRegistrarDocumento
        : l10n.servicioEventualBotonGuardarCambios,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (_) => _FormularioDocumentoFiscal(
      key: _claveDocumento,
      eventual: eventual,
      existente: existente,
      entidades: entidades,
    ),
    onConfirm: () async => _claveDocumento.currentState?.guardar(),
  );
  return resultado ?? false;
}

class _FormularioDocumentoFiscal extends ConsumerStatefulWidget {
  const _FormularioDocumentoFiscal({
    super.key,
    required this.eventual,
    required this.existente,
    required this.entidades,
  });

  final ServicioEventualData eventual;
  final ServicioEventualDocumentoFiscalData? existente;
  final List<EntidadFiscalConDomicilio> entidades;

  @override
  ConsumerState<_FormularioDocumentoFiscal> createState() => _FormularioDocumentoFiscalState();
}

class _FormularioDocumentoFiscalState extends ConsumerState<_FormularioDocumentoFiscal> {
  late final TextEditingController _folioCtrl;
  late final TextEditingController _uuidCtrl;
  late final TextEditingController _razonSocialCtrl;
  late final TextEditingController _rfcCtrl;
  late final TextEditingController _cpFiscalCtrl;
  late final TextEditingController _observacionesCtrl;
  final _motivoCtrl = TextEditingController();

  late DateTime _fechaEmision;
  late MetodoPagoCobro _metodo;
  String? _entidadFiscalId;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    _folioCtrl = TextEditingController(text: e?.folio ?? '');
    _uuidCtrl = TextEditingController(text: e?.uuid ?? '');
    _razonSocialCtrl = TextEditingController(text: e?.snapshotRazonSocial ?? '');
    _rfcCtrl = TextEditingController(text: e?.snapshotRfc ?? '');
    _cpFiscalCtrl = TextEditingController(text: e?.snapshotCodigoPostalFiscal ?? '');
    _observacionesCtrl = TextEditingController(text: e?.observaciones ?? '');
    // Cuando el eventual ya trae receptor fiscal se muestra ÉSE, no el
    // hueco vacío que invitaría a capturar otro distinto.
    if (e == null && _receptorYaDefinido) {
      _razonSocialCtrl.text = widget.eventual.solicitanteRazonSocial ??
          widget.entidades
              .where((x) => x.entidadFiscal.id == widget.eventual.entidadFiscalId)
              .map((x) => x.entidadFiscal.razonSocial)
              .firstOrNull ??
          '';
    }
    _fechaEmision = e?.fechaEmision ?? DateTime.now();
    _metodo = e == null ? MetodoPagoCobro.pue : MetodoPagoCobro.values.byName(e.metodo);
    _entidadFiscalId = e?.entidadFiscalId ?? widget.entidades.firstOrNull?.entidadFiscal.id;
  }

  @override
  void dispose() {
    _folioCtrl.dispose();
    _uuidCtrl.dispose();
    _razonSocialCtrl.dispose();
    _rfcCtrl.dispose();
    _cpFiscalCtrl.dispose();
    _observacionesCtrl.dispose();
    _motivoCtrl.dispose();
    super.dispose();
  }

  bool get _esCliente => widget.eventual.clienteId != null;

  /// El eventual ya sabe a nombre de quién se factura — todo lo vendido
  /// desde la schemaVersion 90.
  bool get _receptorYaDefinido =>
      (widget.eventual.entidadFiscalId ?? '').isNotEmpty ||
      (widget.eventual.solicitanteRazonSocial ?? '').trim().isNotEmpty;

  /// `true` si guardó (el marco cierra), `null` si hay que
  /// corregir algo (el marco se queda abierto con el error a la vista).
  Future<bool?> guardar() async {
    final l10n = AppLocalizations.of(context)!;
    final notifier = ref.read(serviciosEventualesControllerProvider.notifier);
    setState(() => _error = null);

    final Object resultado;
    if (widget.existente == null) {
      resultado = await notifier.registrarDocumentoFiscal(
        servicioEventualId: widget.eventual.id,
        folio: _folioCtrl.text,
        uuid: _uuidCtrl.text,
        fechaEmision: _fechaEmision,
        metodo: _metodo,
        // Con receptor ya definido el caso de uso lo ignora y toma el
        // del eventual; se mandan en null para que quede claro que esta
        // pantalla no decide a nombre de quién se emite.
        entidadFiscalId: _receptorYaDefinido || !_esCliente ? null : _entidadFiscalId,
        razonSocialManual: _receptorYaDefinido || _esCliente ? null : _razonSocialCtrl.text,
        rfcManual: _receptorYaDefinido || _esCliente ? null : _rfcCtrl.text,
        codigoPostalFiscalManual: _receptorYaDefinido || _esCliente ? null : _cpFiscalCtrl.text,
        observaciones: _observacionesCtrl.text,
      );
    } else {
      resultado = await notifier.corregirDocumentoFiscal(
        documentoId: widget.existente!.id,
        folio: _folioCtrl.text,
        uuid: _uuidCtrl.text,
        fechaEmision: _fechaEmision,
        metodo: _metodo,
        observaciones: _observacionesCtrl.text,
        motivo: _motivoCtrl.text,
      );
    }

    if (!mounted) return null;
    final mensaje = _mensajeDocumento(l10n, resultado);
    if (mensaje == null) return true;
    setState(() => _error = mensaje);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegTextField(
              key: const Key('servicio_eventual_campo_folio_factura'),
              label: l10n.servicioEventualCampoFolioFactura,
              controller: _folioCtrl,
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              key: const Key('servicio_eventual_campo_uuid'),
              label: l10n.servicioEventualCampoUuid,
              controller: _uuidCtrl,
              // Opcional a propósito: en la operación real el UUID
              // suele llegar después del folio.
              helperText: l10n.servicioEventualCampoObservaciones,
            ),
            const SizedBox(height: AppSpacing.md),
            RisegDateField(
              label: l10n.servicioEventualCampoFechaEmision,
              value: _fechaEmision,
              onChanged: (valor) => setState(() => _fechaEmision = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<MetodoPagoCobro>(
              key: const Key('servicio_eventual_campo_metodo_factura'),
              label: l10n.servicioEventualCampoMetodoCobro,
              value: _metodo,
              items: [
                RisegSelectItem(value: MetodoPagoCobro.pue, label: l10n.servicioEventualMetodoPue),
                RisegSelectItem(value: MetodoPagoCobro.ppd, label: l10n.servicioEventualMetodoPpd),
              ],
              onChanged: (valor) => setState(() => _metodo = valor ?? MetodoPagoCobro.pue),
            ),
            const SizedBox(height: AppSpacing.md),
            if (widget.existente == null && _receptorYaDefinido)
              // Ya se decidió al vender: aquí sólo se confirma a la
              // vista. Volver a pedirlo permitiría facturar a nombre
              // de alguien distinto del que se le vendió.
              RisegTextField(
                key: const Key('servicio_eventual_receptor_de_la_venta'),
                label: l10n.servicioEventualDocumentoColumnaReceptor,
                controller: _razonSocialCtrl,
                readOnly: true,
              )
            else if (widget.existente == null && _esCliente)
              RisegSelect<String?>(
                key: const Key('servicio_eventual_campo_entidad_fiscal'),
                label: l10n.servicioEventualCampoEntidadFiscal,
                value: _entidadFiscalId,
                items: [
                  for (final e in widget.entidades)
                    RisegSelectItem(
                      value: e.entidadFiscal.id,
                      label: '${e.entidadFiscal.razonSocial} - ${e.entidadFiscal.rfc}',
                    ),
                ],
                onChanged: (valor) => setState(() => _entidadFiscalId = valor),
              )
            else if (widget.existente == null) ...[
              // Histórico anterior a la v90: el eventual no guarda
              // receptor fiscal, así que se captura y se congela aquí.
              RisegTextField(
                key: const Key('servicio_eventual_campo_razon_social'),
                label: l10n.servicioEventualCampoRazonSocial,
                controller: _razonSocialCtrl,
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                key: const Key('servicio_eventual_campo_rfc'),
                label: l10n.servicioEventualCampoRfc,
                controller: _rfcCtrl,
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                key: const Key('servicio_eventual_campo_cp_fiscal'),
                label: l10n.servicioEventualCampoCodigoPostalFiscal,
                controller: _cpFiscalCtrl,
                keyboardType: TextInputType.number,
              ),
            ] else
              // Ya emitido: el snapshot es historia, se muestra pero no
              // se edita.
              RisegTextField(
                label: l10n.servicioEventualDocumentoColumnaReceptor,
                controller: _razonSocialCtrl,
                readOnly: true,
              ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.servicioEventualCampoObservaciones, controller: _observacionesCtrl),
            if (widget.existente != null) ...[
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                key: const Key('servicio_eventual_campo_motivo_factura'),
                label: l10n.servicioEventualCampoMotivo,
                controller: _motivoCtrl,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: AppTypography.caption.copyWith(color: context.colors.error)),
            ],
          ],
        ),
      ),
    );
  }
}

/// `null` = todo bien.
String? _mensajeDocumento(AppLocalizations l10n, Object resultado) {
  return switch (resultado) {
    RegistrarDocumentoFiscalEventualExitoso() || CorregirDocumentoFiscalEventualExitoso() => null,
    RegistrarDocumentoFiscalEventualFolioRequerido() ||
    CorregirDocumentoFiscalEventualFolioRequerido() =>
      l10n.servicioEventualErrorFolioRequerido,
    RegistrarDocumentoFiscalEventualUuidInvalido() || CorregirDocumentoFiscalEventualUuidInvalido() =>
      l10n.servicioEventualErrorUuidInvalido,
    RegistrarDocumentoFiscalEventualNoRequiereFactura() => l10n.servicioEventualErrorNoRequiereFactura,
    RegistrarDocumentoFiscalEventualYaTieneVigente() => l10n.servicioEventualErrorYaTieneFactura,
    RegistrarDocumentoFiscalEventualDatosFiscalesRequeridos() =>
      l10n.servicioEventualErrorDatosFiscalesRequeridos,
    RegistrarDocumentoFiscalEventualEntidadFiscalInvalida() =>
      l10n.servicioEventualErrorEntidadFiscalInvalida,
    RegistrarDocumentoFiscalEventualMetodoInvalido() || CorregirDocumentoFiscalEventualMetodoInvalido() =>
      l10n.servicioEventualErrorMetodoIncoherente,
    RegistrarDocumentoFiscalEventualCancelado() || CorregirDocumentoFiscalEventualCancelado() =>
      l10n.servicioEventualErrorCancelado,
    CorregirDocumentoFiscalEventualMotivoRequerido() => l10n.servicioEventualErrorMotivoRequerido,
    _ => l10n.servicioEventualErrorPermiso,
  };
}
