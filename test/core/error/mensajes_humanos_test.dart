// El traductor de fallos del portón web: `Failure` → una frase que se puede usar.
//
// POR QUÉ ESTO SE PRUEBA Y NO SE DA POR BUENO. El requisito era «mensajes sin
// lenguaje técnico», y eso es exactamente la clase de regla que se cumple el día que
// se escribe y se rompe tres etapas después: basta un `return fallo.message` «para no
// perder información» y la pantalla empieza a decir «La respuesta de autenticación no
// trae: accessToken».
//
// Así que la prueba central NO COMPARA CONTRA UNA LISTA DE FRASES ESPERADAS —eso sólo
// congelaría la redacción y obligaría a tocar la prueba en cada ajuste de estilo—,
// sino que afirma una PROPIEDAD: ningún mensaje contiene vocabulario técnico. Es la
// misma regla que el backend aprendió a golpes nueve veces: se acota la propiedad, no
// se fija la lista.

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/mensajes_humanos.dart';

/// Lo que un mensaje de esta pantalla NO puede contener.
///
/// Son dos familias: **vocabulario de programación** —que no significa nada para
/// quien lo lee— y **números de estado HTTP**, que suenan a avería del sistema y no
/// dicen qué hacer.
const _vocabularioTecnico = <String>[
  'null',
  'Failure',
  'Exception',
  'HTTP',
  'http',
  'JSON',
  'json',
  'token',
  'Token',
  'statusCode',
  'ApiClient',
  'accessToken',
  'refreshToken',
  'Authorization',
  'endpoint',
  'request',
  'response',
  'CORS',
  'localhost',
  'uuid',
  'companyId',
  '401',
  '402',
  '403',
  '404',
  '409',
  '423',
  '429',
  '500',
];

/// Todos los fallos que las tres traducciones pueden recibir de verdad.
///
/// La lista cubre **las dos ramas de cada método** —respuesta del servidor y fallo de
/// transporte— y los códigos que el backend emite de verdad, leídos de
/// `AuthEndpoints.cs`: `credenciales_invalidas`, `cuenta_bloqueada`,
/// `email_no_verificado` y `cuenta_suspendida`.
final _todosLosFallos = <Failure>[
  // --- Lo que responde /auth/login ---
  const ApiHttpFailure(
    statusCode: 401,
    codigo: 'credenciales_invalidas',
    message: 'Correo o contraseña incorrectos.',
  ),
  const ApiHttpFailure(
    statusCode: 423,
    codigo: 'cuenta_bloqueada',
    message: 'Demasiados intentos fallidos. Inténtalo más tarde.',
  ),
  const ApiHttpFailure(
    statusCode: 403,
    codigo: 'email_no_verificado',
    message: 'Verifica tu correo antes de iniciar sesión.',
  ),
  const ApiHttpFailure(
    statusCode: 403,
    codigo: 'cuenta_suspendida',
    message: 'Esta cuenta está suspendida.',
  ),
  const ApiHttpFailure(statusCode: 429, message: 'Too Many Requests'),

  // --- Lo que responde la capa de empresa ---
  const ApiHttpFailure(
    statusCode: 402,
    codigo: 'subscription_restricted',
    message: 'La suscripción está restringida.',
  ),
  const ApiHttpFailure(
    statusCode: 403,
    codigo: 'module_disabled',
    message: 'El módulo está apagado.',
  ),
  const ApiHttpFailure(
    statusCode: 403,
    codigo: 'permission_missing',
    message: 'Falta el permiso areas.read.',
  ),
  const ApiHttpFailure(
    statusCode: 404,
    codigo: 'empresa_no_disponible',
    message: 'La empresa no está disponible.',
  ),
  const ApiHttpFailure(statusCode: 500, message: 'Internal Server Error'),

  // --- Un 4xx que nadie previó, que es el caso que de verdad arrastra texto ajeno ---
  const ApiHttpFailure(
    statusCode: 418,
    codigo: 'quien_sabe',
    message: 'Unexpected JSON token at offset 42 in response body',
  ),

  // --- Transporte ---
  const ApiSinConexionFailure('La conexión con el servidor se interrumpió.'),
  const ApiTimeoutFailure('El servidor tardó demasiado en responder.'),
  const ApiConfigFailure(
    'Falta la dirección del servidor. Compila con '
    '--dart-define=SEVENTRA_API_BASE_URL=https://tu-servidor',
  ),
  const ApiJsonInvalidoFailure('El cuerpo no es JSON válido.'),
  const ApiRespuestaInesperadaFailure(
    'La respuesta de autenticación no trae: accessToken, sessionId.',
  ),
  const ApiSinSesionFailure('No hay una sesión remota abierta.'),
];

void main() {
  /// Las tres traducciones, con nombre, para poder señalar la culpable.
  final traductores = <String, String Function(Failure)>{
    'deLogin': MensajesHumanos.deLogin,
    'deEmpresa': MensajesHumanos.deEmpresa,
    'deSesion': MensajesHumanos.deSesion,
    'deArranque': MensajesHumanos.deArranque,
  };

  group('Ningún mensaje lleva lenguaje técnico', () {
    test('en ninguna de las cuatro traducciones, con ningún fallo', () {
      final infractores = <String>[];

      for (final entrada in traductores.entries) {
        for (final fallo in _todosLosFallos) {
          final mensaje = entrada.value(fallo);

          for (final palabra in _vocabularioTecnico) {
            if (mensaje.contains(palabra)) {
              infractores.add(
                '${entrada.key}(${fallo.runtimeType}) → «$palabra» en: $mensaje',
              );
            }
          }
        }
      }

      expect(
        infractores,
        isEmpty,
        reason:
            'Estos mensajes llegarían a la pantalla con vocabulario que quien los '
            'lee no puede usar:\n${infractores.join('\n')}',
      );
    });

    test('y ninguno sale vacío ni se queda en una palabra', () {
      // Un mensaje vacío deja un hueco en la pantalla donde debería estar la
      // explicación, y es un fallo que pasa desapercibido porque nada lanza.
      for (final entrada in traductores.entries) {
        for (final fallo in _todosLosFallos) {
          final mensaje = entrada.value(fallo);

          expect(
            mensaje.trim().length,
            greaterThan(12),
            reason: '${entrada.key}(${fallo.runtimeType}) devolvió «$mensaje»',
          );
          expect(
            mensaje.trim(),
            endsWith('.'),
            reason:
                '${entrada.key}(${fallo.runtimeType}) no termina en punto: es una '
                'frase para una persona, no una etiqueta',
          );
        }
      }
    });
  });

  group('Los desenlaces del login NO se colapsan', () {
    // SE PRUEBA QUE SON DISTINTOS, no cuál es cada uno. Lo que importa es que los
    // cuatro pidan acciones distintas: escribir otra vez la contraseña, esperar,
    // buscar un correo o hablar con alguien. Un «no se pudo entrar» para los cuatro
    // deja a quien lo lee sin saber qué hacer, y pasaría cualquier prueba que sólo
    // comprobara que hay mensaje.
    test('los cuatro códigos del backend dan cuatro mensajes diferentes', () {
      final mensajes = {
        for (final codigo in [
          'credenciales_invalidas',
          'cuenta_bloqueada',
          'email_no_verificado',
          'cuenta_suspendida',
        ])
          codigo: MensajesHumanos.deLogin(
            ApiHttpFailure(
              statusCode: 401,
              codigo: codigo,
              message: 'lo que diga el servidor',
            ),
          ),
      };

      expect(
        mensajes.values.toSet(),
        hasLength(4),
        reason: 'Dos códigos distintos comparten mensaje: $mensajes',
      );
    });

    test('NO se insinúa si el correo tiene cuenta', () {
      // El backend responde lo MISMO para una contraseña equivocada y para una
      // cuenta que no existe, a propósito: no ser el oráculo con el que se averigua
      // quién tiene cuenta. Separarlos aquí tiraría esa defensa desde el cliente.
      final mensaje = MensajesHumanos.deLogin(
        const ApiHttpFailure(
          statusCode: 401,
          codigo: 'credenciales_invalidas',
          message: 'Correo o contraseña incorrectos.',
        ),
      ).toLowerCase();

      for (final insinuacion in [
        'no existe',
        'no está registrado',
        'no esta registrado',
        'no encontramos',
        'no hay ninguna cuenta',
        'esa cuenta no',
      ]) {
        expect(
          mensaje,
          isNot(contains(insinuacion)),
          reason: 'El mensaje insinúa si el correo tiene cuenta: «$mensaje»',
        );
      }
    });
  });

  group('El 402 no se presenta como un error de quien entra', () {
    test('dice que se puede consultar, y no culpa a nadie', () {
      final mensaje = MensajesHumanos.deEmpresa(
        const ApiHttpFailure(
          statusCode: 402,
          codigo: 'subscription_restricted',
          message: 'restringida',
        ),
      ).toLowerCase();

      // `restricted` es SÓLO LECTURA: leer sigue permitido, y el mensaje tiene que
      // decirlo. Si sonara a bloqueo total, quien lo lea no intentará consultar lo
      // que sí puede ver.
      expect(mensaje, contains('consultar'));

      for (final culpa in ['no tienes permiso', 'no puedes entrar', 'error']) {
        expect(
          mensaje,
          isNot(contains(culpa)),
          reason:
              'Una suscripción limitada no es un problema de permisos ni un error '
              'de quien entra: «$mensaje»',
        );
      }
    });
  });

  group('Un fallo de red NO se reenvía con el texto del cliente', () {
    test('en web «se interrumpió» sería falso, y no se dice', () {
      // EL CASO QUE YA COSTÓ MEDIA HORA. En el navegador, un origen que la API no
      // autoriza y un servidor apagado llegan idénticos; `ApiClient` los traduce al
      // mismo `ApiSinConexionFailure`, pero con el texto «la conexión con el
      // servidor se interrumpió», que sugiere que empezó.
      //
      // Lo único cierto en los dos casos es que no se pudo contactar, y es lo que
      // esta prueba exige que se diga.
      final mensaje = MensajesHumanos.deSesion(
        const ApiSinConexionFailure('La conexión con el servidor se interrumpió.'),
      ).toLowerCase();

      expect(mensaje, contains('no se pudo contactar'));
      expect(
        mensaje,
        isNot(contains('interrump')),
        reason: 'Se reenvió el texto del fallo en vez de traducirlo',
      );
    });

    test('«no se pudo comprobar» no es «tu sesión expiró»', () {
      // La credencial sigue siendo buena y el gestor NO la borró: lo que no se pudo
      // es preguntar. Decir que expiró mandaría a volver a entrar cuando basta
      // reintentar, y además es mentira.
      final mensaje = MensajesHumanos.deSesion(
        const ApiTimeoutFailure('tardó demasiado'),
      ).toLowerCase();

      for (final mentira in ['expiró', 'expiro', 'caducó', 'caduco']) {
        expect(mensaje, isNot(contains(mentira)));
      }
    });
  });

  group('deSesion NO hereda los casos de empresa', () {
    test('un 404 de un proxy no dice que la empresa no esté disponible', () {
      // ESTE ES EL DEFECTO QUE SEPARÓ LOS DOS MÉTODOS. `deSesion` usaba `deEmpresa`,
      // y ante un 404 —que un proxy puede devolver sin que ninguna empresa tenga
      // nada que ver— respondía «esta empresa ya no está disponible para ti»:
      // manda a buscar un problema de permisos donde hay uno de red.
      final mensaje = MensajesHumanos.deSesion(
        const ApiHttpFailure(statusCode: 404, message: 'Not Found'),
      ).toLowerCase();

      expect(mensaje, isNot(contains('empresa')));
    });
  });
}
