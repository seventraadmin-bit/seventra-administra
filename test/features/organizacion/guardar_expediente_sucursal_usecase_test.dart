import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';
import 'package:riseg_one/features/organizacion/data/repositories/sucursal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_sucursal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/shared/horario_input.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_expediente_sucursal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/obtener_expediente_sucursal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/sucursal_expediente_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/sucursal_expediente_input.dart';

List<HorarioDiaBorrador> _semanaCerrada() => [for (var i = 0; i < 7; i++) const HorarioDiaBorrador(abierto: false)];

void main() {
  late AppDatabase db;
  late SucursalRepositoryImpl repo;
  late GuardarExpedienteSucursalUseCase guardar;
  late String sucursalId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = SucursalRepositoryImpl(db);
    guardar = GuardarExpedienteSucursalUseCase(repo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final crear = CrearSucursalUseCase(repo, generarCodigo);
    final creada = await crear.ejecutar(nombre: 'Sucursal Norte', tipoSucursalId: SeedIds.tipoSucursalBaseOperativa);
    sucursalId = creada.when(ok: (s) => s.id, failure: (f) => throw StateError(f.message));
  });

  tearDown(() => db.close());

  test('guarda datos generales, dirección y horario válidos en una sola operación', () async {
    final resultado = await guardar.ejecutar(
      sucursalId: sucursalId,
      input: SucursalExpedienteInput(
        datosGenerales: const SucursalDatosGeneralesInput(
          nombre: 'Sucursal Norte Renombrada',
          tipoSucursalId: SeedIds.tipoSucursalBodega,
        ),
        direccionPrincipal: const DireccionBorrador(
          calle: 'Reforma',
          numeroExterior: '123',
          colonia: 'Centro',
          municipioAlcaldia: 'Cuauhtémoc',
          estado: 'CDMX',
          codigoPostal: '06000',
        ),
        horario: HorarioSemanalBorrador(
          dias: [
            for (var i = 0; i < 7; i++)
              if (i < 5)
                const HorarioDiaBorrador(abierto: true, horaInicioMinutos: 480, horaFinMinutos: 1080)
              else
                const HorarioDiaBorrador(abierto: false),
          ],
        ),
      ),
    );

    expect(resultado, isA<GuardarExpedienteSucursalExitoso>());
    final exitoso = resultado as GuardarExpedienteSucursalExitoso;
    expect(exitoso.datos.sucursal.nombre, 'Sucursal Norte Renombrada');
    expect(exitoso.datos.direccionPrincipal!.calle, 'Reforma');
    expect(exitoso.datos.horario!.where((d) => d.activo), hasLength(5));
  });

  test('tipoSucursalId vacío reporta el error estructurado sin persistir', () async {
    final resultado = await guardar.ejecutar(
      sucursalId: sucursalId,
      input: SucursalExpedienteInput(
        datosGenerales: const SucursalDatosGeneralesInput(nombre: 'X', tipoSucursalId: ''),
        horario: HorarioSemanalBorrador(dias: _semanaCerrada()),
      ),
    );

    expect(resultado, isA<GuardarExpedienteSucursalErroresValidacion>());
    final errores = (resultado as GuardarExpedienteSucursalErroresValidacion).errores;
    expect(errores.whereType<ErrorTipoSucursalRequerido>(), isNotEmpty);
  });

  test('dirección parcial delega en DireccionValidator y reporta sus errores', () async {
    final resultado = await guardar.ejecutar(
      sucursalId: sucursalId,
      input: SucursalExpedienteInput(
        datosGenerales: const SucursalDatosGeneralesInput(nombre: 'X', tipoSucursalId: SeedIds.tipoSucursalBodega),
        direccionPrincipal: const DireccionBorrador(colonia: 'Centro'),
        horario: HorarioSemanalBorrador(dias: _semanaCerrada()),
      ),
    );

    expect(resultado, isA<GuardarExpedienteSucursalErroresValidacion>());
    final errores = (resultado as GuardarExpedienteSucursalErroresValidacion).errores.whereType<ErrorDireccionSucursal>();
    expect(errores.map((e) => e.error.campo), contains(CampoDireccion.calle));
  });

  test('horario con hora de inicio y fin iguales se rechaza', () async {
    final dias = _semanaCerrada();
    dias[0] = const HorarioDiaBorrador(abierto: true, horaInicioMinutos: 480, horaFinMinutos: 480);

    final resultado = await guardar.ejecutar(
      sucursalId: sucursalId,
      input: SucursalExpedienteInput(
        datosGenerales: const SucursalDatosGeneralesInput(nombre: 'X', tipoSucursalId: SeedIds.tipoSucursalBodega),
        horario: HorarioSemanalBorrador(dias: dias),
      ),
    );

    expect(resultado, isA<GuardarExpedienteSucursalErroresValidacion>());
    final errores = (resultado as GuardarExpedienteSucursalErroresValidacion).errores.whereType<ErrorHorarioSucursal>();
    expect(errores.map((e) => e.codigo), contains(CodigoErrorHorario.horasIguales));
  });

  test('horario que cruza medianoche se infiere automáticamente, no es un error', () async {
    final dias = _semanaCerrada();
    dias[0] = const HorarioDiaBorrador(abierto: true, horaInicioMinutos: 1320, horaFinMinutos: 120);

    final resultado = await guardar.ejecutar(
      sucursalId: sucursalId,
      input: SucursalExpedienteInput(
        datosGenerales: const SucursalDatosGeneralesInput(nombre: 'X', tipoSucursalId: SeedIds.tipoSucursalBodega),
        horario: HorarioSemanalBorrador(dias: dias),
      ),
    );

    expect(resultado, isA<GuardarExpedienteSucursalExitoso>());
    final lunes = (resultado as GuardarExpedienteSucursalExitoso).datos.horario!.firstWhere((d) => d.diaSemana == 0);
    expect(lunes.cruzaMedianoche, isTrue);
  });

  test('horario parcial (falta hora de fin) reporta el error sin persistir', () async {
    final dias = _semanaCerrada();
    dias[0] = const HorarioDiaBorrador(abierto: true, horaInicioMinutos: 480);

    final resultado = await guardar.ejecutar(
      sucursalId: sucursalId,
      input: SucursalExpedienteInput(
        datosGenerales: const SucursalDatosGeneralesInput(nombre: 'X', tipoSucursalId: SeedIds.tipoSucursalBodega),
        horario: HorarioSemanalBorrador(dias: dias),
      ),
    );

    expect(resultado, isA<GuardarExpedienteSucursalErroresValidacion>());
    final errores = (resultado as GuardarExpedienteSucursalErroresValidacion).errores.whereType<ErrorHorarioSucursal>();
    expect(errores.map((e) => e.codigo), contains(CodigoErrorHorario.horaFinRequerida));
  });

  test('horario completamente cerrado no crea ningún registro', () async {
    final resultado = await guardar.ejecutar(
      sucursalId: sucursalId,
      input: SucursalExpedienteInput(
        datosGenerales: const SucursalDatosGeneralesInput(nombre: 'X', tipoSucursalId: SeedIds.tipoSucursalBodega),
        horario: HorarioSemanalBorrador(dias: _semanaCerrada()),
      ),
    );

    expect(resultado, isA<GuardarExpedienteSucursalExitoso>());
    expect((resultado as GuardarExpedienteSucursalExitoso).datos.horario, isNull);
  });

  test('ObtenerExpedienteSucursalUseCase refleja lo guardado', () async {
    await guardar.ejecutar(
      sucursalId: sucursalId,
      input: SucursalExpedienteInput(
        datosGenerales: const SucursalDatosGeneralesInput(nombre: 'Actualizada', tipoSucursalId: SeedIds.tipoSucursalBodega),
        horario: HorarioSemanalBorrador(dias: _semanaCerrada()),
      ),
    );

    final obtener = ObtenerExpedienteSucursalUseCase(repo);
    final resultado = await obtener.ejecutar(sucursalId);
    resultado.when(
      ok: (d) => expect(d.sucursal.nombre, 'Actualizada'),
      failure: (f) => fail('no debería fallar: ${f.message}'),
    );
  });
}
