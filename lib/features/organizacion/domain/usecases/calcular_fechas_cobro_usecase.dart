import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_etapa_table.dart';

/// La fecha calculada de una etapa — `fecha` es `null` para cualquier
/// etapa cuya regla todavía no se captura, o cuya cadena de referencia
/// tampoco es calculable (Etapa 4H.2, reafirmado en la Etapa 15: "no
/// inventa fechas"). `tipoSistema`/`nombre` viajan aquí (en vez de
/// forzar a quien llama a volver a resolverlos contra la etapa
/// original) porque `EnsamblarDocumentoPorEmitirUseCase` los necesita
/// tal cual para el snapshot de `DocumentoPorEmitirHito`.
class FechaEtapaCalculada {
  const FechaEtapaCalculada({
    required this.etapaId,
    required this.orden,
    this.tipoSistema,
    this.nombre,
    this.fecha,
  });

  final String etapaId;
  final int orden;
  final String? tipoSistema;
  final String? nombre;
  final DateTime? fecha;
}

/// Resuelve la fecha de la etapa de sistema [tipoSistema] dentro de una
/// lista ya calculada — `null` si esa etapa no está activa en esta
/// vigencia o su fecha no es calculable. Usado por los adaptadores que
/// todavía necesitan las 3 columnas legacy (`DocumentoPorEmitir`/
/// `DocumentoPorEmitirConfiguracion`) mientras sigan existiendo.
DateTime? fechaDeEtapaSistema(List<FechaEtapaCalculada> fechas, TipoEventoCobro tipoSistema) {
  for (final f in fechas) {
    if (f.tipoSistema == tipoSistema.name) return f.fecha;
  }
  return null;
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

/// Etapa 15: días de calendario (no solo hábiles) después de otra
/// etapa (o del origen virtual Cierre de periodo) — `cantidad == 0` da
/// literalmente la misma fecha de origen ("mismo día de la etapa
/// anterior").
DateTime diasCalendarioDespues(DateTime fecha, int cantidad) => _soloFecha(fecha).add(Duration(days: cantidad));

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

/// Calcula la fecha de cada etapa activa de una vigencia (Etapa 15,
/// reemplaza el trío fijo Emisión/Procesamiento/Pago esperado de la
/// Etapa 4H.2) — función pura: sin `Clock`, sin persistencia, sin
/// generar ningún documento. Una etapa sin regla capturada, o cuya
/// cadena de referencia (a otra etapa, o al origen virtual Cierre de
/// periodo) tampoco es calculable, resulta en `fecha == null` — nunca
/// se inventa una fecha. [periodoFin] es el origen que usa
/// `referenciaCierrePeriodo`.
class CalcularFechasCobroUseCase {
  const CalcularFechasCobroUseCase();

  List<FechaEtapaCalculada> ejecutar({
    required List<ConfiguracionCobroEtapaData> etapas,
    required DateTime mesInicioPeriodo,
    required DateTime periodoFin,
  }) {
    final porId = {for (final e in etapas) e.id: e};
    final resueltos = <String, DateTime?>{};

    DateTime? calcular(String etapaId, Set<String> enProgreso) {
      if (resueltos.containsKey(etapaId)) return resueltos[etapaId];
      // Ciclo — no debería ocurrir nunca sobre etapas ya validadas, pero
      // una función pura no debe entrar en recursión infinita si se le
      // pasan etapas malformadas directamente (ej. en una prueba).
      if (enProgreso.contains(etapaId)) {
        resueltos[etapaId] = null;
        return null;
      }

      final etapa = porId[etapaId];
      if (etapa == null || etapa.tipoRegla == null) {
        resueltos[etapaId] = null;
        return null;
      }

      final siguienteEnProgreso = {...enProgreso, etapaId};
      final tipoRegla = TipoReglaEvento.values.byName(etapa.tipoRegla!);
      final mesRelativo = etapa.mesRelativo == null ? null : MesRelativoCobro.values.byName(etapa.mesRelativo!);
      final mesObjetivo = mesRelativo == null
          ? null
          : (mesRelativo == MesRelativoCobro.actual
              ? mesInicioPeriodo
              : DateTime(mesInicioPeriodo.year, mesInicioPeriodo.month + 1, 1));

      DateTime? origen() {
        if (etapa.referenciaCierrePeriodo) return periodoFin;
        if (etapa.etapaReferenciaId == null) return null;
        return calcular(etapa.etapaReferenciaId!, siguienteEnProgreso);
      }

      DateTime? resultado;
      switch (tipoRegla) {
        case TipoReglaEvento.diaFijoDelMes:
          resultado = mesObjetivo == null || etapa.diaDelMes == null
              ? null
              : diaFijoDelMes(mesObjetivo.year, mesObjetivo.month, etapa.diaDelMes!);
        case TipoReglaEvento.nEsimoDiaSemanaDelMes:
          resultado = mesObjetivo == null || etapa.diaSemana == null || etapa.ordinalSemana == null
              ? null
              : nEsimoDiaSemanaDelMes(
                  mesObjetivo.year,
                  mesObjetivo.month,
                  DiaSemanaCobro.values.byName(etapa.diaSemana!),
                  OrdinalSemanaCobro.values.byName(etapa.ordinalSemana!),
                );
        case TipoReglaEvento.diasHabilesDespuesDe:
          if (etapa.offsetDias == null) {
            resultado = null;
          } else {
            final refFecha = origen();
            resultado = refFecha == null ? null : diasHabilesDespues(refFecha, etapa.offsetDias!);
          }
        case TipoReglaEvento.diasCalendarioDespuesDe:
          if (etapa.offsetDias == null) {
            resultado = null;
          } else {
            final refFecha = origen();
            resultado = refFecha == null ? null : diasCalendarioDespues(refFecha, etapa.offsetDias!);
          }
        case TipoReglaEvento.mismoDiaSemanaSiguienteA:
          if (etapa.diaSemana == null) {
            resultado = null;
          } else {
            final refFecha = origen();
            resultado =
                refFecha == null ? null : mismoDiaSemanaSiguienteA(refFecha, DiaSemanaCobro.values.byName(etapa.diaSemana!));
          }
      }

      resueltos[etapaId] = resultado;
      return resultado;
    }

    final ordenadas = [...etapas]..sort((a, b) => a.orden.compareTo(b.orden));
    return [
      for (final e in ordenadas)
        FechaEtapaCalculada(
          etapaId: e.id,
          orden: e.orden,
          tipoSistema: e.tipoSistema,
          nombre: e.nombre,
          fecha: calcular(e.id, const {}),
        ),
    ];
  }
}
