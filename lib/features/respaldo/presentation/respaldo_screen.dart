import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../domain/usecases/crear_respaldo_usecase.dart';
import '../domain/usecases/preparar_restauracion_usecase.dart';
import '../respaldo_providers.dart';
import 'respaldo_controller.dart';
import 'respaldo_state.dart';
import 'widgets/confirmar_restauracion_dialog.dart';

final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Pantalla de Respaldo y restauración (Etapa 14C) — exclusiva del
/// Usuario Maestro, dentro de Configuración. Empaqueta `riseg_one.sqlite`
/// + adjuntos (irremplazables) en un `.zip`; excluye deliberadamente
/// reportes exportados (regenerables) y la clave de cifrado de
/// Telefonía (vive en el Almacén de Credenciales de Windows, nunca en
/// un archivo — ver `credential_cipher.dart`). Restaurar reemplaza
/// todos los datos actuales: siempre crea antes un respaldo preventivo
/// automático y exige reiniciar la aplicación para completarse (no hay
/// mecanismo de recarga en caliente de la conexión de base de datos).
class RespaldoScreen extends ConsumerWidget {
  const RespaldoScreen({super.key});

  String _formatoTamano(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _crearRespaldo(BuildContext context, WidgetRef ref, AppLocalizations l10n) async {
    final sugerido = 'riseg_one_respaldo_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.zip';
    var destino = await FilePicker.platform.saveFile(
      dialogTitle: l10n.respaldoCrearSeleccionarDestinoTitulo,
      fileName: sugerido,
      initialDirectory: ref.read(backupsDirProvider),
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (destino == null) return;
    if (!destino.toLowerCase().endsWith('.zip')) destino = '$destino.zip';

    final resultado = await ref.read(respaldoControllerProvider.notifier).crearRespaldo(destino);
    if (!context.mounted) return;

    switch (resultado) {
      case RespaldoCreado():
        await RisegDialog.showInformational(
          context: context,
          title: l10n.respaldoCrearExitoTitulo,
          message: l10n.respaldoCrearExitoMensaje,
          dismissLabel: l10n.respaldoBotonEntendido,
        );
      case RespaldoIntegridadFallida():
        await RisegDialog.showInformational(
          context: context,
          title: l10n.respaldoErrorTitulo,
          message: l10n.respaldoCrearErrorIntegridad,
          dismissLabel: l10n.respaldoBotonEntendido,
        );
      case RespaldoErrorInesperado(:final mensaje):
        await RisegDialog.showInformational(
          context: context,
          title: l10n.respaldoErrorTitulo,
          message: l10n.respaldoErrorInesperadoMensaje(mensaje),
          dismissLabel: l10n.respaldoBotonEntendido,
        );
    }
  }

  Future<void> _restaurar(BuildContext context, WidgetRef ref, AppLocalizations l10n) async {
    final elegidos = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
    final rutaZip = elegidos?.files.single.path;
    if (rutaZip == null) return;
    if (!context.mounted) return;

    ResultadoPrepararRestauracion? resultado;
    final confirmado = await mostrarConfirmacionRestauracion(
      context: context,
      l10n: l10n,
      onConfirm: () async {
        resultado = await ref.read(respaldoControllerProvider.notifier).restaurar(rutaZip);
      },
    );
    if (!context.mounted || confirmado != true || resultado == null) return;

    await _manejarResultadoRestauracion(context, l10n, resultado!);
  }

  Future<void> _manejarResultadoRestauracion(
    BuildContext context,
    AppLocalizations l10n,
    ResultadoPrepararRestauracion resultado,
  ) {
    switch (resultado) {
      case RestauracionPreparada():
        return RisegDialog.showConfirmation(
          context: context,
          title: l10n.respaldoRestaurarListaTitulo,
          message: l10n.respaldoRestaurarListaMensaje,
          confirmLabel: l10n.respaldoRestaurarCerrarAhoraBoton,
          cancelLabel: l10n.respaldoRestaurarMasTardeBoton,
          onConfirm: () async => exit(0),
        );
      case RestauracionPaqueteInvalido(:final detalle):
        return RisegDialog.showInformational(
          context: context,
          title: l10n.respaldoErrorTitulo,
          message: detalle,
          dismissLabel: l10n.respaldoBotonEntendido,
        );
      case RestauracionIntegridadFallida():
        return RisegDialog.showInformational(
          context: context,
          title: l10n.respaldoErrorTitulo,
          message: l10n.respaldoRestaurarErrorIntegridad,
          dismissLabel: l10n.respaldoBotonEntendido,
        );
      case RestauracionVersionMasNueva(:final versionPaquete, :final versionApp):
        return RisegDialog.showInformational(
          context: context,
          title: l10n.respaldoErrorTitulo,
          message: l10n.respaldoRestaurarErrorVersion(versionPaquete, versionApp),
          dismissLabel: l10n.respaldoBotonEntendido,
        );
      case RestauracionRespaldoPreventivoFallido(:final detalle):
        return RisegDialog.showInformational(
          context: context,
          title: l10n.respaldoErrorTitulo,
          message: l10n.respaldoRestaurarErrorRespaldoPreventivo(detalle),
          dismissLabel: l10n.respaldoBotonEntendido,
        );
      case RestauracionErrorInesperado(:final mensaje):
        return RisegDialog.showInformational(
          context: context,
          title: l10n.respaldoErrorTitulo,
          message: l10n.respaldoErrorInesperadoMensaje(mensaje),
          dismissLabel: l10n.respaldoBotonEntendido,
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(respaldoControllerProvider);
    final notifier = ref.read(respaldoControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(title: l10n.respaldoTitulo),
          const SizedBox(height: AppSpacing.md),
          RisegCard(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.respaldoDescripcion, style: AppTypography.body),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      RisegButton(
                        key: const Key('respaldo_boton_crear'),
                        label: l10n.respaldoBotonCrear,
                        loading: state.procesando,
                        onPressed: state.procesando ? null : () => _crearRespaldo(context, ref, l10n),
                      ),
                      RisegButton(
                        key: const Key('respaldo_boton_restaurar'),
                        label: l10n.respaldoBotonRestaurar,
                        variant: RisegButtonVariant.secondary,
                        loading: state.procesando,
                        onPressed: state.procesando ? null : () => _restaurar(context, ref, l10n),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(child: _listaRespaldos(l10n, state, notifier)),
        ],
      ),
    );
  }

  Widget _listaRespaldos(AppLocalizations l10n, RespaldoState state, RespaldoController notifier) {
    if (state.cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.respaldos.isEmpty) {
      return RisegEmptyState(title: l10n.respaldoListaVaciaTitulo, message: l10n.respaldoListaVaciaMensaje);
    }
    return ListView.separated(
      itemCount: state.respaldos.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, index) {
        final archivo = state.respaldos[index];
        return RisegCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(child: Text(archivo.nombre, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: AppSpacing.md),
                Text(_formatoFechaHora.format(archivo.modificado), style: AppTypography.caption),
                const SizedBox(width: AppSpacing.md),
                Text(_formatoTamano(archivo.tamanoBytes), style: AppTypography.caption),
              ],
            ),
          ),
        );
      },
    );
  }
}
