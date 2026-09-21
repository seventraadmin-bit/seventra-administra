// Etapa "Vehículos: ciclo de vida" (schemaVersion 80) — §12.
//
// GAP QUE CIERRA: `VehiculoDocumento` solo sabía REGISTRAR. Renovar era
// registrar otra vez, y estaba bien; pero un folio capturado con un
// dígito de más solo se podía "arreglar" registrando una renovación
// falsa — que inventaba una vigencia que nunca existió y además movía
// las alertas de vencimiento del vehículo.
//
// Además: qué pasa con los DERIVADOS cuando un mantenimiento se anula.
// El costo acumulado y el próximo mantenimiento programado son cálculos
// puros sobre el historial; si no saltaran las filas anuladas, la
// pantalla del vehículo contradiría a Finanzas.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_documento_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_documento_table.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_mantenimiento_table.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_table.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/calcular_costos_vehiculo.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/calcular_proximo_mantenimiento.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/corregir_documento_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/registrar_documento_vehiculo_usecase.dart';

void main() {
  late AppDatabase db;
  late VehiculoRepositoryImpl vehiculoRepo;
  late VehiculoDocumentoRepositoryImpl documentoRepo;
  late RegistrarDocumentoVehiculoUseCase registrar;
  late CorregirDocumentoVehiculoUseCase corregir;
  late String vehiculoId;
  late String actorId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    vehiculoRepo = VehiculoRepositoryImpl(db, AsignacionVehiculoRepositoryImpl(db));
    documentoRepo = VehiculoDocumentoRepositoryImpl(db);
    registrar = RegistrarDocumentoVehiculoUseCase(documentoRepo, vehiculoRepo);
    corregir = CorregirDocumentoVehiculoUseCase(documentoRepo, vehiculoRepo);

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
    );
    vehiculoId = vehiculo.id;
  });

  tearDown(() => db.close());

  Future<VehiculoDocumentoData> registrarPoliza() async {
    final r = await registrar.ejecutar(
      vehiculoId: vehiculoId,
      tipo: TipoDocumentoVehiculo.seguro.name,
      numeroFolio: 'POL-99999',
      fechaEmision: DateTime(2026, 1, 15),
      fechaVencimiento: DateTime(2027, 1, 15),
    );
    return (r as RegistrarDocumentoVehiculoExitoso).documento;
  }

  group('§12 — corregir un documento NO es renovarlo', () {
    test('la corrección arregla la MISMA fila: no aparece una vigencia inventada', () async {
      final poliza = await registrarPoliza();

      final r = await corregir.ejecutar(
        vehiculoDocumentoId: poliza.id,
        numeroFolio: 'POL-99998',
        motivo: 'El folio se capturó con un dígito de más',
        actorUsuarioId: actorId,
      );

      expect(r, isA<CorregirDocumentoVehiculoExitoso>());
      final documentos = await documentoRepo.listarPorVehiculo(vehiculoId);
      expect(documentos, hasLength(1), reason: 'antes de la v80 esto habría dejado DOS pólizas');
      expect(documentos.single.id, poliza.id);
      expect(documentos.single.numeroFolio, 'POL-99998');
      expect(documentos.single.fechaVencimiento, DateTime(2027, 1, 15), reason: 'la vigencia real no se movió');
    });

    test('sin motivo se rechaza, y NADA cambia', () async {
      final poliza = await registrarPoliza();

      final r = await corregir.ejecutar(vehiculoDocumentoId: poliza.id, numeroFolio: 'X', motivo: '  ');

      expect(r, isA<CorregirDocumentoVehiculoMotivoRequerido>());
      final sinCambios = await documentoRepo.obtenerPorId(poliza.id);
      expect(sinCambios!.numeroFolio, 'POL-99999');
      expect(await vehiculoRepo.listarEventos(vehiculoId), isEmpty);
    });

    test('deja evento con antes/después de SOLO lo que cambió, y su actor', () async {
      final poliza = await registrarPoliza();

      await corregir.ejecutar(
        vehiculoDocumentoId: poliza.id,
        numeroFolio: 'POL-99998',
        fechaVencimiento: DateTime(2027, 3, 31),
        motivo: 'Folio y vencimiento mal capturados según la carátula',
        actorUsuarioId: actorId,
      );

      final evento = (await vehiculoRepo.listarEventos(vehiculoId)).single;
      expect(evento.tipoEvento, TipoEventoVehiculo.documentoCorregido.name);
      expect(evento.actorUsuarioId, actorId);
      expect(evento.observacion, contains('carátula'));

      final antes = jsonDecode(evento.estadoAnterior!) as Map<String, dynamic>;
      final despues = jsonDecode(evento.estadoNuevo!) as Map<String, dynamic>;
      expect(antes['numeroFolio'], 'POL-99999');
      expect(despues['numeroFolio'], 'POL-99998');
      expect(despues.containsKey('fechaVencimiento'), isTrue);
      expect(
        despues.containsKey('fechaEmision'),
        isFalse,
        reason: 'la emisión no se tocó: nunca un snapshot completo',
      );
    });

    test('una corrección que no cambia nada NO genera evento', () async {
      final poliza = await registrarPoliza();

      final r = await corregir.ejecutar(
        vehiculoDocumentoId: poliza.id,
        numeroFolio: 'POL-99999',
        fechaEmision: DateTime(2026, 1, 15),
        fechaVencimiento: DateTime(2027, 1, 15),
        motivo: 'Revisión sin cambios',
        actorUsuarioId: actorId,
      );

      expect(r, isA<CorregirDocumentoVehiculoExitoso>());
      expect(await vehiculoRepo.listarEventos(vehiculoId), isEmpty);
    });

    test('las fechas se validan sobre el RESULTADO, no sobre lo que llegó', () async {
      final poliza = await registrarPoliza();

      // Solo se corrige la emisión, pero la deja después del vencimiento
      // que ya estaba guardado.
      final r = await corregir.ejecutar(
        vehiculoDocumentoId: poliza.id,
        fechaEmision: DateTime(2027, 6, 1),
        motivo: 'Emisión mal capturada',
        actorUsuarioId: actorId,
      );

      expect(r, isA<CorregirDocumentoVehiculoFechasInvalidas>());
      final sinCambios = await documentoRepo.obtenerPorId(poliza.id);
      expect(sinCambios!.fechaEmision, DateTime(2026, 1, 15));
    });

    test('vaciar el folio es distinto de no tocarlo', () async {
      final poliza = await registrarPoliza();

      await corregir.ejecutar(
        vehiculoDocumentoId: poliza.id,
        limpiarNumeroFolio: true,
        motivo: 'Este documento no tiene folio',
        actorUsuarioId: actorId,
      );

      expect((await documentoRepo.obtenerPorId(poliza.id))!.numeroFolio, isNull);
    });

    test('un documento "Otro" no puede quedarse sin descripción', () async {
      final otro = await registrar.ejecutar(
        vehiculoId: vehiculoId,
        tipo: TipoDocumentoVehiculo.otro.name,
        tipoOtroDescripcion: 'Constancia de GPS',
      );
      final documento = (otro as RegistrarDocumentoVehiculoExitoso).documento;

      final r = await corregir.ejecutar(
        vehiculoDocumentoId: documento.id,
        tipoOtroDescripcion: '   ',
        motivo: 'Intento de dejarlo vacío',
        actorUsuarioId: actorId,
      );

      expect(r, isA<CorregirDocumentoVehiculoDescripcionRequerida>());
      expect((await documentoRepo.obtenerPorId(documento.id))!.tipoOtroDescripcion, 'Constancia de GPS');
    });
  });

  group('§6 — un mantenimiento anulado deja de pesar en los derivados', () {
    VehiculoMantenimientoData fila({
      required int costo,
      required String estatus,
      String tipo = 'servicioGeneral',
      DateTime? proximoFecha,
      int? proximoKilometraje,
      DateTime? fecha,
    }) {
      return VehiculoMantenimientoData(
        id: 'm-$costo-$estatus-${proximoFecha ?? ''}',
        vehiculoId: vehiculoId,
        fecha: fecha ?? DateTime(2026, 5, 1),
        tipo: tipo,
        descripcion: 'x',
        costo: costo,
        proximoMantenimientoFecha: proximoFecha,
        proximoMantenimientoKilometraje: proximoKilometraje,
        estatus: estatus,
        cicloVidaRegistro: 'activo',
        createdAt: DateTime(2026, 5, 1),
        updatedAt: DateTime(2026, 5, 1),
      );
    }

    test('el costo acumulado excluye lo anulado — si no, contradiría a Finanzas', () async {
      final vehiculo = (await vehiculoRepo.obtenerPorId(vehiculoId))!;

      final costos = calcularCostosVehiculo(vehiculo, [
        fila(costo: 250000, estatus: EstatusMantenimientoVehiculo.registrado.name),
        fila(costo: 380000, estatus: EstatusMantenimientoVehiculo.cancelado.name),
        fila(costo: 120000, estatus: EstatusMantenimientoVehiculo.cancelado.name, tipo: 'golpe'),
        fila(costo: 90000, estatus: EstatusMantenimientoVehiculo.registrado.name, tipo: 'golpe'),
      ]);

      expect(costos.totalMantenimientos, 250000);
      expect(costos.totalIncidencias, 90000);
    });

    test('un "próximo mantenimiento" anulado no programa nada: se usa la fila válida anterior', () {
      final proximo = calcularProximoMantenimiento(
        [
          // La más reciente está anulada — el servicio nunca ocurrió.
          fila(
            costo: 380000,
            estatus: EstatusMantenimientoVehiculo.cancelado.name,
            fecha: DateTime(2026, 6, 1),
            proximoFecha: DateTime(2026, 12, 1),
          ),
          fila(
            costo: 250000,
            estatus: EstatusMantenimientoVehiculo.registrado.name,
            fecha: DateTime(2026, 5, 1),
            proximoFecha: DateTime(2026, 11, 1),
          ),
        ],
        null,
        hoy: DateTime(2026, 6, 15),
      );

      expect(proximo, isNotNull);
      expect(proximo!.fecha, DateTime(2026, 11, 1), reason: 'nunca la fecha que dejó agendada un registro anulado');
    });
  });
}
