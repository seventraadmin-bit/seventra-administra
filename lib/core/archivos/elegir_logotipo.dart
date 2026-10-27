import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../design_system/design_system_web.dart';
import 'firma_de_logotipo.dart';

/// El archivo que la persona eligió y **confirmó** como logotipo.
class LogotipoElegido {
  const LogotipoElegido({required this.nombre, required this.bytes});

  final String nombre;
  final Uint8List bytes;
}

/// Elegir un logotipo, **verlo antes de aplicarlo**, y confirmar.
///
/// ## Qué significan [donde] y [queReemplaza], y por qué son parámetros
///
/// Porque **el mismo recorrido sirve para dos dueños distintos** —la empresa y un
/// cliente— y las dos frases que explican la vista previa no pueden ser las mismas. El
/// texto decía «Así se verá en la ficha de la empresa y en sus documentos» y «Si la
/// empresa ya tenía logotipo, éste lo reemplaza»: en el alta de un cliente, las dos
/// habrían sido falsas.
///
/// - [donde] completa «Así se verá en …»: «la ficha de la empresa y en sus documentos»,
///   «la ficha del cliente y en su listado».
/// - [queReemplaza] es la frase entera del aviso de reemplazo, **o nula cuando no hay
///   nada que reemplazar** — en un alta no existe todavía un logotipo anterior, y
///   anunciar un reemplazo que no ocurre enseña a no leer los avisos.
///
/// ## Por qué hay vista previa y no se sube al elegir
///
/// Porque elegir el archivo equivocado es el error frecuente, y la vista previa es **el
/// único momento** en que alguien puede darse cuenta. Subir en cuanto se elige
/// convertiría una equivocación de un clic en una subida, un reemplazo del logotipo
/// vigente y una segunda subida para arreglarlo.
///
/// Es además lo que hace el escritorio, y el recorrido se copia: vista previa,
/// confirmar, y «Cancelar» que no toca nada.
///
/// ## La trampa de la web que el código del escritorio no cubre
///
/// En el navegador **no hay sistema de archivos**: `FilePicker` devuelve `bytes` y
/// `path` **siempre nulo**, y `bytes` sólo llega si se pide `withData: true`. El
/// escritorio lee `archivo.path`, así que su código **no se reutiliza** — y el modo en
/// que falla es silencioso: `path` nulo y nada que subir.
///
/// ## Y la validación de aquí es un AVISO, no la garantía
///
/// Se revisa la **firma** del archivo —no su extensión— porque «un archivo puede
/// llamarse `.png` sin serlo». Pero quien decide es el servidor, que lee los mismos
/// bytes mágicos: si acepta algo que el servidor rechaza, se muestra el motivo del
/// servidor.
Future<LogotipoElegido?> elegirLogotipo(
  BuildContext context, {
  required String donde,
  String? queReemplaza,
}) async {
  final seleccion = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    // EL FILTRO ES COMODIDAD, no garantía: el diálogo del sistema se puede sortear
    // escribiendo el nombre a mano. La garantía es la firma, más abajo.
    allowedExtensions: const ['png', 'jpg', 'jpeg'],
    // ⚠️ SIN ESTO, EN WEB NO LLEGAN LOS BYTES Y NO HAY NADA QUE SUBIR.
    withData: true,
  );

  final archivo = seleccion?.files.singleOrNull;

  // CANCELAR EL SELECTOR NO ES UN ERROR y no se dice nada.
  if (archivo == null || !context.mounted) return null;

  final bytes = archivo.bytes;

  if (bytes == null) {
    // NO DEBERÍA PASAR CON `withData: true`, y si pasa se dice en vez de quedarse
    // callado: un selector que devuelve un archivo sin contenido es un fallo del
    // entorno, no algo que la persona pueda arreglar.
    // NO ES UN RECHAZO DEL SERVIDOR: el archivo no llegó a salir de aquí. Antes usaba
    // `mostrarRechazoDelServidor`, que desde D-46 recibe el fallo del servidor y traduce
    // su familia de autorización; para un aviso local el camino es el directo.
    RisegFeedback.showError(
      context,
      'No se pudo leer el archivo que elegiste. Vuelve a intentarlo.',
    );

    return null;
  }

  // EL AVISO TEMPRANO: si no sirve, se dice aquí y no después de subir 5 MB.
  if (FirmaDeLogotipo.porQueNoSirve(bytes) case final motivo?) {
    // Tampoco es del servidor: lo decide la firma del archivo, aquí, antes de subirlo.
    RisegFeedback.showError(context, motivo);

    return null;
  }

  final confirmado = await RisegDialog.showForm<bool>(
    context: context,
    title: 'Vista previa del logotipo',
    confirmLabel: 'Usar este logotipo',
    cancelLabel: 'Cancelar',
    contentBuilder: (contexto) => _VistaPrevia(
      nombre: archivo.name,
      bytes: bytes,
      donde: donde,
      queReemplaza: queReemplaza,
    ),
    onConfirm: () async => true,
  );

  return (confirmado ?? false)
      ? LogotipoElegido(nombre: archivo.name, bytes: bytes)
      : null;
}

class _VistaPrevia extends StatelessWidget {
  const _VistaPrevia({
    required this.nombre,
    required this.bytes,
    required this.donde,
    required this.queReemplaza,
  });

  final String nombre;
  final Uint8List bytes;
  final String donde;
  final String? queReemplaza;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      width: 420,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Así se verá en $donde.',
            style: AppTypography.body.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.md),

          // SOBRE FONDO CLARO Y CON BORDE: un PNG con transparencia sobre el fondo de
          // la pantalla puede verse bien aquí y perderse en un documento blanco. El
          // marco dice dónde acaba la imagen.
          Center(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: colors.borderSubtle),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Image.memory(
                bytes,
                height: 120,
                fit: BoxFit.contain,
                // UN ARCHIVO QUE PASÓ LA FIRMA PERO NO SE PUEDE DECODIFICAR —un PNG
                // truncado— no revienta la pantalla: se dice.
                errorBuilder: (_, _, _) => Text(
                  'No se pudo mostrar la imagen.',
                  style: AppTypography.caption.copyWith(color: colors.error),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          Text(
            '$nombre · ${(bytes.length / 1024).toStringAsFixed(0)} KB',
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
          // SE DICE QUE REEMPLAZA, porque es lo que pasa y no se puede deshacer con un
          // botón: el anterior queda en el historial del archivo, no en pantalla.
          //
          // Y NO SE DICE CUANDO NO HAY NADA QUE REEMPLAZAR —un alta—: un aviso que
          // habla de algo que no existe es lo que enseña a no leer los avisos.
          if (queReemplaza case final aviso?) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              aviso,
              style: AppTypography.caption.copyWith(color: colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
