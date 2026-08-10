import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/empresa_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/pdf/ficha_tecnica_pdf_renderer.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/ficha_tecnica_empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/crear_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/empleado_validator.dart';
import 'package:riseg_one/features/personal/domain/usecases/generar_ficha_tecnica_empleado_usecase.dart';

void main() {
  late AppDatabase db;
  late EmpleadoRepositoryImpl empleadoRepo;
  late FichaTecnicaEmpleadoRepositoryImpl fichaTecnicaRepo;
  late CrearEmpleadoUseCase crearEmpleado;
  late GenerarFichaTecnicaEmpleadoUseCase generarFichaTecnica;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final puestoRepo = PuestoRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final empresaRepo = EmpresaRepositoryImpl(db);
    final attachmentRepo = AttachmentRepository(db);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    const validator = EmpleadoValidator();

    tempDir = Directory.systemTemp.createTempSync('riseg_ficha_tecnica_test_');
    final storage = AttachmentStorage(tempDir.path);

    fichaTecnicaRepo = FichaTecnicaEmpleadoRepositoryImpl(db);
    crearEmpleado = CrearEmpleadoUseCase(empleadoRepo, generarCodigo, validator, servicioRepo);
    generarFichaTecnica = GenerarFichaTecnicaEmpleadoUseCase(
      empleadoRepo,
      asignacionServicioRepo,
      servicioRepo,
      puestoRepo,
      catalogoRepo,
      empresaRepo,
      attachmentRepo,
      storage,
      fichaTecnicaRepo,
      generarCodigo,
      FichaTecnicaPdfRenderer(),
    );
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<EmpleadoData> crearEmpleadoDePrueba({
    String curp = 'PEXJ900101HDFXXX01',
    String rfc = 'PEXJ900101AB1',
  }) async {
    final resultado = await crearEmpleado.ejecutar(
      nombres: 'Juan',
      apellidoPaterno: 'Pérez',
      sexo: SexoEmpleado.masculino,
      fechaNacimiento: DateTime(1990, 1, 1),
      curp: curp,
      rfc: rfc,
      nss: '12345678901',
      estadoCivil: EstadoCivilEmpleado.soltero,
      fechaIngreso: DateTime(2020, 1, 1),
      aniosExperienciaSeguridad: 3,
    );
    return (resultado as CrearEmpleadoExitoso).empleado;
  }

  group('GenerarFichaTecnicaEmpleadoUseCase', () {
    test('genera un PDF real, lo guarda y crea la fila de historial con folio FICHA-######', () async {
      final empleado = await crearEmpleadoDePrueba();

      final resultado = await generarFichaTecnica.ejecutar(empleadoId: empleado.id);

      expect(resultado, isA<GenerarFichaTecnicaEmpleadoExitoso>());
      final ficha = (resultado as GenerarFichaTecnicaEmpleadoExitoso).ficha;
      expect(ficha.folio, matches(RegExp(r'^FICHA-\d{6}$')));
      expect(ficha.empleadoId, empleado.id);
      expect(ficha.servicioId, isNull, reason: 'el Empleado de prueba no tiene asignación vigente');

      final adjunto = await AttachmentRepository(db).obtenerPorId(ficha.attachmentId);
      expect(adjunto, isNotNull);
      expect(adjunto!.mimeType, 'application/pdf');
      expect(adjunto.sizeBytes, greaterThan(0));

      final archivo = File(adjunto.path);
      expect(archivo.existsSync(), isTrue);
      final bytes = await archivo.readAsBytes();
      expect(String.fromCharCodes(bytes.take(4)), '%PDF', reason: 'el archivo guardado debe ser un PDF real');

      final eventos = await empleadoRepo.listarEventos(empleado.id);
      expect(eventos.map((e) => e.tipoEvento), contains('fichaTecnicaGenerada'));
    });

    test('el folio es correlativo indefinido, sin reiniciar', () async {
      final empleado = await crearEmpleadoDePrueba();

      final primera = await generarFichaTecnica.ejecutar(empleadoId: empleado.id);
      final segunda = await generarFichaTecnica.ejecutar(empleadoId: empleado.id);

      expect((primera as GenerarFichaTecnicaEmpleadoExitoso).ficha.folio, 'FICHA-000001');
      expect((segunda as GenerarFichaTecnicaEmpleadoExitoso).ficha.folio, 'FICHA-000002');
    });

    test('cada generación crea una fila nueva — nunca sobrescribe una anterior (snapshot/historial)', () async {
      final empleado = await crearEmpleadoDePrueba();

      await generarFichaTecnica.ejecutar(empleadoId: empleado.id);
      await generarFichaTecnica.ejecutar(empleadoId: empleado.id, seccionesExcluidas: const {'antidoping'});

      final historial = await fichaTecnicaRepo.listarPorEmpleado(empleado.id);
      expect(historial, hasLength(2));
      expect(historial.map((f) => f.camposExcluidos), containsAll([null, 'antidoping']));
    });

    test('persiste las secciones excluidas separadas por coma', () async {
      final empleado = await crearEmpleadoDePrueba();

      final resultado = await generarFichaTecnica.ejecutar(
        empleadoId: empleado.id,
        seccionesExcluidas: const {'fotografia', 'antidoping'},
      );

      final ficha = (resultado as GenerarFichaTecnicaEmpleadoExitoso).ficha;
      expect(ficha.camposExcluidos, isNotNull);
      expect(ficha.camposExcluidos!.split(','), containsAll(['fotografia', 'antidoping']));
    });

    test('devuelve NoExiste si el Empleado no existe', () async {
      final resultado = await generarFichaTecnica.ejecutar(empleadoId: 'empleado-inexistente');
      expect(resultado, isA<GenerarFichaTecnicaEmpleadoNoExiste>());
    });
  });

  group('FichaTecnicaEmpleadoRepository.listarPorEmpleado', () {
    test('ordena descendente por fecha de creación (la más reciente primero)', () async {
      final empleado = await crearEmpleadoDePrueba();

      await generarFichaTecnica.ejecutar(empleadoId: empleado.id);
      await generarFichaTecnica.ejecutar(empleadoId: empleado.id);

      final historial = await fichaTecnicaRepo.listarPorEmpleado(empleado.id);
      expect(historial, hasLength(2));
      expect(historial.first.folio, 'FICHA-000002');
      expect(historial.last.folio, 'FICHA-000001');
    });

    test('vacío para un Empleado sin fichas generadas', () async {
      final empleado = await crearEmpleadoDePrueba();
      final historial = await fichaTecnicaRepo.listarPorEmpleado(empleado.id);
      expect(historial, isEmpty);
    });
  });
}
