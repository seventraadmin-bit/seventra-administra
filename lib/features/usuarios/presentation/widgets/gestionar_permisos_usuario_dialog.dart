import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/permissions/modulos_permiso.dart';

import '../../domain/usecases/guardar_permisos_usuario_usecase.dart';
import '../usuarios_controller.dart';
import 'selector_permisos.dart';

/// Diálogo "Administrar permisos — {nombre}" (Etapa 11B) — matriz de
/// checkboxes por módulo (solo las acciones reales de cada uno, nunca
/// una casilla ficticia) más una sección de permisos especiales.
///
/// Un Maestro no tiene nada que administrar aquí (sus permisos se
/// calculan siempre en memoria, ver `SessionPermissionService`) — se
/// muestra un mensaje informativo en vez de la matriz, mismo criterio
/// que ya aplica `GuardarPermisosUsuarioUseCase` en el dominio.
Future<bool> mostrarDialogoGestionarPermisosUsuario(BuildContext context, WidgetRef ref, UsuarioData usuario) async {
  final l10n = AppLocalizations.of(context)!;
  final notifier = ref.read(usuariosControllerProvider.notifier);

  if (usuario.esMaestro) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.permisosDialogoTitulo(usuario.nombre)),
        content: Text(l10n.permisosMaestroMensaje),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(l10n.vehiculoDocumentoHistorialBotonCerrar)),
        ],
      ),
    );
    return false;
  }

  var seleccionados = await notifier.obtenerPermisos(usuario.id);
  if (!context.mounted) return false;
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.permisosDialogoTitulo(usuario.nombre),
    confirmLabel: l10n.permisosBotonGuardar,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        // Etapa "Usuarios, permisos y UX de seguridad": la matriz plana
        // anterior recorría `modulosPermiso` imprimiendo una tarjeta por
        // módulo, una debajo de otra. Con el catálogo completo eso se
        // volvió una tira vertical imposible de recorrer. Ahora la
        // estructura (buscador, grupos colapsables, contadores, marcar/
        // quitar por grupo, scroll interno) vive en `SelectorPermisos`,
        // compartido con el paso "Permisos" del alta de usuario — una
        // sola implementación, nunca dos que se desincronicen.
        return SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectorPermisos(
                seleccionados: seleccionados,
                // `normalizarPermisos` garantiza que ninguna acción
                // quede concedida sin el `ver` de su módulo — misma
                // regla de siempre, aplicada en un solo lugar.
                onCambio: (nuevo) => setState(() => seleccionados = normalizarPermisos(nuevo)),
              ),
              if (errorGeneral != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(errorGeneral!, style: AppTypography.caption.copyWith(color: context.colors.error)),
                ),
            ],
          ),
        );
      },
    ),
    onConfirm: () async {
      final resultado = await notifier.guardarPermisos(usuarioId: usuario.id, codigos: seleccionados);
      switch (resultado) {
        case GuardarPermisosUsuarioExitoso():
          return true;
        case GuardarPermisosUsuarioNoExiste():
        case GuardarPermisosUsuarioEsMaestro():
          errorGeneral = l10n.usuarioErrorInesperado;
          return false;
        case GuardarPermisosUsuarioErrorInesperado(:final mensaje):
          // Una denegación de permiso llega como `ErrorInesperado` con
          // su motivo real; mostrarlo tal cual evita el genérico
          // "ocurrió un error" que ocultaba "no tiene permiso".
          errorGeneral = mensaje;
          return null;
      }
    },
  );

  final exito = resultado ?? false;
  if (exito && context.mounted) {
    RisegFeedback.showSuccess(context, l10n.permisosGuardarExito);
  } else if (!exito && errorGeneral != null && context.mounted) {
    RisegFeedback.showError(context, errorGeneral!);
  }
  return exito;
}
