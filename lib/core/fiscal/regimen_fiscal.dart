/// Un régimen fiscal del catálogo `c_RegimenFiscal` del SAT.
///
/// ## Por qué vive en `core/fiscal/` y no en el modelo del expediente
///
/// Porque **es un dato público de plataforma, no de ninguna empresa**: el catálogo es el
/// mismo para todas. Nació dentro de `features/organizacion/web/modelos/expediente.dart`
/// porque el expediente fiscal de la empresa fue el primero en necesitarlo, y en C1 lo
/// necesitó también la **entidad fiscal de un cliente** — que es otra feature.
///
/// Con el tipo dentro de Organización, Comercial sólo tenía dos salidas: importar de otra
/// feature, o escribir su propio modelo del mismo catálogo. La segunda es la mala: dos
/// lecturas del mismo JSON que pueden interpretar `selectable` de dos maneras.
library;

class RegimenFiscal {
  const RegimenFiscal({
    required this.codigo,
    required this.nombre,
    required this.personaFisica,
    required this.personaMoral,
    required this.seleccionable,
  });

  factory RegimenFiscal.deJson(Map<String, dynamic> json) => RegimenFiscal(
    codigo: json['code'] as String,
    nombre: json['name'] as String,
    personaFisica: json['personaFisica'] as bool,
    personaMoral: json['personaMoral'] as bool,
    seleccionable: json['selectable'] as bool,
  );

  final String codigo;
  final String nombre;
  final bool personaFisica;
  final bool personaMoral;

  /// ¿Se puede elegir hoy? Un régimen **retirado por el SAT** llega con `false`, y quien
  /// ya lo tenía **lo conserva**: su tarjeta fiscal sigue diciendo la verdad. Lo que no se
  /// puede es elegirlo para algo nuevo.
  final bool seleccionable;

  /// `601 · General de Ley Personas Morales`.
  String get etiqueta => '$codigo · $nombre';
}
