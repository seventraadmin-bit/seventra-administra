import '../repositories/auditoria_repository.dart';

/// Una fila unificada de la pantalla de Auditoría central (Etapa 11D)
/// — agrega los ~17 orígenes reales de eventos del proyecto (las
/// tablas `XxxEvento` de cada dominio + los ledgers append-only que ya
/// eran su propio evento, ej. `MovimientoInventario`/
/// `VehiculoKilometraje`, + `UsuarioEvento` + `EliminacionFisicaEvento`)
/// en una sola forma legible: Fecha/hora | Usuario | Módulo | Acción |
/// Registro | Motivo, tal como pidió Marlon. `detalleJson` solo se usa
/// para el panel de detalle bajo demanda — nunca se muestra crudo en
/// la tabla principal.
/// Un cambio concreto dentro de un evento: `campo: antes → después`.
///
/// Existe para que la Auditoría central presente los cambios con UN
/// solo estándar sin aplanar las diferencias reales del origen. Las
/// tablas del proyecto guardan sus cambios de tres formas distintas, y
/// las tres se proyectan aquí sin reescribir ninguna:
///
///  - `estadoAnterior`/`estadoNuevo` como JSON de objeto
///    (`TiempoExtraEvento`, `VehiculoEvento`) → una entrada por clave;
///  - columnas dedicadas `campo`/`valorAnterior`/`valorNuevo`
///    (`ArticuloUnidadEvento`) → una entrada, tal cual, **sin** pasar
///    por JSON (no hace falta y perdería tipado);
///  - sin cambios estructurados (`BovedaCredencialEvento`,
///    `CompraEvento`…) → lista vacía, y la UI simplemente no dibuja el
///    bloque.
class CambioAuditoria {
  const CambioAuditoria({required this.campo, this.antes, this.despues, this.esImporte = false});

  final String campo;
  final String? antes;
  final String? despues;

  /// `true` cuando [antes]/[despues] son centavos enteros y la UI debe
  /// formatearlos como moneda (`3326608` → `\$33,266.08`).
  ///
  /// La proyección sabe qué columna es dinero; formatear moneda es de la
  /// UI. Este flag comunica lo primero sin que la capa de datos tenga
  /// que hacer lo segundo — y sin que la UI tenga que adivinar por el
  /// nombre del campo.
  final bool esImporte;
}

class EventoAuditoria {
  const EventoAuditoria({
    required this.fechaHora,
    required this.actorUsuarioId,
    required this.modulo,
    required this.accion,
    required this.registroId,
    this.motivo,
    this.detalleJson,
    this.cambios = const [],
    this.entidadEtiqueta,
    this.destinoId,
    this.importe,
  });

  final DateTime fechaHora;
  final String? actorUsuarioId;

  /// Código de módulo (ej. `'compras'`, `'inventario'`) — mismo
  /// vocabulario que `modulos_permiso.dart`, para que el filtro de la
  /// pantalla pueda reutilizar las mismas etiquetas ya traducidas.
  final String modulo;

  /// Tipo de evento/movimiento crudo (ej. `'registrada'`, `'ajuste'`) —
  /// la UI lo traduce a una etiqueta legible por módulo, igual que ya
  /// hace cada diálogo de historial individual.
  final String accion;

  final String registroId;

  /// Motivo REAL del evento — `null` cuando el dominio no exige uno
  /// (una creación o una revelación de credencial no tienen "motivo").
  /// Nunca se rellena con un "Sin motivo" inventado: la UI omite el
  /// bloque, que es distinto de afirmar que el usuario no dio ninguno.
  final String? motivo;

  final String? detalleJson;

  /// Cambios concretos del evento, ya normalizados (ver
  /// [CambioAuditoria]). Vacío es un estado legítimo y frecuente.
  final List<CambioAuditoria> cambios;

  /// Nombre legible de la entidad afectada — folio, código o nombre
  /// (ej. `'TEX-000012'`, `'Portal SAT'`). Se resuelve con lookups
  /// EN LOTE (una consulta por tipo de entidad, nunca una por fila) y
  /// es `null` cuando el origen no tiene una etiqueta natural.
  final String? entidadEtiqueta;

  /// Monto del movimiento en centavos, cuando el origen es un ledger
  /// que mueve dinero (`MovimientoDeuda`, `DescuentoProgramadoMovimiento`).
  /// `null` en los eventos que no mueven un importe — no es lo mismo
  /// que cero.
  final int? importe;

  /// Id con el que se navega al origen, cuando difiere de
  /// [registroId]. Caso real: `ArticuloUnidadEvento` guarda el id de la
  /// **unidad**, pero la ruta del expediente es por **artículo**.
  /// `null` significa "usa `registroId`".
  final String? destinoId;
}

class FiltroAuditoria {
  const FiltroAuditoria({this.actorUsuarioId, this.modulo, this.accion, this.desde, this.hasta});

  final String? actorUsuarioId;
  final String? modulo;
  final String? accion;
  final DateTime? desde;
  final DateTime? hasta;
}

/// Fachada de solo lectura de la Auditoría central (Etapa 11D) — mismo
/// criterio cross-domain que `BuscarInventarioUseCase` (7D): agrega
/// datos de varios dominios sin que ningún dominio dependa de otro.
class BuscarAuditoriaUseCase {
  BuscarAuditoriaUseCase(this._repository);

  final AuditoriaRepository _repository;

  Future<List<EventoAuditoria>> ejecutar(FiltroAuditoria filtro) => _repository.buscar(filtro);
}
