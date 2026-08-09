import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/corregir_empleado_usecase.dart';

import '../../../../organizacion/organizacion_providers.dart';
import '../../../personal_providers.dart';
import 'crear_empleado_dialog.dart' show empleadoEstadoCivilLabel, empleadoNivelEstudiosLabel, empleadoSexoLabel;

int? _enteroDesdeTexto(String texto) {
  final normalizado = texto.trim();
  if (normalizado.isEmpty) return null;
  return int.tryParse(normalizado);
}

/// Diálogo "Corregir datos del empleado" (Etapa 5A) — mismos campos que
/// `mostrarDialogoCrearEmpleado`, ya precargados. Nunca toca
/// `codigoEmpleado` ni `estatus` (vía `CambiarEstatusEmpleadoUseCase`,
/// acción separada).
///
/// Devuelve `true` si la corrección tuvo éxito.
Future<bool> mostrarDialogoCorregirEmpleado(BuildContext context, WidgetRef ref, EmpleadoData empleado) async {
  final l10n = AppLocalizations.of(context)!;

  final nombresController = TextEditingController(text: empleado.nombres);
  final apellidoPaternoController = TextEditingController(text: empleado.apellidoPaterno);
  final apellidoMaternoController = TextEditingController(text: empleado.apellidoMaterno ?? '');
  SexoEmpleado sexo = SexoEmpleado.values.byName(empleado.sexo);
  DateTime? fechaNacimiento = empleado.fechaNacimiento;
  final curpController = TextEditingController(text: empleado.curp);
  final rfcController = TextEditingController(text: empleado.rfc);
  final codigoPostalFiscalController = TextEditingController(text: empleado.codigoPostalFiscal ?? '');
  final nssController = TextEditingController(text: empleado.nss);
  EstadoCivilEmpleado estadoCivil = EstadoCivilEmpleado.values.byName(empleado.estadoCivil);
  final nacionalidadController = TextEditingController(text: empleado.nacionalidad);

  final telefonoController = TextEditingController(text: empleado.telefono ?? '');
  final correoController = TextEditingController(text: empleado.correoElectronico ?? '');
  final contactoEmergenciaNombreController = TextEditingController(text: empleado.contactoEmergenciaNombre ?? '');
  final telefonoEmergenciaController = TextEditingController(text: empleado.telefonoEmergencia ?? '');
  final parentescoEmergenciaController = TextEditingController(text: empleado.parentescoEmergencia ?? '');

  DateTime? fechaIngreso = empleado.fechaIngreso;
  String? puestoId = empleado.puestoId;
  String? sucursalId = empleado.sucursalId;
  final observacionesController = TextEditingController(text: empleado.observaciones ?? '');

  NivelEstudiosEmpleado? nivelEstudios =
      empleado.nivelEstudios == null ? null : NivelEstudiosEmpleado.values.byName(empleado.nivelEstudios!);
  final observacionesEscolaridadController = TextEditingController(text: empleado.observacionesEscolaridad ?? '');

  final aniosExperienciaController = TextEditingController(text: empleado.aniosExperienciaSeguridad.toString());
  final mesesExperienciaController =
      TextEditingController(text: empleado.mesesExperienciaAdicionales?.toString() ?? '');
  final ultimoPuestoController = TextEditingController(text: empleado.ultimoPuestoDesempenado ?? '');
  final resumenExperienciaController = TextEditingController(text: empleado.resumenExperiencia ?? '');
  final observacionesExperienciaController = TextEditingController(text: empleado.observacionesExperiencia ?? '');
  final motivoController = TextEditingController();

  String? errorCurp;
  String? errorRfc;
  String? errorCodigoPostalFiscal;
  String? errorNss;
  String? errorFechaNacimiento;
  String? errorFechaIngreso;

  final puestos = await ref.read(puestoRepositoryProvider).listarActivos();
  final sucursales = await ref.read(sucursalRepositoryProvider).listarActivas();
  if (!context.mounted) return false;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.corregirEmpleadoDialogoTitulo,
    confirmLabel: l10n.corregirEmpleadoBotonConfirmar,
    cancelLabel: l10n.corregirEmpleadoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.empleadoSeccionGeneral, style: AppTypography.heading3),
            const SizedBox(height: AppSpacing.sm),
            RisegTextField(label: l10n.empleadoCampoNombres, controller: nombresController, autofocus: true),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.empleadoCampoApellidoPaterno, controller: apellidoPaternoController),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.empleadoCampoApellidoMaterno, controller: apellidoMaternoController),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<SexoEmpleado>(
              label: l10n.empleadoCampoSexo,
              value: sexo,
              items: [
                for (final s in SexoEmpleado.values) RisegSelectItem(value: s, label: empleadoSexoLabel(l10n, s.name)),
              ],
              onChanged: (valor) => setState(() => sexo = valor ?? sexo),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegDateField(
              label: l10n.empleadoCampoFechaNacimiento,
              value: fechaNacimiento,
              errorText: errorFechaNacimiento,
              onChanged: (valor) => setState(() {
                fechaNacimiento = valor;
                errorFechaNacimiento = null;
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.empleadoCampoCurp,
              controller: curpController,
              errorText: errorCurp,
              onChanged: (_) => setState(() => errorCurp = null),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.empleadoCampoRfc,
              controller: rfcController,
              errorText: errorRfc,
              onChanged: (_) => setState(() => errorRfc = null),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.empleadoCampoCodigoPostalFiscal,
              controller: codigoPostalFiscalController,
              errorText: errorCodigoPostalFiscal,
              onChanged: (_) => setState(() => errorCodigoPostalFiscal = null),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.empleadoCampoNss,
              controller: nssController,
              errorText: errorNss,
              onChanged: (_) => setState(() => errorNss = null),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<EstadoCivilEmpleado>(
              label: l10n.empleadoCampoEstadoCivil,
              value: estadoCivil,
              items: [
                for (final e in EstadoCivilEmpleado.values)
                  RisegSelectItem(value: e, label: empleadoEstadoCivilLabel(l10n, e.name)),
              ],
              onChanged: (valor) => setState(() => estadoCivil = valor ?? estadoCivil),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.empleadoCampoNacionalidad, controller: nacionalidadController),
            const SizedBox(height: AppSpacing.lg),
            Text(l10n.empleadoSeccionContacto, style: AppTypography.heading3),
            const SizedBox(height: AppSpacing.sm),
            RisegTextField(label: l10n.empleadoCampoTelefono, controller: telefonoController),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.empleadoCampoCorreoElectronico, controller: correoController),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.empleadoCampoContactoEmergenciaNombre,
              controller: contactoEmergenciaNombreController,
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.empleadoCampoTelefonoEmergencia, controller: telefonoEmergenciaController),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.empleadoCampoParentescoEmergencia, controller: parentescoEmergenciaController),
            const SizedBox(height: AppSpacing.lg),
            Text(l10n.empleadoSeccionLaboral, style: AppTypography.heading3),
            const SizedBox(height: AppSpacing.sm),
            RisegDateField(
              label: l10n.empleadoCampoFechaIngreso,
              value: fechaIngreso,
              errorText: errorFechaIngreso,
              onChanged: (valor) => setState(() {
                fechaIngreso = valor;
                errorFechaIngreso = null;
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<String?>(
              label: l10n.empleadoCampoPuesto,
              value: puestoId,
              items: [
                RisegSelectItem(value: null, label: l10n.empleadoCampoSinAsignar),
                for (final p in puestos) RisegSelectItem(value: p.id, label: p.nombre),
              ],
              onChanged: (valor) => setState(() => puestoId = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<String?>(
              label: l10n.empleadoCampoSucursal,
              value: sucursalId,
              items: [
                RisegSelectItem(value: null, label: l10n.empleadoCampoSinAsignar),
                for (final s in sucursales) RisegSelectItem(value: s.id, label: s.nombre),
              ],
              onChanged: (valor) => setState(() => sucursalId = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.empleadoCampoObservaciones, controller: observacionesController),
            const SizedBox(height: AppSpacing.lg),
            Text(l10n.empleadoSeccionEscolaridad, style: AppTypography.heading3),
            const SizedBox(height: AppSpacing.sm),
            RisegSelect<NivelEstudiosEmpleado?>(
              label: l10n.empleadoCampoNivelEstudios,
              value: nivelEstudios,
              items: [
                RisegSelectItem(value: null, label: l10n.empleadoCampoSinAsignar),
                for (final n in NivelEstudiosEmpleado.values)
                  RisegSelectItem(value: n, label: empleadoNivelEstudiosLabel(l10n, n.name)),
              ],
              onChanged: (valor) => setState(() => nivelEstudios = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.empleadoCampoObservacionesEscolaridad,
              controller: observacionesEscolaridadController,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(l10n.empleadoSeccionExperiencia, style: AppTypography.heading3),
            const SizedBox(height: AppSpacing.sm),
            RisegTextField(
              label: l10n.empleadoCampoAniosExperiencia,
              controller: aniosExperienciaController,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.empleadoCampoMesesExperiencia,
              controller: mesesExperienciaController,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.empleadoCampoUltimoPuesto, controller: ultimoPuestoController),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.empleadoCampoResumenExperiencia, controller: resumenExperienciaController),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.empleadoCampoObservacionesExperiencia,
              controller: observacionesExperienciaController,
            ),
            const SizedBox(height: AppSpacing.lg),
            RisegTextField(label: l10n.corregirEmpleadoCampoMotivo, controller: motivoController),
          ],
        );
      },
    ),
    onConfirm: () async {
      final resultado = await ref.read(corregirEmpleadoUseCaseProvider).ejecutar(
            empleadoId: empleado.id,
            nombres: nombresController.text,
            apellidoPaterno: apellidoPaternoController.text,
            apellidoMaterno: apellidoMaternoController.text,
            sexo: sexo,
            fechaNacimiento: fechaNacimiento,
            curp: curpController.text,
            rfc: rfcController.text,
            codigoPostalFiscal: codigoPostalFiscalController.text,
            limpiarCodigoPostalFiscal: codigoPostalFiscalController.text.trim().isEmpty,
            nss: nssController.text,
            estadoCivil: estadoCivil,
            nacionalidad: nacionalidadController.text.trim().isEmpty ? null : nacionalidadController.text.trim(),
            telefono: telefonoController.text,
            correoElectronico: correoController.text,
            contactoEmergenciaNombre: contactoEmergenciaNombreController.text,
            telefonoEmergencia: telefonoEmergenciaController.text,
            parentescoEmergencia: parentescoEmergenciaController.text,
            fechaIngreso: fechaIngreso,
            puestoId: puestoId,
            limpiarPuesto: puestoId == null,
            sucursalId: sucursalId,
            limpiarSucursal: sucursalId == null,
            observaciones: observacionesController.text,
            nivelEstudios: nivelEstudios,
            observacionesEscolaridad: observacionesEscolaridadController.text,
            aniosExperienciaSeguridad: _enteroDesdeTexto(aniosExperienciaController.text),
            mesesExperienciaAdicionales: _enteroDesdeTexto(mesesExperienciaController.text),
            ultimoPuestoDesempenado: ultimoPuestoController.text,
            resumenExperiencia: resumenExperienciaController.text,
            observacionesExperiencia: observacionesExperienciaController.text,
            motivo: motivoController.text.trim(),
          );

      if (!context.mounted) return false;

      switch (resultado) {
        case CorregirEmpleadoExitoso():
          RisegFeedback.showSuccess(context, l10n.corregirEmpleadoExito);
          return true;
        case CorregirEmpleadoNoExiste():
          RisegFeedback.showError(context, l10n.corregirEmpleadoErrorInesperado);
          return false;
        case CorregirEmpleadoCurpInvalido():
          errorCurp = l10n.empleadoErrorCurpInvalido;
          return false;
        case CorregirEmpleadoRfcInvalido():
          errorRfc = l10n.empleadoErrorRfcInvalido;
          return false;
        case CorregirEmpleadoCodigoPostalFiscalInvalido():
          errorCodigoPostalFiscal = l10n.empleadoErrorCodigoPostalFiscalInvalido;
          return false;
        case CorregirEmpleadoNssInvalido():
          errorNss = l10n.empleadoErrorNssInvalido;
          return false;
        case CorregirEmpleadoFechaNacimientoInvalida():
          errorFechaNacimiento = l10n.empleadoErrorFechaNacimientoInvalida;
          return false;
        case CorregirEmpleadoFechaIngresoInvalida():
          errorFechaIngreso = l10n.empleadoErrorFechaIngresoInvalida;
          return false;
        case CorregirEmpleadoExperienciaInvalida():
          RisegFeedback.showError(context, l10n.empleadoErrorExperienciaInvalida);
          return false;
        case CorregirEmpleadoErrorInesperado():
          RisegFeedback.showError(context, l10n.corregirEmpleadoErrorInesperado);
          return false;
      }
    },
  );

  for (final c in [
    nombresController,
    apellidoPaternoController,
    apellidoMaternoController,
    curpController,
    rfcController,
    codigoPostalFiscalController,
    nssController,
    nacionalidadController,
    telefonoController,
    correoController,
    contactoEmergenciaNombreController,
    telefonoEmergenciaController,
    parentescoEmergenciaController,
    observacionesController,
    observacionesEscolaridadController,
    aniosExperienciaController,
    mesesExperienciaController,
    ultimoPuestoController,
    resumenExperienciaController,
    observacionesExperienciaController,
    motivoController,
  ]) {
    c.dispose();
  }

  return resultado ?? false;
}
