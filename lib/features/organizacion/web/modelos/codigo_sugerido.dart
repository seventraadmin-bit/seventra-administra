/// El código que se sugiere para la siguiente fila de un catálogo: `ARE-0001`,
/// `PUE-0002`, `SUC-0003`…
///
/// ## De dónde salen los prefijos
///
/// Del escritorio, que los genera solo. En su `seed_data.dart` los renglones son
/// `('area','ARE',4)`, `('puesto','PUE',4)` y `('sucursal','SUC',4)`: prefijo de tres
/// letras y **cuatro** dígitos. Aquí se replican para que un cliente que viene del
/// escritorio reconozca sus códigos, y porque teclear códigos a mano es cómo nacen los
/// `OPERACIONES` y los `operaciones ` que después hay que normalizar.
///
/// ## Lo sugiere el CLIENTE, y es una decisión, no una comodidad
///
/// La alternativa era un consecutivo en el servidor, y se descartó midiendo el coste:
/// necesitaría tabla nueva, bloqueo propio y **un sitio en el orden global de
/// bloqueos**, que es donde nacen los interbloqueos. Lo que se pedía —que nadie teclee
/// el código a mano— se cumple igual.
///
/// La contra es real y conviene tenerla escrita: **dos personas creando a la vez
/// reciben la misma sugerencia**, y la segunda recibe un 409. No es un dato corrupto
/// —el `UNIQUE (company_id, code)` lo rechaza limpio—, y la pantalla reintenta una vez
/// con la lista recién leída.
///
/// ## Es el MÁXIMO más uno, no el primer hueco
///
/// Con `ARE-0001` y `ARE-0003` sugiere **`ARE-0004`**. Rellenar el hueco reutilizaría
/// un número que alguien pudo haber impreso, dicho por teléfono o metido en una hoja de
/// cálculo, y dos filas distintas acabarían llamándose igual en dos sitios.
///
/// ## Lo que NO rompe
///
///  · **Los códigos que no siguen el patrón se ignoran** para la cuenta. Alguien pudo
///    escribir `SUP` a mano —el campo es editable— y eso no debe frenar la sugerencia.
///  · **Pasado el 9999 crece a cinco dígitos** en vez de volver a empezar: un código
///    repetido es peor que uno largo.
///  · La comparación es **numérica, no de texto**: por texto, `ARE-10000` quedaría
///    antes de `ARE-9999` y la sugerencia retrocedería.
///  · Y el prefijo de otro catálogo **no cuenta**: un `PUE-0007` no empuja al área
///    siguiente a `ARE-0008`.
library;

import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';

/// Los tres prefijos del escritorio. **Tres letras y cuatro dígitos, los tres.**
enum PrefijoDeCodigo {
  area('ARE'),
  puesto('PUE'),
  sucursal('SUC');

  const PrefijoDeCodigo(this.letras);

  final String letras;
}

/// Cuántos dígitos lleva el consecutivo. Cuatro, como en el escritorio.
const int _digitosPorOmision = 4;

/// El siguiente código para [prefijo], dado lo que ya existe.
String siguienteCodigo(
  PrefijoDeCodigo prefijo,
  Iterable<String> codigosExistentes, {
  int digitos = _digitosPorOmision,
}) {
  final inicio = '${prefijo.letras}-';

  var mayor = 0;

  for (final codigo in codigosExistentes) {
    final normalizado = codigo.trim().toUpperCase();
    if (!normalizado.startsWith(inicio)) continue;

    final numero = int.tryParse(normalizado.substring(inicio.length));
    if (numero != null && numero > mayor) mayor = numero;
  }

  return '$inicio${(mayor + 1).toString().padLeft(digitos, '0')}';
}

/// Crea una fila con un código sugerido y **reintenta UNA vez** si choca.
///
/// ## Por qué hace falta
///
/// La sugerencia la calcula el cliente, así que **dos personas creando a la vez reciben
/// el mismo código** y la segunda recibe un 409. No es un dato corrupto —el
/// `UNIQUE (company_id, code)` del servidor lo rechaza limpio— pero es un error que la
/// persona no causó y no entiende: ella no escribió ese número.
///
/// Así que se reintenta: se vuelve a leer la lista, se recalcula el consecutivo y se
/// intenta otra vez.
///
/// ## UNA vez, y no en un bucle
///
/// Un bucle «hasta que entre» convierte dos personas creando en una carrera que puede
/// durar lo que duren los choques, y con tres o más clientes no termina nunca de forma
/// acotada. Un reintento cubre el caso real —dos personas a la vez— y el segundo choque
/// se le dice a la persona, que entonces sí puede elegir un código a mano.
///
/// ## SÓLO si el código es el SUGERIDO
///
/// Si la persona escribió `OPERACIONES` y ya existe, **no se reintenta nada**: cambiarle
/// el código por su cuenta sería crear una fila distinta de la que pidió. El reintento
/// arregla un problema de la máquina, no una decisión de la persona.
///
/// ## Y si la relectura falla, se devuelve el choque ORIGINAL
///
/// No el fallo de red de la relectura: lo que la persona necesita saber es que el código
/// chocó, no que el segundo intento de leer la lista se cayó. Mezclarlos cambiaría un
/// mensaje accionable por uno que no lo es.
Future<Result<T>> crearConReintentoDeCodigo<T>({
  required PrefijoDeCodigo prefijo,
  required String codigoUsado,
  required String? codigoSugerido,
  required Future<Result<T>> Function(String codigo) crear,
  required Future<Result<List<String>>> Function() codigosActuales,
}) async {
  final primero = await crear(codigoUsado);

  final choque = primero.when(
    ok: (_) => null,
    failure: (f) => f is ApiHttpFailure && f.codigo == 'code_conflict' ? f : null,
  );

  // No chocó, o chocó por otra razón, o el código lo eligió la persona.
  if (choque == null || codigoSugerido == null || codigoUsado != codigoSugerido) {
    return primero;
  }

  final relectura = await codigosActuales();

  final codigos = relectura.when(ok: (c) => c, failure: (_) => null);
  if (codigos == null) return primero;

  final segundo = siguienteCodigo(prefijo, codigos);

  // Si la relectura propone el MISMO código, el choque no era una carrera: alguien tiene
  // ese código escrito a mano de una forma que el patrón no reconoce, o la lista llegó
  // igual. Reintentar con lo mismo daría el mismo 409 y gastaría otro viaje.
  if (segundo == codigoUsado) return primero;

  return crear(segundo);
}
