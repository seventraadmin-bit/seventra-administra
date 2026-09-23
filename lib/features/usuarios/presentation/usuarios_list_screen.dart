import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

import '../domain/identidad_usuario.dart';
import '../domain/usecases/activar_usuario_usecase.dart';
import '../domain/usecases/desactivar_usuario_usecase.dart';
import 'sesion_controller.dart';
import 'usuarios_controller.dart';
import 'widgets/cambiar_contrasena_usuario_dialog.dart';
import 'widgets/gestionar_permisos_usuario_dialog.dart';
import 'widgets/gestionar_usuario_dialog.dart';
import 'widgets/historial_usuario_dialog.dart';
import 'widgets/usuario_detalle_dialog.dart';

final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Desactiva una cuenta pidiendo motivo — compartido por el listado y
/// por la ficha de detalle, para que la regla (motivo obligatorio,
/// último Maestro bloqueado) tenga una sola implementación.
Future<bool> desactivarUsuarioConMotivo(BuildContext context, WidgetRef ref, IdentidadUsuario identidad) async {
  final l10n = AppLocalizations.of(context)!;
  final motivoCtrl = TextEditingController();
  String? errorGeneral;

  final confirmado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.usuarioDesactivarDialogoTitulo(identidad.nombreEfectivo),
    confirmLabel: l10n.usuarioDesactivarBotonConfirmar,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegTextField(label: l10n.usuarioDesactivarCampoMotivo, controller: motivoCtrl, autofocus: true),
            if (errorGeneral != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                errorGeneral!,
                style: AppTypography.caption.copyWith(color: Theme.of(dialogContext).colorScheme.error),
              ),
            ],
          ],
        );
      },
    ),
    onConfirm: () async {
      final motivo = motivoCtrl.text.trim();
      if (motivo.isEmpty) {
        errorGeneral = l10n.usuarioDesactivarErrorMotivoRequerido;
        return null;
      }
      final resultado = await ref
          .read(usuariosControllerProvider.notifier)
          .desactivar(usuarioId: identidad.usuario.id, motivo: motivo);
      if (!context.mounted) return false;
      switch (resultado) {
        case DesactivarUsuarioExitoso():
          return true;
        case DesactivarUsuarioMotivoRequerido():
          errorGeneral = l10n.usuarioDesactivarErrorMotivoRequerido;
          return null;
        case DesactivarUsuarioBloqueadaPorUltimoMaestro():
          RisegFeedback.showError(context, l10n.usuarioErrorUltimoMaestro);
          return false;
        case DesactivarUsuarioNoExiste():
        case DesactivarUsuarioYaInactivo():
        case DesactivarUsuarioErrorInesperado():
          RisegFeedback.showError(context, l10n.usuarioErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) => motivoCtrl.dispose());
  final exito = confirmado ?? false;
  if (exito && context.mounted) RisegFeedback.showSuccess(context, l10n.usuarioDesactivarExito);
  return exito;
}

/// Reactiva una cuenta. Puede fallar porque la persona sigue de baja
/// laboral: eso no es un error del sistema, es una regla, y se explica
/// como tal.
Future<bool> reactivarUsuario(BuildContext context, WidgetRef ref, IdentidadUsuario identidad) async {
  final l10n = AppLocalizations.of(context)!;
  final resultado = await ref.read(usuariosControllerProvider.notifier).activar(identidad.usuario.id);
  if (!context.mounted) return false;
  switch (resultado) {
    case ActivarUsuarioExitoso():
      RisegFeedback.showSuccess(context, l10n.usuarioActivarExito);
      return true;
    case ActivarUsuarioEmpleadoDeBaja(:final nombreEmpleado):
      RisegFeedback.showError(context, l10n.usuarioErrorReactivarEmpleadoDeBaja(nombreEmpleado));
      return false;
    case ActivarUsuarioNoExiste():
    case ActivarUsuarioYaActivo():
    case ActivarUsuarioErrorInesperado():
      RisegFeedback.showError(context, l10n.usuarioErrorInesperado);
      return false;
  }
}

/// Listado + CRUD de Usuarios (Etapa 11A) — primera funcionalidad real
/// de `/configuracion`. Desde la Etapa 11B gana "Administrar permisos"
/// (matriz dinámica).
///
/// **Etapa 3B:** la tabla muestra la identidad EFECTIVA de cada cuenta
/// (la del Empleado si está vinculada, la propia si no), la fila abre
/// una ficha de detalle, y las cinco acciones sueltas se recogen en un
/// menú ⋮ — mismo patrón que la Bóveda, y una columna de acciones que
/// dejó de competir con el resto por el ancho.
class UsuariosListScreen extends ConsumerWidget {
  const UsuariosListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(usuariosControllerProvider);
    final sesion = ref.watch(sesionControllerProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.usuariosListadoTitulo,
            primaryAction: RisegButton(
              key: const Key('usuarios_boton_crear'),
              label: l10n.usuariosListadoBotonCrear,
              onPressed: () => mostrarDialogoGestionarUsuario(context, ref, puestos: state.puestos),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<IdentidadUsuario>(
              loading: state.cargando,
              rows: state.identidades,
              onRowTap: (i) => mostrarFichaUsuario(context, i.usuario.id),
              emptyState: RisegEmptyState(title: l10n.usuariosListadoVacioTitulo, message: ''),
              columns: [
                RisegColumn<IdentidadUsuario>(
                  label: l10n.usuariosColumnaNombre,
                  // El nombre efectivo: el del expediente cuando la
                  // cuenta pertenece a alguien de Personal. El icono
                  // discreto dice que existe ese vínculo sin gastar una
                  // columna entera en ello.
                  cellBuilder: (i) => Row(
                    children: [
                      Flexible(child: Text(i.nombreEfectivo, overflow: TextOverflow.ellipsis)),
                      if (i.estaVinculado) ...[
                        const SizedBox(width: AppSpacing.xxs),
                        Tooltip(
                          message: l10n.usuarioVinculoTooltip,
                          child: Icon(Icons.badge_outlined, size: 15, color: context.colors.textMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                RisegColumn<IdentidadUsuario>(
                  label: l10n.usuariosColumnaUsuario,
                  cellBuilder: (i) => Text(i.usuario.nombreUsuario, overflow: TextOverflow.ellipsis),
                ),
                RisegColumn<IdentidadUsuario>(
                  label: l10n.usuariosColumnaPuesto,
                  cellBuilder: (i) => Text(i.nombrePuestoEfectivo ?? '—', overflow: TextOverflow.ellipsis),
                ),
                RisegColumn<IdentidadUsuario>(
                  label: l10n.usuariosColumnaEstado,
                  width: 130,
                  cellBuilder: (i) => RisegStatusBadge(
                    label: i.cuentaActiva ? l10n.usuarioEstadoActivo : l10n.usuarioEstadoInactivo,
                    tone: i.cuentaActiva ? RisegStatusTone.success : RisegStatusTone.neutral,
                  ),
                ),
                RisegColumn<IdentidadUsuario>(
                  label: l10n.usuariosColumnaUltimoAcceso,
                  cellBuilder: (i) => Text(
                    i.usuario.ultimoAccesoAt == null ? '—' : _formatoFechaHora.format(i.usuario.ultimoAccesoAt!),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                RisegColumn<IdentidadUsuario>(
                  label: l10n.usuariosColumnaTipo,
                  width: 120,
                  cellBuilder: (i) => RisegStatusBadge(
                    label: i.usuario.esMaestro ? l10n.usuarioTipoMaestro : l10n.usuarioTipoNormal,
                    tone: i.usuario.esMaestro ? RisegStatusTone.warning : RisegStatusTone.neutral,
                  ),
                ),
              ],
              rowActionsBuilder: (i) => _MenuAcciones(identidad: i, puestos: state.puestos),
            ),
          ),
          if (sesion != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.usuariosSesionActualLabel(sesion.nombre),
              style: AppTypography.caption.copyWith(color: context.colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Las cinco acciones de una cuenta, en un menú.
///
/// Antes eran cinco `IconButton` en una columna de 260px que competía
/// con Nombre y Puesto por el ancho disponible. Elegir una acción del
/// menú NO abre además la ficha: el menú vive en la celda de acciones,
/// que `RisegTableBase` excluye del `onRowTap`.
class _MenuAcciones extends ConsumerWidget {
  const _MenuAcciones({required this.identidad, required this.puestos});

  final IdentidadUsuario identidad;
  final List<PuestoData> puestos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final activa = identidad.cuentaActiva;

    return PopupMenuButton<String>(
      key: Key('usuarios_menu_${identidad.usuario.id}'),
      icon: const Icon(Icons.more_vert),
      tooltip: l10n.usuariosColumnaAcciones,
      onSelected: (accion) {
        switch (accion) {
          case 'editar':
            mostrarDialogoGestionarUsuario(context, ref, puestos: puestos, identidad: identidad);
          case 'contrasena':
            mostrarDialogoCambiarContrasenaUsuario(context, ref, identidad.usuario);
          case 'permisos':
            mostrarDialogoGestionarPermisosUsuario(context, ref, identidad.usuario);
          case 'estado':
            if (activa) {
              desactivarUsuarioConMotivo(context, ref, identidad);
            } else {
              reactivarUsuario(context, ref, identidad);
            }
          case 'historial':
            mostrarDialogoHistorialUsuario(context, ref, identidad.usuario);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'editar', child: Text(l10n.usuariosAccionEditar)),
        PopupMenuItem(value: 'contrasena', child: Text(l10n.usuariosAccionCambiarContrasena)),
        PopupMenuItem(
          key: Key('usuarios_menu_permisos_${identidad.usuario.id}'),
          value: 'permisos',
          child: Text(l10n.usuariosAccionPermisos),
        ),
        PopupMenuItem(
          value: 'estado',
          child: Text(activa ? l10n.usuariosAccionDesactivar : l10n.usuariosAccionActivar),
        ),
        PopupMenuItem(value: 'historial', child: Text(l10n.usuariosAccionHistorial)),
      ],
    );
  }
}
