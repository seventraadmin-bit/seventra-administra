/// Catálogo único de módulos y acciones de permiso (Etapa 11B; rediseño
/// granular en Etapa 1 — "un usuario debe recibir exactamente las
/// facultades que necesita", pedido explícito de Marlon).
///
/// Fuente de verdad para la matriz de administración de permisos, el
/// gate del sidebar/router y el conjunto completo que recibe el
/// Maestro (`todosLosCodigosDePermiso`). Agregar un módulo o una acción
/// especial nueva es agregar una entrada aquí — nunca una migración de
/// `Usuario` ni de `PermisoUsuario` (el código es un TEXT libre, sin
/// columnas rígidas tipo `puedeVerFinanzas`).
library;

enum AccionBase { ver, crear, modificar, archivar, eliminar }

class ModuloPermiso {
  const ModuloPermiso({
    required this.codigo,
    required this.accionesBase,
    this.accionesEspeciales = const [],
    this.grupoVisual,
  });

  /// Para los módulos con ruta propia en el Shell, coincide con el
  /// segmento de ruta (`shellModuleDefs`) — es lo que
  /// `permisoRequeridoParaRuta` deriva del primer segmento de la URL
  /// para gatear el módulo completo (`'usuarios'` es la excepción:
  /// pseudo-módulo sin ruta propia, gatea `/configuracion`).
  ///
  /// Etapa 1: varios módulos son subdominios lógicos SIN ruta propia
  /// (viven anidados dentro de otro — ej. `ingresos`/`egresos`/`deudas`
  /// dentro de la pestaña Finanzas, `clientes`/`servicios` dentro de
  /// Comercial) — mismo precedente ya establecido por `nomina` (vive
  /// dentro de `/personal/nomina`, nunca gatea nada por sí solo a nivel
  /// router: `permisoRequeridoParaRuta` solo lee el primer segmento de
  /// la URL, que sigue siendo `finanzas`/`comercial`/`personal`). Estos
  /// subdominios existen únicamente para que la matriz de permisos y
  /// `autorizarUseCase` puedan otorgar/exigir la facultad exacta.
  final String codigo;

  /// Subconjunto real de acciones que aplican a este módulo — nunca se
  /// muestra un permiso ficticio solo para llenar la matriz (ej.
  /// Reportes solo tiene `ver`; Usuarios no tiene ninguna acción base,
  /// solo el permiso especial `usuarios.administrar`). Los subdominios
  /// nuevos de Etapa 1 (Ingresos, Egresos, Clientes, etc.) usan un
  /// conjunto vacío — su granularidad real (crear/corregir/cancelar/
  /// cambiarEstatus) no encaja en el enum rígido `AccionBase` y vive
  /// enteramente en `accionesEspeciales`.
  final Set<AccionBase> accionesBase;

  /// Códigos sensibles fuera de la matriz base — `'modulo.accionEspecifica'`.
  final List<String> accionesEspeciales;

  /// Agrupa visualmente varias entradas bajo un mismo encabezado en la
  /// matriz de administración (ej. `'finanzas'` agrupa Ingresos,
  /// Egresos, Deudas y crédito, Pagos y cobranza, Cuentas financieras y
  /// Categorías financieras bajo "Finanzas") — puramente cosmético,
  /// nunca participa en `autorizarUseCase`/`hasCode`. `null` = tarjeta
  /// de nivel superior, sin agrupar (comportamiento de siempre).
  final String? grupoVisual;

  String codigoPara(AccionBase accion) => '$codigo.${accion.name}';

  Set<String> get todosLosCodigos => {
        for (final a in accionesBase) codigoPara(a),
        ...accionesEspeciales,
      };
}

/// Sin `'dashboard'`: no tiene permiso propio, cualquier sesión válida
/// entra (ver `shell_permissions.dart`). Sin `'documentos'`/`'activos'`:
/// nunca existieron como módulos reales, no hay nada que administrar.
const modulosPermiso = <ModuloPermiso>[
  ModuloPermiso(
    codigo: 'personal',
    accionesBase: {AccionBase.ver, AccionBase.crear, AccionBase.modificar, AccionBase.archivar},
    // Etapa 1 (rediseño granular): `personal.archivar` estaba 100%
    // muerto (confirmado por auditoría) — se reutiliza aquí para "dar
    // de baja"/"reingresar" un Empleado, que dejan de compartir código
    // con la corrección de expediente (`personal.modificar`). Decisión
    // de producto de Marlon: "dar de baja NO es simplemente modificar
    // sus datos". Baja y Reingreso comparten el mismo código
    // deliberadamente — son la misma clase de decisión (transición de
    // ciclo laboral, normalmente la misma autoridad de RRHH), y
    // Reingreso es la reversión operativa de una Baja; separarlos
    // fragmentaría sin reflejar una diferencia real de responsabilidad.
    //
    // `personal.modificar` conserva TODO lo demás del expediente
    // (fotografía, domicilio, documentos, perfil psicológico, estudio
    // socioeconómico, antidoping, datos generales, asignación/cambio/
    // retiro de Servicio) — ninguna de esas operaciones mostró una
    // diferencia de responsabilidad material entre sí en la auditoría.
    //
    // `personal.gestionarDescuentos` se retira de aquí (Etapa 1): se
    // reemplaza por el módulo dedicado `descuentos` más abajo.
    //
    // `tiempoExtra.crear/corregir/cancelar` NO se mueven a su propio
    // módulo: ya están correctamente separados desde la etapa anterior
    // y moverlos sería un refactor cosmético sin beneficio funcional
    // (Etapa 1 solo divide donde hay una facultad hoy colapsada).
    accionesEspeciales: [
      'personal.cambiarSueldo',
      'tiempoExtra.crear',
      'tiempoExtra.corregir',
      'tiempoExtra.cancelar',
    ],
  ),
  // Etapa 1 (nuevo): reemplaza el código único `personal.gestionarDescuentos`
  // — mismo criterio que Tiempos Extra en la etapa anterior. `descuentos.ver`
  // es nuevo: antes Descuentos no tenía NINGÚN guardia de lectura propio
  // (cargaba datos sin verificar nada, protegido solo porque su pestaña
  // vive dentro de Personal) — mismo hueco que tenía Nómina antes de la
  // Etapa 0, cerrado aquí con el mismo patrón (`tieneNomina`/`nomina.ver`).
  // `grupoVisual: 'personal'` (junto con el módulo de arriba) es
  // puramente para que la matriz de administración los muestre
  // contiguos bajo un mismo encabezado — el catálogo los declara
  // consecutivos a propósito para que esa agrupación sea un simple
  // barrido contiguo, sin lógica de reordenamiento en la UI.
  ModuloPermiso(
    codigo: 'descuentos',
    accionesBase: {},
    accionesEspeciales: ['descuentos.ver', 'descuentos.crear', 'descuentos.corregir', 'descuentos.cancelar'],
    grupoVisual: 'personal',
  ),
  ModuloPermiso(
    codigo: 'nomina',
    accionesBase: {AccionBase.ver, AccionBase.crear, AccionBase.modificar},
    // Etapa 1: `nomina.pagar` colapsaba 3 facultades distintas
    // (registrar/corregir/cancelar un pago) — separadas aquí. El PDF de
    // dispersión sigue gateado por `nomina.registrarPago` (decisión
    // deliberada preexistente, Etapa 15: expone CLABE de todos los
    // empleados en un solo archivo — "quien puede ejecutar el dinero
    // puede generar la hoja para dispersarlo"), nunca degradada a solo
    // `nomina.ver`. `nomina.modificar` conserva su alcance de siempre
    // ("modificar borrador": actualizar desde Personal + editar
    // renglón, ambas solo aplican con `estatus == borrador`).
    //
    // Etapa 4 (Nómina — corrección/cancelación/trazabilidad integral):
    // dos facultades nuevas, ninguna reutiliza un código existente
    // (reportado antes de crearlas, per el pedido) — `nomina.modificar`
    // está documentado y probado como exclusivo de Borrador, reusarlo
    // para tocar una Nómina ya `cerrada`/`pagada` le daría ese poder a
    // cualquiera que solo debiera poder editar el borrador:
    // - `nomina.corregir`: corregir un renglón de una Nómina ya
    //   `cerrada`/`pagada` (`CorregirRenglonNominaUseCase`) — motivo
    //   obligatorio, nunca reescribe lo ya pagado.
    // - `nomina.cancelar`: cancelar la Nómina COMPLETA
    //   (`CancelarNominaUseCase`) — solo Borrador o Cerrada-sin-pagos,
    //   nunca sobre una Nómina con `PagoNomina` real (ahí se cancela
    //   pago por pago, `nomina.cancelarPago`).
    accionesEspeciales: [
      'nomina.cerrar',
      'nomina.registrarPago',
      'nomina.corregirPago',
      'nomina.cancelarPago',
      'nomina.corregir',
      'nomina.cancelar',
    ],
  ),
  ModuloPermiso(
    codigo: 'finanzas',
    // Etapa 1: `finanzas.crear/modificar/archivar` colapsaban 7
    // subdominios financieros reales (Ingresos, Egresos, Deudas y
    // crédito, Pagos y cobranza, Cuentas financieras, Categorías
    // financieras, Cuentas por cobrar) bajo 3 códigos únicos — "no
    // quiero que otorgar capacidad para corregir un Egreso permita
    // también modificar una TDC" (pedido explícito de Marlon). Se
    // divide en los 7 módulos siguientes; `finanzas.ver` se conserva
    // como único gate de visibilidad de toda el área (sin fragmentar
    // el `ver`, mismo criterio que Comercial).
    accionesBase: {AccionBase.ver},
  ),
  ModuloPermiso(
    codigo: 'ingresos',
    accionesBase: {},
    accionesEspeciales: ['ingresos.crear', 'ingresos.corregir', 'ingresos.cancelar'],
    grupoVisual: 'finanzas',
  ),
  ModuloPermiso(
    codigo: 'egresos',
    accionesBase: {},
    accionesEspeciales: ['egresos.crear', 'egresos.corregir', 'egresos.cancelar'],
    grupoVisual: 'finanzas',
  ),
  // Etapa 1: "registrar deuda nueva" y "registrar pago a una deuda ya
  // existente" compartían `finanzas.crear` — son facultades distintas
  // (abrir un pasivo nuevo vs. aplicar un pago a uno vigente),
  // separadas aquí como `deudas.crear`/`deudas.registrarPago`.
  // Etapa 9: `deudas.corregirPago`/`deudas.cancelarPago` son facultades
  // REALMENTE distintas de `deudas.registrarPago` — registrar un pago
  // captura un hecho nuevo; corregirlo o cancelarlo reescribe el efecto
  // financiero de uno ya asentado (devuelve dinero a una cuenta, revive
  // una deuda liquidada, libera crédito de una tarjeta). Mismo criterio
  // exacto que `nomina.registrarPago`/`corregirPago`/`cancelarPago`.
  //
  // Deliberadamente SIN migración de datos: nadie las recibe
  // automáticamente. No existe equivalencia histórica demostrable —
  // hasta esta etapa corregir o cancelar un pago individual era
  // imposible para todos, así que nadie "ya tenía" esa facultad bajo
  // otro código. Otorgarlas a quien tenía `deudas.registrarPago` sería
  // ampliar acceso en silencio, justo lo contrario del criterio
  // conservador de `migrar_permisos_granulares_v71.dart` (que solo
  // AGREGA lo equivalente a lo que un código viejo ya cubría). El
  // Usuario Maestro las tiene por su bypass natural, y el resto se
  // asignan a mano desde Configuración → Usuarios.
  ModuloPermiso(
    codigo: 'deudas',
    accionesBase: {},
    accionesEspeciales: [
      'deudas.crear',
      'deudas.registrarPago',
      'deudas.corregirPago',
      'deudas.cancelarPago',
      'deudas.corregir',
      'deudas.cancelar',
    ],
    grupoVisual: 'finanzas',
  ),
  // Incluye Complemento de pago (ComplementoPago es un sub-documento
  // fiscal de Pago, mismo dueño real — no amerita módulo propio).
  // `pagos.cancelarAplicacion` es distinto de `pagos.cancelar`: cancelar
  // solo una aplicación a una Cuenta por cobrar es un alcance más
  // estrecho que cancelar el Pago completo (compartían el mismo código
  // antes de esta etapa).
  ModuloPermiso(
    codigo: 'pagos',
    accionesBase: {},
    accionesEspeciales: ['pagos.registrar', 'pagos.corregir', 'pagos.cancelar', 'pagos.cancelarAplicacion'],
    grupoVisual: 'finanzas',
  ),
  // `cuentasFinancieras.cambiarEstatus` gatea activar/desactivar (un
  // solo toggle, dos direcciones) — pedido explícito de Marlon como
  // facultad separada de corregir los datos de la cuenta.
  ModuloPermiso(
    codigo: 'cuentasFinancieras',
    accionesBase: {},
    accionesEspeciales: [
      'cuentasFinancieras.crear',
      'cuentasFinancieras.corregir',
      'cuentasFinancieras.cambiarEstatus',
      // Transferir mueve dinero real entre cuentas, que es
      // cualitativamente distinto de editar la ficha de una cuenta:
      // por eso no reutiliza `corregir`.
      'cuentasFinancieras.transferir',
    ],
    grupoVisual: 'finanzas',
  ),
  ModuloPermiso(
    codigo: 'categoriasFinancieras',
    accionesBase: {},
    accionesEspeciales: ['categoriasFinancieras.crear', 'categoriasFinancieras.corregir', 'categoriasFinancieras.archivar'],
    grupoVisual: 'finanzas',
  ),
  // CxC es reactiva a `DocumentoPorEmitir` — no tiene crear/eliminar
  // propio (confirmado por auditoría: `crear()` solo se invoca
  // internamente al emitir un documento, nunca desde una pantalla
  // gateada de Finanzas; eliminación física decidida explícitamente
  // fuera de alcance en la Etapa 7 — ver el reporte de esa etapa).
  //
  // Etapa 7: `corregirFecha` evoluciona a `corregir` (ahora cubre
  // también `observaciones`, categoría C completa — nunca solo la
  // fecha), migrado de forma aditiva/idempotente (v74, ver
  // `migrar_correccion_cuenta_por_cobrar_v74.dart`: cada usuario que
  // ya tenía `corregirFecha` recibe `corregir`, nunca se le quita
  // nada). `reprogramarCobro` (decisión de cobranza, incluye quitar
  // una reprogramación — acción inversa, misma facultad) se conserva
  // tal cual. `cancelar` es nuevo (Etapa 7, Sección 6: anula la
  // obligación completa cuando no tiene aplicaciones de Pago activas).
  ModuloPermiso(
    codigo: 'cuentaPorCobrar',
    accionesBase: {},
    accionesEspeciales: ['cuentaPorCobrar.corregir', 'cuentaPorCobrar.reprogramarCobro', 'cuentaPorCobrar.cancelar'],
    grupoVisual: 'finanzas',
  ),
  ModuloPermiso(
    codigo: 'compras',
    // Etapa 1: antes solo existían `ver/crear/archivar` — corregir
    // reutilizaba `compras.crear` (mismo hueco que Marlon pidió cerrar
    // explícitamente: "no quiero que un usuario necesite permiso de
    // crear para poder corregir"). `compras.archivar` se retira del
    // set base y se reemplaza por el código especial `compras.cancelar`
    // (mismo verbo que el resto del rediseño).
    accionesBase: {AccionBase.ver, AccionBase.crear},
    accionesEspeciales: ['compras.corregir', 'compras.cancelar'],
  ),
  ModuloPermiso(
    codigo: 'inventario',
    // Etapa 1: "modificar metadatos ≠ ajustar existencia" (pedido
    // explícito de Marlon) — antes ambas compartían `inventario.modificar`.
    // `inventario.corregir` cubre metadata de Artículo/unidad y también
    // la gestión de una asignación ya existente (cerrar, cambiar
    // responsable, reemplazar, adjuntar resguardo firmado — ninguna
    // cambia cantidad, decisión confirmada con Marlon: no ameritan
    // facultad propia). `inventario.ajustarExistencia` cubre
    // exclusivamente el ajuste manual de cantidad.
    accionesBase: {AccionBase.ver, AccionBase.crear, AccionBase.archivar},
    accionesEspeciales: ['inventario.corregir', 'inventario.ajustarExistencia'],
  ),
  ModuloPermiso(
    codigo: 'vehiculos',
    // Etapa 1: `vehiculos.crear` colapsaba alta de vehículo + documento
    // + mantenimiento + asignación (4 acciones) — "alta de vehículo ≠
    // mantenimiento/documentos/asignación" (pedido explícito de
    // Marlon). `vehiculos.crear` se acota a la alta del expediente;
    // `vehiculos.operar` agrupa las 3 acciones operativas sobre un
    // vehículo YA existente (decisión confirmada con Marlon: mismo rol
    // logístico típico, no ameritan 3 facultades separadas).
    // `vehiculos.modificar`/`archivar` conservan su alcance de siempre
    // (corrección de datos/estatus/fotografía/kilometraje, baja).
    //
    // `vehiculos.cancelar` (schemaVersion 80) es la ÚNICA facultad de
    // Vehículos que revierte dinero real: anular un mantenimiento
    // cancela su Egreso de `CuentaFinanciera`, o libera su cargo de
    // TDC. Va aparte de `vehiculos.operar` por el mismo criterio ya
    // aplicado en Compras (`compras.cancelar`), Tiempos Extra
    // (`tiempoExtra.cancelar`) y Nómina (`nomina.cancelarPago`):
    // quien captura la operación no necesariamente puede revertirla.
    // Corregir SÍ se queda en `vehiculos.operar` — una corrección
    // ajusta el importe, no lo devuelve.
    accionesBase: {AccionBase.ver, AccionBase.crear, AccionBase.modificar, AccionBase.archivar},
    accionesEspeciales: ['vehiculos.operar', 'vehiculos.cancelar'],
  ),
  ModuloPermiso(
    codigo: 'telefonia',
    // Etapa 1: `telefonia.crear` colapsaba alta de línea + asignación +
    // recarga (dinero real) — "alta de línea telefónica ≠ recarga que
    // implica dinero real" (pedido explícito de Marlon).
    // `telefonia.crear` conserva alta + asignación; `telefonia.recargar`
    // es la nueva facultad financiera dedicada (recarga + su
    // comprobante).
    accionesBase: {AccionBase.ver, AccionBase.crear, AccionBase.modificar, AccionBase.archivar},
    accionesEspeciales: ['telefonia.verCredenciales', 'telefonia.recargar'],
  ),
  ModuloPermiso(
    codigo: 'organizacion',
    accionesBase: {AccionBase.ver, AccionBase.crear, AccionBase.modificar, AccionBase.archivar},
  ),
  ModuloPermiso(
    codigo: 'comercial',
    // Etapa 1: `comercial.crear/modificar/archivar` colapsaban 4
    // subdominios reales (Clientes, Servicios, Configuración de cobro,
    // Agenda comercial) — "comercial.modificar actualmente abarca
    // demasiadas entidades" (pedido explícito de Marlon). Se divide en
    // los 4 módulos siguientes; `comercial.ver` se conserva como único
    // gate de visibilidad de toda el área (Organización — Sucursal/
    // Área/Puesto/Empresa — ya usa su propio código `organizacion.*`,
    // sin relación con este split).
    accionesBase: {AccionBase.ver},
  ),
  // Incluye Contacto/EntidadFiscal/ClientePortal (sub-registros de
  // Cliente, mismo dueño real) y el logo. `clientes.archivar` gatea
  // únicamente los 3 cambios de ciclo de vida que ya usaban
  // `comercial.archivar` (archivar Contacto, cambiar ciclo de vida de
  // EntidadFiscal/ClientePortal) — Cliente en sí usa `corregir` para su
  // propio cambio de estatus, nunca `archivar`.
  ModuloPermiso(
    codigo: 'clientes',
    accionesBase: {},
    accionesEspeciales: ['clientes.crear', 'clientes.corregir', 'clientes.archivar'],
    grupoVisual: 'comercial',
  ),
  // Incluye LineaComercial completa (vive dentro de un Servicio, mismo
  // dueño real — no amerita módulo propio).
  ModuloPermiso(
    codigo: 'servicios',
    accionesBase: {},
    accionesEspeciales: ['servicios.crear', 'servicios.corregir'],
    grupoVisual: 'comercial',
  ),
  // Separado de Servicios: configurar cómo se cobra un Servicio puede
  // ser una facultad de un rol distinto (facturación/administración) al
  // que opera el Servicio en sí.
  ModuloPermiso(
    codigo: 'configuracionCobro',
    accionesBase: {},
    accionesEspeciales: ['configuracionCobro.crear', 'configuracionCobro.corregir'],
    grupoVisual: 'comercial',
  ),
  // schemaVersion 87 — Servicios Eventuales. Sin `ver` propio, mismo
  // criterio que Clientes/Servicios: `comercial.ver` ya gatea toda el
  // área y un permiso sin consumidor sólo ensucia la matriz.
  // schemaVersion 87 — Servicios Eventuales. Subdominio de Comercial
  // con permisos propios: un eventual lo captura quien atiende la
  // solicitud, pero PAGAR a quien lo cubrió mueve dinero real (Egreso
  // de una Cuenta, o cargo a una tarjeta) y es una facultad distinta,
  // mismo criterio que `telefonia.recargar` frente a
  // `telefonia.crear`. `revertirPago` va aparte de `pagar` por la
  // misma razón que `compras.cancelar`/`vehiculos.cancelar`: quien
  // captura la operación no necesariamente puede deshacerla.
  ModuloPermiso(
    codigo: 'serviciosEventuales',
    accionesBase: {},
    accionesEspeciales: [
      'serviciosEventuales.crear',
      'serviciosEventuales.corregir',
      'serviciosEventuales.cancelar',
      'serviciosEventuales.pagar',
      'serviciosEventuales.revertirPago',
      'serviciosEventuales.cobrar',
      'serviciosEventuales.facturar',
    ],
    grupoVisual: 'comercial',
  ),
  ModuloPermiso(
    codigo: 'agendaComercial',
    accionesBase: {},
    accionesEspeciales: ['agendaComercial.crear', 'agendaComercial.corregir'],
    grupoVisual: 'comercial',
  ),
  ModuloPermiso(
    codigo: 'reportes',
    accionesBase: {AccionBase.ver},
  ),
  // Etapa "Usuarios, permisos y UX de seguridad": `usuarios.administrar`
  // dejó de ser un todo-o-nada. Cubría a la vez crear/editar cuentas,
  // resetear contraseñas ajenas, otorgar permisos y consultar la
  // auditoría del sistema — responsabilidades de sensibilidad muy
  // distinta. `usuarios.administrar` CONSERVA su código (alta/edición de
  // cuentas, y sigue gateando la ruta `/configuracion` completa) y se le
  // separan las dos facultades que de verdad ameritan decidirse aparte.
  //
  // `usuarios.otorgarPermisos` es la más sensible de las tres: es la
  // facultad con la que alguien podría ampliar el alcance de una cuenta
  // (la propia incluida). Se otorga a mano, nunca por venir en el mismo
  // paquete que "editar el nombre de un usuario".
  ModuloPermiso(
    codigo: 'usuarios',
    accionesBase: {},
    accionesEspeciales: ['usuarios.administrar', 'usuarios.otorgarPermisos', 'usuarios.resetearPassword'],
  ),
  // Auditoría es SOLO LECTURA por diseño: el historial es append-only y
  // no existe ninguna acción de UI que lo modifique o borre, así que
  // `ver` es la única facultad posible — nunca un `auditoria.corregir`
  // que no tendría consumidor. Antes exigía `usuarios.administrar`:
  // consultar quién hizo qué obligaba a poder administrar cuentas, y al
  // revés. Son cosas distintas.
  ModuloPermiso(
    codigo: 'auditoria',
    accionesBase: {AccionBase.ver},
    accionesEspeciales: [],
  ),
];

/// Todos los códigos conocidos hoy — lo que recibe un Usuario Maestro,
/// recalculado siempre en el momento (nunca una copia congelada
/// guardada en `PermisoUsuario`), así un módulo agregado después ya
/// "existe" para el Maestro sin ninguna migración de datos.
Set<String> todosLosCodigosDePermiso() {
  return {for (final m in modulosPermiso) ...m.todosLosCodigos};
}

/// Normaliza un conjunto de códigos para que ninguna acción de un
/// módulo quede concedida sin `ver` en ese mismo módulo (Etapa 11B,
/// dependencia Ver → nunca `crear=true, ver=false`). Función pura,
/// compartida por la UI (mantiene los checkboxes coherentes en vivo) y
/// por `GuardarPermisosUsuarioUseCase` (red de seguridad — nunca
/// persiste una combinación absurda aunque la UI tuviera un bug).
///
/// Dirección deliberada: siempre "corrige hacia adelante" (agrega
/// `ver`), nunca retira una acción que el llamador pidió explícitamente
/// — la dirección contraria ("si se desmarca Ver, desmarcar las
/// demás") es responsabilidad de la UI en el momento de la interacción
/// (ver `gestionar_permisos_usuario_dialog.dart`), no de esta función.
/// Los códigos especiales (`accionesEspeciales`) no participan de esta
/// regla — son independientes de `ver` (los subdominios de Etapa 1 sin
/// `ver` propio, ej. `ingresos`/`clientes`, heredan visibilidad de su
/// `grupoVisual` a nivel de pantalla, nunca de esta función).
Set<String> normalizarPermisos(Set<String> codigos) {
  final resultado = Set<String>.from(codigos);
  for (final modulo in modulosPermiso) {
    if (!modulo.accionesBase.contains(AccionBase.ver)) continue;
    final tieneOtraAccion = modulo.accionesBase
        .where((a) => a != AccionBase.ver)
        .any((a) => resultado.contains(modulo.codigoPara(a)));
    if (tieneOtraAccion) resultado.add(modulo.codigoPara(AccionBase.ver));
  }
  return resultado;
}
