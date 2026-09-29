/// El catálogo de permisos y módulos del backend SaaS, **espejo exacto** de
/// `PermissionCode` y `ModuleCode` del servidor.
///
/// POR QUÉ EXISTE: es el dueño único de estos literales, igual que `ApiConfig` lo es
/// de `/api/v1` y `CompanyRuta` del prefijo de empresa. Un `'personal.read'` escrito
/// a mano en una pantalla es una cadena que nadie renombra cuando el catálogo cambia,
/// y un error de teclado en ella no falla: **devuelve `false` en silencio** y la
/// acción desaparece de la interfaz sin que nada lo señale.
///
/// LO QUE ESTE ARCHIVO **NO** ES:
///
///  · **No es autorización.** Son nombres. Quién posee qué lo calcula el servidor y
///    viaja en `CompanyContext.effectivePermissions`.
///  · **No es una tabla de traducción.** No hay ni habrá aquí correspondencia con los
///    95 códigos del sistema local: `personal.ver` no es `personal.read` sólo porque
///    se parezcan, y decidir que lo son es trabajo de la migración de cada módulo, con
///    criterio humano.
///  · **No se completa por simetría.** Ver [modulosSinPermisos].
///
/// EL CATÁLOGO ESTÁ INCOMPLETO A PROPÓSITO, y saberlo evita un error concreto: pedir
/// un permiso que el servidor no tiene sembrado **no produce un 403**, produce un
/// **500**, porque para el backend es un endpoint exigiendo algo que nadie creó. Así
/// que aquí sólo están los diez que existen de verdad.
library;

/// Los diez permisos que el backend tiene sembrados hoy.
///
/// Convención del servidor: `modulo.accion`, y un nivel más para lo sensible
/// (`personal.sensitive.read`). Los que no pertenecen a ningún módulo llevan el
/// prefijo `company.` y son **core**: apagar módulos nunca los desactiva.
class PermisoCompany {
  const PermisoCompany._();

  // --- Módulo personal ---------------------------------------------------

  /// Consultar expedientes de personal. Ordinario: el Maestro lo hereda.
  static const String personalRead = 'personal.read';

  /// Crear y corregir personal. **No implica** [personalRead]: son dos códigos
  /// independientes, y el backend los exige por separado.
  static const String personalManage = 'personal.manage';

  /// Consultar evaluaciones —psicológica, socioeconómica, antidoping— y datos
  /// bancarios.
  ///
  /// **PROTEGIDO** (`maestro_auto_grant = false` en el catálogo del servidor): el
  /// Maestro **no lo hereda por su rol**. Lo recibe como concesión explícita al
  /// crearse la Company, y puede delegarlo o retirarlo. Que un dato esté en el
  /// expediente no lo hace visible a todo el que administre personal.
  static const String personalSensitiveRead = 'personal.sensitive.read';

  /// Registrar, corregir y anular evaluaciones, y capturar datos bancarios.
  ///
  /// **PROTEGIDO**, por lo mismo. Y no implica [personalSensitiveRead].
  static const String personalSensitiveManage = 'personal.sensitive.manage';

  // --- Módulo payroll ----------------------------------------------------

  static const String payrollRead = 'payroll.read';

  /// Cerrar nómina. **No existe `payroll.manage`**: el backend demuestra aquí que una
  /// acción sensible merece su propio permiso en vez de caber en un «administrar».
  static const String payrollClose = 'payroll.close';

  // --- Módulo clients_services -------------------------------------------

  static const String clientsServicesRead = 'clients_services.read';

  /// Administrar clientes, servicios, líneas comerciales, contratos y sus archivos.
  ///
  /// Cubre un territorio mucho más amplio que cualquier permiso local equivalente: en
  /// el backend, Contratos y Archivos de cliente **reutilizan este mismo permiso**, sin
  /// código propio.
  static const String clientsServicesManage = 'clients_services.manage';

  // --- Core (sin módulo) -------------------------------------------------

  /// Configurar la empresa y su estructura. **Core**: no depende de ningún módulo.
  static const String companySettingsManage = 'company.settings.manage';

  /// Consultar la auditoría de la empresa. Core.
  static const String companyAuditRead = 'company.audit.read';

  /// Los diez, para pruebas y para recorrer el catálogo. **No es una concesión**:
  /// enumerar los códigos que existen no dice que alguien los posea.
  static const Set<String> todos = {
    personalRead,
    personalManage,
    personalSensitiveRead,
    personalSensitiveManage,
    payrollRead,
    payrollClose,
    clientsServicesRead,
    clientsServicesManage,
    companySettingsManage,
    companyAuditRead,
  };

  /// Los dos **protegidos**, que el Maestro no hereda por su rol.
  ///
  /// Se listan porque es la diferencia semántica más grande con el sistema local
  /// —donde el Maestro posee los 95 códigos sin excepción— y la que produciría una
  /// interfaz mentirosa si alguien tradujera «es Maestro» por «puede todo».
  static const Set<String> protegidos = {
    personalSensitiveRead,
    personalSensitiveManage,
  };

  /// Los **core**: no pertenecen a ningún módulo, así que apagar módulos no los
  /// desactiva.
  static const Set<String> core = {companySettingsManage, companyAuditRead};
}

/// Los siete módulos de la plataforma. Espejo de `app.platform_module`, cuya tabla es
/// la fuente de verdad.
class ModuloCompany {
  const ModuloCompany._();

  static const String personal = 'personal';
  static const String payroll = 'payroll';
  static const String clientsServices = 'clients_services';
  static const String collections = 'collections';
  static const String finance = 'finance';
  static const String purchasesInventory = 'purchases_inventory';
  static const String assets = 'assets';

  static const Set<String> todos = {
    personal,
    payroll,
    clientsServices,
    collections,
    finance,
    purchasesInventory,
    assets,
  };
}

/// Los cuatro módulos que **existen y todavía no tienen ni un permiso**.
///
/// Está aquí para que nadie los complete por simetría. La tentación es real —«si hay
/// `personal.read`, habrá `finance.read`»— y el resultado no es una denegación
/// elegante: el backend responde **500**, porque un código fuera de su catálogo
/// significa que un cliente exige algo que nadie sembró, y eso es un error de
/// programación, no una negativa legítima.
///
/// Cuando el servidor siembre esos permisos, se añaden a [PermisoCompany] y esta lista
/// se encoge.
const Set<String> modulosSinPermisos = {
  ModuloCompany.collections,
  ModuloCompany.finance,
  ModuloCompany.purchasesInventory,
  ModuloCompany.assets,
};
