import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/actualizar_fotografia_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/adjuntar_documento_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/cambiar_estatus_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/corregir_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/crear_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/empleado_alertas.dart';
import 'package:riseg_one/features/personal/domain/usecases/empleado_validator.dart';
import 'package:riseg_one/features/personal/domain/usecases/guardar_domicilio_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_antidoping_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_estudio_socioeconomico_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_perfil_psicologico_usecase.dart';

void main() {
  late AppDatabase db;
  late EmpleadoRepositoryImpl empleadoRepo;
  late CrearEmpleadoUseCase crearEmpleado;
  late CorregirEmpleadoUseCase corregirEmpleado;
  late CambiarEstatusEmpleadoUseCase cambiarEstatusEmpleado;
  late ActualizarFotografiaEmpleadoUseCase actualizarFotografia;
  late GuardarDomicilioEmpleadoUseCase guardarDomicilio;
  late AdjuntarDocumentoEmpleadoUseCase adjuntarDocumento;
  late RegistrarPerfilPsicologicoUseCase registrarPerfilPsicologico;
  late RegistrarEstudioSocioeconomicoUseCase registrarEstudioSocioeconomico;
  late RegistrarAntidopingUseCase registrarAntidoping;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    empleadoRepo = EmpleadoRepositoryImpl(db);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    const validator = EmpleadoValidator();

    crearEmpleado = CrearEmpleadoUseCase(empleadoRepo, generarCodigo, validator);
    corregirEmpleado = CorregirEmpleadoUseCase(empleadoRepo, validator);
    cambiarEstatusEmpleado = CambiarEstatusEmpleadoUseCase(empleadoRepo);
    guardarDomicilio = GuardarDomicilioEmpleadoUseCase(empleadoRepo);

    tempDir = Directory.systemTemp.createTempSync('riseg_empleado_test_');
    final storage = AttachmentStorage(tempDir.path);
    actualizarFotografia = ActualizarFotografiaEmpleadoUseCase(empleadoRepo, AttachmentRepository(db), storage);
    adjuntarDocumento = AdjuntarDocumentoEmpleadoUseCase(empleadoRepo, storage);
    registrarPerfilPsicologico = RegistrarPerfilPsicologicoUseCase(empleadoRepo, storage, validator);
    registrarEstudioSocioeconomico = RegistrarEstudioSocioeconomicoUseCase(empleadoRepo, storage, validator);
    registrarAntidoping = RegistrarAntidopingUseCase(empleadoRepo, storage, validator);
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<CrearEmpleadoResultado> crearEmpleadoDePrueba({
    String nombres = 'Juan',
    String apellidoPaterno = 'Pérez',
    String curp = 'PEXJ900101HDFXXX01',
    String rfc = 'PEXJ900101AB1',
    String nss = '12345678901',
    DateTime? fechaNacimiento,
    DateTime? fechaIngreso,
    int aniosExperienciaSeguridad = 3,
  }) {
    return crearEmpleado.ejecutar(
      nombres: nombres,
      apellidoPaterno: apellidoPaterno,
      sexo: SexoEmpleado.masculino,
      fechaNacimiento: fechaNacimiento ?? DateTime(1990, 1, 1),
      curp: curp,
      rfc: rfc,
      nss: nss,
      estadoCivil: EstadoCivilEmpleado.soltero,
      fechaIngreso: fechaIngreso ?? DateTime(2026, 1, 1),
      aniosExperienciaSeguridad: aniosExperienciaSeguridad,
    );
  }

  group('CrearEmpleadoUseCase', () {
    test('registra un Empleado con folio EMP-######', () async {
      final resultado = await crearEmpleadoDePrueba();
      expect(resultado, isA<CrearEmpleadoExitoso>());
      final empleado = (resultado as CrearEmpleadoExitoso).empleado;
      expect(empleado.codigoEmpleado, matches(RegExp(r'^EMP-\d{6}$')));
      expect(empleado.estatus, 'activo');
      expect(empleado.aniosExperienciaSeguridad, 3);

      final eventos = await empleadoRepo.listarEventos(empleado.id);
      expect(eventos, hasLength(1));
      expect(eventos.single.tipoEvento, 'creado');
    });

    test('folio se genera secuencialmente', () async {
      final primero = await crearEmpleadoDePrueba(curp: 'PEXJ900101HDFXXX01', rfc: 'PEXJ900101AB1');
      final segundo = await crearEmpleadoDePrueba(curp: 'GOMJ900101HDFXXX02', rfc: 'GOMJ900101AB2');
      expect((primero as CrearEmpleadoExitoso).empleado.codigoEmpleado, 'EMP-000001');
      expect((segundo as CrearEmpleadoExitoso).empleado.codigoEmpleado, 'EMP-000002');
    });

    test('rechaza nombres vacíos', () async {
      final resultado = await crearEmpleadoDePrueba(nombres: '   ');
      expect(resultado, isA<CrearEmpleadoNombresRequerido>());
    });

    test('rechaza CURP con formato inválido', () async {
      final resultado = await crearEmpleadoDePrueba(curp: 'CORTA');
      expect(resultado, isA<CrearEmpleadoCurpInvalido>());
    });

    test('rechaza RFC con formato inválido', () async {
      final resultado = await crearEmpleadoDePrueba(rfc: 'X');
      expect(resultado, isA<CrearEmpleadoRfcInvalido>());
    });

    test('rechaza NSS con formato inválido', () async {
      final resultado = await crearEmpleadoDePrueba(nss: '123');
      expect(resultado, isA<CrearEmpleadoNssInvalido>());
    });

    test('rechaza fecha de nacimiento futura', () async {
      final resultado = await crearEmpleadoDePrueba(fechaNacimiento: DateTime.now().add(const Duration(days: 1)));
      expect(resultado, isA<CrearEmpleadoFechaNacimientoInvalida>());
    });

    test('rechaza una edad menor a 15 años al momento de la fecha de nacimiento', () async {
      final resultado = await crearEmpleadoDePrueba(
        fechaNacimiento: DateTime.now().subtract(const Duration(days: 365 * 10)),
      );
      expect(resultado, isA<CrearEmpleadoFechaNacimientoInvalida>());
    });

    test('rechaza fecha de ingreso anterior a la edad mínima laboral', () async {
      final resultado = await crearEmpleadoDePrueba(
        fechaNacimiento: DateTime(2005, 1, 1),
        fechaIngreso: DateTime(2015, 1, 1),
      );
      // El Empleado ya es mayor de 15 hoy (nació en 2005), pero en 2015
      // (fecha de ingreso) apenas tenía 10 años.
      expect(resultado, isA<CrearEmpleadoFechaIngresoInvalida>());
    });

    test('rechaza años de experiencia negativos', () async {
      final resultado = await crearEmpleadoDePrueba(aniosExperienciaSeguridad: -1);
      expect(resultado, isA<CrearEmpleadoExperienciaInvalida>());
    });
  });

  group('CorregirEmpleadoUseCase', () {
    test('corrige metadatos administrativos pero nunca codigoEmpleado', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final resultado = await corregirEmpleado.ejecutar(
        empleadoId: empleado.id,
        telefono: '5555555555',
        motivo: 'Actualización de datos de contacto',
      );

      expect(resultado, isA<CorregirEmpleadoExitoso>());
      final actualizado = (resultado as CorregirEmpleadoExitoso).empleado;
      expect(actualizado.telefono, '5555555555');
      expect(actualizado.codigoEmpleado, empleado.codigoEmpleado);

      final eventos = await empleadoRepo.listarEventos(empleado.id);
      expect(eventos.last.tipoEvento, 'corregido');
      expect(eventos.last.observacion, 'Actualización de datos de contacto');
    });

    test('rechaza un Empleado inexistente', () async {
      final resultado = await corregirEmpleado.ejecutar(empleadoId: 'no-existe', motivo: 'x');
      expect(resultado, isA<CorregirEmpleadoNoExiste>());
    });

    test('rechaza corregir con un CURP de formato inválido', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final resultado = await corregirEmpleado.ejecutar(empleadoId: empleado.id, curp: 'X', motivo: 'x');
      expect(resultado, isA<CorregirEmpleadoCurpInvalido>());
    });
  });

  group('CambiarEstatusEmpleadoUseCase', () {
    test('da de baja a un Empleado activo y registra el evento con estados', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final resultado = await cambiarEstatusEmpleado.ejecutar(
        empleadoId: empleado.id,
        nuevo: EstatusEmpleado.baja,
        motivo: 'Renuncia',
      );

      expect(resultado, isA<CambiarEstatusEmpleadoExitoso>());
      expect((resultado as CambiarEstatusEmpleadoExitoso).empleado.estatus, 'baja');

      final eventos = await empleadoRepo.listarEventos(empleado.id);
      expect(eventos.last.tipoEvento, 'cambioEstatus');
      expect(eventos.last.estadoAnterior, 'activo');
      expect(eventos.last.estadoNuevo, 'baja');
    });

    test('rechaza cambiar a un estatus en el que ya está', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final resultado = await cambiarEstatusEmpleado.ejecutar(empleadoId: empleado.id, nuevo: EstatusEmpleado.activo);
      expect(resultado, isA<CambiarEstatusEmpleadoYaEnEseEstatus>());
    });
  });

  group('ActualizarFotografiaEmpleadoUseCase', () {
    test('crea el Attachment, mueve el puntero y archiva la fotografía anterior', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final archivo1 = '${tempDir.path}/foto1.jpg';
      File(archivo1).writeAsStringSync('contenido 1');
      final primera = await actualizarFotografia.ejecutar(
        empleadoId: empleado.id,
        sourceFilePath: archivo1,
        originalFileName: 'foto1.jpg',
        mimeType: 'image/jpeg',
      );
      expect(primera, isA<ActualizarFotografiaEmpleadoExitoso>());
      final primerAttachmentId = (primera as ActualizarFotografiaEmpleadoExitoso).empleado.fotografiaAttachmentId;
      expect(primerAttachmentId, isNotNull);

      final archivo2 = '${tempDir.path}/foto2.jpg';
      File(archivo2).writeAsStringSync('contenido 2');
      final segunda = await actualizarFotografia.ejecutar(
        empleadoId: empleado.id,
        sourceFilePath: archivo2,
        originalFileName: 'foto2.jpg',
        mimeType: 'image/jpeg',
      );
      expect(segunda, isA<ActualizarFotografiaEmpleadoExitoso>());
      final segundoAttachmentId = (segunda as ActualizarFotografiaEmpleadoExitoso).empleado.fotografiaAttachmentId;
      expect(segundoAttachmentId, isNot(primerAttachmentId));

      final anterior = await AttachmentRepository(db).obtenerPorId(primerAttachmentId!);
      expect(anterior!.estado, 'archivado', reason: 'la fotografía anterior debe archivarse, nunca borrarse');

      final activos = await AttachmentRepository(db).listarActivosPorEmpleado(empleado.id);
      expect(activos, hasLength(1));
      expect(activos.single.id, segundoAttachmentId);
    });

    test('rechaza actualizar la fotografía de un Empleado inexistente', () async {
      final resultado = await actualizarFotografia.ejecutar(
        empleadoId: 'no-existe',
        sourceFilePath: '${tempDir.path}/x.jpg',
        originalFileName: 'x.jpg',
        mimeType: 'image/jpeg',
      );
      expect(resultado, isA<ActualizarFotografiaEmpleadoNoExiste>());
    });
  });

  group('GuardarDomicilioEmpleadoUseCase', () {
    test('crea el domicilio con tipoDireccion domicilio', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final resultado = await guardarDomicilio.ejecutar(
        empleadoId: empleado.id,
        domicilio: const DireccionBorrador(
          calle: 'Calle Real',
          numeroExterior: '10',
          colonia: 'Centro',
          municipioAlcaldia: 'Toluca',
          estado: 'Estado de México',
          codigoPostal: '50000',
        ),
      );

      expect(resultado, isA<GuardarDomicilioEmpleadoExitoso>());
      final domicilio = (resultado as GuardarDomicilioEmpleadoExitoso).domicilio;
      expect(domicilio!.tipoDireccion, 'domicilio');
      expect(domicilio.empleadoId, empleado.id);
    });

    test('un domicilio incompleto es rechazado por DireccionValidator', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final resultado = await guardarDomicilio.ejecutar(
        empleadoId: empleado.id,
        domicilio: const DireccionBorrador(calle: 'Calle Real'),
      );

      expect(resultado, isA<GuardarDomicilioEmpleadoErroresValidacion>());
    });

    test('domicilio == null archiva el existente sin borrarlo', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      await guardarDomicilio.ejecutar(
        empleadoId: empleado.id,
        domicilio: const DireccionBorrador(
          calle: 'Calle Real',
          numeroExterior: '10',
          colonia: 'Centro',
          municipioAlcaldia: 'Toluca',
          estado: 'Estado de México',
          codigoPostal: '50000',
        ),
      );

      final limpiado = await guardarDomicilio.ejecutar(empleadoId: empleado.id, domicilio: null);
      expect(limpiado, isA<GuardarDomicilioEmpleadoExitoso>());
      expect((limpiado as GuardarDomicilioEmpleadoExitoso).domicilio, isNull);

      final activo = await empleadoRepo.obtenerDomicilio(empleado.id);
      expect(activo, isNull, reason: 'ya no debe verse como domicilio activo');
    });
  });

  group('AdjuntarDocumentoEmpleadoUseCase', () {
    test('adjunta un documento y registra el evento documentoAdjuntado', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final archivo = '${tempDir.path}/ine.pdf';
      File(archivo).writeAsStringSync('contenido de prueba');

      final resultado = await adjuntarDocumento.ejecutar(
        empleadoId: empleado.id,
        categoria: CategoriaDocumentoEmpleado.ine,
        sourceFilePath: archivo,
        originalFileName: 'ine.pdf',
        mimeType: 'application/pdf',
      );

      expect(resultado, isA<AdjuntarDocumentoEmpleadoExitoso>());
      final adjunto = (resultado as AdjuntarDocumentoEmpleadoExitoso).adjunto;
      expect(adjunto.categoria, 'ine');

      final documentos = await AttachmentRepository(db).listarActivosPorEmpleado(empleado.id);
      expect(documentos, hasLength(1));

      final eventos = await empleadoRepo.listarEventos(empleado.id);
      expect(eventos.last.tipoEvento, 'documentoAdjuntado');
    });

    test('rechaza adjuntar a un Empleado inexistente', () async {
      final resultado = await adjuntarDocumento.ejecutar(
        empleadoId: 'no-existe',
        categoria: CategoriaDocumentoEmpleado.otro,
        sourceFilePath: '${tempDir.path}/x.pdf',
        originalFileName: 'x.pdf',
        mimeType: 'application/pdf',
      );
      expect(resultado, isA<AdjuntarDocumentoEmpleadoNoExiste>());
    });
  });

  group('RegistrarPerfilPsicologicoUseCase', () {
    test('guarda fecha/resumen/observaciones sin PDF y registra el evento', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final resultado = await registrarPerfilPsicologico.ejecutar(
        empleadoId: empleado.id,
        fecha: DateTime(2026, 1, 15),
        resumen: 'Resumen de la evaluación',
        observaciones: 'Sin observaciones adicionales',
      );

      expect(resultado, isA<RegistrarPerfilPsicologicoExitoso>());
      final actualizado = (resultado as RegistrarPerfilPsicologicoExitoso).empleado;
      expect(actualizado.fechaEvaluacionPsicologica, DateTime(2026, 1, 15));
      expect(actualizado.resumenPsicologico, 'Resumen de la evaluación');

      final eventos = await empleadoRepo.listarEventos(empleado.id);
      expect(eventos.last.tipoEvento, 'perfilPsicologicoActualizado');
    });

    test('con PDF adjunta el documento en categoría perfilPsicologico', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final archivo = '${tempDir.path}/perfil.pdf';
      File(archivo).writeAsStringSync('contenido de prueba');

      final resultado = await registrarPerfilPsicologico.ejecutar(
        empleadoId: empleado.id,
        fecha: DateTime(2026, 1, 15),
        sourceFilePath: archivo,
        originalFileName: 'perfil.pdf',
        mimeType: 'application/pdf',
      );

      expect(resultado, isA<RegistrarPerfilPsicologicoExitoso>());
      final documentos = await AttachmentRepository(db).listarActivosPorEmpleado(empleado.id);
      expect(documentos, hasLength(1));
      expect(documentos.single.categoria, 'perfilPsicologico');
    });

    test('rechaza una fecha futura', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final resultado = await registrarPerfilPsicologico.ejecutar(
        empleadoId: empleado.id,
        fecha: DateTime.now().add(const Duration(days: 1)),
      );
      expect(resultado, isA<RegistrarPerfilPsicologicoFechaInvalida>());
    });

    test('rechaza un Empleado inexistente', () async {
      final resultado = await registrarPerfilPsicologico.ejecutar(empleadoId: 'no-existe', fecha: DateTime(2026, 1, 15));
      expect(resultado, isA<RegistrarPerfilPsicologicoNoExiste>());
    });
  });

  group('RegistrarEstudioSocioeconomicoUseCase', () {
    test('guarda fecha/resumen/observaciones y registra el evento', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final resultado = await registrarEstudioSocioeconomico.ejecutar(
        empleadoId: empleado.id,
        fecha: DateTime(2026, 1, 20),
        resumen: 'Resumen del estudio',
      );

      expect(resultado, isA<RegistrarEstudioSocioeconomicoExitoso>());
      final actualizado = (resultado as RegistrarEstudioSocioeconomicoExitoso).empleado;
      expect(actualizado.fechaEstudioSocioeconomico, DateTime(2026, 1, 20));
      expect(actualizado.resumenEstudioSocioeconomico, 'Resumen del estudio');

      final eventos = await empleadoRepo.listarEventos(empleado.id);
      expect(eventos.last.tipoEvento, 'estudioSocioeconomicoActualizado');
    });

    test('rechaza una fecha futura', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final resultado = await registrarEstudioSocioeconomico.ejecutar(
        empleadoId: empleado.id,
        fecha: DateTime.now().add(const Duration(days: 1)),
      );
      expect(resultado, isA<RegistrarEstudioSocioeconomicoFechaInvalida>());
    });

    test('rechaza un Empleado inexistente', () async {
      final resultado = await registrarEstudioSocioeconomico.ejecutar(empleadoId: 'no-existe', fecha: DateTime(2026, 1, 20));
      expect(resultado, isA<RegistrarEstudioSocioeconomicoNoExiste>());
    });
  });

  group('RegistrarAntidopingUseCase', () {
    test('guarda un resultado por sustancia y registra el evento', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final resultado = await registrarAntidoping.ejecutar(
        empleadoId: empleado.id,
        fecha: DateTime(2026, 1, 25),
        amp: ResultadoSustanciaAntidoping.negativo,
        bzd: ResultadoSustanciaAntidoping.negativo,
        coc: ResultadoSustanciaAntidoping.positivo,
        met: ResultadoSustanciaAntidoping.noAplica,
        opi: ResultadoSustanciaAntidoping.noAplica,
        observaciones: 'Panel reducido',
      );

      expect(resultado, isA<RegistrarAntidopingExitoso>());
      final actualizado = (resultado as RegistrarAntidopingExitoso).empleado;
      expect(actualizado.fechaAntidoping, DateTime(2026, 1, 25));
      expect(actualizado.resultadoAmp, 'negativo');
      expect(actualizado.resultadoCoc, 'positivo');
      expect(actualizado.resultadoMet, 'noAplica');

      final eventos = await empleadoRepo.listarEventos(empleado.id);
      expect(eventos.last.tipoEvento, 'antidopingActualizado');
    });

    test('un Antidoping capturado con todas las sustancias en noAplica no es "no realizado"', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final resultado = await registrarAntidoping.ejecutar(
        empleadoId: empleado.id,
        fecha: DateTime(2026, 1, 25),
        amp: ResultadoSustanciaAntidoping.noAplica,
        bzd: ResultadoSustanciaAntidoping.noAplica,
        coc: ResultadoSustanciaAntidoping.noAplica,
        met: ResultadoSustanciaAntidoping.noAplica,
        opi: ResultadoSustanciaAntidoping.noAplica,
      );

      final actualizado = (resultado as RegistrarAntidopingExitoso).empleado;
      expect(calcularAlertasEmpleado(actualizado).antidopingPendiente, isFalse);
    });

    test('rechaza una fecha futura', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final resultado = await registrarAntidoping.ejecutar(
        empleadoId: empleado.id,
        fecha: DateTime.now().add(const Duration(days: 1)),
        amp: ResultadoSustanciaAntidoping.noAplica,
        bzd: ResultadoSustanciaAntidoping.noAplica,
        coc: ResultadoSustanciaAntidoping.noAplica,
        met: ResultadoSustanciaAntidoping.noAplica,
        opi: ResultadoSustanciaAntidoping.noAplica,
      );
      expect(resultado, isA<RegistrarAntidopingFechaInvalida>());
    });

    test('rechaza un Empleado inexistente', () async {
      final resultado = await registrarAntidoping.ejecutar(
        empleadoId: 'no-existe',
        fecha: DateTime(2026, 1, 25),
        amp: ResultadoSustanciaAntidoping.noAplica,
        bzd: ResultadoSustanciaAntidoping.noAplica,
        coc: ResultadoSustanciaAntidoping.noAplica,
        met: ResultadoSustanciaAntidoping.noAplica,
        opi: ResultadoSustanciaAntidoping.noAplica,
      );
      expect(resultado, isA<RegistrarAntidopingNoExiste>());
    });
  });

  group('EmpleadoAlertas', () {
    test('las 3 evaluaciones nunca capturadas quedan pendientes', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final alertas = calcularAlertasEmpleado(empleado);
      expect(alertas.perfilPsicologicoPendiente, isTrue);
      expect(alertas.estudioSocioeconomicoPendiente, isTrue);
      expect(alertas.antidopingPendiente, isTrue);
      expect(alertas.tieneAlertas, isTrue);
    });

    test('capturar las 3 evaluaciones elimina todas las alertas', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      await registrarPerfilPsicologico.ejecutar(empleadoId: empleado.id, fecha: DateTime(2026, 1, 15));
      await registrarEstudioSocioeconomico.ejecutar(empleadoId: empleado.id, fecha: DateTime(2026, 1, 20));
      final ultimo = await registrarAntidoping.ejecutar(
        empleadoId: empleado.id,
        fecha: DateTime(2026, 1, 25),
        amp: ResultadoSustanciaAntidoping.negativo,
        bzd: ResultadoSustanciaAntidoping.negativo,
        coc: ResultadoSustanciaAntidoping.negativo,
        met: ResultadoSustanciaAntidoping.negativo,
        opi: ResultadoSustanciaAntidoping.negativo,
      );

      final actualizado = (ultimo as RegistrarAntidopingExitoso).empleado;
      expect(calcularAlertasEmpleado(actualizado).tieneAlertas, isFalse);
    });
  });
}
