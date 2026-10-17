// La contraparte para el navegador. Las dos devuelven `false`, y es una DECISIÓN,
// no una omisión.
//
// En web no existen `SocketException` ni `HandshakeException` —vienen de `dart:io`,
// que el navegador no tiene—, así que no hay forma de distinguir POR TIPO un fallo
// de conexión, uno de TLS y una respuesta truncada: `BrowserClient` lanza
// `ClientException` para todos.
//
// Se devuelve `false` para no afirmar un diagnóstico que no se puede hacer. La
// consecuencia es que en web un fallo de red se reporta como «transporte
// interrumpido» en vez de «no se pudo conectar».
//
// ⏳ SE PODRÍA AFINAR mirando el mensaje —`BrowserClient` dice «XMLHttpRequest
// error»— pero eso es depender de una cadena de texto del paquete, que cambia sin
// avisar y sin romper nada visible. Cuando la app web esté en uso real y el mensaje
// importe, se decide con el caso enfrente.

/// ¿Es un fallo de conexión de red? En web no se puede saber por tipo.
bool esFalloDeConexion(Object error) => false;

/// ¿Es un fallo al establecer la conexión segura? Tampoco.
bool esFalloDeTls(Object error) => false;
