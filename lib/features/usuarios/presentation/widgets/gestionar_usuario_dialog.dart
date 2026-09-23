import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/personal/presentation/empleados/empleados_list_screen.dart' show empleadoNombreCompleto;

import '../../domain/identidad_usuario.dart';
import '../../domain/usecases/cambiar_vinculo_empleado_usecase.dart';
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
///    .crear` escribe cuenta, permisos y evento en una transacción.
/// 3. **Vínculo con Empleado.** Un usuario Normal se crea eligiendo un
///    Empleado y derivando de él nombre y puesto.
///
/// **Etapa 3B — la edición deja de mentir.** Antes, editar una cuenta
/// vinculada no mostraba el vínculo por ningún lado y dejaba `nombre` y
/// `puesto` perfectamente editables: se podía renombrar desde aquí a
/// alguien cuya identidad vivía en Personal, creando en silencio la
/// segunda identidad que el vínculo existía para impedir. Ahora, si la
/// cuenta está vinculada:
///
///  * el Empleado se muestra siempre, y con él el nombre y el puesto
///    DERIVADOS — como información, no como campos deshabilitados que
///    aparentan ser corregibles;
///  * nombre y puesto no se envían: no hay forma de tocarlos desde
///    Usuarios, ni siquiera por accidente;
///  * cambiar de Empleado es una acción aparte, con su motivo y su
///    confirmación (ver `_cambiarVinculo`), nunca el efecto secundario
///    de mover un desplegable.
///
/// Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoGestionarUsuario(
  BuildContext context,
  WidgetRef ref, {
  required List<PuestoData> puestos,
  IdentidadUsuario? identidad,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final esAlta = identidad == null;
  final notifier = ref.read(usuariosControllerProvider.notifier);
  final vinculada = identidad?.estaVinculado ?? false;

  // Empleados vinculables. En el alta, para elegir; en la edición no se
  // cargan: cambiar de Empleado tiene su propia acción.
  final empleados = esAlta ? await notifier.empleadosVinculables() : const <EmpleadoData>[];
  if (!context.mounted) return false;

  final nombreCtrl = TextEditingController(text: identidad?.usuario.nombre ?? '');
  final nombreUsuarioCtrl = TextEditingController(text: identidad?.usuario.nombreUsuario ?? '');
  final passwordCtrl = TextEditingController();
  String? puestoId = identidad?.usuario.puestoId;
  String? empleadoId;
  bool esMaestro = identidad?.usuario.esMaestro ?? false;
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
              puestoId = empleado.puestoId;
            }
          });
        }

        final empleadoElegido = empleados.where((e) => e.id == empleadoId).firstOrNull;
        // En el alta, "derivada" significa que hay un Empleado elegido
        // ahora mismo; en la edición, que la cuenta ya está vinculada.
        final identidadDerivada = esAlta ? empleadoElegido != null : vinculada;

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
                      for (final e in empleados) RisegSelectItem(value: e.id, label: empleadoNombreCompleto(e)),
                    ],
                    onChanged: elegirEmpleado,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // Identidad DERIVADA: se muestra como información, no
                // como inputs apagados. Un campo deshabilitado invita a
                // intentar escribir en él; un bloque de datos dice
                // claramente de dónde vienen y dónde se corrigen.
                if (identidadDerivada) ...[
                  if (empleadoElegido != null)
                    // Alta con Empleado elegido: los datos salen del
                    // expediente que se acaba de seleccionar.
                    _IdentidadDerivada(
                      nombre: empleadoNombreCompleto(empleadoElegido),
                      puesto: empleadoElegido.puestoId == null
                          ? null
                          : puestos.where((p) => p.id == empleadoElegido.puestoId).firstOrNull?.nombre,
                      empleado: empleadoNombreCompleto(empleadoElegido),
                    )
                  else if (identidad != null)
                    // Edición de una cuenta ya vinculada: la identidad
                    // efectiva viene resuelta desde el repositorio.
                    _IdentidadDerivada(
                      nombre: identidad.nombreEfectivo,
                      puesto: identidad.nombrePuestoEfectivo,
                      empleado: identidad.nombreEfectivo,
                    ),
                  const SizedBox(height: AppSpacing.md),
                ] else ...[
                  RisegTextField(
                    key: const Key('usuario_campo_nombre'),
                    label: l10n.usuarioCampoNombre,
                    controller: nombreCtrl,
                    autofocus: true,
                    errorText: errorNombre,
                    onChanged: (_) => setState(() => errorNombre = null),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

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

                // El puesto propio sólo existe para una cuenta
                // independiente. Para una vinculada ya se mostró
                // arriba, derivado, y no hay nada que elegir.
                if (!identidadDerivada) ...[
                  const SizedBox(height: AppSpacing.md),
                  RisegSelect<String>(
                    key: const Key('usuario_select_puesto'),
                    label: l10n.usuarioCampoPuesto,
                    value: puestoId,
                    errorText: errorPuesto,
                    items: [for (final p in puestos) RisegSelectItem(value: p.id, label: p.nombre)],
                    onChanged: (valor) => setState(() {
                      puestoId = valor;
                      errorPuesto = null;
                    }),
                  ),
                ],

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
                  if (esMaestro)
                    RisegCard(
                      child: Row(
                        children: [
                          Icon(Icons.verified_user_outlined, size: 20, color: colors.info),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(child: Text(l10n.permisosMaestroMensaje, style: AppTypography.body)),
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
          // Una cuenta vinculada no manda puesto: lo toma del Empleado,
          // y que el Empleado no tenga puesto no impide crearla.
          puestoId: empleadoId == null ? puestoId : null,
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
          case CrearUsuarioEmpleadoNoExiste():
          case CrearUsuarioEmpleadoNoElegible():
            errorGeneral = l10n.usuarioErrorEmpleadoNoElegible;
            return null;
          case CrearUsuarioEmpleadoYaTieneCuenta():
            errorGeneral = l10n.usuarioErrorEmpleadoYaTieneCuenta;
            return null;
          case CrearUsuarioErrorInesperado(:final mensaje):
            // Incluye la denegación de permiso, que llega con su motivo
            // real — mostrarlo evita el genérico "ocurrió un error".
            errorGeneral = mensaje;
            return null;
        }
      } else {
        final resultado = await notifier.corregir(
          usuarioId: identidad.usuario.id,
          // Para una cuenta vinculada NO se envían nombre ni puesto: su
          // identidad la manda Personal, y este formulario no tiene voz
          // sobre ella.
          nombre: vinculada ? identidad.usuario.nombre : nombreCtrl.text,
          nombreUsuario: nombreUsuarioCtrl.text,
          puestoId: vinculada ? null : puestoId,
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

/// Cambia (o retira) el Empleado de una cuenta — acción propia, con
/// motivo obligatorio.
///
/// Está separada del formulario de edición a propósito: mover un
/// desplegable no puede reasignar de quién es una cuenta. Aquí hay que
/// elegir explícitamente y explicar por qué.
Future<bool> mostrarDialogoVinculoEmpleado(BuildContext context, WidgetRef ref, IdentidadUsuario identidad) async {
  final l10n = AppLocalizations.of(context)!;
  final notifier = ref.read(usuariosControllerProvider.notifier);

  // Se incluye al Empleado ya vinculado para que aparezca como la
  // selección vigente y no como un hueco.
  final empleados = await notifier.empleadosVinculables(incluirEmpleadoId: identidad.usuario.empleadoId);
  if (!context.mounted) return false;

  String? seleccion = identidad.usuario.empleadoId;
  final motivoCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.usuarioVinculoTitulo,
    confirmLabel: l10n.usuarioVinculoBotonConfirmar,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.usuarioVinculoAyuda,
                  style: AppTypography.caption.copyWith(color: context.colors.textMuted),
                ),
                const SizedBox(height: AppSpacing.md),
                RisegSelect<String?>(
                  key: const Key('usuario_vinculo_select'),
                  label: l10n.usuarioCampoEmpleado,
                  value: seleccion,
                  items: [
                    RisegSelectItem(value: null, label: l10n.usuarioEmpleadoSinVincular),
                    for (final e in empleados) RisegSelectItem(value: e.id, label: empleadoNombreCompleto(e)),
                  ],
                  onChanged: (valor) => setState(() => seleccion = valor),
                ),
                const SizedBox(height: AppSpacing.md),
                RisegTextField(
                  key: const Key('usuario_vinculo_motivo'),
                  label: l10n.usuarioDesactivarCampoMotivo,
                  controller: motivoCtrl,
                ),
                if (errorGeneral != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(errorGeneral!, style: AppTypography.caption.copyWith(color: context.colors.error)),
                ],
              ],
            ),
          ),
        );
      },
    ),
    onConfirm: () async {
      errorGeneral = null;
      final resultado = await notifier.cambiarVinculoEmpleado(
        usuarioId: identidad.usuario.id,
        empleadoIdNuevo: seleccion,
        motivo: motivoCtrl.text,
      );
      switch (resultado) {
        case CambiarVinculoEmpleadoExitoso():
          return true;
        case CambiarVinculoEmpleadoMotivoRequerido():
          errorGeneral = l10n.usuarioDesactivarErrorMotivoRequerido;
          return null;
        case CambiarVinculoEmpleadoSinCambio():
          errorGeneral = l10n.usuarioVinculoSinCambio;
          return null;
        case CambiarVinculoEmpleadoNoExiste():
        case CambiarVinculoEmpleadoNoElegible():
          errorGeneral = l10n.usuarioErrorEmpleadoNoElegible;
          return null;
        case CambiarVinculoEmpleadoYaTieneCuenta():
          errorGeneral = l10n.usuarioErrorEmpleadoYaTieneCuenta;
          return null;
        case CambiarVinculoEmpleadoUsuarioNoExiste():
          errorGeneral = l10n.usuarioErrorInesperado;
          return false;
        case CambiarVinculoEmpleadoErrorInesperado(:final mensaje):
          errorGeneral = mensaje;
          return null;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) => motivoCtrl.dispose());
  final exito = resultado ?? false;
  if (exito && context.mounted) RisegFeedback.showSuccess(context, l10n.usuarioVinculoExito);
  return exito;
}

/// Nombre y puesto que vienen de Personal, presentados como lo que son:
/// información derivada, con una línea que dice dónde se corrigen.
class _IdentidadDerivada extends StatelessWidget {
  const _IdentidadDerivada({required this.nombre, required this.puesto, required this.empleado});

  final String nombre;

  /// `null` cuando el Empleado no tiene puesto asignado — un estado
  /// legítimo que **no** impide crear la cuenta. Antes sí lo impedía, y
  /// además señalando un selector deshabilitado.
  final String? puesto;
  final String empleado;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return RisegCard(
      key: const Key('usuario_identidad_derivada'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.badge_outlined, size: 18, color: colors.textMuted),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Text(
                  l10n.usuarioIdentidadDerivadaAviso,
                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _Linea(etiqueta: l10n.usuarioCampoEmpleado, valor: empleado),
          const SizedBox(height: AppSpacing.xs),
          _Linea(etiqueta: l10n.usuarioCampoNombre, valor: nombre),
          const SizedBox(height: AppSpacing.xs),
          _Linea(etiqueta: l10n.usuarioCampoPuesto, valor: puesto ?? l10n.usuarioPuestoSinAsignar),
        ],
      ),
    );
  }
}

class _Linea extends StatelessWidget {
  const _Linea({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(etiqueta, style: AppTypography.label.copyWith(color: colors.textMuted)),
        ),
        Expanded(child: Text(valor, style: AppTypography.body.copyWith(color: colors.textPrimary))),
      ],
    );
  }
}
