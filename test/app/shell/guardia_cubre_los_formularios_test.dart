// LA REGLA PERMANENTE DE D-56, con su candado.
//
// > **Toda pantalla con «Guardar» se registra en el `GuardiaDeSalida`.**
//
// Decidida por el dueño el 26 de octubre de 2026, y la razón de que sea un candado y no un
// párrafo es la que ya se ha visto tres veces en este proyecto: un acuerdo que depende de
// que alguien lo recuerde se olvida en el formulario número siete. **Clientes, Servicios y
// lo que venga nacen con esto puesto**, porque la suite se pone roja si no.
//
// ## Lo que de verdad protege
//
// Un formulario que no se registra **no está protegido por ninguno de los cuatro
// caminos**: ni el `onExit` de la ruta, ni el cambio de empresa, ni `beforeunload`. Y no
// se nota al programarlo: se nota el día que alguien pierde media hora de captura.
//
// ## ⚠️ ESTE CANDADO YA SIRVIÓ ANTES DE EXISTIR
//
// Al censar a mano los formularios con «Guardar» me salté el **panel de permisos de
// Usuarios**, porque pone la etiqueta de su botón con un `?:` —`guardando ? 'Guardando…' :
// 'Guardar'`— y el `grep` de `label: 'Guardar` no lo veía. Doce casillas marcadas a mano
// son exactamente el trabajo que D-56 vino a no tirar. Por eso la detección de abajo
// **no busca la forma del botón**, busca la palabra.
//
// ## Cómo está escrito, y por qué NO lleva lista de archivos
//
// ⚠️ **UNA PRUEBA NUNCA SE FIJA A UNA LISTA EXACTA NI A UN TOTAL** — es la regla que este
// proyecto ha roto once veces. Aquí no hay censo de formularios: hay una **propiedad**
// —«el que guarda, participa»— aplicada archivo por archivo, y una **cota superior** para
// que crecer sea una decisión y no un descuido. Añadir un formulario correcto no rompe
// nada; añadir uno que no participa, sí.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String normalizar(String ruta) => ruta.replaceAll(r'\', '/');

  /// Los archivos de la web, que son los únicos a los que la regla aplica: el escritorio
  /// tiene sus propios diálogos de confirmación desde antes de la mudanza.
  List<File> fuentesDeLaWeb() => Directory('lib/features')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) {
        final ruta = normalizar(f.path);

        return ruta.endsWith('.dart') &&
            !ruta.endsWith('.g.dart') &&
            ruta.contains('/web/');
      })
      .toList();

  /// ¿Este archivo tiene un formulario que guarda?
  ///
  /// **Dos señales, y hacen falta las dos:**
  ///
  ///  · **la palabra «Guardar»** en un texto, que es cómo se llama el botón en todo el
  ///    producto — y se busca la palabra y no `label: 'Guardar`, porque la etiqueta puede
  ///    venir de un `?:`, que es justo lo que se me escapó censando a mano;
  ///  · **un `TextEditingController` o un conjunto de casillas**, que es lo que convierte
  ///    una pantalla en algo que puede tener trabajo escrito.
  ///
  /// La segunda señal es la que deja fuera `dialogo_de_choque.dart`, que ofrece «Guardar
  /// con estas decisiones» y **no es un formulario**: las decisiones se toman en el propio
  /// diálogo, así que cerrarlo no pierde nada que estuviera a medias.
  bool guardaAlgo(String codigo) =>
      codigo.contains("'Guardar") &&
      (codigo.contains('TextEditingController') ||
          codigo.contains('Set<String> _marcados'));

  /// ¿Participa del guardia?
  ///
  /// **Dos formas válidas, y la segunda no es un atajo:**
  ///
  ///  · **el mixin** `DeclaraSuTrabajoSinGuardar`, que es lo normal;
  ///  · **publicar la pregunta hacia arriba** con `alVigilarCambios`, que es lo que hace
  ///    el formulario del expediente de la empresa: él no tiene el guardia —lo tiene la
  ///    pestaña que lo monta— y le entrega la pregunta a quien sí.
  bool participaDelGuardia(String codigo) =>
      codigo.contains('DeclaraSuTrabajoSinGuardar') ||
      codigo.contains('alVigilarCambios');

  group('toda pantalla con «Guardar» se registra en el guardia', () {
    test('ninguna se queda fuera', () {
      final infractores = <String>[];
      final cubiertos = <String>[];

      for (final archivo in fuentesDeLaWeb()) {
        final codigo = archivo.readAsStringSync();
        if (!guardaAlgo(codigo)) continue;

        final ruta = normalizar(archivo.path);

        if (participaDelGuardia(codigo)) {
          cubiertos.add(ruta);
        } else {
          infractores.add(ruta);
        }
      }

      expect(
        infractores,
        isEmpty,
        reason:
            'Estos formularios de la web guardan y NO participan del '
            '`GuardiaDeSalida`, así que lo escrito en ellos se pierde sin preguntar al '
            'pulsar «atrás», al recargar, al cerrar la pestaña y al cambiar de '
            'empresa.\n\n'
            'Se arregla con el mixin `DeclaraSuTrabajoSinGuardar` —`guardia`, '
            '`hayCambiosSinGuardar` y `queSePierde`— o, si el formulario no tiene el '
            'guardia, publicando la pregunta hacia arriba como `alVigilarCambios`.\n\n'
            '${infractores.join('\n')}',
      );

      // LA RED DE LA RED: si la detección dejara de encontrar nada —porque alguien
      // renombre el botón, o cambie la forma de los formularios— esta prueba pasaría
      // vacía y dejaría de proteger sin que nadie se enterara. Es el mismo error que
      // «esperaba cero y encontró cero porque no miró».
      expect(
        cubiertos,
        isNotEmpty,
        reason:
            'La detección no encontró NI UN formulario que guarde, y la web tiene '
            'varios: el candado dejó de mirar. Revisa `guardaAlgo`.',
      );
    });

    test('y la cuenta de formularios no crece sin que se note', () {
      final queGuardan = [
        for (final archivo in fuentesDeLaWeb())
          if (guardaAlgo(archivo.readAsStringSync())) normalizar(archivo.path),
      ]..sort();

      // SE ACOTA POR ARRIBA Y NO SE FIJA LA LISTA, que es la regla de este proyecto: así
      // añadir el formulario de Clientes no rompe nada, y duplicar los formularios de la
      // web obliga a pasar por aquí y explicarlo.
      expect(
        queGuardan.length,
        lessThanOrEqualTo(14),
        reason:
            'La web tiene ${queGuardan.length} formularios que guardan. Si de verdad '
            'hacen falta tantos, sube el tope en un commit que lo explique: el número '
            'está para que crecer sea una decisión.\n${queGuardan.join('\n')}',
      );
    });
  });

  group('las hojas modales se cierran cuando cambia la dirección', () {
    test('la que abre una hoja, o la hoja misma, lo declara', () {
      // ⚠️ UNA HOJA MODAL NO VIVE EN EL HISTORIAL del router: la empuja el `Navigator`,
      // no go_router. Así que al confirmar «Salir sin guardar» se quedaría **encima de la
      // pantalla nueva**, con los campos puestos y un guardar que escribiría en el sitio
      // de antes.
      //
      // El archivo que abre la hoja es el mismo que la define —son clases privadas—, así
      // que basta comprobar que ahí esté el mixin.
      final infractores = <String>[];

      for (final archivo in fuentesDeLaWeb()) {
        final codigo = archivo.readAsStringSync();

        if (!codigo.contains('showModalBottomSheet')) continue;
        if (codigo.contains('SeCierraAlCambiarLaDireccion')) continue;

        infractores.add(normalizar(archivo.path));
      }

      expect(
        infractores,
        isEmpty,
        reason:
            'Estos archivos abren una hoja modal y no usan '
            '`SeCierraAlCambiarLaDireccion`, así que la hoja se quedaría encima de la '
            'pantalla nueva al cambiar de dirección.\n\n${infractores.join('\n')}',
      );
    });
  });
}
