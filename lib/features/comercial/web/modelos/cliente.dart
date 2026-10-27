import '../../../../core/fechas/dia_de_negocio.dart';

/// Un cliente, tal como lo devuelve `GET /companies/{id}/clients/{cid}`.
///
/// ## El cliente es la MARCA, no la razón social
///
/// «Sportium» es el cliente; su razón social y su RFC viven en sus **entidades
/// fiscales**, y puede tener varias —Sportium factura distinto por club—. Es la regla
/// del dominio que más se confunde al llegar desde el escritorio, y la frontera
/// congelada la dice en una línea: **`Client != FiscalEntity`**.
///
/// Modelo plano y propio de la web, igual que `Area` y `Sucursal`: el dominio del
/// escritorio habla tipos generados por Drift y aquí no hay Drift.
class Cliente {
  const Cliente({
    required this.id,
    required this.codigo,
    required this.nombreComercial,
    required this.estatus,
    required this.inicioDeLaRelacion,
    required this.observaciones,
    required this.actualizadoEn,
  });

  factory Cliente.deJson(Map<String, dynamic> json) => Cliente(
    id: json['id'] as String,
    codigo: json['code'] as String,
    nombreComercial: json['commercialName'] as String,
    estatus: json['status'] as String,
    inicioDeLaRelacion: DiaDeNegocio.deTexto(json['startedOn'] as String?),
    observaciones: json['notes'] as String?,
    actualizadoEn: DateTime.parse(json['updatedAt'] as String),
  );

  final String id;

  /// `CLI-000004`. **Lo asigna el servidor y es inmutable**: no viaja en ningún cuerpo
  /// de petición, porque dejar que el cliente lo eligiera convertiría la referencia
  /// humana en algo que dos capturas pueden duplicar.
  final String codigo;

  final String nombreComercial;

  /// El código del servidor: `active`, `suspended` o `terminated`.
  ///
  /// ⚠️ **SE GUARDA EL CÓDIGO CRUDO Y NO UN `enum`**, y es deliberado. Con un `enum`,
  /// un valor que esta build no conozca —porque el servidor sea más nuevo— sería una
  /// excepción al leer la lista entera, o peor, un `_ => activo` que enseñaría como
  /// activo a un cliente que no lo está. Lo que hay es [estado], que devuelve nulo si no
  /// lo reconoce, y entonces la pantalla enseña el código tal cual: menos bonito que una
  /// insignia, y nunca falso.
  final String estatus;

  /// Desde cuándo es cliente. **No es la fecha de captura**, y el servidor la exige
  /// precisamente por eso: rellenarla sola convertiría una laguna en un hecho falso que
  /// después nadie distingue del real.
  ///
  /// Nula sólo si el servidor mandara algo que no es una fecha; no es un estado del
  /// dominio.
  final DiaDeNegocio? inicioDeLaRelacion;

  final String? observaciones;
  final DateTime actualizadoEn;

  /// El estatus reconocido, o **nulo** si llegó uno que esta build no conoce.
  EstatusDeCliente? get estado => EstatusDeCliente.deCodigo(estatus);
}

/// Una fila del listado: el cliente **y lo que se enseña a su lado**.
///
/// ## Por qué es un tipo aparte de [Cliente] y no el mismo con campos nulos
///
/// Porque es lo que el servidor decidió, y por una razón que vale igual aquí: el cliente
/// que devuelve una ficha **no trae estos conteos**, y publicarlos en nulo haría que la
/// pantalla no pudiera distinguir «cero servicios» de «esta respuesta no los trae».
/// **Ausencia nunca es cero.**
class ClienteEnLista {
  const ClienteEnLista({
    required this.cliente,
    required this.ubicacion,
    required this.serviciosActivos,
    required this.serviciosSuspendidos,
  });

  factory ClienteEnLista.deJson(Map<String, dynamic> json) => ClienteEnLista(
    cliente: Cliente.deJson(json),
    ubicacion: json['location'] as String?,
    serviciosActivos: json['activeServices'] as int,
    serviciosSuspendidos: json['suspendedServices'] as int,
  );

  final Cliente cliente;

  /// «Municipio, Estado» del domicilio de referencia, **ya compuesta por el servidor**,
  /// o nula.
  ///
  /// Nula significa **«sin domicilio de referencia»**, y cómo se dice eso en pantalla
  /// —«No registrada»— es del idioma de la interfaz, no del contrato.
  final String? ubicacion;

  /// Cuántos servicios **activos**. Es la columna «Servicios» del escritorio, que
  /// tampoco cuenta los suspendidos ni los terminados.
  final int serviciosActivos;

  /// Cuántos suspendidos. Hoy no se pinta en una columna propia —el escritorio no la
  /// tiene— y llega porque el servidor lo manda; la ficha sí lo usa.
  final int serviciosSuspendidos;
}

/// Los **tres** estatus de un cliente en la nube, con su código y su nombre.
///
/// ## Por qué tres y no los cinco del escritorio — DECISIÓN DEL DUEÑO
///
/// El escritorio tiene cinco: Prospecto, Activo, Suspendido, Terminado y Descartado, y
/// **todo cliente nace Prospecto**. Aquí el alta nace **activo** y la pantalla no habla
/// de prospectos, porque la arquitectura congelada separa **`Client` de `Prospect`**
/// —son dos cosas, no dos estados de una— y el Prospect llega en **5D.10F** con el CRM,
/// antes de que Administra salga a producción (CP-15).
///
/// No es un olvido ni una simplificación: añadir «Prospecto» y «Descartado» al `CHECK`
/// del cliente dejaría **dos sitios donde vive un prospecto**, y la importación del
/// escritorio tendría que decidir fila por fila a cuál de los dos va. Con tres, hay una
/// sola respuesta: un prospecto es un Prospect.
enum EstatusDeCliente {
  activo('active', 'Activo'),
  suspendido('suspended', 'Suspendido'),
  terminado('terminated', 'Terminado');

  const EstatusDeCliente(this.codigo, this.nombre);

  /// El código del servidor. Es el que viaja; el nombre es para la pantalla.
  final String codigo;

  final String nombre;

  /// El estatus de un código, o **nulo** si no es ninguno de los tres.
  ///
  /// Nulo y no una excepción: ver el comentario de [Cliente.estatus].
  static EstatusDeCliente? deCodigo(String codigo) {
    for (final e in values) {
      if (e.codigo == codigo) return e;
    }

    return null;
  }

  /// ¿Es una relación **terminada**?
  ///
  /// Es la frontera del chip «Vigentes / Finalizados» del escritorio, donde
  /// «Finalizados» eran Terminado **o Descartado**. Sin Descartado es un solo estatus, y
  /// por eso la pregunta vive aquí y no como una lista escrita en la pantalla: el día que
  /// haya otro estatus final, se añade en un sitio.
  bool get esFinalizada => this == terminado;
}
