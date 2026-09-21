import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/personal/presentation/empleados/empleados_list_screen.dart' show empleadoNombreCompleto;

import '../../domain/usecases/corregir_usuario_usecase.dart';
import '../../domain/usecases/crear_usuario_usecase.dart';
import '../usuarios_controller.dart';
import 'selector_permisos.dart';

/// Diálogo combinado de alta/edición de Usuario (Etapa 11A).
///
/// **Etapa "Usuarios, permisos y UX de seguridad" — tres cambios de
/// fondo:**
///
/// 1. **Ninguna validación recuperable cierra el diálogo.** Antes cada
///    rama de error hacía `return false`, y `RisegDialog.showForm` cierra
///    con cualquier valor NO nulo (`null` es su convenio de "corrígelo y
///    seguimos aquí"). El resultado observado: escribir una contraseña
///    corta cerraba el formulario, perdía todo lo capturado y recién
///    entonces mostraba el snackbar. Ahora cada error recuperable vuelve
///    `null` y se pinta INLINE en su propio campo.
/// 2. **Alta atómica de cuenta + permisos.** El paso "Permisos" vive en
///    este mismo diálogo y viaja junto con el alta; `UsuarioRepository
///    .crear` escribe cuenta, permisos y evento en una transacción. Ya
///    no existe la ventana en la que quedaba una cuenta sin permisos.
/// 3. **Vínculo con Empleado.** Un usuario Normal se crea eligiendo un
///    Empleado y derivando de él nombre y puesto, en vez de recapturar
///    una segunda identidad que podía divergir de la del expediente.
///
/// Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoGestionarUsuario(
  BuildContext context,
  WidgetRef ref, {
  required List<PuestoData> puestos,
  UsuarioData? usuario,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final esAlta = usuario == null;
  final notifier = ref.read(usuariosControllerProvider.notifier);

  // Empleados activos disponibles para vincular. Se cargan una sola vez
  // antes de abrir; el diálogo nunca consulta dentro del `build`.
  final empleados = esAlta ? await notifier.empleadosVinculables() : const <EmpleadoData>[];
  if (!context.mounted) return false;

  final nombreCtrl = TextEditingController(text: usuario?.nombre ?? '');
  final nombreUsuarioCtrl = TextEditingController(text: usuario?.nombreUsuario ?? '');
  final passwordCtrl = TextEditingController();
  String? puestoId = usuario?.puestoId;
  String? empleadoId;
  bool esMaestro = usuario?.esMaestro ?? false;
  var permisosIniciales = <String>{};

  // Un error por campo — el mensaje vive donde está el problema, no en
  // un snackbar que aparece después de cerrar.
  String? errorNombre;
  String? errorNombreUsuario;
  String? errorPassword;
  String? errorPuesto;
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: esAlta ? l10n.usuarioAltaTitulo : l10n.usuarioEditarTitulo,
    confirmLabel: esAlta ? l10n.usuarioAltaBotonCrear : l10n.usuarioEditarBotonGuardar,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final colors = context.colors;

        void elegirEmpleado(String? id) {
          setState(() {
            empleadoId = id;
            errorNombre = null;
            errorPuesto = null;
            final empleado = empleados.where((e) => e.id == id).firstOrNull;
            if (empleado != null) {
              // Nombre y puesto se DERIVAN del expediente: son datos de
              // Personal, no de la cuenta.
              nombreCtrl.text = empleadoNombreCompleto(empleado);
              puestoId = empleado.puestoId ?? puestoId;
            }
          });
        }

        return SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.usuarioSeccionCuenta, style: AppTypography.heading3),
                const SizedBox(height: AppSpacing.sm),
                if (esAlta) ...[
                  RisegSelect<String?>(
                    key: const Key('usuario_select_empleado'),
                    label: l10n.usuarioCampoEmpleado,
                    value: empleadoId,
                    helperText: l10n.usuarioCampoEmpleadoAyuda,
                    items: [
                      RisegSelectItem(value: null, label: l10n.usuarioEmpleadoSinVincular),
                      for (final e in empleados)
                        RisegSelectItem(value: e.id, label: empleadoNombreCompleto(e)),
                    ],
                    onChanged: elegirEmpleado,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                RisegTextField(
                  key: const Key('usuario_campo_nombre'),
                  label: l10n.usuarioCampoNombre,
                  controller: nombreCtrl,
                  autofocus: true,
                  errorText: errorNombre,
                  // Un empleado vinculado manda: su nombre es el del
                  // expediente y no se reescribe desde aquí.
                  enabled: empleadoId == null,
                  onChanged: (_) => setState(() => errorNombre = null),
                ),
                const SizedBox(height: AppSpacing.md),
                RisegTextField(
                  key: const Key('usuario_campo_nombre_usuario'),
                  label: l10n.usuarioCampoNombreUsuario,
                  controller: nombreUsuarioCtrl,
                  errorText: errorNombreUsuario,
                  onChanged: (_) => setState(() => errorNombreUsuario = null),
                ),
                if (esAlta) ...[
                  const SizedBox(height: AppSpacing.md),
                  RisegTextField(
                    key: const Key('usuario_campo_contrasena'),
                    label: l10n.usuarioCampoContrasena,
                    controller: passwordCtrl,
                    obscureText: true,
                    errorText: errorPassword,
                    helperText: l10n.usuarioCampoContrasenaTemporalAyuda,
                    onChanged: (_) => setState(() => errorPassword = null),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                RisegSelect<String>(
                  key: const Key('usuario_select_puesto'),
                  label: l10n.usuarioCampoPuesto,
                  value: puestoId,
                  errorText: errorPuesto,
                  enabled: empleadoId == null,
                  items: [for (final p in puestos) RisegSelectItem(value: p.id, label: p.nombre)],
                  onChanged: (valor) => setState(() {
                    puestoId = valor;
                    errorPuesto = null;
                  }),
                ),
                const SizedBox(height: AppSpacing.md),
                CheckboxListTile(
                  key: const Key('usuario_checkbox_maestro'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(l10n.usuarioCampoEsMaestro),
                  subtitle: Text(
                    l10n.usuarioCampoEsMaestroAyuda,
                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                  ),
                  value: esMaestro,
                  onChanged: (valor) => setState(() => esMaestro = valor ?? false),
                ),
                if (esAlta) ...[
                  const Divider(height: AppSpacing.lg),
                  Text(l10n.usuarioSeccionPermisos, style: AppTypography.heading3),
                  const SizedBox(height: AppSpacing.sm),
                  // Un Maestro no tiene permisos que elegir: su acceso es
                  // total por regla y no depende de filas individuales.
                  // Mostrarle el catálogo completo sería pedirle una
                  // decisión que no existe.
                  if (esMaestro)
                    RisegCard(
                      child: Row(
                        children: [
                          Icon(Icons.verified_user_outlined, size: 20, color: colors.info),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(l10n.permisosMaestroMensaje, style: AppTypography.body),
                          ),
                        ],
                      ),
                    )
                  else
                    SelectorPermisos(
                      alto: 320,
                      seleccionados: permisosIniciales,
                      onCambio: (nuevo) => setState(() => permisosIniciales = nuevo),
                    ),
                ],
                if (errorGeneral != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(errorGeneral!, style: AppTypography.caption.copyWith(color: colors.error)),
                ],
              ],
            ),
          ),
        );
      },
    ),
    onConfirm: () async {
      errorNombre = null;
      errorNombreUsuario = null;
      errorPassword = null;
      errorPuesto = null;
      errorGeneral = null;

      if (esAlta) {
        final resultado = await notifier.crear(
          nombre: nombreCtrl.text,
          nombreUsuario: nombreUsuarioCtrl.text,
          password: passwordCtrl.text,
          puestoId: puestoId ?? '',
          empleadoId: empleadoId,
          esMaestro: esMaestro,
          permisosIniciales: permisosIniciales,
        );
        switch (resultado) {
          case CrearUsuarioExitoso():
            return true;
          // Todo lo que sigue es RECUPERABLE: `null` mantiene el
          // diálogo abierto con los datos intactos y el error inline.
          case CrearUsuarioNombreRequerido():
            errorNombre = l10n.usuarioErrorNombreRequerido;
            return null;
          case CrearUsuarioNombreUsuarioRequerido():
            errorNombreUsuario = l10n.usuarioErrorNombreUsuarioRequerido;
            return null;
          case CrearUsuarioNombreUsuarioDuplicado():
            errorNombreUsuario = l10n.usuarioErrorNombreUsuarioDuplicado;
            return null;
          case CrearUsuarioContrasenaInvalida():
            errorPassword = l10n.usuarioErrorContrasenaInvalida;
            return null;
          case CrearUsuarioPuestoInvalido():
            errorPuesto = l10n.usuarioErrorPuestoInvalido;
            return null;
          case CrearUsuarioErrorInesperado(:final mensaje):
            // Incluye la denegación de permiso, que llega con su motivo
            // real — mostrarlo evita el genérico "ocurrió un error".
            errorGeneral = mensaje;
            return null;
        }
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
          case CorregirUsuarioNombreRequerido():
            errorNombre = l10n.usuarioErrorNombreRequerido;
            return null;
          case CorregirUsuarioNombreUsuarioRequerido():
            errorNombreUsuario = l10n.usuarioErrorNombreUsuarioRequerido;
            return null;
          case CorregirUsuarioNombreUsuarioDuplicado():
            errorNombreUsuario = l10n.usuarioErrorNombreUsuarioDuplicado;
            return null;
          case CorregirUsuarioPuestoInvalido():
            errorPuesto = l10n.usuarioErrorPuestoInvalido;
            return null;
          case CorregirUsuarioBloqueadaPorUltimoMaestro():
            errorGeneral = l10n.usuarioErrorUltimoMaestro;
            return null;
          case CorregirUsuarioNoExiste():
            errorGeneral = l10n.usuarioErrorInesperado;
            return false;
          case CorregirUsuarioErrorInesperado(:final mensaje):
            errorGeneral = mensaje;
            return null;
        }
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
  }
  return exito;
}
