import 'buscar_auditoria_usecase.dart';

/// A dónde lleva "Ver origen" desde una fila de la Auditoría central, y
/// bajo qué permiso.
///
/// Se resuelve SIEMPRE por id real (`destinoId` o, si no hay,
/// `registroId`) — nunca por folio ni por texto: un folio se repite
/// entre dominios, se corrige, y no es clave de nada.
///
/// Deliberadamente **no** decide si el usuario puede ir: solo dice a qué
/// ruta llevaría. Quién puede abrirla lo sigue resolviendo el mismo
/// mecanismo de siempre — `permisosQueAbrenRuta` para los módulos
/// normales y el candado de Maestro para Bóveda. Así `auditoria.ver`
/// nunca se convierte en un bypass: ver que algo ocurrió y poder abrir
/// el expediente donde ocurrió son dos facultades distintas.
class DestinoAuditoria {
  const DestinoAuditoria({required this.ruta, this.exigeMaestro = false});

  final String ruta;

  /// `true` solo para Bóveda: su ruta ya es Maestro-only en el router
  /// (Etapa 14D) y con doble candado `exigirMaestro` en sus providers.
  /// Se marca aquí para que la fila no ofrezca siquiera el botón a
  /// quien no podría entrar.
  final bool exigeMaestro;
}

/// Ruta de origen de un evento, o `null` cuando el dominio no tiene una
/// pantalla de detalle por id a la que llevar.
///
/// Cubre solo los orígenes con una ruta REAL por id. Un evento sin
/// destino no es un error: simplemente se muestra sin acción de
/// navegación (ej. las eliminaciones físicas, cuyo registro ya no
/// existe — llevar ahí daría 404 sobre una entidad borrada a propósito).
DestinoAuditoria? destinoDeEvento(EventoAuditoria evento) {
  // Una eliminación física NO navega: la entidad ya no existe. Su
  // snapshot completo vive en el detalle del propio evento.
  if (evento.accion.startsWith('eliminacionFisica:')) return null;

  final id = evento.destinoId ?? evento.registroId;
  if (id.trim().isEmpty) return null;

  return switch (evento.modulo) {
    'tiempoExtra' => DestinoAuditoria(ruta: '/personal/tiempos-extra/$id'),
    'inventario' when evento.destinoId != null => DestinoAuditoria(ruta: '/inventario/articulos/$id'),
    // La pestaña forma parte de la ruta desde la Etapa 8C:
    // `/vehiculos/flotilla/:id`, nunca `/vehiculos/:id`.
    'vehiculos' => DestinoAuditoria(ruta: '/vehiculos/flotilla/$id'),
    'personal' => DestinoAuditoria(ruta: '/personal/empleados/$id'),
    // El expediente de una Deuda es pantalla propia desde la Etapa 19.
    'deudas' => DestinoAuditoria(ruta: '/finanzas/deudas-y-credito/$id'),
    // Un movimiento de cuota se registra contra la OBLIGACIÓN: su
    // expediente es el del descuento, que ya muestra el plan de cuotas.
    'descuentos' => DestinoAuditoria(ruta: '/personal/descuentos/$id'),
    'compras' => DestinoAuditoria(ruta: '/compras/$id'),
    // Comercial. El permiso que abre cada ruta lo sigue resolviendo
    // `permisosQueAbrenRuta`: `auditoria.ver` deja ver QUE algo pasó,
    // nunca abre el expediente de otro módulo.
    'clientes' => DestinoAuditoria(ruta: '/comercial/clientes/$id'),
    'servicios' => DestinoAuditoria(ruta: '/comercial/servicios/$id'),
    // La Configuración de cobro no tiene pantalla por id propia: vive
    // dentro del expediente de su Servicio, y ahí se navega — por eso
    // el evento trae `destinoId` con el servicioId real.
    'configuracionCobro' when evento.destinoId != null =>
      DestinoAuditoria(ruta: '/comercial/servicios/$id'),
    // La Bóveda no tiene ruta por credencial: su pantalla es una sola,
    // Maestro-only. Se lleva a la pantalla, nunca a "abrir" la
    // credencial — revelar el secreto sigue siendo su propia acción,
    // con su propio candado.
    'boveda' => const DestinoAuditoria(ruta: '/configuracion/boveda', exigeMaestro: true),
    _ => null,
  };
}

/// Códigos de módulo que aparecen en Auditoría pero **no** son módulos
/// del catálogo de permisos.
///
/// `tiempoExtra` tiene sus facultades dentro de `personal`
/// (`tiempoExtra.crear/corregir/cancelar` son acciones especiales de
/// ese módulo, decisión de la Etapa 1) y `boveda` no tiene código de
/// permiso alguno: es Maestro-only por diseño (Etapa 14D).
///
/// Existen aquí, y no en `modulosPermiso`, precisamente para NO
/// inventar permisos nuevos (`tiempoExtra.ver`, `boveda.ver`) solo para
/// poder filtrar. El filtro de la pantalla ofrece la unión de ambas
/// listas.
const modulosSoloAuditoria = <String>['tiempoExtra', 'boveda'];
