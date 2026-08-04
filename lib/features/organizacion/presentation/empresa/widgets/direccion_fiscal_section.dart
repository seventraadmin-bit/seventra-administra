import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/empresa_expediente_errors.dart';
import 'package:riseg_one/features/organizacion/presentation/empresa/campo_error_l10n.dart';
import 'package:riseg_one/features/organizacion/presentation/empresa/empresa_expediente_form_controllers.dart';
import 'package:riseg_one/features/organizacion/presentation/empresa/empresa_expediente_state.dart';

import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';

/// Sección "Dirección fiscal". Si no se ha capturado ninguna dirección
/// ([direccion] nulo), la consulta muestra todos los campos como
/// pendientes — nunca oculta la sección por completo, para que el
/// usuario sepa que la puede capturar entrando a edición.
class DireccionFiscalSection extends StatelessWidget {
  const DireccionFiscalSection({
    required this.modo,
    required this.direccion,
    required this.controllers,
    required this.habilitado,
    required this.errores,
    required this.onCampoModificado,
    super.key,
  });

  final EmpresaExpedienteModo modo;
  final DireccionData? direccion;
  final DireccionFiscalControllers controllers;
  final bool habilitado;
  final List<ErrorCampoExpediente> errores;
  final VoidCallback onCampoModificado;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (modo == EmpresaExpedienteModo.consulta) {
      return RisegFormSection(
        title: l10n.empresaSeccionDireccionFiscalTitulo,
        children: [
          CampoConsulta(label: l10n.empresaCampoCalle, value: direccion?.calle),
          CampoConsulta(label: l10n.empresaCampoNumeroExterior, value: direccion?.numeroExterior),
          CampoConsulta(label: l10n.empresaCampoNumeroInterior, value: direccion?.numeroInterior),
          CampoConsulta(label: l10n.empresaCampoColonia, value: direccion?.colonia),
          CampoConsulta(label: l10n.empresaCampoMunicipioAlcaldia, value: direccion?.municipioAlcaldia),
          CampoConsulta(label: l10n.empresaCampoCiudadLocalidad, value: direccion?.ciudadLocalidad),
          CampoConsulta(label: l10n.empresaCampoEstadoDireccion, value: direccion?.estado),
          CampoConsulta(label: l10n.empresaCampoCodigoPostal, value: direccion?.codigoPostal),
          CampoConsulta(label: l10n.empresaCampoPais, value: direccion?.pais),
          CampoConsulta(label: l10n.empresaCampoReferencias, value: direccion?.referencias),
        ],
      );
    }

    String? errorDe(CampoExpediente campo) {
      final error = errorParaCampo(errores, campo);
      return error == null ? null : mensajeErrorCampoExpediente(l10n, error);
    }

    return RisegFormSection(
      title: l10n.empresaSeccionDireccionFiscalTitulo,
      children: [
        RisegTextField(
          label: l10n.empresaCampoCalle,
          controller: controllers.calle,
          enabled: habilitado,
          errorText: errorDe(CampoExpediente.calle),
          onChanged: (_) => onCampoModificado(),
        ),
        RisegTextField(
          label: l10n.empresaCampoNumeroExterior,
          controller: controllers.numeroExterior,
          enabled: habilitado,
          errorText: errorDe(CampoExpediente.numeroExterior),
          onChanged: (_) => onCampoModificado(),
        ),
        RisegTextField(
          label: l10n.empresaCampoNumeroInterior,
          controller: controllers.numeroInterior,
          enabled: habilitado,
          onChanged: (_) => onCampoModificado(),
        ),
        RisegTextField(
          label: l10n.empresaCampoColonia,
          controller: controllers.colonia,
          enabled: habilitado,
          errorText: errorDe(CampoExpediente.colonia),
          onChanged: (_) => onCampoModificado(),
        ),
        RisegTextField(
          label: l10n.empresaCampoMunicipioAlcaldia,
          controller: controllers.municipioAlcaldia,
          enabled: habilitado,
          errorText: errorDe(CampoExpediente.municipioAlcaldia),
          onChanged: (_) => onCampoModificado(),
        ),
        RisegTextField(
          label: l10n.empresaCampoCiudadLocalidad,
          controller: controllers.ciudadLocalidad,
          enabled: habilitado,
          onChanged: (_) => onCampoModificado(),
        ),
        RisegTextField(
          label: l10n.empresaCampoEstadoDireccion,
          controller: controllers.estado,
          enabled: habilitado,
          errorText: errorDe(CampoExpediente.estado),
          onChanged: (_) => onCampoModificado(),
        ),
        RisegTextField(
          label: l10n.empresaCampoCodigoPostal,
          controller: controllers.codigoPostal,
          enabled: habilitado,
          keyboardType: TextInputType.number,
          errorText: errorDe(CampoExpediente.codigoPostal),
          onChanged: (_) => onCampoModificado(),
        ),
        RisegTextField(
          label: l10n.empresaCampoPais,
          controller: controllers.pais,
          enabled: habilitado,
          onChanged: (_) => onCampoModificado(),
        ),
        RisegTextField(
          label: l10n.empresaCampoReferencias,
          controller: controllers.referencias,
          enabled: habilitado,
          onChanged: (_) => onCampoModificado(),
        ),
      ],
    );
  }
}
