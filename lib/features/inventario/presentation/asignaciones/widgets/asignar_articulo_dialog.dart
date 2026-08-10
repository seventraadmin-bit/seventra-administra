import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';

/// Diálogo "Asignar artículo" (Etapa 7B) — entrega un Artículo/
/// variante/unidad a un Empleado o Servicio (exactamente uno de los
/// dos). Nunca captura texto libre: variante/unidad siempre se elige
/// de lo que el catálogo/existencia ya tiene.
Future<bool> mostrarDialogoAsignarArticulo(
  BuildContext context,
  WidgetRef ref, {
  String? empleadoId,
  String? servicioId,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final articuloRepo = ref.read(articuloRepositoryProvider);
  final inventarioRepo = ref.read(inventarioRepositoryProvider);
  final crearAsignacion = ref.read(crearAsignacionUseCaseProvider);

  final articulos = await articuloRepo.listar();
  if (!context.mounted) return false;

  ArticuloData? articulo;
  List<ArticuloVarianteData> variantes = const [];
  List<ArticuloUnidadData> unidadesDisponibles = const [];
  String? varianteId;
  String? unidadId;
  final cantidadCtrl = TextEditingController(text: '1');
  final condicionCtrl = TextEditingController();
  final observacionesCtrl = TextEditingController();
  DateTime? fechaEntrega = DateTime.now();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.asignarArticuloDialogoTitulo,
    confirmLabel: l10n.asignarArticuloBotonConfirmar,
    cancelLabel: l10n.asignarArticuloBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        Future<void> onArticuloCambiado(ArticuloData? nuevo) async {
          setState(() {
            articulo = nuevo;
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

        return SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegSelect<ArticuloData?>(
                label: l10n.asignarArticuloCampoArticulo,
                value: articulo,
                items: [for (final a in articulos) RisegSelectItem(value: a, label: a.nombre)],
                onChanged: onArticuloCambiado,
              ),
              if (articulo != null) ...[
                const SizedBox(height: AppSpacing.md),
                if (articulo!.manejaSerie) ...[
                  if (unidadesDisponibles.isEmpty)
                    Text(l10n.asignarArticuloSinUnidadesDisponibles, style: AppTypography.body)
                  else
                    RisegSelect<String?>(
                      label: l10n.asignarArticuloCampoUnidad,
                      value: unidadId,
                      items: [
                        for (final u in unidadesDisponibles) RisegSelectItem(value: u.id, label: '${u.codigo} · ${u.numeroSerie}'),
                      ],
                      onChanged: (valor) => setState(() => unidadId = valor),
                    ),
                ] else ...[
                  if (articulo!.manejaVariante) ...[
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
                value: fechaEntrega,
                onChanged: (valor) => setState(() => fechaEntrega = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.asignarArticuloCampoCondicion, controller: condicionCtrl),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.asignarArticuloCampoObservaciones, controller: observacionesCtrl),
              if (errorGeneral != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(errorGeneral!, style: AppTypography.caption.copyWith(color: Theme.of(dialogContext).colorScheme.error)),
              ],
            ],
          ),
        );
      },
    ),
    onConfirm: () async {
      if (articulo == null) {
        errorGeneral = l10n.asignarArticuloErrorArticuloRequerido;
        return null;
      }

      int cantidad = 1;
      if (!articulo!.manejaSerie) {
        if (articulo!.manejaVariante && varianteId == null) {
          errorGeneral = l10n.asignarArticuloErrorVarianteInvalida;
          return null;
        }
        final parsed = int.tryParse(cantidadCtrl.text.trim());
        if (parsed == null || parsed <= 0) {
          errorGeneral = l10n.asignarArticuloErrorCantidadInvalida;
          return null;
        }
        cantidad = parsed;
      } else if (unidadId == null) {
        errorGeneral = l10n.asignarArticuloErrorUnidadInvalida;
        return null;
      }

      final resultado = await crearAsignacion.ejecutar(
        articuloId: articulo!.id,
        varianteId: varianteId,
        unidadId: unidadId,
        cantidad: cantidad,
        empleadoId: empleadoId,
        servicioId: servicioId,
        fechaEntrega: fechaEntrega ?? DateTime.now(),
        condicionEntrega: condicionCtrl.text.trim().isEmpty ? null : condicionCtrl.text.trim(),
        observaciones: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
      );
      if (!context.mounted) return false;
      switch (resultado) {
        case CrearAsignacionExitoso():
          RisegFeedback.showSuccess(context, l10n.asignarArticuloExito);
          return true;
        case CrearAsignacionVarianteInvalida():
          errorGeneral = l10n.asignarArticuloErrorVarianteInvalida;
          return null;
        case CrearAsignacionUnidadInvalida():
          errorGeneral = l10n.asignarArticuloErrorUnidadInvalida;
          return null;
        case CrearAsignacionUnidadNoDisponible():
          errorGeneral = l10n.asignarArticuloErrorUnidadNoDisponible;
          return null;
        case CrearAsignacionCantidadInvalida():
          errorGeneral = l10n.asignarArticuloErrorCantidadInvalida;
          return null;
        case CrearAsignacionSobrepasaDisponible():
          errorGeneral = l10n.asignarArticuloErrorSobrepasaDisponible;
          return null;
        case CrearAsignacionArticuloNoExiste():
        case CrearAsignacionDestinoInvalido():
        case CrearAsignacionErrorInesperado():
          RisegFeedback.showError(context, l10n.asignarArticuloErrorInesperado);
          return false;
      }
    },
  );

  cantidadCtrl.dispose();
  condicionCtrl.dispose();
  observacionesCtrl.dispose();

  return resultado ?? false;
}
