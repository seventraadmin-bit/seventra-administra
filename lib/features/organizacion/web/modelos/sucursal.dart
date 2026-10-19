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
}
