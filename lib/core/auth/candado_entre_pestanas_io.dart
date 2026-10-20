import '../error/result.dart';

/// El candado entre pestañas **en el escritorio: no hace falta ninguno**.
///
/// **Y ES CORRECTO, NO UN HUECO.** En Windows hay **un proceso y un
/// `GestorDeSesion`**, así que no existen «dos pestañas» que puedan canjear el mismo
/// token de refresco a la vez. Lo que sí puede pasar —diez peticiones en paralelo
/// pidiendo token dentro del mismo proceso— ya lo serializa el «single-flight» del
/// gestor, que entrega el mismo `Future` a todas.
///
/// Dicho de otra forma: aquí el trabajo ya está serializado por construcción, y
/// envolverlo en un candado añadiría una espera que nunca tendría nada que esperar.
///
/// La contraparte real está en `candado_entre_pestanas_web.dart`.
Future<Result<String>> conCandadoDeRefresco(
  Future<Result<String>> Function() trabajo,
) => trabajo();
