import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/data/tables/categoria_articulo_table.dart' show AplicacionEspecializadaCategoriaArticulo;
import 'package:riseg_one/features/inventario/domain/usecases/regularizar_articulo_serializado_usecase.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';
import 'package:riseg_one/features/inventario/presentation/articulos/articulos_list_screen.dart' show formatoCosto;

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Diálogo "Regularizar artículo" (Etapa 9D, ajuste posterior) —
/// Maestro-only: convierte un Artículo que se dio de alta sin marcar
/// "maneja número de serie" (caso real: "SMARTPHONE" comprado como
/// COM-000001, que quedó como existencia por cantidad en vez de una
/// `ArticuloUnidad`) en uno correctamente serializado, dividiendo una
/// entrada histórica por cantidad en unidades reales. Nunca inventa
/// números de serie — el Maestro los captura uno por uno. Acotado a
/// Artículos cuya Categoría ya está marcada `telefonia` (mismo criterio
/// estructurado de "Configurar equipo") porque este diálogo vive en
/// Telefonía; la operación en sí es general de Inventario
/// (`RegularizarArticuloSerializadoUseCase`).
Future<bool> mostrarDialogoRegularizarArticuloSerializado(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;
  final regularizar = ref.read(regularizarArticuloSerializadoAutorizadoProvider);

  final articuloRepo = ref.read(articuloRepositoryProvider);
  final categoriaRepo = ref.read(categoriaArticuloRepositoryProvider);
  final inventarioRepo = ref.read(inventarioRepositoryProvider);

  final categorias = await categoriaRepo.listar();
  final categoriasTelefonia = categorias
      .where((c) => c.aplicacionEspecializada == AplicacionEspecializadaCategoriaArticulo.telefonia.name)
      .map((c) => c.id)
      .toSet();

  final articulosElegibles = <ArticuloData>[];
  final movimientosPorArticulo = <String, List<MovimientoInventarioData>>{};
  for (final categoriaId in categoriasTelefonia) {
    final articulos = await articuloRepo.listar(categoriaId: categoriaId);
    for (final articulo in articulos) {
      if (articulo.manejaSerie || articulo.manejaVariante) continue;
      final movimientos = await inventarioRepo.listarMovimientos(articuloId: articulo.id);
      final candidatos = movimientos
          .where((m) => m.tipoMovimiento == 'entrada' && m.unidadId == null && m.varianteId == null)
          .toList();
      if (candidatos.isEmpty) continue;
      articulosElegibles.add(articulo);
      movimientosPorArticulo[articulo.id] = candidatos;
    }
  }
  if (!context.mounted) return false;

  // Sin elegibles no se abre un formulario con un botón "Regularizar"
  // que no puede regularizar nada: se explica y se cierra. La razón
  // técnica completa vive en el doc comment, no en la cara del usuario.
  if (articulosElegibles.isEmpty) {
    await RisegDialog.showInformational(
      context: context,
      title: l10n.regularizarArticuloDialogoTitulo,
      message: l10n.regularizarArticuloSinArticulos,
      dismissLabel: l10n.regularizarArticuloBotonEntendido,
    );
    return false;
  }

  String? articuloSeleccionado;
  String? movimientoSeleccionadoId;
  final marcaCtrl = TextEditingController();
  final modeloCtrl = TextEditingController();
  var serieCtrls = <TextEditingController>[];
  var imeiCtrls = <TextEditingController>[];
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.regularizarArticuloDialogoTitulo,
    confirmLabel: l10n.regularizarArticuloBotonConfirmar,
    cancelLabel: l10n.regularizarArticuloBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final movimientosArticulo = articuloSeleccionado == null ? const <MovimientoInventarioData>[] : movimientosPorArticulo[articuloSeleccionado] ?? const [];
        final movimientoSeleccionado =
            movimientosArticulo.where((m) => m.id == movimientoSeleccionadoId).firstOrNull;

        return SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ayuda secundaria: qué hace realmente esta operación.
                // Llegar aquí ya implica que hay algo por regularizar.
                Text(
                  l10n.regularizarArticuloAyuda,
                  style: AppTypography.caption.copyWith(color: dialogContext.colors.textMuted),
                ),
                const SizedBox(height: AppSpacing.md),
                ...[
                  RisegSelect<String?>(
                    label: l10n.regularizarArticuloCampoArticulo,
                    value: articuloSeleccionado,
                    items: [
                      for (final a in articulosElegibles) RisegSelectItem(value: a.id, label: '${a.folio} · ${a.nombre}'),
                    ],
                    onChanged: (valor) => setState(() {
                      articuloSeleccionado = valor;
                      movimientoSeleccionadoId = null;
                      serieCtrls = [];
                      imeiCtrls = [];
                    }),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (articuloSeleccionado != null)
                    RisegSelect<String?>(
                      label: l10n.regularizarArticuloCampoMovimiento,
                      value: movimientoSeleccionadoId,
                      items: [
                        for (final m in movimientosArticulo)
                          RisegSelectItem(
                            value: m.id,
                            label: '${_formatoFecha.format(m.fecha)} · ${m.cantidad} · ${m.costoUnitario == null ? '—' : formatoCosto(m.costoUnitario!)}',
                          ),
                      ],
                      onChanged: (valor) => setState(() {
                        movimientoSeleccionadoId = valor;
                        final cantidad = movimientosArticulo.where((m) => m.id == valor).firstOrNull?.cantidad ?? 0;
                        serieCtrls = List.generate(cantidad, (_) => TextEditingController());
                        imeiCtrls = List.generate(cantidad, (_) => TextEditingController());
                      }),
                    ),
                  if (movimientoSeleccionado != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    RisegTextField(label: l10n.regularizarArticuloCampoMarca, controller: marcaCtrl),
                    const SizedBox(height: AppSpacing.md),
                    RisegTextField(label: l10n.regularizarArticuloCampoModelo, controller: modeloCtrl),
                    for (var i = 0; i < serieCtrls.length; i++) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(l10n.regularizarArticuloUnidadTitulo(i + 1), style: AppTypography.label),
                      const SizedBox(height: AppSpacing.xs),
                      RisegTextField(label: l10n.regularizarArticuloCampoNumeroSerie, controller: serieCtrls[i]),
                      const SizedBox(height: AppSpacing.xs),
                      RisegTextField(label: l10n.equipoTelefonicoConfigurarCampoImei1, controller: imeiCtrls[i]),
                    ],
                  ],
                ],
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
      final articuloId = articuloSeleccionado;
      final movimientoId = movimientoSeleccionadoId;
      if (articuloId == null) {
        errorGeneral = l10n.regularizarArticuloErrorArticuloRequerido;
        return null;
      }
      if (movimientoId == null) {
        errorGeneral = l10n.regularizarArticuloErrorMovimientoRequerido;
        return null;
      }
      if (serieCtrls.any((c) => c.text.trim().isEmpty)) {
        errorGeneral = l10n.regularizarArticuloErrorNumeroSerieRequerido;
        return null;
      }

      final resultado = await regularizar(
        articuloId: articuloId,
        movimientoInventarioId: movimientoId,
        unidades: [
          for (var i = 0; i < serieCtrls.length; i++)
            DatosUnidadRegularizacionInput(
              numeroSerie: serieCtrls[i].text.trim(),
              marca: marcaCtrl.text.trim().isEmpty ? null : marcaCtrl.text.trim(),
              modelo: modeloCtrl.text.trim().isEmpty ? null : modeloCtrl.text.trim(),
              imei: imeiCtrls[i].text.trim().isEmpty ? null : imeiCtrls[i].text.trim(),
            ),
        ],
      );
      if (!context.mounted) return false;
      switch (resultado) {
        case RegularizarArticuloSerializadoExitoso():
          RisegFeedback.showSuccess(context, l10n.regularizarArticuloExito);
          return true;
        case RegularizarArticuloSerializadoNumeroSerieDuplicado():
          errorGeneral = l10n.regularizarArticuloErrorNumeroSerieDuplicado;
          return null;
        case RegularizarArticuloSerializadoArticuloNoExiste():
        case RegularizarArticuloSerializadoArticuloYaManejaSerie():
        case RegularizarArticuloSerializadoArticuloManejaVariante():
        case RegularizarArticuloSerializadoMovimientoNoExiste():
        case RegularizarArticuloSerializadoMovimientoNoElegible():
        case RegularizarArticuloSerializadoCantidadNoCoincide():
        case RegularizarArticuloSerializadoNumeroSerieRequerido():
        case RegularizarArticuloSerializadoErrorInesperado():
          RisegFeedback.showError(context, l10n.regularizarArticuloErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    marcaCtrl.dispose();
    modeloCtrl.dispose();
    for (final c in serieCtrls) {
      c.dispose();
    }
    for (final c in imeiCtrls) {
      c.dispose();
    }
  });
  return resultado ?? false;
}
