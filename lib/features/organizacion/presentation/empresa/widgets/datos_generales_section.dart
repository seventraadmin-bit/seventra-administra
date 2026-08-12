import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/empresa_expediente_errors.dart';
import 'package:riseg_one/features/organizacion/presentation/empresa/campo_error_l10n.dart';
import 'package:riseg_one/features/organizacion/presentation/empresa/empresa_expediente_form_controllers.dart';
import 'package:riseg_one/features/organizacion/presentation/empresa/empresa_expediente_state.dart';

import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';

/// Sección "Datos generales" — el código de Empresa siempre se muestra
/// de solo lectura (es autogenerado, nunca es parte de la entrada del
/// formulario), incluso en modo edición.
class DatosGeneralesSection extends StatelessWidget {
  const DatosGeneralesSection({
    required this.modo,
    required this.empresa,
    required this.controllers,
    required this.habilitado,
    required this.errores,
    required this.onCampoModificado,
    super.key,
  });

  final EmpresaExpedienteModo modo;
  final EmpresaData empresa;
  final DatosGeneralesControllers controllers;
  final bool habilitado;
  final List<ErrorCampoExpediente> errores;
  final VoidCallback onCampoModificado;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (modo == EmpresaExpedienteModo.consulta) {
      return RisegFormSection(
        title: l10n.empresaSeccionDatosGeneralesTitulo,
        grid: true,
        children: [
          CampoConsulta(label: l10n.empresaCampoCodigo, value: empresa.codigo),
          CampoConsulta(label: l10n.empresaCampoRazonSocial, value: empresa.razonSocial),
          CampoConsulta(label: l10n.empresaCampoNombreComercial, value: empresa.nombreComercial),
          CampoConsulta(label: l10n.empresaCampoRfc, value: empresa.rfc),
          CampoConsulta(label: l10n.empresaCampoRepresentanteLegal, value: empresa.representanteLegal),
          CampoConsulta(label: l10n.empresaCampoEslogan, value: empresa.eslogan),
        ],
      );
    }

    final errorRfc = errorParaCampo(errores, CampoExpediente.rfc);

    return RisegFormSection(
      title: l10n.empresaSeccionDatosGeneralesTitulo,
      grid: true,
      children: [
        CampoConsulta(label: l10n.empresaCampoCodigo, value: empresa.codigo),
        RisegTextField(
          label: l10n.empresaCampoNombreComercial,
          controller: controllers.nombreComercial,
          enabled: habilitado,
          onChanged: (_) => onCampoModificado(),
        ),
        RisegTextField(
          label: l10n.empresaCampoRazonSocial,
          controller: controllers.razonSocial,
          enabled: habilitado,
          onChanged: (_) => onCampoModificado(),
        ),
        RisegTextField(
          label: l10n.empresaCampoRfc,
          controller: controllers.rfc,
          enabled: habilitado,
          errorText: errorRfc == null ? null : mensajeErrorCampoExpediente(l10n, errorRfc),
          onChanged: (_) => onCampoModificado(),
        ),
        RisegTextField(
          label: l10n.empresaCampoRepresentanteLegal,
          controller: controllers.representanteLegal,
          enabled: habilitado,
          onChanged: (_) => onCampoModificado(),
        ),
        RisegTextField(
          label: l10n.empresaCampoEslogan,
          controller: controllers.eslogan,
          enabled: habilitado,
          onChanged: (_) => onCampoModificado(),
        ),
      ],
    );
  }
}
