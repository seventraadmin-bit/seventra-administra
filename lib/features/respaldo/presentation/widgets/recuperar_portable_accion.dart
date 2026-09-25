import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../../domain/portable/contenedor_portable.dart';
import '../../domain/portable/coordinador_restauracion_portable.dart';
import '../../domain/portable/verificar_respaldo_portable_usecase.dart';
import '../../domain/usecases/preparar_restauracion_usecase.dart';
import '../../domain/usecases/validar_paquete_respaldo_usecase.dart';
import '../../portable_providers.dart';
import '../respaldo_screen.dart' show mensajeDePaqueteInvalido;
import 'portable_dialogs.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy HH:mm');

/// Recuperar desde un respaldo portable, de principio a fin (Etapa 4D).
///
/// Vive suelto, y no dentro de la pantalla de Respaldos, porque hay **dos**
/// sitios desde donde tiene que poder hacerse y son muy distintos:
///
///  * Configuración → Respaldo, con sesión de Maestro iniciada.
///  * La pantalla de bienvenida de una instalación nueva, donde todavía no
///    existe ningún usuario. Ése es justamente el caso para el que se
///    construyó todo esto: la computadora de la empresa se destruyó y lo
///    único que queda es una memoria USB. Si esta acción viviera dentro de
///    Configuración, haría falta una sesión para llegar a ella, y no hay
///    ninguna que iniciar.
///
/// Quién puede hacerlo no se decide aquí: lo decide
/// `prepararRestauracionPortableAutorizadoProvider` mirando si esta
/// instalación tiene algo que perder. Esta función sólo conduce la
/// conversación.
Future<void> recuperarDesdePaquetePortable(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;

  Future<void> avisar(String titulo, String mensaje) => RisegDialog.showInformational(
    context: context,
    title: titulo,
    message: mensaje,
    dismissLabel: l10n.respaldoBotonEntendido,
  );
  Future<void> error(String mensaje) => avisar(l10n.portableErrorTitulo, mensaje);

  final seleccion = await FilePicker.platform.pickFiles(
    dialogTitle: l10n.portableVerificarSeleccionarTitulo,
    type: FileType.any,
  );
  final ruta = seleccion?.files.single.path;
  if (ruta == null || !context.mounted) return;

  // La cabecera se lee ANTES de pedir cualquier credencial: no hace falta
  // ninguna para leerla, y sirve para que la confirmación diga de qué fecha
  // es el respaldo. "Vas a reemplazar todo" es una advertencia; "vas a
  // reemplazar todo con el respaldo del 12/03/2026" es una decisión que se
  // puede tomar. Si el archivo no se puede ni inspeccionar, se sigue con el
  // mensaje genérico: rechazarlo aquí adelantaría un diagnóstico que hace
  // mejor la verificación completa.
  String? fechaDelPaquete;
  try {
    final informacion = await ref.read(inspeccionarPaquetePortableProvider)(rutaPaquete: ruta);
    fechaDelPaquete = _formatoFecha.format(informacion.creadoEn);
  } catch (_) {
    fechaDelPaquete = null;
  }
  if (!context.mounted) return;

  final confirmado = await RisegDialog.showConfirmation(
    context: context,
    title: l10n.portableRestaurarConfirmarTitulo,
    message:
        fechaDelPaquete == null
            ? l10n.portableRestaurarConfirmarMensaje
            : l10n.portableRestaurarConfirmarMensajeConFecha(fechaDelPaquete),
    confirmLabel: l10n.portableRestaurarConfirmarBoton,
    cancelLabel: l10n.respaldoRestaurarCancelarBoton,
    destructive: true,
  );
  if (confirmado != true || !context.mounted) return;

  final credencial = await pedirCredencialPortable(context);
  if (credencial == null || !context.mounted) return;

  final resultado = await ref.read(prepararRestauracionPortableAutorizadoProvider)(
    rutaPaquete: ruta,
    frase: credencial.frase,
    claveRecuperacionTexto: credencial.clave,
  );
  if (!context.mounted) return;

  switch (resultado) {
    case RestauracionPortablePreparada():
      await avisar(l10n.portableRestaurarPreparadaTitulo, l10n.portableRestaurarPreparadaMensaje);
    case RestauracionPortableNoAutorizada():
      await error(l10n.portableRestaurarNoAutorizada);
    case RestauracionPortableRechazada(:final verificacion):
      await error(mensajeDeVerificacionPortable(l10n, verificacion));
    case RestauracionPortablePreparacionFallida(:final resultado):
      await error(_mensajeDePreparacionFallida(l10n, resultado));
  }
}

/// Qué se le dice al usuario ante cada veredicto de la verificación.
///
/// Se comparte con "Revisar un archivo": el mismo problema tiene que
/// contarse igual, se llegue a él revisando o recuperando.
String mensajeDeVerificacionPortable(AppLocalizations l10n, ResultadoVerificarPortable resultado) {
  return switch (resultado) {
    // Un paquete correcto no es un error que reportar; si llega aquí es
    // porque quien llamó se equivocó de rama.
    PortableVerificado() => l10n.portableVerificadoMensajeCorto,
    PortableEstructuraInvalida(:final motivo) => mensajeDeContenedorInvalido(l10n, motivo),
    PortableCredencialIncorrectaOModificado() => l10n.portableErrorCredencial,
    PortableContenidoDanado() => l10n.portableErrorArchivoDanado,
    PortableRespaldoInternoInvalido(:final resultado) => descripcionValidacionInterna(l10n, resultado),
    PortableVerificarErrorInesperado(:final mensaje) => l10n.portableErrorGenerico(mensaje),
  };
}

/// Los once motivos por los que un contenedor puede estar mal se agrupan en
/// tres mensajes: desde donde está el usuario sólo hay tres situaciones
/// distintas, y sólo una de ellas —la versión— le pide algo que pueda hacer.
/// Decirle "relleno no nulo" no le deja hacer nada que no pudiera hacer con
/// "el archivo está dañado".
///
/// El `switch` sigue siendo exhaustivo, así que un motivo nuevo obliga a
/// decidir en cuál de los tres cae.
String mensajeDeContenedorInvalido(AppLocalizations l10n, MotivoContenedorInvalido motivo) {
  return switch (motivo) {
    MotivoContenedorInvalido.demasiadoCorto => l10n.portableErrorNoEsPortable,
    MotivoContenedorInvalido.magicIncorrecto => l10n.portableErrorNoEsPortable,
    MotivoContenedorInvalido.versionMasNueva => l10n.portableErrorVersionMasNueva,
    MotivoContenedorInvalido.longitudesFueraDeRango => l10n.portableErrorArchivoDanado,
    MotivoContenedorInvalido.rellenoNoNulo => l10n.portableErrorArchivoDanado,
    MotivoContenedorInvalido.cabeceraIlegible => l10n.portableErrorArchivoDanado,
    MotivoContenedorInvalido.envolturasIlegibles => l10n.portableErrorArchivoDanado,
    MotivoContenedorInvalido.sinEnvolturas => l10n.portableErrorArchivoDanado,
    MotivoContenedorInvalido.demasiadasEnvolturas => l10n.portableErrorArchivoDanado,
    MotivoContenedorInvalido.tamanoInconsistente => l10n.portableErrorArchivoDanado,
    MotivoContenedorInvalido.dekWrapInvalido => l10n.portableErrorArchivoDanado,
  };
}

/// El veredicto del validador de la Etapa 4B, con los mensajes que ya
/// existen: un adjunto alterado es un adjunto alterado, venga en un `.zip` o
/// dentro de un paquete portable.
String descripcionValidacionInterna(AppLocalizations l10n, ResultadoValidarPaqueteRespaldo resultado) {
  return switch (resultado) {
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

/// La preparación de archivos es la de la Etapa 4B y ya tiene sus mensajes.
String _mensajeDePreparacionFallida(AppLocalizations l10n, ResultadoPrepararRestauracion resultado) {
  return switch (resultado) {
    RestauracionPreparada() => l10n.portableRestaurarPreparadaMensaje,
    RestauracionPaqueteInvalido(:final motivo) => mensajeDePaqueteInvalido(l10n, motivo),
    RestauracionIntegridadFallida() => l10n.respaldoRestaurarErrorIntegridad,
    RestauracionVersionMasNueva(:final versionPaquete, :final versionApp) => l10n.respaldoRestaurarErrorVersion(
      versionPaquete,
      versionApp,
    ),
    RestauracionRespaldoPreventivoFallido(:final detalle) => l10n.respaldoRestaurarErrorRespaldoPreventivo(detalle),
    RestauracionErrorInesperado(:final mensaje) => l10n.portableErrorGenerico(mensaje),
  };
}
