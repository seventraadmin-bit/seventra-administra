/// Cómo se dice **el eje temporal** de un servicio en una insignia.
///
/// ## 🚫 POR QUÉ EXISTE: «TERMINADO» Y «VIGENTE» A LA VEZ
///
/// El dueño probando C2 el 11 de noviembre de 2026: un servicio **Terminado** enseñaba a
/// su lado la insignia **«Vigente»**. Las dos eran ciertas por separado —el estatus es
/// `terminated` y la condición temporal que el servidor deriva de las fechas es
/// `inforce`, porque su término aún no llega— y juntas **no se pueden leer**: para quien
/// trabaja, un servicio terminado no está vigente.
///
/// La causa no es un error de cálculo: son **dos ejes distintos** pintados como si fueran
/// comparables. El estatus dice qué se decidió; la condición temporal, dónde cae hoy
/// respecto de las fechas.
///
/// ## LA REGLA, decidida el 11 de noviembre de 2026
///
/// **En un servicio terminado, el eje temporal deja de hablar de vigencia y dice cuándo
/// terminó:**
///
/// | estatus | qué insignia temporal sale |
/// |---|---|
/// | activo o suspendido | `Próximo` · `Vigente` · `Vencido`, como hasta hoy |
/// | **terminado**, con fecha de término | **«Terminó el 12/nov/2026»**, en tono neutro |
/// | **terminado**, sin fecha de término | **ninguna** |
///
/// El caso sin fecha existe de verdad: terminar un servicio no obliga a registrar el día
/// —el servidor acepta `endedOn` nulo—, y entonces lo único cierto es el estatus, que ya
/// se enseña al lado. **Inventar un texto genérico ahí no añadiría nada.**
///
/// ⚠️ **Y NO SE «ARREGLA» EL DATO DEL SERVIDOR.** `temporalCondition` sigue llegando tal
/// cual y sigue siendo correcta: lo que cambia es **qué se enseña**. Normalizarla en el
/// modelo —o pedirle al servidor que mande otra cosa— mezclaría los dos ejes en el dato,
/// y entonces el día que haga falta saber si un terminado vencía o no, ya no se podría.
///
/// ## Por qué es un archivo y no dos bloques iguales
///
/// Porque **el expediente y la fila del listado** enseñan esto, y el 11 de noviembre
/// estaban en un solo sitio por casualidad: el listado todavía no pintaba el eje temporal.
/// Con «Por terminar» entrando al listado serían dos, y dos juegos de reglas divergen en
/// el tercero sin que nada falle. Es la misma razón por la que los diez campos de un
/// domicilio viven en una tabla.
library;

import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/fechas/dia_de_negocio.dart';
import '../../../../core/fechas/fecha_en_pantalla.dart';
import '../modelos/servicio.dart';

/// Lo que una insignia temporal dice, o **nulo si no hay nada que decir**.
@immutable
class InsigniaTemporal {
  const InsigniaTemporal({required this.etiqueta, required this.tono});

  final String etiqueta;
  final RisegStatusTone tono;

  /// La insignia, ya pintada.
  ///
  /// Es un método y no un widget suelto **porque quien no tiene nada que decir devuelve
  /// nulo**: un widget que se construyera siempre y pintara un hueco vacío dejaría el
  /// espacio del `Wrap` donde no hay insignia. Así el llamador escribe
  /// `if (temporal != null) temporal.pintar()` y no hay hueco que explicar.
  Widget pintar() =>
      RisegStatusBadge(label: etiqueta, tone: tono, icon: Icons.schedule);
}

/// Qué insignia temporal le toca a un servicio.
///
/// Recibe los tres datos sueltos —y no un `Servicio`— porque **la ficha y la fila son
/// dos clases distintas** con los mismos tres campos: pedir el modelo obligaría a una
/// sobrecarga por clase, que es justo la duplicación que esto viene a evitar.
InsigniaTemporal? insigniaTemporalDe({
  required String estatus,
  required String condicionTemporal,
  required DiaDeNegocio? termino,
}) {
  final estado = EstatusDeServicio.deCodigo(estatus);

  // ⚠️ `esFinalizado` Y NO `== terminado`: la frontera vive en el modelo para que el día
  // que haya otro estatus final se añada en un solo sitio.
  if (estado?.esFinalizado ?? false) {
    if (termino == null) return null;

    return InsigniaTemporal(
      etiqueta: 'Terminó el ${fechaDeNegocioCorta(termino)}',
      tono: RisegStatusTone.neutral,
    );
  }

  final temporal = CondicionTemporal.deCodigo(condicionTemporal);
  if (temporal == null) return null;

  return InsigniaTemporal(
    etiqueta: temporal.nombre,
    // LA CONDICIÓN TEMPORAL SE TRADUCE AQUÍ, y sólo aquí: viaja como
    // `upcoming · inforce · expired` por decisión del dueño, y la pantalla es la que la
    // pone en español.
    tono: switch (temporal) {
      CondicionTemporal.proxima => RisegStatusTone.info,
      CondicionTemporal.vigente => RisegStatusTone.success,
      CondicionTemporal.vencida => RisegStatusTone.warning,
    },
  );
}

