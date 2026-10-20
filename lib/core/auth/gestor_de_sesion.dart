import 'dart:async';

import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, visibleForTesting;

import '../error/failure.dart';
import '../error/result.dart';
import '../logging/app_logger.dart';
import 'almacen_sesion_remota.dart';
import 'auth_api.dart';
import 'sesion_remota.dart';

/// El motor de la sesión remota: entra, se mantiene viva, se restaura y se
/// cierra. **Es la única pieza del cliente que conoce los dos tokens.**
///
/// DÓNDE VIVE CADA SECRETO, que es la decisión de la que cuelga todo lo demás:
///
///  · el **token de acceso** sólo en memoria, en un campo privado de esta clase.
///    Dura treinta minutos; persistirlo dejaría en disco un secreto que no hace
///    falta guardar.
///  · el **token de refresco** sólo en el almacén de credenciales del sistema.
///    Dura catorce días y con él se emiten accesos nuevos, así que es el que de
///    verdad hay que cuidar.
///  · la **contraseña**, en ningún sitio. Pasa por `iniciarSesion`, viaja al
///    servidor y se olvida: no hay campo, no hay caché y no hay «reintentar con
///    las credenciales guardadas».
///
/// EL «SINGLE-FLIGHT» NO ES UNA OPTIMIZACIÓN, ES CORRECCIÓN. El backend rota el
/// token de refresco en cada canje y **detecta la reutilización revocando la
/// sesión entera**. Si diez peticiones en paralelo descubrieran a la vez que el
/// acceso caducó y cada una pidiera un refresco, nueve enviarían un token ya
/// canjeado y el servidor las expulsaría a todas — con el usuario mirando. Por eso
/// hay un solo refresco en vuelo y todas esperan el mismo `Future`.
///
/// LA GENERACIÓN protege el otro lado del mismo problema: un refresco que llega
/// DESPUÉS de cerrar sesión traería un token válido para una sesión que el usuario
/// ya cerró. Guardarlo la resucitaría en el siguiente arranque. Cada refresco
/// anota la generación con la que empezó y, si al volver no coincide, su resultado
/// se tira sin escribir nada.
class GestorDeSesion {
  GestorDeSesion({
    required AuthApi api,
    required AlmacenSesionRemota almacen,
    required AppLogger logger,
    DateTime Function()? ahora,
  }) : _api = api,
       _almacen = almacen,
       _logger = logger,
       _ahora = ahora ?? _ahoraReal;

  static DateTime _ahoraReal() => DateTime.now().toUtc();

  /// Cuánto margen se exige al token de acceso antes de darlo por usable.
  ///
  /// Con más de un minuto por delante se usa el que hay; con menos se refresca
  /// ANTES de enviar la petición. La alternativa —esperar el 401 y reintentar—
  /// funciona, pero paga un viaje de ida y vuelta inútil en cada petición que cae
  /// justo en el borde, y deja al usuario esperando dos veces.
  ///
  /// El servidor sigue siendo la autoridad: esto sólo evita el caso previsible.
  /// Un token revocado antes de su caducidad se detecta igual, por el 401.
  static const Duration ventanaDeRefrescoPreventivo = Duration(seconds: 60);

  final AuthApi _api;
  final AlmacenSesionRemota _almacen;
  final AppLogger _logger;
  final DateTime Function() _ahora;

  final ValueNotifier<EstadoAutenticacion> _estado =
      ValueNotifier<EstadoAutenticacion>(const AutenticacionSinResolver());

  CredencialRemota? _credencial;
  String? _accessToken;
  DateTime? _accessExpiresAt;

  /// Cuántas veces ha cambiado la identidad de la sesión (login, cierre o
  /// invalidación). No es un contador de refrescos: rotar un token no cambia de
  /// sesión.
  int _generacion = 0;

  Future<Result<String>>? _refrescoEnVuelo;
  Future<EstadoAutenticacion>? _restauracionEnVuelo;
  bool _desechado = false;

  /// El aviso de cierre al backend, que se dispara sin esperarlo. Se expone para
  /// que una prueba pueda esperar algo determinista en vez de bombear el reloj.
  @visibleForTesting
  Future<void>? avisoDeCierreEnVuelo;

  /// El estado, para observarlo. Se usa un `ValueListenable` y no un `Stream`
  /// porque tiene valor actual: quien empieza a escuchar sabe en qué situación
  /// está sin esperar el siguiente evento, y no hay ninguna ventana en la que un
  /// cambio se pueda perder entre leer y suscribirse.
  ValueListenable<EstadoAutenticacion> get estadoObservable => _estado;

  EstadoAutenticacion get estado => _estado.value;

  /// Si hay una credencial con la que se podría autenticar. **No** implica que el
  /// backend la haya confirmado.
  bool get hayCredencial => _credencial != null;

  // -------------------------------------------------------------------------
  // Entrar
  // -------------------------------------------------------------------------

  /// Inicia sesión con correo y contraseña.
  ///
  /// La contraseña no se conserva en ninguna parte después de esta llamada. Si
  /// falla, el estado **no cambia**: un intento fallido desde una sesión abierta
  /// no la cierra.
  Future<Result<SesionRemota>> iniciarSesion({
    required String email,
    required String password,
  }) async {
    final resultado = await _api.iniciarSesion(
      email: email,
      password: password,
    );

    switch (resultado) {
      case Err<TokensDeSesion>(:final failure):
        return Result.failure(failure);

      case Ok<TokensDeSesion>(:final value):
        // La generación cambia ANTES de adoptar la sesión nueva: si había un
        // refresco de la anterior en vuelo, su resultado queda huérfano y no
        // podrá sobrescribir lo que se guarda a continuación.
        _invalidarGeneracion();

        final credencial = CredencialRemota(
          refreshToken: value.refreshToken,
          refreshExpiresAt: value.refreshExpiresAt,
          identityId: value.identityId,
          sessionId: value.sessionId,
          // El correo con el que se entró es el que vale si el backend no lo
          // reenvía; nunca se inventa otro.
          email: value.email ?? email,
          displayName: value.displayName,
        );

        await _guardar(credencial);

        _credencial = credencial;
        _accessToken = value.accessToken;
        _accessExpiresAt = value.accessExpiresAt;
        _publicar(Autenticado(credencial.sesion));

        _logger.info(
          'Sesión remota iniciada — sesión: ${credencial.sessionId}',
        );

        return Result.ok(credencial.sesion);
    }
  }

  /// Intenta recuperar la sesión guardada en el equipo y devuelve el estado
  /// resultante.
  ///
  /// CONFIRMA CONTRA EL SERVIDOR en vez de creerse el disco: una credencial
  /// guardada puede haber sido revocada —contraseña restablecida, cuenta
  /// suspendida, canje repetido detectado— y publicar [Autenticado] sin
  /// preguntar haría que la aplicación se comportara como si hubiera sesión hasta
  /// la primera petición real.
  ///
  /// EN IF-2 ESTO NO GOBIERNA EL ARRANQUE. No lo llama `bootstrap` ni el router:
  /// el portón del producto sigue siendo la sesión local, y un fallo aquí no
  /// puede impedir entrar. Se invoca desde quien decida usar la capa SaaS, y será
  /// el relevo del portón —cuando ocurra— el que lo mueva al arranque.
  ///
  /// **También es «single-flight»**, por la misma razón que el refresco: dos
  /// restauraciones simultáneas leerían el mismo token del disco y lo canjearían
  /// dos veces, y el backend lee eso como reutilización y revoca la sesión. Basta
  /// que dos pantallas del futuro portón pidan restaurar a la vez.
  Future<EstadoAutenticacion> restaurar() {
    final enVuelo = _restauracionEnVuelo;
    if (enVuelo != null) return enVuelo;

    final futuro = _restaurar();
    _restauracionEnVuelo = futuro;

    futuro.whenComplete(() {
      if (identical(_restauracionEnVuelo, futuro)) _restauracionEnVuelo = null;
    });

    return futuro;
  }

  Future<EstadoAutenticacion> _restaurar() async {
    final guardada = await _leerCredencial();

    if (guardada == null) {
      _olvidar();
      _publicar(const NoAutenticado());
      return estado;
    }

    if (guardada.haCaducado(_ahora())) {
      // Catorce días sin abrir la aplicación. Pedir un refresco con esto sólo
      // puede terminar en 401, así que se ahorra el viaje y se limpia el rastro.
      _logger.info('La credencial remota guardada caducó; se descarta.');
      await _borrarCredencial();
      _olvidar();
      _publicar(const NoAutenticado());
      return estado;
    }

    _invalidarGeneracion();
    _credencial = guardada;

    // El refresco publica el estado que corresponda: `Autenticado` si el
    // servidor confirma, `NoAutenticado` si lo rechaza, `SesionRemotaSinConfirmar`
    // si no se pudo preguntar.
    await _refrescar();

    return estado;
  }

  // -------------------------------------------------------------------------
  // Mantenerse viva
  // -------------------------------------------------------------------------

  /// Un token de acceso con el que firmar la siguiente petición, refrescando
  /// antes si está por caducar.
  Future<Result<String>> tokenDeAccesoVigente() {
    if (_credencial == null) return _sinSesion();

    final token = _accessToken;
    final expira = _accessExpiresAt;

    if (token != null &&
        expira != null &&
        expira.difference(_ahora()) > ventanaDeRefrescoPreventivo) {
      return Future<Result<String>>.value(Result.ok(token));
    }

    return _refrescar();
  }

  /// El backend rechazó [tokenRechazado] con un 401. Devuelve el token con el que
  /// merece la pena reintentar.
  ///
  /// EL CASO QUE ESTO RESUELVE: diez peticiones en paralelo firmadas con el mismo
  /// token reciben diez 401. La primera refresca; cuando las otras nueve llegan
  /// aquí, el token vigente ya es otro y se les entrega **sin pedir un refresco
  /// más** — que es lo que el backend interpretaría como reutilización.
  Future<Result<String>> renovarTrasRechazo(String tokenRechazado) {
    if (_credencial == null) return _sinSesion();

    final vigente = _accessToken;
    if (vigente != null && vigente != tokenRechazado) {
      return Future<Result<String>>.value(Result.ok(vigente));
    }

    return _refrescar();
  }

  /// El «single-flight». Un refresco en vuelo como máximo; el resto de las
  /// llamadas esperan exactamente el mismo `Future`.
  Future<Result<String>> _refrescar() {
    final enVuelo = _refrescoEnVuelo;
    if (enVuelo != null) return enVuelo;

    final futuro = _ejecutarRefresco();
    _refrescoEnVuelo = futuro;

    // La limpieza se registra ANTES de devolver, así que corre antes de que
    // despierte cualquiera que esté esperando: nadie observa un `_refrescoEnVuelo`
    // ya completado. El `identical` evita que un refresco viejo borre el apunte
    // de uno nuevo si la generación cambió entre medias.
    futuro.whenComplete(() {
      if (identical(_refrescoEnVuelo, futuro)) _refrescoEnVuelo = null;
    });

    return futuro;
  }

  Future<Result<String>> _ejecutarRefresco() async {
    final enMemoria = _credencial;
    if (enMemoria == null) {
      return const Result.failure(
        ApiSinSesionFailure('No hay una sesión remota abierta.'),
      );
    }

    // LA GENERACIÓN SE CAPTURA ANTES DE LEER EL ALMACÉN, no sólo antes de la
    // petición: la lectura es asíncrona, así que entre ella y aquí cabe un cierre
    // de sesión. Capturarla después dejaría pasar ese hueco.
    final generacion = _generacion;

    // SE REFRESCA CON LA CREDENCIAL DEL ALMACÉN, NO CON LA DE MEMORIA. Ver
    // [_credencialParaRefrescar]: es lo que impide que dos pestañas se tumben la
    // sesión mutuamente.
    final credencial = await _credencialParaRefrescar(enMemoria);

    if (generacion != _generacion) {
      _logger.warning(
        'Refresco descartado: la sesión cambió mientras se leía el almacén.',
      );

      return const Result.failure(
        ApiSinSesionFailure('La sesión se cerró durante el refresco.'),
      );
    }

    final resultado = await _api.refrescar(
      refreshToken: credencial.refreshToken,
    );

    if (generacion != _generacion) {
      // Se cerró sesión —o se abrió otra— mientras el refresco viajaba. El token
      // rotado que acaba de llegar pertenece a una sesión que aquí ya no existe:
      // no se guarda y no se publica. Escribirlo resucitaría lo que el usuario
      // cerró, y en el siguiente arranque volvería a entrar solo.
      _logger.warning(
        'Refresco descartado: la sesión cambió mientras la respuesta viajaba.',
      );

      return const Result.failure(
        ApiSinSesionFailure('La sesión se cerró durante el refresco.'),
      );
    }

    switch (resultado) {
      case Ok<TokensDeSesion>(:final value):
        final rotada = credencial.copyWith(
          refreshToken: value.refreshToken,
          refreshExpiresAt: value.refreshExpiresAt,
          // El refresco no reenvía la identidad: `copyWith` conserva la que ya
          // había en vez de borrarla con el nulo que llega.
          displayName: value.displayName,
        );

        // SE PERSISTE ANTES DE DEVOLVER, y por tanto antes de que despierte
        // ningún waiter: el servidor ya invalidó el token anterior, así que desde
        // este instante el único que sirve es el nuevo. Lo que jamás puede
        // ocurrir es que el disco conserve el viejo mientras la memoria usa el
        // nuevo — un arranque posterior lo canjearía, el backend lo leería como
        // reutilización y revocaría la sesión completa.
        await _guardar(rotada);

        _credencial = rotada;
        _accessToken = value.accessToken;
        _accessExpiresAt = value.accessExpiresAt;
        _publicar(Autenticado(rotada.sesion));

        return Result.ok(value.accessToken);

      case Err<TokensDeSesion>(:final failure):
        if (_esRechazoDefinitivo(failure)) {
          // 401. Llega con `refresh_invalido` —caducó o no existe— o con
          // `refresh_reutilizado`, y en el segundo caso el backend ya revocó la
          // sesión entera. En los dos, aquí no queda nada que salvar.
          _logger.warning(
            'El backend rechazó el token de refresco; la sesión remota se cierra.',
          );

          await _borrarCredencial();
          _olvidar();
          _publicar(const NoAutenticado());
        } else if (_estado.value is! Autenticado) {
          // Sin red, tiempo agotado o 5xx: la credencial puede seguir siendo
          // buena y NO SE TOCA. Tirarla convertiría un bache de red en un cierre
          // de sesión, y encima nada volvería a intentarlo.
          _publicar(SesionRemotaSinConfirmar(failure));
        }

        return Result.failure(failure);
    }
  }

  /// Sólo un 401 cierra la sesión. Un 429 del limitador, un 502 de un proxy o un
  /// 500 del servidor no dicen nada sobre la validez del token.
  static bool _esRechazoDefinitivo(Failure failure) =>
      failure is ApiHttpFailure && failure.statusCode == 401;

  // -------------------------------------------------------------------------
  // Salir
  // -------------------------------------------------------------------------

  /// Cierra la sesión remota. **Siempre termina**, incluso con el backend caído.
  ///
  /// El orden es deliberado:
  ///
  ///  1. muere la generación, así que ningún refresco en vuelo puede volver a
  ///     escribir nada;
  ///  2. el estado pasa a [NoAutenticado] de inmediato, sin esperar a la red;
  ///  3. se borra el artefacto seguro, que es lo que impide volver mañana;
  ///  4. se avisa al backend **sin esperarlo**.
  ///
  /// El aviso va sin `await` a propósito. Un servidor inalcanzable no puede
  /// impedir cerrar sesión —esperar veinte segundos con la interfaz bloqueada
  /// sería peor que no avisar—, y bajo `flutter test` el canal del almacén de
  /// credenciales puede no responder nunca: es el mismo motivo por el que
  /// `SesionController.logout` del producto local también lo hace en segundo
  /// plano. **Sin cola de revocación**: el token de acceso caduca solo en treinta
  /// minutos y el de refresco ya no existe en este equipo.
  ///
  /// NO TOCA LA SESIÓN LOCAL. Cerrar la remota no cierra `SesionUsuario`: son dos
  /// infraestructuras separadas y en IF-2 la local es la que gobierna el acceso a
  /// los módulos.
  Future<void> cerrarSesion() async {
    final token = _accessToken;
    final sessionId = _credencial?.sessionId;

    _olvidar();
    _publicar(const NoAutenticado());

    await _borrarCredencial();

    if (token != null) {
      avisoDeCierreEnVuelo = _avisarCierre(token);
      unawaited(avisoDeCierreEnVuelo!);
    }

    if (sessionId != null) {
      _logger.info('Sesión remota cerrada — sesión: $sessionId');
    }
  }

  Future<void> _avisarCierre(String accessToken) async {
    final resultado = await _api.cerrarSesion(accessToken: accessToken);

    if (resultado.isFailure) {
      _logger.warning(
        'El backend no confirmó el cierre de sesión. La sesión de este equipo '
        'ya está cerrada; el token de acceso caducará por su cuenta.',
      );
    }
  }

  /// Suelta el estado observable. **Idempotente**: desechar dos veces un
  /// `ChangeNotifier` lanza, y este gestor puede ser desechado por el contenedor
  /// que lo aloja y por quien lo construyó a mano en una prueba.
  void dispose() {
    if (_desechado) return;

    _desechado = true;
    _estado.dispose();
  }

  // -------------------------------------------------------------------------

  Future<Result<String>> _sinSesion() => Future<Result<String>>.value(
    const Result.failure(
      ApiSinSesionFailure('No hay una sesión remota abierta.'),
    ),
  );

  /// Sube la generación y deja sin efecto lo que estuviera en vuelo.
  ///
  /// Limpiar el apunte del refresco es parte de la invalidación: si se dejara, una
  /// petición posterior se engancharía a un refresco que pertenece a la sesión
  /// anterior y que va a descartarse.
  void _invalidarGeneracion() {
    _generacion++;
    _refrescoEnVuelo = null;
    _accessToken = null;
    _accessExpiresAt = null;
  }

  /// Aquí no hay sesión. **Sube la generación**, y eso no es un detalle: sin ello,
  /// un refresco que estuviera viajando volvería, encontraría su misma generación
  /// y publicaría [Autenticado] justo después de que se decidiera que no hay nada.
  void _olvidar() {
    _invalidarGeneracion();
    _credencial = null;
  }

  /// Publica el estado, **salvo si ya se desechó el gestor**.
  ///
  /// Una petición o un refresco pueden estar viajando cuando el contenedor que
  /// aloja el gestor se destruye. Escribir en un `ValueNotifier` desechado lanza,
  /// y hacerlo desde una continuación asíncrona produce un error sin relación
  /// visible con su causa: es mucho mejor que el resultado tardío simplemente no
  /// se publique en un estado que ya nadie observa.
  void _publicar(EstadoAutenticacion nuevo) {
    if (_desechado) return;

    _estado.value = nuevo;
  }

  /// Las tres operaciones del almacén van envueltas porque son llamadas al
  /// sistema operativo, y ninguna de las tres debe poder tumbar la aplicación.
  ///
  /// No poder ESCRIBIR no invalida la sesión que acaba de emitirse: sigue siendo
  /// usable en esta ejecución, y lo que se pierde es poder restaurarla mañana.
  /// Convertirlo en fallo tiraría una sesión buena por un problema del almacén.
  Future<void> _guardar(CredencialRemota credencial) async {
    try {
      await _almacen.escribir(credencial);
    } catch (e) {
      _logger.error(
        'No se pudo guardar la credencial de la sesión remota. La sesión '
        'funciona en esta ejecución, pero no se podrá restaurar.',
        e,
      );
    }
  }

  /// Con qué credencial hay que refrescar: **la del almacén, no la de memoria**.
  ///
  /// ## El fallo que esto arregla, que el código ya nombraba al revés
  ///
  /// Más arriba, al persistir la credencial rotada, está escrito que «lo que jamás
  /// puede ocurrir es que el disco conserve el viejo mientras la memoria usa el
  /// nuevo». **Con varias pestañas pasa el espejo exacto**: la pestaña A refresca,
  /// el disco queda con el token nuevo, y la pestaña B **sigue con el viejo en
  /// memoria indefinidamente**. Cuando a B le caduca el token de acceso, lo canjea,
  /// el backend lo lee como **reutilización** y **revoca la sesión de las dos**.
  ///
  /// No es una carrera estrecha: es determinista. Y no falla el detector del
  /// servidor —ése es justo lo que caza un token robado—, falla que había **dos
  /// refrescadores sobre una credencial compartida**.
  ///
  /// ## Los cuatro casos, y por qué cada uno es así
  ///
  ///  · **igual que en memoria** → la de siempre. Es el caso de una sola pestaña;
  ///  · **misma sesión, token distinto** → **se adopta la del almacén**. Otra pestaña
  ///    ya rotó, y el único token que el servidor acepta es el suyo;
  ///  · **no se pudo leer** —`null`— → **se sigue con la de memoria**. Un fallo
  ///    transitorio del almacén **no debe cerrar la sesión**; y si de verdad no hay
  ///    credencial, el servidor contesta 401 y el camino que ya existe cierra limpio;
  ///  · **sesión distinta** → **NO se adopta**. Si otra pestaña entró con otra
  ///    cuenta, adoptar su credencial haría que esta pestaña actuara como otra
  ///    persona **en silencio**. Se sigue con la propia, el servidor contesta 401
  ///    porque esa sesión ya no vive, y se cierra como corresponde.
  ///
  /// El último caso es el que obliga a comparar por **`sessionId`** y no por el
  /// token: la versión obvia —«si el almacén tiene algo distinto, úsalo»— cambiaría
  /// de usuario sin avisar.
  ///
  /// ## Lo que esto NO hace
  ///
  /// No serializa dos refrescos **simultáneos**: si las dos pestañas disparan a la
  /// vez, las dos leen el mismo token y la segunda sigue siendo una reutilización.
  /// Eso lo cierra el candado entre pestañas, que es el paso siguiente. Esto arregla
  /// la **copia obsoleta**, que es el caso que se vio en pantalla.
  ///
  /// **No muta `_credencial`** a propósito: la lectura es asíncrona y escribir aquí
  /// podría resucitar una sesión que se cerró mientras se leía. Quien decide
  /// publicar es el camino del refresco, después de comprobar la generación.
  Future<CredencialRemota> _credencialParaRefrescar(
    CredencialRemota enMemoria,
  ) async {
    final guardada = await _leerCredencial();

    if (guardada == null ||
        guardada.sessionId != enMemoria.sessionId ||
        guardada.refreshToken == enMemoria.refreshToken) {
      return enMemoria;
    }

    _logger.info(
      'Otra pestaña rotó el token de refresco; se usa el del almacén en vez del '
      'de memoria para no provocar una reutilización.',
    );

    return guardada;
  }

  Future<CredencialRemota?> _leerCredencial() async {
    try {
      return await _almacen.leer();
    } catch (e) {
      _logger.error('No se pudo leer la credencial de la sesión remota.', e);
      return null;
    }
  }

  Future<void> _borrarCredencial() async {
    try {
      await _almacen.borrar();
    } catch (e) {
      // Se registra y se sigue: el estado en memoria ya dice que no hay sesión, y
      // dejar el cierre a medias por esto sería peor.
      _logger.error('No se pudo borrar la credencial de la sesión remota.', e);
    }
  }
}
