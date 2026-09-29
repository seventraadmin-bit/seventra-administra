import '../api/api_client.dart';
import '../api/api_error_parser.dart';
import '../api/api_respuesta.dart';
import '../error/failure.dart';
import '../error/result.dart';

/// Lo que devuelve `/auth/login` y `/auth/refresh`: la respuesta del backend, ya
/// leída, sin decidir nada con ella.
///
/// Es el ÚNICO sitio del cliente donde los dos tokens conviven en un mismo
/// objeto, y vive lo que dura una llamada: [GestorDeSesion] los separa en cuanto
/// los recibe —el de acceso a memoria, el de refresco al almacén seguro— y este
/// objeto se descarta.
final class TokensDeSesion {
  const TokensDeSesion({
    required this.accessToken,
    required this.accessExpiresAt,
    required this.refreshToken,
    required this.refreshExpiresAt,
    required this.identityId,
    required this.sessionId,
    this.displayName,
    this.email,
  });

  final String accessToken;

  /// En UTC. El backend lo escribe como `DateTimeOffset`; normalizarlo aquí
  /// evita que la ventana de refresco preventivo mida distinto según el
  /// desplazamiento con que llegó.
  final DateTime accessExpiresAt;

  final String refreshToken;
  final DateTime refreshExpiresAt;

  /// La Identity. **Obligatorio también en el refresco**, a diferencia de
  /// [displayName] y [email]: es lo único que permite saber de quién es la sesión
  /// que se acaba de restaurar.
  final String identityId;

  final String sessionId;

  /// `null` en un refresco: el backend responde `SessionResponse.From(tokens,
  /// account: null)` y no reenvía la identidad. Quien lo consuma tiene que
  /// CONSERVAR lo que ya sabía en vez de sobrescribirlo con nulo.
  final String? displayName;

  /// `null` en un refresco, por la misma razón que [displayName].
  final String? email;

  /// **Sin los tokens.** Este objeto puede acabar en un mensaje de excepción o en
  /// un volcado de diagnóstico, y ahí no puede ir una credencial.
  @override
  String toString() =>
      'TokensDeSesion($sessionId, acceso expira: '
      '${accessExpiresAt.toIso8601String()})';
}

/// Las tres llamadas de autenticación del backend SaaS, y ninguna más.
///
/// USA EL CLIENTE DESNUDO —[ApiClient], no el decorador autenticado— y tiene que
/// ser así: el decorador pide un token a [GestorDeSesion], el gestor llama a
/// `refrescar`, y si eso pasara por el decorador la primera llamada se llamaría a
/// sí misma. La frontera es tajante: **el grupo `/auth` es lo único que se llama
/// sin `Authorization`** (salvo `logout`, que lo lleva porque identifica qué
/// sesión cerrar).
///
/// NO IMPLEMENTA `register`, `verify-email`, `forgot-password` ni
/// `reset-password`. Existen en el backend, pero alta de cuentas y recuperación
/// de contraseña son flujos con correo de por medio: pertenecen al portal web,
/// no a una aplicación de escritorio instalada en la caseta de un servicio.
///
/// LA COOKIE SE IGNORA POR COMPLETO. El backend escribe `Set-Cookie` con el token
/// de refresco para su cliente web; `package:http` no gestiona cookies
/// —verificado: ni `io_client.dart` ni `base_client.dart` las mencionan—, así que
/// aquí no se guarda ni se reenvía ninguna. El token de refresco viaja en el
/// CUERPO, que el backend acepta como camino de primera clase
/// (`http.Request.Cookies[...] ?? request?.RefreshToken`). Por eso IF-2 no
/// necesita ni un cambio en el servidor, y por eso **no se debilita `HttpOnly`,
/// `Secure` ni `SameSite`** para facilitarle la vida al escritorio.
class AuthApi {
  const AuthApi(this._cliente);

  final ApiClient _cliente;

  static const String rutaLogin = '/auth/login';
  static const String rutaRefresco = '/auth/refresh';
  static const String rutaCierre = '/auth/logout';
  static const String rutaOlvideContrasena = '/auth/forgot-password';

  /// Treinta segundos, más que el plazo general de veinte.
  ///
  /// No es holgura arbitraria: el backend verifica la contraseña con un hash
  /// deliberadamente costoso, y ese costo es una defensa, no un defecto. Un
  /// plazo de veinte segundos podría cortar un login legítimo en una máquina
  /// cargada y el usuario lo leería como «no funciona».
  static const Duration timeoutDeLogin = Duration(seconds: 30);

  /// Correo y contraseña. La contraseña **sólo pasa por aquí**: no se guarda, no
  /// se registra y no se conserva en ningún campo después de esta llamada.
  Future<Result<TokensDeSesion>> iniciarSesion({
    required String email,
    required String password,
  }) async {
    final respuesta = await _cliente.post(
      rutaLogin,
      json: {'email': email, 'password': password},
      timeout: timeoutDeLogin,
    );

    return _leerSesion(respuesta);
  }

  /// Pide al backend que mande el correo de restablecimiento.
  ///
  /// **NO reconstruye la recuperación aquí**: el ciclo entero —correo real por
  /// Resend, enlace, página web, token de un solo uso— ya existe y está probado.
  /// Esto es únicamente el disparador, para que quien no recuerda su contraseña
  /// no tenga que salir de la aplicación a buscarlo.
  ///
  /// El backend responde **202 siempre**, exista o no la cuenta, así que aquí no
  /// hay nada que distinguir: decirle a quien pregunta si ese correo tiene cuenta
  /// convertiría esta pantalla en el oráculo que el servidor evita.
  Future<Result<void>> solicitarRestablecimiento({required String email}) async {
    final respuesta = await _cliente.post(
      rutaOlvideContrasena,
      json: {'email': email},
      timeout: timeoutDeLogin,
    );

    return switch (respuesta) {
      Ok() => const Result.ok(null),
      Err(:final failure) => Result.failure(failure),
    };
  }

  /// Canjea el token de refresco por uno nuevo. **Rotación estricta**: el que se
  /// envía queda inservible en el servidor en cuanto éste responde.
  ///
  /// Un 401 aquí no es un tropiezo recuperable. Llega con `refresh_invalido`
  /// —caducó o no existe— o con `refresh_reutilizado`, y el segundo significa que
  /// el backend detectó un canje repetido y **revocó la sesión completa**. Por eso
  /// este método nunca debe llamarse en paralelo consigo mismo, y de eso se
  /// encarga el «single-flight» de [GestorDeSesion].
  Future<Result<TokensDeSesion>> refrescar({
    required String refreshToken,
  }) async {
    final respuesta = await _cliente.post(
      rutaRefresco,
      json: {'refreshToken': refreshToken},
    );

    return _leerSesion(respuesta);
  }

  /// Revoca la sesión en el servidor. El backend responde **204 siempre**, exista
  /// o no la sesión, así que no hay forma —ni falta— de distinguir «se cerró» de
  /// «ya estaba cerrada».
  Future<Result<void>> cerrarSesion({required String accessToken}) async {
    final respuesta = await _cliente.post(
      rutaCierre,
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    switch (respuesta) {
      case Err<ApiRespuesta>(:final failure):
        return Result.failure(failure);
      case Ok<ApiRespuesta>(:final value):
        return value.esExitosa
            ? const Result<void>.ok(null)
            : Result.failure(ApiErrorParser.interpretar(value));
    }
  }

  // -------------------------------------------------------------------------

  /// Convierte la respuesta de `/login` o `/refresh` en tokens, o en un fallo.
  ///
  /// Una respuesta no exitosa se traduce con [ApiErrorParser], que conserva el
  /// `code` del backend: `credenciales_invalidas`, `cuenta_bloqueada` (423),
  /// `email_no_verificado`, `cuenta_suspendida`, `refresh_reutilizado`. Quien
  /// llame necesita distinguirlos —«te equivocaste de contraseña» y «tu cuenta
  /// está bloqueada quince minutos» no se arreglan igual—, así que no se
  /// colapsan en un mensaje.
  static Result<TokensDeSesion> _leerSesion(Result<ApiRespuesta> respuesta) {
    switch (respuesta) {
      case Err<ApiRespuesta>(:final failure):
        return Result.failure(failure);

      case Ok<ApiRespuesta>(:final value):
        if (!value.esExitosa) {
          return Result.failure(ApiErrorParser.interpretar(value));
        }

        return value.comoObjeto().when(
          ok: _tokensDesdeObjeto,
          failure: Result.failure,
        );
    }
  }

  /// Lee los campos exigiendo lo que de verdad hace falta.
  ///
  /// **Falta un campo obligatorio, es un desacuerdo de contrato, no un dato
  /// opcional.** Una sesión sin caducidad de acceso no se puede refrescar a
  /// tiempo, y una sin token de refresco no sobrevive al primer cierre: dar
  /// cualquiera de las dos por buena produciría una sesión que falla más tarde,
  /// lejos de su causa.
  static Result<TokensDeSesion> _tokensDesdeObjeto(Map<String, Object?> json) {
    final accessToken = _texto(json['accessToken']);
    final refreshToken = _texto(json['refreshToken']);
    final identityId = _texto(json['identityId']);
    final sessionId = _texto(json['sessionId']);
    final accessExpiresAt = _instante(json['accessExpiresAt']);
    final refreshExpiresAt = _instante(json['refreshExpiresAt']);

    final faltantes = <String>[
      if (accessToken == null) 'accessToken',
      if (refreshToken == null) 'refreshToken',
      // Obligatorio, no opcional: una sesión sin identidad deja a la aplicación
      // autenticada sin saber como quién, y el actor de toda la auditoría local
      // sale de aquí. Aceptarla produciría el fallo lejos de su causa.
      if (identityId == null) 'identityId',
      if (sessionId == null) 'sessionId',
      if (accessExpiresAt == null) 'accessExpiresAt',
      if (refreshExpiresAt == null) 'refreshExpiresAt',
    ];

    if (faltantes.isNotEmpty) {
      // Se nombran los campos, nunca los valores: el cuerpo lleva dos tokens.
      return Result.failure(
        ApiRespuestaInesperadaFailure(
          'La respuesta de autenticación no trae: ${faltantes.join(', ')}.',
        ),
      );
    }

    return Result.ok(
      TokensDeSesion(
        accessToken: accessToken!,
        accessExpiresAt: accessExpiresAt!,
        refreshToken: refreshToken!,
        refreshExpiresAt: refreshExpiresAt!,
        identityId: identityId!,
        sessionId: sessionId!,
        displayName: _texto(json['displayName']),
        email: _texto(json['email']),
      ),
    );
  }

  static String? _texto(Object? valor) {
    if (valor is! String) return null;

    final limpio = valor.trim();
    return limpio.isEmpty ? null : limpio;
  }

  /// Un instante, normalizado a UTC. Devuelve `null` —y no lanza— si el texto no
  /// es una fecha: aquí un formato imprevisto es un campo ausente, y la lista de
  /// faltantes ya lo reporta con nombre.
  static DateTime? _instante(Object? valor) {
    if (valor is! String) return null;

    return DateTime.tryParse(valor)?.toUtc();
  }
}
