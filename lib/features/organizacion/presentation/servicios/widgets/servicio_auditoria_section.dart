import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';

final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Sección "Auditoría" de Servicio — siempre de solo lectura,
/// independiente del modo consulta/edición. Widget propio desde la
/// Etapa 4F.2 para que el expediente crezca agregando secciones sin
/// reestructurar las existentes.
class ServicioAuditoriaSection extends StatelessWidget {
  const ServicioAuditoriaSection({required this.servicio, super.key});

  final ServicioData servicio;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return RisegFormSection(
      title: l10n.servicioSeccionAuditoriaTitulo,
      children: [
        CampoConsulta(label: l10n.servicioAuditoriaCreado, value: _formatoFechaHora.format(servicio.createdAt)),
        CampoConsulta(label: l10n.servicioAuditoriaActualizado, value: _formatoFechaHora.format(servicio.updatedAt)),
      ],
    );
  }
}
