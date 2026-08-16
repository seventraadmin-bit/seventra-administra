import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_etapa_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_etapa_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_etapa_validator.dart';

/// Cubre `ConfiguracionCobroEtapaValidator` (Etapa 15, reemplaza
/// `ConfiguracionCobroReglaEventoValidator` de la Etapa 4H.2) — a
/// diferencia de su predecesor, el grafo de referencias ya no está
/// hardcodeado a pares fijos (Emisión nunca depende de nada;
/// Procesamiento solo de Emisión; Pago esperado de Emisión o
/// Procesamiento): cualquier etapa, incluida Emisión, puede depender de
/// cualquier otra etapa capturada en el lote o del origen virtual
/// Cierre de periodo. También cubre las etapas personalizadas
/// (`tipoSistema == null`, exigen `nombre`) y la nueva regla
/// `diasCalendarioDespuesDe` (offset 0 = "mismo día").
void main() {
  const validator = ConfiguracionCobroEtapaValidator();

  group('Corrección obligatoria — etapas parciales, ausentes o sin regla capturada', () {
    test('lista vacía no genera errores (una Configuración de cobro puede guardarse sin ningún flujo capturado)', () {
      final resultado = validator.validar(const []);
      expect(resultado.errores, isEmpty);
      expect(resultado.resultado, isEmpty);
    });

    test('una etapa activa sin regla capturada todavía se persiste (activo != capturado, Etapa 15)', () {
      final resultado = validator.validar(const [
        EtapaCobroBorrador(id: 'e1', tipoSistema: TipoEventoCobro.emision, orden: 0),
      ]);

      expect(resultado.errores, isEmpty);
      expect(resultado.resultado, hasLength(1));
      expect(resultado.resultado.single.tipoRegla, isNull);
    });

    test('solo Pago esperado capturado, sin Emisión, no hay errores (Toluca 32/Tikal)', () {
      final resultado = validator.validar(const [
        EtapaCobroBorrador(
          id: 'e1',
          tipoSistema: TipoEventoCobro.pagoEsperado,
          orden: 0,
          tipoRegla: TipoReglaEvento.diaFijoDelMes,
          mesRelativo: MesRelativoCobro.actual,
          diaDelMes: 10,
        ),
      ]);

      expect(resultado.errores, isEmpty);
      expect(resultado.resultado, hasLength(1));
    });
  });

  group('etapas personalizadas', () {
    test('exige nombre cuando tipoSistema es null', () {
      final resultado = validator.validar(const [
        EtapaCobroBorrador(id: 'e1', orden: 0),
      ]);

      expect(
        resultado.errores.any((e) => e.etapaId == 'e1' && e.campo == CampoEtapaCobro.nombre && e.codigo == CodigoErrorEtapaCobro.requerido),
        isTrue,
      );
    });

    test('nombre en blanco (solo espacios) también se rechaza', () {
      final resultado = validator.validar(const [
        EtapaCobroBorrador(id: 'e1', nombre: '   ', orden: 0),
      ]);

      expect(resultado.errores.any((e) => e.campo == CampoEtapaCobro.nombre), isTrue);
    });

    test('una etapa personalizada con nombre y sin tipoSistema es válida y se persiste tal cual', () {
      final resultado = validator.validar(const [
        EtapaCobroBorrador(id: 'e1', nombre: 'Validación por correo', orden: 0),
      ]);

      expect(resultado.errores, isEmpty);
      expect(resultado.resultado.single.nombre, 'Validación por correo');
      expect(resultado.resultado.single.tipoSistema, isNull);
    });

    test('dos etapas de sistema con el mismo tipoSistema se rechazan (a lo más una por tipo)', () {
      final resultado = validator.validar(const [
        EtapaCobroBorrador(id: 'e1', tipoSistema: TipoEventoCobro.emision, orden: 0),
        EtapaCobroBorrador(id: 'e2', tipoSistema: TipoEventoCobro.emision, orden: 1),
      ]);

      expect(resultado.errores.any((e) => e.codigo == CodigoErrorEtapaCobro.tipoSistemaDuplicado), isTrue);
    });

    test('varias etapas personalizadas conviven sin problema (sin tipoSistema, sin restricción de unicidad)', () {
      final resultado = validator.validar(const [
        EtapaCobroBorrador(id: 'e1', nombre: 'Validación', orden: 0),
        EtapaCobroBorrador(id: 'e2', nombre: 'Carga a portal', orden: 1),
      ]);

      expect(resultado.errores, isEmpty);
    });
  });

  group('coherencia por tipoRegla', () {
    test('diaFijoDelMes sin mesRelativo/diaDelMes es rechazado', () {
      final resultado = validator.validar(const [
        EtapaCobroBorrador(id: 'e1', tipoSistema: TipoEventoCobro.emision, orden: 0, tipoRegla: TipoReglaEvento.diaFijoDelMes),
      ]);

      expect(resultado.errores.any((e) => e.campo == CampoEtapaCobro.mesRelativo), isTrue);
      expect(resultado.errores.any((e) => e.campo == CampoEtapaCobro.diaDelMes), isTrue);
    });

    test('nEsimoDiaSemanaDelMes sin ordinalSemana/diaSemana/mesRelativo es rechazado', () {
      final resultado = validator.validar(const [
        EtapaCobroBorrador(id: 'e1', tipoSistema: TipoEventoCobro.procesamiento, orden: 0, tipoRegla: TipoReglaEvento.nEsimoDiaSemanaDelMes),
      ]);

      expect(resultado.errores.any((e) => e.campo == CampoEtapaCobro.mesRelativo), isTrue);
      expect(resultado.errores.any((e) => e.campo == CampoEtapaCobro.diaSemana), isTrue);
      expect(resultado.errores.any((e) => e.campo == CampoEtapaCobro.ordinalSemana), isTrue);
    });

    test('diasHabilesDespuesDe sin offsetDias/referencia es rechazado', () {
      final resultado = validator.validar(const [
        EtapaCobroBorrador(id: 'e1', tipoSistema: TipoEventoCobro.emision, orden: 0, tipoRegla: TipoReglaEvento.diaFijoDelMes, mesRelativo: MesRelativoCobro.actual, diaDelMes: 1),
        EtapaCobroBorrador(id: 'e2', tipoSistema: TipoEventoCobro.pagoEsperado, orden: 1, tipoRegla: TipoReglaEvento.diasHabilesDespuesDe),
      ]);

      expect(resultado.errores.any((e) => e.etapaId == 'e2' && e.campo == CampoEtapaCobro.offsetDias), isTrue);
      expect(resultado.errores.any((e) => e.etapaId == 'e2' && e.campo == CampoEtapaCobro.etapaReferenciaId), isTrue);
    });

    test('diasCalendarioDespuesDe sin offsetDias/referencia es rechazado', () {
      final resultado = validator.validar(const [
        EtapaCobroBorrador(id: 'e1', tipoSistema: TipoEventoCobro.emision, orden: 0, tipoRegla: TipoReglaEvento.diaFijoDelMes, mesRelativo: MesRelativoCobro.actual, diaDelMes: 21),
        EtapaCobroBorrador(id: 'e2', nombre: 'Validación', orden: 1, tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe),
      ]);

      expect(resultado.errores.any((e) => e.etapaId == 'e2' && e.campo == CampoEtapaCobro.offsetDias), isTrue);
      expect(resultado.errores.any((e) => e.etapaId == 'e2' && e.campo == CampoEtapaCobro.etapaReferenciaId), isTrue);
    });

    test('diasCalendarioDespuesDe con offsetDias 0 ("mismo día") es una regla completa y válida', () {
      final resultado = validator.validar(const [
        EtapaCobroBorrador(id: 'e1', tipoSistema: TipoEventoCobro.emision, orden: 0, tipoRegla: TipoReglaEvento.diaFijoDelMes, mesRelativo: MesRelativoCobro.actual, diaDelMes: 21),
        EtapaCobroBorrador(
          id: 'e2',
          nombre: 'Validación',
          orden: 1,
          tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe,
          offsetDias: 0,
          etapaReferenciaId: 'e1',
        ),
      ]);

      expect(resultado.errores, isEmpty, reason: 'offsetDias == 0 es un valor real capturado, nunca "campo vacío"');
    });

    test('mismoDiaSemanaSiguienteA sin diaSemana/referencia es rechazado', () {
      final resultado = validator.validar(const [
        EtapaCobroBorrador(id: 'e1', tipoSistema: TipoEventoCobro.emision, orden: 0, tipoRegla: TipoReglaEvento.diaFijoDelMes, mesRelativo: MesRelativoCobro.actual, diaDelMes: 1),
        EtapaCobroBorrador(id: 'e2', tipoSistema: TipoEventoCobro.pagoEsperado, orden: 1, tipoRegla: TipoReglaEvento.mismoDiaSemanaSiguienteA),
      ]);

      expect(resultado.errores.any((e) => e.campo == CampoEtapaCobro.diaSemana), isTrue);
      expect(resultado.errores.any((e) => e.campo == CampoEtapaCobro.etapaReferenciaId), isTrue);
    });
  });

  group('referencias entre etapas — generalizadas (Etapa 15, ya no hay pares fijos)', () {
    test('Emisión SÍ puede depender de otra etapa (antes prohibido, ahora permitido)', () {
      final resultado = validator.validar(const [
        EtapaCobroBorrador(
          id: 'emision',
          tipoSistema: TipoEventoCobro.emision,
          orden: 0,
          tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe,
          offsetDias: 5,
          referenciaCierrePeriodo: true,
        ),
      ]);

      expect(resultado.errores, isEmpty, reason: 'Cierre de periodo es un origen válido para cualquier etapa, incluida Emisión');
    });

    test('Pago esperado puede depender de una etapa personalizada intermedia (Sportium: Portal → Pago)', () {
      final resultado = validator.validar(const [
        EtapaCobroBorrador(id: 'emision', tipoSistema: TipoEventoCobro.emision, orden: 0, tipoRegla: TipoReglaEvento.diaFijoDelMes, mesRelativo: MesRelativoCobro.siguiente, diaDelMes: 21),
        EtapaCobroBorrador(id: 'validacion', nombre: 'Validación', orden: 1, tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe, offsetDias: 0, etapaReferenciaId: 'emision'),
        EtapaCobroBorrador(id: 'portal', nombre: 'Carga a portal', orden: 2, tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe, offsetDias: 4, etapaReferenciaId: 'validacion'),
        EtapaCobroBorrador(id: 'pago', tipoSistema: TipoEventoCobro.pagoEsperado, orden: 3, tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe, offsetDias: 7, etapaReferenciaId: 'portal'),
      ]);

      expect(resultado.errores, isEmpty);
      expect(resultado.resultado, hasLength(4));
    });

    test('etapaReferenciaId y referenciaCierrePeriodo a la vez es una referencia ambigua', () {
      final resultado = validator.validar(const [
        EtapaCobroBorrador(id: 'emision', tipoSistema: TipoEventoCobro.emision, orden: 0, tipoRegla: TipoReglaEvento.diaFijoDelMes, mesRelativo: MesRelativoCobro.actual, diaDelMes: 1),
        EtapaCobroBorrador(
          id: 'pago',
          tipoSistema: TipoEventoCobro.pagoEsperado,
          orden: 1,
          tipoRegla: TipoReglaEvento.diasHabilesDespuesDe,
          offsetDias: 5,
          etapaReferenciaId: 'emision',
          referenciaCierrePeriodo: true,
        ),
      ]);

      expect(resultado.errores.any((e) => e.codigo == CodigoErrorEtapaCobro.referenciaAmbigua), isTrue);
    });

    test('rechaza auto-referencia', () {
      final resultado = validator.validar(const [
        EtapaCobroBorrador(
          id: 'pago',
          tipoSistema: TipoEventoCobro.pagoEsperado,
          orden: 0,
          tipoRegla: TipoReglaEvento.diasHabilesDespuesDe,
          offsetDias: 5,
          etapaReferenciaId: 'pago',
        ),
      ]);

      expect(resultado.errores.any((e) => e.codigo == CodigoErrorEtapaCobro.autoReferencia), isTrue);
    });

    test('rechaza una referencia a una etapa que no está en el lote', () {
      final resultado = validator.validar(const [
        EtapaCobroBorrador(
          id: 'pago',
          tipoSistema: TipoEventoCobro.pagoEsperado,
          orden: 0,
          tipoRegla: TipoReglaEvento.diasHabilesDespuesDe,
          offsetDias: 10,
          etapaReferenciaId: 'emision-que-no-existe',
        ),
      ]);

      expect(resultado.errores.any((e) => e.codigo == CodigoErrorEtapaCobro.referenciaNoExiste), isTrue);
    });

    test('rechaza un ciclo directo A→B→A', () {
      final resultado = validator.validar(const [
        EtapaCobroBorrador(id: 'a', nombre: 'A', orden: 0, tipoRegla: TipoReglaEvento.diasHabilesDespuesDe, offsetDias: 1, etapaReferenciaId: 'b'),
        EtapaCobroBorrador(id: 'b', nombre: 'B', orden: 1, tipoRegla: TipoReglaEvento.diasHabilesDespuesDe, offsetDias: 1, etapaReferenciaId: 'a'),
      ]);

      expect(resultado.errores, isNotEmpty);
      expect(resultado.errores.any((e) => e.codigo == CodigoErrorEtapaCobro.cicloDetectado), isTrue);
      expect(resultado.resultado, isEmpty, reason: 'todo o nada — un ciclo rechaza el lote completo');
    });

    test('rechaza un ciclo indirecto A→B→C→A (tres etapas, ninguna combinación de pares fijos que lo impida ahora)', () {
      final resultado = validator.validar(const [
        EtapaCobroBorrador(id: 'a', nombre: 'A', orden: 0, tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe, offsetDias: 1, etapaReferenciaId: 'c'),
        EtapaCobroBorrador(id: 'b', nombre: 'B', orden: 1, tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe, offsetDias: 1, etapaReferenciaId: 'a'),
        EtapaCobroBorrador(id: 'c', nombre: 'C', orden: 2, tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe, offsetDias: 1, etapaReferenciaId: 'b'),
      ]);

      expect(resultado.errores.any((e) => e.codigo == CodigoErrorEtapaCobro.cicloDetectado), isTrue);
    });
  });
}
