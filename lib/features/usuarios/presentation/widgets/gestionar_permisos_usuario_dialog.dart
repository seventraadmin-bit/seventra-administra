import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/permissions/modulos_permiso.dart';

import '../../domain/usecases/guardar_permisos_usuario_usecase.dart';
import '../usuarios_controller.dart';
import 'permiso_labels.dart';

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
        void alternar(String codigo, bool marcado) {
          setState(() {
            final nuevo = Set<String>.from(seleccionados);
            if (marcado) {
              nuevo.add(codigo);
            } else {
              nuevo.remove(codigo);
              // Si se desmarca Ver, las demás acciones base del mismo
              // módulo se desmarcan también (Etapa 11B, punto 4) — la
              // dirección contraria a `normalizarPermisos` (que solo
              // agrega Ver cuando falta, nunca retira nada).
              for (final modulo in modulosPermiso) {
                if (modulo.codigoPara(AccionBase.ver) == codigo) {
                  nuevo.removeAll(modulo.accionesBase.map(modulo.codigoPara));
                }
              }
            }
            seleccionados = normalizarPermisos(nuevo);
          });
        }

        return SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final modulo in modulosPermiso) ...[
                  _FilaModuloPermiso(
                    modulo: modulo,
                    seleccionados: seleccionados,
                    onCambio: alternar,
                    onMarcarTodo: () => setState(() {
                      final nuevo = Set<String>.from(seleccionados)..addAll(modulo.todosLosCodigos);
                      seleccionados = normalizarPermisos(nuevo);
                    }),
                    onQuitarTodo: () => setState(() {
                      final nuevo = Set<String>.from(seleccionados)
                        ..removeAll(modulo.todosLosCodigos);
                      seleccionados = nuevo;
                    }),
                  ),
                  const Divider(height: AppSpacing.lg),
                ],
                if (errorGeneral != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(errorGeneral!, style: AppTypography.caption.copyWith(color: context.colors.error)),
                  ),
              ],
            ),
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
        case GuardarPermisosUsuarioErrorInesperado():
          errorGeneral = l10n.usuarioErrorInesperado;
          return false;
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

class _FilaModuloPermiso extends StatelessWidget {
  const _FilaModuloPermiso({
    required this.modulo,
    required this.seleccionados,
    required this.onCambio,
    required this.onMarcarTodo,
    required this.onQuitarTodo,
  });

  final ModuloPermiso modulo;
  final Set<String> seleccionados;
  final void Function(String codigo, bool marcado) onCambio;
  final VoidCallback onMarcarTodo;
  final VoidCallback onQuitarTodo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(moduloPermisoLabel(l10n, modulo.codigo), style: AppTypography.bodyStrong),
            ),
            RisegButton(
              label: l10n.permisosBotonMarcarTodo,
              variant: RisegButtonVariant.ghost,
              size: RisegButtonSize.compact,
              onPressed: onMarcarTodo,
            ),
            RisegButton(
              label: l10n.permisosBotonQuitarTodo,
              variant: RisegButtonVariant.ghost,
              size: RisegButtonSize.compact,
              onPressed: onQuitarTodo,
            ),
          ],
        ),
        if (modulo.accionesBase.isNotEmpty)
          Wrap(
            spacing: AppSpacing.md,
            children: [
              for (final accion in AccionBase.values)
                if (modulo.accionesBase.contains(accion))
                  _CheckboxPermiso(
                    label: accionBaseLabel(l10n, accion),
                    codigo: modulo.codigoPara(accion),
                    seleccionados: seleccionados,
                    onCambio: onCambio,
                  ),
            ],
          ),
        if (modulo.accionesEspeciales.isNotEmpty)
          Wrap(
            spacing: AppSpacing.md,
            children: [
              for (final codigo in modulo.accionesEspeciales)
                _CheckboxPermiso(
                  label: permisoEspecialLabel(l10n, codigo),
                  codigo: codigo,
                  seleccionados: seleccionados,
                  onCambio: onCambio,
                ),
            ],
          ),
      ],
    );
  }
}

class _CheckboxPermiso extends StatelessWidget {
  const _CheckboxPermiso({
    required this.label,
    required this.codigo,
    required this.seleccionados,
    required this.onCambio,
  });

  final String label;
  final String codigo;
  final Set<String> seleccionados;
  final void Function(String codigo, bool marcado) onCambio;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onCambio(codigo, !seleccionados.contains(codigo)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(value: seleccionados.contains(codigo), onChanged: (v) => onCambio(codigo, v ?? false)),
          Text(label),
        ],
      ),
    );
  }
}
