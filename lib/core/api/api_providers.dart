import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../di/providers.dart';
import 'api_client.dart';

/// Los providers de la capa HTTP (Integration Foundation IF-1).
///
/// Siguen el patrón que el proyecto ya usa en `core/di/providers.dart`: lo que
/// depende de inicialización —la configuración validada y el cliente de
/// transporte— se resuelve UNA VEZ en `bootstrap` antes de `runApp` y se inyecta
/// con `ProviderScope(overrides: [...])`. Los dos de abajo lanzan si nadie los
/// sobreescribió, exactamente como `appDatabaseProvider`.
///
/// Viven aquí y no en `core/di/providers.dart` porque ése es el archivo raíz que
/// importa medio proyecto, y arrastrarle `package:http` obligaría a todo el árbol
/// a conocer el transporte.

/// La dirección del backend, ya validada y normalizada.
///
/// Se sobreescribe en `bootstrap` con el resultado de `ApiConfig.resolve()`. Si la
/// configuración es inválida, `bootstrap` no llega a construir el `ProviderScope`:
/// la aplicación no arranca, y eso es deliberado (ver `ApiConfig`).
final apiConfigProvider = Provider<ApiConfig>((ref) {
  throw UnimplementedError(
    'apiConfigProvider debe sobreescribirse en bootstrap.',
  );
});

/// El cliente de transporte. **UNO para toda la aplicación.**
///
/// No se crea por pantalla ni por petición: perdería el pool de conexiones y
/// repetiría el saludo TLS en cada llamada. Lo construye `bootstrap` y lo cierra
/// el propio provider al desecharse, lo que importa sobre todo en pruebas, donde
/// cada `ProviderContainer` debe soltar sus recursos.
final httpClientProvider = Provider<http.Client>((ref) {
  throw UnimplementedError(
    'httpClientProvider debe sobreescribirse en bootstrap.',
  );
});

/// El cliente de la API. Éste SÍ se construye aquí: sólo compone lo anterior, sin
/// inicialización propia que `bootstrap` deba resolver.
final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    config: ref.watch(apiConfigProvider),
    cliente: ref.watch(httpClientProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);
