// BUG REAL — "Dashboard ignora asignaciones históricas con
// lineaComercialId = NULL" (Juan Manuel Zintzun López / MILOYILE).
// Pruebas de la función pura `atribuirAsignacionesHistoricas`, la
// política de atribución (Reglas A/B del pedido de Marlon):
//  A) Servicio con exactamente UNA línea vigente → cualquier
//     asignación histórica sin línea se atribuye a esa única línea sin
//     ambigüedad posible.
//  B) Servicio con 2+ líneas vigentes → solo se atribuye si el
//     `turnoId` de la asignación coincide con exactamente UNA línea;
//     en cualquier otro caso (turno nulo, coincide con 0 o con 2+)
//     queda en `ambiguas` — NUNCA se adivina.

import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/atribucion_historica_linea_comercial.dart';

AsignacionServicioData _asignacion({required String id, String? turnoId}) {
  return AsignacionServicioData(
    id: id,
    empleadoId: 'empleado-$id',
    servicioId: 'servicio-1',
    fechaInicio: DateTime(2025, 11, 20),
    turnoId: turnoId,
    lineaComercialId: null,
    cicloVidaRegistro: 'activo',
    createdAt: DateTime(2025, 11, 20),
    updatedAt: DateTime(2025, 11, 20),
  );
}

void main() {
  group('atribuirAsignacionesHistoricas — Regla A (una sola línea vigente)', () {
    test('MILOYILE: 1 línea vigente + 1 histórico NULL → se atribuye sin ambigüedad, cero ambiguas', () {
      final resultado = atribuirAsignacionesHistoricas(
        asignacionesSinLinea: [_asignacion(id: 'a1')],
        lineasVigentes: const [LineaVigenteAtribuible(lineaComercialId: 'linea-miloyile', modalidadTurnoId: 'turno-12x12')],
      );

      expect(resultado.atribuidasPorLinea, {'linea-miloyile': 1});
      expect(resultado.ambiguas, isEmpty);
    });

    test('1 línea vigente + 2 históricos NULL → ambos se atribuyen a la misma línea (el tope de cobertura se aplica después, no aquí)', () {
      final resultado = atribuirAsignacionesHistoricas(
        asignacionesSinLinea: [_asignacion(id: 'a1'), _asignacion(id: 'a2')],
        lineasVigentes: const [LineaVigenteAtribuible(lineaComercialId: 'linea-1', modalidadTurnoId: 'turno-12x12')],
      );

      expect(resultado.atribuidasPorLinea, {'linea-1': 2});
      expect(resultado.ambiguas, isEmpty);
    });

    test('el turnoId es irrelevante cuando solo hay una línea candidata — atribuye aunque turnoId sea null', () {
      final resultado = atribuirAsignacionesHistoricas(
        asignacionesSinLinea: [_asignacion(id: 'a1', turnoId: null)],
        lineasVigentes: const [LineaVigenteAtribuible(lineaComercialId: 'linea-1', modalidadTurnoId: 'turno-24x24')],
      );

      expect(resultado.atribuidasPorLinea, {'linea-1': 1});
    });
  });

  group('atribuirAsignacionesHistoricas — Regla B (2+ líneas vigentes)', () {
    test('2 líneas con turnos distintos + histórico con turnoId que coincide con exactamente una → se atribuye a esa línea', () {
      final resultado = atribuirAsignacionesHistoricas(
        asignacionesSinLinea: [_asignacion(id: 'a1', turnoId: 'turno-12x12')],
        lineasVigentes: const [
          LineaVigenteAtribuible(lineaComercialId: 'linea-guardia', modalidadTurnoId: 'turno-24x24'),
          LineaVigenteAtribuible(lineaComercialId: 'linea-jefe', modalidadTurnoId: 'turno-12x12'),
        ],
      );

      expect(resultado.atribuidasPorLinea, {'linea-jefe': 1});
      expect(resultado.ambiguas, isEmpty);
    });

    test('2 líneas + histórico sin turnoId (ambiguo) → NUNCA se atribuye arbitrariamente, queda en ambiguas', () {
      final asignacion = _asignacion(id: 'a1', turnoId: null);
      final resultado = atribuirAsignacionesHistoricas(
        asignacionesSinLinea: [asignacion],
        lineasVigentes: const [
          LineaVigenteAtribuible(lineaComercialId: 'linea-guardia', modalidadTurnoId: 'turno-24x24'),
          LineaVigenteAtribuible(lineaComercialId: 'linea-jefe', modalidadTurnoId: 'turno-12x12'),
        ],
      );

      expect(resultado.atribuidasPorLinea, isEmpty);
      expect(resultado.ambiguas, [asignacion]);
    });

    test('2 líneas con el MISMO turno + histórico de ese turno (coincide con 2) → ambiguo, no se atribuye', () {
      final asignacion = _asignacion(id: 'a1', turnoId: 'turno-24x24');
      final resultado = atribuirAsignacionesHistoricas(
        asignacionesSinLinea: [asignacion],
        lineasVigentes: const [
          LineaVigenteAtribuible(lineaComercialId: 'linea-1', modalidadTurnoId: 'turno-24x24'),
          LineaVigenteAtribuible(lineaComercialId: 'linea-2', modalidadTurnoId: 'turno-24x24'),
        ],
      );

      expect(resultado.atribuidasPorLinea, isEmpty);
      expect(resultado.ambiguas, [asignacion]);
    });

    test('2 líneas + histórico con turnoId que no coincide con ninguna → ambiguo, no se atribuye', () {
      final asignacion = _asignacion(id: 'a1', turnoId: 'turno-desconocido');
      final resultado = atribuirAsignacionesHistoricas(
        asignacionesSinLinea: [asignacion],
        lineasVigentes: const [
          LineaVigenteAtribuible(lineaComercialId: 'linea-1', modalidadTurnoId: 'turno-24x24'),
          LineaVigenteAtribuible(lineaComercialId: 'linea-2', modalidadTurnoId: 'turno-12x12'),
        ],
      );

      expect(resultado.atribuidasPorLinea, isEmpty);
      expect(resultado.ambiguas, [asignacion]);
    });
  });

  group('atribuirAsignacionesHistoricas — casos vacíos', () {
    test('sin líneas vigentes → todas quedan ambiguas (nada que atribuir)', () {
      final asignacion = _asignacion(id: 'a1');
      final resultado = atribuirAsignacionesHistoricas(asignacionesSinLinea: [asignacion], lineasVigentes: const []);

      expect(resultado.atribuidasPorLinea, isEmpty);
      expect(resultado.ambiguas, [asignacion]);
    });

    test('sin asignaciones históricas → resultado vacío, sin excepciones', () {
      final resultado = atribuirAsignacionesHistoricas(
        asignacionesSinLinea: const [],
        lineasVigentes: const [LineaVigenteAtribuible(lineaComercialId: 'linea-1', modalidadTurnoId: 'turno-1')],
      );

      expect(resultado.atribuidasPorLinea, isEmpty);
      expect(resultado.ambiguas, isEmpty);
    });
  });
}
