import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../domain/identidad_usuario.dart';
import '../usuarios_controller.dart';
import '../usuarios_list_screen.dart';
import 'cambiar_contrasena_usuario_dialog.dart';
import 'gestionar_permisos_usuario_dialog.dart';
import 'gestionar_usuario_dialog.dart';
import 'historial_usuario_dialog.dart';
import 'permiso_labels.dart';

final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Abre la ficha de una cuenta. Mismo patrón que la Bóveda: un diálogo
/// sobre el listado, nunca una ruta ni una entrada de sidebar nuevas.
Future<void> mostrarFichaUsuario(BuildContext context, String usuarioId) {
  return showDialog<void>(context: context, builder: (_) => UsuarioDetalleDialog(usuarioId: usuarioId));
}

/// Ficha de detalle de una cuenta (Etapa 3B).
///
/// Carga **por id**, nunca buscando en la lista del controlador: esa
/// lista puede estar filtrada, y la ficha tiene que seguir teniendo
/// datos justo después de la acción que acaba de cambiarlos (lección de
/// la Bóveda, donde dar de baja dejaba la ficha abierta en blanco).
///
/// No muestra ningún dato técnico: ni identificadores, ni el hash de la
/// contraseña, ni el nombre interno de ninguna columna.
class UsuarioDetalleDialog extends ConsumerStatefulWidget {
  const UsuarioDetalleDialog({required this.usuarioId, super.key});

  final String usuarioId;

  @override
  ConsumerState<UsuarioDetalleDialog> createState() => _UsuarioDetalleDialogState();
}

class _UsuarioDetalleDialogState extends ConsumerState<UsuarioDetalleDialog> {
  IdentidadUsuario? _identidad;
  Set<String>? _permisos;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_recargar);
  }

  /// Dos consultas dirigidas para UNA cuenta: su identidad y sus
  /// permisos. Abrir una ficha nunca toca a las demás cuentas.
  ///
  /// A un Maestro no se le consultan permisos: no tiene filas que leer
  /// (su acceso se calcula del catálogo), así que preguntarlo sería una
  /// consulta garantizada a devolver vacío y una invitación a pintar
  /// "sin permisos" sobre quien los tiene todos.
  Future<void> _recargar() async {
    final identidad = await ref.read(usuariosControllerProvider.notifier).obtenerIdentidad(widget.usuarioId);
    Set<String>? permisos;
    if (identidad != null && !identidad.usuario.esMaestro) {
      permisos = await ref.read(permisoUsuarioRepositoryProvider).obtenerCodigos(widget.usuarioId);
    }
    if (!mounted) return;
    setState(() {
      _identidad = identidad;
      _permisos = permisos;
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // La ficha se redibuja cuando el listado cambia: así una acción
    // lanzada desde aquí actualiza a la vez la fila de atrás y estos
    // campos, sin cerrar nada.
    ref.listen(usuariosControllerProvider, (_, __) => _recargar());

    if (_cargando) {
      return _Marco(
        titulo: l10n.usuarioFichaTitulo,
        cuerpo: const SizedBox(height: 140, child: Center(child: CircularProgressIndicator())),
        acciones: const [],
      );
    }

    final identidad = _identidad;
    if (identidad == null) {
      return _Marco(
        titulo: l10n.usuarioFichaTitulo,
        cuerpo: Text(l10n.usuarioErrorInesperado),
        acciones: const [],
      );
    }

    final permisos = ref.read(permissionServiceProvider);
    final puedeAdministrar = permisos.hasCode('usuarios.administrar');
    final puedeResetear = permisos.hasCode('usuarios.resetearPassword');
    final puedeOtorgar = permisos.hasCode('usuarios.otorgarPermisos');

    return _Marco(
      titulo: l10n.usuarioFichaTitulo,
      cuerpo: _Cuerpo(identidad: identidad, permisos: _permisos),
      acciones: [
        if (puedeAdministrar)
          RisegButton(
            key: const Key('usuario_ficha_editar'),
            label: l10n.usuariosAccionEditar,
            variant: RisegButtonVariant.secondary,
            onPressed: () =>
                mostrarDialogoGestionarUsuario(context, ref, puestos: _puestosActivos(), identidad: identidad),
          ),
        if (puedeResetear)
          RisegButton(
            label: l10n.usuariosAccionCambiarContrasena,
            variant: RisegButtonVariant.secondary,
            onPressed: () => mostrarDialogoCambiarContrasenaUsuario(context, ref, identidad.usuario),
          ),
        if (puedeOtorgar)
          RisegButton(
            key: const Key('usuario_ficha_permisos'),
            label: l10n.usuariosAccionPermisos,
            variant: RisegButtonVariant.secondary,
            onPressed: () => mostrarDialogoGestionarPermisosUsuario(context, ref, identidad.usuario),
          ),
        if (puedeAdministrar)
          RisegButton(
            key: const Key('usuario_ficha_vinculo'),
            label: l10n.usuarioVinculoTitulo,
            variant: RisegButtonVariant.secondary,
            onPressed: () => mostrarDialogoVinculoEmpleado(context, ref, identidad),
          ),
        RisegButton(
          label: l10n.usuariosAccionHistorial,
          variant: RisegButtonVariant.secondary,
          onPressed: () => mostrarDialogoHistorialUsuario(context, ref, identidad.usuario),
        ),
        if (puedeAdministrar)
          RisegButton(
            key: const Key('usuario_ficha_estado'),
            label: identidad.cuentaActiva ? l10n.usuariosAccionDesactivar : l10n.usuariosAccionActivar,
            variant: RisegButtonVariant.secondary,
            onPressed: () => identidad.cuentaActiva
                ? desactivarUsuarioConMotivo(context, ref, identidad)
                : reactivarUsuario(context, ref, identidad),
          ),
      ],
    );
  }

  List<PuestoData> _puestosActivos() => ref.read(usuariosControllerProvider).puestos;
}

class _Cuerpo extends StatelessWidget {
  const _Cuerpo({required this.identidad, required this.permisos});

  final IdentidadUsuario identidad;

  /// `null` para un Maestro — no tiene filas de permiso, y decirlo es
  /// distinto de decir "ninguno".
  final Set<String>? permisos;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final u = identidad.usuario;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: Text(identidad.nombreEfectivo, style: AppTypography.heading2)),
            const SizedBox(width: AppSpacing.xs),
            RisegStatusBadge(
              label: identidad.cuentaActiva ? l10n.usuarioEstadoActivo : l10n.usuarioEstadoInactivo,
              tone: identidad.cuentaActiva ? RisegStatusTone.success : RisegStatusTone.neutral,
            ),
            const SizedBox(width: AppSpacing.xxs),
            RisegStatusBadge(
              label: u.esMaestro ? l10n.usuarioTipoMaestro : l10n.usuarioTipoNormal,
              tone: u.esMaestro ? RisegStatusTone.warning : RisegStatusTone.neutral,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // Un aviso, no un error: una cuenta inactiva porque la persona
        // causó baja necesita explicarse, o alguien intentará
        // reactivarla y no entenderá por qué no puede.
        if (identidad.empleadoDeBaja) ...[
          RisegCard(
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: colors.info),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: Text(l10n.usuarioFichaAvisoEmpleadoDeBaja, style: AppTypography.body)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        Wrap(
          spacing: AppSpacing.xl,
          runSpacing: AppSpacing.sm,
          children: [
            _Dato(etiqueta: l10n.usuariosColumnaUsuario, valor: u.nombreUsuario),
            _Dato(
              etiqueta: l10n.usuariosColumnaPuesto,
              valor: identidad.nombrePuestoEfectivo ?? l10n.usuarioPuestoSinAsignar,
            ),
            _Dato(
              etiqueta: l10n.usuariosColumnaUltimoAcceso,
              valor: u.ultimoAccesoAt == null
                  ? l10n.usuarioFichaSinAccesos
                  : _formatoFechaHora.format(u.ultimoAccesoAt!),
            ),
            _Dato(
              key: const Key('usuario_ficha_empleado'),
              etiqueta: l10n.usuarioCampoEmpleado,
              valor: identidad.estaVinculado ? identidad.nombreEfectivo : l10n.usuarioEmpleadoSinVincular,
            ),
          ],
        ),

        if (u.debeCambiarPassword) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(Icons.lock_clock_outlined, size: 18, color: colors.warning),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Text(
                  l10n.usuarioFichaContrasenaTemporal,
                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                ),
              ),
            ],
          ),
        ],

        const Divider(height: AppSpacing.lg),
        Text(l10n.usuarioSeccionPermisos, style: AppTypography.heading3),
        const SizedBox(height: AppSpacing.xs),
        _Permisos(esMaestro: u.esMaestro, permisos: permisos),
      ],
    );
  }
}

/// El acceso de la cuenta, dicho como es.
///
/// A un Maestro NO se le pinta una lista vacía ni se le inventan filas:
/// su acceso es total por regla y no depende de permisos individuales.
/// Fingir lo contrario sería mentir sobre lo único que esta sección
/// tiene que comunicar.
class _Permisos extends StatelessWidget {
  const _Permisos({required this.esMaestro, required this.permisos});

  final bool esMaestro;
  final Set<String>? permisos;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    if (esMaestro) {
      return RisegCard(
        child: Row(
          children: [
            Icon(Icons.verified_user_outlined, size: 20, color: colors.info),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: Text(l10n.permisosMaestroMensaje, style: AppTypography.body)),
          ],
        ),
      );
    }

    final codigos = permisos ?? const <String>{};
    if (codigos.isEmpty) {
      return Text(
        l10n.usuarioFichaSinPermisos,
        key: const Key('usuario_ficha_permisos_resumen'),
        style: AppTypography.body.copyWith(color: colors.textMuted),
      );
    }

    // Resumen por módulo, no la lista de 20+ códigos: la ficha informa,
    // y quien necesite el detalle abre "Permisos". Las etiquetas son
    // las humanas del catálogo, nunca el código técnico.
    final modulos = <String>{for (final c in codigos) c.split('.').first};
    final nombres = [for (final m in modulos) moduloPermisoLabel(l10n, m)]..sort();

    return Text(
      key: const Key('usuario_ficha_permisos_resumen'),
      l10n.usuarioFichaResumenPermisos(codigos.length, nombres.join(', ')),
      style: AppTypography.body,
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.etiqueta, required this.valor, super.key});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(etiqueta, style: AppTypography.label.copyWith(color: colors.textMuted)),
          const SizedBox(height: AppSpacing.xxs),
          Text(valor, style: AppTypography.body.copyWith(color: colors.textPrimary)),
        ],
      ),
    );
  }
}

/// Mismo armazón que la ficha de la Bóveda: ancho acotado, scroll
/// propio y acciones en `Wrap` para que a 500px bajen de línea en vez
/// de desbordarse.
class _Marco extends StatelessWidget {
  const _Marco({required this.titulo, required this.cuerpo, required this.acciones});

  final String titulo;
  final Widget cuerpo;
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(titulo, style: AppTypography.heading3),
                const SizedBox(height: AppSpacing.md),
                cuerpo,
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    ...acciones,
                    RisegButton(
                      label: l10n.compraBotonCancelarFormulario,
                      variant: RisegButtonVariant.ghost,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
