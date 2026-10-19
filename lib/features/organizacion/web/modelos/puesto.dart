/// Un puesto, tal como lo devuelve `GET /companies/{id}/positions`.
///
/// **UN PUESTO ES EL CARGO, NO LA PERSONA.** «Supervisor general» es un puesto;
/// quién lo ocupa es una asignación de Personal. Por eso un puesto sigue existiendo
/// —inactivo— cuando nadie lo ocupa: su historia laboral lo referencia.
///
/// Modelo plano y propio de la web, por la misma razón que [Area]: el dominio del
/// escritorio habla tipos generados por Drift y aquí no hay Drift.
class Puesto {
  const Puesto({
    required this.id,
    required this.areaId,
    required this.codigo,
    required this.nombre,
    required this.tipo,
    required this.activo,
    required this.nivel,
    required this.descripcion,
  });

  factory Puesto.deJson(Map<String, dynamic> json) => Puesto(
    id: json['id'] as String,
    areaId: json['areaId'] as String,
    codigo: json['code'] as String,
    nombre: json['name'] as String,
    tipo: json['kind'] as String,
    // `activo` se DERIVA del estado, igual que en Área: dos campos para un solo
    // hecho acabarían discrepando.
    activo: json['status'] == 'activa',
    nivel: (json['hierarchyLevel'] as num?)?.toInt(),
    descripcion: json['description'] as String?,
  );

  final String id;

  /// El área a la que pertenece. **No se puede cambiar**: la base lo respalda con un
  /// disparador, porque es configuración estable de una fila que la historia laboral
  /// referencia. Reclasificar es desactivar y crear otro.
  final String areaId;

  /// El código, `PUE-0001`. **Identidad, y tampoco se cambia.**
  final String codigo;

  final String nombre;

  /// `operativo` u `administrativo`. **Tampoco se cambia**, por lo mismo que el área.
  final String tipo;

  final bool activo;

  /// Del 1 al 10, **donde el 1 es el más bajo**. Lo dice el propio servidor al
  /// rechazar un alta sin nivel.
  ///
  /// ⚠️ **NULO ES POSIBLE Y NO SIGNIFICA CERO.** La columna es opcional en la base
  /// —ya existen puestos sin nivel, de antes de que el campo existiera— y la ruta sólo
  /// lo exige **al crear**. Un puesto viejo se puede corregir de nombre sin
  /// inventarle un nivel, que es justo lo que hay que poder hacer. La pantalla lo
  /// muestra como «sin nivel», nunca como «Nivel 0».
  final int? nivel;

  /// Opcional, y vacío **no es lo mismo que nulo** para quien lo lee: las dos cosas se
  /// muestran igual —no hay descripción— y no se distinguen en pantalla.
  final String? descripcion;

  bool get esOperativo => tipo == 'operativo';
}

/// El código que se sugiere para el siguiente puesto: `PUE-0001`, `PUE-0002`…
///
/// ## De dónde sale el formato
///
/// Del escritorio, que lo genera solo: en `seed_data.dart` el renglón del puesto es
/// `('puesto', 'PUE', 4)` — prefijo **PUE** y **cuatro** dígitos. Aquí se replica para
/// que un cliente que viene del escritorio reconozca sus códigos.
///
/// ## Es el MÁXIMO más uno, no el primer hueco
///
/// Con `PUE-0001` y `PUE-0003` sugiere **`PUE-0004`**. Rellenar el hueco reutilizaría
/// un número que alguien pudo haber impreso, dicho por teléfono o metido en una hoja
/// de cálculo, y dos puestos distintos acabarían llamándose igual en dos sitios.
///
/// ## Lo que NO rompe
///
///  · **Los códigos que no siguen el patrón se ignoran** para la cuenta. Alguien pudo
///    escribir `SUP` a mano —el campo es editable— y eso no debe frenar la sugerencia.
///  · **Pasado el 9999 crece a cinco dígitos** en vez de volver a empezar: un código
///    repetido es peor que uno largo.
///  · Y la comparación es **numérica, no de texto**: por texto, `PUE-10000` quedaría
///    antes de `PUE-9999` y la sugerencia retrocedería.
String siguienteCodigoDePuesto(Iterable<String> codigosExistentes) {
  const prefijo = 'PUE-';
  const digitos = 4;

  var mayor = 0;

  for (final codigo in codigosExistentes) {
    final normalizado = codigo.trim().toUpperCase();
    if (!normalizado.startsWith(prefijo)) continue;

    final numero = int.tryParse(normalizado.substring(prefijo.length));
    if (numero != null && numero > mayor) mayor = numero;
  }

  return '$prefijo${(mayor + 1).toString().padLeft(digitos, '0')}';
}
