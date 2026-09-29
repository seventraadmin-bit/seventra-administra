import 'dart:convert';

import '../error/failure.dart';

/// La sesión remota **vista desde fuera**: quién es, no con qué se prueba.
///
/// NO CONTIENE NINGÚN TOKEN, y ésa es la decisión central de este archivo. El
/// token de acceso vive en memoria dentro de [GestorDeSesion] y el de refresco
/// sólo en el almacén seguro; ninguno de los dos pasa por el estado que observa
/// la interfaz. Así, una pantalla que muestre la sesión —o un registro que
/// serialice el estado para diagnóstico— no puede filtrar una credencial ni
/// queriendo.
///
/// TAMPOCO CONTIENE COMPANY, PERMISOS NI `restricted`. Autenticarse es responder
/// «quién eres»; qué Company está activa y qué puede hacer esa identidad es otra
/// pregunta, la responde `GET /context` en el backend y la resolverá IF-4.
/// Mezclarlas aquí obligaría a reautenticar para refrescar un permiso, y haría
/// que el estado de sesión caducara por razones que no son de sesión.
final class SesionRemota {
  const SesionRemota({
    required this.sessionId,
    required this.email,
    this.displayName,
  });

  /// El identificador de la sesión en el backend, no de la Identity. Sirve para
  /// correlacionar con la auditoría de seguridad del servidor.
  final String sessionId;

  final String email;

  /// El nombre para mostrar. Es `null` cuando la sesión se restauró por refresco
  /// y el backend no lo reenvió —`/auth/refresh` responde con `displayName` y
  /// `email` nulos, verificado en su contrato—, así que quien lo muestre tiene
  /// que tolerar su ausencia.
  final String? displayName;

  @override
  String toString() => 'SesionRemota($sessionId, $email)';

  @override
  bool operator ==(Object other) =>
      other is SesionRemota &&
      other.sessionId == sessionId &&
      other.email == email &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(sessionId, email, displayName);
}

/// Lo que se guarda en el almacén seguro del sistema para poder volver mañana.
///
/// SEPARADA DE [SesionRemota] A PROPÓSITO: esto es una credencial, aquello es
/// una identidad. Tenerlas en una sola clase haría que el objeto que la interfaz
/// observa llevara dentro el token de refresco, que es exactamente el secreto
/// que más hay que cuidar —con él se emiten tokens de acceso nuevos durante
/// catorce días—.
///
/// El token de ACCESO no está aquí: dura treinta minutos y persistirlo sería
/// dejar en disco un secreto que no hace falta guardar.
final class CredencialRemota {
  const CredencialRemota({
    required this.refreshToken,
    required this.refreshExpiresAt,
    required this.sessionId,
    required this.email,
    this.displayName,
  });

  final String refreshToken;

  /// Siempre en UTC. Normalizarlo al construir evita que una comparación dé un
  /// resultado distinto según el desplazamiento con que llegó del servidor.
  final DateTime refreshExpiresAt;

  final String sessionId;
  final String email;
  final String? displayName;

  SesionRemota get sesion => SesionRemota(
    sessionId: sessionId,
    email: email,
    displayName: displayName,
  );

  bool haCaducado(DateTime ahora) => !refreshExpiresAt.isAfter(ahora.toUtc());

  CredencialRemota copyWith({
    String? refreshToken,
    DateTime? refreshExpiresAt,
    String? displayName,
  }) => CredencialRemota(
    refreshToken: refreshToken ?? this.refreshToken,
    refreshExpiresAt: refreshExpiresAt ?? this.refreshExpiresAt,
    sessionId: sessionId,
    email: email,
    // `??` y no un parámetro-bandera: el refresco del backend devuelve
    // `displayName` nulo, y en ese caso hay que CONSERVAR el que ya se tenía,
    // no borrarlo.
    displayName: displayName ?? this.displayName,
  );

  // -------------------------------------------------------------------------
  // El formato en disco
  // -------------------------------------------------------------------------

  /// Versión del blob. Existe para que un formato futuro pueda reconocer —y
  /// descartar— lo que escribió una versión anterior sin adivinar.
  static const int versionActual = 1;

  static const String _kVersion = 'v';
  static const String _kRefreshToken = 'rt';
  static const String _kRefreshExpira = 'rte';
  static const String _kSessionId = 'sid';
  static const String _kEmail = 'em';
  static const String _kDisplayName = 'dn';

  /// UN SOLO BLOB, y no cinco entradas: el almacén de credenciales de Windows no
  /// ofrece transacción, así que cinco escrituras pueden quedar a medias —token
  /// nuevo con caducidad vieja— y eso produce una sesión que parece válida y no
  /// lo es. Con un blob, o está entero o no está.
  String aTexto() => jsonEncode({
    _kVersion: versionActual,
    _kRefreshToken: refreshToken,
    _kRefreshExpira: refreshExpiresAt.toUtc().toIso8601String(),
    _kSessionId: sessionId,
    _kEmail: email,
    if (displayName != null) _kDisplayName: displayName,
  });

  /// Lee el blob. **Nunca lanza**: devuelve `null` ante cualquier cosa que no
  /// sea un blob completo de esta versión.
  ///
  /// Tolerar basura no es laxitud, es la única respuesta segura: un blob
  /// truncado, escrito por una versión anterior o manipulado no puede
  /// autenticar a nadie, y lanzar desde aquí reventaría el arranque por un
  /// archivo que lo correcto es tirar.
  static CredencialRemota? desdeTexto(String? texto) {
    if (texto == null || texto.trim().isEmpty) return null;

    final Object? crudo;
    try {
      crudo = jsonDecode(texto);
    } on FormatException {
      return null;
    }

    if (crudo is! Map<String, Object?>) return null;
    if (crudo[_kVersion] != versionActual) return null;

    final refreshToken = _texto(crudo[_kRefreshToken]);
    final sessionId = _texto(crudo[_kSessionId]);
    final email = _texto(crudo[_kEmail]);
    final expira = _texto(crudo[_kRefreshExpira]);

    if (refreshToken == null ||
        sessionId == null ||
        email == null ||
        expira == null) {
      return null;
    }

    final refreshExpiresAt = DateTime.tryParse(expira);
    if (refreshExpiresAt == null) return null;

    return CredencialRemota(
      refreshToken: refreshToken,
      refreshExpiresAt: refreshExpiresAt.toUtc(),
      sessionId: sessionId,
      email: email,
      displayName: _texto(crudo[_kDisplayName]),
    );
  }

  static String? _texto(Object? valor) {
    if (valor is! String) return null;

    final limpio = valor.trim();
    return limpio.isEmpty ? null : limpio;
  }

  /// **Sin el token.** `toString` acaba en registros, en mensajes de error y en
  /// volcados de excepción; incluir la credencial aquí sería filtrarla por la
  /// puerta de atrás después de haberla guardado cifrada.
  @override
  String toString() =>
      'CredencialRemota($sessionId, $email, expira: '
      '${refreshExpiresAt.toIso8601String()})';
}

// ===========================================================================
// El estado observable
// ===========================================================================

/// En qué situación está la autenticación remota.
///
/// SON CUATRO ESTADOS Y NO DOS, porque colapsarlos produce errores concretos:
///
///  · «todavía no se ha mirado» no es «no hay sesión». Un portón que los
///    confunda manda al login antes de que la restauración termine, y el usuario
///    ve la pantalla de credenciales un instante aunque su sesión fuera válida.
///  · «no se pudo comprobar» no es «no hay sesión». Si un fallo de red se
///    tratara como cierre, una wifi intermitente expulsaría a quien tiene una
///    credencial perfectamente buena guardada — y además nada volvería a
///    intentarlo.
sealed class EstadoAutenticacion {
  const EstadoAutenticacion();
}

/// Nadie ha intentado restaurar todavía. Es el estado inicial.
final class AutenticacionSinResolver extends EstadoAutenticacion {
  const AutenticacionSinResolver();

  @override
  String toString() => 'AutenticacionSinResolver()';
}

/// No hay credencial: nunca hubo, o el backend la invalidó, o se cerró sesión.
final class NoAutenticado extends EstadoAutenticacion {
  const NoAutenticado();

  @override
  String toString() => 'NoAutenticado()';
}

/// La sesión remota está establecida: hay credencial y el backend la confirmó al
/// menos una vez en esta ejecución.
///
/// NO ES UNA PROMESA de que la siguiente petición vaya a funcionar. Que la red
/// caiga después no cambia este estado —la sesión no se ha cerrado, sólo no se
/// puede alcanzar—, y cada petición informa de su propio resultado. Degradar el
/// estado ante un refresco preventivo fallido haría parpadear la interfaz por un
/// bache de red.
final class Autenticado extends EstadoAutenticacion {
  const Autenticado(this.sesion);

  final SesionRemota sesion;

  @override
  String toString() => 'Autenticado($sesion)';

  @override
  bool operator ==(Object other) =>
      other is Autenticado && other.sesion == sesion;

  @override
  int get hashCode => sesion.hashCode;
}

/// Hay una credencial guardada, pero el servidor no se pudo consultar para
/// confirmarla **ni una vez**. **No se borra nada**: la credencial sigue ahí y el
/// siguiente intento la usará.
final class SesionRemotaSinConfirmar extends EstadoAutenticacion {
  const SesionRemotaSinConfirmar(this.motivo);

  final Failure motivo;

  @override
  String toString() => 'SesionRemotaSinConfirmar(${motivo.runtimeType})';
}
