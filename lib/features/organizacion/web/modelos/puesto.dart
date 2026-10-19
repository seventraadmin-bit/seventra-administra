import 'codigo_sugerido.dart';

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
    this.creadoEn,
    this.actualizadoEn,
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
    // LAS DOS FECHAS SE LEEN TOLERANTES, y no por pereza: una respuesta de una API
    // anterior —o un ensayo sin desplegar todavía— no trae `createdAt`, y la pantalla
    // tiene que seguir abriendo. `tryParse` con nulo es «no la sé», que es la verdad;
    // una excepción aquí sería la pantalla roja por una fecha.
    creadoEn: _fechaONulo(json['createdAt']),
    actualizadoEn: _fechaONulo(json['updatedAt']),
  );

  /// Una fecha de la API, o `null` si no vino o no se entiende.
  static DateTime? _fechaONulo(Object? valor) =>
      valor is String ? DateTime.tryParse(valor) : null;

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

  /// Cuándo se creó y cuándo se tocó por última vez.
  ///
  /// **Nulas si la API no las mandó**, que es lo que pasa contra un servidor anterior a
  /// que la ruta las expusiera. La pantalla dice «no se sabe» en vez de inventar una
  /// fecha, por la misma razón que un nivel nulo no es cero: **ausencia nunca es cero.**
  final DateTime? creadoEn;
  final DateTime? actualizadoEn;

  bool get esOperativo => tipo == 'operativo';
}

/// El código que se sugiere para el siguiente puesto: `PUE-0001`, `PUE-0002`…
///
/// **Una línea, y a propósito.** Cuando Áreas y Sucursales estrenaron su sugerencia
/// —`ARE-####` y `SUC-####`—, la lógica se generalizó en [siguienteCodigo] en vez de
/// copiarse tres veces. Tres copias de un generador de consecutivos divergirían justo
/// en el borde que importa: el 9999, el código escrito a mano, el orden numérico.
///
/// Este nombre se conserva porque es el que la pantalla de Puestos ya usa y porque sus
/// pruebas describen el contrato con detalle; el razonamiento completo —por qué es el
/// máximo más uno y no el primer hueco, qué pasa pasado el 9999— vive en
/// [siguienteCodigo].
String siguienteCodigoDePuesto(Iterable<String> codigosExistentes) =>
    siguienteCodigo(PrefijoDeCodigo.puesto, codigosExistentes);
