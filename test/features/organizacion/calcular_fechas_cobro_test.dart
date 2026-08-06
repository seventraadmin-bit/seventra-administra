import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_regla_evento_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/calcular_fechas_cobro_usecase.dart';

ConfiguracionCobroReglaEventoData _regla({
  required TipoEventoCobro tipoEvento,
  required TipoReglaEvento tipoRegla,
  MesRelativoCobro? mesRelativo,
  int? diaDelMes,
  OrdinalSemanaCobro? ordinalSemana,
  DiaSemanaCobro? diaSemana,
  int? offsetDiasHabiles,
  TipoEventoCobro? eventoReferencia,
}) {
  return ConfiguracionCobroReglaEventoData(
    id: 0,
    configuracionCobroVigenciaId: 'vigencia-prueba',
    tipoEvento: tipoEvento.name,
    tipoRegla: tipoRegla.name,
    mesRelativo: mesRelativo?.name,
    diaDelMes: diaDelMes,
    ordinalSemana: ordinalSemana?.name,
    diaSemana: diaSemana?.name,
    offsetDiasHabiles: offsetDiasHabiles,
    eventoReferencia: eventoReferencia?.name,
  );
}

void main() {
  group('días hábiles (Resolución C)', () {
    test('el día de origen no cuenta, el conteo empieza al día siguiente', () {
      // Martes 2026-01-06 (2026-01-01 es jueves).
      final martes = DateTime(2026, 1, 6);
      // Miércoles siguiente = 1er día hábil.
      expect(diasHabilesDespues(martes, 1), DateTime(2026, 1, 7));
    });

    test('cruce de fin de semana: sábado y domingo no cuentan', () {
      // Viernes 2026-08-21.
      final viernes = DateTime(2026, 8, 21);
      // 1 día hábil después de un viernes es el lunes siguiente (sábado y domingo no cuentan).
      expect(diasHabilesDespues(viernes, 1), DateTime(2026, 8, 24));
    });

    test('cruce de fin de mes: agosto → septiembre', () {
      // Viernes 2026-08-28.
      final origen = DateTime(2026, 8, 28);
      // Sáb29/Dom30 no cuentan; Lun31=1, Mar1(sep)=2.
      expect(diasHabilesDespues(origen, 2), DateTime(2026, 9, 1));
    });

    test('cruce de fin de año: diciembre → enero', () {
      // Miércoles 2026-12-30.
      final origen = DateTime(2026, 12, 30);
      // Jue31=1, Vie1(ene 2027)=2 (Sáb2/Dom3 no cuentan), Lun4=3.
      expect(diasHabilesDespues(origen, 3), DateTime(2027, 1, 4));
    });

    test('Sportium: 10 días hábiles después del viernes 21 de agosto de 2026', () {
      final emision = DateTime(2026, 8, 21);
      expect(diasHabilesDespues(emision, 10), DateTime(2026, 9, 4));
    });
  });

  group('nEsimoDiaSemanaDelMes', () {
    test('primer miércoles de enero de 2026 (2026-01-01 es jueves)', () {
      expect(
        nEsimoDiaSemanaDelMes(2026, 1, DiaSemanaCobro.miercoles, OrdinalSemanaCobro.primero),
        DateTime(2026, 1, 7),
      );
    });

    test('segundo viernes de febrero de 2026', () {
      expect(
        nEsimoDiaSemanaDelMes(2026, 2, DiaSemanaCobro.viernes, OrdinalSemanaCobro.segundo),
        DateTime(2026, 2, 13),
      );
    });

    test('último viernes de febrero de 2026 (mes corto, 28 días)', () {
      expect(
        nEsimoDiaSemanaDelMes(2026, 2, DiaSemanaCobro.viernes, OrdinalSemanaCobro.ultimo),
        DateTime(2026, 2, 27),
      );
    });
  });

  group('mismoDiaSemanaSiguienteA', () {
    test('nunca el mismo día, aunque la referencia ya caiga en ese día de la semana', () {
      final miercoles = DateTime(2026, 1, 7);
      expect(mismoDiaSemanaSiguienteA(miercoles, DiaSemanaCobro.miercoles), DateTime(2026, 1, 14));
    });
  });

  group('mesInicioDelPeriodoActual (Resolución B, Sportium 21-20)', () {
    test('una fecha dentro del período ya iniciado devuelve el mes de inicio', () {
      // Período 21 jul - 20 ago; hoy = 5 de agosto → todavía dentro del período que inició el 21 de julio.
      expect(
        mesInicioDelPeriodoActual(diaInicioPeriodo: 21, hoy: DateTime(2026, 8, 5)),
        DateTime(2026, 7, 1),
      );
    });

    test('una fecha en o después del día de inicio pertenece al período que empieza ese mes', () {
      expect(
        mesInicioDelPeriodoActual(diaInicioPeriodo: 21, hoy: DateTime(2026, 8, 21)),
        DateTime(2026, 8, 1),
      );
    });
  });

  group('CalcularFechasCobroUseCase — casos reales obligatorios', () {
    const calcular = CalcularFechasCobroUseCase();

    test('Sportium: período 21 jul - 20 ago → emisión 21 de agosto, pago 4 de septiembre', () {
      final reglas = [
        _regla(
          tipoEvento: TipoEventoCobro.emision,
          tipoRegla: TipoReglaEvento.diaFijoDelMes,
          mesRelativo: MesRelativoCobro.siguiente,
          diaDelMes: 21,
        ),
        _regla(
          tipoEvento: TipoEventoCobro.pagoEsperado,
          tipoRegla: TipoReglaEvento.diasHabilesDespuesDe,
          offsetDiasHabiles: 10,
          eventoReferencia: TipoEventoCobro.emision,
        ),
      ];

      final resultado = calcular.ejecutar(reglas: reglas, mesInicioPeriodo: DateTime(2026, 7, 1));

      expect(resultado.fechaEmision, DateTime(2026, 8, 21));
      expect(resultado.fechaProcesamiento, isNull);
      expect(resultado.fechaPagoEsperado, DateTime(2026, 9, 4));
    });

    test('Miluyole: emisión día 1, procesamiento primer miércoles del mismo mes, pago miércoles siguiente', () {
      final reglas = [
        _regla(
          tipoEvento: TipoEventoCobro.emision,
          tipoRegla: TipoReglaEvento.diaFijoDelMes,
          mesRelativo: MesRelativoCobro.actual,
          diaDelMes: 1,
        ),
        _regla(
          tipoEvento: TipoEventoCobro.procesamiento,
          tipoRegla: TipoReglaEvento.nEsimoDiaSemanaDelMes,
          mesRelativo: MesRelativoCobro.actual,
          diaSemana: DiaSemanaCobro.miercoles,
          ordinalSemana: OrdinalSemanaCobro.primero,
        ),
        _regla(
          tipoEvento: TipoEventoCobro.pagoEsperado,
          tipoRegla: TipoReglaEvento.mismoDiaSemanaSiguienteA,
          diaSemana: DiaSemanaCobro.miercoles,
          eventoReferencia: TipoEventoCobro.procesamiento,
        ),
      ];

      final resultado = calcular.ejecutar(reglas: reglas, mesInicioPeriodo: DateTime(2026, 1, 1));

      expect(resultado.fechaEmision, DateTime(2026, 1, 1));
      expect(resultado.fechaProcesamiento, DateTime(2026, 1, 7));
      expect(resultado.fechaPagoEsperado, DateTime(2026, 1, 14));
    });

    test('Morgan: emisión inicio de mes, pago segundo viernes del mes siguiente', () {
      final reglas = [
        _regla(
          tipoEvento: TipoEventoCobro.emision,
          tipoRegla: TipoReglaEvento.diaFijoDelMes,
          mesRelativo: MesRelativoCobro.actual,
          diaDelMes: 1,
        ),
        _regla(
          tipoEvento: TipoEventoCobro.pagoEsperado,
          tipoRegla: TipoReglaEvento.nEsimoDiaSemanaDelMes,
          mesRelativo: MesRelativoCobro.siguiente,
          diaSemana: DiaSemanaCobro.viernes,
          ordinalSemana: OrdinalSemanaCobro.segundo,
        ),
      ];

      final resultado = calcular.ejecutar(reglas: reglas, mesInicioPeriodo: DateTime(2026, 1, 1));

      expect(resultado.fechaEmision, DateTime(2026, 1, 1));
      expect(resultado.fechaProcesamiento, isNull);
      expect(resultado.fechaPagoEsperado, DateTime(2026, 2, 13));
    });

    test('Toluca 32: solo pago día 10, sin inventar una regla de emisión', () {
      final reglas = [
        _regla(
          tipoEvento: TipoEventoCobro.pagoEsperado,
          tipoRegla: TipoReglaEvento.diaFijoDelMes,
          mesRelativo: MesRelativoCobro.actual,
          diaDelMes: 10,
        ),
      ];

      final resultado = calcular.ejecutar(reglas: reglas, mesInicioPeriodo: DateTime(2026, 1, 1));

      expect(resultado.fechaEmision, isNull);
      expect(resultado.fechaProcesamiento, isNull);
      expect(resultado.fechaPagoEsperado, DateTime(2026, 1, 10));
    });

    test('Tikal: solo pago día 20, sin inventar una regla de emisión', () {
      final reglas = [
        _regla(
          tipoEvento: TipoEventoCobro.pagoEsperado,
          tipoRegla: TipoReglaEvento.diaFijoDelMes,
          mesRelativo: MesRelativoCobro.actual,
          diaDelMes: 20,
        ),
      ];

      final resultado = calcular.ejecutar(reglas: reglas, mesInicioPeriodo: DateTime(2026, 1, 1));

      expect(resultado.fechaEmision, isNull);
      expect(resultado.fechaPagoEsperado, DateTime(2026, 1, 20));
    });

    test('Mirabilia: sin ninguna regla capturada, no se inventa ninguna fecha', () {
      final resultado = calcular.ejecutar(reglas: const [], mesInicioPeriodo: DateTime(2026, 1, 1));

      expect(resultado.fechaEmision, isNull);
      expect(resultado.fechaProcesamiento, isNull);
      expect(resultado.fechaPagoEsperado, isNull);
    });

    test('un evento cuyo evento de referencia no está configurado no se calcula (no inventa fechas)', () {
      final reglas = [
        _regla(
          tipoEvento: TipoEventoCobro.pagoEsperado,
          tipoRegla: TipoReglaEvento.diasHabilesDespuesDe,
          offsetDiasHabiles: 5,
          eventoReferencia: TipoEventoCobro.emision,
        ),
      ];

      final resultado = calcular.ejecutar(reglas: reglas, mesInicioPeriodo: DateTime(2026, 1, 1));

      expect(resultado.fechaEmision, isNull);
      expect(resultado.fechaPagoEsperado, isNull, reason: 'depende de Emisión, que no está configurada');
    });
  });
}
