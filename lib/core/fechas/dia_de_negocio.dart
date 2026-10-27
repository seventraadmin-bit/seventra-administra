/// **EL «HOY» DE ADMINISTRA, Y EL ÚNICO SITIO QUE LO CALCULA** (deuda D-55).
///
/// ## Por qué no sirve el reloj del navegador
///
/// Porque **México tiene varias zonas**: Cancún está en −05, el Pacífico en −07 y
/// Tijuana en −08/−07. El servidor decide el día de negocio con un desplazamiento
/// **fijo** de −06:00 —`FechaDeNegocio` del backend—, así que un «hoy» sacado de la hora
/// local propondría, para alguien en Cancún, **un día distinto al que el servidor va a
/// leer** durante una hora cada día, y en Tijuana durante dos. Se notaría una vez al mes
/// y parecería un error de captura.
///
/// ## Y tampoco sirve el día UTC
///
/// Es el error que el dueño encontró en el servidor el 25 de octubre de 2026, copiado
/// en **ocho** sitios: de las 18:00 a las 23:59 de la Ciudad de México **el día UTC ya
/// es el siguiente**. Un alta capturada a las ocho de la noche nacería con la fecha de
/// mañana, y de día funcionaría perfectamente.
///
/// Por eso aquí se parte de un instante en UTC —que es un instante, no un día— y se le
/// aplica el desplazamiento antes de quedarse con el año, el mes y el día.
///
/// ## Qué NO es esto
///
/// **No formatea un instante para la pantalla.** Decir cuándo pasó algo se hace en la
/// hora de quien lo lee —`fechaCorta`, `fechaYHora`— y eso sigue siendo correcto: la
/// bitácora responde «cuándo», no «qué día de negocio». Confundirlos es lo que hace que
/// un ayudante acabe usándose para las dos cosas y no sirva para ninguna.
library;

/// El desplazamiento fijo de la Ciudad de México.
///
/// **Fijo y no un cálculo de zona**, igual que en el servidor: México suprimió el
/// horario de verano en 2022, y un desplazamiento que dependiera de la fecha volvería a
/// abrir la puerta a que el cliente y el servidor discrepen un día dos veces al año.
const Duration _desplazamientoDeLaCiudadDeMexico = Duration(hours: -6);

/// Un **día**, no un instante: año, mes y día, sin hora y sin zona.
///
/// ## Por qué es un tipo y no un `DateTime`
///
/// Porque un `DateTime` lleva hora y zona, y eso es exactamente lo que se presta a
/// confusión: `DateTime(2026, 10, 26)` es la medianoche **local** de quien lo construyó,
/// así que dos navegadores en zonas distintas producen dos instantes para el mismo día.
/// En cuanto uno de los dos se convierte a UTC —o se compara con otro— el día cambia sin
/// que nada falle.
///
/// Con un tipo propio, la conversión ocurre **en los bordes y a la vista**: [de] al
/// entrar, [enTexto] al salir hacia el servidor, y [comoFechaLocal] sólo para el
/// selector de fechas, que es el único que necesita un `DateTime`.
class DiaDeNegocio {
  const DiaDeNegocio(this.anio, this.mes, this.dia);

  /// El día de negocio de **este instante**.
  ///
  /// Recibe el instante en vez de leerlo del reloj para poder probarse: las dos pruebas
  /// que D-55 exige —las 23:30 de la Ciudad de México, y el mismo instante visto desde
  /// Cancún y Tijuana— no se pueden escribir sobre una función que mira el reloj.
  ///
  /// **Un instante es un instante**: da lo mismo si llega en UTC o con el
  /// desplazamiento de otra zona, porque lo primero que se hace es normalizarlo. Eso es
  /// lo que hace que la respuesta no dependa de dónde esté el navegador.
  factory DiaDeNegocio.de(DateTime instante) {
    final enLaCiudadDeMexico = instante.toUtc().add(
      _desplazamientoDeLaCiudadDeMexico,
    );

    return DiaDeNegocio(
      enLaCiudadDeMexico.year,
      enLaCiudadDeMexico.month,
      enLaCiudadDeMexico.day,
    );
  }

  /// Lo que el servidor manda en un `DateOnly`: `2026-10-26`.
  ///
  /// Devuelve nulo si el texto no tiene esa forma. **Nulo y no una excepción**: una
  /// respuesta con una fecha rara no debe reventar una lista entera, y quien recibe el
  /// nulo puede enseñar «sin fecha» — que es menos que la verdad, pero no es falso.
  static DiaDeNegocio? deTexto(String? texto) {
    if (texto == null) return null;

    final partes = texto.split('T').first.split('-');
    if (partes.length < 3) return null;

    final anio = int.tryParse(partes[0]);
    final mes = int.tryParse(partes[1]);
    final dia = int.tryParse(partes[2]);

    if (anio == null || mes == null || dia == null) return null;

    return DiaDeNegocio(anio, mes, dia);
  }

  /// El día de hoy **para el negocio**, que es el de la Ciudad de México.
  ///
  /// ⚠️ `DateTime.timestamp()` y no `DateTime.now().toUtc()`, que es el patrón que el
  /// candado de `test/core/fechas_de_negocio_test.dart` prohíbe. **No es una manera de
  /// sortearlo**: el candado vigila los dos, y este archivo es su única excepción
  /// precisamente porque es el único que aplica el desplazamiento después.
  static DiaDeNegocio hoy() => DiaDeNegocio.de(DateTime.timestamp());

  final int anio;
  final int mes;
  final int dia;

  /// Como lo espera el servidor en un `DateOnly`.
  String get enTexto =>
      '${anio.toString().padLeft(4, '0')}-'
      '${mes.toString().padLeft(2, '0')}-'
      '${dia.toString().padLeft(2, '0')}';

  /// La medianoche **local** de este día, que es lo único que `showDatePicker` entiende.
  ///
  /// **Sólo para el selector.** No se manda al servidor ni se compara con otro instante:
  /// es un `DateTime` cuyo valor depende de la zona del navegador, y eso es correcto
  /// aquí —el calendario se pinta en la pantalla de quien lo usa— y es un error en
  /// cualquier otro sitio.
  DateTime get comoFechaLocal => DateTime(anio, mes, dia);

  /// El día que el selector devolvió. **La vuelta de [comoFechaLocal]**, y por eso lee
  /// los campos y no convierte nada: el `DateTime` que entrega `showDatePicker` ya es la
  /// medianoche local del día que la persona tocó con el dedo.
  static DiaDeNegocio deFechaLocal(DateTime fecha) =>
      DiaDeNegocio(fecha.year, fecha.month, fecha.day);

  @override
  bool operator ==(Object other) =>
      other is DiaDeNegocio &&
      other.anio == anio &&
      other.mes == mes &&
      other.dia == dia;

  @override
  int get hashCode => Object.hash(anio, mes, dia);

  @override
  String toString() => enTexto;
}
