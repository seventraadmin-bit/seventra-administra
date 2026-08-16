import 'package:drift/drift.dart';

import 'configuracion_cobro_vigencia_table.dart';

/// Las etapas con significado funcional propio para otras partes del
/// sistema (Etapa 15, ampliación "flujo posterior a la emisión") — el
/// resto del flujo de un cliente (Validación, Carga a portal,
/// Autorización interna, Revisión, Recepción de documentos, Liberación
/// de pago, o cualquier otra que un cliente real necesite) se captura
/// como etapa **personalizada** (`tipoSistema == null`), nunca amplía
/// este enum: agregar un cliente con un proceso distinto nunca vuelve
/// a exigir una migración de esquema. `procesamiento` se conserva
/// exclusivamente por compatibilidad histórica con vigencias
/// capturadas antes de esta ampliación — la UI de captura nueva nunca
/// vuelve a ofrecerlo como opción.
enum TipoEventoCobro { emision, procesamiento, pagoEsperado, complementoPago }

/// Las 5 formas de calcular la fecha de una etapa — las 4 originales
/// (Etapa 4H.2, confirmadas contra 6 casos reales) más
/// `diasCalendarioDespuesDe` (Etapa 15): a diferencia de
/// `diasHabilesDespuesDe`, cuenta días de calendario, no solo hábiles
/// — con `offsetDias == 0` expresa literalmente "mismo día de la etapa
/// anterior" (Sportium: "Envío a validación: mismo día de Emisión").
enum TipoReglaEvento {
  /// Día fijo del mes (Sportium emisión día 21; Toluca 32/Tikal pago
  /// día 10/20).
  diaFijoDelMes,

  /// N días hábiles después de otro evento de la misma vigencia
  /// (Sportium: pago = 10 días hábiles después de emisión).
  diasHabilesDespuesDe,

  /// N días de calendario después de otra etapa (o de Cierre de
  /// periodo) — `offsetDias == 0` es "mismo día". Sportium: "Carga a
  /// portal: 4 días después de Validación"; "Pago esperado: 7 días
  /// después de Carga a portal".
  diasCalendarioDespuesDe,

  /// El N-ésimo día de la semana de un mes (Miluyole: procesamiento =
  /// primer miércoles; Morgan: pago = segundo viernes del mes
  /// siguiente).
  nEsimoDiaSemanaDelMes,

  /// La siguiente ocurrencia (estrictamente posterior, nunca el mismo
  /// día) de un día de la semana, contada desde otro evento de la
  /// misma vigencia (Miluyole: pago = miércoles siguiente al
  /// procesamiento).
  mismoDiaSemanaSiguienteA,
}

/// A qué mes se refiere una etapa de tipo `diaFijoDelMes`/
/// `nEsimoDiaSemanaDelMes`, relativo al mes en que inicia el período
/// (Resolución B de la Etapa 4H.2) — nunca implícito.
enum MesRelativoCobro { actual, siguiente }

enum OrdinalSemanaCobro { primero, segundo, tercero, cuarto, ultimo }

enum DiaSemanaCobro { lunes, martes, miercoles, jueves, viernes, sabado, domingo }

/// Una etapa del flujo de cobro de una vigencia de Configuración de
/// cobro (Etapa 15, reemplaza `ConfiguracionCobroReglaEvento` de la
/// Etapa 4H.2) — colección dinámica en vez de un catálogo fijo de
/// eventos: Sportium puede tener Cierre→Emisión→Validación→Portal→Pago
/// mientras otro cliente tiene solo Cierre→Emisión→Pago, sin que
/// ninguno de los dos exija cambiar código. Tabla hija sin lifecycle
/// propio, mismo criterio que su predecesora: se borra y reinserta
/// completa junto con su vigencia (cualquier cambio a una etapa exige
/// una nueva vigencia o, si la vigencia todavía es corregible, se
/// reemplaza dentro del mismo "Corregir" — nunca se edita una fila
/// suelta fuera de ese ciclo).
///
/// `id` se genera en el cliente (no autoincrement): las referencias
/// entre etapas del mismo lote (`etapaReferenciaId`) necesitan poder
/// apuntar a una etapa hermana antes de que exista ninguna fila en la
/// base de datos.
///
/// `tipoSistema` no nulo identifica una etapa de sistema (ver
/// [TipoEventoCobro]) — su nombre visible se deriva de `tipoSistema`
/// vía l10n, nunca de la columna `nombre` (que por eso se exige NULL
/// para estas filas): así ninguna otra parte del sistema que siga
/// leyendo `tipoSistema` puede quedar confundida por un renombre. Una
/// etapa personalizada (`tipoSistema IS NULL`) exige `nombre` — texto
/// libre elegido por quien la captura.
///
/// Una fila presente siempre significa "etapa activa", incluso si
/// `tipoRegla` todavía es NULL ("activada pero su regla temporal
/// todavía no se captura", Etapa 15 — antes la Etapa 4H.2 fusionaba
/// ambos conceptos en uno solo: la ausencia de fila). Esquema explícito
/// por columnas, nunca JSON (misma decisión, reafirmada) — cada
/// `tipoRegla` usa solo el subconjunto de columnas que le corresponde.
///
/// `etapaReferenciaId`/`referenciaCierrePeriodo` son mutuamente
/// excluyentes (nunca ambos a la vez) — de qué depende la etapa para
/// las reglas relativas (`diasHabilesDespuesDe`/
/// `diasCalendarioDespuesDe`/`mismoDiaSemanaSiguienteA`): otra etapa de
/// la misma vigencia, o el origen virtual "Cierre de periodo" (nunca
/// una fila real, siempre disponible). `diaFijoDelMes`/
/// `nEsimoDiaSemanaDelMes` no dependen de nada — ambas columnas quedan
/// NULL/`false`. Las combinaciones válidas de referencia y la ausencia
/// de ciclos se validan en el dominio (`ConfiguracionCobroEtapaValidator`),
/// no aquí.
class ConfiguracionCobroEtapa extends Table {
  TextColumn get id => text()();

  TextColumn get configuracionCobroVigenciaId =>
      text().references(ConfiguracionCobroVigencia, #id, onDelete: KeyAction.cascade)();

  TextColumn get tipoSistema => text().nullable()();

  TextColumn get nombre => text().nullable()();

  IntColumn get orden => integer()();

  TextColumn get tipoRegla => text().nullable()();

  /// Solo aplica a `diaFijoDelMes`/`nEsimoDiaSemanaDelMes`.
  TextColumn get mesRelativo => text().nullable()();

  /// Solo aplica a `diaFijoDelMes`.
  IntColumn get diaDelMes => integer().nullable()();

  /// Solo aplica a `nEsimoDiaSemanaDelMes`.
  TextColumn get ordinalSemana => text().nullable()();

  /// Aplica a `nEsimoDiaSemanaDelMes` y `mismoDiaSemanaSiguienteA`.
  TextColumn get diaSemana => text().nullable()();

  /// Aplica a `diasHabilesDespuesDe`/`diasCalendarioDespuesDe` — el
  /// mismo valor 0 en la variante de calendario expresa "mismo día".
  IntColumn get offsetDias => integer().nullable()();

  TextColumn get etapaReferenciaId =>
      text().nullable().references(ConfiguracionCobroEtapa, #id, onDelete: KeyAction.restrict)();

  BoolColumn get referenciaCierrePeriodo => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'UNIQUE (configuracion_cobro_vigencia_id, tipo_sistema)',
        'CHECK (dia_del_mes IS NULL OR dia_del_mes BETWEEN 1 AND 31)',
        'CHECK (tipo_sistema IS NOT NULL OR nombre IS NOT NULL)',
        'CHECK (tipo_sistema IS NULL OR nombre IS NULL)',
        'CHECK (NOT (etapa_referencia_id IS NOT NULL AND referencia_cierre_periodo = 1))',
      ];
}
