import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/catalogo_repository.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/servicio_expediente_form_controllers.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/servicio_expediente_state.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Sección "Datos generales" de Servicio — código y fechas de auditoría
/// siempre de solo lectura (mismo patrón que Cliente/Puesto); nombre,
/// Tipo de Servicio, fecha de inicio y observaciones editables.
class ServicioDatosGeneralesSection extends StatelessWidget {
  const ServicioDatosGeneralesSection({
    required this.modo,
    required this.servicio,
    required this.controllers,
    required this.tiposServicio,
    required this.habilitado,
    required this.errorNombreRequerido,
    required this.errorTipoServicio,
    required this.errorFechaInicioRequerida,
    required this.onCampoModificado,
    required this.onTipoServicioCambiado,
    required this.onFechaInicioCambiado,
    super.key,
  });

  final ServicioExpedienteModo modo;
  final ServicioData servicio;
  final ServicioDatosGeneralesControllers controllers;
  final List<CatalogoItem> tiposServicio;
  final bool habilitado;
  final bool errorNombreRequerido;
  final String? errorTipoServicio;
  final bool errorFechaInicioRequerida;
  final VoidCallback onCampoModificado;

  /// Distintos de `onCampoModificado`: `RisegSelect`/`RisegDateField` no
  /// están respaldados por un `TextEditingController` propio, así que su
  /// valor mostrado solo se actualiza si la pantalla hace su propio
  /// `setState` en cada cambio — nunca alcanza con la bandera de
  /// "cambios sin guardar" del controlador (esa solo dispara un
  /// re-render la primera vez). Mismo patrón que
  /// `SucursalExpedienteScreen._onTipoCambiado`.
  final ValueChanged<String?> onTipoServicioCambiado;
  final ValueChanged<DateTime> onFechaInicioCambiado;

  String _nombreTipoServicio(String id) {
    for (final tipo in tiposServicio) {
      if (tipo.id == id) return tipo.nombre;
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final camposAuditoria = [
      CampoConsulta(label: l10n.servicioAuditoriaCreado, value: _formatoFechaHora.format(servicio.createdAt)),
      CampoConsulta(label: l10n.servicioAuditoriaActualizado, value: _formatoFechaHora.format(servicio.updatedAt)),
    ];

    if (modo == ServicioExpedienteModo.consulta) {
      return RisegFormSection(
        title: l10n.servicioSeccionDatosGeneralesTitulo,
        children: [
          CampoConsulta(label: l10n.serviciosColumnaCodigo, value: servicio.codigo),
          CampoConsulta(label: l10n.servicioCampoNombre, value: servicio.nombre),
          CampoConsulta(label: l10n.servicioCampoTipoServicio, value: _nombreTipoServicio(servicio.tipoServicioId)),
          CampoConsulta(label: l10n.servicioCampoFechaInicio, value: _formatoFecha.format(servicio.fechaInicio)),
          CampoConsulta(label: l10n.servicioCampoObservaciones, value: servicio.observaciones),
          ...camposAuditoria,
        ],
      );
    }

    return RisegFormSection(
      title: l10n.servicioSeccionDatosGeneralesTitulo,
      children: [
        CampoConsulta(label: l10n.serviciosColumnaCodigo, value: servicio.codigo),
        RisegTextField(
          label: l10n.servicioCampoNombre,
          controller: controllers.nombre,
          enabled: habilitado,
          errorText: errorNombreRequerido ? l10n.servicioErrorNombreRequerido : null,
          onChanged: (_) => onCampoModificado(),
        ),
        RisegSelect<String>(
          label: l10n.servicioCampoTipoServicio,
          value: controllers.tipoServicioId.isEmpty ? null : controllers.tipoServicioId,
          enabled: habilitado,
          errorText: errorTipoServicio,
          items: [for (final tipo in tiposServicio) RisegSelectItem(value: tipo.id, label: tipo.nombre)],
          onChanged: onTipoServicioCambiado,
        ),
        RisegDateField(
          label: l10n.servicioCampoFechaInicio,
          value: controllers.fechaInicio,
          enabled: habilitado,
          errorText: errorFechaInicioRequerida ? l10n.servicioErrorFechaInicioRequerida : null,
          onChanged: onFechaInicioCambiado,
        ),
        RisegTextField(
          label: l10n.servicioCampoObservaciones,
          controller: controllers.observaciones,
          enabled: habilitado,
          onChanged: (_) => onCampoModificado(),
        ),
        ...camposAuditoria,
      ],
    );
  }
}
