/// Una sucursal, tal como la devuelve `GET /companies/{id}/branches`.
///
/// **SUCURSAL ES UN DESTINO ADMINISTRATIVO, NO OPERATIVO**, y es la regla del dominio
/// que más se confunde: dónde está dada de alta una persona no es dónde trabaja. Lo
/// operativo es el Servicio, y Personal **nunca** usa Sucursal como sustituto.
///
/// Modelo plano y propio de la web, por la misma razón que [Area]: el dominio del
/// escritorio habla tipos generados por Drift y aquí no hay Drift.
class Sucursal {
  const Sucursal({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.activa,
    required this.tipoId,
    required this.estadoOperativo,
  });

  factory Sucursal.deJson(Map<String, dynamic> json) => Sucursal(
    id: json['id'] as String,
    codigo: json['code'] as String,
    nombre: json['name'] as String,
    // `activa` se DERIVA del estado, igual que en Área: dos campos para un solo
    // hecho acabarían discrepando.
    activa: json['status'] == 'activa',
    tipoId: json['branchTypeId'] as String?,
    estadoOperativo: json['operationalStatus'] as String,
  );

  final String id;
  final String codigo;
  final String nombre;

  /// ¿Está dada de alta? **No es lo mismo que [estadoOperativo]**: una sucursal
  /// activa puede estar temporalmente cerrada, y una inactiva ya no se usa en
  /// absoluto. Son dos preguntas distintas y el servidor las manda por separado.
  final bool activa;

  /// Su tipo —oficina, bodega—, **o nulo**: las sucursales dadas de alta antes de
  /// que existieran los tipos no tienen ninguno.
  ///
  /// Nulo NO es «sin tipo porque alguien lo borró»: la columna es opcional por
  /// historia, y mostrarlo como «—» es más honesto que inventar un tipo.
  final String? tipoId;

  /// `operando`, `cerrada_temporalmente`… Lo manda el servidor y la pantalla lo
  /// traduce; **no se deriva de [activa]**.
  final String estadoOperativo;

  /// La misma sucursal con algún campo cambiado, **para avisar a la lista** de lo que
  /// el expediente acaba de guardar.
  ///
  /// No es un atajo para construir sucursales: lo que se pasa viene de una respuesta
  /// del servidor. Sin esto, la lista seguiría enseñando el nombre viejo hasta que
  /// alguien recargara la pantalla.
  Sucursal copiaCon({
    String? nombre,
    String? tipoId,
    bool? activa,
    String? estadoOperativo,
  }) => Sucursal(
    id: id,
    codigo: codigo,
    nombre: nombre ?? this.nombre,
    activa: activa ?? this.activa,
    // ⚠️ `tipoId` ES ANULABLE DE VERDAD —una sucursal histórica no tiene tipo— así
    // que aquí `null` significa «no lo cambies» y no «bórralo». Quitarle el tipo a
    // una sucursal no es algo que esta pantalla pueda hacer.
    tipoId: tipoId ?? this.tipoId,
    estadoOperativo: estadoOperativo ?? this.estadoOperativo,
  );
}
