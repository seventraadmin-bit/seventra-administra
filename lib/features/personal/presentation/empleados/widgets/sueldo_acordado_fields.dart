import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';

import 'crear_empleado_dialog.dart' show pesosDesdeCentavosParaEditar;

/// Busca el `ServicioData` de un `id` dentro de una lista ya cargada de
/// `ServicioListItem` — sin depender de `package:collection` para un
/// solo `firstWhereOrNull`.
ServicioData? buscarServicioPorId(List<ServicioListItem> servicios, String? id) {
  if (id == null) return null;
  for (final item in servicios) {
    if (item.servicio.id == id) return item.servicio;
  }
  return null;
}

/// Precarga los controladores de "Sueldo acordado"/"Bono acordado" con
/// el sueldo/bono de referencia del Servicio elegido (Etapa 6B) — vacíos
/// si el Servicio no tiene referencia capturada, para que el campo
/// quede editable y el usuario pueda escribir una excepción manual sin
/// que nada lo bloquee (Resolución explícita de Marlon: "no quiero
/// bloquear innecesariamente cuando el usuario sí conoce el sueldo").
void precargarSueldoAcordado({
  required ServicioData? servicio,
  required TextEditingController sueldoController,
  required TextEditingController bonoController,
}) {
  sueldoController.text = pesosDesdeCentavosParaEditar(servicio?.sueldoMensualReferenciaPersonal);
  bonoController.text = pesosDesdeCentavosParaEditar(servicio?.bonoMensualReferenciaPersonal);
}

/// Campos "Sueldo acordado"/"Bono acordado" de una asignación a Servicio
/// (Etapa 6B) — muestra el sueldo/bono de referencia del Servicio
/// elegido (o "Sin configurar") y un campo editable para el valor que
/// quedará acordado en esa asignación específica; deja explícito que no
/// es una edición del Servicio, solo una excepción individual
/// (Resolución explícita de Marlon). Reutilizado por Asignar/Cambiar
/// Servicio y por el Alta de Personal con adscripción a Servicio.
class SueldoAcordadoFields extends StatelessWidget {
  const SueldoAcordadoFields({
    required this.servicio,
    required this.sueldoController,
    required this.bonoController,
    this.errorSueldo,
    this.errorBono,
    super.key,
  });

  final ServicioData? servicio;
  final TextEditingController sueldoController;
  final TextEditingController bonoController;
  final String? errorSueldo;
  final String? errorBono;

  @override
  Widget build(BuildContext context) {
    if (servicio == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final formato = NumberFormat.currency(locale: 'es_MX', symbol: r'$');
    final sueldoRef = servicio!.sueldoMensualReferenciaPersonal;
    final bonoRef = servicio!.bonoMensualReferenciaPersonal;

    Widget referencia(String etiqueta, int? centavos) {
      return Text(
        '$etiqueta: ${centavos == null ? l10n.servicioCondicionesPersonalValorSinConfigurar : formato.format(centavos / 100)}',
        style: AppTypography.caption.copyWith(color: colors.textMuted),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        referencia(l10n.empleadoCampoSueldoReferenciaServicio, sueldoRef),
        const SizedBox(height: AppSpacing.xs),
        RisegTextField(
          label: l10n.empleadoCampoSueldoAcordado,
          controller: sueldoController,
          errorText: errorSueldo,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: AppSpacing.md),
        referencia(l10n.empleadoCampoBonoReferenciaServicio, bonoRef),
        const SizedBox(height: AppSpacing.xs),
        RisegTextField(
          label: l10n.empleadoCampoBonoAcordado,
          controller: bonoController,
          errorText: errorBono,
          keyboardType: TextInputType.number,
        ),
      ],
    );
  }
}
