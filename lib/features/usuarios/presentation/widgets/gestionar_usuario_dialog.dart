import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

import '../../domain/usecases/corregir_usuario_usecase.dart';
import '../../domain/usecases/crear_usuario_usecase.dart';
import '../usuarios_controller.dart';

/// Diálogo combinado de alta/edición de Usuario (Etapa 11A) — si
/// [usuario] es `null` es un alta (captura Nombre/Usuario/Contraseña/
/// Puesto/Maestro); si no, una edición (mismos campos salvo la
/// contraseña, que tiene su propio diálogo —
/// `mostrarDialogoCambiarContrasenaUsuario`, mismo criterio que en
/// cada dominio del proyecto de no mezclar datos administrativos con
/// cambios ya comprometidos). Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoGestionarUsuario(
  BuildContext context,
  WidgetRef ref, {
  required List<PuestoData> puestos,
  UsuarioData? usuario,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final esAlta = usuario == null;
  final notifier = ref.read(usuariosControllerProvider.notifier);

  final nombreCtrl = TextEditingController(text: usuario?.nombre ?? '');
  final nombreUsuarioCtrl = TextEditingController(text: usuario?.nombreUsuario ?? '');
  final passwordCtrl = TextEditingController();
  String? puestoId = usuario?.puestoId;
  bool esMaestro = usuario?.esMaestro ?? false;
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: esAlta ? l10n.usuarioAltaTitulo : l10n.usuarioEditarTitulo,
    confirmLabel: esAlta ? l10n.usuarioAltaBotonCrear : l10n.usuarioEditarBotonGuardar,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegTextField(label: l10n.usuarioCampoNombre, controller: nombreCtrl, autofocus: true),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.usuarioCampoNombreUsuario, controller: nombreUsuarioCtrl),
              if (esAlta) ...[
                const SizedBox(height: AppSpacing.md),
                RisegTextField(label: l10n.usuarioCampoContrasena, controller: passwordCtrl, obscureText: true),
              ],
              const SizedBox(height: AppSpacing.md),
              RisegSelect<String>(
                label: l10n.usuarioCampoPuesto,
                value: puestoId,
                items: [for (final p in puestos) RisegSelectItem(value: p.id, label: p.nombre)],
                onChanged: (valor) => setState(() => puestoId = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              CheckboxListTile(
                key: const Key('usuario_checkbox_maestro'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(l10n.usuarioCampoEsMaestro),
                value: esMaestro,
                onChanged: (valor) => setState(() => esMaestro = valor ?? false),
              ),
              if (errorGeneral != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(errorGeneral!, style: AppTypography.caption.copyWith(color: context.colors.error)),
              ],
            ],
          ),
        );
      },
    ),
    onConfirm: () async {
      if (esAlta) {
        final resultado = await notifier.crear(
          nombre: nombreCtrl.text,
          nombreUsuario: nombreUsuarioCtrl.text,
          password: passwordCtrl.text,
          puestoId: puestoId ?? '',
          esMaestro: esMaestro,
        );
        switch (resultado) {
          case CrearUsuarioExitoso():
            return true;
          case CrearUsuarioNombreRequerido():
            errorGeneral = l10n.usuarioErrorNombreRequerido;
          case CrearUsuarioNombreUsuarioRequerido():
            errorGeneral = l10n.usuarioErrorNombreUsuarioRequerido;
          case CrearUsuarioNombreUsuarioDuplicado():
            errorGeneral = l10n.usuarioErrorNombreUsuarioDuplicado;
          case CrearUsuarioContrasenaInvalida():
            errorGeneral = l10n.usuarioErrorContrasenaInvalida;
          case CrearUsuarioPuestoInvalido():
            errorGeneral = l10n.usuarioErrorPuestoInvalido;
          case CrearUsuarioErrorInesperado():
            errorGeneral = l10n.usuarioErrorInesperado;
        }
        return false;
      } else {
        final resultado = await notifier.corregir(
          usuarioId: usuario.id,
          nombre: nombreCtrl.text,
          nombreUsuario: nombreUsuarioCtrl.text,
          puestoId: puestoId ?? '',
          esMaestro: esMaestro,
        );
        switch (resultado) {
          case CorregirUsuarioExitoso():
            return true;
          case CorregirUsuarioNoExiste():
            errorGeneral = l10n.usuarioErrorInesperado;
          case CorregirUsuarioNombreRequerido():
            errorGeneral = l10n.usuarioErrorNombreRequerido;
          case CorregirUsuarioNombreUsuarioRequerido():
            errorGeneral = l10n.usuarioErrorNombreUsuarioRequerido;
          case CorregirUsuarioNombreUsuarioDuplicado():
            errorGeneral = l10n.usuarioErrorNombreUsuarioDuplicado;
          case CorregirUsuarioPuestoInvalido():
            errorGeneral = l10n.usuarioErrorPuestoInvalido;
          case CorregirUsuarioBloqueadaPorUltimoMaestro():
            errorGeneral = l10n.usuarioErrorUltimoMaestro;
          case CorregirUsuarioErrorInesperado():
            errorGeneral = l10n.usuarioErrorInesperado;
        }
        return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    nombreCtrl.dispose();
    nombreUsuarioCtrl.dispose();
    passwordCtrl.dispose();
  });

  final exito = resultado ?? false;
  if (exito && context.mounted) {
    RisegFeedback.showSuccess(context, esAlta ? l10n.usuarioCrearExito : l10n.usuarioEditarExito);
  } else if (!exito && errorGeneral != null && context.mounted) {
    RisegFeedback.showError(context, errorGeneral!);
  }
  return exito;
}
