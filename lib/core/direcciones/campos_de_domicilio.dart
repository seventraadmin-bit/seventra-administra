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
    leerDe: (d) => d.calle,
  ),
  CampoDeDomicilio(
    clave: 'address.exteriorNumber',
    etiqueta: 'Número exterior',
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
    leerDe: (d) => d.colonia,
  ),
  CampoDeDomicilio(
    clave: 'address.municipality',
    etiqueta: 'Municipio',
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
    leerDe: (d) => d.estado,
  ),
  CampoDeDomicilio(
    clave: 'address.postalCode',
    etiqueta: 'Código postal',
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
/// **No valida nada.** Quien decide si un domicilio sirve es el servidor —seis campos
/// obligatorios en cuanto hay uno escrito, y el código postal de cinco dígitos—, y
/// adelantarlo aquí dejaría dos reglas que pueden divergir. Lo que esto responde es
/// qué hay escrito y cómo se lee.
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
