import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_regla_evento_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_regla_evento_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_regla_evento_validator.dart';

void main() {
  const validator = ConfiguracionCobroReglaEventoValidator();

  group('Corrección obligatoria — reglas parciales o ausentes', () {
    test('sin ninguna regla capturada, no hay errores (Mirabilia)', () {
      final resultado = validator.validar(const [
        ReglaEventoBorrador(tipoEvento: TipoEventoCobro.emision),
        ReglaEventoBorrador(tipoEvento: TipoEventoCobro.procesamiento),
        ReglaEventoBorrador(tipoEvento: TipoEventoCobro.pagoEsperado),
      ]);

      expect(resultado.errores, isEmpty);
      expect(resultado.resultado, isEmpty);
    });

    test('solo Pago esperado capturado, sin Emisión ni Procesamiento, no hay errores (Toluca 32/Tikal)', () {
      final resultado = validator.validar(const [
        ReglaEventoBorrador(
          tipoEvento: TipoEventoCobro.pagoEsperado,
          tipoRegla: TipoReglaEvento.diaFijoDelMes,
          mesRelativo: MesRelativoCobro.actual,
          diaDelMes: 10,
        ),
      ]);

      expect(resultado.errores, isEmpty);
      expect(resultado.resultado, hasLength(1));
    });
  });

  group('coherencia por tipoRegla', () {
    test('diaFijoDelMes sin mesRelativo/diaDelMes es rechazado', () {
      final resultado = validator.validar(const [
        ReglaEventoBorrador(tipoEvento: TipoEventoCobro.emision, tipoRegla: TipoReglaEvento.diaFijoDelMes),
      ]);

      expect(resultado.errores.any((e) => e.campo == CampoReglaEvento.mesRelativo), isTrue);
      expect(resultado.errores.any((e) => e.campo == CampoReglaEvento.diaDelMes), isTrue);
    });

    test('nEsimoDiaSemanaDelMes sin ordinalSemana/diaSemana/mesRelativo es rechazado', () {
      final resultado = validator.validar(const [
        ReglaEventoBorrador(
          tipoEvento: TipoEventoCobro.procesamiento,
          tipoRegla: TipoReglaEvento.nEsimoDiaSemanaDelMes,
        ),
      ]);

      expect(resultado.errores.any((e) => e.campo == CampoReglaEvento.mesRelativo), isTrue);
      expect(resultado.errores.any((e) => e.campo == CampoReglaEvento.diaSemana), isTrue);
      expect(resultado.errores.any((e) => e.campo == CampoReglaEvento.ordinalSemana), isTrue);
    });

    test('diasHabilesDespuesDe sin offsetDiasHabiles/eventoReferencia es rechazado', () {
      final resultado = validator.validar(const [
        ReglaEventoBorrador(tipoEvento: TipoEventoCobro.emision, tipoRegla: TipoReglaEvento.diaFijoDelMes, mesRelativo: MesRelativoCobro.actual, diaDelMes: 1),
        ReglaEventoBorrador(tipoEvento: TipoEventoCobro.pagoEsperado, tipoRegla: TipoReglaEvento.diasHabilesDespuesDe),
      ]);

      expect(resultado.errores.any((e) => e.campo == CampoReglaEvento.offsetDiasHabiles), isTrue);
      expect(resultado.errores.any((e) => e.campo == CampoReglaEvento.eventoReferencia), isTrue);
    });

    test('mismoDiaSemanaSiguienteA sin diaSemana/eventoReferencia es rechazado', () {
      final resultado = validator.validar(const [
        ReglaEventoBorrador(tipoEvento: TipoEventoCobro.emision, tipoRegla: TipoReglaEvento.diaFijoDelMes, mesRelativo: MesRelativoCobro.actual, diaDelMes: 1),
        ReglaEventoBorrador(tipoEvento: TipoEventoCobro.pagoEsperado, tipoRegla: TipoReglaEvento.mismoDiaSemanaSiguienteA),
      ]);

      expect(resultado.errores.any((e) => e.campo == CampoReglaEvento.diaSemana), isTrue);
      expect(resultado.errores.any((e) => e.campo == CampoReglaEvento.eventoReferencia), isTrue);
    });
  });

  group('reglas de referencia entre eventos', () {
    test('Emisión nunca puede depender de otro evento', () {
      final resultado = validator.validar(const [
        ReglaEventoBorrador(
          tipoEvento: TipoEventoCobro.emision,
          tipoRegla: TipoReglaEvento.diaFijoDelMes,
          mesRelativo: MesRelativoCobro.actual,
          diaDelMes: 1,
          eventoReferencia: TipoEventoCobro.pagoEsperado,
        ),
      ]);

      expect(
        resultado.errores.any(
          (e) => e.tipoEvento == TipoEventoCobro.emision && e.codigo == CodigoErrorReglaEvento.eventoReferenciaNoPermitido,
        ),
        isTrue,
      );
    });

    test('Procesamiento solo puede depender de Emisión, nunca de Pago esperado', () {
      final resultado = validator.validar(const [
        ReglaEventoBorrador(tipoEvento: TipoEventoCobro.emision, tipoRegla: TipoReglaEvento.diaFijoDelMes, mesRelativo: MesRelativoCobro.actual, diaDelMes: 1),
        ReglaEventoBorrador(
          tipoEvento: TipoEventoCobro.pagoEsperado,
          tipoRegla: TipoReglaEvento.diaFijoDelMes,
          mesRelativo: MesRelativoCobro.actual,
          diaDelMes: 10,
        ),
        ReglaEventoBorrador(
          tipoEvento: TipoEventoCobro.procesamiento,
          tipoRegla: TipoReglaEvento.diasHabilesDespuesDe,
          offsetDiasHabiles: 1,
          eventoReferencia: TipoEventoCobro.pagoEsperado,
        ),
      ]);

      expect(
        resultado.errores.any(
          (e) =>
              e.tipoEvento == TipoEventoCobro.procesamiento &&
              e.codigo == CodigoErrorReglaEvento.eventoReferenciaNoPermitido,
        ),
        isTrue,
      );
    });

    test('Pago esperado puede depender de Emisión o de Procesamiento', () {
      final resultadoEmision = validator.validar(const [
        ReglaEventoBorrador(tipoEvento: TipoEventoCobro.emision, tipoRegla: TipoReglaEvento.diaFijoDelMes, mesRelativo: MesRelativoCobro.actual, diaDelMes: 21),
        ReglaEventoBorrador(
          tipoEvento: TipoEventoCobro.pagoEsperado,
          tipoRegla: TipoReglaEvento.diasHabilesDespuesDe,
          offsetDiasHabiles: 10,
          eventoReferencia: TipoEventoCobro.emision,
        ),
      ]);
      expect(resultadoEmision.errores, isEmpty);

      final resultadoProcesamiento = validator.validar(const [
        ReglaEventoBorrador(tipoEvento: TipoEventoCobro.emision, tipoRegla: TipoReglaEvento.diaFijoDelMes, mesRelativo: MesRelativoCobro.actual, diaDelMes: 1),
        ReglaEventoBorrador(
          tipoEvento: TipoEventoCobro.procesamiento,
          tipoRegla: TipoReglaEvento.nEsimoDiaSemanaDelMes,
          mesRelativo: MesRelativoCobro.actual,
          diaSemana: DiaSemanaCobro.miercoles,
          ordinalSemana: OrdinalSemanaCobro.primero,
        ),
        ReglaEventoBorrador(
          tipoEvento: TipoEventoCobro.pagoEsperado,
          tipoRegla: TipoReglaEvento.mismoDiaSemanaSiguienteA,
          diaSemana: DiaSemanaCobro.miercoles,
          eventoReferencia: TipoEventoCobro.procesamiento,
        ),
      ]);
      expect(resultadoProcesamiento.errores, isEmpty);
    });

    test('rechaza auto-referencia', () {
      final resultado = validator.validar(const [
        ReglaEventoBorrador(
          tipoEvento: TipoEventoCobro.pagoEsperado,
          tipoRegla: TipoReglaEvento.diasHabilesDespuesDe,
          offsetDiasHabiles: 5,
          eventoReferencia: TipoEventoCobro.pagoEsperado,
        ),
      ]);

      expect(resultado.errores.any((e) => e.codigo == CodigoErrorReglaEvento.autoReferencia), isTrue);
    });

    test('rechaza una referencia a un evento no capturado en esta misma vigencia', () {
      final resultado = validator.validar(const [
        ReglaEventoBorrador(
          tipoEvento: TipoEventoCobro.pagoEsperado,
          tipoRegla: TipoReglaEvento.diasHabilesDespuesDe,
          offsetDiasHabiles: 10,
          eventoReferencia: TipoEventoCobro.emision,
        ),
      ]);

      expect(resultado.errores.any((e) => e.codigo == CodigoErrorReglaEvento.eventoReferenciaNoExiste), isTrue);
    });

    test('rechaza un ciclo Procesamiento→Pago→Procesamiento', () {
      // Nota: esta combinación ya es individualmente inválida por las
      // combinaciones permitidas (Procesamiento solo puede depender de
      // Emisión), así que el ciclo nunca llega a evaluarse — pero el
      // resultado final debe seguir siendo un rechazo.
      final resultado = validator.validar(const [
        ReglaEventoBorrador(
          tipoEvento: TipoEventoCobro.procesamiento,
          tipoRegla: TipoReglaEvento.diasHabilesDespuesDe,
          offsetDiasHabiles: 1,
          eventoReferencia: TipoEventoCobro.pagoEsperado,
        ),
        ReglaEventoBorrador(
          tipoEvento: TipoEventoCobro.pagoEsperado,
          tipoRegla: TipoReglaEvento.diasHabilesDespuesDe,
          offsetDiasHabiles: 1,
          eventoReferencia: TipoEventoCobro.procesamiento,
        ),
      ]);

      expect(resultado.errores, isNotEmpty);
      expect(resultado.resultado, isEmpty);
    });
  });
}
