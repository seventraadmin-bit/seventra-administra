/// Cierra una hoja modal cuando **cambia la dirección** (D-56).
///
/// ## El agujero que tapa, y por qué no lo tapa el router
///
/// Las cuatro hojas de alta y edición de la estructura —área, puesto, sucursal, tipo de
/// sucursal— se abren con `showModalBottomSheet`, y **eso no es una ruta**: la empuja el
/// `Navigator` directamente, no go_router, así que **no vive en el historial** y un cambio
/// de dirección no se la lleva.
///
/// El efecto, pensado antes de escribir esto: alguien con un alta a medio llenar pulsa
/// «atrás», el `onExit` de la ruta pregunta, confirma «Salir sin guardar»… y **la hoja se
/// queda encima de la pantalla nueva**, con los campos puestos y un botón de guardar que
/// escribiría en el sitio de antes.
///
/// ## Por qué aquí y no en otros dos sitios que se consideraron
///
/// **No lo hace el portón**, que es quien sabe que la dirección cambió: no sabe que hay
/// una hoja abierta, y enseñarle a saberlo sería devolverle a la cáscara un estado que es
/// de la pantalla — justo lo que D-39 vino a quitar.
///
/// **No lo hace la pantalla que abrió la hoja**: áreas y puestos no reciben ningún dato de
/// la dirección, así que no pueden enterarse; y al cambiar de pestaña la pantalla **se
/// desmonta** y la hoja no — el `dispose` de la pantalla no alcanza a una ruta que vive
/// por encima de ella.
///
/// Así que lo hace **la hoja misma**, que es la que tiene que irse.
///
/// ## Por qué un mixin y no un widget que envuelva
///
/// Porque un envoltorio añade un nivel al árbol de los cuatro paneles **sin cambiar lo que
/// pintan**, y eso es ruido en cuatro archivos. El mixin no toca el `build`.
///
/// ⚠️ **SIN ROUTER NO HACE NADA, y es deliberado.** Las pruebas de los cuatro paneles los
/// montan con `MaterialApp(home: …)`, sin router, porque lo que miden son los campos y los
/// permisos. Con `GoRouter.of` esas pruebas reventarían con un error que no tiene nada que
/// ver con lo que afirman; con `maybeOf`, el mixin es transparente.
///
/// **El orden con el `onExit` sale bien y no por casualidad:** go_router pregunta primero
/// y **sólo adopta la dirección nueva si se confirma**. Si se cancela no hay notificación,
/// y la hoja se queda donde estaba — que es lo correcto.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

mixin SeCierraAlCambiarLaDireccion<T extends StatefulWidget> on State<T> {
  GoRouter? _router;

  /// La dirección en la que se abrió. **Se guarda al montarse**, porque es con la que hay
  /// que comparar: la hoja pertenece al sitio donde alguien la abrió.
  String? _direccionAlAbrir;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // SE BUSCA AQUÍ Y NO EN `initState`: leer un `InheritedWidget` del árbol en
    // `initState` no está permitido, y esto sí.
    final router = GoRouter.maybeOf(context);
    if (router == _router) return;

    _router?.routerDelegate.removeListener(_alCambiarLaDireccion);
    _router = router;
    _direccionAlAbrir = router?.state.uri.path;
    router?.routerDelegate.addListener(_alCambiarLaDireccion);
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_alCambiarLaDireccion);

    super.dispose();
  }

  void _alCambiarLaDireccion() {
    if (!mounted) return;

    final ahora = _router?.state.uri.path;
    if (ahora == null || ahora == _direccionAlAbrir) return;

    // `maybePop` Y NO `pop`: si por lo que sea esta hoja ya no es lo de encima, un `pop`
    // cerraría **otra cosa**. Y se comprueba que haya algo que cerrar por lo mismo.
    final navegador = Navigator.maybeOf(context);
    if (navegador?.canPop() ?? false) navegador!.maybePop();
  }
}
