import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_etapa_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/calcular_fechas_cobro_usecase.dart';

ConfiguracionCobroEtapaData _etapa({
  required String id,
  TipoEventoCobro? tipoSistema,
  String? nombre,
  int orden = 0,
  required TipoReglaEvento tipoRegla,
  MesRelativoCobro? mesRelativo,
  int? diaDelMes,
  OrdinalSemanaCobro? ordinalSemana,
  DiaSemanaCobro? diaSemana,
  int? offsetDias,
  String? etapaReferenciaId,
  bool referenciaCierrePeriodo = false,
}) {
  return ConfiguracionCobroEtapaData(
    id: id,
    configuracionCobroVigenciaId: 'vigencia-prueba',
    tipoSistema: tipoSistema?.name,
    nombre: nombre,
    orden: orden,
    tipoRegla: tipoRegla.name,
    mesRelativo: mesRelativo?.name,
    diaDelMes: diaDelMes,
    ordinalSemana: ordinalSemana?.name,
    diaSemana: diaSemana?.name,
    offsetDias: offsetDias,
    etapaReferenciaId: etapaReferenciaId,
    referenciaCierrePeriodo: referenciaCierrePeriodo,
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

  group('días de calendario (Etapa 15 — diasCalendarioDespuesDe)', () {
    test('offset 0 es literalmente "mismo día"', () {
      expect(diasCalendarioDespues(DateTime(2026, 8, 21), 0), DateTime(2026, 8, 21));
    });

    test('a diferencia de días hábiles, sí cuenta fines de semana', () {
      // Viernes 2026-08-21 + 4 días de calendario = martes 25 (incluye
      // sábado y domingo, nunca los salta).
      expect(diasCalendarioDespues(DateTime(2026, 8, 21), 4), DateTime(2026, 8, 25));
    });

    test('cruza fin de mes sin ajuste especial', () {
      expect(diasCalendarioDespues(DateTime(2026, 8, 25), 7), DateTime(2026, 9, 1));
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

  group('CalcularFechasCobroUseCase — casos reales de sistema (2-3 etapas fijas)', () {
    const calcular = CalcularFechasCobroUseCase();
    // periodoFin cualquiera de estos casos no usa Cierre de periodo como
    // origen — se pasa un valor cualquiera del mes para no ensuciar los
    // casos con un cálculo de límites de periodo que no viene al caso.
    final periodoFinCualquiera = DateTime(2026, 1, 31);

    test('Miluyole: emisión día 1, procesamiento primer miércoles del mismo mes, pago miércoles siguiente', () {
      final etapas = [
        _etapa(id: 'e', tipoSistema: TipoEventoCobro.emision, orden: 0, tipoRegla: TipoReglaEvento.diaFijoDelMes, mesRelativo: MesRelativoCobro.actual, diaDelMes: 1),
        _etapa(id: 'p', tipoSistema: TipoEventoCobro.procesamiento, orden: 1, tipoRegla: TipoReglaEvento.nEsimoDiaSemanaDelMes, mesRelativo: MesRelativoCobro.actual, diaSemana: DiaSemanaCobro.miercoles, ordinalSemana: OrdinalSemanaCobro.primero),
        _etapa(id: 'pg', tipoSistema: TipoEventoCobro.pagoEsperado, orden: 2, tipoRegla: TipoReglaEvento.mismoDiaSemanaSiguienteA, diaSemana: DiaSemanaCobro.miercoles, etapaReferenciaId: 'p'),
      ];

      final resultado = calcular.ejecutar(etapas: etapas, mesInicioPeriodo: DateTime(2026, 1, 1), periodoFin: periodoFinCualquiera);

      expect(fechaDeEtapaSistema(resultado, TipoEventoCobro.emision), DateTime(2026, 1, 1));
      expect(fechaDeEtapaSistema(resultado, TipoEventoCobro.procesamiento), DateTime(2026, 1, 7));
      expect(fechaDeEtapaSistema(resultado, TipoEventoCobro.pagoEsperado), DateTime(2026, 1, 14));
    });

    test('Morgan: emisión inicio de mes, pago segundo viernes del mes siguiente', () {
      final etapas = [
        _etapa(id: 'e', tipoSistema: TipoEventoCobro.emision, orden: 0, tipoRegla: TipoReglaEvento.diaFijoDelMes, mesRelativo: MesRelativoCobro.actual, diaDelMes: 1),
        _etapa(id: 'pg', tipoSistema: TipoEventoCobro.pagoEsperado, orden: 1, tipoRegla: TipoReglaEvento.nEsimoDiaSemanaDelMes, mesRelativo: MesRelativoCobro.siguiente, diaSemana: DiaSemanaCobro.viernes, ordinalSemana: OrdinalSemanaCobro.segundo),
      ];

      final resultado = calcular.ejecutar(etapas: etapas, mesInicioPeriodo: DateTime(2026, 1, 1), periodoFin: periodoFinCualquiera);

      expect(fechaDeEtapaSistema(resultado, TipoEventoCobro.emision), DateTime(2026, 1, 1));
      expect(fechaDeEtapaSistema(resultado, TipoEventoCobro.procesamiento), isNull);
      expect(fechaDeEtapaSistema(resultado, TipoEventoCobro.pagoEsperado), DateTime(2026, 2, 13));
    });

    test('Toluca 32/Tikal: solo pago, sin inventar una fecha de emisión', () {
      final etapas = [
        _etapa(id: 'pg', tipoSistema: TipoEventoCobro.pagoEsperado, orden: 0, tipoRegla: TipoReglaEvento.diaFijoDelMes, mesRelativo: MesRelativoCobro.actual, diaDelMes: 10),
      ];

      final resultado = calcular.ejecutar(etapas: etapas, mesInicioPeriodo: DateTime(2026, 1, 1), periodoFin: periodoFinCualquiera);

      expect(fechaDeEtapaSistema(resultado, TipoEventoCobro.emision), isNull);
      expect(fechaDeEtapaSistema(resultado, TipoEventoCobro.pagoEsperado), DateTime(2026, 1, 10));
    });

    test('Mirabilia: sin ninguna etapa capturada, no se inventa ninguna fecha', () {
      final resultado = calcular.ejecutar(etapas: const [], mesInicioPeriodo: DateTime(2026, 1, 1), periodoFin: periodoFinCualquiera);
      expect(resultado, isEmpty);
    });

    test('una etapa cuya referencia no está en el lote no se calcula (no inventa fechas)', () {
      final etapas = [
        _etapa(id: 'pg', tipoSistema: TipoEventoCobro.pagoEsperado, orden: 0, tipoRegla: TipoReglaEvento.diasHabilesDespuesDe, offsetDias: 5, etapaReferenciaId: 'no-existe'),
      ];

      final resultado = calcular.ejecutar(etapas: etapas, mesInicioPeriodo: DateTime(2026, 1, 1), periodoFin: periodoFinCualquiera);

      expect(fechaDeEtapaSistema(resultado, TipoEventoCobro.pagoEsperado), isNull);
    });
  });

  group('CalcularFechasCobroUseCase — flujo dinámico completo (Etapa 15)', () {
    const calcular = CalcularFechasCobroUseCase();

    test(
      'Sportium: periodo 21 jul-20 ago → Emisión 21 ago (mes siguiente), Validación mismo día de Emisión, '
      'Carga a portal 4 días después de Validación, Pago esperado 7 días después de Carga a portal',
      () {
        final etapas = [
          _etapa(id: 'emision', tipoSistema: TipoEventoCobro.emision, orden: 0, tipoRegla: TipoReglaEvento.diaFijoDelMes, mesRelativo: MesRelativoCobro.siguiente, diaDelMes: 21),
          _etapa(id: 'validacion', nombre: 'Validación por correo', orden: 1, tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe, offsetDias: 0, etapaReferenciaId: 'emision'),
          _etapa(id: 'portal', nombre: 'Carga a portal', orden: 2, tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe, offsetDias: 4, etapaReferenciaId: 'validacion'),
          _etapa(id: 'pago', tipoSistema: TipoEventoCobro.pagoEsperado, orden: 3, tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe, offsetDias: 7, etapaReferenciaId: 'portal'),
        ];

        // Periodo 21 jul-20 ago: mesInicioPeriodo = julio, mesRelativo
        // "siguiente" para Emisión → agosto.
        final resultado = calcular.ejecutar(etapas: etapas, mesInicioPeriodo: DateTime(2026, 7, 1), periodoFin: DateTime(2026, 8, 20));

        expect(resultado, hasLength(4));
        expect(resultado.firstWhere((f) => f.etapaId == 'emision').fecha, DateTime(2026, 8, 21), reason: 'Emisión');
        expect(resultado.firstWhere((f) => f.etapaId == 'validacion').fecha, DateTime(2026, 8, 21), reason: 'Validación — mismo día de Emisión');
        expect(resultado.firstWhere((f) => f.etapaId == 'portal').fecha, DateTime(2026, 8, 25), reason: 'Carga a portal — 4 días después de Validación');
        expect(resultado.firstWhere((f) => f.etapaId == 'pago').fecha, DateTime(2026, 9, 1), reason: 'Pago esperado — 7 días después de Carga a portal');
      },
    );

    test('cliente simple: Cierre → Emisión → Pago esperado, solo 2 etapas activas, ninguna intermedia', () {
      final etapas = [
        _etapa(id: 'emision', tipoSistema: TipoEventoCobro.emision, orden: 0, tipoRegla: TipoReglaEvento.diaFijoDelMes, mesRelativo: MesRelativoCobro.actual, diaDelMes: 1),
        _etapa(id: 'pago', tipoSistema: TipoEventoCobro.pagoEsperado, orden: 1, tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe, offsetDias: 15, etapaReferenciaId: 'emision'),
      ];

      final resultado = calcular.ejecutar(etapas: etapas, mesInicioPeriodo: DateTime(2026, 9, 1), periodoFin: DateTime(2026, 9, 30));

      expect(resultado, hasLength(2), reason: 'ninguna etapa intermedia activa — nunca se inventa una');
      expect(resultado.firstWhere((f) => f.etapaId == 'emision').fecha, DateTime(2026, 9, 1));
      expect(resultado.firstWhere((f) => f.etapaId == 'pago').fecha, DateTime(2026, 9, 16));
    });

    test('Cierre de periodo como origen virtual: "30 días después de cierre de periodo"', () {
      final etapas = [
        _etapa(id: 'emision', tipoSistema: TipoEventoCobro.emision, orden: 0, tipoRegla: TipoReglaEvento.diaFijoDelMes, mesRelativo: MesRelativoCobro.actual, diaDelMes: 1),
        _etapa(
          id: 'pago',
          tipoSistema: TipoEventoCobro.pagoEsperado,
          orden: 1,
          tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe,
          offsetDias: 30,
          referenciaCierrePeriodo: true,
        ),
      ];

      final periodoFin = DateTime(2026, 9, 30);
      final resultado = calcular.ejecutar(etapas: etapas, mesInicioPeriodo: DateTime(2026, 9, 1), periodoFin: periodoFin);

      expect(resultado.firstWhere((f) => f.etapaId == 'pago').fecha, DateTime(2026, 10, 30), reason: '30 días de calendario después del cierre del periodo (30 sep)');
    });

    test('una etapa desactivada (nunca enviada en la lista) nunca participa — la lista resultante solo trae las activas', () {
      // Mismo Sportium, pero sin "Carga a portal" — la lista resultante
      // solo trae las 3 etapas realmente activas, nunca 4 con un hueco.
      final etapas = [
        _etapa(id: 'emision', tipoSistema: TipoEventoCobro.emision, orden: 0, tipoRegla: TipoReglaEvento.diaFijoDelMes, mesRelativo: MesRelativoCobro.siguiente, diaDelMes: 21),
        _etapa(id: 'validacion', nombre: 'Validación por correo', orden: 1, tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe, offsetDias: 0, etapaReferenciaId: 'emision'),
        _etapa(id: 'pago', tipoSistema: TipoEventoCobro.pagoEsperado, orden: 2, tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe, offsetDias: 7, etapaReferenciaId: 'validacion'),
      ];

      final resultado = calcular.ejecutar(etapas: etapas, mesInicioPeriodo: DateTime(2026, 7, 1), periodoFin: DateTime(2026, 8, 20));

      expect(resultado, hasLength(3));
      expect(resultado.map((f) => f.etapaId), isNot(contains('portal')));
    });
  });
}
