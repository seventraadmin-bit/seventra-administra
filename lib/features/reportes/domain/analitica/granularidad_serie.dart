import 'comparacion_periodo.dart';

/// Con qué paso se agrupa una serie temporal (§6 del rediseño de
/// Reportes).
///
/// Puro y sin formato: decidir el paso es una regla, no una decisión
/// de presentación. Las etiquetas visibles las arma la capa de UI con
/// `AppLocalizations`, nunca este archivo.
enum GranularidadSerie {
  dia,
  semana,
  mes;

  /// Elige el paso apropiado al largo del rango.
  ///
  /// Los cortes no son arbitrarios: buscan que una gráfica nunca tenga
  /// más de ~45 barras, que es donde dejan de ser legibles en el ancho
  /// disponible de esta aplicación de escritorio.
  ///
  ///  - hasta 45 días  -> un punto por día    (<= 45 barras)
  ///  - hasta 45 semanas (~10 meses) -> semanas (<= 45 barras)
  ///  - más            -> meses
  static GranularidadSerie paraRango(RangoPeriodo rango) {
    final dias = rango.dias;
    if (dias <= 45) return GranularidadSerie.dia;
    if (dias <= 315) return GranularidadSerie.semana;
    return GranularidadSerie.mes;
  }

  /// Inicio de la cubeta a la que pertenece [fecha].
  ///
  /// Siempre se construye con `DateTime(y, m, d)` y nunca sumando
  /// `Duration`: la aritmética por componentes es la única que no se
  /// desalinea en un cambio de horario, y además normaliza la hora a
  /// medianoche — un movimiento registrado a las 23:50 tiene que caer
  /// en el mismo cubo que uno de las 00:10 del mismo día.
  DateTime cubetaDe(DateTime fecha) => switch (this) {
        GranularidadSerie.dia => DateTime(fecha.year, fecha.month, fecha.day),
        // `weekday` es 1 = lunes: restar `weekday - 1` días deja
        // siempre el lunes de esa semana.
        GranularidadSerie.semana => DateTime(fecha.year, fecha.month, fecha.day - (fecha.weekday - 1)),
        GranularidadSerie.mes => DateTime(fecha.year, fecha.month),
      };

  /// La cubeta siguiente a [cubeta].
  DateTime siguiente(DateTime cubeta) => switch (this) {
        GranularidadSerie.dia => DateTime(cubeta.year, cubeta.month, cubeta.day + 1),
        GranularidadSerie.semana => DateTime(cubeta.year, cubeta.month, cubeta.day + 7),
        GranularidadSerie.mes => DateTime(cubeta.year, cubeta.month + 1),
      };

  /// Todas las cubetas que cubren [rango], en orden y SIN huecos.
  ///
  /// Que incluya las cubetas vacías es deliberado: una gráfica temporal
  /// que se salta los días sin movimiento miente sobre el ritmo del
  /// negocio — un mes con tres ventas se vería igual de denso que uno
  /// con noventa.
  List<DateTime> cubetas(RangoPeriodo rango) {
    final cubetas = <DateTime>[];
    final ultima = cubetaDe(rango.fin);
    var actual = cubetaDe(rango.inicio);
    // Cota dura: aun con un rango absurdo, la lista no puede crecer sin
    // control y colgar la UI.
    while (!actual.isAfter(ultima) && cubetas.length < 600) {
      cubetas.add(actual);
      actual = siguiente(actual);
    }
    return cubetas;
  }
}
