import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/rechazo_del_servidor.dart';

// EL RECHAZO DEL SERVIDOR Y EL TOPE DEL MOTIVO SE FUERON A `core/error/` EN C1, y se
// reexportan desde aquí a propósito: las cuatro pantallas de la estructura los usan
// junto a `pedirMotivoDeEliminacion`, y partirles el import en dos sólo para que la
// mudanza se vea no las habría mejorado en nada. Lo que el movimiento resuelve es que
// **Clientes no tenga que importar de Organización** para traducir un 402.
export '../../../../core/error/rechazo_del_servidor.dart'
    show mostrarRechazoDelServidor, motivoMaximo;

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

