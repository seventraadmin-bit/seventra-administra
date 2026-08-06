import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_regla_evento_table.dart';

/// Las 3 fechas calculables de un período de una Configuración de
/// cobro — `null` para cualquier evento que todavía no tenga una regla
/// capturada (Etapa 4H.2: "no inventa fechas").
class FechasCobroCalculadas {
  const FechasCobroCalculadas({this.fechaEmision, this.fechaProcesamiento, this.fechaPagoEsperado});

  final DateTime? fechaEmision;
  final DateTime? fechaProcesamiento;
  final DateTime? fechaPagoEsperado;
}

DateTime _soloFecha(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

bool _esDiaHabil(DateTime fecha) => fecha.weekday != DateTime.saturday && fecha.weekday != DateTime.sunday;

/// Resolución C (Etapa 4H.2): el día de origen nunca cuenta, el conteo
/// empieza al día siguiente, solo lunes a viernes, sin calendario de
/// festivos oficiales todavía.
DateTime diasHabilesDespues(DateTime fecha, int cantidad) {
  var resultado = _soloFecha(fecha);
  var restantes = cantidad;
  while (restantes > 0) {
    resultado = resultado.add(const Duration(days: 1));
    if (_esDiaHabil(resultado)) restantes--;
  }
  return resultado;
}

int _ultimoDiaDelMes(int anio, int mes) => DateTime(anio, mes + 1, 0).day;

/// Público (Etapa 4I.1) — además de usarse aquí para `diaFijoDelMes`/
/// `nEsimoDiaSemanaDelMes`, la Agenda de documentos por emitir lo
/// reutiliza directamente para calcular los límites de un periodo de
/// servicio a partir de `diaInicioPeriodo`, sin duplicar el mismo
/// recorte de fin de mes.
DateTime diaFijoDelMes(int anio, int mes, int dia) {
  final ultimoDia = _ultimoDiaDelMes(anio, mes);
  return DateTime(anio, mes, dia > ultimoDia ? ultimoDia : dia);
}

/// Los límites `[periodoInicio, periodoFin]` de un periodo de servicio
/// que arranca en `mesInicioPeriodo` con el día `diaInicioPeriodo` de
/// `ConfiguracionCobroVigencia` (Etapa 4I.1) — `periodoFin` es el día
/// anterior a que inicie el periodo siguiente, mismo criterio inclusivo
/// que el resto del proyecto usa para `fechaFinVigencia`.
({DateTime periodoInicio, DateTime periodoFin}) calcularLimitesPeriodo({
  required int diaInicioPeriodo,
  required DateTime mesInicioPeriodo,
}) {
  final inicio = diaFijoDelMes(mesInicioPeriodo.year, mesInicioPeriodo.month, diaInicioPeriodo);
  final mesSiguiente = DateTime(mesInicioPeriodo.year, mesInicioPeriodo.month + 1, 1);
  final inicioSiguiente = diaFijoDelMes(mesSiguiente.year, mesSiguiente.month, diaInicioPeriodo);
  final fin = inicioSiguiente.subtract(const Duration(days: 1));
  return (periodoInicio: inicio, periodoFin: fin);
}

int _weekdayDe(DiaSemanaCobro dia) {
  return switch (dia) {
    DiaSemanaCobro.lunes => DateTime.monday,
    DiaSemanaCobro.martes => DateTime.tuesday,
    DiaSemanaCobro.miercoles => DateTime.wednesday,
    DiaSemanaCobro.jueves => DateTime.thursday,
    DiaSemanaCobro.viernes => DateTime.friday,
    DiaSemanaCobro.sabado => DateTime.saturday,
    DiaSemanaCobro.domingo => DateTime.sunday,
  };
}

/// El N-ésimo día de la semana indicada dentro de un mes — `ultimo` es
/// la última ocurrencia, no necesariamente la cuarta (meses con 5
/// ocurrencias de un día existen).
DateTime nEsimoDiaSemanaDelMes(int anio, int mes, DiaSemanaCobro diaSemana, OrdinalSemanaCobro ordinal) {
  final weekdayObjetivo = _weekdayDe(diaSemana);

  if (ordinal == OrdinalSemanaCobro.ultimo) {
    var fecha = DateTime(anio, mes + 1, 0);
    while (fecha.weekday != weekdayObjetivo) {
      fecha = fecha.subtract(const Duration(days: 1));
    }
    return fecha;
  }

  final ordinalIndice = switch (ordinal) {
    OrdinalSemanaCobro.primero => 1,
    OrdinalSemanaCobro.segundo => 2,
    OrdinalSemanaCobro.tercero => 3,
    OrdinalSemanaCobro.cuarto => 4,
    OrdinalSemanaCobro.ultimo => throw StateError('caso ya manejado arriba'),
  };

  var fecha = DateTime(anio, mes, 1);
  var contador = 0;
  while (true) {
    if (fecha.weekday == weekdayObjetivo) {
      contador++;
      if (contador == ordinalIndice) return fecha;
    }
    fecha = fecha.add(const Duration(days: 1));
  }
}

/// La siguiente ocurrencia del día de la semana indicado, estrictamente
/// posterior a `referencia` — nunca el mismo día, aunque `referencia`
/// ya caiga en ese día de la semana (Miluyole: "miércoles siguiente al
/// procesamiento" es una semana después del propio procesamiento, que
/// también es miércoles).
DateTime mismoDiaSemanaSiguienteA(DateTime referencia, DiaSemanaCobro diaSemana) {
  final weekdayObjetivo = _weekdayDe(diaSemana);
  var fecha = _soloFecha(referencia).add(const Duration(days: 1));
  while (fecha.weekday != weekdayObjetivo) {
    fecha = fecha.add(const Duration(days: 1));
  }
  return fecha;
}

/// El mes en que inicia el período que contiene `hoy`, dado el día del
/// mes en que arranca cada período (Resolución B: un período se
/// identifica por su mes de inicio, nunca por el mes en que termina).
DateTime mesInicioDelPeriodoActual({required int diaInicioPeriodo, required DateTime hoy}) {
  final hoySinHora = _soloFecha(hoy);
  final inicioEsteMes = diaFijoDelMes(hoySinHora.year, hoySinHora.month, diaInicioPeriodo);

  if (!hoySinHora.isBefore(inicioEsteMes)) {
    return DateTime(hoySinHora.year, hoySinHora.month, 1);
  }
  return DateTime(hoySinHora.year, hoySinHora.month - 1, 1);
}

/// Calcula Emisión/Procesamiento/Pago esperado para un período dado a
/// partir de las reglas capturadas — función pura (Etapa 4H.2): sin
/// `Clock`, sin persistencia, sin generar ningún documento. Un evento
/// sin regla capturada, o cuyo evento de referencia tampoco es
/// calculable, resulta en `null` — nunca se inventa una fecha.
class CalcularFechasCobroUseCase {
  const CalcularFechasCobroUseCase();

  FechasCobroCalculadas ejecutar({
    required List<ConfiguracionCobroReglaEventoData> reglas,
    required DateTime mesInicioPeriodo,
  }) {
    final porEvento = {for (final r in reglas) TipoEventoCobro.values.byName(r.tipoEvento): r};
    final resueltos = <TipoEventoCobro, DateTime?>{};

    DateTime? calcular(TipoEventoCobro evento, Set<TipoEventoCobro> enProgreso) {
      if (resueltos.containsKey(evento)) return resueltos[evento];
      // Ciclo — no debería ocurrir nunca sobre reglas ya validadas, pero
      // una función pura no debe entrar en recursión infinita si se le
      // pasan reglas malformadas directamente (ej. en una prueba).
      if (enProgreso.contains(evento)) {
        resueltos[evento] = null;
        return null;
      }

      final regla = porEvento[evento];
      if (regla == null) {
        resueltos[evento] = null;
        return null;
      }

      final siguienteEnProgreso = {...enProgreso, evento};
      final tipoRegla = TipoReglaEvento.values.byName(regla.tipoRegla);
      final mesRelativo = regla.mesRelativo == null ? null : MesRelativoCobro.values.byName(regla.mesRelativo!);
      final mesObjetivo = mesRelativo == null
          ? null
          : (mesRelativo == MesRelativoCobro.actual
              ? mesInicioPeriodo
              : DateTime(mesInicioPeriodo.year, mesInicioPeriodo.month + 1, 1));

      DateTime? resultado;
      switch (tipoRegla) {
        case TipoReglaEvento.diaFijoDelMes:
          resultado = mesObjetivo == null || regla.diaDelMes == null
              ? null
              : diaFijoDelMes(mesObjetivo.year, mesObjetivo.month, regla.diaDelMes!);
        case TipoReglaEvento.nEsimoDiaSemanaDelMes:
          resultado = mesObjetivo == null || regla.diaSemana == null || regla.ordinalSemana == null
              ? null
              : nEsimoDiaSemanaDelMes(
                  mesObjetivo.year,
                  mesObjetivo.month,
                  DiaSemanaCobro.values.byName(regla.diaSemana!),
                  OrdinalSemanaCobro.values.byName(regla.ordinalSemana!),
                );
        case TipoReglaEvento.diasHabilesDespuesDe:
          if (regla.eventoReferencia == null || regla.offsetDiasHabiles == null) {
            resultado = null;
          } else {
            final refFecha = calcular(TipoEventoCobro.values.byName(regla.eventoReferencia!), siguienteEnProgreso);
            resultado = refFecha == null ? null : diasHabilesDespues(refFecha, regla.offsetDiasHabiles!);
          }
        case TipoReglaEvento.mismoDiaSemanaSiguienteA:
          if (regla.eventoReferencia == null || regla.diaSemana == null) {
            resultado = null;
          } else {
            final refFecha = calcular(TipoEventoCobro.values.byName(regla.eventoReferencia!), siguienteEnProgreso);
            resultado =
                refFecha == null ? null : mismoDiaSemanaSiguienteA(refFecha, DiaSemanaCobro.values.byName(regla.diaSemana!));
          }
      }

      resueltos[evento] = resultado;
      return resultado;
    }

    return FechasCobroCalculadas(
      fechaEmision: calcular(TipoEventoCobro.emision, const {}),
      fechaProcesamiento: calcular(TipoEventoCobro.procesamiento, const {}),
      fechaPagoEsperado: calcular(TipoEventoCobro.pagoEsperado, const {}),
    );
  }
}
