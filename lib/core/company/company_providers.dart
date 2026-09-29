import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../di/providers.dart';
import 'almacen_company_recordada.dart';
import 'autorizacion_company.dart';
import 'company_api.dart';
import 'company_remota.dart';
import 'gestor_de_company.dart';

/// Los providers de la Company activa (Integration Foundation IF-3).
///
/// NINGUNA PANTALLA DEL PRODUCTO LOS OBSERVA, y es la decisión de la etapa: los
/// once módulos visibles siguen siendo locales y no dependen de la Company SaaS.
/// Montar un selector encima de ellos haría creer que cambiar de empresa cambia lo
/// que se ve, cuando no cambiaría nada — una mentira visible, peor que la ausencia.
///
/// LA DIRECCIÓN DE LAS DEPENDENCIAS ES DE UN SOLO SENTIDO: esto conoce `core/api`,
/// `core/auth` y `core/di`; ni `core/auth` ni `features/` conocen esto. Así el motor
/// de sesión no puede acabar dependiendo del de empresa, y un fallo de Company no
/// puede cerrar una sesión.

/// Dónde se recuerda la última empresa elegida.
final almacenCompanyRecordadaProvider = Provider<AlmacenCompanyRecordada>(
  (ref) => const AlmacenCompanyRecordadaPreferencias(),
);

/// Las dos llamadas de Company. Recibe el cliente **autenticado** de IF-2: aquí ya
/// hay sesión, y el token, su refresco y el reintento tras un 401 están resueltos
/// antes de llegar. Es lo contrario de `AuthApi`, que usa el cliente desnudo porque
/// pedir un token no puede necesitar un token.
final companyApiProvider = Provider<CompanyApi>(
  (ref) => CompanyApi(ref.watch(apiClientAutenticadoProvider)),
);

/// El motor de la Company activa. **Uno por contenedor y vivo mientras dure**: es
/// donde residen la generación y la resolución en vuelo, así que reconstruirlo
/// perdería la empresa activa y podría lanzar un descubrimiento paralelo.
final gestorDeCompanyProvider = Provider<GestorDeCompany>((ref) {
  final gestor = GestorDeCompany(
    api: ref.watch(companyApiProvider),
    almacen: ref.watch(almacenCompanyRecordadaProvider),
    logger: ref.watch(appLoggerProvider),
  );

  ref.onDispose(gestor.dispose);

  return gestor;
});

/// El estado de la Company, para observarlo.
///
/// `ValueListenable` y no `Stream` porque tiene valor actual: quien empiece a
/// escuchar sabrá en qué situación está sin esperar el siguiente evento, y no hay
/// ninguna ventana en la que un cambio se pueda perder entre leer y suscribirse.
final estadoCompanyProvider = Provider<ValueListenable<EstadoCompany>>(
  (ref) => ref.watch(gestorDeCompanyProvider).estadoObservable,
);

/// **La dependencia que todo provider remoto con alcance de empresa debe observar.**
///
/// EL PATRÓN QUEDA CONGELADO AQUÍ, y es lo contrario de un registro manual de
/// invalidaciones:
///
/// ```dart
/// final empleadosRemotosProvider = FutureProvider((ref) async {
///   final companyId = ref.watch(companyIdActivoProvider);   // ← la dependencia
///   if (companyId == null) {
///     return const Result.failure(CompanySinSeleccionFailure('...'));
///   }
///   return ref.watch(personalApiProvider).listar(companyId);
/// });
/// ```
///
/// Cuando la empresa activa cambia, Riverpod reconstruye **todo** lo que observa este
/// provider, transitivamente, y el estado de la anterior deja de existir. Un provider
/// nuevo queda cubierto por construcción, porque **no puede obtener el `companyId` de
/// otro sitio**: una lista explícita de invalidaciones se quedaría obsoleta en cuanto
/// naciera un módulo, que es justo lo que documenta `SesionController` sobre la
/// sesión.
///
/// Se prefiere observar la empresa activa antes que indexar por `companyId` con
/// familias: con una familia, los datos de A seguirían vivos en la caché de otra
/// clave y bastaría leer con la clave equivocada para mostrarlos.
///
/// Es un `Provider` que **no** es `autoDispose`: su valor tiene que sobrevivir a que
/// nadie lo observe un instante durante una transición de navegación, igual que la
/// sesión.
final companyIdActivoProvider = Provider<String?>(
  (ref) => _derivarDelEstado(
    ref,
    (estado) => switch (estado) {
      CompanyActiva(:final contexto) => contexto.companyId,
      _ => null,
    },
  ),
);

/// El contexto completo de la empresa activa, o `null`.
///
/// Lleva dentro `enabledModules`, `effectivePermissions`, `isMaestro` y `restricted`,
/// que IF-3 **conserva y no aplica**: están aquí para que IF-4 no tenga que volver a
/// pedir lo que ya vino en la misma llamada.
final companyContextProvider = Provider<CompanyContext?>(
  (ref) => _derivarDelEstado(
    ref,
    (estado) => switch (estado) {
      CompanyActiva(:final contexto) => contexto,
      _ => null,
    },
  ),
);

/// Qué puede hacer esta Identity en la empresa activa (Integration Foundation IF-4).
///
/// SE DERIVA DEL MISMO CONTEXTO, y de ahí sale la atomicidad sin sincronizar nada: al
/// cambiar de empresa, `companyContextProvider` cambia y esto se reconstruye con él. No
/// existe una segunda caché que pueda quedarse con los permisos de la anterior, porque
/// `AutorizacionCompany` no guarda permisos: los consulta en el contexto.
///
/// Sin empresa activa entrega la vista que **niega todo**. Denegar por omisión no es
/// una comprobación que alguien deba recordar: es el único valor que puede tener esto
/// cuando no hay contexto del que derivar.
final autorizacionProvider = Provider<AutorizacionCompany>(
  (ref) => AutorizacionCompany(ref.watch(companyContextProvider)),
);

/// Deriva un valor del estado de Company y lo recalcula cuando ese estado cambia.
///
/// Un `ValueNotifier` no es algo que Riverpod observe por sí solo, así que se escucha
/// explícitamente y el aviso se traduce en `invalidateSelf`. La lógica vive **una
/// vez** aquí: repetirla por provider haría que uno se quedara sin escuchar y su
/// valor se congelara en la empresa anterior, que es exactamente el error que esta
/// capa existe para impedir.
T _derivarDelEstado<T>(Ref ref, T Function(EstadoCompany) leer) {
  final observable = ref.watch(estadoCompanyProvider);

  void avisar() => ref.invalidateSelf();

  observable.addListener(avisar);
  ref.onDispose(() => observable.removeListener(avisar));

  return leer(observable.value);
}
