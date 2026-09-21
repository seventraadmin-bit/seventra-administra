import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart'
    show formatoCentavosPago;

import '../../domain/usecases/cancelar_servicio_eventual_usecase.dart';
import '../../servicios_eventuales_providers.dart';
import '../servicios_eventuales_controller.dart';

/// Cancelar el evento = anular la venta.
///
/// Antes de pedir el motivo, este diálogo **enumera** lo que va a pasar:
/// qué dinero regresa, qué obligación se cancela y qué gasto real se
/// queda donde está. Existe por un hallazgo concreto de la prueba
/// manual: el evento se cancelaba y el pago, el ingreso y el saldo
/// bancario seguían vivos sin que nada lo dijera.
///
/// Devuelve `true` si la venta quedó anulada.
Future<bool> mostrarDialogoAnularServicioEventual(
  BuildContext context,
  WidgetRef ref, {
  required String servicioEventualId,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final resumen = await ref.read(previsualizarAnulacionServicioEventualProvider)(servicioEventualId);
  if (!context.mounted) return false;

  // Con CFDI o complemento vigente no hay nada que confirmar: se
  // explica qué resolver primero y se cierra. Nunca una cascada fiscal
  // automática — RISEG ONE no timbra, así que tampoco cancela.
  if (resumen.bloqueada) {
    final documento = resumen.documentoFiscalVigente;
    await RisegDialog.showInformational(
      context: context,
      title: l10n.servicioEventualDialogoAnularTitulo,
      message: documento != null
          ? l10n.servicioEventualAnularBloqueadaDocumento(documento.folio)
          : l10n.servicioEventualAnularBloqueadaComplemento(resumen.complementoVigenteUuid ?? ''),
      dismissLabel: l10n.compraBotonCancelarFormulario,
    );
    return false;
  }

  final confirmado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.servicioEventualDialogoAnularTitulo,
    confirmLabel: l10n.servicioEventualAnularConfirmar,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (_) => _FormularioAnulacion(key: _claveAnulacion, resumen: resumen),
    onConfirm: () async => _claveAnulacion.currentState?.guardar(servicioEventualId),
  );
  return confirmado ?? false;
}

final _claveAnulacion = GlobalKey<_FormularioAnulacionState>();

class _FormularioAnulacion extends ConsumerStatefulWidget {
  const _FormularioAnulacion({super.key, required this.resumen});

  final ResumenAnulacionServicioEventual resumen;

  @override
  ConsumerState<_FormularioAnulacion> createState() => _FormularioAnulacionState();
}

class _FormularioAnulacionState extends ConsumerState<_FormularioAnulacion> {
  final _motivoCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _motivoCtrl.dispose();
    super.dispose();
  }

  Future<bool?> guardar(String servicioEventualId) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _error = null);
    final resultado = await ref.read(serviciosEventualesControllerProvider.notifier).cancelar(
          servicioEventualId: servicioEventualId,
          motivo: _motivoCtrl.text,
        );
    if (!mounted) return null;
    final mensaje = switch (resultado) {
      CancelarServicioEventualExitoso() => null,
      CancelarServicioEventualMotivoRequerido() => l10n.servicioEventualErrorMotivoRequerido,
      CancelarServicioEventualYaCancelado() => l10n.servicioEventualErrorCancelado,
      CancelarServicioEventualDocumentoFiscalVigente(folio: final folio) =>
        l10n.servicioEventualAnularBloqueadaDocumento(folio),
      CancelarServicioEventualComplementoVigente(uuid: final uuid) =>
        l10n.servicioEventualAnularBloqueadaComplemento(uuid),
      CancelarServicioEventualNoExiste() => l10n.serviciosEventualesVacioMensaje,
      CancelarServicioEventualErrorInesperado(mensaje: final detalle) => detalle,
    };
    if (mensaje == null) return true;
    setState(() => _error = mensaje);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final r = widget.resumen;

    // Dos listas, deliberadamente separadas: lo que vuelve atrás y lo
    // que no. Mezclarlas es lo que dejaba al usuario sin saber que su
    // gasto real seguía siendo un gasto real.
    final revierte = <String>[
      for (final cobro in r.cobros)
        if (cobro.exclusivoDeEstaVenta)
          l10n.servicioEventualAnularPagoCompleto(
            cobro.pago.folioPago,
            formatoCentavosPago(cobro.pago.montoTotal),
          )
        else
          l10n.servicioEventualAnularPagoCompartido(
            cobro.pago.folioPago,
            formatoCentavosPago(cobro.monto),
          ),
      if (r.cuenta != null) l10n.servicioEventualAnularCuenta,
      if (r.coberturasPorCancelar > 0)
        l10n.servicioEventualAnularCoberturas('${r.coberturasPorCancelar}'),
      if (r.costosPorCancelar > 0) l10n.servicioEventualAnularCostos('${r.costosPorCancelar}'),
    ];
    final permanece = <String>[
      if (r.gastoQuePermanece > 0)
        l10n.servicioEventualAnularGastoReal(formatoCentavosPago(r.gastoQuePermanece)),
    ];

    return SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.servicioEventualAnularIntro, style: AppTypography.body),
            const SizedBox(height: AppSpacing.md),
            _Lista(
              key: const Key('servicio_eventual_anular_revierte'),
              titulo: l10n.servicioEventualAnularSeRevierte,
              renglones: revierte,
              vacio: r.sinCobros ? l10n.servicioEventualAnularSinCobros : null,
            ),
            if (permanece.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _Lista(
                key: const Key('servicio_eventual_anular_permanece'),
                titulo: l10n.servicioEventualAnularPermanece,
                renglones: permanece,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            RisegTextField(
              key: const Key('servicio_eventual_anular_motivo'),
              label: l10n.servicioEventualCampoMotivo,
              controller: _motivoCtrl,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: AppTypography.caption.copyWith(color: colors.error)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista({super.key, required this.titulo, required this.renglones, this.vacio});

  final String titulo;
  final List<String> renglones;

  /// Qué decir cuando no hay nada que enumerar — callar dejaría la duda
  /// de si es que no hay o de si no se consultó.
  final String? vacio;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xs),
        if (renglones.isEmpty && vacio != null)
          Text(vacio!, style: AppTypography.caption.copyWith(color: colors.textMuted))
        else
          for (final renglon in renglones)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('·  ', style: AppTypography.body.copyWith(color: colors.textMuted)),
                  Expanded(child: Text(renglon, style: AppTypography.body)),
                ],
              ),
            ),
      ],
    );
  }
}
