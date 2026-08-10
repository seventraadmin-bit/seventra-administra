import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;
import 'package:riseg_one/features/nomina/data/tables/nomina_empleado_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_distribucion_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_movimientos_nomina_usecase.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';

import '../../../nomina_providers.dart';
import '../nominas_controller.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

String _fuenteSueldoLabel(AppLocalizations l10n, String valor) {
  return switch (FuenteSueldoNomina.values.byName(valor)) {
    FuenteSueldoNomina.servicio => l10n.nominaFuenteSueldoServicio,
    FuenteSueldoNomina.administrativo => l10n.nominaFuenteSueldoAdministrativo,
  };
}

/// Detalle de un renglón de Nómina (Etapa 6C) — banco/cuenta/CLABE,
/// cálculo, desglose por tramos, movimientos manuales y distribución
/// Fiscal/No fiscal. Todo lo que `NominaDetalleScreen` deliberadamente
/// no mete en su tabla principal.
///
/// Devuelve `true` (al cerrarse) si algo cambió, para que el listado se
/// recargue.
class RenglonNominaDetalleDialog extends ConsumerStatefulWidget {
  const RenglonNominaDetalleDialog({required this.nominaEmpleadoId, required this.nominaCerrada, super.key});

  final String nominaEmpleadoId;
  final bool nominaCerrada;

  @override
  ConsumerState<RenglonNominaDetalleDialog> createState() => _RenglonNominaDetalleDialogState();
}

class _RenglonNominaDetalleDialogState extends ConsumerState<RenglonNominaDetalleDialog> {
  NominaEmpleadoData? _renglon;
  List<NominaEmpleadoTramoData> _tramos = const [];
  bool _cargando = true;
  bool _guardandoMovimientos = false;
  bool _guardandoDistribucion = false;
  bool _huboCambios = false;

  late final TextEditingController _prestamoCtrl;
  late final TextEditingController _tiempoExtraCtrl;
  late final TextEditingController _bonoCtrl;
  late final TextEditingController _faltasCtrl;
  late final TextEditingController _otrosDescuentosCtrl;
  late final TextEditingController _observacionesCtrl;
  late final TextEditingController _montoFiscalCtrl;
  late final TextEditingController _montoNoFiscalCtrl;

  @override
  void initState() {
    super.initState();
    _prestamoCtrl = TextEditingController();
    _tiempoExtraCtrl = TextEditingController();
    _bonoCtrl = TextEditingController();
    _faltasCtrl = TextEditingController();
    _otrosDescuentosCtrl = TextEditingController();
    _observacionesCtrl = TextEditingController();
    _montoFiscalCtrl = TextEditingController();
    _montoNoFiscalCtrl = TextEditingController();
    _cargar();
  }

  @override
  void dispose() {
    _prestamoCtrl.dispose();
    _tiempoExtraCtrl.dispose();
    _bonoCtrl.dispose();
    _faltasCtrl.dispose();
    _otrosDescuentosCtrl.dispose();
    _observacionesCtrl.dispose();
    _montoFiscalCtrl.dispose();
    _montoNoFiscalCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final notifier = ref.read(nominasControllerProvider.notifier);
    final tramos = await notifier.listarTramos(widget.nominaEmpleadoId);
    final renglon = await ref.read(nominaRepositoryProvider).obtenerEmpleado(widget.nominaEmpleadoId);
    if (!mounted) return;
    setState(() {
      _renglon = renglon;
      _tramos = tramos;
      _cargando = false;
      if (renglon != null) {
        _prestamoCtrl.text = _pesos(renglon.prestamo);
        _tiempoExtraCtrl.text = _pesos(renglon.tiempoExtra);
        _bonoCtrl.text = _pesos(renglon.bono);
        _faltasCtrl.text = renglon.faltas.toString();
        _otrosDescuentosCtrl.text = _pesos(renglon.otrosDescuentos);
        _observacionesCtrl.text = renglon.observaciones ?? '';
        _montoFiscalCtrl.text = _pesos(renglon.montoFiscal);
        _montoNoFiscalCtrl.text = _pesos(renglon.montoNoFiscal);
      }
    });
  }

  String _pesos(int centavos) => (centavos / 100).toStringAsFixed(2);

  int? _centavos(String texto) {
    final normalizado = texto.trim().replaceAll(',', '');
    if (normalizado.isEmpty) return 0;
    final pesos = double.tryParse(normalizado);
    if (pesos == null) return null;
    return (pesos * 100).round();
  }

  Future<void> _guardarMovimientos() async {
    final l10n = AppLocalizations.of(context)!;
    final prestamo = _centavos(_prestamoCtrl.text);
    final tiempoExtra = _centavos(_tiempoExtraCtrl.text);
    final bono = _centavos(_bonoCtrl.text);
    final faltas = int.tryParse(_faltasCtrl.text.trim().isEmpty ? '0' : _faltasCtrl.text.trim());
    final otrosDescuentos = _centavos(_otrosDescuentosCtrl.text);

    if (prestamo == null || tiempoExtra == null || bono == null || faltas == null || otrosDescuentos == null) {
      RisegFeedback.showError(context, l10n.renglonNominaDetalleErrorValorInvalido);
      return;
    }

    setState(() => _guardandoMovimientos = true);
    final resultado = await ref.read(nominasControllerProvider.notifier).actualizarMovimientos(
          nominaEmpleadoId: widget.nominaEmpleadoId,
          prestamo: prestamo,
          tiempoExtra: tiempoExtra,
          bono: bono,
          faltas: faltas,
          otrosDescuentos: otrosDescuentos,
          observaciones: _observacionesCtrl.text.trim().isEmpty ? null : _observacionesCtrl.text.trim(),
          limpiarObservaciones: _observacionesCtrl.text.trim().isEmpty,
        );
    if (!mounted) return;
    setState(() => _guardandoMovimientos = false);

    switch (resultado) {
      case ActualizarMovimientosNominaExitoso():
        RisegFeedback.showSuccess(context, l10n.renglonNominaDetalleMovimientosExito);
        _huboCambios = true;
        await _cargar();
      case ActualizarMovimientosNominaValorInvalido():
        RisegFeedback.showError(context, l10n.renglonNominaDetalleErrorValorInvalido);
      case ActualizarMovimientosNominaNoExiste():
      case ActualizarMovimientosNominaNominaCerrada():
        RisegFeedback.showError(context, l10n.renglonNominaDetalleNominaCerrada);
    }
  }

  Future<void> _guardarDistribucion() async {
    final l10n = AppLocalizations.of(context)!;
    final montoFiscal = _centavos(_montoFiscalCtrl.text);
    final montoNoFiscal = _centavos(_montoNoFiscalCtrl.text);
    if (montoFiscal == null || montoNoFiscal == null) {
      RisegFeedback.showError(context, l10n.renglonNominaDetalleErrorValorInvalido);
      return;
    }

    setState(() => _guardandoDistribucion = true);
    final resultado = await ref.read(nominasControllerProvider.notifier).actualizarDistribucion(
          nominaEmpleadoId: widget.nominaEmpleadoId,
          montoFiscal: montoFiscal,
          montoNoFiscal: montoNoFiscal,
        );
    if (!mounted) return;
    setState(() => _guardandoDistribucion = false);

    switch (resultado) {
      case ActualizarDistribucionNominaExitoso():
        RisegFeedback.showSuccess(context, l10n.renglonNominaDetalleDistribucionExito);
        _huboCambios = true;
        await _cargar();
      case ActualizarDistribucionNominaNoBalancea():
        RisegFeedback.showError(context, l10n.renglonNominaDetalleErrorDistribucionNoBalancea);
      case ActualizarDistribucionNominaValorInvalido():
        RisegFeedback.showError(context, l10n.renglonNominaDetalleErrorValorInvalido);
      case ActualizarDistribucionNominaNoExiste():
      case ActualizarDistribucionNominaNominaCerrada():
        RisegFeedback.showError(context, l10n.renglonNominaDetalleNominaCerrada);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    Widget content;
    if (_cargando) {
      content = const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
    } else if (_renglon == null) {
      content = Text(l10n.nominaDetalleCargaErrorMensaje);
    } else {
      final r = _renglon!;
      final soloLectura = widget.nominaCerrada;

      content = SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.nombreCompleto, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: CampoConsulta(label: l10n.renglonNominaDetalleCampoBanco, value: r.bancoNombre)),
                Expanded(child: CampoConsulta(label: l10n.renglonNominaDetalleCampoCuenta, value: r.numeroCuentaTarjeta)),
                Expanded(child: CampoConsulta(label: l10n.renglonNominaDetalleCampoClabe, value: r.clabe)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.renglonNominaDetalleSeccionCalculo, style: AppTypography.label.copyWith(color: colors.textMuted)),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(child: CampoConsulta(label: l10n.renglonNominaDetalleCampoFuente, value: _fuenteSueldoLabel(l10n, r.fuenteSueldoUtilizada))),
                Expanded(child: CampoConsulta(label: l10n.renglonNominaDetalleCampoDias, value: r.diasPagables.toString())),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: CampoConsulta(
                    label: l10n.renglonNominaDetalleCampoSueldoUtilizado,
                    value: formatoCentavosPago(r.sueldoMensualUtilizado),
                  ),
                ),
                Expanded(child: CampoConsulta(label: l10n.renglonNominaDetalleCampoImporteBase, value: formatoCentavosPago(r.importeBase))),
                Expanded(child: CampoConsulta(label: l10n.renglonNominaDetalleCampoTotal, value: formatoCentavosPago(r.totalAPagar))),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.renglonNominaDetalleSeccionTramos, style: AppTypography.label.copyWith(color: colors.textMuted)),
            const SizedBox(height: AppSpacing.xs),
            for (final t in _tramos)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: Text(
                  '${_formatoFecha.format(t.fechaInicio)} – ${_formatoFecha.format(t.fechaFin)} · '
                  '${t.servicioNombre ?? _fuenteSueldoLabel(l10n, t.fuenteSueldo)} · '
                  '${t.diasReales}d · ${formatoCentavosPago(t.importeTramo)}',
                  style: AppTypography.body.copyWith(color: colors.textPrimary),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.renglonNominaDetalleSeccionMovimientos, style: AppTypography.label.copyWith(color: colors.textMuted)),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: RisegTextField(
                    label: l10n.renglonNominaDetalleCampoPrestamo,
                    controller: _prestamoCtrl,
                    enabled: !soloLectura,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: RisegTextField(
                    label: l10n.renglonNominaDetalleCampoTiempoExtra,
                    controller: _tiempoExtraCtrl,
                    enabled: !soloLectura,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: RisegTextField(
                    label: l10n.renglonNominaDetalleCampoBono,
                    controller: _bonoCtrl,
                    enabled: !soloLectura,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: RisegTextField(
                    label: l10n.renglonNominaDetalleCampoFaltas,
                    controller: _faltasCtrl,
                    enabled: !soloLectura,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            RisegTextField(
              label: l10n.renglonNominaDetalleCampoOtrosDescuentos,
              controller: _otrosDescuentosCtrl,
              enabled: !soloLectura,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppSpacing.sm),
            RisegTextField(label: l10n.renglonNominaDetalleCampoObservaciones, controller: _observacionesCtrl, enabled: !soloLectura),
            if (!soloLectura) ...[
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: RisegButton(
                  label: l10n.renglonNominaDetalleBotonGuardarMovimientos,
                  variant: RisegButtonVariant.secondary,
                  loading: _guardandoMovimientos,
                  onPressed: _guardarMovimientos,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Text(l10n.renglonNominaDetalleSeccionDistribucion, style: AppTypography.label.copyWith(color: colors.textMuted)),
            if (r.distribucionPendienteRevision) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                l10n.renglonNominaDetalleDistribucionPendienteAviso,
                style: AppTypography.caption.copyWith(color: colors.error),
              ),
            ],
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: RisegTextField(
                    label: l10n.renglonNominaDetalleCampoMontoFiscal,
                    controller: _montoFiscalCtrl,
                    enabled: !soloLectura,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: RisegTextField(
                    label: l10n.renglonNominaDetalleCampoMontoNoFiscal,
                    controller: _montoNoFiscalCtrl,
                    enabled: !soloLectura,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            if (!soloLectura) ...[
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: RisegButton(
                  label: l10n.renglonNominaDetalleBotonGuardarDistribucion,
                  variant: RisegButtonVariant.secondary,
                  loading: _guardandoDistribucion,
                  onPressed: _guardarDistribucion,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {},
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 660),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.renglonNominaDetalleDialogoTitulo, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop(_huboCambios)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  content,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
