/// El domicilio fiscal como **líneas de texto ya formateadas**, en el orden en el que
/// se muestran.
///
/// ## Por qué vive en su propio archivo
///
/// Esta función existía dentro de `tarjeta_fiscal_data.dart`, que **importa
/// `app_database.dart`** —Drift— para los tipos del escritorio. Así que un solo
/// `import` de ese archivo arrastra Drift y **rompe la build web**, sin que nada en la
/// pantalla parezca estar mal. Es el mismo problema que obligó a crear
/// `design_system_web.dart`, y la misma salida: la parte pura se separa y la importan
/// los dos productos.
///
/// **Y es un patrón, no un caso aislado:** las funciones puras del escritorio son
/// reutilizables; sus archivos, no. `LogoEmpresaValidacion.tipoReal` tiene exactamente
/// el mismo problema con `dart:io`.
///
/// ## Qué garantiza
///
/// **Es la única fuente de este formato**, que es la razón por la que el escritorio la
/// escribió así: «función pura, única fuente de este formato para no tener 3 formatos
/// ligeramente distintos entre pantalla, PDF y portapapeles». Ahora son cuatro salidas
/// —se suma la ficha de la web— y el argumento sólo se hace más fuerte.
library;

String? _vacioANull(String? valor) {
  final recortado = valor?.trim();

  return (recortado == null || recortado.isEmpty) ? null : recortado;
}

/// Las cinco líneas del domicilio fiscal, en orden.
///
/// ```
/// Hidalgo 10 INT. 3
/// Centro
/// Toluca, Estado de México
/// C.P. 50000
/// México
/// ```
///
/// **El interior sólo aparece si existe**, y la ciudad sólo si está capturada: un
/// «INT. » suelto o una coma de más se leen como un dato que falta.
List<String> lineasDeDomicilioFiscal({
  required String calle,
  required String numeroExterior,
  required String colonia,
  required String municipio,
  required String estado,
  required String codigoPostal,
  String? numeroInterior,
  String? ciudad,
  String? pais,
}) {
  final interior = _vacioANull(numeroInterior);
  final calleNumero = interior == null
      ? '$calle $numeroExterior'
      : '$calle $numeroExterior INT. $interior';

  final localidad = _vacioANull(ciudad);
  final terceraLinea = [
    if (localidad != null) localidad,
    municipio,
    estado,
  ].join(', ');

  final nacion = _vacioANull(pais);

  return [
    calleNumero,
    colonia,
    terceraLinea,
    'C.P. $codigoPostal',
    // EL PAÍS PUEDE NO ESTAR: es opcional en el expediente, y una línea vacía al final
    // de la tarjeta se lee como un renglón que falta.
    if (nacion != null) nacion,
  ];
}
