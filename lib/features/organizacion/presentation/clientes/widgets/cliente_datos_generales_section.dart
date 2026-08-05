import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/presentation/clientes/cliente_expediente_form_controllers.dart';
import 'package:riseg_one/features/organizacion/presentation/clientes/cliente_expediente_state.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy HH:mm');

/// Sección "Datos generales" de Cliente — código y fechas de auditoría
/// siempre de solo lectura (mismo patrón que Puesto), nombre comercial y
/// observaciones editables.
class ClienteDatosGeneralesSection extends StatelessWidget {
  const ClienteDatosGeneralesSection({
    required this.modo,
    required this.cliente,
    required this.controllers,
    required this.habilitado,
    required this.errorNombreComercialRequerido,
    required this.onCampoModificado,
    super.key,
  });

  final ClienteExpedienteModo modo;
  final ClienteData cliente;
  final ClienteDatosGeneralesControllers controllers;
  final bool habilitado;
  final bool errorNombreComercialRequerido;
  final VoidCallback onCampoModificado;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final camposAuditoria = [
      CampoConsulta(label: l10n.clienteCampoFechaCreacion, value: _formatoFecha.format(cliente.createdAt)),
      CampoConsulta(label: l10n.clienteCampoUltimaActualizacion, value: _formatoFecha.format(cliente.updatedAt)),
    ];

    if (modo == ClienteExpedienteModo.consulta) {
      return RisegFormSection(
        title: l10n.clienteSeccionDatosGeneralesTitulo,
        children: [
          CampoConsulta(label: l10n.clienteCampoCodigo, value: cliente.codigo),
          CampoConsulta(label: l10n.clienteCampoNombreComercial, value: cliente.nombreComercial),
          CampoConsulta(label: l10n.clienteCampoObservaciones, value: cliente.observaciones),
          ...camposAuditoria,
        ],
      );
    }

    return RisegFormSection(
      title: l10n.clienteSeccionDatosGeneralesTitulo,
      children: [
        CampoConsulta(label: l10n.clienteCampoCodigo, value: cliente.codigo),
        RisegTextField(
          label: l10n.clienteCampoNombreComercial,
          controller: controllers.nombreComercial,
          enabled: habilitado,
          errorText: errorNombreComercialRequerido ? l10n.clienteErrorNombreComercialRequerido : null,
          onChanged: (_) => onCampoModificado(),
        ),
        RisegTextField(
          label: l10n.clienteCampoObservaciones,
          controller: controllers.observaciones,
          enabled: habilitado,
          onChanged: (_) => onCampoModificado(),
        ),
        ...camposAuditoria,
      ],
    );
  }
}
