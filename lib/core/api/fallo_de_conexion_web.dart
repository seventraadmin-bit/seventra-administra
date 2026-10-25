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
// DECISIÓN REGISTRADA, NO PENDIENTE: no se afina mirando el mensaje. Se podría
// —`BrowserClient` dice «XMLHttpRequest error»— y no se hace, porque sería depender
// de una cadena de texto del paquete, que cambia sin avisar y sin romper nada
// visible. Si algún día un caso real lo exige, deja de ser esta decisión y pasa a
// ser una deuda con número.

/// ¿Es un fallo de conexión de red? En web no se puede saber por tipo.
bool esFalloDeConexion(Object error) => false;

/// ¿Es un fallo al establecer la conexión segura? Tampoco.
bool esFalloDeTls(Object error) => false;
