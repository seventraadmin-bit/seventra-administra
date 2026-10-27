/// **EL ÚNICO SITIO QUE DECIDE LA ESTRUCTURA DE ADMINISTRA EN LA NUBE.**
///
/// De aquí salen tres cosas que antes se decidían por separado y podían discrepar:
///
///  1. **el menú lateral** —apartados, nombres, iconos y orden—;
///  2. **las pestañas** de cada apartado, y cuál ya está mudada;
///  3. **los grupos del panel de permisos**, con su nombre y si se muestran.
///
/// Que salgan del mismo sitio es la decisión, no una comodidad: el grupo de permisos
/// de Compras se llama «Compras e inventario» **porque el apartado se llama así**, no
/// porque alguien escribiera el mismo texto en dos archivos. Dos listas paralelas
/// acaban divergiendo, y el síntoma —un menú que dice una cosa y un permiso que dice
/// otra— se descubre tarde.
///
/// ## Cómo se muda un módulo
///
/// Una línea: `mudada: false` → `mudada: true` en su pestaña. Con eso aparece en el
/// menú sin «Próximamente», se abre su pantalla y sus permisos salen en el panel.
///
/// ## La regla de los permisos que esto implementa
///
/// **Los permisos de un módulo aparecen cuando ese módulo se muda.** Mostrar hoy los
/// 103 del catálogo haría que un Maestro concediera `nomina.ver` en la nube y no
/// pasara nada: el módulo que lo lee sigue en SQLite, en el escritorio. Una casilla
/// que se marca sin surtir efecto es peor que una que no está, porque parece que el
/// trabajo quedó hecho.
///
/// ## Dos uniones decididas para la nube
///
/// El escritorio tiene **once** entradas planas; aquí hay **nueve**, porque
/// `Inventario`+`Compras` van juntas y `Vehículos`+`Telefonía` también. No es
/// capricho: son exactamente los módulos `purchases_inventory` y `assets` del
/// servidor, así que el menú y el catálogo de permisos acaban diciendo lo mismo.
///
/// Y «Activos» aquí **no es el módulo que se retiró tras la Etapa 10** —aquél era un
/// placeholder sin tabla, repositorio ni pantalla—: es un contenedor de pestañas con
/// Vehículos y Telefonía dentro.
library;

import 'package:flutter/material.dart';

import '../../core/company/permiso_company.dart';

/// Una pestaña dentro de un apartado.
@immutable
class PestanaDeApartado {
  const PestanaDeApartado({
    required this.id,
    required this.nombre,
    required this.mudada,
    this.icono,
    this.permiso,
    this.soloMaestro = false,
  });

  /// Clave corta y estable. Se usa para las `Key` de prueba y para saber qué pintar.
  final String id;

  final String nombre;

  /// Su ícono **propio**, para el aviso de «Próximamente».
  ///
  /// ⚠️ **SIN ESTO TODAS LAS PESTAÑAS DE UN APARTADO SALÍAN CON EL MISMO ÍCONO**, el
  /// del apartado: Puestos enseñaba el mismo edificio que Empresa, y las dos parecían
  /// la misma cosa sin terminar. Lo cazó una revisión en pantalla.
  ///
  /// `null` cae al del apartado, que sigue siendo razonable para una pestaña sin
  /// ícono decidido.
  final IconData? icono;

  /// **LA ÚNICA LÍNEA QUE SE CAMBIA AL MUDAR UN MÓDULO.**
  final bool mudada;

  /// El permiso que hace falta para ofrecerla, o `null` si basta tener acceso.
  ///
  /// **OFRECERLA NO ES AUTORIZARLA.** El servidor vuelve a decidir en cada petición;
  /// esto sólo evita enseñar una puerta que va a responder 403.
  final String? permiso;

  /// ¿Sólo para el Maestro de la empresa? El rol no es un permiso, así que va aparte.
  final bool soloMaestro;
}

/// Un apartado del menú lateral.
@immutable
class ApartadoDeAdministra {
  const ApartadoDeAdministra({
    required this.ruta,
    required this.nombre,
    required this.icono,
    required this.modulos,
    required this.pestanas,
  });

  /// La ruta, igual que en el escritorio —`/organizacion`, `/configuracion`—. Es
  /// también la clave de las `Key` de prueba del menú.
  final String ruta;

  final String nombre;
  final IconData icono;

  /// Los módulos del servidor que este apartado representa, **de
  /// [ModuloCompany]**, nunca escritos a mano.
  ///
  /// Vacío = **del núcleo**: Dashboard, Organización, Reportes y Configuración no
  /// dependen de ningún módulo contratado.
  ///
  /// Son varios porque el menú agrupa: `Personal` cubre `personal` y `payroll`, y
  /// `Finanzas` cubre `finance` y `collections`. Así los permisos de nómina salen bajo
  /// «Personal», que es donde el usuario los va a buscar.
  final Set<String> modulos;

  /// Sus pestañas, en orden. **Vacío significa que el apartado no está mudado**: lo
  /// que no tiene ni una pantalla no tiene pestañas que enseñar.
  final List<PestanaDeApartado> pestanas;

  /// ¿Hay algo que abrir aquí? Basta **una** pestaña mudada.
  bool get mudado => pestanas.any((p) => p.mudada);

  /// Las pestañas con pantalla. Es lo que se pinta.
  List<PestanaDeApartado> get pestanasMudadas =>
      pestanas.where((p) => p.mudada).toList();
}

/// **Los nueve apartados, en el orden del menú.**
///
/// Los iconos son **los mismos de `shellModuleDefs`** del escritorio: Organización
/// lleva `apartment_outlined` allá y aquí. Los dos contenedores nuevos toman el icono
/// del módulo que más los representa —`inventory_2_outlined` y
/// `directions_car_outlined`—, que es el que el escritorio ya usaba para Inventario y
/// Vehículos.
const List<ApartadoDeAdministra> apartados = [
  ApartadoDeAdministra(
    ruta: '/dashboard',
    nombre: 'Dashboard',
    icono: Icons.dashboard_outlined,
    modulos: {},
    pestanas: [],
  ),

  // --- MUDADO EN PARTE ---------------------------------------------------
  ApartadoDeAdministra(
    ruta: '/organizacion',
    nombre: 'Organización',
    icono: Icons.apartment_outlined,
    modulos: {},
    pestanas: [
      // ⚠️ LAS CUATRO DECLARAN SU PERMISO, Y NINGUNA LO HACÍA. Con `permiso: null`
      // el apartado se ofrecía a cualquiera con acceso a la empresa, así que un
      // usuario de cero permisos veía «Organización» en el menú, entraba, y el
      // servidor le servía las listas —porque tampoco las pedía—. Cerrado el
      // servidor, esto es lo que evita ofrecer una puerta que responderá 403.
      //
      // EMPRESA PIDE EL DEL EXPEDIENTE y las otras tres el de la ESTRUCTURA: son
      // dos familias, y la frontera decide quién ve el RFC.
      PestanaDeApartado(
        id: 'empresa',
        nombre: 'Empresa',
        mudada: true,
        icono: Icons.business_outlined,
        permiso: PermisoCompany.companySettingsRead,
      ),
      PestanaDeApartado(
        id: 'sucursales',
        nombre: 'Sucursales',
        mudada: true,
        icono: Icons.store_outlined,
        permiso: PermisoCompany.organizacionVer,
      ),
      PestanaDeApartado(
        id: 'puestos',
        nombre: 'Puestos',
        mudada: true,
        icono: Icons.badge_outlined,
        permiso: PermisoCompany.organizacionVer,
      ),
      PestanaDeApartado(
        id: 'areas',
        nombre: 'Áreas',
        mudada: true,
        icono: Icons.account_tree_outlined,
        permiso: PermisoCompany.organizacionVer,
      ),
    ],
  ),

  // --- MUDADO EN PARTE ---------------------------------------------------
  //
  // ⚠️ **EL MÓDULO LO FILTRA EL PERMISO, Y NO HACE FALTA MIRAR `modulos` AQUÍ.** Los
  // permisos efectivos que devuelve `/context` ya **excluyen los de un módulo
  // apagado** —el servidor los resuelve con `PermissionPossession`, que recibe si el
  // módulo está habilitado— así que una empresa que no contrató `clients_services` no
  // trae `clients_services.read` y esta pestaña no se le ofrece. `modulos` sigue
  // sirviendo para agrupar los permisos en el panel, que es para lo que nació.
  ApartadoDeAdministra(
    ruta: '/comercial',
    nombre: 'Comercial',
    icono: Icons.handshake_outlined,
    modulos: {ModuloCompany.clientsServices},
    pestanas: [
      PestanaDeApartado(
        id: 'clientes',
        nombre: 'Clientes',
        mudada: true,
        // ÍCONO PROPIO Y NO EL DEL APARTADO: una prueba lo exige, y con razón —el aviso
        // de «Próximamente» de una pestaña no se distinguiría del del apartado—.
        icono: Icons.contact_page_outlined,
        permiso: PermisoCompany.clientsServicesRead,
      ),
      // SERVICIOS SE ENSEÑA SIN PANTALLA, igual que las dos de Organización que
      // faltaban: llega en C2 y esconderla haría pensar que el producto perdió la
      // mitad de «Clientes y servicios».
      PestanaDeApartado(
        id: 'servicios',
        nombre: 'Servicios',
        mudada: false,
        icono: Icons.design_services_outlined,
        permiso: PermisoCompany.clientsServicesRead,
      ),
    ],
  ),

  ApartadoDeAdministra(
    ruta: '/finanzas',
    nombre: 'Finanzas',
    icono: Icons.account_balance_outlined,
    modulos: {ModuloCompany.finance, ModuloCompany.collections},
    pestanas: [],
  ),

  ApartadoDeAdministra(
    ruta: '/personal',
    nombre: 'Personal',
    icono: Icons.people_outline,
    modulos: {ModuloCompany.personal, ModuloCompany.payroll},
    pestanas: [],
  ),

  // LAS DOS UNIONES. En el escritorio son cuatro entradas planas; aquí dos
  // contenedores, que es lo que el servidor ya llama `purchases_inventory` y `assets`.
  ApartadoDeAdministra(
    ruta: '/compras-inventario',
    nombre: 'Compras e inventario',
    icono: Icons.inventory_2_outlined,
    modulos: {ModuloCompany.purchasesInventory},
    pestanas: [],
  ),

  ApartadoDeAdministra(
    ruta: '/activos',
    nombre: 'Activos',
    icono: Icons.directions_car_outlined,
    modulos: {ModuloCompany.assets},
    pestanas: [],
  ),

  ApartadoDeAdministra(
    ruta: '/reportes',
    nombre: 'Reportes',
    icono: Icons.bar_chart_outlined,
    modulos: {},
    pestanas: [],
  ),

  // --- MUDADO EN PARTE ---------------------------------------------------
  //
  // Respaldo y Bóveda NO se mudan, y no es un pendiente: el respaldo portable y la
  // bóveda local son del producto de escritorio, donde los datos viven en el disco de
  // quien los usa. En la nube el respaldo es del servidor.
  ApartadoDeAdministra(
    ruta: '/configuracion',
    nombre: 'Configuración',
    icono: Icons.settings_outlined,
    modulos: {},
    pestanas: [
      PestanaDeApartado(
        id: 'usuarios',
        nombre: 'Usuarios',
        mudada: true,
        icono: Icons.people_outline,
        soloMaestro: true,
      ),
      PestanaDeApartado(
        id: 'auditoria',
        nombre: 'Auditoría',
        mudada: true,
        icono: Icons.history,
        permiso: PermisoCompany.companyAuditRead,
      ),
    ],
  ),
];

/// Qué hacer con un apartado para una persona concreta.
///
/// **DOS CASOS: se abre, o no aparece.**
///
/// ## Aquí hubo un tercero, y se retiró el 21 de octubre de 2026
///
/// Un apartado **sin mudar** aparecía en el menú con la insignia «Próximamente», y al
/// abrirlo decía: «Este apartado todavía se usa **desde la aplicación de escritorio**.
/// Lo estamos trayendo a la web módulo por módulo».
///
/// Ese texto es **interno**. Tiene sentido para RISEG, que es cliente piloto y sí usa
/// el escritorio, y no lo tiene para ningún cliente nuevo: a quien contrata Administra
/// en la nube se le estaría nombrando un producto que no tiene y una mudanza que no le
/// incumbe. Lo vio el dueño probando con una cuenta de usuario.
///
/// **Así que lo que no está mudado no se enseña.** Un menú con siete entradas que no
/// llevan a ninguna parte tampoco es un buen anuncio de lo que se compró.
///
/// La consecuencia, y por eso esto no es sólo quitar una línea: **una persona puede
/// quedarse sin ningún apartado visible**. Antes era imposible, porque Dashboard y los
/// demás sin mudar aparecían para todo el mundo. Ahora pasa con quien no tiene ningún
/// permiso, y el portón lo recibe con una bienvenida que lo explica en vez de con una
/// pantalla en blanco.
enum QueHacerConElApartado {
  /// Tiene al menos una pestaña que esta persona puede abrir.
  seAbre,

  /// No aparece en el menú. Por una de dos razones, y las dos son correctas:
  ///
  ///  · **no está mudado** —no hay nada que abrir todavía—;
  ///  · está mudado **pero esta persona no tiene nada dentro**, que es el caso de
  ///    quien no es Maestro y no puede leer la auditoría: Configuración existe y no
  ///    es para él.
  ///
  /// No se distinguen porque **la persona no puede hacer nada distinto** en un caso y
  /// en el otro, y la diferencia es de nuestro calendario, no de su trabajo.
  noAparece,
}

/// La decisión, **sin widgets y sin contexto**: recibe lo que el servidor confirmó ya
/// convertido en dos datos simples.
///
/// Está aquí y no en la pantalla para poder probarla sola.
QueHacerConElApartado queHacerCon(
  ApartadoDeAdministra apartado, {
  required bool esMaestro,
  required Set<String> permisos,
}) {
  // LO QUE NO ESTÁ MUDADO NO SE ENSEÑA. Ver el comentario del enum: su aviso nombraba
  // la aplicación de escritorio, que es un producto que un cliente nuevo no tiene.
  if (!apartado.mudado) return QueHacerConElApartado.noAparece;

  final suyas = pestanasPara(apartado, esMaestro: esMaestro, permisos: permisos);

  // NINGUNA PESTAÑA SUYA ESTÁ MUDADA → no tiene nada que abrir. Pasa cuando las
  // mudadas son justo las que esta persona no puede ver.
  return suyas.any((p) => p.mudada)
      ? QueHacerConElApartado.seAbre
      : QueHacerConElApartado.noAparece;
}

/// Las pestañas que este apartado le muestra **a esta persona**.
///
/// **INCLUYE LAS QUE NO ESTÁN MUDADAS**, y es deliberado: Organización enseña sus
/// cuatro —Empresa, Sucursales, Puestos, Áreas— en el orden del escritorio desde el
/// primer día, y al abrir una que no tiene pantalla se explica. Mostrar sólo dos haría
/// pensar que el producto perdió las otras.
///
/// Lo que sí filtra es **a quién le toca**: el rol y el permiso que la pestaña exige.
/// Eso no se enseña y se explica — no tenerlo no es algo que vaya a llegar.
///
/// **FILTRAR NO ES AUTORIZAR.** El servidor vuelve a decidir en cada petición; lo que
/// se evita es ofrecer una puerta que va a cerrarse en la cara.
List<PestanaDeApartado> pestanasPara(
  ApartadoDeAdministra apartado, {
  required bool esMaestro,
  required Set<String> permisos,
}) => [
  for (final p in apartado.pestanas)
    if (!p.soloMaestro || esMaestro)
      if (p.permiso == null || permisos.contains(p.permiso)) p,
];

/// ¿Puede esta persona **editar** la configuración de la empresa?
///
/// Es la pregunta de los dos expedientes —el de la empresa y el de una sucursal—: los
/// dos se LEEN con sólo tener acceso a la Company, y se EDITAN con
/// `company.settings.manage`.
///
/// ## Por qué vive aquí y no en la pantalla que la necesita
///
/// Porque **ninguna feature puede conocer el catálogo de permisos**, y las dos formas
/// de saltarse eso están cerradas a propósito por dos guardias distintos: escribir el
/// literal `'company.settings.manage'` lo caza «los literales del catálogo tienen un
/// dueño único», e importar `PermisoCompany` desde `features/` lo caza «ninguna
/// feature la consume». Lo intenté por los dos caminos y los dos fallaron, que es
/// exactamente lo que esos guardias existen para hacer.
///
/// Este archivo es el sitio correcto: ya es el dueño del registro que dice qué permiso
/// exige cada pestaña, y no está bajo `features/`.
///
/// **FILTRAR NO ES AUTORIZAR**, igual que en [pestanasPara]: el servidor vuelve a
/// decidir en cada `PUT`. Lo que esto evita es ofrecer un formulario que va a
/// responder 403 al guardar.
bool puedeEditarLaConfiguracionDeLaEmpresa(Set<String> permisos) =>
    permisos.contains(PermisoCompany.companySettingsManage);

/// La lectura que **arrastra** esta escritura, o `null` si no es una escritura
/// emparejada.
///
/// La usa el panel de permisos: marcar «Modificar la organización» marca «Consultar
/// la organización», porque conceder la escritura sin la lectura produce una cuenta
/// que puede guardar y no puede ver el formulario.
///
/// **Vive aquí y no en la pantalla** por lo mismo que
/// [puedeEditarLaConfiguracionDeLaEmpresa]: ninguna feature puede conocer el catálogo
/// de permisos, y hay dos guardias que lo impiden.
String? lecturaQueImplica(String escritura) =>
    PermisoCompany.lecturaQueImplica[escritura];

/// Si esta lectura **no se puede desmarcar** porque queda una escritura suya marcada.
///
/// Sólo mira **su propia familia**: «Consultar la empresa» la retienen las escrituras
/// del expediente, no las de la estructura.
bool laLecturaEstaRetenida(String lectura, Set<String> marcados) =>
    PermisoCompany.escriturasQueDependenDe(lectura).any(marcados.contains);

/// **LO QUE UNA PERSONA PUEDE HACER EN UNA PANTALLA, en un solo objeto.**
///
/// ## Por qué existe, y qué costó no tenerlo
///
/// Las tres pantallas de la estructura —Áreas, Puestos, Sucursales— recibían `bool`
/// sueltos, y cada una los cableaba a mano. El resultado fue el previsible: Áreas y
/// Puestos sólo recibían `esMaestro` —que gobierna el BORRADO— y sus botones de alta no
/// colgaban de nada; Sucursales recibía un flag que gobernaba sólo el expediente y
/// dejaba abiertas otras cuatro acciones. Un usuario con cero permisos veía todo.
///
/// Y al arreglarlo a mano se me olvidó el **estado vacío**, que tiene su propio botón de
/// alta aparte del encabezado. Tres pantallas, tres cableados, tres oportunidades de
/// olvidar lo mismo.
///
/// ## Qué resuelve para el módulo siguiente
///
/// Una pantalla pide `CapacidadesDeModulo` y pregunta `puedeCrear`, `puedeModificar`,
/// `puedeArchivar`. Añadir un módulo es llamar a [CapacidadesDeModulo.de] con sus cuatro
/// códigos; **ninguna feature necesita conocer un literal del catálogo**, que es lo que
/// los dos guardias de arquitectura impiden a propósito.
///
/// **FILTRAR NO ES AUTORIZAR.** El servidor vuelve a decidir en cada petición. Esto
/// evita ofrecer una puerta que va a cerrarse en la cara, y que alguien confunda
/// «no veo el botón» con «no tengo permiso».
@immutable
class CapacidadesDeModulo {
  const CapacidadesDeModulo({
    required this.puedeVer,
    required this.puedeCrear,
    required this.puedeModificar,
    required this.puedeArchivar,
  });

  /// Nada: ni ver. Es la línea base con la que se prueban las pantallas.
  const CapacidadesDeModulo.ninguna()
    : puedeVer = false,
      puedeCrear = false,
      puedeModificar = false,
      puedeArchivar = false;

  /// Las cuatro de la ESTRUCTURA de la organización, resueltas de los permisos
  /// efectivos que confirmó el servidor.
  factory CapacidadesDeModulo.deLaOrganizacion(Set<String> permisos) =>
      CapacidadesDeModulo.de(
        permisos,
        ver: PermisoCompany.organizacionVer,
        crear: PermisoCompany.organizacionCrear,
        modificar: PermisoCompany.organizacionModificar,
        archivar: PermisoCompany.organizacionArchivar,
      );

  /// Las de **Clientes y servicios**.
  ///
  /// ⚠️ **LAS TRES ESCRITURAS SON EL MISMO CÓDIGO, y no es un atajo mío: es el catálogo.**
  /// El módulo `clients_services` tiene **dos** permisos —`.read` y `.manage`— y el
  /// backend lo razona: «Contratos y Archivos de cliente reutilizan este mismo permiso,
  /// sin código propio». Archivar un cliente —terminar la relación— también es `manage`,
  /// porque no hay un permiso aparte para archivar.
  ///
  /// **Esto NO ensancha ningún permiso**: traduce al objeto de la pantalla exactamente lo
  /// que el servidor va a exigir. Lo que evita es que cada botón de Clientes pregunte por
  /// `puedeModificar` y alguien cablee ahí un permiso que no existe.
  ///
  /// Y `crm.manage` **no está**, a propósito: llega en 5D.10F con el CRM, y la conversión
  /// de un prospecto exigirá **los dos**. Sumarlo hoy sería declarar una capacidad que
  /// ninguna ruta lee.
  factory CapacidadesDeModulo.deClientes(Set<String> permisos) =>
      CapacidadesDeModulo.de(
        permisos,
        ver: PermisoCompany.clientsServicesRead,
        crear: PermisoCompany.clientsServicesManage,
        modificar: PermisoCompany.clientsServicesManage,
        archivar: PermisoCompany.clientsServicesManage,
      );

  /// La forma genérica. Un módulo nuevo pasa sus cuatro códigos y ya está.
  factory CapacidadesDeModulo.de(
    Set<String> permisos, {
    required String ver,
    required String crear,
    required String modificar,
    required String archivar,
  }) => CapacidadesDeModulo(
    puedeVer: permisos.contains(ver),
    puedeCrear: permisos.contains(crear),
    puedeModificar: permisos.contains(modificar),
    puedeArchivar: permisos.contains(archivar),
  );

  /// Consultar la lista.
  final bool puedeVer;

  /// Crear una entidad nueva. Gobierna el botón de alta **y el del estado vacío**.
  final bool puedeCrear;

  /// Corregir lo que existe: gobierna si el panel es formulario o ficha.
  final bool puedeModificar;

  /// Mover el interruptor, en las dos direcciones. El borrado físico exige además
  /// ser Maestro, y eso va aparte porque un rol no es un permiso.
  final bool puedeArchivar;

  /// ¿Hay algo que escribir desde esta pantalla?
  ///
  /// Es la pregunta de los adornos que no pertenecen a una acción concreta —un
  /// encabezado de columna de acciones, una leyenda de «pulsa para editar»—, no la
  /// de un botón: cada botón pregunta por SU capacidad.
  bool get puedeAlgo => puedeCrear || puedeModificar || puedeArchivar;

  @override
  bool operator ==(Object other) =>
      other is CapacidadesDeModulo &&
      other.puedeVer == puedeVer &&
      other.puedeCrear == puedeCrear &&
      other.puedeModificar == puedeModificar &&
      other.puedeArchivar == puedeArchivar;

  @override
  int get hashCode =>
      Object.hash(puedeVer, puedeCrear, puedeModificar, puedeArchivar);

  @override
  String toString() =>
      'CapacidadesDeModulo(ver: $puedeVer, crear: $puedeCrear, '
      'modificar: $puedeModificar, archivar: $puedeArchivar)';
}

/// Cuál se abre al entrar a un apartado: **la primera disponible**.
///
/// No la primera de la lista. En Organización el orden del escritorio empieza por
/// Empresa, que todavía no tiene pantalla; abrir ahí recibiría a todo el mundo con un
/// «Próximamente» teniendo Sucursales y Áreas al lado.
///
/// Si ninguna está mudada devuelve `null`: quien llama no debería haber llegado aquí
/// —[queHacerCon] ya lo dijo— y un «primera de la lista» escondería ese error.
PestanaDeApartado? primeraDisponible(List<PestanaDeApartado> pestanas) {
  for (final p in pestanas) {
    if (p.mudada) return p;
  }

  return null;
}

/// El primer apartado que **tiene algo que abrir**, para recibir a quien entra.
///
/// Sale del mismo registro que todo lo demás, así que el día que Dashboard se mude,
/// la sesión empezará ahí sin tocar una línea de la pantalla.
///
/// Devuelve `null` si no hay ninguno, que sería un producto sin nada dentro: quien
/// llama lo trata como lo que es, un estado imposible, en vez de abrir el primero.
ApartadoDeAdministra? primerApartadoConPantalla({
  required bool esMaestro,
  required Set<String> permisos,
}) {
  for (final a in apartados) {
    if (queHacerCon(a, esMaestro: esMaestro, permisos: permisos) ==
        QueHacerConElApartado.seAbre) {
      return a;
    }
  }

  return null;
}

/// El apartado que **representa** un módulo del servidor, o `null` si ninguno.
///
/// Es lo que permite que el grupo de permisos de `purchases_inventory` se titule
/// «Compras e inventario»: el nombre sale del menú, no de un segundo diccionario.
ApartadoDeAdministra? apartadoDelModulo(String? moduloCode) {
  if (moduloCode == null) return null;

  for (final a in apartados) {
    if (a.modulos.contains(moduloCode)) return a;
  }

  return null;
}

/// ¿Se muestran los permisos de este módulo? `null` es el **núcleo**.
///
/// **EL NÚCLEO SIEMPRE SE MUESTRA**, porque no depende de ningún módulo contratado:
/// configurar la empresa, la auditoría, los usuarios, la estructura y los reportes
/// existen siempre, y parte de eso ya está en la nube.
bool permisosVisiblesDe(String? moduloCode) {
  if (moduloCode == null) return true;

  return apartadoDelModulo(moduloCode)?.mudado ?? false;
}

/// Cómo se titula **el grupo de permisos** de un módulo. `null` es el núcleo.
///
/// Devuelve el nombre del **APARTADO**, no el del módulo, y eso es la decisión: los
/// permisos de nómina se buscan en «Personal», que es donde está la pestaña. Así el
/// panel de permisos y el menú dicen lo mismo **porque sale del mismo sitio**, no
/// porque dos textos coincidan.
///
/// **Un módulo sin apartado NO se oculta**: se muestra con su propio código. Si el
/// servidor sembrara un módulo nuevo, aparecería con su código feo —visible,
/// corregible— en vez de desaparecer con sus permisos dentro, que es la clase de
/// ausencia silenciosa que más cuesta encontrar.
String nombreDelGrupoDePermisos(String? moduloCode) {
  if (moduloCode == null) return 'Núcleo de la empresa';

  return apartadoDelModulo(moduloCode)?.nombre ?? moduloCode;
}

// ⚠️ AQUÍ VIVÍAN LAS SIETE ETIQUETAS DE LOS MÓDULOS, y se retiraron el 19 de octubre
// de 2026 porque el catálogo del servidor ya manda `moduleName`.
//
// POR QUÉ SE RETIRARON Y NO SE DEJARON «POR SI ACASO»: habían DERIVADO. Decían
// «Compras e inventario» y «Clientes y servicios» donde `app.platform_module` dice
// «Compras e Inventario» y «Clientes y Servicios». Dos de siete, y nadie lo notó
// porque una etiqueta que difiere no falla: sólo miente un poco.
//
// Ahora el nombre del módulo lo inyecta la pantalla de auditoría desde el mismo
// catálogo del que ya saca los nombres de permisos. Si no hubiera catálogo, se
// humaniza el código —«Payroll»—, que se ve claramente sin curar y, sobre todo, NO
// dice «Personal» cuando el hecho fue Nómina.
//
// LO QUE SÍ SE QUEDA AQUÍ es [nombreDelGrupoDePermisos], que es otra pregunta: el
// panel agrupa por APARTADO del menú —«Comercial», «Finanzas»—, y eso es una decisión
// del cliente, no un dato del servidor. La diferencia entre las dos la cazó una prueba
// cuando la auditoría empezó a decir «Activó el módulo Personal» siendo `payroll`, y
// sigue vigilada: ahora en `auditoria_legible_test.dart`, donde se puede comparar el
// nombre que manda el servidor contra el apartado que decide la web.
