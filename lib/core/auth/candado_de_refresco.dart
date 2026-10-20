import '../error/result.dart';

/// Cómo se serializa un refresco de sesión **entre pestañas**.
///
/// ## El problema que esto cierra, y el que NO
///
/// El token de refresco es de un solo uso con rotación: el servidor marca el
/// presentado como consumido y emite otro. Si llega uno ya consumido lo lee como
/// **reutilización** y **revoca la sesión entera** — y eso está bien, es justo lo que
/// caza un token robado.
///
/// Con varias pestañas eso ocurría de dos formas distintas:
///
///  1. **Copia obsoleta.** La pestaña B guardaba el token viejo en memoria y lo
///     canjeaba mucho después. **Ya resuelto**: el refresco relee el almacén antes de
///     llamar —ver `GestorDeSesion`—;
///  2. **Carrera simultánea.** Las dos pestañas leen el MISMO token en el mismo
///     instante y las dos lo canjean. La relectura no ayuda: las dos leyeron bien.
///     **Esto es lo que cierra el candado.**
///
/// ## Por qué es un parámetro y no una llamada directa
///
/// Porque si no, **la propiedad no se puede probar**. El candado de verdad es
/// `navigator.locks`, que sólo existe en el navegador, y las pruebas corren en la VM
/// de Dart: el archivo web nunca se ejecutaría y la prueba mediría el camino que no
/// es. Inyectándolo, una prueba puede dar dos `GestorDeSesion` un candado que
/// serializa de verdad y afirmar que **sólo sale UNA petición de refresco**.
///
/// La implementación por omisión la elige el `import` condicional de
/// `candado_entre_pestanas.dart`.
typedef CandadoDeRefresco =
    Future<Result<String>> Function(Future<Result<String>> Function() trabajo);
