import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/direccion_controllers.dart';
import 'package:riseg_one/features/organizacion/presentation/sucursales/sucursal_expediente_state.dart';

/// Sección "Dirección principal" de Sucursal — mismo patrón que la
/// dirección fiscal de Empresa, pero los errores son directamente
/// `ErrorCampoDireccion` de `core/validation` (sin envoltorio propio, ya
/// que Sucursal no combina dirección con otros campos en un único enum
/// plano como sí lo hace Empresa con RFC/correo/sitio web).
class DireccionPrincipalSection extends StatelessWidget {
  const DireccionPrincipalSection({
    required this.modo,
    required this.direccion,
    required this.controllers,
    required this.habilitado,
    required this.errores,
    required this.onCampoModificado,
    super.key,
  });

  final SucursalExpedienteModo modo;
  final DireccionData? direccion;
  final DireccionControllers controllers;
  final bool habilitado;
  final List<ErrorCampoDireccion> errores;
  final VoidCallback onCampoModificado;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (modo == SucursalExpedienteModo.consulta) {
      return RisegFormSection(
        title: l10n.sucursalSeccionDireccionPrincipalTitulo,
        grid: true,
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

    String? errorDe(CampoDireccion campo) {
      final error = errorParaCampoDireccion(errores, campo);
      if (error == null) return null;
      return error.codigo == CodigoErrorCampoDireccion.formatoInvalido
          ? l10n.empresaErrorCodigoPostalFormato
          : l10n.empresaErrorCampoRequerido;
    }

    return RisegFormSection(
      title: l10n.sucursalSeccionDireccionPrincipalTitulo,
      grid: true,
      children: [
        RisegTextField(
          label: l10n.empresaCampoCalle,
          controller: controllers.calle,
          enabled: habilitado,
          errorText: errorDe(CampoDireccion.calle),
          onChanged: (_) => onCampoModificado(),
        ),
        RisegTextField(
          label: l10n.empresaCampoNumeroExterior,
          controller: controllers.numeroExterior,
          enabled: habilitado,
          errorText: errorDe(CampoDireccion.numeroExterior),
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
          errorText: errorDe(CampoDireccion.colonia),
          onChanged: (_) => onCampoModificado(),
        ),
        RisegTextField(
          label: l10n.empresaCampoMunicipioAlcaldia,
          controller: controllers.municipioAlcaldia,
          enabled: habilitado,
          errorText: errorDe(CampoDireccion.municipioAlcaldia),
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
          errorText: errorDe(CampoDireccion.estado),
          onChanged: (_) => onCampoModificado(),
        ),
        RisegTextField(
          label: l10n.empresaCampoCodigoPostal,
          controller: controllers.codigoPostal,
          enabled: habilitado,
          keyboardType: TextInputType.number,
          errorText: errorDe(CampoDireccion.codigoPostal),
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
