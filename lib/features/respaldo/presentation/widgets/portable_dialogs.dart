import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../../domain/portable/clave_recuperacion.dart';
import '../../domain/portable/configurar_recuperacion_usecase.dart';

/// Diálogos de la recuperación portable (Etapa 4D).
///
/// Ninguno nombra un algoritmo, un formato ni una llave. El usuario tiene
/// dos cosas: una **frase** que eligió y una **clave de recuperación** que
/// RISEG ONE le dio. Todo lo demás es asunto del programa.

/// Con qué credencial abrir un paquete. Exactamente una de las dos.
class CredencialPortable {
  const CredencialPortable.conFrase(String this.frase) : clave = null;
  const CredencialPortable.conClave(String this.clave) : frase = null;

  final String? frase;
  final String? clave;
}

/// Pide una frase. Devuelve `null` si se cancela.
Future<String?> pedirFrasePortable(
  BuildContext context, {
  required String titulo,
  required String etiqueta,
  String? ayuda,
  String? aviso,
}) {
  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController();

  return RisegDialog.showForm<String>(
    context: context,
    title: titulo,
    confirmLabel: l10n.portableBotonContinuar,
    cancelLabel: l10n.respaldoRestaurarCancelarBoton,
    contentBuilder:
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegTextField(
              key: const Key('portable_campo_frase'),
              label: etiqueta,
              controller: controller,
              obscureText: true,
              autofocus: true,
              helperText: ayuda,
            ),
            if (aviso != null) ...[const SizedBox(height: AppSpacing.md), _Aviso(aviso)],
          ],
        ),
    // Devolver `null` mantiene el diálogo abierto; una frase vacía no es
    // una respuesta, es no haber contestado todavía.
    onConfirm: () async => controller.text.isEmpty ? null : controller.text,
  );
}

/// Pide la frase actual y la nueva de una sola vez: cambiarla exige las
/// dos, y partirlo en dos diálogos sólo añade pasos.
Future<({String actual, String nueva})?> pedirCambioDeFrase(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  final actual = TextEditingController();
  final nueva = TextEditingController();

  return RisegDialog.showForm<({String actual, String nueva})>(
    context: context,
    title: l10n.portableCambiarFraseTitulo,
    confirmLabel: l10n.portableBotonCambiarFrase,
    cancelLabel: l10n.respaldoRestaurarCancelarBoton,
    contentBuilder:
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegTextField(
              key: const Key('portable_campo_frase_actual'),
              label: l10n.portableFraseActualEtiqueta,
              controller: actual,
              obscureText: true,
              autofocus: true,
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              key: const Key('portable_campo_frase_nueva'),
              label: l10n.portableFraseNuevaEtiqueta,
              controller: nueva,
              obscureText: true,
              helperText: l10n.portableFraseAyuda(ConfigurarRecuperacionUseCase.longitudMinimaFrase),
            ),
            const SizedBox(height: AppSpacing.md),
            _Aviso(l10n.portableCambiarFraseAviso),
          ],
        ),
    onConfirm: () async {
      if (actual.text.isEmpty || nueva.text.isEmpty) return null;
      return (actual: actual.text, nueva: nueva.text);
    },
  );
}

/// Pide la credencial con la que abrir un paquete: la frase **o** la clave
/// de recuperación, en un solo diálogo.
///
/// La primera versión preguntaba primero "¿con qué quieres abrirlo?" usando
/// las dos acciones del diálogo compartido, y era un error grave: su acción
/// secundaria cierra devolviendo `null`, igual que la Escape o la cruz. Con
/// eso, elegir "con la clave de recuperación" era indistinguible de
/// cancelar, y la puerta de la clave quedaba inalcanzable desde la
/// interfaz — justo la puerta que existe para el día que la frase se haya
/// olvidado, que es el escenario entero de esta etapa.
///
/// Las dos puertas se ofrecen siempre, sin mirar qué dice el archivo: un
/// paquete manipulado podría declarar que sólo tiene una, y la interfaz
/// estaría escondiendo la buena.
Future<CredencialPortable?> pedirCredencialPortable(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController();
  var conFrase = true;

  return RisegDialog.showForm<CredencialPortable>(
    context: context,
    title: l10n.portableCredencialTitulo,
    confirmLabel: l10n.portableBotonContinuar,
    cancelLabel: l10n.respaldoRestaurarCancelarBoton,
    contentBuilder:
        (_) => StatefulBuilder(
          builder:
              (_, setState) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // `Wrap` y no `Row`: las dos etiquetas son largas y a 500 px no
                  // caben en una línea.
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      RisegButton(
                        key: const Key('portable_elegir_frase'),
                        label: l10n.portableCredencialConFrase,
                        variant: conFrase ? RisegButtonVariant.primary : RisegButtonVariant.secondary,
                        onPressed:
                            conFrase
                                ? null
                                : () => setState(() {
                                  conFrase = true;
                                  controller.clear();
                                }),
                      ),
                      RisegButton(
                        key: const Key('portable_elegir_clave'),
                        label: l10n.portableCredencialConClave,
                        variant: conFrase ? RisegButtonVariant.secondary : RisegButtonVariant.primary,
                        onPressed:
                            !conFrase
                                ? null
                                : () => setState(() {
                                  conFrase = false;
                                  controller.clear();
                                }),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  RisegTextField(
                    // La llave cambia con la puerta elegida para que Flutter
                    // construya un campo nuevo: si se reutilizara el mismo, el texto
                    // ya escrito sobreviviría al cambio y se enviaría una frase como
                    // si fuera una clave.
                    key: conFrase ? const Key('portable_campo_frase') : const Key('portable_campo_clave_recuperacion'),
                    label: conFrase ? l10n.portableFraseEtiqueta : l10n.portableCredencialClaveEtiqueta,
                    controller: controller,
                    // La clave de recuperación se escribe a la vista: viene de un
                    // papel y hay que poder comprobar lo escrito. La frase, no.
                    obscureText: conFrase,
                    autofocus: true,
                  ),
                ],
              ),
        ),
    onConfirm: () async {
      final texto = controller.text;
      if (texto.trim().isEmpty) return null; // el diálogo sigue abierto
      return conFrase ? CredencialPortable.conFrase(texto) : CredencialPortable.conClave(texto);
    },
  );
}

/// Muestra la clave de recuperación y **exige** que se escriba de vuelta.
///
/// La verificación no es una formalidad: es el único momento en que se
/// puede descubrir que alguien copió un `0` donde había una `O`. Devuelve
/// `true` sólo si la persona la escribió correctamente.
Future<bool> mostrarYVerificarClaveRecuperacion(BuildContext context, String claveTexto) async {
  final l10n = AppLocalizations.of(context)!;

  // El aviso serio se lee ANTES de ver la clave, no después.
  await RisegDialog.showInformational(
    context: context,
    title: l10n.portableClaveTitulo,
    // El marco informativo sólo acepta texto, y esta clave necesita un
    // recuadro monoespaciado y un botón de copiar, así que el contenido
    // va en el diálogo de formulario de abajo. Este paso previo existe
    // para que el mensaje serio se lea antes de ver la clave.
    message: l10n.portableClaveMensaje,
    dismissLabel: l10n.respaldoBotonEntendido,
  );
  if (!context.mounted) return false;

  final escrito = TextEditingController();
  var noCoincide = false;

  final confirmada = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.portableClaveConfirmarTitulo,
    confirmLabel: l10n.portableClaveConfirmarBoton,
    cancelLabel: l10n.respaldoRestaurarCancelarBoton,
    contentBuilder:
        (_) => StatefulBuilder(
          builder:
              (_, setState) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RecuadroClave(claveTexto),
                  const SizedBox(height: AppSpacing.md),
                  _Aviso(l10n.portableClaveAvisoUnaVez),
                  const SizedBox(height: AppSpacing.md),
                  Text(l10n.portableClaveConfirmarInstruccion, style: AppTypography.body),
                  const SizedBox(height: AppSpacing.sm),
                  RisegTextField(
                    key: const Key('portable_campo_confirmar_clave'),
                    label: l10n.portableClaveConfirmarEtiqueta,
                    controller: escrito,
                    autofocus: true,
                    errorText: noCoincide ? l10n.portableClaveConfirmarNoCoincide : null,
                    onChanged: (_) {
                      if (noCoincide) setState(() => noCoincide = false);
                    },
                  ),
                ],
              ),
        ),
    onConfirm: () async {
      // Se comparan los BYTES, no el texto: así una clave escrita sin
      // guiones, en minúsculas o con un `1` donde se imprimió una `I`
      // cuenta como correcta, igual que contaría el día de la
      // recuperación. Lo contrario sería rechazar una copia buena.
      final a = ClaveRecuperacion.interpretar(escrito.text);
      final b = ClaveRecuperacion.interpretar(claveTexto);
      if (a == null || b == null || !_mismosBytes(a, b)) {
        noCoincide = true;
        return null; // el diálogo sigue abierto, con el error visible
      }
      return true;
    },
  );

  return confirmada ?? false;
}

bool _mismosBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// La clave, grande y seleccionable, con un botón de copiar.
///
/// Se puede seleccionar con el ratón a propósito: si el portapapeles
/// falla —y en Windows falla cuando otra aplicación lo tiene tomado— tiene
/// que quedar una forma de sacarla de aquí.
class _RecuadroClave extends StatelessWidget {
  const _RecuadroClave(this.clave);
  final String clave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: AppRadius.mdRadius,
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            clave,
            key: const Key('portable_texto_clave_recuperacion'),
            style: AppTypography.body.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: RisegButton(
              label: l10n.portableClaveBotonCopiar,
              variant: RisegButtonVariant.secondary,
              onPressed: () async {
                // Copiar es una comodidad, nunca un requisito: si el
                // portapapeles no responde se dice y se sigue, porque la
                // clave ya está a la vista y se puede seleccionar.
                try {
                  await Clipboard.setData(ClipboardData(text: clave));
                  if (context.mounted) RisegFeedback.showSuccess(context, l10n.portableClaveCopiada);
                } catch (_) {
                  if (context.mounted) RisegFeedback.showError(context, l10n.portableClaveNoSePudoCopiar);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Aviso en tono de advertencia, con el mismo peso visual que el de
/// credenciales de la pantalla de respaldos.
class _Aviso extends StatelessWidget {
  const _Aviso(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.warningBg,
        borderRadius: AppRadius.smRadius,
        border: Border.all(color: colors.warning),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: colors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(texto, style: AppTypography.caption.copyWith(color: colors.textPrimary))),
        ],
      ),
    );
  }
}
