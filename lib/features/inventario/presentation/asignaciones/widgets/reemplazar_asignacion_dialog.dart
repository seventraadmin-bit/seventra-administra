import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart';
import 'package:riseg_one/features/inventario/domain/usecases/obtener_empleados_responsables_servicio_usecase.dart'
    show EmpleadoOpcion;
import 'package:riseg_one/features/inventario/domain/usecases/reemplazar_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';

import 'cerrar_asignacion_dialog.dart' show motivoCierreLabel;

/// Diálogo "Reemplazar artículo" (Etapa 7B) — cierra la Asignación
/// vigente y crea de inmediato la de reemplazo, siempre elegida del
/// inventario disponible (nunca texto libre). Una sola pantalla con
/// dos bloques ("Lo que se retira" / "Lo que se entrega") en vez de
/// un asistente de varios pasos — el flujo completo cabe en un
/// formulario, sin necesidad de partirlo.
Future<bool> mostrarDialogoReemplazarAsignacion(
  BuildContext context,
  WidgetRef ref, {
  required AsignacionData asignacion,
  List<EmpleadoOpcion> empleadosParaResponsable = const [],
}) async {
  final l10n = AppLocalizations.of(context)!;
  final articuloRepo = ref.read(articuloRepositoryProvider);
  final inventarioRepo = ref.read(inventarioRepositoryProvider);
  final reemplazarAsignacion = ref.read(reemplazarAsignacionUseCaseProvider);

  final articulos = await articuloRepo.listar();
  if (!context.mounted) return false;

  MotivoCierreAsignacion motivo = MotivoCierreAsignacion.desgaste;
  bool? atribuibleAlEmpleado;
  bool generaDescuento = false;
  final observacionesCtrl = TextEditingController();
  final importeCtrl = TextEditingController();
  String? empleadoResponsableId = asignacion.empleadoId;
  DateTime? fechaCierre = DateTime.now();

  ArticuloData? articuloReemplazo;
  List<ArticuloVarianteData> variantes = const [];
  List<ArticuloUnidadData> unidadesDisponibles = const [];
  String? varianteId;
  String? unidadId;
  final cantidadCtrl = TextEditingController(text: '1');
  final condicionCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.reemplazarAsignacionDialogoTitulo,
    confirmLabel: l10n.reemplazarAsignacionBotonConfirmar,
    cancelLabel: l10n.reemplazarAsignacionBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        Future<void> onArticuloCambiado(ArticuloData? nuevo) async {
          setState(() {
            articuloReemplazo = nuevo;
            varianteId = null;
            unidadId = null;
            variantes = const [];
            unidadesDisponibles = const [];
          });
          if (nuevo == null) return;
          if (nuevo.manejaVariante) {
            final v = await articuloRepo.listarVariantes(nuevo.id);
            if (context.mounted) setState(() => variantes = v);
          } else if (nuevo.manejaSerie) {
            final u = await inventarioRepo.listarUnidades(nuevo.id, estatus: 'disponible');
            if (context.mounted) setState(() => unidadesDisponibles = u);
          }
        }

        final disparaDanoPerdida = motivo.disparaDanoPerdida;

        return SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.reemplazarAsignacionSeccionRetiro, style: AppTypography.label),
                const SizedBox(height: AppSpacing.sm),
                RisegSelect<MotivoCierreAsignacion>(
                  label: l10n.cerrarAsignacionCampoMotivo,
                  value: motivo,
                  items: [
                    for (final m in MotivoCierreAsignacion.values)
                      RisegSelectItem(value: m, label: motivoCierreLabel(l10n, m)),
                  ],
                  onChanged: (valor) => setState(() => motivo = valor ?? motivo),
                ),
                const SizedBox(height: AppSpacing.md),
                RisegTextField(label: l10n.cerrarAsignacionCampoObservaciones, controller: observacionesCtrl),
                if (disparaDanoPerdida) ...[
                  const SizedBox(height: AppSpacing.md),
                  RisegSelect<bool?>(
                    label: l10n.cerrarAsignacionCampoAtribuible,
                    value: atribuibleAlEmpleado,
                    items: [
                      RisegSelectItem(value: true, label: l10n.cerrarAsignacionSi),
                      RisegSelectItem(value: false, label: l10n.cerrarAsignacionNo),
                    ],
                    onChanged: (valor) => setState(() => atribuibleAlEmpleado = valor),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  RisegSelect<bool>(
                    label: l10n.cerrarAsignacionCampoGeneraDescuento,
                    value: generaDescuento,
                    items: [
                      RisegSelectItem(value: true, label: l10n.cerrarAsignacionSi),
                      RisegSelectItem(value: false, label: l10n.cerrarAsignacionNo),
                    ],
                    onChanged: (valor) => setState(() => generaDescuento = valor ?? false),
                  ),
                  if (generaDescuento) ...[
                    const SizedBox(height: AppSpacing.md),
                    RisegTextField(
                      label: l10n.cerrarAsignacionCampoImporteDescuento,
                      controller: importeCtrl,
                      keyboardType: TextInputType.number,
                    ),
                    if (empleadosParaResponsable.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      RisegSelect<String?>(
                        label: l10n.cerrarAsignacionCampoResponsable,
                        value: empleadoResponsableId,
                        items: [for (final e in empleadosParaResponsable) RisegSelectItem(value: e.id, label: e.nombre)],
                        onChanged: (valor) => setState(() => empleadoResponsableId = valor),
                      ),
                    ],
                  ],
                ],
                const SizedBox(height: AppSpacing.lg),
                Text(l10n.reemplazarAsignacionSeccionReemplazo, style: AppTypography.label),
                const SizedBox(height: AppSpacing.sm),
                RisegSelect<ArticuloData?>(
                  label: l10n.asignarArticuloCampoArticulo,
                  value: articuloReemplazo,
                  items: [for (final a in articulos) RisegSelectItem(value: a, label: a.nombre)],
                  onChanged: onArticuloCambiado,
                ),
                if (articuloReemplazo != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  if (articuloReemplazo!.manejaSerie) ...[
                    if (unidadesDisponibles.isEmpty)
                      Text(l10n.asignarArticuloSinUnidadesDisponibles, style: AppTypography.body)
                    else
                      RisegSelect<String?>(
                        label: l10n.asignarArticuloCampoUnidad,
                        value: unidadId,
                        items: [
                          for (final u in unidadesDisponibles)
                            RisegSelectItem(value: u.id, label: '${u.codigo} · ${u.numeroSerie}'),
                        ],
                        onChanged: (valor) => setState(() => unidadId = valor),
                      ),
                  ] else ...[
                    if (articuloReemplazo!.manejaVariante) ...[
                      RisegSelect<String?>(
                        label: l10n.asignarArticuloCampoVariante,
                        value: varianteId,
                        items: [for (final v in variantes) RisegSelectItem(value: v.id, label: v.valor)],
                        onChanged: (valor) => setState(() => varianteId = valor),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    RisegTextField(label: l10n.asignarArticuloCampoCantidad, controller: cantidadCtrl, keyboardType: TextInputType.number),
                  ],
                ],
                const SizedBox(height: AppSpacing.md),
                RisegDateField(
                  label: l10n.asignarArticuloCampoFecha,
                  value: fechaCierre,
                  onChanged: (valor) => setState(() => fechaCierre = valor),
                ),
                const SizedBox(height: AppSpacing.md),
                RisegTextField(label: l10n.asignarArticuloCampoCondicion, controller: condicionCtrl),
                if (errorGeneral != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(errorGeneral!, style: AppTypography.caption.copyWith(color: Theme.of(dialogContext).colorScheme.error)),
                ],
              ],
            ),
          ),
        );
      },
    ),
    onConfirm: () async {
      if (articuloReemplazo == null) {
        errorGeneral = l10n.reemplazarAsignacionErrorArticuloRequerido;
        return null;
      }

      int cantidad = 1;
      if (!articuloReemplazo!.manejaSerie) {
        if (articuloReemplazo!.manejaVariante && varianteId == null) {
          errorGeneral = l10n.reemplazarAsignacionErrorVarianteInvalida;
          return null;
        }
        final parsed = int.tryParse(cantidadCtrl.text.trim());
        if (parsed == null || parsed <= 0) {
          errorGeneral = l10n.reemplazarAsignacionErrorCantidadInvalida;
          return null;
        }
        cantidad = parsed;
      } else if (unidadId == null) {
        errorGeneral = l10n.reemplazarAsignacionErrorUnidadInvalida;
        return null;
      }

      final importe = double.tryParse(importeCtrl.text.trim().replaceAll(',', ''));
      final resultado = await reemplazarAsignacion.ejecutar(
        asignacionId: asignacion.id,
        motivo: motivo,
        fechaCierre: fechaCierre ?? DateTime.now(),
        observacionesCierre: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
        atribuibleAlEmpleado: atribuibleAlEmpleado,
        generaDescuento: generaDescuento,
        importeDescuento: importe == null ? null : (importe * 100).round(),
        empleadoResponsableDescuentoId: empleadoResponsableId,
        articuloIdReemplazo: articuloReemplazo!.id,
        varianteIdReemplazo: varianteId,
        unidadIdReemplazo: unidadId,
        cantidadReemplazo: cantidad,
        condicionEntregaReemplazo: condicionCtrl.text.trim().isEmpty ? null : condicionCtrl.text.trim(),
      );
      if (!context.mounted) return false;
      switch (resultado) {
        case ReemplazarAsignacionExitoso():
          RisegFeedback.showSuccess(context, l10n.reemplazarAsignacionExito);
          return true;
        case ReemplazarAsignacionObservacionesRequeridas():
          errorGeneral = l10n.cerrarAsignacionErrorObservacionesRequeridas;
          return null;
        case ReemplazarAsignacionAtribucionRequerida():
          errorGeneral = l10n.cerrarAsignacionErrorAtribucionRequerida;
          return null;
        case ReemplazarAsignacionDescuentoInvalido():
          errorGeneral = l10n.cerrarAsignacionErrorDescuentoInvalido;
          return null;
        case ReemplazarAsignacionReemplazoVarianteInvalida():
          errorGeneral = l10n.reemplazarAsignacionErrorVarianteInvalida;
          return null;
        case ReemplazarAsignacionReemplazoUnidadInvalida():
          errorGeneral = l10n.reemplazarAsignacionErrorUnidadInvalida;
          return null;
        case ReemplazarAsignacionReemplazoUnidadNoDisponible():
          errorGeneral = l10n.reemplazarAsignacionErrorUnidadNoDisponible;
          return null;
        case ReemplazarAsignacionReemplazoCantidadInvalida():
          errorGeneral = l10n.reemplazarAsignacionErrorCantidadInvalida;
          return null;
        case ReemplazarAsignacionReemplazoSobrepasaDisponible():
          errorGeneral = l10n.reemplazarAsignacionErrorSobrepasaDisponible;
          return null;
        case ReemplazarAsignacionNoExiste():
        case ReemplazarAsignacionYaCerrada():
        case ReemplazarAsignacionReemplazoArticuloNoExiste():
        case ReemplazarAsignacionReemplazoDestinoInvalido():
        case ReemplazarAsignacionErrorInesperado():
          RisegFeedback.showError(context, l10n.reemplazarAsignacionErrorInesperado);
          return false;
      }
    },
  );

  observacionesCtrl.dispose();
  importeCtrl.dispose();
  cantidadCtrl.dispose();
  condicionCtrl.dispose();

  return resultado ?? false;
}
