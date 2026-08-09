import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/registrar_envio_documento_por_emitir_usecase.dart';

import '../agenda_controller.dart';

/// Abre el diálogo "Registrar envío" (Etapa 4I.2.1) — los correos se
/// precargan desde el envío anterior o, si nunca se ha enviado, desde
/// el snapshot de la Configuración de cobro al generar
/// (`DocumentoPorEmitirCorreo`), pero quedan editables antes de
/// confirmar (Resolución 8 de Marlon). Devuelve `true` si se registró
/// el envío.
Future<bool> mostrarDialogoRegistrarEnvio(BuildContext context, WidgetRef ref, String documentoPorEmitirId) async {
  final l10n = AppLocalizations.of(context)!;
  final correosSugeridos =
      await ref.read(agendaControllerProvider.notifier).obtenerCorreosSugeridosParaEnvio(documentoPorEmitirId);
  if (!context.mounted) return false;

  var datos = _DatosEnvio(correos: correosSugeridos);

  final resultado = await RisegDialog.showForm<RegistrarEnvioDocumentoPorEmitirResultado?>(
    context: context,
    title: l10n.agendaRegistrarEnvioDialogoTitulo,
    confirmLabel: l10n.agendaRegistrarEnvioBotonConfirmar,
    cancelLabel: l10n.agendaRegistrarEnvioBotonCancelar,
    contentBuilder: (_) => _RegistrarEnvioForm(correosIniciales: correosSugeridos, onCambio: (nuevo) => datos = nuevo),
    onConfirm: () async {
      return ref.read(agendaControllerProvider.notifier).registrarEnvio(
            documentoPorEmitirId: documentoPorEmitirId,
            fechaEnvio: datos.fechaEnvio,
            correos: datos.correos,
            observacionesEnvio: datos.observaciones.trim().isEmpty ? null : datos.observaciones.trim(),
          );
    },
  );

  if (!context.mounted) return false;

  switch (resultado) {
    case RegistrarEnvioDocumentoPorEmitirExitoso():
      RisegFeedback.showSuccess(context, l10n.agendaRegistrarEnvioExito);
      return true;
    case RegistrarEnvioDocumentoPorEmitirTransicionInvalida():
      RisegFeedback.showError(context, l10n.agendaRegistrarEnvioErrorTransicionInvalida);
    case RegistrarEnvioDocumentoPorEmitirNoExiste():
    case RegistrarEnvioDocumentoPorEmitirErrorInesperado():
      RisegFeedback.showError(context, l10n.agendaRegistrarEnvioErrorInesperado);
    case null:
      break;
  }
  return false;
}

class _DatosEnvio {
  _DatosEnvio({required this.correos, DateTime? fechaEnvio, this.observaciones = ''})
      : fechaEnvio = fechaEnvio ?? DateTime.now();

  final List<String> correos;
  final DateTime fechaEnvio;
  final String observaciones;

  _DatosEnvio copyWith({List<String>? correos, DateTime? fechaEnvio, String? observaciones}) {
    return _DatosEnvio(
      correos: correos ?? this.correos,
      fechaEnvio: fechaEnvio ?? this.fechaEnvio,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}

class _RegistrarEnvioForm extends StatefulWidget {
  const _RegistrarEnvioForm({required this.correosIniciales, required this.onCambio});

  final List<String> correosIniciales;
  final void Function(_DatosEnvio datos) onCambio;

  @override
  State<_RegistrarEnvioForm> createState() => _RegistrarEnvioFormState();
}

class _RegistrarEnvioFormState extends State<_RegistrarEnvioForm> {
  late _DatosEnvio _datos = _DatosEnvio(correos: List.of(widget.correosIniciales));
  final _correoNuevoController = TextEditingController();
  final _observacionesController = TextEditingController();

  @override
  void dispose() {
    _correoNuevoController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  void _agregarCorreo() {
    final correo = _correoNuevoController.text.trim();
    if (correo.isEmpty || _datos.correos.contains(correo)) return;
    setState(() {
      _datos = _datos.copyWith(correos: [..._datos.correos, correo]);
      _correoNuevoController.clear();
    });
    widget.onCambio(_datos);
  }

  void _quitarCorreo(String correo) {
    setState(() => _datos = _datos.copyWith(correos: _datos.correos.where((c) => c != correo).toList()));
    widget.onCambio(_datos);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegDateField(
          label: l10n.agendaDetalleCampoFechaEnvio,
          value: _datos.fechaEnvio,
          onChanged: (valor) {
            setState(() => _datos = _datos.copyWith(fechaEnvio: valor));
            widget.onCambio(_datos);
          },
        ),
        const SizedBox(height: AppSpacing.md),
        Text(l10n.agendaDetalleCampoCorreosUtilizados, style: AppTypography.label),
        const SizedBox(height: AppSpacing.xxs),
        for (final correo in _datos.correos)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: Row(
              children: [
                Expanded(child: Text(correo)),
                RisegButton(
                  label: l10n.agendaRegistrarEnvioBotonQuitarCorreo,
                  variant: RisegButtonVariant.ghost,
                  onPressed: () => _quitarCorreo(correo),
                ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: RisegTextField(
                label: l10n.agendaRegistrarEnvioCampoCorreoNuevo,
                controller: _correoNuevoController,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            RisegButton(
              label: l10n.agendaRegistrarEnvioBotonAgregarCorreo,
              variant: RisegButtonVariant.secondary,
              onPressed: _agregarCorreo,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.agendaDetalleCampoObservacionesEnvio,
          controller: _observacionesController,
          onChanged: (valor) {
            _datos = _datos.copyWith(observaciones: valor);
            widget.onCambio(_datos);
          },
        ),
      ],
    );
  }
}
