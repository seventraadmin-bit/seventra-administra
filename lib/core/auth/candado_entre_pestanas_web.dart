import 'dart:js_interop';

import '../error/result.dart';

/// El candado entre pestañas **en el navegador**, con la Web Locks API.
///
/// ## Qué cierra, y por qué hacía falta además de releer el almacén
///
/// Releer la credencial antes de refrescar arregla la **copia obsoleta** —una pestaña
/// que guardaba el token viejo—, pero no la **carrera simultánea**: si las dos
/// pestañas leen el mismo token en el mismo instante, las dos leyeron bien, y las dos
/// lo canjean. La segunda es una reutilización y el servidor revoca la sesión de las
/// dos.
///
/// `navigator.locks` resuelve exactamente eso: el navegador garantiza que **sólo un
/// contexto del mismo origen** tiene el candado a la vez, y los demás esperan. Cuando
/// la pestaña que esperaba entra, relee el almacén y encuentra el token nuevo — las
/// dos piezas se necesitan, ninguna sobra.
///
/// ## Por qué un candado del NAVEGADOR y no uno hecho con el almacén
///
/// Un mutex sobre `localStorage` exige leer-y-escribir sin que nadie se cuele en
/// medio, y el almacén web **no ofrece comparar-e-intercambiar**. Lo que sale es un
/// candado que falla justo cuando hay contención, que es cuando se necesita.
/// `navigator.locks` lo implementa el navegador y no tiene ese agujero.
///
/// ## SI NO EXISTE, SE SIGUE SIN CANDADO, Y SE DICE AQUÍ
///
/// La API falta en navegadores viejos y en contextos no seguros. En ese caso se
/// ejecuta el trabajo igual, **sin pretender un candado que no hay**: la relectura del
/// almacén sigue cubriendo el caso frecuente, y lo que queda expuesto es la carrera
/// simultánea — la misma situación que antes de este archivo, no peor.
///
/// Fingir lo contrario —por ejemplo, abortar— dejaría sin sesión a alguien por una
/// capacidad del navegador que no cambia nada de su derecho a entrar.
Future<Result<String>> conCandadoDeRefresco(
  Future<Result<String>> Function() trabajo,
) async {
  final candados = _navegador?.locks;

  if (candados == null) return trabajo();

  // EL RESULTADO VIAJA POR FUERA DEL PUENTE A JAVASCRIPT. La promesa que se le
  // devuelve al navegador sólo sirve para decirle CUÁNDO soltar el candado; el valor
  // —y un posible error— se recogen aquí, en Dart, sin pasar por `JSAny`.
  Result<String>? resultado;
  Object? fallo;
  StackTrace? rastro;

  JSPromise<JSAny?> dentroDelCandado(JSAny? _) {
    final futuro = trabajo().then<JSAny?>(
      (valor) {
        resultado = valor;
        return null;
      },
      onError: (Object e, StackTrace s) {
        // SE CAPTURA Y SE RESUELVE LA PROMESA IGUAL. Si se dejara propagar hacia
        // JavaScript, el candado se soltaría de todas formas pero el error llegaría
        // como un rechazo de promesa cruzando la frontera, que es más difícil de
        // seguir. Se vuelve a lanzar abajo, en Dart, con su rastro intacto.
        fallo = e;
        rastro = s;
        return null;
      },
    );

    return futuro.toJS;
  }

  // EL NOMBRE ES DEL ORIGEN, y por eso lleva prefijo: los candados se comparten entre
  // todo lo que corra en este origen, así que uno llamado «refresco» podría chocar
  // con otra cosa el día que algo más lo use.
  await candados.request('seventra.sesion.refresco', dentroDelCandado.toJS).toDart;

  if (fallo != null) {
    Error.throwWithStackTrace(fallo!, rastro ?? StackTrace.current);
  }

  // No puede ser nulo: o se completó, o se capturó un fallo y ya se relanzó.
  return resultado!;
}

@JS('navigator')
external _Navegador? get _navegador;

extension type _Navegador._(JSObject _) implements JSObject {
  /// Nulo en navegadores sin Web Locks y en contextos no seguros.
  external _GestorDeCandados? get locks;
}

extension type _GestorDeCandados._(JSObject _) implements JSObject {
  /// Toma el candado `nombre`, llama a `callback` cuando lo tiene, y lo suelta
  /// cuando la promesa que `callback` devuelve se resuelve.
  external JSPromise<JSAny?> request(String nombre, JSFunction callback);
}
