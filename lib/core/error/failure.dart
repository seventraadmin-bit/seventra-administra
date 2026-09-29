/// Jerarquía base de errores esperados del dominio (no crashes inesperados).
///
/// Se usa como el lado "error" de [Result]. Los casos concretos se agregan
/// conforme cada módulo los necesite — esta etapa solo define la base común.
sealed class Failure {
  const Failure(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message);
}

class PermissionFailure extends Failure {
  const PermissionFailure(super.message);
}

class DatabaseFailure extends Failure {
  const DatabaseFailure(super.message);
}

class UnknownFailure extends Failure {
  const UnknownFailure(super.message);
}

// ===========================================================================
// Capa HTTP (Integration Foundation IF-1)
// ===========================================================================

/// Los errores de la capa HTTP.
///
/// VIVEN AQUÍ Y NO EN `core/api/` por una razón del lenguaje y otra de diseño:
/// [Failure] es `sealed`, así que sus ramas deben declararse en esta librería —y
/// eso es precisamente lo que garantiza que la taxonomía de errores del proyecto
/// esté en un solo sitio y sea exhaustiva—. Inventar un `ApiError` paralelo
/// obligaría a traducir en cada frontera y a que cada pantalla conociera dos
/// taxonomías.
///
/// LA FRONTERA QUE ESTAS CLASES DIBUJAN es la decisión importante de la capa:
///
///  · **No hubo respuesta** —sin red, timeout, fallo de transporte— es un
///    [ApiFailure]. Ninguna excepción de `dart:io` ni de `package:http` escapa
///    como contrato público del cliente.
///  · **Hubo respuesta** —incluido un 404, un 409 o un 500— NO es un fallo: es
///    una `ApiRespuesta`. Un 409 `contrato_con_sucesor` es información de
///    negocio, y convertirlo en excepción en el transporte obligaría a cada
///    repositorio a atraparla para volver a decidir lo mismo.
sealed class ApiFailure extends Failure {
  const ApiFailure(super.message);
}

/// La dirección del backend no es utilizable. Se detecta al arrancar, nunca en
/// la primera petición.
final class ApiConfigFailure extends ApiFailure {
  const ApiConfigFailure(super.message);
}

/// No se pudo alcanzar el servidor: sin red, DNS que no resuelve, puerto
/// cerrado, servidor caído.
///
/// Distinto de [ApiTimeoutFailure] a propósito: «no hay conexión» y «el servidor
/// tarda» piden dos mensajes y dos reacciones distintas.
final class ApiSinConexionFailure extends ApiFailure {
  const ApiSinConexionFailure(super.message);
}

/// El servidor no respondió dentro del plazo.
final class ApiTimeoutFailure extends ApiFailure {
  const ApiTimeoutFailure(super.message);
}

/// El cuerpo no es JSON sintácticamente válido.
final class ApiJsonInvalidoFailure extends ApiFailure {
  const ApiJsonInvalidoFailure(super.message);
}

/// El cuerpo es JSON válido pero no tiene la forma que esperaba quien lo pidió:
/// llegó una lista donde iba un objeto, o falta un campo obligatorio.
///
/// Separado de [ApiJsonInvalidoFailure] porque son dos averías distintas: una es
/// del transporte o de un proxy que devolvió HTML, y la otra es un desacuerdo de
/// contrato entre cliente y servidor. Confundirlas haría que un cambio de
/// contrato pareciera un problema de red.
final class ApiRespuestaInesperadaFailure extends ApiFailure {
  const ApiRespuestaInesperadaFailure(super.message);
}

/// Una respuesta HTTP que una capa superior decidió tratar como fallo.
///
/// IF-1 NO la produce por su cuenta: una respuesta no exitosa sigue siendo una
/// `ApiRespuesta`, y quien la convierta en fallo será el repositorio o la capa de
/// sesión. Lo que esta clase garantiza es que, cuando eso ocurra, **no se pierda
/// nada** de lo que las capas siguientes necesitan:
///
///  · IF-2 mirará el **401** para decidir sobre la sesión;
///  · IF-4 mirará el **402 `subscription_restricted`** para el banner, y
///    distinguirá **403 `module_disabled`** de **403 `permission_missing`**, que
///    piden mensajes distintos;
///  · Files mirará el **409 `storage_capacity_exceeded`** con sus cifras.
///
/// Por eso conserva el `statusCode`, el `code` textual del backend y los datos
/// extra: colapsarlos en un mensaje perdería justo lo que hace útil la respuesta.
final class ApiHttpFailure extends ApiFailure {
  const ApiHttpFailure({
    required this.statusCode,
    required String message,
    this.codigo,
    this.extra = const {},
  }) : super(message);

  final int statusCode;

  /// El `code` del backend: `subscription_restricted`, `permission_missing`,
  /// `contrato_no_encontrado`… `null` cuando la respuesta no lo traía.
  final String? codigo;

  /// Lo demás que venía en el cuerpo y puede hacer falta —`usedBytes` y
  /// `capacityBytes` de una respuesta de capacidad, por ejemplo—. Acotado por el
  /// parser: nunca es el cuerpo entero.
  final Map<String, Object?> extra;

  @override
  String toString() =>
      'ApiHttpFailure($statusCode${codigo == null ? '' : ' $codigo'}): $message';
}
