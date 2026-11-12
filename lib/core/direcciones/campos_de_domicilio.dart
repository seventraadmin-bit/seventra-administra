import 'package:flutter/material.dart';

import 'direccion.dart';

/// Un campo de un domicilio, **con su clave del servidor, su etiqueta y cómo se lee de
/// una [Direccion]**, dicho una sola vez.
///
/// ## Por qué esto es una tabla y no diez bloques
///
/// Porque los diez aparecen en **cinco sitios** de la misma pantalla —el formulario, el
/// volcado al cargar, la lectura al guardar, la comparación de un choque y la mezcla de
/// su resultado— y escribirlos por separado es exactamente cómo uno de los cinco se
/// queda sin un campo. El expediente de una sucursal ya lo tuvo: al añadir el nodo de
/// foco habrían sido diez sitios donde emparejar a mano la clave del error con la del
/// nodo, y **dos claves escritas por separado es cómo un campo se queda sin señalar sin
/// que nada falle** —el error se pintaría en «Colonia» y la vista iría a «Municipio»—.
@immutable
class CampoDeDomicilio {
  const CampoDeDomicilio({
    required this.clave,
    required this.etiqueta,
    required this.leerDe,
    this.comoSeLlama,
    this.ayuda,
    this.soloDigitos = false,
  });

  /// La clave del servidor, **con el prefijo `address.`**: así es como llegan los
  /// errores por campo y así se nombran los nodos de foco.
  final String clave;

  /// Cómo se llama en pantalla.
  final String etiqueta;

  /// De dónde sale su valor en una [Direccion] ya construida.
  final String? Function(Direccion) leerDe;

  /// Cómo se nombra en el aviso de que falta —«la calle»—, **o nulo si es opcional**.
  ///
  /// ⚠️ **ES LO QUE DECIDE SI ES OBLIGATORIO**, y es un solo dato y no dos: un `bool
  /// obligatorio` más un texto habrían podido contradecirse —obligatorio sin nombre, o un
  /// nombre que nunca se usa—, y entonces un campo obligatorio se quedaría sin marcar
  /// **sin que nada falle**. Es la misma razón por la que la clave del servidor y la del
  /// nodo de foco son el mismo campo.
  ///
  /// Va en minúsculas y con artículo porque el mensaje se arma con él: `Falta $x.`, que es
  /// **palabra por palabra** lo que contesta el servidor.
  final String? comoSeLlama;

  /// La letra chica del campo, o nula.
  final String? ayuda;

  /// Si el teclado del móvil debe abrir en números. Sólo el código postal.
  final bool soloDigitos;

  /// La clave **sin el prefijo**: `street`. La necesita quien compone la clave del
  /// servidor a mano, como la comparación de un choque.
  String get claveCorta => clave.substring('address.'.length);
}

/// **LOS DIEZ CAMPOS DE UN DOMICILIO, EN EL ORDEN EN QUE SE PINTAN.**
///
/// Los seis primeros son los obligatorios **cuando se escribe alguno** —y el servidor
/// los impone en ese orden, así que el formulario los pide en el mismo—; los otros
/// cuatro son opcionales siempre.
final List<CampoDeDomicilio> camposDeDomicilio = [
  CampoDeDomicilio(
    clave: 'address.street',
    etiqueta: 'Calle',
    comoSeLlama: 'la calle',
    leerDe: (d) => d.calle,
  ),
  CampoDeDomicilio(
    clave: 'address.exteriorNumber',
    etiqueta: 'Número exterior',
    comoSeLlama: 'el número exterior',
    leerDe: (d) => d.numeroExterior,
  ),
  CampoDeDomicilio(
    clave: 'address.interiorNumber',
    etiqueta: 'Número interior',
    leerDe: (d) => d.numeroInterior,
    ayuda: 'Opcional.',
  ),
  CampoDeDomicilio(
    clave: 'address.neighborhood',
    etiqueta: 'Colonia',
    comoSeLlama: 'la colonia',
    leerDe: (d) => d.colonia,
  ),
  CampoDeDomicilio(
    clave: 'address.municipality',
    etiqueta: 'Municipio',
    comoSeLlama: 'el municipio o alcaldía',
    leerDe: (d) => d.municipio,
  ),
  CampoDeDomicilio(
    clave: 'address.city',
    etiqueta: 'Ciudad',
    leerDe: (d) => d.ciudad,
    ayuda: 'Opcional.',
  ),
  CampoDeDomicilio(
    clave: 'address.state',
    etiqueta: 'Estado',
    comoSeLlama: 'el estado',
    leerDe: (d) => d.estado,
  ),
  CampoDeDomicilio(
    clave: 'address.postalCode',
    etiqueta: 'Código postal',
    comoSeLlama: 'el código postal',
    leerDe: (d) => d.codigoPostal,
    ayuda: 'Cinco dígitos.',
    soloDigitos: true,
  ),
  CampoDeDomicilio(
    clave: 'address.country',
    etiqueta: 'País',
    leerDe: (d) => d.pais,
    ayuda: 'Opcional.',
  ),
  CampoDeDomicilio(
    clave: 'address.landmarks',
    etiqueta: 'Referencias',
    leerDe: (d) => d.referencias,
    ayuda: 'Opcional. Entre qué calles, frente a qué.',
  ),
];

/// Lo que una persona tiene escrito en los diez campos de un domicilio.
///
/// **POSEE SUS `TextEditingController` Y LOS LIBERA**, y de eso depende que no haya que
/// acordarse: quien lo use llama a [dispose] una vez, no diez. En este proyecto olvidar
/// uno ya costó una sesión de depuración, y `Future.delayed(300ms)` para «esperar la
/// animación» está **prohibido**.
///
/// ## Qué valida, y por qué cambió el 11 de noviembre de 2026
///
/// Hasta ese día aquí **no se validaba nada**, con este argumento escrito: «quien decide
/// si un domicilio sirve es el servidor, y adelantarlo aquí dejaría dos reglas que pueden
/// divergir».
///
/// 🚫 **LO QUE ESO PRODUCÍA EN PANTALLA:** el servidor de Clientes y Servicios contesta
/// **el primer campo que falta y para** —«Falta el estado.»—, así que guardar un
/// domicilio incompleto obligaba a **un guardado por campo que falta**, descubriéndolos
/// de uno en uno en un aviso abajo. El dueño lo vio con «Falta el estado» y después
/// «Falta el código postal». Tres campos vacíos son tres viajes al servidor y tres avisos
/// que se van solos.
///
/// **Lo que se valida ahora es la PRESENCIA de los obligatorios, y nada más:** los seis
/// campos en cuanto hay algo escrito, y que el código postal sean cinco dígitos. Es un
/// **subconjunto** de lo que el servidor exige, con **sus mismas palabras**, y por eso no
/// puede contradecirlo: lo que esto marca, el servidor lo habría rechazado igual.
///
/// ⚠️ **Y EL SERVIDOR SIGUE SIENDO LA AUTORIDAD.** Esto no decide si un domicilio sirve
/// —no mira longitudes máximas, ni nada que el servidor sume mañana—: decide **qué se
/// puede señalar antes de molestar a nadie**. Lo que no esté aquí llega como respuesta y
/// se pinta igual que siempre.
///
/// [faltantes] es lo que esto contesta.
class CamposDeDomicilio {
  CamposDeDomicilio() {
    for (final campo in camposDeDomicilio) {
      _porClave[campo.clave] = TextEditingController();
    }
  }

  final Map<String, TextEditingController> _porClave = {};

  /// El controlador de un campo. Lanza si la clave no es de los diez, y es lo
  /// correcto: una clave inventada es un error de programación, no un dato.
  TextEditingController operator [](String clave) => _porClave[clave]!;

  /// Los diez, para quien necesite recorrerlos.
  Iterable<TextEditingController> get todos => _porClave.values;

  /// ¿Hay **algo** escrito?
  ///
  /// Es la pregunta que distingue «sin domicilio» —válido— de «un domicilio a medio
  /// llenar», que el servidor rechaza nombrando el primer campo que falta.
  bool get hayAlgo => todos.any((c) => c.text.trim().isNotEmpty);

  /// Los obligatorios que faltan, **por clave del servidor**, listos para señalar.
  ///
  /// **Vacío si no hay nada escrito**, porque «sin domicilio» es válido en un cliente y
  /// en una sucursal: quien lo exija —un servicio— lo dice él, que es quien conoce su
  /// regla. Esto sólo responde «de lo que hay, qué falta».
  ///
  /// Los mensajes son **los del servidor, palabra por palabra**, y eso importa: si algún
  /// día una respuesta llegara igualmente, quien captura no leería dos redacciones
  /// distintas del mismo problema y pensaría que son dos problemas.
  Map<String, String> get faltantes => hayAlgo ? _faltantes() : const {};

  /// Los obligatorios que faltan **en una pantalla donde el domicilio es obligatorio**.
  ///
  /// Es [faltantes] sin la excepción del formulario vacío, y existe por un caso real: un
  /// **servicio** no puede no tener domicilio operativo, así que dejarlo entero en blanco
  /// no es «sin domicilio», es un domicilio al que le faltan seis campos. Antes se
  /// señalaba sólo la calle con una frase explicativa; con esto se marcan los seis, que es
  /// lo que de verdad falta por capturar.
  Map<String, String> get faltantesSiendoObligatorio => _faltantes();

  Map<String, String> _faltantes() {
    final faltan = <String, String>{};

    for (final campo in camposDeDomicilio) {
      // SIN NOMBRE NO ES OBLIGATORIO: la tabla es la que lo dice, y es un solo dato.
      if (campo.comoSeLlama == null) continue;

      if (valorDe(campo.clave) == null) {
        faltan[campo.clave] = 'Falta ${campo.comoSeLlama}.';
      }
    }

    // EL CÓDIGO POSTAL TIENE DOS REGLAS Y SON DISTINTAS: que esté —arriba— y que sean
    // cinco dígitos. Sólo se mira la segunda si pasó la primera: «falta» y «no sirve» en
    // el mismo campo a la vez no se podrían pintar, y además la de arriba es la que hay
    // que atender.
    final cp = valorDe('address.postalCode');

    // ⚠️ UNA EXPRESIÓN Y NO `int.tryParse`: `+1234` y `-1234` miden cinco y **se parsean
    // bien**, así que un `tryParse` los dejaría pasar y el servidor los rechazaría
    // después. Lo que se exige son cinco dígitos, que es lo que el servidor comprueba con
    // `char.IsAsciiDigit`.
    if (cp != null && !RegExp(r'^[0-9]{5}$').hasMatch(cp)) {
      faltan['address.postalCode'] =
          'El código postal son 5 dígitos, por ejemplo 50000.';
    }

    return faltan;
  }

  /// Pone un domicilio en el formulario, o lo vacía si es nulo.
  void volcar(Direccion? d) {
    for (final campo in camposDeDomicilio) {
      _porClave[campo.clave]!.text = d == null ? '' : campo.leerDe(d) ?? '';
    }
  }

  /// Pone valores **por clave del servidor**, para el resultado de una mezcla.
  ///
  /// Lo que no venga en el mapa se vacía: ese mapa es el resultado completo de resolver
  /// un choque, así que una clave ausente significa «este campo queda vacío» y no «no
  /// lo toques».
  void volcarPorClave(Map<String, String?> valores) {
    for (final campo in camposDeDomicilio) {
      _porClave[campo.clave]!.text = valores[campo.clave] ?? '';
    }
  }

  /// Lo escrito en un campo, recortado, **o nulo si está vacío**.
  String? valorDe(String clave) {
    final texto = _porClave[clave]!.text.trim();

    return texto.isEmpty ? null : texto;
  }

  /// El domicilio que hay escrito, **o nulo si no hay nada**.
  ///
  /// ⚠️ **LOS OBLIGATORIOS SE MANDAN TAL CUAL, aunque estén vacíos.** No se devuelve
  /// nulo por un domicilio incompleto: quien decide es el servidor, y su mensaje nombra
  /// el campo que falta —«Falta la colonia.»—, que es justo lo que la persona necesita
  /// leer. Adivinarlo aquí convertiría un error preciso en un formulario que no manda
  /// nada y no dice por qué.
  Direccion? get direccion {
    if (!hayAlgo) return null;

    return Direccion(
      calle: _porClave['address.street']!.text.trim(),
      numeroExterior: _porClave['address.exteriorNumber']!.text.trim(),
      colonia: _porClave['address.neighborhood']!.text.trim(),
      municipio: _porClave['address.municipality']!.text.trim(),
      estado: _porClave['address.state']!.text.trim(),
      codigoPostal: _porClave['address.postalCode']!.text.trim(),
      numeroInterior: valorDe('address.interiorNumber'),
      ciudad: valorDe('address.city'),
      pais: valorDe('address.country'),
      referencias: valorDe('address.landmarks'),
    );
  }

  /// ¿Lo escrito es lo mismo que esto?
  ///
  /// La usa la detección de cambios sin guardar (D-56), y **compara contra lo cargado,
  /// nunca contra un «se tocó algo»**: escribir una letra y borrarla no es un cambio, y
  /// una pregunta que sale por nada enseña a contestar el diálogo sin leerlo.
  bool igualA(Direccion? d) {
    for (final campo in camposDeDomicilio) {
      final escrito = valorDe(campo.clave);
      final cargado = d == null ? null : _vacioEsNulo(campo.leerDe(d));

      if (escrito != cargado) return false;
    }

    return true;
  }

  static String? _vacioEsNulo(String? texto) {
    final t = (texto ?? '').trim();

    return t.isEmpty ? null : t;
  }

  void dispose() {
    for (final c in todos) {
      c.dispose();
    }
  }
}
