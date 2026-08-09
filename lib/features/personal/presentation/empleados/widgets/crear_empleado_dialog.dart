import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/crear_empleado_usecase.dart';

import '../../../../organizacion/organizacion_providers.dart';
import '../../../personal_providers.dart';

/// Tipo de adscripción capturada en la Alta (Etapa 5D) — Servicio *o*
/// Sucursal, nunca ambas. Puramente de UI: nunca se persiste como tal,
/// `servicioId` alimenta la `AsignacionServicio` inicial (nunca una
/// columna de `Empleado`), `sucursalId` sigue siendo la columna ya
/// existente desde 5A.
enum _TipoAdscripcion { ninguna, servicio, sucursal }

String empleadoSexoLabel(AppLocalizations l10n, String valor) {
  return switch (SexoEmpleado.values.byName(valor)) {
    SexoEmpleado.masculino => l10n.empleadoSexoMasculino,
    SexoEmpleado.femenino => l10n.empleadoSexoFemenino,
  };
}

String empleadoEstadoCivilLabel(AppLocalizations l10n, String valor) {
  return switch (EstadoCivilEmpleado.values.byName(valor)) {
    EstadoCivilEmpleado.soltero => l10n.empleadoEstadoCivilSoltero,
    EstadoCivilEmpleado.casado => l10n.empleadoEstadoCivilCasado,
    EstadoCivilEmpleado.divorciado => l10n.empleadoEstadoCivilDivorciado,
    EstadoCivilEmpleado.viudo => l10n.empleadoEstadoCivilViudo,
    EstadoCivilEmpleado.unionLibre => l10n.empleadoEstadoCivilUnionLibre,
  };
}

String empleadoNivelEstudiosLabel(AppLocalizations l10n, String valor) {
  return switch (NivelEstudiosEmpleado.values.byName(valor)) {
    NivelEstudiosEmpleado.sinEstudios => l10n.empleadoNivelEstudiosSinEstudios,
    NivelEstudiosEmpleado.primaria => l10n.empleadoNivelEstudiosPrimaria,
    NivelEstudiosEmpleado.secundaria => l10n.empleadoNivelEstudiosSecundaria,
    NivelEstudiosEmpleado.bachillerato => l10n.empleadoNivelEstudiosBachillerato,
    NivelEstudiosEmpleado.tecnico => l10n.empleadoNivelEstudiosTecnico,
    NivelEstudiosEmpleado.licenciatura => l10n.empleadoNivelEstudiosLicenciatura,
    NivelEstudiosEmpleado.posgrado => l10n.empleadoNivelEstudiosPosgrado,
  };
}

int? _enteroDesdeTexto(String texto) {
  final normalizado = texto.trim();
  if (normalizado.isEmpty) return null;
  return int.tryParse(normalizado);
}

/// Diálogo "Registrar empleado" (Etapa 5A) — información general,
/// contacto, laboral, escolaridad y experiencia general en seguridad
/// privada. Domicilio y documentación se capturan después, desde el
/// expediente ya creado.
///
/// Devuelve el `id` del Empleado creado, o `null` si se canceló.
Future<String?> mostrarDialogoCrearEmpleado(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;

  final nombresController = TextEditingController();
  final apellidoPaternoController = TextEditingController();
  final apellidoMaternoController = TextEditingController();
  SexoEmpleado sexo = SexoEmpleado.masculino;
  DateTime? fechaNacimiento;
  final curpController = TextEditingController();
  final rfcController = TextEditingController();
  final codigoPostalFiscalController = TextEditingController();
  final nssController = TextEditingController();
  EstadoCivilEmpleado estadoCivil = EstadoCivilEmpleado.soltero;
  final nacionalidadController = TextEditingController(text: 'Mexicana');

  final telefonoController = TextEditingController();
  final correoController = TextEditingController();
  final contactoEmergenciaNombreController = TextEditingController();
  final telefonoEmergenciaController = TextEditingController();
  final parentescoEmergenciaController = TextEditingController();

  DateTime? fechaIngreso;
  String? puestoId;
  _TipoAdscripcion tipoAdscripcion = _TipoAdscripcion.ninguna;
  String? servicioId;
  String? turnoId;
  String? sucursalId;
  final observacionesController = TextEditingController();

  NivelEstudiosEmpleado? nivelEstudios;
  final observacionesEscolaridadController = TextEditingController();

  final aniosExperienciaController = TextEditingController(text: '0');
  final mesesExperienciaController = TextEditingController();
  final ultimoPuestoController = TextEditingController();
  final resumenExperienciaController = TextEditingController();
  final observacionesExperienciaController = TextEditingController();

  String? errorNombres;
  String? errorApellidoPaterno;
  String? errorCurp;
  String? errorRfc;
  String? errorCodigoPostalFiscal;
  String? errorNss;
  String? errorFechaNacimiento;
  String? errorFechaIngreso;
  String? errorAdscripcion;

  final puestos = await ref.read(puestoRepositoryProvider).listarActivos();
  final sucursales = await ref.read(sucursalRepositoryProvider).listarActivas();
  // RISEG ONE opera con una sola Empresa activa a la vez (ver el doc
  // comment de `Empresa`) — se asigna directo, sin selector en el
  // formulario.
  final empresaActiva = await ref.read(empresaRepositoryProvider).obtenerActiva();
  // Adscripción (Etapa 5D) — solo Servicios activos son elegibles
  // (`AsignarEmpleadoServicioUseCase`/`CrearEmpleadoUseCase` ya
  // rechazan cualquier otro estatus; se filtra aquí para no ofrecer una
  // opción que de todas formas se rechazaría). Reutiliza el catálogo de
  // modalidades de turno ya existente (Etapa 4G.1) — mismo concepto
  // real que el Turno de una asignación.
  final servicios = (await ref.read(servicioRepositoryProvider).listar())
      .where((item) => item.servicio.estatus == EstatusServicio.activo.name)
      .toList();
  final modalidadesTurno = await ref.read(catalogoRepositoryProvider).listarModalidadesTurno();
  if (!context.mounted) return null;

  final resultado = await RisegDialog.showForm<String>(
    context: context,
    title: l10n.crearEmpleadoDialogoTitulo,
    confirmLabel: l10n.crearEmpleadoBotonConfirmar,
    cancelLabel: l10n.crearEmpleadoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.empleadoSeccionGeneral, style: AppTypography.heading3),
            const SizedBox(height: AppSpacing.sm),
            RisegTextField(
              label: l10n.empleadoCampoNombres,
              controller: nombresController,
              autofocus: true,
              errorText: errorNombres,
              onChanged: (_) => setState(() => errorNombres = null),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.empleadoCampoApellidoPaterno,
              controller: apellidoPaternoController,
              errorText: errorApellidoPaterno,
              onChanged: (_) => setState(() => errorApellidoPaterno = null),
            ),
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
            RisegTextField(label: l10n.empleadoCampoObservaciones, controller: observacionesController),
            const SizedBox(height: AppSpacing.lg),
            Text(l10n.empleadoSeccionAdscripcion, style: AppTypography.heading3),
            const SizedBox(height: AppSpacing.sm),
            RisegSelect<_TipoAdscripcion>(
              label: l10n.empleadoCampoTipoAdscripcion,
              value: tipoAdscripcion,
              items: [
                RisegSelectItem(value: _TipoAdscripcion.ninguna, label: l10n.empleadoTipoAdscripcionNinguna),
                RisegSelectItem(value: _TipoAdscripcion.servicio, label: l10n.empleadoTipoAdscripcionServicio),
                RisegSelectItem(value: _TipoAdscripcion.sucursal, label: l10n.empleadoTipoAdscripcionSucursal),
              ],
              onChanged: (valor) => setState(() {
                tipoAdscripcion = valor ?? _TipoAdscripcion.ninguna;
                servicioId = null;
                turnoId = null;
                sucursalId = null;
                errorAdscripcion = null;
              }),
            ),
            if (tipoAdscripcion == _TipoAdscripcion.servicio) ...[
              const SizedBox(height: AppSpacing.md),
              RisegSelect<String?>(
                label: l10n.empleadoCampoServicio,
                value: servicioId,
                errorText: errorAdscripcion,
                items: [
                  for (final item in servicios) RisegSelectItem(value: item.servicio.id, label: item.servicio.nombre),
                ],
                onChanged: (valor) => setState(() {
                  servicioId = valor;
                  errorAdscripcion = null;
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegSelect<String?>(
                label: l10n.empleadoCampoTurno,
                value: turnoId,
                items: [
                  RisegSelectItem(value: null, label: l10n.empleadoCampoSinAsignar),
                  for (final m in modalidadesTurno) RisegSelectItem(value: m.id, label: m.nombre),
                ],
                onChanged: (valor) => setState(() => turnoId = valor),
              ),
            ],
            if (tipoAdscripcion == _TipoAdscripcion.sucursal) ...[
              const SizedBox(height: AppSpacing.md),
              RisegSelect<String?>(
                label: l10n.empleadoCampoSucursal,
                value: sucursalId,
                errorText: errorAdscripcion,
                items: [
                  for (final s in sucursales) RisegSelectItem(value: s.id, label: s.nombre),
                ],
                onChanged: (valor) => setState(() {
                  sucursalId = valor;
                  errorAdscripcion = null;
                }),
              ),
            ],
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
          ],
        );
      },
    ),
    onConfirm: () async {
      var valido = true;
      if (nombresController.text.trim().isEmpty) {
        errorNombres = l10n.empleadoErrorNombresRequerido;
        valido = false;
      }
      if (apellidoPaternoController.text.trim().isEmpty) {
        errorApellidoPaterno = l10n.empleadoErrorApellidoPaternoRequerido;
        valido = false;
      }
      if (fechaNacimiento == null) {
        errorFechaNacimiento = l10n.empleadoCampoFechaNacimiento;
        valido = false;
      }
      if (fechaIngreso == null) {
        errorFechaIngreso = l10n.empleadoCampoFechaIngreso;
        valido = false;
      }
      if (tipoAdscripcion == _TipoAdscripcion.servicio && servicioId == null) {
        errorAdscripcion = l10n.empleadoCampoServicio;
        valido = false;
      }
      if (tipoAdscripcion == _TipoAdscripcion.sucursal && sucursalId == null) {
        errorAdscripcion = l10n.empleadoCampoSucursal;
        valido = false;
      }
      if (!valido) return null;

      final resultado = await ref.read(crearEmpleadoUseCaseProvider).ejecutar(
            nombres: nombresController.text,
            apellidoPaterno: apellidoPaternoController.text,
            apellidoMaterno: apellidoMaternoController.text,
            sexo: sexo,
            fechaNacimiento: fechaNacimiento!,
            curp: curpController.text,
            rfc: rfcController.text,
            codigoPostalFiscal: codigoPostalFiscalController.text,
            nss: nssController.text,
            estadoCivil: estadoCivil,
            nacionalidad: nacionalidadController.text.trim().isEmpty ? 'Mexicana' : nacionalidadController.text.trim(),
            telefono: telefonoController.text,
            correoElectronico: correoController.text,
            contactoEmergenciaNombre: contactoEmergenciaNombreController.text,
            telefonoEmergencia: telefonoEmergenciaController.text,
            parentescoEmergencia: parentescoEmergenciaController.text,
            fechaIngreso: fechaIngreso!,
            puestoId: puestoId,
            empresaId: empresaActiva.id,
            servicioId: tipoAdscripcion == _TipoAdscripcion.servicio ? servicioId : null,
            turnoId: tipoAdscripcion == _TipoAdscripcion.servicio ? turnoId : null,
            sucursalId: tipoAdscripcion == _TipoAdscripcion.sucursal ? sucursalId : null,
            observaciones: observacionesController.text,
            nivelEstudios: nivelEstudios,
            observacionesEscolaridad: observacionesEscolaridadController.text,
            aniosExperienciaSeguridad: _enteroDesdeTexto(aniosExperienciaController.text) ?? 0,
            mesesExperienciaAdicionales: _enteroDesdeTexto(mesesExperienciaController.text),
            ultimoPuestoDesempenado: ultimoPuestoController.text,
            resumenExperiencia: resumenExperienciaController.text,
            observacionesExperiencia: observacionesExperienciaController.text,
          );

      if (!context.mounted) return null;

      switch (resultado) {
        case CrearEmpleadoExitoso():
          RisegFeedback.showSuccess(context, l10n.crearEmpleadoExito);
          return resultado.empleado.id;
        case CrearEmpleadoNombresRequerido():
          errorNombres = l10n.empleadoErrorNombresRequerido;
          return null;
        case CrearEmpleadoApellidoPaternoRequerido():
          errorApellidoPaterno = l10n.empleadoErrorApellidoPaternoRequerido;
          return null;
        case CrearEmpleadoCurpInvalido():
          errorCurp = l10n.empleadoErrorCurpInvalido;
          return null;
        case CrearEmpleadoRfcInvalido():
          errorRfc = l10n.empleadoErrorRfcInvalido;
          return null;
        case CrearEmpleadoCodigoPostalFiscalInvalido():
          errorCodigoPostalFiscal = l10n.empleadoErrorCodigoPostalFiscalInvalido;
          return null;
        case CrearEmpleadoNssInvalido():
          errorNss = l10n.empleadoErrorNssInvalido;
          return null;
        case CrearEmpleadoFechaNacimientoInvalida():
          errorFechaNacimiento = l10n.empleadoErrorFechaNacimientoInvalida;
          return null;
        case CrearEmpleadoFechaIngresoInvalida():
          errorFechaIngreso = l10n.empleadoErrorFechaIngresoInvalida;
          return null;
        case CrearEmpleadoExperienciaInvalida():
          RisegFeedback.showError(context, l10n.empleadoErrorExperienciaInvalida);
          return null;
        case CrearEmpleadoAdscripcionAmbigua():
          errorAdscripcion = l10n.empleadoErrorAdscripcionAmbigua;
          return null;
        case CrearEmpleadoServicioNoExiste():
        case CrearEmpleadoServicioNoActivo():
          errorAdscripcion = l10n.empleadoErrorServicioNoActivo;
          return null;
        case CrearEmpleadoErrorInesperado():
          RisegFeedback.showError(context, l10n.crearEmpleadoErrorInesperado);
          return null;
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
  ]) {
    c.dispose();
  }

  return resultado;
}
