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
///    México, igual que `FechaDeNegocio` del backend. **Eso es `DiaDeNegocio`**, en este
///    mismo directorio, y era la deuda D-55 — cerrada con el alta de Clientes.
///
/// ## Por qué vive en `core/fechas/` y ya no en el portón
///
/// Nació en `features/usuarios/web/` porque la bitácora fue la primera pantalla que
/// pintó una fecha, y en C1 lo necesitaban tres features. Su asunto es la fecha, no el
/// portón; y con el archivo dentro de una feature, las otras dos sólo podían importar de
/// ella o escribir otra lista de meses.
library;

import 'dia_de_negocio.dart';

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

/// `1/mar/2025`, para un **día de negocio**.
///
/// ⚠️ **NO PASA POR `DateTime` Y ES LO QUE IMPORTA.** Un [DiaDeNegocio] ya es un día
/// —año, mes y día, sin hora y sin zona—, así que convertirlo a `DateTime` para
/// formatearlo le pondría una medianoche local que después alguien podría llevar a otro
/// reloj. Aquí se leen sus tres campos y se escriben.
String fechaDeNegocioCorta(DiaDeNegocio dia) =>
    '${dia.dia}/${_meses[dia.mes - 1]}/${dia.anio}';

/// `18/oct/2026 13:45`. Para la bitácora, donde la hora **es parte del dato**.
String fechaYHora(DateTime instante) {
  final local = instante.toLocal();

  return '${_dos(local.day)}/${_meses[local.month - 1]}/${local.year} '
      '${_dos(local.hour)}:${_dos(local.minute)}';
}
