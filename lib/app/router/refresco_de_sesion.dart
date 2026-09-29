import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/usuarios/presentation/sesion_controller.dart';

/// Le avisa al router cuando la sesión cambia, para que vuelva a decidir la ruta.
///
/// ## Por qué existe
///
/// El `redirect` de GoRouter corre **al navegar**, no cuando cambia un provider.
/// Mientras la sesión se restauraba leyendo SQLite eso no importaba: `bootstrap()`
/// la resolvía ANTES de `runApp`, así que la primera evaluación ya la veía.
///
/// Con el cutover (IF-5) restaurar pasó a ser una llamada de RED. Esperarla antes
/// de `runApp` dejaría la ventana en blanco mientras el servidor contesta, así que
/// se lanza en paralelo — y entonces el primer `redirect` corre sin sesión y manda
/// a `/login`. **Sin este puente, la sesión llegaba después y nadie volvía a
/// mirarla: la aplicación se quedaba en «Iniciar sesión» con la credencial
/// intacta en el almacén seguro.** Era exactamente el fallo reportado al cerrar
/// con la X y volver a abrir.
///
/// ## Funciona en las dos direcciones, y eso importa
///
/// No sólo saca del login cuando la sesión aparece: también devuelve al login en
/// el acto cuando desaparece —acceso revocado, suscripción caída, cierre de
/// sesión— sin esperar a que alguien navegue. Antes ese caso dependía de que la
/// persona tocara algo.
///
/// ## Lo que NO hace
///
/// No decide nada. No lee permisos, no resuelve Company y no toca el estado: sólo
/// notifica. Quien decide sigue siendo el `redirect`, que es donde el gate estaba
/// y donde se puede leer entero de un tirón.
class RefrescoDeSesion extends ChangeNotifier {
  RefrescoDeSesion(ProviderContainer contenedor) {
    // `fireImmediately: false`: al construirse el router todavía no hay nada que
    // reevaluar, y notificar antes del primer `redirect` sería trabajo inútil.
    _suscripcion = contenedor.listen(
      sesionControllerProvider,
      (_, __) => notifyListeners(),
    );
  }

  late final ProviderSubscription<dynamic> _suscripcion;

  @override
  void dispose() {
    _suscripcion.close();
    super.dispose();
  }
}
