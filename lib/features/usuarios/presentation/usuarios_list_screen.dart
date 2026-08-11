import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

import '../domain/usecases/activar_usuario_usecase.dart';
import '../domain/usecases/desactivar_usuario_usecase.dart';
import 'sesion_controller.dart';
import 'usuarios_controller.dart';
import 'widgets/cambiar_contrasena_usuario_dialog.dart';
import 'widgets/gestionar_permisos_usuario_dialog.dart';
import 'widgets/gestionar_usuario_dialog.dart';
import 'widgets/historial_usuario_dialog.dart';

final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Listado + CRUD de Usuarios (Etapa 11A) — primera funcionalidad real
/// de `/configuracion` (hasta ahora un placeholder puro). Desde la
/// Etapa 11B gana "Administrar permisos" (matriz dinámica) — ver
/// `gestionar_permisos_usuario_dialog.dart`.
class UsuariosListScreen extends ConsumerWidget {
  const UsuariosListScreen({super.key});

  Future<void> _desactivar(BuildContext context, WidgetRef ref, UsuarioData usuario) async {
    final l10n = AppLocalizations.of(context)!;
    final motivoCtrl = TextEditingController();

    final confirmado = await RisegDialog.showForm<bool>(
      context: context,
      title: l10n.usuarioDesactivarDialogoTitulo(usuario.nombre),
      confirmLabel: l10n.usuarioDesactivarBotonConfirmar,
      cancelLabel: l10n.compraBotonCancelarFormulario,
      contentBuilder: (_) => RisegTextField(label: l10n.usuarioDesactivarCampoMotivo, controller: motivoCtrl),
      onConfirm: () async {
        final resultado = await ref
            .read(usuariosControllerProvider.notifier)
            .desactivar(usuarioId: usuario.id, motivo: motivoCtrl.text.trim().isEmpty ? null : motivoCtrl.text.trim());
        if (!context.mounted) return false;
        switch (resultado) {
          case DesactivarUsuarioExitoso():
            return true;
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
    if (confirmado ?? false) {
      if (context.mounted) RisegFeedback.showSuccess(context, l10n.usuarioDesactivarExito);
    }
  }

  Future<void> _activar(BuildContext context, WidgetRef ref, UsuarioData usuario) async {
    final l10n = AppLocalizations.of(context)!;
    final resultado = await ref.read(usuariosControllerProvider.notifier).activar(usuario.id);
    if (!context.mounted) return;
    switch (resultado) {
      case ActivarUsuarioExitoso():
        RisegFeedback.showSuccess(context, l10n.usuarioActivarExito);
      case ActivarUsuarioNoExiste():
      case ActivarUsuarioYaActivo():
      case ActivarUsuarioErrorInesperado():
        RisegFeedback.showError(context, l10n.usuarioErrorInesperado);
    }
  }

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
            child: RisegTableBase<UsuarioData>(
              loading: state.cargando,
              rows: state.usuarios,
              emptyState: RisegEmptyState(title: l10n.usuariosListadoVacioTitulo, message: ''),
              columns: [
                RisegColumn<UsuarioData>(label: l10n.usuariosColumnaNombre, cellBuilder: (u) => Text(u.nombre)),
                RisegColumn<UsuarioData>(label: l10n.usuariosColumnaUsuario, cellBuilder: (u) => Text(u.nombreUsuario)),
                RisegColumn<UsuarioData>(
                  label: l10n.usuariosColumnaPuesto,
                  cellBuilder: (u) => Text(state.nombrePuesto(u.puestoId) ?? '—'),
                ),
                RisegColumn<UsuarioData>(
                  label: l10n.usuariosColumnaEstado,
                  width: 130,
                  cellBuilder: (u) => RisegStatusBadge(
                    label: u.cicloVidaRegistro == 'activo' ? l10n.usuarioEstadoActivo : l10n.usuarioEstadoInactivo,
                    tone: u.cicloVidaRegistro == 'activo' ? RisegStatusTone.success : RisegStatusTone.neutral,
                  ),
                ),
                RisegColumn<UsuarioData>(
                  label: l10n.usuariosColumnaUltimoAcceso,
                  cellBuilder: (u) => Text(u.ultimoAccesoAt == null ? '—' : _formatoFechaHora.format(u.ultimoAccesoAt!)),
                ),
                RisegColumn<UsuarioData>(
                  label: l10n.usuariosColumnaTipo,
                  width: 120,
                  cellBuilder: (u) => RisegStatusBadge(
                    label: u.esMaestro ? l10n.usuarioTipoMaestro : l10n.usuarioTipoNormal,
                    tone: u.esMaestro ? RisegStatusTone.warning : RisegStatusTone.neutral,
                  ),
                ),
                RisegColumn<UsuarioData>(
                  label: l10n.usuariosColumnaAcciones,
                  width: 260,
                  cellBuilder: (u) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AccionIcono(
                        tooltip: l10n.usuariosAccionEditar,
                        icon: Icons.edit_outlined,
                        onPressed: () => mostrarDialogoGestionarUsuario(context, ref, puestos: state.puestos, usuario: u),
                      ),
                      _AccionIcono(
                        tooltip: l10n.usuariosAccionCambiarContrasena,
                        icon: Icons.key_outlined,
                        onPressed: () => mostrarDialogoCambiarContrasenaUsuario(context, ref, u),
                      ),
                      _AccionIcono(
                        key: Key('usuarios_boton_permisos_${u.id}'),
                        tooltip: l10n.usuariosAccionPermisos,
                        icon: Icons.shield_outlined,
                        onPressed: () => mostrarDialogoGestionarPermisosUsuario(context, ref, u),
                      ),
                      _AccionIcono(
                        tooltip: u.cicloVidaRegistro == 'activo' ? l10n.usuariosAccionDesactivar : l10n.usuariosAccionActivar,
                        icon: u.cicloVidaRegistro == 'activo' ? Icons.block_outlined : Icons.check_circle_outline,
                        onPressed: () => u.cicloVidaRegistro == 'activo'
                            ? _desactivar(context, ref, u)
                            : _activar(context, ref, u),
                      ),
                      _AccionIcono(
                        tooltip: l10n.usuariosAccionHistorial,
                        icon: Icons.history,
                        onPressed: () => mostrarDialogoHistorialUsuario(context, ref, u),
                      ),
                    ],
                  ),
                ),
              ],
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

/// Botón de acción compacto para la columna de Acciones — 5 acciones
/// no caben con el tamaño mínimo de toque por defecto de `IconButton`
/// (48×48, overflow real encontrado al probar con la columna a 220px).
class _AccionIcono extends StatelessWidget {
  const _AccionIcono({required this.tooltip, required this.icon, required this.onPressed, super.key});

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      visualDensity: VisualDensity.compact,
    );
  }
}
