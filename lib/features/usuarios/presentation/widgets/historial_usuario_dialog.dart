import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

import '../usuarios_controller.dart';

final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

String _tipoEventoLabel(AppLocalizations l10n, String tipoEvento) {
  return switch (tipoEvento) {
    'creado' => l10n.usuarioEventoCreado,
    'datosCorregidos' => l10n.usuarioEventoDatosCorregidos,
    'contrasenaCambiada' => l10n.usuarioEventoContrasenaCambiada,
    'activado' => l10n.usuarioEventoActivado,
    'desactivado' => l10n.usuarioEventoDesactivado,
    'permisosModificados' => l10n.usuarioEventoPermisosModificados,
    _ => tipoEvento,
  };
}

/// Historial administrativo de un Usuario (Etapa 11A) — solo lectura,
/// mismo molde que `mostrarDialogoHistorialDocumentoVehiculo`. El actor
/// se resuelve por nombre a partir de la lista de Usuarios ya cargada
/// en `UsuariosState` (bulk-fetch-then-loop, sin N+1) — un evento sin
/// `actorUsuarioId` se muestra como "Configuración inicial" (el único
/// caso posible: el bootstrap del primer Maestro).
Future<void> mostrarDialogoHistorialUsuario(BuildContext context, WidgetRef ref, UsuarioData usuario) async {
  final l10n = AppLocalizations.of(context)!;
  final eventos = await ref.read(usuariosControllerProvider.notifier).obtenerEventos(usuario.id);
  final usuariosPorId = {for (final u in ref.read(usuariosControllerProvider).usuarios) u.id: u.nombre};
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.usuarioHistorialDialogoTitulo(usuario.nombre)),
      content: SizedBox(
        width: 460,
        child: eventos.isEmpty
            ? Text(l10n.usuarioHistorialVacio)
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final evento in eventos)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _tipoEventoLabel(l10n, evento.tipoEvento),
                                    style: AppTypography.bodyStrong,
                                  ),
                                ),
                                Text(_formatoFechaHora.format(evento.fechaHora), style: AppTypography.caption),
                              ],
                            ),
                            Text(
                              l10n.usuarioHistorialPor(
                                evento.actorUsuarioId == null
                                    ? l10n.usuarioHistorialConfiguracionInicial
                                    : usuariosPorId[evento.actorUsuarioId] ?? l10n.usuarioHistorialConfiguracionInicial,
                              ),
                              style: AppTypography.caption.copyWith(color: context.colors.textMuted),
                            ),
                            if (evento.observacion != null)
                              Text(evento.observacion!, style: AppTypography.body),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(l10n.vehiculoDocumentoHistorialBotonCerrar)),
      ],
    ),
  );
}
