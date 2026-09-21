import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/personal/domain/usecases/construir_eventos_baja.dart';

EmpleadoData _empleado({
  required String id,
  required int numero,
  required String estatus,
  DateTime? fechaBaja,
  String? motivoBaja,
  String? puestoNombreBaja,
  String? servicioNombreBaja,
  String? turnoNombreBaja,
}) {
  return EmpleadoData(
    id: id,
    numeroEmpleado: numero,
    nombres: 'Empleado',
    apellidoPaterno: '$numero',
    sexo: 'masculino',
    fechaNacimiento: DateTime(1990, 1, 1),
    curp: 'X',
    rfc: 'X',
    nss: 'X',
    estadoCivil: 'soltero',
    nacionalidad: 'Mexicana',
    fechaIngreso: DateTime(2026, 1, 1),
    estatus: estatus,
    fechaBaja: fechaBaja,
    motivoBaja: motivoBaja,
    puestoNombreBaja: puestoNombreBaja,
    servicioNombreBaja: servicioNombreBaja,
    turnoNombreBaja: turnoNombreBaja,
    aniosExperienciaSeguridad: 0,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    cicloVidaRegistro: 'activo',
  );
}

void main() {
  group('construirEventosBaja', () {
    test('un Empleado activo (nunca de baja, sin periodos archivados) no genera ningún evento', () {
      final activo = _empleado(id: 'e1', numero: 1, estatus: 'activo');
      final eventos = construirEventosBaja([activo], const {});
      expect(eventos, isEmpty);
    });

    test('un Empleado actualmente de baja (nunca reingresó) genera exactamente 1 evento, con el snapshot de Empleado', () {
      final baja = _empleado(
        id: 'e1',
        numero: 1,
        estatus: 'baja',
        fechaBaja: DateTime(2026, 6, 1),
        motivoBaja: 'renuncia',
        puestoNombreBaja: 'Elemento Operativo',
        servicioNombreBaja: 'Morgan Atlacomulco',
        turnoNombreBaja: '24x24',
      );
      final eventos = construirEventosBaja([baja], const {});

      expect(eventos, hasLength(1));
      expect(eventos.single.esBajaVigente, isTrue);
      expect(eventos.single.motivoBaja, 'renuncia');
      expect(eventos.single.puestoNombre, 'Elemento Operativo');
      expect(eventos.single.servicioNombre, 'Morgan Atlacomulco');
      expect(eventos.single.turnoNombre, '24x24');
    });

    test('Ingreso → Baja → Reingreso → Baja genera DOS eventos independientes — nunca uno solo', () {
      final empleado = _empleado(
        id: 'e1',
        numero: 1,
        estatus: 'baja',
        fechaBaja: DateTime(2026, 8, 1),
        motivoBaja: 'inasistencias',
        servicioNombreBaja: 'Sportium Satélite',
      );
      final periodoArchivado = EmpleadoPeriodoLaboralData(
        id: 1,
        empleadoId: 'e1',
        fechaIngreso: DateTime(2025, 1, 1),
        fechaBaja: DateTime(2025, 6, 1),
        motivoBaja: 'finContrato',
        servicioNombre: 'Morgan Atlacomulco',
      );

      final eventos = construirEventosBaja([empleado], {
        'e1': [periodoArchivado],
      });

      expect(eventos, hasLength(2), reason: 'un periodo laboral terminado = un evento, nunca uno por Empleado');
      expect(eventos.where((e) => e.esBajaVigente), hasLength(1));
      expect(eventos.where((e) => !e.esBajaVigente), hasLength(1));
      expect(eventos.map((e) => e.motivoBaja), containsAll(['inasistencias', 'finContrato']));
    });

    test('orden por defecto: fecha de baja más reciente primero', () {
      final empleado = _empleado(id: 'e1', numero: 1, estatus: 'baja', fechaBaja: DateTime(2026, 3, 1), motivoBaja: 'renuncia');
      final periodoAntiguo = EmpleadoPeriodoLaboralData(id: 1, empleadoId: 'e1', fechaIngreso: DateTime(2024, 1, 1), fechaBaja: DateTime(2024, 6, 1), motivoBaja: 'finContrato');
      final periodoReciente = EmpleadoPeriodoLaboralData(id: 2, empleadoId: 'e1', fechaIngreso: DateTime(2025, 1, 1), fechaBaja: DateTime(2025, 12, 1), motivoBaja: 'renuncia');

      final eventos = construirEventosBaja([empleado], {
        'e1': [periodoAntiguo, periodoReciente],
      });

      expect(eventos.map((e) => e.fechaBaja), [DateTime(2026, 3, 1), DateTime(2025, 12, 1), DateTime(2024, 6, 1)]);
    });

    test('permanencia de cada evento usa el periodo laboral de ESE evento, nunca la fecha de creación del Empleado', () {
      final periodo = EmpleadoPeriodoLaboralData(id: 1, empleadoId: 'e1', fechaIngreso: DateTime(2025, 1, 1), fechaBaja: DateTime(2025, 1, 15), motivoBaja: 'inasistencias');
      final empleado = _empleado(id: 'e1', numero: 1, estatus: 'activo');

      final eventos = construirEventosBaja([empleado], {
        'e1': [periodo],
      });

      expect(eventos.single.permanenciaDias, 14);
      expect(eventos.single.esRotacionTemprana, isTrue);
    });
  });
}
