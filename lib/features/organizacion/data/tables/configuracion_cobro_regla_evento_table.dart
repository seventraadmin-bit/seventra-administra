import 'package:drift/drift.dart';

import 'configuracion_cobro_vigencia_table.dart';

/// Los 3 eventos que una vigencia de Configuración de cobro puede
/// calcular (Etapa 4H.2) — Emisión y Pago esperado son los únicos que
/// la migración exige tener alguno para considerarse capturados;
/// Procesamiento es siempre opcional (Resolución A de la Etapa 4H.1,
/// reafirmada aquí).
enum TipoEventoCobro { emision, procesamiento, pagoEsperado }

/// Las 4 formas de calcular la fecha de un evento, confirmadas contra
/// los 6 casos reales — ninguna es reducible a las otras.
enum TipoReglaEvento {
  /// Día fijo del mes (Sportium emisión día 21; Toluca 32/Tikal pago
  /// día 10/20).
  diaFijoDelMes,

  /// N días hábiles después de otro evento de la misma vigencia
  /// (Sportium: pago = 10 días hábiles después de emisión).
  diasHabilesDespuesDe,

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

/// A qué mes se refiere un evento de tipo `diaFijoDelMes`/
/// `nEsimoDiaSemanaDelMes`, relativo al mes en que inicia el período
/// (Resolución B de la Etapa 4H.2) — nunca implícito.
enum MesRelativoCobro { actual, siguiente }

enum OrdinalSemanaCobro { primero, segundo, tercero, cuarto, ultimo }

enum DiaSemanaCobro { lunes, martes, miercoles, jueves, viernes, sabado, domingo }

/// Una regla de cálculo de fecha para un evento de una vigencia de
/// Configuración de cobro (Etapa 4H.2) — tabla hija, mismo criterio que
/// `ConfiguracionCobroCorreo`: sin lifecycle propio, se borra y
/// reinserta completa junto con su vigencia (cualquier cambio a una
/// regla temporal exige una nueva vigencia, nunca se edita in place).
///
/// Esquema explícito por columnas, nunca JSON (Resolución B de la Etapa
/// 4H.1, reafirmada aquí) — cada `tipoRegla` usa solo el subconjunto de
/// columnas que le corresponde; el resto queda `NULL`. La coherencia
/// entre `tipoRegla` y qué columnas están pobladas se valida en
/// `ConfiguracionCobroReglaEventoValidator`, no aquí (requeriría un
/// `CHECK` condicional que SQLite no expresa con claridad).
///
/// Emisión y Pago esperado son opcionales a nivel de fila igual que
/// Procesamiento — una Configuración de cobro puede guardarse sin
/// ninguna regla, o con reglas parciales (Corrección obligatoria de la
/// Etapa 4H.2): la ausencia de una fila para un evento simplemente
/// significa "todavía no capturado", nunca un error.
class ConfiguracionCobroReglaEvento extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get configuracionCobroVigenciaId =>
      text().references(ConfiguracionCobroVigencia, #id, onDelete: KeyAction.cascade)();

  TextColumn get tipoEvento => text()();

  TextColumn get tipoRegla => text()();

  /// Solo aplica a `diaFijoDelMes`/`nEsimoDiaSemanaDelMes`.
  TextColumn get mesRelativo => text().nullable()();

  /// Solo aplica a `diaFijoDelMes`.
  IntColumn get diaDelMes => integer().nullable()();

  /// Solo aplica a `nEsimoDiaSemanaDelMes`.
  TextColumn get ordinalSemana => text().nullable()();

  /// Aplica a `nEsimoDiaSemanaDelMes` y `mismoDiaSemanaSiguienteA`.
  TextColumn get diaSemana => text().nullable()();

  /// Solo aplica a `diasHabilesDespuesDe`.
  IntColumn get offsetDiasHabiles => integer().nullable()();

  /// De qué evento de la misma vigencia depende — solo aplica a
  /// `diasHabilesDespuesDe`/`mismoDiaSemanaSiguienteA`. Emisión nunca
  /// tiene un valor aquí (no puede depender de otro evento); las
  /// combinaciones válidas (Procesamiento→Emisión;
  /// Pago esperado→Emisión o →Procesamiento; nunca auto-referencia ni
  /// ciclos) se validan en el dominio, no aquí.
  TextColumn get eventoReferencia => text().nullable()();

  @override
  List<String> get customConstraints => [
        'UNIQUE (configuracion_cobro_vigencia_id, tipo_evento)',
        'CHECK (dia_del_mes IS NULL OR dia_del_mes BETWEEN 1 AND 31)',
      ];
}
