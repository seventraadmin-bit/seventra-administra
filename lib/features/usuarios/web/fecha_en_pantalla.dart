/// Cómo se escribe una fecha del servidor en la pantalla de Administra.
///
/// ## Por qué existe, y qué problema NO resuelve
///
/// Había **dos copias** de los nombres de los meses —la bitácora y Puestos—, y la
/// tercera iba a nacer con la fecha de alta de una empresa. Es el mismo caso que D-11
/// en el servidor: una copia no se nota al escribirla, se nota cuando hay que cambiar
/// algo en todas.
///
/// ⚠️ **ESTO FORMATEA UN INSTANTE, NO CALCULA UN DÍA DE NEGOCIO.** Son dos cosas
/// distintas y conviene no confundirlas:
///
///  · **mostrar** cuándo pasó algo se hace en la hora de quien lo lee —`toLocal()`—,
///    porque eso es lo que esa persona quiere saber;
///  · **proponer «hoy»** para una fecha de negocio NO puede salir del reloj del
///    navegador: México tiene varias zonas —Cancún −05, el Pacífico −07, Tijuana
///    −08— y alguien fuera de la zona centro propondría un día distinto al que el
///    servidor va a leer. Eso va con el desplazamiento **fijo** de la Ciudad de
///    México, igual que `FechaDeNegocio` del backend, y es la deuda **D-55**.
library;

const List<String> _meses = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

String _dos(int n) => n.toString().padLeft(2, '0');

/// `3/oct/2026`, **en la zona de quien mira**.
///
/// El mes va en letras a propósito: `3/10/2026` y `10/3/2026` se leen distinto según
/// de dónde sea quien lo lee, y una fecha no debería necesitar contexto.
String fechaCorta(DateTime instante) {
  final local = instante.toLocal();

  return '${local.day}/${_meses[local.month - 1]}/${local.year}';
}

/// `18/oct/2026 13:45`. Para la bitácora, donde la hora **es parte del dato**.
String fechaYHora(DateTime instante) {
  final local = instante.toLocal();

  return '${_dos(local.day)}/${_meses[local.month - 1]}/${local.year} '
      '${_dos(local.hour)}:${_dos(local.minute)}';
}
