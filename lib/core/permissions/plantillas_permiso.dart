import 'modulos_permiso.dart';

/// Plantillas de permisos (Etapa "Usuarios, permisos y UX de
/// seguridad", punto 12) — decisión de producto de Marlon: **plantillas
/// en código, sin entidad nueva**.
///
/// Qué SON: un punto de partida para no armar a mano un conjunto de 20+
/// códigos cada vez que entra alguien a un puesto conocido. Aplicar una
/// plantilla en el selector solo PRECARGA casillas; lo que se guarda son
/// siempre códigos individuales en `PermisoUsuario`, exactamente como si
/// se hubieran marcado uno por uno.
///
/// Qué NO son:
///  - No son roles. No se persisten, no se referencian desde `Usuario`,
///    no existe una tabla de plantillas. Cambiar una plantilla mañana no
///    altera a nadie que ya tenga permisos guardados — y eso es
///    deliberado: un rol vivo convertiría un cambio de catálogo en una
///    ampliación silenciosa de acceso a cuentas existentes.
///  - No son una segunda fuente de verdad de autorización. Nada en la
///    app consulta plantillas para decidir si alguien puede algo; el
///    único juez sigue siendo `PermissionService` sobre los códigos
///    guardados.
///
/// Reglas que las plantillas respetan, y que fija
/// `plantillas_permiso_test.dart`:
///  1. Ninguna plantilla otorga `usuarios.*` ni `auditoria.ver`.
///     Administrar cuentas, otorgar permisos, resetear contraseñas y
///     leer la auditoría son facultades de gobierno: se conceden a mano,
///     una por una, nunca de paquete por "el puesto de esta persona".
///  2. Ninguna plantilla otorga `telefonia.verCredenciales`. Es acceso a
///     secretos guardados cifrados, del mismo orden que la Bóveda.
///  3. Ningún código de plantilla queda fuera del catálogo (una
///     plantilla con un código muerto concedería nada, en silencio).
///  4. Respaldo y Bóveda no aparecen porque no tienen código: son
///     Maestro-only por `esMaestro`, y una plantilla no puede alcanzarlas
///     ni por accidente.
class PlantillaPermiso {
  const PlantillaPermiso({required this.codigo, required this.codigos});

  /// Identificador estable para etiquetas y pruebas — nunca se guarda.
  final String codigo;

  /// Códigos que precarga. Se normalizan al aplicarse.
  final Set<String> codigos;
}

/// Todos los códigos de lectura del catálogo, salvo la auditoría
/// (facultad de gobierno, regla 1). Se calcula del catálogo real para
/// que un módulo nuevo entre solo en "Solo consulta" sin editar esta
/// lista — que es exactamente lo que "solo consulta" significa.
Set<String> _todosLosVer() {
  return {
    for (final codigo in todosLosCodigosDePermiso())
      if (codigo.endsWith('.ver') && codigo != 'auditoria.ver') codigo,
  };
}

/// Orden de presentación = el del negocio, de la plantilla más común a
/// la más acotada.
final plantillasPermiso = <PlantillaPermiso>[
  // Expediente del personal y su ciclo laboral. Sin `personal.cambiarSueldo`
  // a propósito: cambiar la percepción de alguien es una decisión de
  // autoridad distinta a mantener su expediente, y se concede aparte.
  const PlantillaPermiso(
    codigo: 'recursosHumanos',
    codigos: {
      'personal.ver',
      'personal.crear',
      'personal.modificar',
      'personal.archivar',
      'tiempoExtra.crear',
      'tiempoExtra.corregir',
      'tiempoExtra.cancelar',
      'descuentos.ver',
      'descuentos.crear',
      'descuentos.corregir',
      'descuentos.cancelar',
      'nomina.ver',
      'organizacion.ver',
      'reportes.ver',
    },
  ),
  // Arma y cierra la Nómina, pero NO ejecuta su dispersión: pagar es
  // mover dinero, y vive en la plantilla de Tesorería.
  const PlantillaPermiso(
    codigo: 'nomina',
    codigos: {
      'personal.ver',
      'descuentos.ver',
      'nomina.ver',
      'nomina.crear',
      'nomina.modificar',
      'nomina.cerrar',
      'nomina.corregir',
      'nomina.cancelar',
      'reportes.ver',
    },
  ),
  // Movimiento de dinero: ingresos, egresos, deudas y crédito, cobranza,
  // cuentas y catálogos financieros, más los pagos de Nómina.
  const PlantillaPermiso(
    codigo: 'tesoreria',
    codigos: {
      'finanzas.ver',
      'ingresos.crear',
      'ingresos.corregir',
      'ingresos.cancelar',
      'egresos.crear',
      'egresos.corregir',
      'egresos.cancelar',
      'deudas.crear',
      'deudas.corregir',
      'deudas.cancelar',
      'deudas.registrarPago',
      'deudas.corregirPago',
      'deudas.cancelarPago',
      'pagos.registrar',
      'pagos.corregir',
      'pagos.cancelar',
      'pagos.cancelarAplicacion',
      'cuentaPorCobrar.corregir',
      'cuentaPorCobrar.reprogramarCobro',
      'cuentaPorCobrar.cancelar',
      'cuentasFinancieras.crear',
      'cuentasFinancieras.corregir',
      'cuentasFinancieras.cambiarEstatus',
      'categoriasFinancieras.crear',
      'categoriasFinancieras.corregir',
      'categoriasFinancieras.archivar',
      'nomina.ver',
      'nomina.registrarPago',
      'nomina.corregirPago',
      'nomina.cancelarPago',
      'reportes.ver',
    },
  ),
  // Clientes, servicios contratados, condiciones de cobro y agenda.
  const PlantillaPermiso(
    codigo: 'comercial',
    codigos: {
      'comercial.ver',
      'clientes.crear',
      'clientes.corregir',
      'clientes.archivar',
      'servicios.crear',
      'servicios.corregir',
      'configuracionCobro.crear',
      'configuracionCobro.corregir',
      'agendaComercial.crear',
      'agendaComercial.corregir',
      'reportes.ver',
    },
  ),
  // Activos operativos: inventario, vehículos y telefonía. Sin
  // `telefonia.verCredenciales` (regla 2).
  const PlantillaPermiso(
    codigo: 'operaciones',
    codigos: {
      'inventario.ver',
      'inventario.crear',
      'inventario.corregir',
      'inventario.archivar',
      'inventario.ajustarExistencia',
      'vehiculos.ver',
      'vehiculos.crear',
      'vehiculos.modificar',
      'vehiculos.archivar',
      'vehiculos.operar',
      // `vehiculos.cancelar` NO va aquí (schemaVersion 80), a propósito:
      // Operaciones captura el mantenimiento de la flotilla, pero anular
      // uno revierte un Egreso real de banco o libera un cargo de TDC —
      // eso es una facultad financiera, y esta plantilla no otorga
      // ninguna otra (no tiene egresos.*, deudas.* ni cuentasFinancieras.*).
      // Concederlo aquí volvería la separación decorativa. Mismo trato
      // exacto que `compras.cancelar`, que tampoco está en Operaciones.
      'telefonia.ver',
      'telefonia.crear',
      'telefonia.modificar',
      'telefonia.archivar',
      'telefonia.recargar',
      'compras.ver',
      'reportes.ver',
    },
  ),
  // Abastecimiento: registra compras y ve a dónde entran.
  const PlantillaPermiso(
    codigo: 'compras',
    codigos: {
      'compras.ver',
      'compras.crear',
      'compras.corregir',
      'compras.cancelar',
      'inventario.ver',
      'reportes.ver',
    },
  ),
  // Lectura transversal, sin ninguna facultad de mutación.
  PlantillaPermiso(codigo: 'consulta', codigos: {..._todosLosVer()}),
];

/// Códigos que aplica una plantilla, ya normalizados — una acción nunca
/// llega sin el `ver` de su módulo, misma regla que al guardar.
Set<String> codigosDePlantilla(String codigoPlantilla) {
  final plantilla = plantillasPermiso.where((p) => p.codigo == codigoPlantilla).firstOrNull;
  if (plantilla == null) return {};
  return normalizarPermisos(plantilla.codigos);
}
