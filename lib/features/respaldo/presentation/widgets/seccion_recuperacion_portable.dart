import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../../domain/portable/configuracion_recuperacion.dart';
import '../../domain/portable/configurar_recuperacion_usecase.dart';
import '../../domain/portable/contenedor_portable.dart';
import '../../domain/portable/crear_respaldo_portable_usecase.dart';
import '../../domain/portable/resultado_recuperacion.dart';
import '../../domain/portable/verificar_respaldo_portable_usecase.dart';
import '../../domain/usecases/validar_paquete_respaldo_usecase.dart';
import '../../portable_providers.dart';
import '../respaldo_screen.dart' show mensajeDePaqueteInvalido;
import 'portable_dialogs.dart';
import 'recuperar_portable_accion.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy HH:mm');

/// "Recuperación en otro equipo" — la segunda mitad de la pantalla de
/// Respaldos (Etapa 4D).
///
/// Va debajo de los respaldos de este equipo y no en una pestaña aparte a
/// propósito: son dos respuestas a la misma pregunta —"¿qué pasa si esto se
/// pierde?"— y separarlas haría que quien entra a hacer un respaldo normal
/// nunca descubriera que existe la otra.
class SeccionRecuperacionPortable extends ConsumerStatefulWidget {
  const SeccionRecuperacionPortable({super.key});

  @override
  ConsumerState<SeccionRecuperacionPortable> createState() => _SeccionRecuperacionPortableState();
}

class _SeccionRecuperacionPortableState extends ConsumerState<SeccionRecuperacionPortable> {
  bool _procesando = false;

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  /// Envuelve una acción larga: bloquea los botones mientras corre y los
  /// libera pase lo que pase. Sin esto, un fallo a mitad de camino deja la
  /// sección inerte hasta que alguien cambia de pantalla.
  Future<void> _conBloqueo(Future<void> Function() accion) async {
    if (_procesando) return;
    setState(() => _procesando = true);
    try {
      await accion();
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _avisar(String titulo, String mensaje) {
    return RisegDialog.showInformational(
      context: context,
      title: titulo,
      message: mensaje,
      dismissLabel: _l10n.respaldoBotonEntendido,
    );
  }

  Future<void> _error(String mensaje) => _avisar(_l10n.portableErrorTitulo, mensaje);

  // -------------------------------------------------------------------
  // Preparar por primera vez
  // -------------------------------------------------------------------

  Future<void> _preparar() async {
    final frase = await pedirFrasePortable(
      context,
      titulo: _l10n.portableBotonPreparar,
      etiqueta: _l10n.portableFraseEtiqueta,
      ayuda: _l10n.portableFraseAyuda(ConfigurarRecuperacionUseCase.longitudMinimaFrase),
      aviso: _l10n.portableFraseAvisoNoSeGuarda,
    );
    if (frase == null || !mounted) return;

    await _conBloqueo(() async {
      final resultado = await ref.read(configurarRecuperacionAutorizadoProvider)(frase: frase);
      if (!mounted) return;
      await _atenderResultadoRecuperacion(resultado);
    });
  }

  Future<void> _cambiarFrase() async {
    final frases = await pedirCambioDeFrase(context);
    if (frases == null || !mounted) return;

    await _conBloqueo(() async {
      final resultado = await ref.read(cambiarFraseAutorizadoProvider)(
        fraseActual: frases.actual,
        fraseNueva: frases.nueva,
      );
      if (!mounted) return;
      await _atenderResultadoRecuperacion(resultado);
    });
  }

  Future<void> _regenerarClave() async {
    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: _l10n.portableRegenerarTitulo,
      message: _l10n.portableRegenerarAviso,
      confirmLabel: _l10n.portableBotonRegenerarClave,
      cancelLabel: _l10n.respaldoRestaurarCancelarBoton,
    );
    if (confirmado != true || !mounted) return;

    final frase = await pedirFrasePortable(
      context,
      titulo: _l10n.portableRegenerarTitulo,
      etiqueta: _l10n.portableFraseEtiqueta,
    );
    if (frase == null || !mounted) return;

    await _conBloqueo(() async {
      final resultado = await ref.read(regenerarClaveRecuperacionAutorizadoProvider)(frase: frase);
      if (!mounted) return;
      await _atenderResultadoRecuperacion(resultado);
    });
  }

  /// Un solo lugar donde se traduce el resultado de las tres operaciones
  /// de configuración. El `switch` es exhaustivo: añadir un caso al
  /// resultado sellado rompe la compilación aquí, que es donde alguien
  /// tiene que decidir qué se le dice al usuario.
  Future<void> _atenderResultadoRecuperacion(ResultadoRecuperacion resultado) async {
    switch (resultado) {
      case RecuperacionLista(:final datos):
        // La configuración ya está guardada. Lo que falta es que la
        // persona tenga una copia buena de la clave, y eso se comprueba
        // exigiendo que la escriba.
        final verificada = await mostrarYVerificarClaveRecuperacion(context, datos.claveRecuperacionTexto);
        if (!mounted) return;
        if (!verificada) {
          // No se deshace nada: la recuperación quedó configurada y
          // funciona. Lo único incierto es la copia en papel, y para eso
          // existe el botón de generar otra clave.
          await _avisar(_l10n.portableClaveTitulo, _l10n.portableRegenerarAviso);
        }
      case RecuperacionFraseCambiada():
        await _avisar(_l10n.portableFraseCambiadaTitulo, _l10n.portableFraseCambiadaMensaje);
      case RecuperacionFraseIncorrecta():
        await _error(_l10n.portableFraseIncorrecta);
      case RecuperacionFraseDemasiadoCorta(:final longitudMinima):
        await _error(_l10n.portableFraseDemasiadoCorta(longitudMinima));
      case RecuperacionNoConfigurada():
        await _error(_l10n.portableErrorNoConfigurada);
      case RecuperacionNoAutorizada(:final mensaje):
        await _error(mensaje);
      case RecuperacionErrorInesperado(:final mensaje):
        await _error(_l10n.portableErrorGenerico(mensaje));
    }
  }

  // -------------------------------------------------------------------
  // Crear
  // -------------------------------------------------------------------

  Future<void> _crear() async {
    final destino = await FilePicker.platform.saveFile(
      dialogTitle: _l10n.portableCrearDestinoTitulo,
      fileName: 'RISEG-ONE-${DateFormat('yyyy-MM-dd').format(DateTime.now())}${ContenedorPortable.extension}',
      type: FileType.any,
    );
    if (destino == null || !mounted) return;

    final frase = await pedirFrasePortable(
      context,
      titulo: _l10n.portableCrearTitulo,
      etiqueta: _l10n.portableFraseEtiqueta,
      aviso: _l10n.portableCrearMensaje,
    );
    if (frase == null || !mounted) return;

    await _conBloqueo(() async {
      final resultado = await ref.read(crearRespaldoPortableAutorizadoProvider)(destino: destino, frase: frase);
      if (!mounted) return;

      switch (resultado) {
        case PortableCreado():
          await _avisar(_l10n.portableCreadoTitulo, _l10n.portableCreadoMensaje);
        case PortableSinConfiguracion():
          await _error(_l10n.portableErrorSinConfiguracion);
        case PortableCredencialIncorrecta():
          await _error(_l10n.portableErrorCredencial);
        case PortableSinClaveDeCifrado():
          await _error(_l10n.portableErrorSinClaveDeCifrado);
        case PortableRespaldoInternoFallido():
          await _error(_l10n.portableErrorArchivoDanado);
        case PortableNoSuperaAutoverificacion(:final motivo):
          await _error(_l10n.portableErrorNoSuperaAutoverificacion(motivo));
        case PortableDestinoNoDisponible(:final detalle):
          await _error(_l10n.portableErrorDestinoNoDisponible(detalle));
        case PortableErrorInesperado(:final mensaje):
          await _error(_l10n.portableErrorGenerico(mensaje));
      }
    });
  }

  // -------------------------------------------------------------------
  // Revisar y recuperar
  // -------------------------------------------------------------------

  Future<String?> _elegirPaquete() async {
    final seleccion = await FilePicker.platform.pickFiles(
      dialogTitle: _l10n.portableVerificarSeleccionarTitulo,
      type: FileType.any,
    );
    return seleccion?.files.single.path;
  }

  Future<void> _revisar() async {
    final ruta = await _elegirPaquete();
    if (ruta == null || !mounted) return;

    final credencial = await pedirCredencialPortable(context);
    if (credencial == null || !mounted) return;

    await _conBloqueo(() async {
      final resultado = await ref.read(verificarRespaldoPortableAutorizadoProvider)(
        rutaPaquete: ruta,
        frase: credencial.frase,
        claveRecuperacionTexto: credencial.clave,
      );
      if (!mounted) return;
      await _atenderResultadoVerificacion(resultado);
    });
  }

  Future<void> _atenderResultadoVerificacion(ResultadoVerificarPortable resultado) async {
    if (resultado case PortableVerificado(:final informacion)) {
      await _avisar(
        _l10n.portableVerificadoTitulo,
        _l10n.portableVerificadoMensaje(_formatoFecha.format(informacion.creadoEn), informacion.appVersion),
      );
      return;
    }
    await _error(mensajeDeVerificacionPortable(_l10n, resultado));
  }

  /// Delega en la accion compartida: exactamente el mismo recorrido que
  /// ofrece la pantalla de bienvenida de una instalacion nueva. Duplicarlo
  /// habria sido garantizar que las dos se separaran con el tiempo.
  Future<void> _recuperar() => _conBloqueo(() => recuperarDesdePaquetePortable(context, ref));

  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    final configuracion = ref.watch(configuracionRecuperacionProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.portableSeccionTitulo, style: AppTypography.heading3),
        Text(l10n.portableSeccionDescripcion, style: AppTypography.caption.copyWith(color: context.colors.textMuted)),
        const SizedBox(height: AppSpacing.sm),
        RisegCard(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: switch (configuracion) {
              AsyncLoading() => const Center(
                child: Padding(padding: EdgeInsets.all(AppSpacing.lg), child: CircularProgressIndicator()),
              ),
              // Si no se puede leer si está configurada, no se adivina: se
              // ofrece prepararla, que es lo único seguro de ofrecer.
              AsyncError() => _sinPreparar(l10n),
              AsyncValue(value: final valor) => valor == null ? _sinPreparar(l10n) : _preparada(l10n, valor),
            },
          ),
        ),
      ],
    );
  }

  Widget _sinPreparar(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.portableNoConfiguradoTitulo, style: AppTypography.bodyStrong),
        const SizedBox(height: AppSpacing.xs),
        Text(l10n.portableNoConfiguradoMensaje, style: AppTypography.body),
        const SizedBox(height: AppSpacing.md),
        // Recuperar está disponible aun sin haber preparado nada: es
        // exactamente el caso del equipo nuevo, donde el paquete viene de
        // la computadora que se perdió.
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            RisegButton(
              key: const Key('portable_boton_preparar'),
              label: l10n.portableBotonPreparar,
              loading: _procesando,
              onPressed: _procesando ? null : _preparar,
            ),
            RisegButton(
              key: const Key('portable_boton_recuperar_sin_preparar'),
              label: l10n.portableBotonRestaurar,
              variant: RisegButtonVariant.secondary,
              loading: _procesando,
              onPressed: _procesando ? null : _recuperar,
            ),
          ],
        ),
      ],
    );
  }

  Widget _preparada(AppLocalizations l10n, ConfiguracionRecuperacion configuracion) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.portableEstadoListaTitulo, style: AppTypography.bodyStrong),
        const SizedBox(height: AppSpacing.xs),
        Text(l10n.portableEstadoListaMensaje, style: AppTypography.body),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.portableClaveGeneradaEn(_formatoFecha.format(configuracion.claveRecuperacionGeneradaEn)),
          style: AppTypography.caption.copyWith(color: context.colors.textMuted),
        ),
        const SizedBox(height: AppSpacing.md),
        // `Wrap` y no `Row`: son cinco acciones con etiquetas largas en
        // español, y a 700 px de ancho no caben en una línea.
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            RisegButton(
              key: const Key('portable_boton_crear'),
              label: l10n.portableBotonCrear,
              loading: _procesando,
              onPressed: _procesando ? null : _crear,
            ),
            RisegButton(
              key: const Key('portable_boton_revisar'),
              label: l10n.portableBotonVerificar,
              variant: RisegButtonVariant.secondary,
              loading: _procesando,
              onPressed: _procesando ? null : _revisar,
            ),
            RisegButton(
              key: const Key('portable_boton_recuperar'),
              label: l10n.portableBotonRestaurar,
              variant: RisegButtonVariant.secondary,
              loading: _procesando,
              onPressed: _procesando ? null : _recuperar,
            ),
            RisegButton(
              key: const Key('portable_boton_cambiar_frase'),
              label: l10n.portableBotonCambiarFrase,
              variant: RisegButtonVariant.secondary,
              loading: _procesando,
              onPressed: _procesando ? null : _cambiarFrase,
            ),
            RisegButton(
              key: const Key('portable_boton_regenerar_clave'),
              label: l10n.portableBotonRegenerarClave,
              variant: RisegButtonVariant.secondary,
              loading: _procesando,
              onPressed: _procesando ? null : _regenerarClave,
            ),
          ],
        ),
      ],
    );
  }
}

/// Traduce el veredicto del validador interno de la Etapa 4B.
///
/// Se reutiliza para que la pantalla de respaldos normales y esta sección
/// digan lo mismo ante el mismo problema: un adjunto alterado es un adjunto
/// alterado, venga en un `.zip` o dentro de un paquete portable.
String descripcionValidacionInterna(AppLocalizations l10n, ResultadoValidarPaqueteRespaldo resultado) {
  return switch (resultado) {
    // Un paquete válido no debería llegar aquí; si llega, es un problema
    // de este archivo y no del respaldo, así que no se le echa la culpa al
    // archivo del usuario.
    PaqueteRespaldoValido() => l10n.portableErrorArchivoDanado,
    PaqueteRespaldoInvalido(:final motivo) => mensajeDePaqueteInvalido(l10n, motivo),
    PaqueteRespaldoIntegridadFallida() => l10n.respaldoRestaurarErrorIntegridad,
    PaqueteRespaldoVersionMasNueva(:final versionPaquete, :final versionApp) => l10n.respaldoRestaurarErrorVersion(
      versionPaquete,
      versionApp,
    ),
    PaqueteRespaldoErrorInesperado(:final mensaje) => l10n.respaldoErrorInesperadoMensaje(mensaje),
  };
}
