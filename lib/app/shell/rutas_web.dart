/// Las direcciones de Administra en la web, y cómo se leen.
///
/// **POR QUÉ ESTE ARCHIVO ES PURO.** Traducir una dirección a «qué apartado, qué
/// pestaña y qué se abrió dentro» es la regla que el router aplica en cada navegación
/// y que el rastro lee en cada repintado. Separarla del router la deja probada sin
/// montar una sola pantalla, y deja el router con una sola responsabilidad: decidir
/// quién puede estar dónde.
///
/// **LA FORMA ES SIEMPRE LA MISMA**, y no se inventa por apartado:
///
/// ```
/// /<apartado>/<pestaña>/<lo que se abrió dentro>
/// ```
///
/// El apartado y la pestaña **no se nombran aquí**: salen del registro de
/// [apartados.apartados], que ya tiene la ruta de cada apartado y el `id` de cada
/// pestaña. Este archivo sólo parte la cadena y la vuelve a juntar.
library;

import 'apartados_web.dart' as apartados;

/// Las dos direcciones que no son de un apartado.
abstract final class RutaDeEntrada {
  /// El login. Lo que se ve cuando no hay sesión.
  static const entrar = '/entrar';

  /// El selector de empresa, que **sólo aparece con varias** (E1-B).
  static const elegirEmpresa = '/elegir-empresa';
}

/// Lo que una dirección dice.
///
/// **La empresa NO está aquí, y es deliberado** (E1-B): con qué empresa se trabaja es
/// estado de la sesión, no parte de la dirección. Un enlace con la empresa dentro
/// sería un enlace que cambia de empresa al abrirlo, y cambiar de empresa se hace
/// **sólo desde la barra inferior**.
final class UbicacionWeb {
  const UbicacionWeb({required this.apartado, this.pestana, this.dentro});

  /// La ruta del apartado, con su barra: `/organizacion`.
  final String apartado;

  /// El `id` de la pestaña, o nulo si la dirección no llega a tanto.
  final String? pestana;

  /// Los segmentos que vienen **después** de la pestaña, si hay.
  ///
  /// Para `/organizacion/sucursales/tipos` es `['tipos']`; para
  /// `/organizacion/sucursales/<id>/expediente` es `['<id>', 'expediente']`. Se
  /// guardan tal cual porque quien sabe interpretarlos es la pantalla de la pestaña,
  /// no esta clase.
  final List<String>? dentro;

  /// La dirección completa, que es lo que se le pasa al router.
  String get direccion => [
    apartado,
    if (pestana != null) pestana!,
    ...?dentro,
  ].join('/').replaceFirst('//', '/');

  @override
  String toString() => direccion;
}

/// Lee una dirección. Devuelve nulo si no es de un apartado conocido.
///
/// **UN APARTADO DESCONOCIDO ES NULO Y NO UNA EXCEPCIÓN**: una dirección escrita a
/// mano llega aquí tal cual, y reventar sería convertir una errata en una pantalla
/// roja. Quien recibe el nulo decide a dónde mandar a esa persona.
UbicacionWeb? leerUbicacion(String direccion) {
  final partes = direccion
      .split('?')
      .first
      .split('/')
      .where((p) => p.isNotEmpty)
      .toList();

  if (partes.isEmpty) return null;

  final ruta = '/${partes.first}';

  final existe = apartados.apartados.any((a) => a.ruta == ruta);
  if (!existe) return null;

  return UbicacionWeb(
    apartado: ruta,
    pestana: partes.length > 1 ? partes[1] : null,
    dentro: partes.length > 2 ? partes.sublist(2) : null,
  );
}

/// La dirección de una pestaña: `/organizacion/sucursales`.
String direccionDe(String rutaDelApartado, String pestanaId) =>
    '$rutaDelApartado/$pestanaId';

/// Cómo se llama en el rastro lo que se abrió **dentro** de una pestaña.
///
/// **POR QUÉ ESTA TABLA EXISTE, Y POR QUÉ ES PEQUEÑA A PROPÓSITO.** El rastro sale de
/// la dirección, así que alguien tiene que traducir `tipos` a «Tipos de sucursal». Lo
/// hace una tabla y no cada pantalla porque antes lo hacía cada pantalla —avisando
/// hacia arriba con un callback— y era la deuda D-39: quien sabe dónde estás es la
/// dirección, no un aviso que alguien tiene que acordarse de mandar.
///
/// **Lo que no está en la tabla no sale en el rastro**, y es lo correcto: un
/// identificador no se le enseña a nadie. Para `/sucursales/<id>/expediente` el rastro
/// dice «Expediente», no el UUID.
String? nombreDeLoDeDentro(String pestanaId, List<String>? dentro) {
  if (dentro == null || dentro.isEmpty) return null;

  // SE MIRA EL ÚLTIMO SEGMENTO, no el primero: en `<id>/expediente` lo que se abrió es
  // el expediente, y el id es de qué.
  return switch ((pestanaId, dentro.last)) {
    ('sucursales', 'tipos') => 'Tipos de sucursal',
    ('sucursales', 'expediente') => 'Expediente',
    ('clientes', 'editar') => 'Editar',
    _ => null,
  };
}
