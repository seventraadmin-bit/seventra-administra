import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart' show EstatusArticuloUnidad;
import 'package:riseg_one/features/inventario/data/tables/categoria_articulo_table.dart' show AplicacionEspecializadaCategoriaArticulo;
import 'package:riseg_one/features/inventario/inventario_providers.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/configurar_equipo_telefonico_usecase.dart';

import '../../telefonia_providers.dart';

/// Diálogo "Configurar equipo" (Etapa 9D) — captura IMEI 1/IMEI 2 sobre
/// una `ArticuloUnidad` serializada ya existente (nunca crea una unidad
/// nueva). Se reutiliza en dos contextos con el mismo formulario: alta
/// (sin [unidadId], el usuario elige entre las unidades serializadas
/// que aún no tienen `ArticuloUnidadTelefono`) y edición desde el propio
/// expediente del equipo (con [unidadId] fijo, precargando IMEI 1/IMEI 2
/// vigentes). Devuelve el `unidadId` configurado si tuvo éxito; `null`
/// si el usuario canceló, y cadena vacía si falló de forma inesperada
/// (mismo convenio que el resto de los diálogos de RISEG: un valor no
/// nulo cierra el diálogo, `null` desde `onConfirm` lo mantiene abierto
/// para corregir).
Future<String?> mostrarDialogoConfigurarEquipoTelefonico(
  BuildContext context,
  WidgetRef ref, {
  String? unidadId,
  String? imeiActual,
  String? imei2Actual,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final configurar = ref.read(configurarEquipoTelefonicoAutorizadoProvider);

  var unidadesElegibles = const <ArticuloUnidadData>[];
  var etiquetaPorUnidad = const <String, String>{};
  if (unidadId == null) {
    final inventarioRepo = ref.read(inventarioRepositoryProvider);
    final articuloRepo = ref.read(articuloRepositoryProvider);
    final categoriaRepo = ref.read(categoriaArticuloRepositoryProvider);
    final todas = await inventarioRepo.listarTodasUnidades();
    final elegibles = <ArticuloUnidadData>[];
    final etiquetas = <String, String>{};
    final categoriasPorId = <String, CategoriaArticuloData?>{};
    for (final unidad in todas) {
      if (EstatusArticuloUnidad.values.byName(unidad.estatus) != EstatusArticuloUnidad.disponible) continue;
      final telefono = await inventarioRepo.obtenerTelefono(unidad.id);
      if (telefono != null) continue;
      final articulo = await articuloRepo.obtenerPorId(unidad.articuloId);
      if (articulo == null || !articulo.manejaSerie) continue;
      if (!categoriasPorId.containsKey(articulo.categoriaId)) {
        categoriasPorId[articulo.categoriaId] = await categoriaRepo.obtenerPorId(articulo.categoriaId);
      }
      final categoria = categoriasPorId[articulo.categoriaId];
      if (categoria?.aplicacionEspecializada != AplicacionEspecializadaCategoriaArticulo.telefonia.name) continue;
      elegibles.add(unidad);
      final descripcion = [unidad.marca, unidad.modelo].whereType<String>().where((p) => p.trim().isNotEmpty).join(' ');
      etiquetas[unidad.id] = descripcion.isEmpty ? unidad.codigo : '${unidad.codigo} · $descripcion';
    }
    unidadesElegibles = elegibles;
    etiquetaPorUnidad = etiquetas;
  }
  if (!context.mounted) return null;

  String? unidadSeleccionada = unidadId;
  final imeiCtrl = TextEditingController(text: imeiActual ?? '');
  final imei2Ctrl = TextEditingController(text: imei2Actual ?? '');
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<String>(
    context: context,
    title: unidadId == null
        ? l10n.equipoTelefonicoConfigurarDialogoTituloAlta
        : l10n.equipoTelefonicoConfigurarDialogoTituloEdicion,
    confirmLabel: l10n.equipoTelefonicoConfigurarBotonConfirmar,
    cancelLabel: l10n.equipoTelefonicoConfigurarBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (unidadId == null) ...[
                if (unidadesElegibles.isEmpty)
                  Text(l10n.equipoTelefonicoConfigurarSinUnidadesDisponibles, style: AppTypography.body)
                else
                  RisegSelect<String?>(
                    label: l10n.equipoTelefonicoConfigurarCampoUnidad,
                    value: unidadSeleccionada,
                    items: [
                      for (final u in unidadesElegibles)
                        RisegSelectItem(value: u.id, label: etiquetaPorUnidad[u.id] ?? u.codigo),
                    ],
                    onChanged: (valor) => setState(() => unidadSeleccionada = valor),
                  ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (unidadId != null || unidadSeleccionada != null) ...[
                RisegTextField(label: l10n.equipoTelefonicoConfigurarCampoImei1, controller: imeiCtrl),
                const SizedBox(height: AppSpacing.md),
                RisegTextField(label: l10n.equipoTelefonicoConfigurarCampoImei2, controller: imei2Ctrl),
              ],
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
      final unidad = unidadSeleccionada;
      if (unidad == null) {
        errorGeneral = l10n.equipoTelefonicoConfigurarErrorUnidadRequerida;
        return null;
      }
      final resultado = await configurar(
        unidadId: unidad,
        imei: imeiCtrl.text.trim(),
        imei2: imei2Ctrl.text.trim().isEmpty ? null : imei2Ctrl.text.trim(),
      );
      if (!context.mounted) return '';
      switch (resultado) {
        case ConfigurarEquipoTelefonicoExitoso():
          RisegFeedback.showSuccess(context, l10n.equipoTelefonicoConfigurarExito);
          return unidad;
        case ConfigurarEquipoTelefonicoImei1Requerido():
          errorGeneral = l10n.equipoTelefonicoConfigurarErrorImei1Requerido;
          return null;
        case ConfigurarEquipoTelefonicoImeiDuplicado(:final detalle):
          errorGeneral = detalle;
          return null;
        case ConfigurarEquipoTelefonicoUnidadNoExiste():
        case ConfigurarEquipoTelefonicoUnidadNoSerializada():
        case ConfigurarEquipoTelefonicoErrorInesperado():
          RisegFeedback.showError(context, l10n.equipoTelefonicoConfigurarErrorInesperado);
          return '';
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    imeiCtrl.dispose();
    imei2Ctrl.dispose();
  });
  return resultado;
}
