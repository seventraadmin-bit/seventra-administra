import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system_web.dart';

/// Pide el motivo para eliminar definitivamente una fila de catálogo, y lo valida.
///
/// ## Reutiliza el diálogo del escritorio, no uno propio
///
/// Llama a `mostrarDialogoMotivo`, que ya existe en el sistema de diseño y lleva dentro
/// una lección cara de este proyecto: su campo vive en un `StatefulWidget` que posee y
/// destruye su propio controlador, porque crearlo fuera y destruirlo tras el `await`
/// estalla con *«A TextEditingController was used after being disposed»* —la transición
/// de salida mantiene el campo montado un frame más—.
///
/// Escribir aquí un diálogo nuevo habría significado volver a tropezar con eso. La regla
/// del proyecto es explícita: **si algo ya existe en el escritorio, la web lo reutiliza
/// tal cual; no se rediseña.**
///
/// ## Lo único que esta función añade
///
/// **El tope de 500 caracteres**, que es una regla del SaaS y no del escritorio: el
/// `AuditPayload` del backend **lanza** con un valor textual de más de 512, así que un
/// motivo largo convertiría un borrado legítimo en un error 500. Se comprueba aquí y no
/// dentro del diálogo compartido para no meter una regla de la nube en un componente que
/// el escritorio también usa —y el escritorio no se toca—.
///
/// ## Lo que NO hace
///
/// **No decide si se puede borrar.** Eso lo contesta el servidor, con el conteo de lo que
/// estorba. Una comprobación local intentaría adivinarlo y acabaría ofreciendo un botón
/// que falla, o escondiéndolo sin poder decir por qué.
Future<String?> pedirMotivoDeEliminacion(
  BuildContext context, {
  required String queEs,
  required String comoSeLlama,
  required String queSePierde,
}) async {
  final motivo = await mostrarDialogoMotivo(
    context,
    titulo: 'Eliminar $queEs',
    etiquetaMotivo: 'Motivo',
    confirmarLabel: 'Eliminar',
    cancelarLabel: 'Cancelar',
    errorMotivoRequerido:
        'Falta el motivo. Eliminar es definitivo y el motivo es lo único que '
        'quedará de $queEs.',
    // LA ADVERTENCIA NOMBRA LA FILA Y DICE QUÉ SE PIERDE. «Esta acción no se puede
    // deshacer» a secas no informa: todo el mundo la ha leído mil veces y nadie sabe
    // qué pierde. Y sin el nombre, la persona tiene que confiar en que pulsó la fila
    // correcta.
    advertencia:
        '$comoSeLlama\n\n'
        '$queSePierde No se puede recuperar. Si sólo quieres dejar de usarlo, '
        'desactívalo en vez de eliminarlo.',
    // EL BOTÓN QUE DESTRUYE NO SE PARECE AL QUE GUARDA. Estaba en azul de acento,
    // idéntico a un «Guardar», y es el último clic antes de que una fila desaparezca.
    destructivo: true,
  );

  if (motivo == null) return null;

  if (motivo.length > motivoMaximo) {
    if (context.mounted) {
      RisegFeedback.showError(
        context,
        'El motivo admite hasta $motivoMaximo caracteres; escribiste ${motivo.length}.',
      );
    }

    return null;
  }

  return motivo;
}

/// Cuántos caracteres admite el motivo. **Lo fija el servidor**, no esta pantalla:
/// su `AuditPayload` lanza por encima de 512, y 500 deja margen.
const int motivoMaximo = 500;

/// El rechazo del servidor al borrar o al desactivar, mostrado donde se lee.
///
/// ## Por qué no es un `errorText` de campo
///
/// Porque **no es un error de ningún campo**. «Tiene 3 puesto(s) registrado(s)» no se
/// arregla cambiando lo que está escrito en el formulario; se arregla en otra pantalla.
/// Ponerlo bajo el campo del código —que es donde acababa antes de M3, porque todo 409
/// se trataba como código duplicado— mandaba a la persona a cambiar un código que estaba
/// perfectamente bien.
///
/// ## Por qué el texto llega del servidor y no se reescribe
///
/// Porque el servidor es el único que sabe **el conteo**, y el conteo es lo que cambia
/// qué hace la persona: a un puesto lo mueve, a doscientos los deja y desactiva. Un
/// mensaje local tendría que decir «tiene puestos» sin número, que es la versión inútil.
/// Los dos códigos con los que el servidor rechaza por ESTADO —`estructura_en_uso` y
/// `desactivacion_bloqueada`— caen aquí, y es lo correcto: los dos traen su conteo y su
/// salida escritas desde el servidor.
///
/// **No existe una constante con esa lista**, y es deliberado: las pantallas sólo
/// necesitan distinguir `code_conflict` —que sí va a un campo— de todo lo demás. Una
/// lista de los otros códigos sería una segunda fuente de verdad que habría que
/// mantener al día con el backend sin que nada lo exija.
void mostrarRechazoDelServidor(BuildContext context, String mensaje) =>
    RisegFeedback.showError(context, mensaje);
