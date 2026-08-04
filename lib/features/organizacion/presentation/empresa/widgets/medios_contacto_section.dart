import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/empresa_expediente_errors.dart';
import 'package:riseg_one/features/organizacion/presentation/empresa/campo_error_l10n.dart';
import 'package:riseg_one/features/organizacion/presentation/empresa/empresa_expediente_form_controllers.dart';
import 'package:riseg_one/features/organizacion/presentation/empresa/empresa_expediente_state.dart';

import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';

/// Sección "Medios de contacto" — administra únicamente el medio de
/// contacto principal (`etiqueta = 'principal'`); la etiqueta en sí no
/// es un campo editable de esta pantalla.
class MediosContactoSection extends StatelessWidget {
  const MediosContactoSection({
    required this.modo,
    required this.contacto,
    required this.controllers,
    required this.habilitado,
    required this.errores,
    required this.onCampoModificado,
    super.key,
  });

  final EmpresaExpedienteModo modo;
  final MedioContactoData? contacto;
  final MedioContactoControllers controllers;
  final bool habilitado;
  final List<ErrorCampoExpediente> errores;
  final VoidCallback onCampoModificado;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (modo == EmpresaExpedienteModo.consulta) {
      return RisegFormSection(
        title: l10n.empresaSeccionMediosContactoTitulo,
        children: [
          CampoConsulta(label: l10n.empresaCampoTelefono, value: contacto?.telefono),
          CampoConsulta(label: l10n.empresaCampoCorreo, value: contacto?.correo),
          CampoConsulta(label: l10n.empresaCampoSitioWeb, value: contacto?.sitioWeb),
        ],
      );
    }

    String? errorDe(CampoExpediente campo) {
      final error = errorParaCampo(errores, campo);
      return error == null ? null : mensajeErrorCampoExpediente(l10n, error);
    }

    return RisegFormSection(
      title: l10n.empresaSeccionMediosContactoTitulo,
      children: [
        RisegTextField(
          label: l10n.empresaCampoTelefono,
          controller: controllers.telefono,
          enabled: habilitado,
          onChanged: (_) => onCampoModificado(),
        ),
        RisegTextField(
          label: l10n.empresaCampoCorreo,
          controller: controllers.correo,
          enabled: habilitado,
          errorText: errorDe(CampoExpediente.correo),
          onChanged: (_) => onCampoModificado(),
        ),
        RisegTextField(
          label: l10n.empresaCampoSitioWeb,
          controller: controllers.sitioWeb,
          enabled: habilitado,
          errorText: errorDe(CampoExpediente.sitioWeb),
          onChanged: (_) => onCampoModificado(),
        ),
      ],
    );
  }
}
