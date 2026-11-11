import '../error/failure.dart';
import '../error/result.dart';

/// Construye un modelo a partir del JSON **atrapando cualquier error de lectura**.
///
/// ## Por qué existe, y es una pantalla rota del 11 de noviembre de 2026
///
/// `ClienteEnLista.deJson` leía `createdAt`, que la **ficha** publicaba y **la fila no**.
/// Al leer el listado, el `as String` sobre un nulo **lanzaba**. Y lanzar dentro de la rama
/// `ok:` de un `Result` no produce un fallo: **rompe la cadena del `await`**, así que el
/// `setState(() => _cargando = false)` de la pantalla **nunca se ejecuta**.
///
/// 🚫 **El resultado no es un error: es un indicador de carga que no se apaga nunca.** La
/// pestaña de Clientes se quedó cargando para siempre y **no dijo nada**, que es la peor
/// forma de fallar: parece lentitud, invita a esperar, y no hay nada que leer.
///
/// ## La regla
///
/// **Todo modelo que se construye a partir de una respuesta se construye aquí dentro.** Un
/// desacuerdo de contrato pasa a ser un `Result.failure`, que es lo que las pantallas ya
/// saben pintar: el estado de error, con su botón de reintentar.
///
/// ## Qué dice el mensaje, y qué NO
///
/// Dice **qué se estaba leyendo** y el error de tipo, que es lo único accionable: nombra el
/// campo o el tipo que no cuadra y apunta a una aplicación desactualizada. **No lleva el
/// cuerpo de la respuesta**, por lo mismo que no lo lleva el fallo de JSON inválido: podría
/// ser la página de error de un proxy corporativo con información de la red interna, y este
/// texto acaba en pantallas y en registros.
Result<T> leyendo<T>(String queEs, T Function() construir) {
  try {
    return Result.ok(construir());
  } on Object catch (error) {
    // SE ATRAPA `Object` Y NO `Exception`, a propósito: un `as` que falla lanza un
    // `TypeError`, que es un `Error` y NO un `Exception`. Atrapar sólo `Exception` habría
    // dejado pasar exactamente el fallo que esto existe para cazar.
    return Result.failure(
      ApiJsonInvalidoFailure(
        'El servidor devolvió $queEs con una forma que esta versión no entiende. '
        'Puede que la aplicación esté desactualizada. ($error)',
      ),
    );
  }
}
