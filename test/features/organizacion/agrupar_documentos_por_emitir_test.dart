import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/organizacion/domain/usecases/agrupar_documentos_por_emitir.dart';

CandidatoDocumentoPorEmitir _candidato({
  required String servicioId,
  String clienteId = 'cliente-1',
  String? entidadFiscalId,
  String tipoDocumento = 'cfdi',
  String metodo = 'pue',
  bool requiereComplemento = false,
  DateTime? periodoInicio,
  DateTime? periodoFin,
  String configuracionCobroVigenciaId = 'vigencia-1',
}) {
  return CandidatoDocumentoPorEmitir(
    servicioId: servicioId,
    clienteId: clienteId,
    entidadFiscalId: entidadFiscalId,
    tipoDocumento: tipoDocumento,
    metodo: metodo,
    requiereComplemento: requiereComplemento,
    periodoInicio: periodoInicio ?? DateTime(2026, 8, 1),
    periodoFin: periodoFin ?? DateTime(2026, 8, 31),
    configuracionCobroVigenciaId: configuracionCobroVigenciaId,
  );
}

void main() {
  group('sonCompatiblesParaAgrupar — Agrupaciones compatibles (Etapa 4I.1)', () {
    test('mismo Cliente, tipo de documento, periodo, método y complemento son compatibles', () {
      final a = _candidato(servicioId: 's1');
      final b = _candidato(servicioId: 's2');
      expect(sonCompatiblesParaAgrupar(a, b), isTrue);
    });

    test('Clientes distintos nunca son compatibles', () {
      final a = _candidato(servicioId: 's1', clienteId: 'cliente-1');
      final b = _candidato(servicioId: 's2', clienteId: 'cliente-2');
      expect(sonCompatiblesParaAgrupar(a, b), isFalse);
    });

    test('CFDI con Entidad fiscal distinta no es compatible', () {
      final a = _candidato(servicioId: 's1', entidadFiscalId: 'ef-1');
      final b = _candidato(servicioId: 's2', entidadFiscalId: 'ef-2');
      expect(sonCompatiblesParaAgrupar(a, b), isFalse);
    });

    test('recibo con Entidad fiscal distinta sí es compatible (Entidad fiscal solo importa para CFDI)', () {
      final a = _candidato(servicioId: 's1', tipoDocumento: 'reciboDePago', entidadFiscalId: 'ef-1');
      final b = _candidato(servicioId: 's2', tipoDocumento: 'reciboDePago', entidadFiscalId: 'ef-2');
      expect(sonCompatiblesParaAgrupar(a, b), isTrue);
    });

    test('periodos distintos no son compatibles', () {
      final a = _candidato(servicioId: 's1', periodoInicio: DateTime(2026, 8, 1), periodoFin: DateTime(2026, 8, 31));
      final b = _candidato(servicioId: 's2', periodoInicio: DateTime(2026, 9, 1), periodoFin: DateTime(2026, 9, 30));
      expect(sonCompatiblesParaAgrupar(a, b), isFalse);
    });

    test('métodos distintos no son compatibles', () {
      final a = _candidato(servicioId: 's1', metodo: 'pue');
      final b = _candidato(servicioId: 's2', metodo: 'ppd');
      expect(sonCompatiblesParaAgrupar(a, b), isFalse);
    });

    test('condición de complemento distinta no es compatible', () {
      final a = _candidato(servicioId: 's1', requiereComplemento: false);
      final b = _candidato(servicioId: 's2', requiereComplemento: true);
      expect(sonCompatiblesParaAgrupar(a, b), isFalse);
    });

    test('nunca se agrupa solo por compartir Cliente o Entidad fiscal', () {
      final a = _candidato(servicioId: 's1', entidadFiscalId: 'ef-1', metodo: 'pue');
      final b = _candidato(servicioId: 's2', entidadFiscalId: 'ef-1', metodo: 'ppd');
      expect(sonCompatiblesParaAgrupar(a, b), isFalse);
    });
  });

  group('agruparCompatibles — partición en los grupos compatibles más grandes', () {
    test('todos compatibles quedan en un solo grupo', () {
      final candidatos = [_candidato(servicioId: 's1'), _candidato(servicioId: 's2'), _candidato(servicioId: 's3')];
      final grupos = agruparCompatibles(candidatos);
      expect(grupos, hasLength(1));
      expect(grupos.single, hasLength(3));
    });

    test('un Servicio con condiciones distintas queda en su propio grupo, nunca mezclado', () {
      final candidatos = [
        _candidato(servicioId: 's1', metodo: 'pue'),
        _candidato(servicioId: 's2', metodo: 'pue'),
        _candidato(servicioId: 's3', metodo: 'ppd'),
      ];
      final grupos = agruparCompatibles(candidatos);

      expect(grupos, hasLength(2));
      final grupoPue = grupos.firstWhere((g) => g.length == 2);
      final grupoPpd = grupos.firstWhere((g) => g.length == 1);
      expect(grupoPue.map((c) => c.servicioId), containsAll(['s1', 's2']));
      expect(grupoPpd.single.servicioId, 's3');
    });

    test('lista vacía produce cero grupos', () {
      expect(agruparCompatibles(const []), isEmpty);
    });
  });
}
