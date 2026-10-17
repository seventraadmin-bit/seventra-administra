import 'dart:io';

// Los dos fallos de red que sólo existen en escritorio, detrás de una función para
// que `api_client` no tenga que importar `dart:io` — y pueda compilar para web.
//
// SE MIDIÓ EN EL PAQUETE, NO SE SUPUSO. Las dos preguntas no son simétricas:
//
//   · `SocketException` llega ENVUELTA. `IOClient.send` la atrapa y lanza una
//     `ClientException` que además `implements SocketException`, y el paquete
//     documenta que lo hace «para no romper a los usuarios de `IOClient` que puedan
//     atrapar esa excepción». Por eso se pregunta por el tipo: el objeto es las dos
//     cosas a la vez, y por eso quitar la rama NO era inocuo.
//
//   · `HandshakeException` llega CRUDA. `IOClient.send` sólo atrapa
//     `SocketException` y `HttpException`, así que un fallo de TLS sube sin tocar.

/// ¿Es un fallo de conexión de red?
bool esFalloDeConexion(Object error) => error is SocketException;

/// ¿Es un fallo al establecer la conexión segura?
bool esFalloDeTls(Object error) => error is HandshakeException;
