import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/puesto_errors.dart';
import 'package:riseg_one/features/organizacion/presentation/puestos/campo_error_puesto_l10n.dart';
import 'package:riseg_one/features/organizacion/presentation/puestos/puesto_expediente_form_controllers.dart';
import 'package:riseg_one/features/organizacion/presentation/puestos/puesto_expediente_state.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy HH:mm');

/// Sección "Datos generales" de Puesto — única sección del expediente
/// (sin sub-entidades). Las fechas de auditoría (creación/última
/// actualización) se muestran de solo lectura en ambos modos, igual que
/// el código — nunca son parte de la entrada del formulario.
class PuestoDatosGeneralesSection extends StatelessWidget {
  const PuestoDatosGeneralesSection({
    required this.modo,
    required this.puesto,
    required this.areas,
    required this.controllers,
    required this.habilitado,
    required this.errores,
    required this.onAreaCambiada,
    required this.onTipoCambiado,
    required this.onCampoModificado,
    super.key,
  });

  final PuestoExpedienteModo modo;
  final PuestoData puesto;
  final List<AreaData> areas;
  final PuestoDatosGeneralesControllers controllers;
  final bool habilitado;
  final List<ErrorCampoPuesto> errores;
  final ValueChanged<String?> onAreaCambiada;
  final ValueChanged<TipoPuesto?> onTipoCambiado;
  final VoidCallback onCampoModificado;

  String? _nombreArea(String areaId) {
    for (final area in areas) {
      if (area.id == areaId) return area.nombre;
    }
    return null;
  }

  String _nombreTipo(AppLocalizations l10n, String tipo) {
    return tipo == TipoPuesto.administrativo.name ? l10n.puestoTipoAdministrativo : l10n.puestoTipoOperativo;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final camposAuditoria = [
      CampoConsulta(label: l10n.puestoCampoFechaCreacion, value: _formatoFecha.format(puesto.createdAt)),
      CampoConsulta(label: l10n.puestoCampoUltimaActualizacion, value: _formatoFecha.format(puesto.updatedAt)),
    ];

    if (modo == PuestoExpedienteModo.consulta) {
      return RisegFormSection(
        title: l10n.puestoSeccionDatosGeneralesTitulo,
        children: [
          CampoConsulta(label: l10n.puestoCampoCodigo, value: puesto.codigo),
          CampoConsulta(label: l10n.puestoCampoNombre, value: puesto.nombre),
          CampoConsulta(label: l10n.puestoCampoArea, value: _nombreArea(puesto.areaId)),
          CampoConsulta(label: l10n.puestoCampoTipo, value: _nombreTipo(l10n, puesto.tipo)),
          CampoConsulta(label: l10n.puestoCampoNivelJerarquico, value: '${puesto.nivelJerarquico}'),
          CampoConsulta(label: l10n.puestoCampoDescripcion, value: puesto.descripcion),
          ...camposAuditoria,
        ],
      );
    }

    final errorArea = errorParaCampoPuesto(errores, CampoPuesto.area);
    final errorTipo = errorParaCampoPuesto(errores, CampoPuesto.tipo);
    final errorNivel = errorParaCampoPuesto(errores, CampoPuesto.nivelJerarquico);

    return RisegFormSection(
      title: l10n.puestoSeccionDatosGeneralesTitulo,
      children: [
        CampoConsulta(label: l10n.puestoCampoCodigo, value: puesto.codigo),
        RisegTextField(
          label: l10n.puestoCampoNombre,
          controller: controllers.nombre,
          enabled: habilitado,
          errorText: errorParaCampoPuesto(errores, CampoPuesto.nombre) == null
              ? null
              : mensajeErrorCampoPuesto(l10n, errorParaCampoPuesto(errores, CampoPuesto.nombre)!),
          onChanged: (_) => onCampoModificado(),
        ),
        RisegSelect<String>(
          label: l10n.puestoCampoArea,
          value: controllers.areaId,
          enabled: habilitado,
          errorText: errorArea == null ? null : mensajeErrorCampoPuesto(l10n, errorArea),
          items: [for (final area in areas) RisegSelectItem(value: area.id, label: area.nombre)],
          onChanged: onAreaCambiada,
        ),
        RisegSelect<TipoPuesto>(
          label: l10n.puestoCampoTipo,
          value: controllers.tipo,
          enabled: habilitado,
          errorText: errorTipo == null ? null : mensajeErrorCampoPuesto(l10n, errorTipo),
          items: [
            RisegSelectItem(value: TipoPuesto.operativo, label: l10n.puestoTipoOperativo),
            RisegSelectItem(value: TipoPuesto.administrativo, label: l10n.puestoTipoAdministrativo),
          ],
          onChanged: onTipoCambiado,
        ),
        RisegTextField(
          label: l10n.puestoCampoNivelJerarquico,
          controller: controllers.nivelJerarquico,
          enabled: habilitado,
          helperText: l10n.puestoAyudaNivelJerarquico,
          errorText: errorNivel == null ? null : mensajeErrorCampoPuesto(l10n, errorNivel),
          keyboardType: TextInputType.number,
          onChanged: (_) => onCampoModificado(),
        ),
        RisegTextField(
          label: l10n.puestoCampoDescripcion,
          controller: controllers.descripcion,
          enabled: habilitado,
          onChanged: (_) => onCampoModificado(),
        ),
        ...camposAuditoria,
      ],
    );
  }
}
