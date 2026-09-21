// Etapa "Vehículos: ciclo de vida y trazabilidad" (schemaVersion 80).
//
// GAP P0 QUE CIERRA: `CorregirVehiculoUseCase` podía cambiar **placas,
// VIN, número de motor y costo de adquisición** — identidad legal del
// activo — sin `motivo`, sin `actorUsuarioId` y sin dejar rastro. Era la
// ÚNICA excepción del proyecto: Personal, Compras, Finanzas, Nómina,
// Deudas y Descuentos ya exigían los tres.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/usuarios/data/repositories/auditoria_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/buscar_auditoria_usecase.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_kilometraje_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_kilometraje_table.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_table.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/corregir_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/registrar_kilometraje_vehiculo_usecase.dart';

void main() {
  late AppDatabase db;
  late VehiculoRepositoryImpl vehiculoRepo;
  late VehiculoKilometrajeRepositoryImpl kilometrajeRepo;
  late CorregirVehiculoUseCase corregir;
  late RegistrarKilometrajeVehiculoUseCase registrarKilometraje;
  late String vehiculoId;
  late String actorId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    vehiculoRepo = VehiculoRepositoryImpl(db, AsignacionVehiculoRepositoryImpl(db));
    kilometrajeRepo = VehiculoKilometrajeRepositoryImpl(db);
    corregir = CorregirVehiculoUseCase(vehiculoRepo);
    registrarKilometraje = RegistrarKilometrajeVehiculoUseCase(kilometrajeRepo, vehiculoRepo);

    final actor = await db.into(db.usuario).insertReturning(
          UsuarioCompanion.insert(
            nombre: 'MARLON',
            nombreUsuario: 'marlon',
            passwordHash: r'pbkdf2$1$c2FsdA==$aGFzaA==',
            esMaestro: const Value(true),
          ),
        );
    actorId = actor.id;

    final vehiculo = await vehiculoRepo.crear(
      codigo: 'VEH-000001',
      marca: 'Nissan',
      modelo: 'NP300',
      tipoVehiculo: 'pickup',
      placas: 'ABC-123',
      vin: 'VIN-ORIGINAL-0001',
      numeroMotor: 'MOT-0001',
      costoAdquisicion: 30000000,
    );
    vehiculoId = vehiculo.id;
  });

  tearDown(() => db.close());

  group('§2 — corrección auditada del expediente', () {
    test('sin motivo se rechaza, y NADA cambia', () async {
      final r = await corregir.ejecutar(vehiculoId: vehiculoId, placas: 'XYZ-999', motivo: '   ');

      expect(r, isA<CorregirVehiculoMotivoRequerido>());
      final sinCambios = await vehiculoRepo.obtenerPorId(vehiculoId);
      expect(sinCambios!.placas, 'ABC-123');
      expect(await vehiculoRepo.listarEventos(vehiculoId), isEmpty);
    });

    test('cambiar placas/VIN/motor deja evento con antes/después y actor', () async {
      final r = await corregir.ejecutar(
        vehiculoId: vehiculoId,
        placas: 'XYZ-999',
        vin: 'VIN-CORREGIDO-0002',
        numeroMotor: 'MOT-0002',
        motivo: 'Reemplacamiento 2026 y corrección de VIN mal capturado',
        actorUsuarioId: actorId,
      );
      expect(r, isA<CorregirVehiculoExitoso>());

      final eventos = await vehiculoRepo.listarEventos(vehiculoId);
      expect(eventos, hasLength(1));
      final evento = eventos.single;
      expect(evento.tipoEvento, TipoEventoVehiculo.corregido.name);
      expect(evento.actorUsuarioId, actorId, reason: 'quién lo hizo');
      expect(evento.observacion, contains('Reemplacamiento'), reason: 'por qué');

      final antes = jsonDecode(evento.estadoAnterior!) as Map<String, dynamic>;
      final despues = jsonDecode(evento.estadoNuevo!) as Map<String, dynamic>;
      expect(antes['placas'], 'ABC-123');
      expect(despues['placas'], 'XYZ-999');
      expect(antes['vin'], 'VIN-ORIGINAL-0001');
      expect(despues['vin'], 'VIN-CORREGIDO-0002');
      expect(antes['numeroMotor'], 'MOT-0001');
      expect(despues['numeroMotor'], 'MOT-0002');
    });

    test('SOLO los campos realmente modificados entran al diff', () async {
      await corregir.ejecutar(
        vehiculoId: vehiculoId,
        color: 'Blanco',
        // Se manda igual que ya estaba: no debe aparecer en el diff.
        marca: 'Nissan',
        motivo: 'Se pintó',
        actorUsuarioId: actorId,
      );

      final evento = (await vehiculoRepo.listarEventos(vehiculoId)).single;
      final despues = jsonDecode(evento.estadoNuevo!) as Map<String, dynamic>;
      expect(despues.keys, ['color'], reason: 'nunca un snapshot completo del registro');
    });

    test('una corrección que no cambia nada NO genera evento', () async {
      final r = await corregir.ejecutar(
        vehiculoId: vehiculoId,
        marca: 'Nissan',
        modelo: 'NP300',
        motivo: 'Sin cambios reales',
        actorUsuarioId: actorId,
      );

      expect(r, isA<CorregirVehiculoExitoso>());
      expect(
        await vehiculoRepo.listarEventos(vehiculoId),
        isEmpty,
        reason: 'una "corrección" que no cambió nada no es una corrección',
      );
    });

    test('el costo de adquisición se audita en centavos, sin pasar por double', () async {
      await corregir.ejecutar(
        vehiculoId: vehiculoId,
        costoAdquisicion: 31550075,
        motivo: 'Factura real',
        actorUsuarioId: actorId,
      );

      final evento = (await vehiculoRepo.listarEventos(vehiculoId)).single;
      final despues = jsonDecode(evento.estadoNuevo!) as Map<String, dynamic>;
      expect(despues['costoAdquisicion'], 31550075);
      expect(despues['costoAdquisicion'], isA<int>(), reason: 'centavos enteros, cero pérdida de precisión');
    });
  });

  group('§10 — el historial llega a Configuración → Auditoría', () {
    test('el evento de Vehículos aparece en la auditoría central', () async {
      await corregir.ejecutar(
        vehiculoId: vehiculoId,
        placas: 'XYZ-999',
        motivo: 'Reemplacamiento',
        actorUsuarioId: actorId,
      );

      final auditoria = await AuditoriaRepositoryImpl(db).buscar(const FiltroAuditoria());
      final deVehiculos = auditoria.where((e) => e.modulo == 'vehiculos').toList();

      expect(deVehiculos, hasLength(1), reason: 'hasta la v79 Vehículos no aparecía en absoluto');
      expect(deVehiculos.single.accion, TipoEventoVehiculo.corregido.name);
      expect(deVehiculos.single.actorUsuarioId, actorId);
      expect(deVehiculos.single.registroId, vehiculoId);
      expect(deVehiculos.single.motivo, 'Reemplacamiento');
    });

    test('el filtro por módulo lo encuentra', () async {
      await corregir.ejecutar(vehiculoId: vehiculoId, color: 'Rojo', motivo: 'Pintura', actorUsuarioId: actorId);

      final soloVehiculos =
          await AuditoriaRepositoryImpl(db).buscar(const FiltroAuditoria(modulo: 'vehiculos'));
      expect(soloVehiculos, hasLength(1));
    });
  });

  group('§12 — kilometraje: la regla de corrección YA existía', () {
    test('un valor menor se rechaza como lectura normal', () async {
      await registrarKilometraje.ejecutar(
        vehiculoId: vehiculoId,
        fecha: DateTime(2026, 5, 1),
        kilometraje: 80000,
        origen: OrigenKilometrajeVehiculo.lecturaManual.name,
      );

      final r = await registrarKilometraje.ejecutar(
        vehiculoId: vehiculoId,
        fecha: DateTime(2026, 5, 2),
        kilometraje: 70000,
        origen: OrigenKilometrajeVehiculo.lecturaManual.name,
      );

      expect(r, isA<RegistrarKilometrajeVehiculoMenorAlActual>(), reason: 'nunca decrece en silencio');
    });

    test('pero SÍ puede bajar como corrección explícita, y exige observaciones', () async {
      await registrarKilometraje.ejecutar(
        vehiculoId: vehiculoId,
        fecha: DateTime(2026, 5, 1),
        kilometraje: 80000,
        origen: OrigenKilometrajeVehiculo.lecturaManual.name,
      );

      final sinObservaciones = await registrarKilometraje.ejecutar(
        vehiculoId: vehiculoId,
        fecha: DateTime(2026, 5, 2),
        kilometraje: 70000,
        origen: OrigenKilometrajeVehiculo.correccion.name,
      );
      expect(
        sinObservaciones,
        isA<RegistrarKilometrajeVehiculoResultado>(),
        reason: 'la corrección exige explicar por qué',
      );
      expect(sinObservaciones, isNot(isA<RegistrarKilometrajeVehiculoExitoso>()));

      final conObservaciones = await registrarKilometraje.ejecutar(
        vehiculoId: vehiculoId,
        fecha: DateTime(2026, 5, 2),
        kilometraje: 70000,
        origen: OrigenKilometrajeVehiculo.correccion.name,
        observaciones: 'El odómetro se había capturado con un dígito de más',
      );
      expect(conObservaciones, isA<RegistrarKilometrajeVehiculoExitoso>());
    });

    test('nunca acepta un valor negativo', () async {
      final r = await registrarKilometraje.ejecutar(
        vehiculoId: vehiculoId,
        fecha: DateTime(2026, 5, 1),
        kilometraje: -1,
        origen: OrigenKilometrajeVehiculo.lecturaManual.name,
      );
      expect(r, isNot(isA<RegistrarKilometrajeVehiculoExitoso>()));
      expect(await db.select(db.vehiculoKilometraje).get(), isEmpty);
    });

    test('la corrección NO destruye el historial: el ledger es append-only', () async {
      await registrarKilometraje.ejecutar(
        vehiculoId: vehiculoId,
        fecha: DateTime(2026, 5, 1),
        kilometraje: 80000,
        origen: OrigenKilometrajeVehiculo.lecturaManual.name,
      );
      await registrarKilometraje.ejecutar(
        vehiculoId: vehiculoId,
        fecha: DateTime(2026, 5, 2),
        kilometraje: 70000,
        origen: OrigenKilometrajeVehiculo.correccion.name,
        observaciones: 'Dígito de más',
      );

      final lecturas = await db.select(db.vehiculoKilometraje).get();
      expect(lecturas, hasLength(2), reason: 'la lectura errónea se conserva como evidencia');
      expect(lecturas.map((l) => l.kilometraje).toSet(), {80000, 70000});

      final actual = await kilometrajeRepo.obtenerActual(vehiculoId);
      expect(actual!.kilometraje, 70000, reason: 'el actual es la lectura más reciente, no la mayor');
    });
  });
}
