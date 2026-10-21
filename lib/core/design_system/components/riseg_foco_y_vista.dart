/// Que **la vista siga a donde se fue la atención**, en un formulario más alto que la
/// pantalla.
///
/// ## Los dos defectos que esto arregla, los dos medidos
///
/// El expediente de una sucursal mide 962 px más que una ventana de 900, y en esa
/// diferencia caben dos formas de dejar a la persona mirando el sitio equivocado:
///
/// **1 · `Tab` da la vuelta y la vista se queda abajo.** Bajando, el recorrido
/// funciona: Flutter desplaza el formulario para que el campo enfocado se vea. Pero al
/// llegar al último —«Guardar expediente»— el siguiente `Tab` devuelve el foco al
/// primero, **arriba**, y la vista no sube con él. Medido: el enlace de regreso queda
/// en `y = -910` con el desplazamiento quieto en 934. Dos `Tab` más y se está
/// escribiendo a ciegas en un campo que no se ve.
///
/// La causa está en el propio Flutter y no en la pantalla:
/// `FocusTraversalPolicy.next` llama a `ensureVisible` con
/// `ScrollPositionAlignmentPolicy.keepVisibleAtEnd`, que **sólo desplaza hacia abajo**.
/// Para un destino que está por encima no hace nada.
///
/// **2 · Guardar desde abajo con un error arriba.** El botón está al final y el nombre
/// al principio. Medido: con el servidor señalando `name`, el error **se pinta** y el
/// desplazamiento se queda en 962, así que para la persona el botón no hizo nada.
///
/// ## Lo que hace, y lo que deliberadamente NO hace
///
/// Desplaza **sólo cuando lo enfocado queda fuera de la ventana**. Llevar el campo
/// enfocado siempre a la misma altura sería más simple de escribir y peor de usar: la
/// vista daría un salto en cada `Tab`, incluso entre dos campos que ya se veían juntos.
///
/// Y **no toca el orden** del recorrido. El orden que Flutter deduce de la geometría ya
/// es el de lectura —medido campo por campo en el expediente— así que imponer uno
/// propio sería cambiar algo que funciona por algo que habría que mantener.
library;

import 'package:flutter/material.dart';

/// Instala el recorrido de foco que **arrastra la vista** en las dos direcciones.
///
/// Se pone **por encima del `Scrollable`**, envolviendo el formulario entero: la
/// política necesita encontrar el `Scrollable` desde el contexto de lo enfocado, y lo
/// busca hacia arriba.
class RisegRecorridoDeFoco extends StatelessWidget {
  const RisegRecorridoDeFoco({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    policy: RisegPoliticaDeFoco(),
    child: child,
  );
}

/// El orden de lectura de siempre, **más traer la vista cuando hace falta**.
///
/// Se expone por si una pantalla necesita componerla con otro `FocusTraversalGroup`;
/// lo normal es usar [RisegRecorridoDeFoco].
class RisegPoliticaDeFoco extends ReadingOrderTraversalPolicy {
  @override
  bool next(FocusNode currentNode) =>
      _trayendoLaVista(() => super.next(currentNode));

  @override
  bool previous(FocusNode currentNode) =>
      _trayendoLaVista(() => super.previous(currentNode));

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) =>
      _trayendoLaVista(() => super.inDirection(currentNode, direction));

  /// Mueve el foco y, **si lo nuevo quedó fuera**, trae la vista.
  ///
  /// El movimiento se hace primero y se pregunta después: quién acabó con el foco lo
  /// decide la política de arriba, no esta función.
  bool _trayendoLaVista(bool Function() mover) {
    final movio = mover();

    // ⚠️ **DESPUÉS DEL CUADRO, Y NO AQUÍ MISMO.** `requestFocus` no entrega el foco en
    // el instante: lo aplica en el siguiente ciclo. Preguntar por `primaryFocus` en
    // esta línea devuelve el nodo **VIEJO**, y la primera versión de esto hacía
    // justamente eso: miraba el botón de guardar —que sí se veía—, decidía que no
    // hacía falta desplazar, y la vista se quedaba abajo. Al `Tab` siguiente
    // desplazaba hacia el nodo anterior, así que la vista iba **un paso por detrás**
    // del foco todo el recorrido.
    //
    // Lo cazó la prueba de la vuelta: esperaba la vista arriba y medía 934.
    if (movio) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => risegLlevarLaVistaAlFoco(),
      );
    }

    return movio;
  }
}

/// Los nodos de foco de un formulario, **indexados por la clave que usa el SERVIDOR**.
///
/// ## Para qué, y el defecto que cierra
///
/// Cuando un guardado falla, la pantalla **enfoca el primer campo señalado**: eso hace
/// de una vez las dos cosas que la persona necesita —ver el campo y poder escribir en
/// él sin volver a pulsarlo—.
///
/// Sin esto, medido en el expediente de una sucursal: con el botón de guardar al final
/// del formulario y el nombre al principio, un error en el nombre se pintaba **fuera de
/// la vista** y el desplazamiento se quedaba abajo. Para la persona, el botón no había
/// hecho nada.
///
/// ## Las dos reglas que están aquí y no en cada pantalla
///
/// **1 · La clave es la del servidor, dicha una sola vez.** El mismo `name` o
/// `address.street` que llega en `fields` sirve para el nodo y para el error. Dos
/// claves escritas por separado es cómo el error se pinta en «Colonia» y la vista va a
/// «Municipio», sin que nada falle.
///
/// **2 · Se va al primero del FORMULARIO, no al primero de la respuesta.** El servidor
/// reúne todos los errores antes de fallar, y el orden en que los enumera no lo
/// controlamos. [orden] es el de la pantalla, de arriba abajo.
class RisegFocosDeFormulario {
  RisegFocosDeFormulario(this.orden)
    : _focos = {for (final campo in orden) campo: FocusNode()};

  /// Los campos **en el orden en que están en la pantalla**.
  final List<String> orden;

  final Map<String, FocusNode> _focos;

  /// El nodo de un campo, o nulo si ese campo no se puede enfocar —un selector, una
  /// sección— y hay que llegar a él por su sitio.
  FocusNode? operator [](String campo) => _focos[campo];

  /// **No es opcional.** Un `FocusNode` sin liberar deja al `FocusManager` con una
  /// referencia a un widget desmontado.
  void dispose() {
    for (final nodo in _focos.values) {
      nodo.dispose();
    }
  }

  /// Lleva la vista y el cursor al primer campo señalado.
  ///
  /// Devuelve `false` cuando ninguno de los campos señalados es enfocable —el error es
  /// del horario, o del selector de régimen—, y entonces la pantalla lo resuelve con
  /// [risegLlevarLaVistaA] sobre la sección que lo contiene.
  bool llevarLaVistaAlPrimerError(Map<String, String?> errores) {
    for (final campo in orden) {
      if (errores[campo] == null) continue;

      final nodo = _focos[campo];
      if (nodo == null) continue;

      nodo.requestFocus();

      // LA VISTA SE TRAE CON EL CONTEXTO DEL NODO, no con `primaryFocus`: pedir el
      // foco no lo entrega en el mismo instante, así que `primaryFocus` todavía sería
      // el botón de guardar y la vista se quedaría donde estaba.
      //
      // Y un campo de SÓLO LECTURA no acepta el foco, pero su contexto sigue
      // existiendo: la vista llega igual y el campo en rojo se ve. Es lo correcto —si
      // no lo puede editar, al menos ve qué pasó—.
      if (nodo.context case final contexto?) risegLlevarLaVistaA(contexto);

      return true;
    }

    return false;
  }
}

/// Trae la vista a lo que tiene el foco, **si está fuera de la ventana**.
///
/// Sirve también suelta: después de un guardado que falla, la pantalla enfoca el primer
/// campo señalado y esto lo pone a la vista.
void risegLlevarLaVistaAlFoco() {
  final contexto = FocusManager.instance.primaryFocus?.context;

  if (contexto != null) risegLlevarLaVistaA(contexto);
}

/// Trae la vista a un contexto cualquiera, **si está fuera de la ventana**.
///
/// Para lo que no se puede enfocar: la sección del horario no es un campo de texto, así
/// que cuando el error es del horario lo que se trae a la vista es la sección.
///
/// **Es tolerante a propósito.** Un contexto desmontado, sin `Scrollable` encima o sin
/// `RenderBox` todavía **no hace nada** en vez de lanzar: esto se llama desde un
/// recorrido de teclado y desde la respuesta de una petición, y romper la pantalla por
/// no poder desplazarla sería peor que no desplazarla.
void risegLlevarLaVistaA(BuildContext contexto, {double alineacion = 0.15}) {
  if (!contexto.mounted) return;

  final posicion = Scrollable.maybeOf(contexto)?.position;
  if (posicion == null) return;

  final caja = contexto.findRenderObject();
  if (caja is! RenderBox || !caja.hasSize) return;

  final viewport = Scrollable.maybeOf(contexto)!.context.findRenderObject();
  if (viewport is! RenderBox || !viewport.hasSize) return;

  // DÓNDE ESTÁ LO ENFOCADO **DENTRO** DE LA VENTANA que lo desplaza, no en la pantalla:
  // el formulario puede tener encima una barra de pestañas y un rastro, y medir contra
  // la pantalla contaría ese alto como si fuera parte del área desplazable.
  final arriba = caja.localToGlobal(Offset.zero, ancestor: viewport).dy;
  final abajo = arriba + caja.size.height;

  // YA SE VE ENTERO: no se toca nada. Un desplazamiento en cada `Tab` —aunque fuera
  // pequeño— convertiría recorrer un formulario en una sucesión de saltos.
  if (arriba >= 0 && abajo <= viewport.size.height) return;

  Scrollable.ensureVisible(
    contexto,
    // `explicit` ES LO QUE PERMITE SUBIR. `keepVisibleAtEnd` —el que usa la política de
    // Flutter— sólo desplaza hacia abajo, que es exactamente por qué la vuelta de `Tab`
    // dejaba la vista abajo.
    alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    alignment: alineacion,
    duration: const Duration(milliseconds: 140),
    curve: Curves.easeOut,
  );
}
