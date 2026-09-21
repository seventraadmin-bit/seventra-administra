import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_con_vigencia.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/actualizar_fotografia_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/adjuntar_documento_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/crear_empleado_usecase.dart';

import '../../../../organizacion/organizacion_providers.dart';
import '../../../personal_providers.dart';
import 'adjuntar_documento_empleado_dialog.dart' show categoriaDocumentoEmpleadoLabel;
import 'sueldo_acordado_fields.dart';

/// Tipo de adscripción capturada en la Alta (Etapa 5D) — Servicio *o*
/// Sucursal, nunca ambas. Puramente de UI: nunca se persiste como tal,
/// `servicioId` alimenta la `AsignacionServicio` inicial (nunca una
/// columna de `Empleado`), `sucursalId` sigue siendo la columna ya
/// existente desde 5A.
enum _TipoAdscripcion { ninguna, servicio, sucursal }

/// Documento del expediente elegido durante la Alta pero aún no subido
/// — se sube después de crear el `Empleado` (Etapa 5D.1), reutilizando
/// `AdjuntarDocumentoEmpleadoUseCase` tal cual, sin solución paralela.
class _DocumentoPendiente {
  _DocumentoPendiente({required this.categoria, required this.path, required this.nombre});
  final CategoriaDocumentoEmpleado categoria;
  final String path;
  final String nombre;
}

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

/// Convierte texto capturado en pesos (ej. "10000.00") a centavos —
/// misma unidad monetaria del resto del proyecto. `null` si el campo
/// está vacío o no es un número válido (mismo criterio que
/// `centavosDesdeTexto` en Finanzas — duplicado aquí a propósito, ya
/// es el patrón establecido por cada diálogo con montos, ver
/// `registrar_pago_aplicado_dialog.dart`).
int? centavosDesdeTexto(String texto) {
  final normalizado = texto.trim().replaceAll(',', '');
  if (normalizado.isEmpty) return null;
  final pesos = double.tryParse(normalizado);
  if (pesos == null) return null;
  return (pesos * 100).round();
}

/// Texto editable en pesos a partir de centavos — para precargar un
/// campo de corrección. Sin símbolo de moneda ni separador de miles
/// (eso es para lectura, ver `formatoCentavos`); esto es para volver a
/// capturarse.
String pesosDesdeCentavosParaEditar(int? centavos) {
  if (centavos == null) return '';
  return (centavos / 100).toStringAsFixed(2);
}

/// Traduce el mensaje técnico de un `XxxErrorInesperado` (Etapa 15,
/// hallazgo real) a un mensaje accionable cuando reconoce un patrón
/// conocido — nunca expone el texto crudo de la excepción/SQLite al
/// usuario. Hoy solo distingue el caso real ya visto: la base de datos
/// local todavía no tiene una columna que el código ya espera (falta
/// reabrir la app para que la migración pendiente corra) — cualquier
/// otro error cae al mensaje genérico ya existente.
String mensajeErrorTecnicoEmpleado(AppLocalizations l10n, String mensajeTecnico, String mensajeGenerico) {
  final texto = mensajeTecnico.toLowerCase();
  if (texto.contains('no such column') || texto.contains('has no column named')) {
    return l10n.empleadoErrorBaseDatosDesactualizada;
  }
  return mensajeGenerico;
}

/// Campos de sueldo/bono mensual administrativo (Etapa 6A) — solo
/// tienen sentido cuando la adscripción **no** es a Servicio (ver el
/// doc comment de `Empleado.sueldoMensualAdministrativo`); reutilizado
/// tal cual por `mostrarDialogoCrearEmpleado`/`mostrarDialogoCorregirEmpleado`
/// para no duplicar el layout entre ambos diálogos.
List<Widget> camposCondicionAdministrativa({
  required AppLocalizations l10n,
  required TextEditingController sueldoController,
  required TextEditingController bonoController,
  required String? errorSueldo,
  required String? errorBono,
  required StateSetter setState,
  required VoidCallback limpiarErrorSueldo,
  required VoidCallback limpiarErrorBono,
}) {
  return [
    const SizedBox(height: AppSpacing.md),
    RisegTextField(
      label: l10n.empleadoCampoSueldoMensualAdministrativo,
      controller: sueldoController,
      errorText: errorSueldo,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(limpiarErrorSueldo),
    ),
    const SizedBox(height: AppSpacing.md),
    RisegTextField(
      label: l10n.empleadoCampoBonoMensualAdministrativo,
      controller: bonoController,
      errorText: errorBono,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(limpiarErrorBono),
    ),
  ];
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

  // --- Datos bancarios (Etapa 6A) — todo opcional; ver
  // `EmpleadoValidator.datosBancariosValidos`. ---
  String? bancoId;
  final bancoOtroDescripcionController = TextEditingController();
  final numeroCuentaTarjetaController = TextEditingController();
  final clabeController = TextEditingController();

  DateTime? fechaIngreso;
  String? puestoId;
  _TipoAdscripcion tipoAdscripcion = _TipoAdscripcion.ninguna;
  String? servicioId;
  String? lineaComercialId;
  String? turnoId;
  String? sucursalId;
  List<LineaComercialConVigencia> lineasDelServicio = [];
  // --- Condición laboral administrativa (Etapa 6A) — solo relevante
  // cuando la adscripción no es a Servicio (ver doc comment de
  // `Empleado`). ---
  final sueldoMensualAdministrativoController = TextEditingController();
  final bonoMensualAdministrativoController = TextEditingController();
  // --- Sueldo/bono acordado de la asignación inicial (Etapa 6B) — solo
  // relevante cuando la adscripción es a Servicio; se precarga desde la
  // referencia del Servicio elegido, editable como excepción individual
  // (ver `SueldoAcordadoFields`). ---
  final sueldoAcordadoController = TextEditingController();
  final bonoAcordadoController = TextEditingController();
  final observacionesController = TextEditingController();

  NivelEstudiosEmpleado? nivelEstudios;
  final observacionesEscolaridadController = TextEditingController();

  // Vacío por defecto (no '0' precargado) — un campo vacío ya se
  // interpreta como 0 al confirmar (`_enteroDesdeTexto(...) ?? 0`), pero
  // precargado se sentía obligatorio. La Experiencia es información no
  // esencial para el alta (Resolución de Marlon, Etapa 5D).
  final aniosExperienciaController = TextEditingController();
  final mesesExperienciaController = TextEditingController();
  final ultimoPuestoController = TextEditingController();
  final resumenExperienciaController = TextEditingController();
  final observacionesExperienciaController = TextEditingController();

  String? fotografiaPath;
  String? fotografiaNombre;
  String? fotografiaMimeType;
  CategoriaDocumentoEmpleado categoriaDocumentoSeleccionada = CategoriaDocumentoEmpleado.otro;
  final documentosPendientes = <_DocumentoPendiente>[];

  String? errorNombres;
  String? errorApellidoPaterno;
  String? errorCurp;
  String? errorRfc;
  String? errorCodigoPostalFiscal;
  String? errorNss;
  String? errorFechaNacimiento;
  String? errorFechaIngreso;
  String? errorAdscripcion;
  String? errorLinea;
  String? errorDatosBancarios;
  String? errorBancoOtroDescripcion;
  String? errorSueldoAdministrativo;
  String? errorBonoAdministrativo;
  String? errorSueldoAcordado;
  String? errorBonoAcordado;

  final bancos = await ref.read(catalogoRepositoryProvider).listarBancos();
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
            Text(l10n.empleadoSeccionDatosBancarios, style: AppTypography.heading3),
            const SizedBox(height: AppSpacing.sm),
            RisegSelect<String?>(
              label: l10n.empleadoCampoBanco,
              value: bancoId,
              errorText: errorDatosBancarios,
              items: [
                RisegSelectItem(value: null, label: l10n.empleadoCampoSinAsignar),
                for (final b in bancos) RisegSelectItem(value: b.id, label: b.nombre),
              ],
              onChanged: (valor) => setState(() {
                bancoId = valor;
                errorDatosBancarios = null;
                errorBancoOtroDescripcion = null;
              }),
            ),
            if (bancoId == SeedIds.bancoOtro) ...[
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: l10n.empleadoCampoBancoOtroDescripcion,
                controller: bancoOtroDescripcionController,
                errorText: errorBancoOtroDescripcion,
                onChanged: (_) => setState(() => errorBancoOtroDescripcion = null),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.empleadoCampoNumeroCuentaTarjeta,
              controller: numeroCuentaTarjetaController,
              onChanged: (_) => setState(() => errorDatosBancarios = null),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.empleadoCampoClabe,
              controller: clabeController,
              onChanged: (_) => setState(() => errorDatosBancarios = null),
            ),
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
                lineaComercialId = null;
                lineasDelServicio = [];
                turnoId = null;
                sucursalId = null;
                errorAdscripcion = null;
                errorLinea = null;
              }),
            ),
            // `KeyedSubtree` con `ValueKey(tipoAdscripcion)` — sin esto,
            // alternar entre Servicio/Sucursal/Ninguna inserta y quita
            // `DropdownButtonFormField`s en medio de la lista de hijos del
            // `Column` sin ninguna `Key`; Flutter reconcilia por posición y
            // puede reutilizar el Element de un dropdown para otro
            // completamente distinto (mismo tipo genérico `RisegSelect<String?>`
            // en Servicio/Sucursal), corrompiendo su estado interno y
            // provocando el crash "_dependents.isEmpty is not true" /
            // "Tried to build dirty widget in the wrong build scope" al
            // cambiar la selección. La `Key` obliga a Flutter a desmontar
            // el subárbol anterior por completo antes de montar el nuevo.
            KeyedSubtree(
              key: ValueKey(tipoAdscripcion),
              child: switch (tipoAdscripcion) {
                _TipoAdscripcion.servicio => Builder(
                    builder: (_) {
                      final lineasVigentes = lineasDelServicio.where((l) => l.vigenciaActual != null).toList();
                      final lineaElegida = buscarLineaComercialPorId(lineasDelServicio, lineaComercialId);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: AppSpacing.md),
                          RisegSelect<String?>(
                            label: l10n.empleadoCampoServicio,
                            value: servicioId,
                            errorText: errorAdscripcion,
                            items: [
                              for (final item in servicios)
                                RisegSelectItem(value: item.servicio.id, label: item.servicio.nombre),
                            ],
                            onChanged: (valor) async {
                              final lineas = valor == null
                                  ? <LineaComercialConVigencia>[]
                                  : await ref.read(servicioComercialRepositoryProvider).listarLineas(valor);
                              setState(() {
                                servicioId = valor;
                                lineasDelServicio = lineas;
                                lineaComercialId = null;
                                errorAdscripcion = null;
                                errorLinea = null;
                                errorSueldoAcordado = null;
                                errorBonoAcordado = null;
                                precargarSueldoAcordado(
                                  linea: null,
                                  sueldoController: sueldoAcordadoController,
                                  bonoController: bonoAcordadoController,
                                );
                              });
                            },
                          ),
                          if (servicioId != null && lineasVigentes.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.md),
                            RisegSelect<String?>(
                              label: l10n.empleadoCampoLineaComercial,
                              value: lineaComercialId,
                              errorText: errorLinea,
                              items: [
                                for (final l in lineasVigentes)
                                  RisegSelectItem(value: l.linea.id, label: etiquetaLineaComercial(l10n, l)),
                              ],
                              onChanged: (valor) => setState(() {
                                final linea = buscarLineaComercialPorId(lineasDelServicio, valor);
                                lineaComercialId = valor;
                                errorLinea = null;
                                errorSueldoAcordado = null;
                                errorBonoAcordado = null;
                                if (linea?.vigenciaActual != null) turnoId = linea!.vigenciaActual!.modalidadTurnoId;
                                precargarSueldoAcordado(
                                  linea: linea,
                                  sueldoController: sueldoAcordadoController,
                                  bonoController: bonoAcordadoController,
                                );
                              }),
                            ),
                            if (lineaElegida?.vigenciaActual != null) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                l10n.empleadoLineaComercialCapacidad(
                                  lineaElegida!.asignadosVigentes,
                                  lineaElegida.vigenciaActual!.cantidadElementos,
                                ),
                                style: AppTypography.caption.copyWith(color: context.colors.textMuted),
                              ),
                              if (lineaElegida.capacidadExcedida) ...[
                                const SizedBox(height: AppSpacing.xxs),
                                Text(
                                  l10n.empleadoLineaComercialCapacidadExcedidaAdviso,
                                  style: AppTypography.caption.copyWith(color: context.colors.warning),
                                ),
                              ],
                            ],
                          ],
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
                          if (servicioId != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            SueldoAcordadoFields(
                              linea: lineaElegida,
                              sueldoController: sueldoAcordadoController,
                              bonoController: bonoAcordadoController,
                              errorSueldo: errorSueldoAcordado,
                              errorBono: errorBonoAcordado,
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                _TipoAdscripcion.sucursal => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                      ...camposCondicionAdministrativa(
                        l10n: l10n,
                        sueldoController: sueldoMensualAdministrativoController,
                        bonoController: bonoMensualAdministrativoController,
                        errorSueldo: errorSueldoAdministrativo,
                        errorBono: errorBonoAdministrativo,
                        setState: setState,
                        limpiarErrorSueldo: () => errorSueldoAdministrativo = null,
                        limpiarErrorBono: () => errorBonoAdministrativo = null,
                      ),
                    ],
                  ),
                _TipoAdscripcion.ninguna => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: camposCondicionAdministrativa(
                      l10n: l10n,
                      sueldoController: sueldoMensualAdministrativoController,
                      bonoController: bonoMensualAdministrativoController,
                      errorSueldo: errorSueldoAdministrativo,
                      errorBono: errorBonoAdministrativo,
                      setState: setState,
                      limpiarErrorSueldo: () => errorSueldoAdministrativo = null,
                      limpiarErrorBono: () => errorBonoAdministrativo = null,
                    ),
                  ),
              },
            ),
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
            Text(l10n.empleadoSeccionFotografia, style: AppTypography.heading3),
            const SizedBox(height: AppSpacing.sm),
            // Misma protección de `Key` que la Adscripción de arriba —
            // alternar entre el botón "Seleccionar imagen" y la vista
            // previa cambia de tipo de widget en la misma posición.
            KeyedSubtree(
              key: ValueKey(fotografiaPath == null),
              child: fotografiaPath == null
                  ? RisegButton(
                      label: l10n.crearEmpleadoBotonSeleccionarImagen,
                      variant: RisegButtonVariant.secondary,
                      icon: Icons.add_a_photo_outlined,
                      onPressed: () async {
                        final seleccion = await FilePicker.platform.pickFiles(type: FileType.image);
                        final archivo = seleccion?.files.singleOrNull;
                        if (archivo?.path == null) return;
                        setState(() {
                          fotografiaPath = archivo!.path;
                          fotografiaNombre = archivo.name;
                          fotografiaMimeType = 'image/${archivo.extension ?? 'jpeg'}';
                        });
                      },
                    )
                  : Row(
                      children: [
                        ClipRRect(
                          borderRadius: AppRadius.mdRadius,
                          child: Image.file(File(fotografiaPath!), width: 56, height: 56, fit: BoxFit.cover),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: Text(fotografiaNombre ?? '', overflow: TextOverflow.ellipsis)),
                        RisegButton(
                          label: l10n.crearEmpleadoBotonCambiarImagen,
                          variant: RisegButtonVariant.ghost,
                          onPressed: () async {
                            final seleccion = await FilePicker.platform.pickFiles(type: FileType.image);
                            final archivo = seleccion?.files.singleOrNull;
                            if (archivo?.path == null) return;
                            setState(() {
                              fotografiaPath = archivo!.path;
                              fotografiaNombre = archivo.name;
                              fotografiaMimeType = 'image/${archivo.extension ?? 'jpeg'}';
                            });
                          },
                        ),
                        RisegButton(
                          label: l10n.crearEmpleadoBotonQuitar,
                          variant: RisegButtonVariant.ghost,
                          onPressed: () => setState(() {
                            fotografiaPath = null;
                            fotografiaNombre = null;
                            fotografiaMimeType = null;
                          }),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(l10n.crearEmpleadoSeccionDocumentos, style: AppTypography.heading3),
            const SizedBox(height: AppSpacing.sm),
            RisegSelect<CategoriaDocumentoEmpleado>(
              label: l10n.adjuntarDocumentoEmpleadoCampoCategoria,
              value: categoriaDocumentoSeleccionada,
              items: [
                for (final c in CategoriaDocumentoEmpleado.values)
                  RisegSelectItem(value: c, label: categoriaDocumentoEmpleadoLabel(l10n, c.name)),
              ],
              onChanged: (valor) => setState(() => categoriaDocumentoSeleccionada = valor ?? categoriaDocumentoSeleccionada),
            ),
            const SizedBox(height: AppSpacing.sm),
            RisegButton(
              label: l10n.crearEmpleadoBotonAgregarDocumento,
              variant: RisegButtonVariant.secondary,
              icon: Icons.attach_file,
              onPressed: () async {
                final seleccion = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
                final archivo = seleccion?.files.singleOrNull;
                if (archivo?.path == null) return;
                setState(() {
                  documentosPendientes.add(
                    _DocumentoPendiente(categoria: categoriaDocumentoSeleccionada, path: archivo!.path!, nombre: archivo.name),
                  );
                });
              },
            ),
            if (documentosPendientes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              for (final doc in documentosPendientes)
                Padding(
                  key: ValueKey(doc),
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(child: Text('${categoriaDocumentoEmpleadoLabel(l10n, doc.categoria.name)} · ${doc.nombre}')),
                      RisegButton(
                        label: l10n.crearEmpleadoBotonQuitar,
                        variant: RisegButtonVariant.ghost,
                        onPressed: () => setState(() => documentosPendientes.remove(doc)),
                      ),
                    ],
                  ),
                ),
            ],
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

      final resultado = await ref.read(crearEmpleadoAutorizadoProvider)(
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
            bancoId: bancoId,
            bancoOtroDescripcion: bancoId == SeedIds.bancoOtro ? bancoOtroDescripcionController.text : null,
            numeroCuentaTarjeta: numeroCuentaTarjetaController.text,
            clabe: clabeController.text,
            fechaIngreso: fechaIngreso!,
            puestoId: puestoId,
            empresaId: empresaActiva.id,
            servicioId: tipoAdscripcion == _TipoAdscripcion.servicio ? servicioId : null,
            turnoId: tipoAdscripcion == _TipoAdscripcion.servicio ? turnoId : null,
            lineaComercialId: tipoAdscripcion == _TipoAdscripcion.servicio ? lineaComercialId : null,
            sucursalId: tipoAdscripcion == _TipoAdscripcion.sucursal ? sucursalId : null,
            sueldoMensualAsignacion: tipoAdscripcion == _TipoAdscripcion.servicio
                ? centavosDesdeTexto(sueldoAcordadoController.text)
                : null,
            bonoMensualAsignacion: tipoAdscripcion == _TipoAdscripcion.servicio
                ? centavosDesdeTexto(bonoAcordadoController.text)
                : null,
            sueldoMensualAdministrativo: tipoAdscripcion == _TipoAdscripcion.servicio
                ? null
                : centavosDesdeTexto(sueldoMensualAdministrativoController.text),
            bonoMensualAdministrativo: tipoAdscripcion == _TipoAdscripcion.servicio
                ? null
                : centavosDesdeTexto(bonoMensualAdministrativoController.text),
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
          final empleadoId = resultado.empleado.id;
          // La fotografía y los documentos son opcionales y se suben
          // DESPUÉS de crear el Empleado — no pueden participar en la
          // misma transacción de BD porque son operaciones de archivo
          // (mismo criterio que 5B). Un fallo aquí no deja un Empleado
          // "a medias": el registro ya es válido y completo sin ellos,
          // igual que si el usuario los hubiera omitido a propósito; solo
          // se avisa para que puedan completarse después desde el
          // expediente.
          var huboAdvertencia = false;

          if (fotografiaPath != null) {
            final fotoResultado = await ref.read(actualizarFotografiaEmpleadoAutorizadoProvider)(
                  empleadoId: empleadoId,
                  sourceFilePath: fotografiaPath!,
                  originalFileName: fotografiaNombre!,
                  mimeType: fotografiaMimeType!,
                );
            if (fotoResultado is! ActualizarFotografiaEmpleadoExitoso) huboAdvertencia = true;
          }

          for (final doc in documentosPendientes) {
            final docResultado = await ref.read(adjuntarDocumentoEmpleadoAutorizadoProvider)(
                  empleadoId: empleadoId,
                  categoria: doc.categoria,
                  sourceFilePath: doc.path,
                  originalFileName: doc.nombre,
                  mimeType: 'application/pdf',
                );
            if (docResultado is! AdjuntarDocumentoEmpleadoExitoso) huboAdvertencia = true;
          }

          if (!context.mounted) return empleadoId;
          if (huboAdvertencia) {
            RisegFeedback.showError(context, l10n.crearEmpleadoAdvertenciaAdjuntos);
          } else {
            RisegFeedback.showSuccess(context, l10n.crearEmpleadoExito);
          }
          return empleadoId;
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
        case CrearEmpleadoLineaComercialRequerida():
          errorLinea = l10n.empleadoErrorLineaComercialRequerida;
          return null;
        case CrearEmpleadoLineaComercialInvalida():
          errorLinea = l10n.empleadoErrorLineaComercialInvalida;
          return null;
        case CrearEmpleadoSueldoAsignacionRequerido():
          errorSueldoAcordado = l10n.empleadoErrorSueldoRequerido;
          return null;
        case CrearEmpleadoSueldoAsignacionInvalido():
          errorSueldoAcordado = l10n.empleadoErrorSueldoAcordadoInvalido;
          return null;
        case CrearEmpleadoBonoAsignacionInvalido():
          errorBonoAcordado = l10n.empleadoErrorBonoAcordadoInvalido;
          return null;
        case CrearEmpleadoDatosBancariosInvalidos():
          errorDatosBancarios = l10n.empleadoErrorDatosBancariosInvalidos;
          return null;
        case CrearEmpleadoBancoOtroDescripcionRequerida():
          errorBancoOtroDescripcion = l10n.empleadoErrorBancoOtroDescripcionRequerido;
          return null;
        case CrearEmpleadoSueldoAdministrativoInvalido():
          errorSueldoAdministrativo = l10n.empleadoErrorSueldoAdministrativoInvalido;
          return null;
        case CrearEmpleadoBonoAdministrativoInvalido():
          errorBonoAdministrativo = l10n.empleadoErrorBonoAdministrativoInvalido;
          return null;
        case CrearEmpleadoErrorInesperado(:final mensaje):
          RisegFeedback.showError(
            context,
            mensajeErrorTecnicoEmpleado(l10n, mensaje, l10n.crearEmpleadoErrorInesperado),
          );
          return null;
      }
    },
  );

  // Liberar aquí es seguro: `RisegDialog.showForm` no devuelve
  // hasta que la ruta del diálogo terminó de cerrarse (ver su
  // documentación). Antes sí hacía falta aplazarlo 300 ms, y ese
  // aplazamiento dejaba un Timer vivo después de desmontar el árbol.
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
    bancoOtroDescripcionController,
    numeroCuentaTarjetaController,
    clabeController,
    sueldoMensualAdministrativoController,
    bonoMensualAdministrativoController,
    sueldoAcordadoController,
    bonoAcordadoController,
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
