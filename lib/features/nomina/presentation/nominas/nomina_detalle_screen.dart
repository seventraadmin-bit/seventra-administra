import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;
import 'package:riseg_one/features/nomina/data/tables/nomina_empleado_table.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_nomina_desde_personal_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cerrar_nomina_usecase.dart';

import 'nominas_controller.dart';
import 'nominas_list_screen.dart' show nominaEstatusLabel, nominaEstatusTono;
import 'widgets/generar_nomina_dialog.dart' show nominaTipoPeriodoLabel;
import 'widgets/renglon_nomina_detalle_dialog.dart';

String nominaEstatusPagoLabel(AppLocalizations l10n, String valor) {
  return switch (EstatusPagoNominaEmpleado.values.byName(valor)) {
    EstatusPagoNominaEmpleado.pendiente => l10n.nominaEstatusPagoPendiente,
    EstatusPagoNominaEmpleado.pagado => l10n.nominaEstatusPagoPagado,
  };
}

/// Detalle de una Nómina (Etapa 6C) — el listado principal por Empleado,
/// con exactamente las columnas que pidió Marlon: No. empleado, nombre,
/// Servicio, días, base, percepciones, deducciones, total, Fiscal, No
/// fiscal, estado. Deliberadamente sin replicar el Excel como tabla
/// horizontal gigantesca — banco/CLABE/cálculo/tramos/movimientos viven
/// en el detalle de cada renglón (`RenglonNominaDetalleDialog`).
class NominaDetalleScreen extends ConsumerStatefulWidget {
  const NominaDetalleScreen({required this.nominaId, super.key});

  final String nominaId;

  @override
  ConsumerState<NominaDetalleScreen> createState() => _NominaDetalleScreenState();
}

class _NominaDetalleScreenState extends ConsumerState<NominaDetalleScreen> {
  NominaData? _nomina;
  List<NominaEmpleadoData> _renglones = const [];
  bool _cargando = true;
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final notifier = ref.read(nominasControllerProvider.notifier);
    final nomina = await notifier.obtenerPorId(widget.nominaId);
    final renglones = nomina == null ? <NominaEmpleadoData>[] : await notifier.listarEmpleados(widget.nominaId);
    if (!mounted) return;
    setState(() {
      _nomina = nomina;
      _renglones = renglones;
      _cargando = false;
    });
  }

  Future<void> _abrirRenglon(NominaEmpleadoData renglon) async {
    final cambio = await showDialog<bool>(
      context: context,
      builder: (_) => RenglonNominaDetalleDialog(nominaEmpleadoId: renglon.id, nominaCerrada: _nomina!.estatus != 'borrador'),
    );
    if (cambio == true) await _cargar();
  }

  Future<void> _actualizarDesdePersonal() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _procesando = true);
    final resultado = await ref.read(nominasControllerProvider.notifier).actualizarDesdePersonal(widget.nominaId);
    if (!mounted) return;
    setState(() => _procesando = false);

    switch (resultado) {
      case ActualizarNominaDesdePersonalExitoso():
        RisegFeedback.showSuccess(context, l10n.actualizarNominaExito);
        await _cargar();
      case ActualizarNominaDesdePersonalNoExiste():
      case ActualizarNominaDesdePersonalErrorInesperado():
        RisegFeedback.showError(context, l10n.actualizarNominaErrorInesperado);
      case ActualizarNominaDesdePersonalNominaCerrada():
        RisegFeedback.showError(context, l10n.actualizarNominaNominaCerrada);
    }
  }

  Future<void> _cerrar() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: l10n.cerrarNominaConfirmacionTitulo,
      message: l10n.cerrarNominaConfirmacionMensaje,
      confirmLabel: l10n.cerrarNominaConfirmacionConfirmar,
      cancelLabel: l10n.cerrarNominaConfirmacionCancelar,
    );
    if (confirmado != true || !mounted) return;

    setState(() => _procesando = true);
    final resultado = await ref.read(nominasControllerProvider.notifier).cerrar(widget.nominaId);
    if (!mounted) return;
    setState(() => _procesando = false);

    switch (resultado) {
      case CerrarNominaExitoso():
        RisegFeedback.showSuccess(context, l10n.cerrarNominaExito);
        await _cargar();
      case CerrarNominaSinEmpleados():
        RisegFeedback.showError(context, l10n.cerrarNominaSinEmpleados);
      case CerrarNominaDistribucionPendiente():
        RisegFeedback.showError(context, l10n.cerrarNominaDistribucionPendiente);
      case CerrarNominaYaCerrada():
        RisegFeedback.showError(context, l10n.cerrarNominaYaCerrada);
      case CerrarNominaNoExiste():
        RisegFeedback.showError(context, l10n.cerrarNominaErrorInesperado);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final nomina = _nomina;

    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (nomina == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.nominaDetalleCargaErrorTitulo)),
        body: RisegEmptyState(icon: Icons.error_outline, title: l10n.nominaDetalleCargaErrorTitulo, message: l10n.nominaDetalleCargaErrorMensaje),
      );
    }

    final esBorrador = nomina.estatus == 'borrador';

    return Scaffold(
      appBar: AppBar(title: Text(nomina.folio)),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${nomina.anio}-${nomina.mes.toString().padLeft(2, '0')} · '
                  '${nominaTipoPeriodoLabel(l10n, TipoPeriodoNomina.values.byName(nomina.tipoPeriodo))}',
                  style: AppTypography.heading3,
                ),
                const SizedBox(width: AppSpacing.sm),
                RisegStatusBadge(label: nominaEstatusLabel(l10n, nomina.estatus), tone: nominaEstatusTono(nomina.estatus)),
                const Spacer(),
                if (esBorrador) ...[
                  RisegButton(
                    label: l10n.nominaDetalleBotonActualizarDesdePersonal,
                    variant: RisegButtonVariant.secondary,
                    loading: _procesando,
                    onPressed: _actualizarDesdePersonal,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  RisegButton(
                    label: l10n.nominaDetalleBotonCerrar,
                    variant: RisegButtonVariant.primary,
                    loading: _procesando,
                    onPressed: _cerrar,
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: RisegTableBase<NominaEmpleadoData>(
                rows: _renglones,
                onRowTap: _abrirRenglon,
                emptyState: RisegEmptyState(title: l10n.nominaDetalleVacioTitulo, message: l10n.nominaDetalleVacioMensaje),
                columns: [
                  RisegColumn<NominaEmpleadoData>(
                    label: l10n.nominaDetalleColumnaNumeroEmpleado,
                    width: 110,
                    cellBuilder: (r) => Text(r.numeroEmpleado.toString()),
                  ),
                  RisegColumn<NominaEmpleadoData>(
                    label: l10n.nominaDetalleColumnaNombre,
                    cellBuilder: (r) => Text(r.nombreCompleto),
                  ),
                  RisegColumn<NominaEmpleadoData>(
                    label: l10n.nominaDetalleColumnaServicio,
                    cellBuilder: (r) => Text(r.servicioNombre ?? ''),
                  ),
                  RisegColumn<NominaEmpleadoData>(
                    label: l10n.nominaDetalleColumnaDias,
                    width: 70,
                    alignment: TextAlign.right,
                    cellBuilder: (r) => Text(r.diasPagables.toString()),
                  ),
                  RisegColumn<NominaEmpleadoData>(
                    label: l10n.nominaDetalleColumnaBase,
                    width: 110,
                    alignment: TextAlign.right,
                    cellBuilder: (r) => Text(formatoCentavosPago(r.importeBase)),
                  ),
                  RisegColumn<NominaEmpleadoData>(
                    label: l10n.nominaDetalleColumnaPercepciones,
                    width: 120,
                    alignment: TextAlign.right,
                    cellBuilder: (r) => Text(formatoCentavosPago(r.importeBase + r.bono + r.tiempoExtra)),
                  ),
                  RisegColumn<NominaEmpleadoData>(
                    label: l10n.nominaDetalleColumnaDeducciones,
                    width: 120,
                    alignment: TextAlign.right,
                    cellBuilder: (r) => Text(formatoCentavosPago(r.prestamo + r.descuentoPorFaltas + r.otrosDescuentos)),
                  ),
                  RisegColumn<NominaEmpleadoData>(
                    label: l10n.nominaDetalleColumnaTotal,
                    width: 120,
                    alignment: TextAlign.right,
                    cellBuilder: (r) => Text(formatoCentavosPago(r.totalAPagar)),
                  ),
                  RisegColumn<NominaEmpleadoData>(
                    label: l10n.nominaDetalleColumnaFiscal,
                    width: 110,
                    alignment: TextAlign.right,
                    cellBuilder: (r) => Text(formatoCentavosPago(r.montoFiscal)),
                  ),
                  RisegColumn<NominaEmpleadoData>(
                    label: l10n.nominaDetalleColumnaNoFiscal,
                    width: 110,
                    alignment: TextAlign.right,
                    cellBuilder: (r) => Text(formatoCentavosPago(r.montoNoFiscal)),
                  ),
                  RisegColumn<NominaEmpleadoData>(
                    label: l10n.nominaDetalleColumnaEstado,
                    width: 110,
                    cellBuilder: (r) => r.distribucionPendienteRevision
                        ? RisegStatusBadge(label: nominaEstatusPagoLabel(l10n, r.estatusPago), tone: RisegStatusTone.error)
                        : RisegStatusBadge(label: nominaEstatusPagoLabel(l10n, r.estatusPago), tone: RisegStatusTone.neutral),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
