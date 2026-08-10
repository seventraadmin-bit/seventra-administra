import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';

import 'servicio_configuracion_comercial_section.dart' show formatoCentavos;

/// Sección "Condiciones de Personal" del expediente de Servicio (ajuste
/// funcional final de la Etapa 6B) — sueldo/bono mensual de referencia
/// que se precargan al asignar personal a este Servicio
/// (`AsignarEmpleadoServicioUseCase`/`CambiarServicioEmpleadoUseCase`/
/// `CrearEmpleadoUseCase`). Deliberadamente simple — un solo diálogo con
/// dos campos, nunca una pantalla propia (Resolución explícita de
/// Marlon: "no quiero un formulario complejo ni una nueva pantalla").
///
/// Ambos valores pueden estar sin configurar; si falta el sueldo, la
/// sección lo deja explícito ("Condiciones salariales sin configurar")
/// en vez de mostrar campos vacíos — mismo criterio de claridad que el
/// mensaje de error correspondiente en los diálogos de asignación.
class ServicioCondicionesPersonalSection extends StatelessWidget {
  const ServicioCondicionesPersonalSection({
    required this.servicio,
    required this.deshabilitado,
    required this.onEditar,
    super.key,
  });

  final ServicioData servicio;
  final bool deshabilitado;
  final VoidCallback onEditar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final sueldo = servicio.sueldoMensualReferenciaPersonal;
    final bono = servicio.bonoMensualReferenciaPersonal;

    return RisegFormSection(
      title: l10n.servicioSeccionCondicionesPersonalTitulo,
      children: [
        if (sueldo == null)
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.servicioCondicionesPersonalSinConfigurar,
                  style: AppTypography.body.copyWith(color: colors.textMuted, fontStyle: FontStyle.italic),
                ),
              ),
              TextButton.icon(
                key: const Key('servicio_condiciones_personal_boton_editar'),
                onPressed: deshabilitado ? null : onEditar,
                icon: const Icon(Icons.add_circle_outline, size: 16),
                label: Text(l10n.servicioVinculacionBotonAsignar),
              ),
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CampoConsulta(label: l10n.servicioCampoSueldoReferencia, value: formatoCentavos(sueldo)),
                    const SizedBox(height: AppSpacing.sm),
                    CampoConsulta(
                      label: l10n.servicioCampoBonoReferencia,
                      value: bono == null ? l10n.servicioCondicionesPersonalValorSinConfigurar : formatoCentavos(bono),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('servicio_condiciones_personal_boton_editar'),
                tooltip: l10n.servicioVinculacionBotonEditar,
                icon: const Icon(Icons.edit_outlined, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: deshabilitado ? null : onEditar,
              ),
            ],
          ),
      ],
    );
  }
}
