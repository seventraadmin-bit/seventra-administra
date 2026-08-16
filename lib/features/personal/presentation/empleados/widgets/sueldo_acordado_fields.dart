import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_con_vigencia.dart';

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

/// Busca una `LineaComercialConVigencia` por el id de su `linea` dentro
/// de una lista ya cargada — mismo criterio que `buscarServicioPorId`.
LineaComercialConVigencia? buscarLineaComercialPorId(List<LineaComercialConVigencia> lineas, String? id) {
  if (id == null) return null;
  for (final l in lineas) {
    if (l.linea.id == id) return l;
  }
  return null;
}

/// El texto legible de una línea comercial para el selector de perfil
/// — "Elemento Operativo · 24x24 · 2 posiciones" (Etapa 15, rediseño de
/// "Condiciones de Personal"). Usa la vigencia vigente si existe; si la
/// línea solo tiene vigencias programadas, la más próxima (mismo
/// criterio que el resto de la UI de Configuración comercial).
String etiquetaLineaComercial(AppLocalizations l10n, LineaComercialConVigencia linea) {
  final fila = linea.vigenciaActual ?? (linea.vigenciasProgramadas.isEmpty ? null : linea.vigenciasProgramadas.first);
  return l10n.empleadoLineaComercialOpcion(
    linea.puestoNombre,
    linea.modalidadTurnoNombre,
    fila?.cantidadElementos ?? 0,
  );
}

/// Precarga los controladores de "Sueldo acordado"/"Bono acordado" con
/// el sueldo/bono de referencia de la línea comercial elegida (Etapa
/// 15, rediseño de "Condiciones de Personal" — reemplaza el sueldo
/// global del Servicio) — vacíos si la línea no tiene referencia
/// capturada o si no hay ninguna línea elegida, para que el campo quede
/// editable y el usuario pueda escribir una excepción manual sin que
/// nada lo bloquee.
void precargarSueldoAcordado({
  required LineaComercialConVigencia? linea,
  required TextEditingController sueldoController,
  required TextEditingController bonoController,
}) {
  sueldoController.text = pesosDesdeCentavosParaEditar(linea?.vigenciaActual?.sueldoMensualReferenciaPersonal);
  bonoController.text = pesosDesdeCentavosParaEditar(linea?.vigenciaActual?.bonoMensualReferenciaPersonal);
}

/// Campos "Sueldo acordado"/"Bono acordado" de una asignación a Servicio
/// (Etapa 15, rediseño de "Condiciones de Personal") — cuando hay una
/// línea comercial elegida, muestra su sueldo/bono de referencia (o
/// "Sin configurar") arriba de cada campo editable; cuando el Servicio
/// no tiene ninguna línea comercial vigente (caso real, ver
/// `resolverLineaComercialAsignacion`), omite la referencia pero el
/// campo sigue siendo editable — de lo contrario no habría forma de
/// capturar la excepción manual que ese caso exige. Deja explícito que
/// no es una edición de la línea, solo una excepción individual.
/// Reutilizado por Asignar/Cambiar Servicio y por el Alta de Personal
/// con adscripción a Servicio.
class SueldoAcordadoFields extends StatelessWidget {
  const SueldoAcordadoFields({
    required this.linea,
    required this.sueldoController,
    required this.bonoController,
    this.errorSueldo,
    this.errorBono,
    super.key,
  });

  final LineaComercialConVigencia? linea;
  final TextEditingController sueldoController;
  final TextEditingController bonoController;
  final String? errorSueldo;
  final String? errorBono;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final formato = NumberFormat.currency(locale: 'es_MX', symbol: r'$');
    final sueldoRef = linea?.vigenciaActual?.sueldoMensualReferenciaPersonal;
    final bonoRef = linea?.vigenciaActual?.bonoMensualReferenciaPersonal;

    Widget referencia(String etiqueta, int? centavos) {
      return Text(
        '$etiqueta: ${centavos == null ? l10n.servicioCondicionesPersonalValorSinConfigurar : formato.format(centavos / 100)}',
        style: AppTypography.caption.copyWith(color: colors.textMuted),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (linea != null) ...[
          referencia(l10n.empleadoCampoSueldoReferenciaPerfil, sueldoRef),
          const SizedBox(height: AppSpacing.xs),
        ],
        RisegTextField(
          label: l10n.empleadoCampoSueldoAcordado,
          controller: sueldoController,
          errorText: errorSueldo,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: AppSpacing.md),
        if (linea != null) ...[
          referencia(l10n.empleadoCampoBonoReferenciaPerfil, bonoRef),
          const SizedBox(height: AppSpacing.xs),
        ],
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
