/// **Claro, oscuro o el del sistema, en la web.**
///
/// ## 🚫 Por qué existe, y qué estaba mal antes
///
/// Hasta el 12 de noviembre de 2026 **la web no tenía tema oscuro**: `main_web.dart`
/// declaraba `theme:` y nada más, así que `AppTheme.dark()` existía en el proyecto —el
/// escritorio sí lo usa— y **la web no tenía forma de pintarlo**. La barra superior lo
/// decía con todas sus letras: «el selector de tema no está».
///
/// ⚠️ **Y YO DIJE QUE LO HABÍA REVISADO.** Las capturas «en oscuro» del 11 de noviembre
/// salieron de un andamio que montaba las pantallas con `AppTheme.dark()` **a mano**: los
/// colores eran los de verdad, pero **el producto no podía enseñarlos**, así que decir
/// «revisado en oscuro» afirmaba un estado que no existía. El dueño lo cazó leyendo
/// `main_web.dart`. La lección queda en [[feedback_verificacion_en_la_app_real]]: una
/// captura sólo prueba algo si sale **por el camino por el que el usuario llega**.
///
/// ## Por qué un `ValueNotifier` y no el controlador del escritorio
///
/// El del escritorio es un `@riverpod` y **la web no monta `ProviderScope`**: su shell son
/// widgets y gestores corrientes. Traer Riverpod para un enum sería traer un contenedor
/// entero por una preferencia.
///
/// **Se guarda en `shared_preferences`**, que en el navegador es `localStorage`: la misma
/// pieza que el escritorio y la misma clave, así que quien use los dos no encuentra dos
/// preferencias distintas con el mismo nombre.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La misma clave que usa el escritorio: una preferencia, un nombre.
const _clave = 'riseg_one.theme_mode';

class ModoDeTemaWeb extends ValueNotifier<ThemeMode> {
  /// Arranca en **el del sistema** y luego lee lo guardado.
  ///
  /// ⚠️ **NO BLOQUEA EL ARRANQUE**: leer la preferencia es asíncrono, y esperarla
  /// retrasaría la primera pantalla por un color. Si había algo guardado, el tema cambia
  /// en cuanto llega; si no, se queda con el del sistema, que es la respuesta correcta
  /// para quien nunca eligió.
  ModoDeTemaWeb() : super(ThemeMode.system) {
    _restaurar();
  }

  Future<void> _restaurar() async {
    // ⚠️ **EL ALMACÉN PUEDE NO ESTAR, Y ESO NO ES UN FALLO DE LA APLICACIÓN.** En el
    // navegador `localStorage` se puede estar negando —ventana privada, datos de sitio
    // bloqueados— y fuera de él el complemento puede faltar: en un banco de pruebas sin
    // `setMockInitialValues` esto lanzaba `MissingPluginException`. Un color recordado es
    // una comodidad; **que no se pueda leer no puede tirar el arranque**, así que se cae
    // al tema del sistema, que es la respuesta correcta para quien nunca eligió.
    final String? guardado;

    try {
      guardado = (await SharedPreferences.getInstance()).getString(_clave);
    } on Object {
      return;
    }

    if (guardado == null) return;

    value = ThemeMode.values.firstWhere(
      (m) => m.name == guardado,
      // UN VALOR QUE NO RECONOCEMOS NO ROMPE NADA: se cae al del sistema. Puede venir de
      // una versión vieja, de otra máquina o de alguien escribiendo en `localStorage`.
      orElse: () => ThemeMode.system,
    );
  }

  /// Cambia el tema **y lo recuerda**.
  ///
  /// ⚠️ **EL TEMA CAMBIA ANTES DE GUARDAR, y en ese orden a propósito:** si el almacén
  /// falla, la elección **sí se aplica** —se pierde al recargar, y eso es lo que se puede
  /// perder— en vez de no pasar nada al pulsar.
  Future<void> elegir(ThemeMode modo) async {
    value = modo;

    try {
      await (await SharedPreferences.getInstance()).setString(_clave, modo.name);
    } on Object {
      return;
    }
  }
}
