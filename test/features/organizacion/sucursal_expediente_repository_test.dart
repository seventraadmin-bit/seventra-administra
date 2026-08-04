import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/organizacion/data/repositories/sucursal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/sucursal_table.dart';
import 'package:riseg_one/features/organizacion/domain/shared/direccion_input.dart';
import 'package:riseg_one/features/organizacion/domain/shared/horario_input.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_sucursal_usecase.dart';

const _direccionCompleta = DireccionInput(
  calle: 'Reforma',
  numeroExterior: '123',
  colonia: 'Centro',
  municipioAlcaldia: 'Cuauhtémoc',
  estado: 'CDMX',
  codigoPostal: '06000',
  pais: 'México',
);

List<HorarioDiaInput> _horarioLunesAViernes() => [
      for (var i = 0; i < 7; i++)
        if (i < 5)
          HorarioDiaInput(diaSemana: i, abierto: true, horaInicioMinutos: 480, horaFinMinutos: 1080)
        else
          HorarioDiaInput(diaSemana: i, abierto: false),
    ];

void main() {
  late AppDatabase db;
  late SucursalRepositoryImpl repo;
  late String sucursalId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = SucursalRepositoryImpl(db);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final crear = CrearSucursalUseCase(repo, generarCodigo);
    final creada = await crear.ejecutar(nombre: 'Sucursal Norte', tipoSucursalId: SeedIds.tipoSucursalBaseOperativa);
    sucursalId = creada.when(ok: (s) => s.id, failure: (f) => throw StateError(f.message));
  });

  tearDown(() => db.close());

  SucursalCompanion sinCambiosDeNombre() => const SucursalCompanion();

  test('cambiarEstadoOperativo actualiza el campo sin tocar los demás', () async {
    final actualizada = await repo.cambiarEstadoOperativo(
      sucursalId: sucursalId,
      nuevo: EstadoOperativoSucursal.cerradaTemporalmente,
    );
    expect(actualizada.estadoOperativo, EstadoOperativoSucursal.cerradaTemporalmente.name);

    final reabierta = await repo.cambiarEstadoOperativo(
      sucursalId: sucursalId,
      nuevo: EstadoOperativoSucursal.operando,
    );
    expect(reabierta.estadoOperativo, EstadoOperativoSucursal.operando.name);
  });

  test('guardarExpediente dos veces actualiza la misma Dirección principal, no la duplica', () async {
    await repo.guardarExpediente(
      sucursalId: sucursalId,
      datosGenerales: sinCambiosDeNombre(),
      direccionPrincipal: _direccionCompleta,
      horario: null,
    );
    await repo.guardarExpediente(
      sucursalId: sucursalId,
      datosGenerales: sinCambiosDeNombre(),
      direccionPrincipal: const DireccionInput(
        calle: 'Insurgentes',
        numeroExterior: '456',
        colonia: 'Roma',
        municipioAlcaldia: 'Cuauhtémoc',
        estado: 'CDMX',
        codigoPostal: '06700',
      ),
      horario: null,
    );

    final filas = await db.select(db.direccion).get();
    expect(filas, hasLength(1));
    expect(filas.single.calle, 'Insurgentes');
  });

  test('guardarExpediente dos veces actualiza el mismo Horario, no lo duplica', () async {
    await repo.guardarExpediente(
      sucursalId: sucursalId,
      datosGenerales: sinCambiosDeNombre(),
      direccionPrincipal: null,
      horario: HorarioSemanalInput(dias: _horarioLunesAViernes()),
    );
    await repo.guardarExpediente(
      sucursalId: sucursalId,
      datosGenerales: sinCambiosDeNombre(),
      direccionPrincipal: null,
      horario: HorarioSemanalInput(
        dias: [
          for (var i = 0; i < 7; i++)
            HorarioDiaInput(diaSemana: i, abierto: true, horaInicioMinutos: 540, horaFinMinutos: 1020),
        ],
      ),
    );

    final headers = await db.select(db.horario).get();
    expect(headers, hasLength(1));
    final detalles = await db.select(db.horarioDetalle).get();
    expect(detalles, hasLength(7));
    expect(detalles.every((d) => d.horaInicio == 540 && d.horaFin == 1020), isTrue);
  });

  test('dirección/horario vacíos tras existir uno previo lo archivan, no lo borran', () async {
    await repo.guardarExpediente(
      sucursalId: sucursalId,
      datosGenerales: sinCambiosDeNombre(),
      direccionPrincipal: _direccionCompleta,
      horario: HorarioSemanalInput(dias: _horarioLunesAViernes()),
    );
    await repo.guardarExpediente(
      sucursalId: sucursalId,
      datosGenerales: sinCambiosDeNombre(),
      direccionPrincipal: null,
      horario: null,
    );

    expect(await repo.obtenerDireccionPrincipal(sucursalId), isNull);
    expect(await repo.obtenerHorario(sucursalId), isNull);

    final direcciones = await db.select(db.direccion).get();
    expect(direcciones, hasLength(1));
    expect(direcciones.single.cicloVidaRegistro, 'archivado');

    final horarios = await db.select(db.horario).get();
    expect(horarios, hasLength(1));
    expect(horarios.single.cicloVidaRegistro, 'archivado');
  });

  test('recapturar Dirección y Horario después de archivarlos no revienta contra el índice único', () async {
    await repo.guardarExpediente(
      sucursalId: sucursalId,
      datosGenerales: sinCambiosDeNombre(),
      direccionPrincipal: _direccionCompleta,
      horario: HorarioSemanalInput(dias: _horarioLunesAViernes()),
    );
    // Vaciar ambos los archiva (las filas con `sucursalId` único quedan
    // ocupadas por las filas archivadas).
    await repo.guardarExpediente(
      sucursalId: sucursalId,
      datosGenerales: sinCambiosDeNombre(),
      direccionPrincipal: null,
      horario: null,
    );
    // Recapturar no debe intentar un segundo INSERT contra ese mismo
    // `sucursalId` — debe reactivar y actualizar las filas archivadas.
    await repo.guardarExpediente(
      sucursalId: sucursalId,
      datosGenerales: sinCambiosDeNombre(),
      direccionPrincipal: const DireccionInput(
        calle: 'Recapturada',
        numeroExterior: '1',
        colonia: 'Colonia',
        municipioAlcaldia: 'Municipio',
        estado: 'Estado',
        codigoPostal: '33333',
      ),
      horario: HorarioSemanalInput(dias: _horarioLunesAViernes()),
    );

    final direccion = await repo.obtenerDireccionPrincipal(sucursalId);
    expect(direccion!.calle, 'Recapturada');
    expect(await db.select(db.direccion).get(), hasLength(1));

    final horario = await repo.obtenerHorario(sucursalId);
    expect(horario, isNotNull);
    expect(await db.select(db.horario).get(), hasLength(1));
  });

  test('una falla al guardar el Horario revierte también los datos generales y la Dirección', () async {
    // `diaSemana: 9` viola el CHECK de la tabla (0-6) — provoca una falla
    // SQL real a mitad de la transacción, después de que la Sucursal y
    // la Dirección ya se escribieron dentro de la misma transacción.
    final horarioInvalido = HorarioSemanalInput(
      dias: [
        ..._horarioLunesAViernes().take(6),
        const HorarioDiaInput(diaSemana: 9, abierto: true, horaInicioMinutos: 480, horaFinMinutos: 600),
      ],
    );

    await expectLater(
      repo.guardarExpediente(
        sucursalId: sucursalId,
        datosGenerales: const SucursalCompanion(nombre: Value('Nombre que no debe persistir')),
        direccionPrincipal: _direccionCompleta,
        horario: horarioInvalido,
      ),
      throwsA(anything),
    );

    final sucursal = await repo.obtenerPorId(sucursalId);
    expect(sucursal!.nombre, 'Sucursal Norte');
    expect(await repo.obtenerDireccionPrincipal(sucursalId), isNull);
  });
}
