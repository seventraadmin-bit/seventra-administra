import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

/// Selector de `Asignacion` activas por checkbox — reutilizado por
/// "Generar resguardo" y "Adjuntar resguardo firmado" (Etapa 7C).
/// Nunca captura texto libre: siempre a partir de la lista de
/// asignaciones ya cargada por el llamador (mismo criterio que el
/// resto de Inventario desde 7B).
Future<List<String>?> mostrarDialogoSeleccionarAsignaciones(
  BuildContext context, {
  required List<AsignacionData> asignaciones,
  required String Function(AsignacionData) detalleBuilder,
  required String titulo,
  required String botonConfirmar,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final seleccionadas = <String>{if (asignaciones.length == 1) asignaciones.single.id};

  return showDialog<List<String>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return AlertDialog(
          title: Text(titulo),
          content: SizedBox(
            width: 420,
            child: asignaciones.isEmpty
                ? Text(l10n.seleccionarAsignacionesCampoVacio)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final asignacion in asignaciones)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                          value: seleccionadas.contains(asignacion.id),
                          onChanged: (marcado) => setState(() {
                            if (marcado ?? false) {
                              seleccionadas.add(asignacion.id);
                            } else {
                              seleccionadas.remove(asignacion.id);
                            }
                          }),
                          title: Text(detalleBuilder(asignacion)),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.seleccionarAsignacionesBotonCancelar),
            ),
            RisegButton(
              label: botonConfirmar,
              onPressed: seleccionadas.isEmpty ? null : () => Navigator.of(dialogContext).pop(seleccionadas.toList()),
            ),
          ],
        );
      },
    ),
  );
}
