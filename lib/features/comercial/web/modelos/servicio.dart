import '../../../../core/fechas/dia_de_negocio.dart';
import 'cliente.dart' show Monto;

/// Un servicio, tal como lo devuelve `GET /companies/{id}/services/{sid}`.
///
/// ## Qué es un Servicio, y qué NO es
///
/// Es **un contrato de servicio prestado a un cliente** —vigilancia en un club—, con su
/// folio `SRV`, su cliente **fijo para siempre** y su domicilio **operativo**: el lugar
/// donde se presta. Un cliente con cuatro sedes tiene **cuatro servicios**.
///
/// ⚠️ **No se confunde con dos cosas que se parecen.** `Service` **no es** `Quote`: el
/// embudo comercial —cotizar— llega en 5D.10F, y por eso aquí no hay estatus «Cotizado».
/// Y el `Service` del plano de la empresa **no es** el servicio profesional del catálogo
/// de la plataforma, que es otra tabla y otro apartado.
///
/// Modelo plano y propio de la web, igual que [Cliente]: aquí no hay Drift.
class Servicio {
  const Servicio({
    required this.id,
    required this.clienteId,
    required this.codigo,
    required this.nombre,
    required this.tipoId,
    required this.estatus,
    required this.condicionTemporal,
    required this.inicio,
    required this.termino,
    required this.observaciones,
    required this.supervisorEmpleadoId,
    required this.sucursalAdministrativaId,
    required this.contactoResponsableId,
    required this.entidadFiscalId,
    required this.creadoEn,
    required this.actualizadoEn,
  });

  factory Servicio.deJson(Map<String, dynamic> json) => Servicio(
    id: json['id'] as String,
    clienteId: json['clientId'] as String,
    codigo: json['code'] as String,
    nombre: json['name'] as String,
    tipoId: json['serviceTypeId'] as String,
    estatus: json['status'] as String,
    condicionTemporal: json['temporalCondition'] as String,
    inicio: DiaDeNegocio.deTexto(json['startedOn'] as String?),
    termino: DiaDeNegocio.deTexto(json['endedOn'] as String?),
    observaciones: json['notes'] as String?,
    supervisorEmpleadoId: json['supervisorEmployeeId'] as String?,
    sucursalAdministrativaId: json['administrativeBranchId'] as String?,
    contactoResponsableId: json['responsibleContactId'] as String?,
    entidadFiscalId: json['fiscalEntityId'] as String?,
    creadoEn: DateTime.parse(json['createdAt'] as String),
    actualizadoEn: DateTime.parse(json['updatedAt'] as String),
  );

  final String id;

  /// El cliente al que se le presta. **Inmutable**: no viaja en ningún `PATCH`, y el
  /// servidor no ofrece ruta para cambiarlo. Un servicio que cambiara de cliente
  /// reescribiría a quién se le cobró.
  final String clienteId;

  /// `SRV-000001`. Lo asigna el servidor y es inmutable.
  final String codigo;

  final String nombre;
  final String tipoId;

  /// El código del servidor: `active`, `suspended` o `terminated`.
  ///
  /// ⚠️ **SE GUARDA EL CÓDIGO CRUDO Y NO UN `enum`**, por la misma razón que en
  /// [Cliente.estatus]: un valor que esta build no conozca sería una excepción al leer la
  /// lista, o peor, un `_ => activo` que enseñaría como activo lo que no lo está. Lo que
  /// hay es [estado], que devuelve nulo si no lo reconoce.
  final String estatus;

  /// `upcoming`, `inforce` o `expired`, **derivado por el servidor** de las fechas
  /// contra el día de negocio de hoy.
  ///
  /// ⚠️ **`inforce` SIN GUION BAJO**, y no es un descuido del servidor: sale de
  /// `ToString().ToLowerInvariant()` sobre su enumeración. **Se queda así** —decisión del
  /// dueño del 9-nov-2026— y es **la pantalla la que traduce**: cambiar el contrato por
  /// estética no lo vale, y una forma distinta en cada sitio sería peor que una fea.
  ///
  /// **No se deriva aquí**, aunque las dos fechas estén a mano: el único que sabe qué día
  /// es hoy **para el negocio** es el servidor. El navegador tiene otro reloj y otra zona,
  /// y «hoy» calculado en el cliente se equivocaría seis horas al día.
  final String condicionTemporal;

  /// Desde cuándo opera. La exige el servidor en el alta.
  final DiaDeNegocio? inicio;

  /// Último día de vigencia, **inclusivo**, o nulo si no tiene término programado.
  final DiaDeNegocio? termino;

  final String? observaciones;

  /// El empleado que **responde** por el servicio, o nulo.
  ///
  /// 🚫 **NO es personal asignado al servicio.** El supervisor lleva **zona**; quién
  /// trabaja aquí es la cobertura operativa, que llega en C5 y es otra cosa. El nombre y
  /// si sigue activo se piden por su ruta propia: ver [SupervisorDelServicio].
  final String? supervisorEmpleadoId;

  /// La sucursal **propia** que administra este servicio. **No es dónde se presta** —eso
  /// es el servicio mismo—: `Branch` es destino administrativo y `Service` el operativo.
  final String? sucursalAdministrativaId;

  /// El contacto **del cliente** que responde por este servicio.
  final String? contactoResponsableId;

  /// A quién se le factura. Nulo mientras no se asigne.
  final String? entidadFiscalId;

  /// Cuándo se **capturó la fila**. No se confunde con [inicio], que es cuándo empezó a
  /// operar: la primera puede ser de hoy y la segunda de hace tres años.
  final DateTime creadoEn;

  final DateTime actualizadoEn;

  /// El estatus reconocido, o **nulo** si llegó uno que esta build no conoce.
  EstatusDeServicio? get estado => EstatusDeServicio.deCodigo(estatus);

  /// La condición temporal reconocida, o nulo si llegó una desconocida.
  CondicionTemporal? get condicion =>
      CondicionTemporal.deCodigo(condicionTemporal);
}

/// Una fila del listado: el servicio **y lo que se enseña a su lado**.
///
/// ## Por qué es un tipo aparte de [Servicio]
///
/// Porque es lo que el servidor decidió, y la razón vale igual aquí: la ficha **no trae**
/// el nombre del cliente ni la ubicación, y publicarlos en nulo haría que la pantalla no
/// pudiera distinguir «no hay» de «esta respuesta no lo trae». Y al revés: la ficha trae
/// observaciones, vínculos y marcas de tiempo que el listado **no publica**, para que
/// nadie pinte en una fila un dato que no pidió.
class ServicioEnLista {
  const ServicioEnLista({
    required this.id,
    required this.clienteId,
    required this.codigo,
    required this.nombre,
    required this.tipoId,
    required this.estatus,
    required this.condicionTemporal,
    required this.inicio,
    required this.termino,
    required this.clienteNombreComercial,
    required this.clienteLogotipoFileId,
    required this.ubicacion,
  });

  factory ServicioEnLista.deJson(Map<String, dynamic> json) => ServicioEnLista(
    id: json['id'] as String,
    clienteId: json['clientId'] as String,
    codigo: json['code'] as String,
    nombre: json['name'] as String,
    tipoId: json['serviceTypeId'] as String,
    estatus: json['status'] as String,
    condicionTemporal: json['temporalCondition'] as String,
    inicio: DiaDeNegocio.deTexto(json['startedOn'] as String?),
    termino: DiaDeNegocio.deTexto(json['endedOn'] as String?),
    clienteNombreComercial: json['clientCommercialName'] as String,
    // SE LEE EL IDENTIFICADOR Y NO `clientHasLogo`, aunque el servidor manda los dos: el
    // id contesta las dos preguntas —si hay y cuál— y dos fuentes para lo mismo pueden
    // discrepar.
    clienteLogotipoFileId: json['clientLogoFileId'] as String?,
    ubicacion: json['location'] as String?,
  );

  final String id;
  final String clienteId;
  final String codigo;
  final String nombre;
  final String tipoId;
  final String estatus;
  final String condicionTemporal;
  final DiaDeNegocio? inicio;
  final DiaDeNegocio? termino;

  /// El nombre del cliente, **ya en la fila**: el listado del escritorio lo enseña debajo
  /// del nombre del servicio, y pedirlo por fila sería una petición por fila.
  final String clienteNombreComercial;

  /// **Qué logotipo tiene puesto SU CLIENTE**, o nulo.
  ///
  /// ⚠️ Es la **identidad de la versión**, así que es la clave de la caché: reemplazar el
  /// logotipo estrena archivo y el valor cambia, de modo que la imagen vieja no se queda
  /// pegada. Y como es del **cliente**, dos servicios del mismo cliente comparten clave y
  /// la caché pide los bytes **una vez**.
  final String? clienteLogotipoFileId;

  /// «Municipio, Estado» del domicilio **operativo del servicio**, ya compuesta por el
  /// servidor, o nula.
  ///
  /// ⚠️ **Desde la 0059 no debería ser nula nunca**, porque ningún servicio existe sin
  /// domicilio operativo. La pantalla conserva su «Ubicación no registrada» como **red**,
  /// no como estado esperado.
  final String? ubicacion;

  bool get clienteTieneLogotipo => clienteLogotipoFileId != null;

  EstatusDeServicio? get estado => EstatusDeServicio.deCodigo(estatus);

  CondicionTemporal? get condicion =>
      CondicionTemporal.deCodigo(condicionTemporal);
}

/// Una página del listado de servicios.
///
/// [cursorSiguiente] nulo significa **que no hay más**. No trae el total, por lo mismo que
/// la de clientes: contarlo costaría otra consulta para un número que la pantalla no
/// necesita y que ya sería viejo al pintarse.
class PaginaDeServicios {
  const PaginaDeServicios({
    required this.servicios,
    required this.cursorSiguiente,
  });

  factory PaginaDeServicios.deJson(Map<String, dynamic> json) =>
      PaginaDeServicios(
        servicios: [
          for (final fila in json['items'] as List)
            ServicioEnLista.deJson(fila as Map<String, dynamic>),
        ],
        cursorSiguiente: json['nextCursor'] as String?,
      );

  final List<ServicioEnLista> servicios;
  final String? cursorSiguiente;

  bool get hayMas => cursorSiguiente != null;
}

/// Los indicadores de la ficha de un servicio.
///
/// **El personal asignado y la cobertura por turnos NO están**: llegan con C5, y hasta
/// entonces el indicador **no aparece** en lugar de salir en cero — **ausencia nunca es
/// cero**, y un cero diría que el servicio no tiene gente.
class IndicadoresDeServicio {
  const IndicadoresDeServicio({
    required this.importeMensual,
    required this.antiguedadEnMeses,
  });

  factory IndicadoresDeServicio.deJson(Map<String, dynamic> json) =>
      IndicadoresDeServicio(
        importeMensual: [
          for (final m in json['monthlyAmount'] as List)
            Monto.deJson(m as Map<String, dynamic>),
        ],
        antiguedadEnMeses: json['seniorityMonths'] as int,
      );

  /// El importe mensual contratado, **una línea por moneda**. **Vacía no es cero**:
  /// significa que no hay condiciones vigentes.
  final List<Monto> importeMensual;

  /// Meses **cumplidos** desde el inicio. En un servicio terminado **deja de crecer**: se
  /// mide hasta su término, porque es cuánto duró.
  ///
  /// El número lo da el servidor, que es el único que sabe qué día es hoy para el negocio.
  final int antiguedadEnMeses;

  /// «Menos de 1 mes», «7 meses», «2 años, 3 meses».
  ///
  /// La redacción es **de la pantalla** y por eso vive aquí y no en el servidor: el
  /// contrato manda el número.
  String get antiguedadEnPantalla {
    if (antiguedadEnMeses < 1) return 'Menos de 1 mes';
    if (antiguedadEnMeses < 12) {
      return '$antiguedadEnMeses ${antiguedadEnMeses == 1 ? 'mes' : 'meses'}';
    }

    final anios = antiguedadEnMeses ~/ 12;
    final meses = antiguedadEnMeses % 12;
    final enAnios = '$anios ${anios == 1 ? 'año' : 'años'}';

    if (meses == 0) return enAnios;

    return '$enAnios, $meses ${meses == 1 ? 'mes' : 'meses'}';
  }
}

/// El supervisor responsable de un servicio, como lo devuelve su ruta propia.
///
/// ## Por qué una ruta propia y no un campo de la ficha
///
/// Porque la ficha ya sabe **si hay uno** —[Servicio.supervisorEmpleadoId]—, así que el
/// nombre se pide **sólo cuando lo hay**, y ninguna mutación del servicio paga una
/// consulta más para devolver un dato que no cambió.
///
/// ⚠️ **[estaActivo] sostiene la insignia «Baja».** Un supervisor que deja de estar activo
/// **no se desvincula solo** —decisión del dueño—, así que la pantalla tiene que poder
/// decir que esa persona ya no está y ofrecer cambiarlo.
class SupervisorDelServicio {
  const SupervisorDelServicio({
    required this.empleadoId,
    required this.numeroDeEmpleado,
    required this.nombreCompleto,
    required this.estaActivo,
  });

  factory SupervisorDelServicio.deJson(Map<String, dynamic> json) =>
      SupervisorDelServicio(
        empleadoId: json['employeeId'] as String,
        numeroDeEmpleado: json['employeeNumber'] as int,
        nombreCompleto: json['fullName'] as String,
        estaActivo: json['isActive'] as bool,
      );

  final String empleadoId;
  final int numeroDeEmpleado;
  final String nombreCompleto;

  /// Si **sigue** activo. Se deriva en el servidor de un periodo laboral abierto.
  final bool estaActivo;
}

/// Un tipo de servicio del catálogo de la empresa: `INTRAMUROS`, `RONDIN`.
///
/// ⚠️ **Es Company-owned y NACE VACÍO**: una empresa nueva no tiene tipos hasta que
/// alguien los crea, así que el alta tiene que poder decir eso en lugar de enseñar un
/// selector vacío sin explicación.
class TipoDeServicio {
  const TipoDeServicio({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.estatus,
  });

  factory TipoDeServicio.deJson(Map<String, dynamic> json) => TipoDeServicio(
    id: json['id'] as String,
    codigo: json['code'] as String,
    nombre: json['name'] as String,
    estatus: json['status'] as String,
  );

  final String id;
  final String codigo;
  final String nombre;

  /// `activa` o `inactiva`. Un tipo **retirado** no se puede elegir para un servicio
  /// nuevo, pero **sí** sirve para filtrar el listado: los servicios que lo usan siguen
  /// ahí. Son dos preguntas distintas.
  final String estatus;

  bool get estaActivo => estatus == 'activa';
}

/// Los **tres** estatus de un servicio, con su código y su nombre.
///
/// ## Por qué tres y no los cuatro del escritorio
///
/// El escritorio tiene **Cotizado**, Activo, Suspendido y Terminado, y todo servicio nace
/// Cotizado. Aquí nace **activo** y no hay «Cotizado», porque la arquitectura congelada
/// separa **`Service` de `Quote`**: cotizar es del embudo comercial y llega en 5D.10F.
/// La consecuencia visible es que el filtro de estatus tiene **tres** valores.
enum EstatusDeServicio {
  activo('active', 'Activo'),
  suspendido('suspended', 'Suspendido'),
  terminado('terminated', 'Terminado');

  const EstatusDeServicio(this.codigo, this.nombre);

  final String codigo;
  final String nombre;

  static EstatusDeServicio? deCodigo(String codigo) {
    for (final e in values) {
      if (e.codigo == codigo) return e;
    }

    return null;
  }

  /// ¿Es un servicio **terminado**? Es la frontera del chip «Vigentes / Finalizados», y
  /// vive aquí para que el día que haya otro estatus final se añada en un solo sitio.
  bool get esFinalizado => this == terminado;
}

/// La condición **temporal** de un servicio, derivada por el servidor de sus fechas.
///
/// ⚠️ **No se persiste y no se deriva en la pantalla.** Es un eje distinto del estatus: un
/// servicio puede estar **activo y vencido** sólo si alguien rompió un invariante, y por
/// eso el servidor tiene tres reglas que lo impiden. Aquí sólo se traduce.
enum CondicionTemporal {
  /// Su primer día todavía no llega.
  proxima('upcoming', 'Próximo'),

  /// Opera hoy.
  vigente('inforce', 'Vigente'),

  /// Su término ya pasó.
  vencida('expired', 'Vencido');

  const CondicionTemporal(this.codigo, this.nombre);

  /// ⚠️ `inforce` **sin guion bajo**: es el código que manda el servidor, y **se queda
  /// así** por decisión del dueño. Esta enumeración es justamente el único sitio donde la
  /// traducción vive, así que la fealdad del cable no sale de aquí.
  final String codigo;

  final String nombre;

  static CondicionTemporal? deCodigo(String codigo) {
    for (final c in values) {
      if (c.codigo == codigo) return c;
    }

    return null;
  }
}
