import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/catalogo_repository.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';
import 'package:riseg_one/features/organizacion/presentation/sucursales/sucursal_expediente_form_controllers.dart';
import 'package:riseg_one/features/organizacion/presentation/sucursales/sucursal_expediente_state.dart';

/// Sección "Datos generales" de Sucursal — el código siempre se muestra
/// de solo lectura (autogenerado). `estadoOperativo` no aparece aquí:
/// es una acción de botón independiente del formulario, ver
/// `SucursalExpedienteScreen`.
class SucursalDatosGeneralesSection extends StatelessWidget {
  const SucursalDatosGeneralesSection({
    required this.modo,
    required this.sucursal,
    required this.tipos,
    required this.controllers,
    required this.habilitado,
    required this.errorTipoRequerido,
    required this.onTipoCambiado,
    required this.onCampoModificado,
    super.key,
  });

  final SucursalExpedienteModo modo;
  final SucursalData sucursal;
  final List<CatalogoItem> tipos;
  final SucursalDatosGeneralesControllers controllers;
  final bool habilitado;
  final bool errorTipoRequerido;
  final ValueChanged<String?> onTipoCambiado;
  final VoidCallback onCampoModificado;

  String? _nombreTipo(String tipoSucursalId) {
    for (final tipo in tipos) {
      if (tipo.id == tipoSucursalId) return tipo.nombre;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (modo == SucursalExpedienteModo.consulta) {
      return RisegFormSection(
        title: l10n.sucursalSeccionDatosGeneralesTitulo,
        grid: true,
        children: [
          CampoConsulta(label: l10n.sucursalCampoCodigo, value: sucursal.codigo),
          CampoConsulta(label: l10n.sucursalCampoNombre, value: sucursal.nombre),
          CampoConsulta(label: l10n.sucursalCampoTipo, value: _nombreTipo(sucursal.tipoSucursalId)),
        ],
      );
    }

    return RisegFormSection(
      title: l10n.sucursalSeccionDatosGeneralesTitulo,
      grid: true,
      children: [
        CampoConsulta(label: l10n.sucursalCampoCodigo, value: sucursal.codigo),
        RisegTextField(
          label: l10n.sucursalCampoNombre,
          controller: controllers.nombre,
          enabled: habilitado,
          onChanged: (_) => onCampoModificado(),
        ),
        RisegSelect<String>(
          label: l10n.sucursalCampoTipo,
          value: controllers.tipoSucursalId,
          enabled: habilitado,
          errorText: errorTipoRequerido ? l10n.sucursalAltaErrorTipoRequerido : null,
          items: [for (final tipo in tipos) RisegSelectItem(value: tipo.id, label: tipo.nombre)],
          onChanged: onTipoCambiado,
        ),
      ],
    );
  }
}
