import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/organizacion/domain/usecases/documento_por_emitir_generation_key.dart';

void main() {
  group('calcularGenerationKey — idempotencia (Etapa 4I.1)', () {
    test('el mismo grupo produce la misma clave sin importar el orden de Servicios y vigencias', () {
      final claveA = calcularGenerationKey(
        agrupacion: 'porCliente',
        tipoDocumento: 'cfdi',
        clienteId: 'cliente-1',
        servicioIds: ['servicio-a', 'servicio-b'],
        configuracionCobroVigenciaIds: ['vigencia-a', 'vigencia-b'],
        periodoInicio: DateTime(2026, 8, 1),
        periodoFin: DateTime(2026, 8, 31),
        entidadFiscalId: 'entidad-1',
      );
      final claveB = calcularGenerationKey(
        agrupacion: 'porCliente',
        tipoDocumento: 'cfdi',
        clienteId: 'cliente-1',
        servicioIds: ['servicio-b', 'servicio-a'],
        configuracionCobroVigenciaIds: ['vigencia-b', 'vigencia-a'],
        periodoInicio: DateTime(2026, 8, 1),
        periodoFin: DateTime(2026, 8, 31),
        entidadFiscalId: 'entidad-1',
      );

      expect(claveA, claveB);
    });

    test('cambiar el conjunto de Servicios produce una clave distinta', () {
      final base = calcularGenerationKey(
        agrupacion: 'porServicio',
        tipoDocumento: 'reciboDePago',
        clienteId: 'cliente-1',
        servicioIds: ['servicio-a'],
        configuracionCobroVigenciaIds: ['vigencia-a'],
        periodoInicio: DateTime(2026, 8, 1),
        periodoFin: DateTime(2026, 8, 31),
      );
      final otroServicio = calcularGenerationKey(
        agrupacion: 'porServicio',
        tipoDocumento: 'reciboDePago',
        clienteId: 'cliente-1',
        servicioIds: ['servicio-c'],
        configuracionCobroVigenciaIds: ['vigencia-a'],
        periodoInicio: DateTime(2026, 8, 1),
        periodoFin: DateTime(2026, 8, 31),
      );

      expect(base, isNot(otroServicio));
    });

    test('cambiar el periodo produce una clave distinta aunque el resto sea igual', () {
      final agosto = calcularGenerationKey(
        agrupacion: 'porServicio',
        tipoDocumento: 'reciboDePago',
        clienteId: 'cliente-1',
        servicioIds: ['servicio-a'],
        configuracionCobroVigenciaIds: ['vigencia-a'],
        periodoInicio: DateTime(2026, 8, 1),
        periodoFin: DateTime(2026, 8, 31),
      );
      final septiembre = calcularGenerationKey(
        agrupacion: 'porServicio',
        tipoDocumento: 'reciboDePago',
        clienteId: 'cliente-1',
        servicioIds: ['servicio-a'],
        configuracionCobroVigenciaIds: ['vigencia-a'],
        periodoInicio: DateTime(2026, 9, 1),
        periodoFin: DateTime(2026, 9, 30),
      );

      expect(agosto, isNot(septiembre));
    });

    test('sin Entidad fiscal la clave sigue siendo determinista (nunca null en la concatenación)', () {
      final resultado = calcularGenerationKey(
        agrupacion: 'porServicio',
        tipoDocumento: 'reciboDePago',
        clienteId: 'cliente-1',
        servicioIds: ['servicio-a'],
        configuracionCobroVigenciaIds: ['vigencia-a'],
        periodoInicio: DateTime(2026, 8, 1),
        periodoFin: DateTime(2026, 8, 31),
      );

      expect(resultado, contains('porServicio|cliente-1||servicio-a|vigencia-a|2026-08-01|2026-08-31|reciboDePago'));
    });
  });
}
