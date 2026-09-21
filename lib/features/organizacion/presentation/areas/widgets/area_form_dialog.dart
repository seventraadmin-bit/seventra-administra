import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

import '../../../domain/usecases/guardar_area_resultado.dart';
import '../../../organizacion_providers.dart';
import '../areas_list_controller.dart';

/// Diálogo de alta/edición de Área (Etapa 16, tercera pasada visual) —
/// reutilizado tanto por el listado como por el expediente de Área,
/// nunca duplicado entre los dos.
Future<void> mostrarDialogoAreaAltaEdicion(BuildContext context, WidgetRef ref, {AreaData? area}) async {
  final l10n = AppLocalizations.of(context)!;
  var nombre = area?.nombre ?? '';
  var descripcion = area?.descripcion ?? '';

  final resultado = await RisegDialog.showForm<GuardarAreaResultado>(
    context: context,
    title: area == null ? l10n.areaDialogoTituloAlta : l10n.areaDialogoTituloEdicion,
    confirmLabel: l10n.areaDialogoBotonGuardar,
    cancelLabel: l10n.areaDialogoBotonCancelar,
    contentBuilder: (_) => _AreaForm(
      nombreInicial: nombre,
      descripcionInicial: descripcion,
      onCambio: (n, d) {
        nombre = n;
        descripcion = d;
      },
    ),
    onConfirm: () async {
      if (area == null) {
        return ref.read(crearAreaAutorizadoProvider)(nombre: nombre, descripcion: descripcion);
      }
      return ref.read(actualizarAreaAutorizadoProvider)(id: area.id, nombre: nombre, descripcion: descripcion);
    },
  );

  if (!context.mounted) return;

  switch (resultado) {
    case GuardarAreaExitoso():
      ref.read(areasListControllerProvider.notifier).recargar();
      RisegFeedback.showSuccess(context, l10n.areaGuardadoExito);
    case GuardarAreaNombreRequerido():
    case GuardarAreaErrorInesperado():
      RisegFeedback.showError(context, l10n.areaGuardadoError);
    case null:
      break;
  }
}

/// Contenido del diálogo de alta/edición — `StatefulWidget` propio para
/// que sus `TextEditingController` vivan y mueran con el ciclo de vida
/// real del widget.
class _AreaForm extends StatefulWidget {
  const _AreaForm({required this.nombreInicial, required this.descripcionInicial, required this.onCambio});

  final String nombreInicial;
  final String descripcionInicial;
  final void Function(String nombre, String descripcion) onCambio;

  @override
  State<_AreaForm> createState() => _AreaFormState();
}

class _AreaFormState extends State<_AreaForm> {
  late final _nombreController = TextEditingController(text: widget.nombreInicial);
  late final _descripcionController = TextEditingController(text: widget.descripcionInicial);

  @override
  void dispose() {
    _nombreController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  void _notificar() => widget.onCambio(_nombreController.text, _descripcionController.text);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegTextField(
          label: l10n.areaCampoNombre,
          controller: _nombreController,
          autofocus: true,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.areaCampoDescripcion,
          controller: _descripcionController,
          onChanged: (_) => _notificar(),
        ),
      ],
    );
  }
}
