import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/servicio_expediente_form_controllers.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/servicio_expediente_state.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';

/// Sección "Referencias" de Servicio — referencia comercial (típicamente
/// un número de cotización hoy, sin acoplarse a ese origen) y referencia
/// contractual, ambas opcionales. Comparte el mismo ciclo de
/// Editar/Guardar que `ServicioDatosGeneralesSection` (Etapa 4F.2,
/// resolución B) — widget propio solo para que el expediente quede
/// modular, no porque tenga su propia acción de guardado.
class ServicioReferenciasSection extends StatelessWidget {
  const ServicioReferenciasSection({
    required this.modo,
    required this.servicio,
    required this.controllers,
    required this.habilitado,
    required this.onCampoModificado,
    super.key,
  });

  final ServicioExpedienteModo modo;
  final ServicioData servicio;
  final ServicioDatosGeneralesControllers controllers;
  final bool habilitado;
  final VoidCallback onCampoModificado;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (modo == ServicioExpedienteModo.consulta) {
      return RisegFormSection(
        title: l10n.servicioSeccionReferenciasTitulo,
        grid: true,
        children: [
          CampoConsulta(label: l10n.servicioCampoReferenciaComercial, value: servicio.referenciaComercial),
          CampoConsulta(label: l10n.servicioCampoReferenciaContractual, value: servicio.referenciaContractual),
        ],
      );
    }

    return RisegFormSection(
      title: l10n.servicioSeccionReferenciasTitulo,
      grid: true,
      children: [
        RisegTextField(
          label: l10n.servicioCampoReferenciaComercial,
          controller: controllers.referenciaComercial,
          enabled: habilitado,
          onChanged: (_) => onCampoModificado(),
        ),
        RisegTextField(
          label: l10n.servicioCampoReferenciaContractual,
          controller: controllers.referenciaContractual,
          enabled: habilitado,
          onChanged: (_) => onCampoModificado(),
        ),
      ],
    );
  }
}
