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
    this.permiso,
    this.soloMaestro = false,
  });

  /// Clave corta y estable. Se usa para las `Key` de prueba y para saber qué pintar.
  final String id;

  final String nombre;

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
      PestanaDeApartado(id: 'empresa', nombre: 'Empresa', mudada: false),
      PestanaDeApartado(id: 'sucursales', nombre: 'Sucursales', mudada: true),
      PestanaDeApartado(id: 'puestos', nombre: 'Puestos', mudada: false),
      PestanaDeApartado(id: 'areas', nombre: 'Áreas', mudada: true),
    ],
  ),

  ApartadoDeAdministra(
    ruta: '/comercial',
    nombre: 'Comercial',
    icono: Icons.handshake_outlined,
    modulos: {ModuloCompany.clientsServices},
    pestanas: [],
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
        soloMaestro: true,
      ),
      PestanaDeApartado(
        id: 'auditoria',
        nombre: 'Auditoría',
        mudada: true,
        permiso: PermisoCompany.companyAuditRead,
      ),
    ],
  ),
];

/// Qué hacer con un apartado para una persona concreta.
///
/// **TRES CASOS, Y CONFUNDIR LOS DOS ÚLTIMOS SERÍA MENTIR.**
enum QueHacerConElApartado {
  /// Tiene al menos una pestaña que esta persona puede abrir.
  seAbre,

  /// **No está mudado.** Aparece en el menú con «Próximamente», y al abrirlo explica
  /// que todavía se usa desde el escritorio.
  proximamente,

  /// Está mudado **pero esta persona no tiene nada dentro**.
  ///
  /// No aparece. Es el caso real de quien no es Maestro y no puede leer la auditoría:
  /// Configuración existe y no es para él. Decirle «Próximamente» le prometería algo
  /// que ya llegó, y dejarlo entrar a un apartado vacío es un callejón sin salida.
  noAparece,
}

/// La decisión, **sin widgets y sin contexto**: recibe lo que el servidor confirmó ya
/// convertido en dos datos simples.
///
/// Está aquí y no en la pantalla para poder probarla sola, que es donde se ven los
/// tres casos de un golpe.
QueHacerConElApartado queHacerCon(
  ApartadoDeAdministra apartado, {
  required bool esMaestro,
  required Set<String> permisos,
}) {
  if (!apartado.mudado) return QueHacerConElApartado.proximamente;

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

/// Cómo se llama **el módulo en sí**, que NO es lo mismo que su apartado.
///
/// ⚠️ **LA DIFERENCIA LA CAZÓ UNA PRUEBA, Y VALE LA PENA ESCRIBIRLA.** Al unificar los
/// nombres en este archivo, la auditoría empezó a decir «Activó el módulo Personal»
/// cuando el hecho registrado era `module: payroll`. Eso es **falso**: lo que se
/// encendió fue Nómina, no todo Personal.
///
/// Son dos preguntas distintas y tienen dos respuestas:
///
///  · **el panel de permisos** agrupa por apartado → [nombreDelGrupoDePermisos];
///  · **la auditoría** nombra el hecho exacto → esto.
///
/// Los siete son los de `app.platform_module`, cuya tabla es la fuente de verdad; aquí
/// sólo están sus etiquetas, porque el catálogo del servidor **no manda un nombre**.
const Map<String, String> nombresDeModulo = {
  ModuloCompany.personal: 'Personal',
  ModuloCompany.payroll: 'Nómina',
  ModuloCompany.finance: 'Finanzas',
  ModuloCompany.collections: 'Cobranza',
  ModuloCompany.purchasesInventory: 'Compras e inventario',
  ModuloCompany.assets: 'Activos',
  ModuloCompany.clientsServices: 'Clientes y servicios',
};

/// El nombre de un módulo. **Un código desconocido se devuelve tal cual**, nunca se
/// oculta: un módulo nuevo del servidor aparecería feo y corregible.
String nombreDelModulo(String moduloCode) =>
    nombresDeModulo[moduloCode] ?? moduloCode;
