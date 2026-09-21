import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/features/personal/data/tables/vacante_operativa_table.dart';

/// Una `VacanteOperativa` con el contexto legible que necesita el
/// Tiempo Extra: qué puesto y qué turno pedía la plaza, desde cuándo
/// está abierta y en qué estado se encuentra hoy.
///
/// La `VacanteOperativa` en sí NO guarda puesto ni turno — guarda
/// `lineaComercialId`, y son las condiciones de esa línea las que dicen
/// qué se requería. Por eso esto se resuelve, nunca se duplica en una
/// columna nueva.
class VacanteCobertura {
  const VacanteCobertura({
    required this.id,
    required this.servicioId,
    required this.lineaComercialId,
    required this.fechaApertura,
    required this.estatus,
    this.puestoNombre,
    this.modalidadTurnoId,
    this.modalidadTurnoNombre,
  });

  final String id;
  final String servicioId;
  final String lineaComercialId;
  final DateTime fechaApertura;

  /// `abierta` | `cubierta` — los dos únicos estados que existen en
  /// `EstatusVacanteOperativa`.
  final String estatus;

  /// `null` sólo si la línea comercial perdió sus condiciones (no
  /// debería ocurrir: es `restrict`). Nunca se inventa un nombre.
  final String? puestoNombre;

  /// Turno que pedía la plaza — sirve de valor por defecto para el
  /// turno del Tiempo Extra, nunca como su verdad: el TEX guarda su
  /// propio `turnoId` porque quien cubre puede hacerlo en otro turno.
  final String? modalidadTurnoId;
  final String? modalidadTurnoNombre;

  bool get estaAbierta => estatus == EstatusVacanteOperativa.abierta.name;

  /// "Guardia — Nocturno", o sólo el puesto si la línea no tiene turno
  /// resoluble. Nunca un id.
  String get etiqueta {
    final puesto = puestoNombre;
    final turno = modalidadTurnoNombre;
    if (puesto == null) return '—';
    if (turno == null || turno.isEmpty) return puesto;
    return '$puesto — $turno';
  }
}

/// Resuelve el contexto legible de las vacantes SIN tocar el módulo
/// Comercial: lee las tablas directamente y siempre en lote (nunca una
/// consulta por vacante), igual que `_etiquetasPorId` en Auditoría.
///
/// Distingue deliberadamente dos catálogos (§24 del pedido):
///
/// - [elegiblesPorServicio] — qué puede ELEGIRSE al registrar un TEX
///   nuevo: sólo vacantes `abierta` de ese Servicio.
/// - [porId] / [porIds] — cómo se RESUELVE un histórico: cualquier
///   vacante, incluidas las que ya se cubrieron después. Un Tiempo
///   Extra registrado en marzo debe seguir diciendo qué plaza cubrió
///   aunque esa plaza se haya llenado en abril.
class VacanteCoberturaReader {
  VacanteCoberturaReader(this._db);

  final AppDatabase _db;

  Future<List<VacanteCobertura>> elegiblesPorServicio(String servicioId) async {
    final filas = await (_db.select(_db.vacanteOperativa)
          ..where((t) => t.servicioId.equals(servicioId) & t.estatus.equals(EstatusVacanteOperativa.abierta.name))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaApertura)]))
        .get();
    final contexto = await _contextoDeLineas(filas.map((v) => v.lineaComercialId));
    return [for (final v in filas) _componer(v, contexto[v.lineaComercialId])];
  }

  Future<VacanteCobertura?> porId(String id) async {
    final resueltas = await porIds([id]);
    return resueltas[id];
  }

  Future<Map<String, VacanteCobertura>> porIds(Iterable<String> ids) async {
    final unicos = ids.toSet().toList();
    if (unicos.isEmpty) return const {};
    final filas = await (_db.select(_db.vacanteOperativa)..where((t) => t.id.isIn(unicos))).get();
    final contexto = await _contextoDeLineas(filas.map((v) => v.lineaComercialId));
    return {for (final v in filas) v.id: _componer(v, contexto[v.lineaComercialId])};
  }

  VacanteCobertura _componer(VacanteOperativaData v, _ContextoLinea? contexto) {
    return VacanteCobertura(
      id: v.id,
      servicioId: v.servicioId,
      lineaComercialId: v.lineaComercialId,
      fechaApertura: v.fechaApertura,
      estatus: v.estatus,
      puestoNombre: contexto?.puestoNombre,
      modalidadTurnoId: contexto?.modalidadTurnoId,
      modalidadTurnoNombre: contexto?.modalidadTurnoNombre,
    );
  }

  /// Puesto y turno de cada línea comercial, en 3 consultas totales sin
  /// importar cuántas vacantes se pidan. Se usa la vigencia activa más
  /// reciente de cada línea: las plazas de una línea son anónimas, así
  /// que lo que describe la vacante son las condiciones vigentes de su
  /// línea, no una vigencia histórica concreta.
  Future<Map<String, _ContextoLinea>> _contextoDeLineas(Iterable<String> lineaIds) async {
    final unicos = lineaIds.toSet().toList();
    if (unicos.isEmpty) return const {};

    final vigencias = await (_db.select(_db.servicioLineaComercialVigencia)
          ..where((t) =>
              t.lineaComercialId.isIn(unicos) & t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaInicioVigencia)]))
        .get();

    // La última de cada línea gana: el `orderBy` ascendente hace que la
    // más reciente sobrescriba a las anteriores.
    final vigentePorLinea = <String, ServicioLineaComercialVigenciaData>{};
    for (final v in vigencias) {
      vigentePorLinea[v.lineaComercialId] = v;
    }
    if (vigentePorLinea.isEmpty) return const {};

    final puestos = await (_db.select(_db.puesto)
          ..where((t) => t.id.isIn(vigentePorLinea.values.map((v) => v.puestoId).toSet().toList())))
        .get();
    final nombrePuesto = {for (final p in puestos) p.id: p.nombre};

    final modalidades = await (_db.select(_db.tipoModalidadTurno)
          ..where((t) => t.id.isIn(vigentePorLinea.values.map((v) => v.modalidadTurnoId).toSet().toList())))
        .get();
    final nombreModalidad = {for (final m in modalidades) m.id: m.nombre};

    return {
      for (final entrada in vigentePorLinea.entries)
        entrada.key: _ContextoLinea(
          puestoNombre: nombrePuesto[entrada.value.puestoId],
          modalidadTurnoId: entrada.value.modalidadTurnoId,
          modalidadTurnoNombre: nombreModalidad[entrada.value.modalidadTurnoId],
        ),
    };
  }
}

class _ContextoLinea {
  const _ContextoLinea({this.puestoNombre, this.modalidadTurnoId, this.modalidadTurnoNombre});
  final String? puestoNombre;
  final String? modalidadTurnoId;
  final String? modalidadTurnoNombre;
}
