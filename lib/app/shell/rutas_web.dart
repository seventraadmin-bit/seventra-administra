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
/// dice «Expediente» — y cuando la pantalla ya cargó la sucursal, el nombre lo añade
/// [rastroConNombre], **de los datos y nunca de la URL**.
String? nombreDeLoDeDentro(String pestanaId, List<String>? dentro) {
  if (dentro == null || dentro.isEmpty) return null;

  // SE MIRA EL ÚLTIMO SEGMENTO, no el primero: en `<id>/expediente` lo que se abrió es
  // el expediente, y el id es de qué.
  return switch ((pestanaId, dentro.last)) {
    ('sucursales', 'tipos') => 'Tipos de sucursal',
    ('sucursales', 'expediente') => 'Expediente',
    ('empresa', 'editar') => 'Editar',
    ('empresa', 'administracion') => 'Administración',
    // ⚠️ **CLIENTES NO TIENE PALABRA, Y `editar` SALIÓ DE LA TABLA A PROPÓSITO.**
    //
    // El expediente de un cliente vive en `/comercial/clientes/<id>` —sin una palabra
    // que lo nombre— así que el tercer segmento del rastro es **el cliente**:
    // «Comercial › Clientes › CLI-000004 Sportium», que es lo que el diseño pide. Y en
    // edición sigue siendo el cliente, no «Editar de Sportium», que no es español.
    //
    // En Empresa sí hay palabra y es lo correcto por lo contrario: ahí no hay fila que
    // nombrar —hay una sola empresa y su nombre ya está en la barra— así que lo único
    // que el rastro puede añadir es en qué paso estás.
    _ => null,
  };
}

/// ¿Se honra de verdad lo que la dirección dice que está abierto dentro?
///
/// **POR QUÉ ESTA PREGUNTA EXISTE.** El guardia del router deja pasar los segmentos de
/// dentro sin mirarlos, y está bien: quien sabe interpretarlos es la pantalla. Pero hay
/// **una** dirección que la pantalla puede decidir no abrir, y entonces el rastro no
/// debe nombrarla — un rastro que miente es peor que no tenerlo, y es lo único que dice
/// dónde estás cuando una pantalla vive dentro de otra.
///
/// ⚠️ **LA EXCEPCIÓN TIENE NOMBRE: la administración de empresas pide autoridad de
/// ORGANIZATION**, y el guardia del router no la conoce —sólo entiende permisos de
/// Company—, así que `/organizacion/empresa/administracion` escrita a mano llega hasta
/// la pantalla de Empresa, que sin autoridad enseña la ficha. **No concede nada**: lo
/// que decide sigue siendo la autoridad que confirmó el servidor.
///
/// Vive aquí y no en el portón para poder probarse sin montar una pantalla, que es la
/// misma razón por la que el guardia del router vive fuera del router.
bool seAbreLoDeDentro(
  String pestanaId,
  List<String>? dentro, {
  required bool puedeAdministrarEmpresas,
}) => !(pestanaId == 'empresa' &&
    dentro?.lastOrNull == 'administracion' &&
    !puedeAdministrarEmpresas);

/// El identificador de lo abierto dentro de una pestaña, si la dirección lo lleva.
///
/// Para `/organizacion/sucursales/<id>/expediente` devuelve el `<id>`; para
/// `/comercial/clientes/<id>` y `/comercial/clientes/<id>/editar`, también. Para
/// `/organizacion/sucursales/tipos` devuelve nulo: ahí no hay nada identificado, hay un
/// catálogo.
///
/// ## La regla, y por qué NO es «dos segmentos o más»
///
/// Era eso hasta C1 —`dentro.length >= 2`— y funcionaba mientras toda dirección con id
/// llevara una palabra detrás. El expediente de un cliente rompió la suposición: vive en
/// `…/clientes/<id>`, **un solo segmento**, y con la regla vieja su id no se leía y el
/// rastro no podía nombrarlo.
///
/// La regla es ahora: **un segmento que la tabla sabe nombrar no es un id.** `tipos` es
/// un catálogo, `editar` es un paso; lo que no está en la tabla sólo puede ser una fila.
/// Sale de [nombreDeLoDeDentro], así que hay **una** lista y no dos que puedan discrepar.
///
/// Lo que pasa si alguien añade una palabra de ruta y olvida la tabla: se tomaría por un
/// id, la pantalla no encontraría la fila y volvería a la lista. Se ve y se arregla —que
/// es mejor que lo contrario, un id tratado como palabra y un rastro que miente—.
String? idDeLoDeDentro(String pestanaId, List<String>? dentro) {
  if (dentro == null || dentro.isEmpty) return null;

  if (dentro.length == 1 && nombreDeLoDeDentro(pestanaId, dentro) != null) {
    return null;
  }

  return dentro.first;
}

/// El tercer segmento del rastro, con el **nombre** cuando se conoce.
///
/// ## La regla, decidida por el dueño el 25 de octubre de 2026
///
/// **La URL lleva sólo el id; el nombre sale de los datos que la pantalla ya cargó.**
/// Mientras carga, el rastro dice «Expediente»; cuando la sucursal está en memoria,
/// dice «Expediente de Matriz». Y **vale para todo expediente con ruta hija**, incluido
/// el de un cliente cuando llegue.
///
/// ## Por qué esto NO es la vía que D-39 vino a quitar
///
/// Lo que la pantalla publicaba antes era **dónde estabas** —«se abrió Tipos de
/// sucursal»—, y eso es navegación: un aviso que alguien tenía que acordarse de mandar,
/// y que mentía si se olvidaba. Lo que publica ahora es **cómo se llama una fila que ya
/// tiene cargada**, que es un dato y no un estado: si no llega, el rastro sigue siendo
/// correcto —dice «Expediente»—, sólo menos específico. La diferencia es que aquí no
/// hay nada que pueda quedarse pegado.
///
/// **El nombre NO va en la URL** y es deliberado: sería estado disfrazado de dirección,
/// y además quedaría viejo en cuanto alguien renombrara la sucursal.
///
/// ## Los cuatro casos, y el que C1 añadió
///
/// | Qué es | Nombre | Rastro |
/// |---|---|---|
/// | nulo | nulo | **nulo** — no se abrió nada, el rastro termina en la pestaña |
/// | «Expediente» | nulo | «Expediente» — mientras carga, y es cierto desde el primer instante |
/// | «Expediente» | «Matriz» | «Expediente de Matriz» |
/// | nulo | «CLI-000004 Sportium» | **el nombre** — lo que C1 añadió |
///
/// El último caso devolvía nulo hasta C1, y la razón escrita era buena: «lo que no está
/// en la tabla no sale en el rastro, un identificador no se le enseña a nadie». Pero lo
/// que llega aquí **no es el identificador**: es el nombre de una fila que la pantalla ya
/// cargó, y el expediente de un cliente vive en una dirección sin palabra que nombrarla.
/// Devolver nulo ahí dejaba el rastro en «Comercial › Clientes» estando dentro de un
/// cliente — menos cierto que decir cuál.
String? rastroConNombre(String? queEs, String? nombre) => switch ((queEs, nombre)) {
  (null, null) => null,
  (null, final como) => como,
  (final que, null) => que,
  (final que, final como) => '$que de $como',
};
