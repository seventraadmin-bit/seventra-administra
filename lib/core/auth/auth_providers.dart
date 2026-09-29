import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client_autenticado.dart';
import '../api/api_providers.dart';
import '../di/providers.dart';
import 'almacen_sesion_remota.dart';
import 'auth_api.dart';
import 'gestor_de_sesion.dart';
import 'sesion_remota.dart';

/// Los providers de la autenticación remota (Integration Foundation IF-2).
///
/// NINGUNA PANTALLA DEL PRODUCTO LOS OBSERVA TODAVÍA, y es la decisión de la
/// etapa: el portón sigue siendo la sesión local (`SesionUsuario`), el router no
/// se ha tocado y `bootstrap` no restaura nada remoto. Estos providers existen
/// para que la maquinaria sea construible e inyectable —por pruebas hoy, por la
/// capa SaaS cuando llegue el relevo—, no para empezar a gobernar el arranque.
///
/// LA DIRECCIÓN DE LAS DEPENDENCIAS ES DE UN SOLO SENTIDO: esto conoce
/// `core/api` y `core/di`, y **nada de `features/usuarios` conoce esto**. Así no
/// hay ciclo posible, y sobre todo no hay forma de que la sesión local acabe
/// dependiendo de la remota por accidente.

/// Dónde se guarda la credencial entre arranques.
///
/// Se construye aquí y no en `bootstrap` porque no necesita inicialización: es una
/// fachada sobre el almacén de credenciales de Windows. Las pruebas lo
/// sobreescriben con una implementación en memoria, igual que ya hacen con
/// `almacenSesionRecordadaProvider`.
final almacenSesionRemotaProvider = Provider<AlmacenSesionRemota>(
  (ref) => const AlmacenSesionRemotaWindows(),
);

/// Las tres llamadas de `/auth`. Recibe el cliente **desnudo**: firmarlas con el
/// decorador autenticado haría que pedir un token necesitara un token.
final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(apiClientProvider)),
);

/// El motor de la sesión remota. **Uno por contenedor y vivo mientras dure**: es
/// donde reside el token de acceso en memoria y el apunte del refresco en vuelo,
/// así que reconstruirlo perdería la sesión y podría lanzar un segundo refresco
/// en paralelo — justo lo que el backend interpreta como reutilización.
final gestorDeSesionProvider = Provider<GestorDeSesion>((ref) {
  final gestor = GestorDeSesion(
    api: ref.watch(authApiProvider),
    almacen: ref.watch(almacenSesionRemotaProvider),
    logger: ref.watch(appLoggerProvider),
  );

  ref.onDispose(gestor.dispose);

  return gestor;
});

/// El estado de la autenticación remota, para observarlo.
///
/// Se expone como `ValueListenable` y no como `Stream` porque tiene valor actual:
/// quien empiece a escuchar sabrá en qué situación está sin esperar el siguiente
/// evento, y no hay ninguna ventana en la que un cambio se pueda perder entre leer
/// y suscribirse.
final estadoAutenticacionProvider =
    Provider<ValueListenable<EstadoAutenticacion>>(
      (ref) => ref.watch(gestorDeSesionProvider).estadoObservable,
    );

/// El cliente HTTP con sesión, para cuando un módulo empiece a consumir el
/// backend. En IF-2 no lo usa ninguna feature.
final apiClientAutenticadoProvider = Provider<ApiClientAutenticado>(
  (ref) => ApiClientAutenticado(
    cliente: ref.watch(apiClientProvider),
    gestor: ref.watch(gestorDeSesionProvider),
  ),
);
