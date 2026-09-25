import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../domain/manifest_respaldo.dart';
import '../domain/usecases/crear_respaldo_usecase.dart';
import '../domain/usecases/eliminar_respaldo_usecase.dart';
import '../domain/usecases/preparar_restauracion_usecase.dart';
import '../domain/usecases/validar_paquete_respaldo_usecase.dart';
import '../respaldo_providers.dart';
import 'respaldo_controller.dart';
import 'respaldo_state.dart';
import 'widgets/confirmar_restauracion_dialog.dart';
import 'widgets/seccion_recuperacion_portable.dart';

final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Traduce el motivo por el que un paquete no sirve a una frase que una
/// persona entiende.
///
/// El dominio devuelve un valor cerrado, nunca una cadena técnica: así
/// la pantalla nunca muestra una ruta del sistema ni el texto de una
/// excepción, y el `switch` obliga a decidir qué decir en cada caso
/// nuevo.
String mensajeDePaqueteInvalido(AppLocalizations l10n, MotivoPaqueteInvalido motivo) {
  return switch (motivo) {
    MotivoPaqueteInvalido.noEsUnZip => l10n.respaldoErrorNoEsUnZip,
    MotivoPaqueteInvalido.rutaInsegura => l10n.respaldoErrorRutaInsegura,
    MotivoPaqueteInvalido.faltaManifiesto => l10n.respaldoErrorFaltaManifiesto,
    MotivoPaqueteInvalido.manifiestoDanado => l10n.respaldoErrorManifiestoDanado,
    MotivoPaqueteInvalido.formatoNoSoportado => l10n.respaldoErrorFormatoNoSoportado,
    MotivoPaqueteInvalido.faltaBaseDatos => l10n.respaldoErrorFaltaBaseDatos,
    MotivoPaqueteInvalido.baseDatosAlterada => l10n.respaldoErrorBaseDatosAlterada,
    MotivoPaqueteInvalido.baseDatosIlegible => l10n.respaldoErrorBaseDatosIlegible,
    MotivoPaqueteInvalido.integridadBaseDatos => l10n.respaldoRestaurarErrorIntegridad,
    MotivoPaqueteInvalido.referenciasRotas => l10n.respaldoErrorReferenciasRotas,
    MotivoPaqueteInvalido.adjuntoFaltante => l10n.respaldoErrorAdjuntoFaltante,
    MotivoPaqueteInvalido.adjuntoAlterado => l10n.respaldoErrorAdjuntoAlterado,
    MotivoPaqueteInvalido.adjuntoNoDeclarado => l10n.respaldoErrorAdjuntoNoDeclarado,
  };
}

/// Pantalla de Respaldo y restauración — exclusiva del Usuario Maestro,
/// dentro de Configuración. Empaqueta `riseg_one.sqlite` + adjuntos
/// (irremplazables) en un `.zip` con la huella SHA-256 de cada archivo;
/// excluye los documentos regenerables y la clave de cifrado de
/// credenciales, que vive en el Almacén de Credenciales de Windows.
/// Restaurar reemplaza todos los datos actuales: siempre crea antes un
/// respaldo preventivo automático y exige reiniciar para completarse.
class RespaldoScreen extends ConsumerWidget {
  const RespaldoScreen({super.key});

  String _formatoTamano(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _avisar(BuildContext context, AppLocalizations l10n, String titulo, String mensaje) {
    return RisegDialog.showInformational(
      context: context,
      title: titulo,
      message: mensaje,
      dismissLabel: l10n.respaldoBotonEntendido,
    );
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
        await _avisar(context, l10n, l10n.respaldoCrearExitoTitulo, l10n.respaldoCrearExitoMensaje);
      case RespaldoIntegridadFallida():
        await _avisar(context, l10n, l10n.respaldoErrorTitulo, l10n.respaldoCrearErrorIntegridad);
      case RespaldoNoSuperaValidacion():
        await _avisar(context, l10n, l10n.respaldoErrorTitulo, l10n.respaldoCrearErrorNoValida);
      case RespaldoDestinoNoDisponible():
        await _avisar(context, l10n, l10n.respaldoErrorTitulo, l10n.respaldoCrearErrorDestino);
      case RespaldoErrorInesperado():
        await _avisar(context, l10n, l10n.respaldoErrorTitulo, l10n.respaldoErrorGenerico);
    }
  }

  Future<void> _restaurarDesdeArchivo(BuildContext context, WidgetRef ref, AppLocalizations l10n) async {
    final elegidos = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
    final rutaZip = elegidos?.files.single.path;
    if (rutaZip == null || !context.mounted) return;
    await _restaurar(context, ref, l10n, rutaZip);
  }

  Future<void> _restaurar(BuildContext context, WidgetRef ref, AppLocalizations l10n, String rutaZip) async {
    ResultadoPrepararRestauracion? resultado;
    final confirmado = await mostrarConfirmacionRestauracion(
      context: context,
      l10n: l10n,
      onConfirm: () async {
        resultado = await ref.read(respaldoControllerProvider.notifier).restaurar(rutaZip);
      },
    );
    if (!context.mounted || confirmado != true || resultado == null) return;

    switch (resultado!) {
      case RestauracionPreparada():
        await RisegDialog.showConfirmation(
          context: context,
          title: l10n.respaldoRestaurarListaTitulo,
          message: l10n.respaldoRestaurarListaMensaje,
          confirmLabel: l10n.respaldoRestaurarCerrarAhoraBoton,
          cancelLabel: l10n.respaldoRestaurarMasTardeBoton,
          onConfirm: () async => exit(0),
        );
      case RestauracionPaqueteInvalido(:final motivo):
        await _avisar(context, l10n, l10n.respaldoErrorTitulo, mensajeDePaqueteInvalido(l10n, motivo));
      case RestauracionIntegridadFallida():
        await _avisar(context, l10n, l10n.respaldoErrorTitulo, l10n.respaldoRestaurarErrorIntegridad);
      case RestauracionVersionMasNueva(:final versionPaquete, :final versionApp):
        await _avisar(
          context,
          l10n,
          l10n.respaldoErrorTitulo,
          l10n.respaldoRestaurarErrorVersion(versionPaquete, versionApp),
        );
      case RestauracionRespaldoPreventivoFallido():
        await _avisar(context, l10n, l10n.respaldoErrorTitulo, l10n.respaldoRestaurarErrorRespaldoPreventivo(''));
      case RestauracionErrorInesperado():
        await _avisar(context, l10n, l10n.respaldoErrorTitulo, l10n.respaldoErrorGenerico);
    }
  }

  Future<void> _verificar(BuildContext context, WidgetRef ref, AppLocalizations l10n, ArchivoRespaldo archivo) async {
    final resultado = await ref.read(respaldoControllerProvider.notifier).verificar(archivo);
    if (!context.mounted) return;

    switch (resultado) {
      case PaqueteRespaldoValido(:final verificacionCompleta):
        await _avisar(
          context,
          l10n,
          l10n.respaldoVerificarTitulo,
          verificacionCompleta ? l10n.respaldoVerificarExitoCompleta : l10n.respaldoVerificarExitoLimitada,
        );
      case PaqueteRespaldoInvalido(:final motivo):
        await _avisar(context, l10n, l10n.respaldoVerificarTitulo, mensajeDePaqueteInvalido(l10n, motivo));
      case PaqueteRespaldoIntegridadFallida():
        await _avisar(context, l10n, l10n.respaldoVerificarTitulo, l10n.respaldoRestaurarErrorIntegridad);
      case PaqueteRespaldoVersionMasNueva(:final versionPaquete, :final versionApp):
        await _avisar(
          context,
          l10n,
          l10n.respaldoVerificarTitulo,
          l10n.respaldoRestaurarErrorVersion(versionPaquete, versionApp),
        );
      case PaqueteRespaldoErrorInesperado():
        await _avisar(context, l10n, l10n.respaldoErrorTitulo, l10n.respaldoErrorGenerico);
    }
  }

  Future<void> _eliminar(BuildContext context, WidgetRef ref, AppLocalizations l10n, ArchivoRespaldo archivo) async {
    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: l10n.respaldoEliminarConfirmarTitulo,
      message: l10n.respaldoEliminarConfirmarMensaje(archivo.nombre, _formatoFechaHora.format(archivo.modificado)),
      confirmLabel: l10n.respaldoEliminarBoton,
      cancelLabel: l10n.respaldoRestaurarCancelarBoton,
      destructive: true,
    );
    if (confirmado != true || !context.mounted) return;

    final resultado = await ref.read(respaldoControllerProvider.notifier).eliminar(archivo);
    if (!context.mounted) return;
    switch (resultado) {
      case RespaldoEliminado():
        RisegFeedback.showSuccess(context, l10n.respaldoEliminarExito);
      case RespaldoProtegidoPorRestauracionPendiente():
        await _avisar(context, l10n, l10n.respaldoErrorTitulo, l10n.respaldoEliminarBloqueadoPreventivo);
      case RespaldoNoEncontrado():
      case EliminarRespaldoErrorInesperado():
        await _avisar(context, l10n, l10n.respaldoErrorTitulo, l10n.respaldoErrorGenerico);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(respaldoControllerProvider);

    // Una sola superficie que se desplaza. La cabecera explicativa crece
    // al estrecharse la ventana —el aviso de credenciales ocupa varias
    // líneas a 500 px— y con la lista atrapada en un `Expanded` eso
    // terminaba desbordando por abajo en lugar de poder deslizarse.
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
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
                const _AvisoCredenciales(),
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
                      label: l10n.respaldoBotonRestaurarDesdeArchivo,
                      variant: RisegButtonVariant.secondary,
                      loading: state.procesando,
                      onPressed: state.procesando ? null : () => _restaurarDesdeArchivo(context, ref, l10n),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // "Respaldos en este equipo", nunca "Historial": esta lista es
        // lo que hay en una carpeta, y un respaldo guardado en otra
        // unidad no aparece aquí aunque exista.
        Text(l10n.respaldoListaLocalTitulo, style: AppTypography.heading3),
        Text(l10n.respaldoListaLocalAyuda, style: AppTypography.caption.copyWith(color: context.colors.textMuted)),
        const SizedBox(height: AppSpacing.xs),
        ..._listaRespaldos(context, ref, l10n, state),
        // La segunda mitad: cómo volver a levantar todo esto en OTRA
        // computadora. Va en la misma pantalla y no en una pestaña porque
        // quien entra aquí ya está pensando en lo que pasaría si esta
        // máquina se perdiera; en una pestaña aparte no lo encontraría
        // nunca.
        const SizedBox(height: AppSpacing.xl),
        Divider(color: context.colors.borderSubtle),
        const SizedBox(height: AppSpacing.lg),
        const SeccionRecuperacionPortable(),
      ],
    );
  }

  /// Devuelve las filas ya desplegadas, no otro scrollable: la pantalla
  /// entera es una sola lista, y anidar dos desplazamientos verticales
  /// obliga al usuario a adivinar cuál está moviendo.
  List<Widget> _listaRespaldos(BuildContext context, WidgetRef ref, AppLocalizations l10n, RespaldoState state) {
    if (state.cargando) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (state.respaldos.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
          child: RisegEmptyState(title: l10n.respaldoListaVaciaTitulo, message: l10n.respaldoListaVaciaMensaje),
        ),
      ];
    }
    return [
      for (final (indice, archivo) in state.respaldos.indexed) ...[
        if (indice > 0) const SizedBox(height: AppSpacing.xs),
        _FilaRespaldo(
          archivo: archivo,
          tamano: _formatoTamano(archivo.tamanoBytes),
          onRestaurar: () => _restaurar(context, ref, l10n, archivo.ruta),
          onVerificar: () => _verificar(context, ref, l10n, archivo),
          onAbrirUbicacion: () => ref.read(respaldoControllerProvider.notifier).abrirUbicacion(archivo),
          onEliminar: () => _eliminar(context, ref, l10n, archivo),
        ),
      ],
    ];
  }
}

/// La advertencia que la auditoría encontró incompleta.
///
/// Antes nombraba sólo a Telefonía, y quien la leía concluía —con toda
/// razón— que su Bóveda de Accesos viajaba en el respaldo. No viaja: el
/// texto cifrado sí, la llave no. Ahora se nombran los tres módulos y
/// se explica la consecuencia, que es lo único que el usuario necesita
/// para decidir.
class _AvisoCredenciales extends StatelessWidget {
  const _AvisoCredenciales();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    return RisegCard(
      key: const Key('respaldo_aviso_credenciales'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.key_off_outlined, size: 20, color: colors.warning),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.respaldoAvisoCredencialesTitulo, style: AppTypography.bodyStrong),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    l10n.respaldoAvisoCredencialesMensaje,
                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaRespaldo extends StatelessWidget {
  const _FilaRespaldo({
    required this.archivo,
    required this.tamano,
    required this.onRestaurar,
    required this.onVerificar,
    required this.onAbrirUbicacion,
    required this.onEliminar,
  });

  final ArchivoRespaldo archivo;
  final String tamano;
  final VoidCallback onRestaurar;
  final VoidCallback onVerificar;
  final VoidCallback onAbrirUbicacion;
  final VoidCallback onEliminar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    final detalles = <String>[
      _formatoFechaHora.format(archivo.modificado),
      tamano,
      if (archivo.tipo != null)
        archivo.tipo == TipoRespaldo.preventivo ? l10n.respaldoTipoPreventivo : l10n.respaldoTipoManual,
      if (archivo.esFormatoAnterior) l10n.respaldoFormatoAnterior,
    ];

    return RisegCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(archivo.nombre, overflow: TextOverflow.ellipsis, style: AppTypography.bodyStrong),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    detalles.join(' · '),
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _InsigniaIntegridad(estado: archivo.integridad),
            PopupMenuButton<String>(
              key: Key('respaldo_menu_${archivo.nombre}'),
              icon: const Icon(Icons.more_vert),
              tooltip: l10n.usuariosColumnaAcciones,
              onSelected: (accion) {
                switch (accion) {
                  case 'restaurar':
                    onRestaurar();
                  case 'verificar':
                    onVerificar();
                  case 'ubicacion':
                    onAbrirUbicacion();
                  case 'eliminar':
                    onEliminar();
                }
              },
              itemBuilder:
                  (_) => [
                    PopupMenuItem(value: 'restaurar', child: Text(l10n.respaldoAccionRestaurar)),
                    PopupMenuItem(value: 'verificar', child: Text(l10n.respaldoAccionVerificar)),
                    PopupMenuItem(value: 'ubicacion', child: Text(l10n.respaldoAccionAbrirUbicacion)),
                    PopupMenuItem(value: 'eliminar', child: Text(l10n.respaldoAccionEliminar)),
                  ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InsigniaIntegridad extends StatelessWidget {
  const _InsigniaIntegridad({required this.estado});

  final EstadoIntegridad estado;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (etiqueta, tono) = switch (estado) {
      EstadoIntegridad.verificado => (l10n.respaldoIntegridadVerificado, RisegStatusTone.success),
      EstadoIntegridad.limitada => (l10n.respaldoIntegridadLimitada, RisegStatusTone.warning),
      EstadoIntegridad.invalido => (l10n.respaldoIntegridadInvalido, RisegStatusTone.error),
      EstadoIntegridad.sinVerificar => (l10n.respaldoIntegridadSinVerificar, RisegStatusTone.neutral),
    };
    return RisegStatusBadge(label: etiqueta, tone: tono);
  }
}
