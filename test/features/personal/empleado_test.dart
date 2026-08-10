import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_numero_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/actualizar_fotografia_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/adjuntar_documento_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/alerta_recontratacion_empleado.dart';
import 'package:riseg_one/features/personal/domain/usecases/calcular_ciclo_laboral_empleado.dart';
import 'package:riseg_one/features/personal/domain/usecases/corregir_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/crear_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/empleado_alertas.dart';
import 'package:riseg_one/features/personal/domain/usecases/empleado_validator.dart';
import 'package:riseg_one/features/personal/domain/usecases/guardar_domicilio_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_antidoping_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_baja_laboral_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_estudio_socioeconomico_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_perfil_psicologico_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_reingreso_usecase.dart';

void main() {
  late AppDatabase db;
  late EmpleadoRepositoryImpl empleadoRepo;
  late CrearEmpleadoUseCase crearEmpleado;
  late CorregirEmpleadoUseCase corregirEmpleado;
  late RegistrarBajaLaboralUseCase registrarBajaLaboral;
  late RegistrarReingresoUseCase registrarReingreso;
  late ActualizarFotografiaEmpleadoUseCase actualizarFotografia;
  late GuardarDomicilioEmpleadoUseCase guardarDomicilio;
  late AdjuntarDocumentoEmpleadoUseCase adjuntarDocumento;
  late RegistrarPerfilPsicologicoUseCase registrarPerfilPsicologico;
  late RegistrarEstudioSocioeconomicoUseCase registrarEstudioSocioeconomico;
  late RegistrarAntidopingUseCase registrarAntidoping;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final generarNumero = GenerarNumeroUseCase(CodigoSecuenciaService(db));
    const validator = EmpleadoValidator();

    crearEmpleado = CrearEmpleadoUseCase(empleadoRepo, generarNumero, validator, servicioRepo);
    corregirEmpleado = CorregirEmpleadoUseCase(empleadoRepo, validator);
    registrarBajaLaboral = RegistrarBajaLaboralUseCase(empleadoRepo, validator);
    registrarReingreso = RegistrarReingresoUseCase(empleadoRepo, validator);
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
    String? codigoPostalFiscal,
    String nss = '12345678901',
    DateTime? fechaNacimiento,
    DateTime? fechaIngreso,
    int aniosExperienciaSeguridad = 3,
    String? servicioId,
    String? sucursalId,
  }) {
    return crearEmpleado.ejecutar(
      nombres: nombres,
      apellidoPaterno: apellidoPaterno,
      sexo: SexoEmpleado.masculino,
      fechaNacimiento: fechaNacimiento ?? DateTime(1990, 1, 1),
      curp: curp,
      rfc: rfc,
      codigoPostalFiscal: codigoPostalFiscal,
      nss: nss,
      estadoCivil: EstadoCivilEmpleado.soltero,
      fechaIngreso: fechaIngreso ?? DateTime(2026, 1, 1),
      aniosExperienciaSeguridad: aniosExperienciaSeguridad,
      servicioId: servicioId,
      sucursalId: sucursalId,
    );
  }

  group('EmpleadoValidator', () {
    const validator = EmpleadoValidator();

    test('datosBancariosValidos acepta que no se capture nada', () {
      expect(validator.datosBancariosValidos(), isTrue);
    });

    test('datosBancariosValidos rechaza tarjeta/CLABE sin banco', () {
      expect(validator.datosBancariosValidos(numeroCuentaTarjeta: '1234567890123456'), isFalse);
    });

    test('datosBancariosValidos rechaza banco sin tarjeta ni CLABE', () {
      expect(validator.datosBancariosValidos(bancoId: 'banco-x'), isFalse);
    });

    test('datosBancariosValidos acepta banco + solo tarjeta, o banco + solo CLABE', () {
      expect(validator.datosBancariosValidos(bancoId: 'banco-x', numeroCuentaTarjeta: '1234567890123456'), isTrue);
      expect(validator.datosBancariosValidos(bancoId: 'banco-x', clabe: '123456789012345678'), isTrue);
    });

    test('sueldoAdministrativoValido rechaza 0 pero acepta null y valores positivos', () {
      expect(validator.sueldoAdministrativoValido(null), isTrue);
      expect(validator.sueldoAdministrativoValido(0), isFalse);
      expect(validator.sueldoAdministrativoValido(1500000), isTrue);
    });

    test('bonoAdministrativoValido acepta 0, null y valores positivos, rechaza negativos', () {
      expect(validator.bonoAdministrativoValido(null), isTrue);
      expect(validator.bonoAdministrativoValido(0), isTrue);
      expect(validator.bonoAdministrativoValido(500000), isTrue);
      expect(validator.bonoAdministrativoValido(-1), isFalse);
    });
  });

  group('CrearEmpleadoUseCase', () {
    test('registra un Empleado con numeroEmpleado numérico consecutivo', () async {
      final resultado = await crearEmpleadoDePrueba();
      expect(resultado, isA<CrearEmpleadoExitoso>());
      final empleado = (resultado as CrearEmpleadoExitoso).empleado;
      expect(empleado.numeroEmpleado, 1);
      expect(empleado.estatus, 'activo');
      expect(empleado.aniosExperienciaSeguridad, 3);

      final eventos = await empleadoRepo.listarEventos(empleado.id);
      expect(eventos, hasLength(1));
      expect(eventos.single.tipoEvento, 'creado');
    });

    test('numeroEmpleado se genera secuencialmente, empezando en 1', () async {
      final primero = await crearEmpleadoDePrueba(curp: 'PEXJ900101HDFXXX01', rfc: 'PEXJ900101AB1');
      final segundo = await crearEmpleadoDePrueba(curp: 'GOMJ900101HDFXXX02', rfc: 'GOMJ900101AB2');
      expect((primero as CrearEmpleadoExitoso).empleado.numeroEmpleado, 1);
      expect((segundo as CrearEmpleadoExitoso).empleado.numeroEmpleado, 2);
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

    test('rechaza un código postal fiscal con formato inválido', () async {
      final resultado = await crearEmpleadoDePrueba(codigoPostalFiscal: 'ABC');
      expect(resultado, isA<CrearEmpleadoCodigoPostalFiscalInvalido>());
    });

    test('acepta un código postal fiscal válido, independiente del domicilio', () async {
      final resultado = await crearEmpleadoDePrueba(codigoPostalFiscal: '50000');
      expect(resultado, isA<CrearEmpleadoExitoso>());
      expect((resultado as CrearEmpleadoExitoso).empleado.codigoPostalFiscal, '50000');
    });

    test('rechaza adscripción ambigua (Servicio y Sucursal a la vez)', () async {
      final resultado = await crearEmpleadoDePrueba(servicioId: 'servicio-cualquiera', sucursalId: 'sucursal-cualquiera');
      expect(resultado, isA<CrearEmpleadoAdscripcionAmbigua>());
    });

    test('rechaza una adscripción a un Servicio inexistente', () async {
      final resultado = await crearEmpleadoDePrueba(servicioId: 'servicio-inexistente');
      expect(resultado, isA<CrearEmpleadoServicioNoExiste>());
    });

    test('acepta datos bancarios completos y los persiste', () async {
      final resultado = await crearEmpleado.ejecutar(
        nombres: 'Juan',
        apellidoPaterno: 'Pérez',
        sexo: SexoEmpleado.masculino,
        fechaNacimiento: DateTime(1990, 1, 1),
        curp: 'PEXJ900101HDFXXX01',
        rfc: 'PEXJ900101AB1',
        nss: '12345678901',
        estadoCivil: EstadoCivilEmpleado.soltero,
        fechaIngreso: DateTime(2026, 1, 1),
        aniosExperienciaSeguridad: 3,
        bancoId: SeedIds.bancoBbva,
        clabe: '123456789012345678',
      );
      expect(resultado, isA<CrearEmpleadoExitoso>());
      final empleado = (resultado as CrearEmpleadoExitoso).empleado;
      expect(empleado.bancoId, SeedIds.bancoBbva);
      expect(empleado.clabe, '123456789012345678');
    });

    test('rechaza datos bancarios incompletos (tarjeta/CLABE sin banco)', () async {
      final resultado = await crearEmpleado.ejecutar(
        nombres: 'Juan',
        apellidoPaterno: 'Pérez',
        sexo: SexoEmpleado.masculino,
        fechaNacimiento: DateTime(1990, 1, 1),
        curp: 'PEXJ900101HDFXXX01',
        rfc: 'PEXJ900101AB1',
        nss: '12345678901',
        estadoCivil: EstadoCivilEmpleado.soltero,
        fechaIngreso: DateTime(2026, 1, 1),
        aniosExperienciaSeguridad: 3,
        clabe: '123456789012345678',
      );
      expect(resultado, isA<CrearEmpleadoDatosBancariosInvalidos>());
    });

    test('rechaza sueldoMensualAdministrativo = 0 pero acepta bonoMensualAdministrativo = 0', () async {
      final conSueldoCero = await crearEmpleado.ejecutar(
        nombres: 'Juan',
        apellidoPaterno: 'Pérez',
        sexo: SexoEmpleado.masculino,
        fechaNacimiento: DateTime(1990, 1, 1),
        curp: 'PEXJ900101HDFXXX01',
        rfc: 'PEXJ900101AB1',
        nss: '12345678901',
        estadoCivil: EstadoCivilEmpleado.soltero,
        fechaIngreso: DateTime(2026, 1, 1),
        aniosExperienciaSeguridad: 3,
        sueldoMensualAdministrativo: 0,
      );
      expect(conSueldoCero, isA<CrearEmpleadoSueldoAdministrativoInvalido>());

      final conBonoCero = await crearEmpleado.ejecutar(
        nombres: 'Juan',
        apellidoPaterno: 'Pérez',
        sexo: SexoEmpleado.masculino,
        fechaNacimiento: DateTime(1990, 1, 1),
        curp: 'PEXJ900101HDFXXX01',
        rfc: 'PEXJ900101AB1',
        nss: '12345678901',
        estadoCivil: EstadoCivilEmpleado.soltero,
        fechaIngreso: DateTime(2026, 1, 1),
        aniosExperienciaSeguridad: 3,
        sueldoMensualAdministrativo: 1500000,
        bonoMensualAdministrativo: 0,
      );
      expect(conBonoCero, isA<CrearEmpleadoExitoso>());
      final empleado = (conBonoCero as CrearEmpleadoExitoso).empleado;
      expect(empleado.sueldoMensualAdministrativo, 1500000);
      expect(empleado.bonoMensualAdministrativo, 0);
    });
  });

  group('CorregirEmpleadoUseCase', () {
    test('corrige metadatos administrativos pero nunca numeroEmpleado', () async {
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
      expect(actualizado.numeroEmpleado, empleado.numeroEmpleado);

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

    test('acepta y persiste datos bancarios completos', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final resultado = await corregirEmpleado.ejecutar(
        empleadoId: empleado.id,
        bancoId: SeedIds.bancoBbva,
        numeroCuentaTarjeta: '1234567890123456',
        motivo: 'Captura de datos bancarios',
      );

      expect(resultado, isA<CorregirEmpleadoExitoso>());
      final actualizado = (resultado as CorregirEmpleadoExitoso).empleado;
      expect(actualizado.bancoId, SeedIds.bancoBbva);
      expect(actualizado.numeroCuentaTarjeta, '1234567890123456');
    });

    test('rechaza datos bancarios incompletos (banco sin tarjeta ni CLABE)', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final resultado = await corregirEmpleado.ejecutar(
        empleadoId: empleado.id,
        bancoId: SeedIds.bancoBbva,
        motivo: 'x',
      );
      expect(resultado, isA<CorregirEmpleadoDatosBancariosInvalidos>());
    });

    test('rechaza sueldoMensualAdministrativo = 0 pero acepta bonoMensualAdministrativo = 0', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final conSueldoCero = await corregirEmpleado.ejecutar(
        empleadoId: empleado.id,
        sueldoMensualAdministrativo: 0,
        motivo: 'x',
      );
      expect(conSueldoCero, isA<CorregirEmpleadoSueldoAdministrativoInvalido>());

      final conBonoCero = await corregirEmpleado.ejecutar(
        empleadoId: empleado.id,
        sueldoMensualAdministrativo: 1500000,
        bonoMensualAdministrativo: 0,
        motivo: 'x',
      );
      expect(conBonoCero, isA<CorregirEmpleadoExitoso>());
      final actualizado = (conBonoCero as CorregirEmpleadoExitoso).empleado;
      expect(actualizado.sueldoMensualAdministrativo, 1500000);
      expect(actualizado.bonoMensualAdministrativo, 0);
    });

    test('limpiarBanco/limpiarClabe/limpiarNumeroCuentaTarjeta borran los datos bancarios previos', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;
      await corregirEmpleado.ejecutar(
        empleadoId: empleado.id,
        bancoId: SeedIds.bancoBbva,
        clabe: '123456789012345678',
        motivo: 'x',
      );

      final resultado = await corregirEmpleado.ejecutar(
        empleadoId: empleado.id,
        limpiarBanco: true,
        limpiarClabe: true,
        motivo: 'x',
      );

      expect(resultado, isA<CorregirEmpleadoExitoso>());
      final actualizado = (resultado as CorregirEmpleadoExitoso).empleado;
      expect(actualizado.bancoId, isNull);
      expect(actualizado.clabe, isNull);
    });
  });

  group('RegistrarBajaLaboralUseCase', () {
    test('cierra el periodo vigente y registra el evento bajaLaboral', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final resultado = await registrarBajaLaboral.ejecutar(
        empleadoId: empleado.id,
        fechaBaja: DateTime(2026, 6, 15),
        motivo: MotivoBajaEmpleado.renuncia,
      );

      expect(resultado, isA<RegistrarBajaLaboralExitoso>());
      final actualizado = (resultado as RegistrarBajaLaboralExitoso).empleado;
      expect(actualizado.estatus, 'baja');
      expect(actualizado.fechaBaja, DateTime(2026, 6, 15));
      expect(actualizado.motivoBaja, 'renuncia');

      final eventos = await empleadoRepo.listarEventos(empleado.id);
      expect(eventos.last.tipoEvento, 'bajaLaboral');
      expect(eventos.last.estadoAnterior, 'activo');
      expect(eventos.last.estadoNuevo, 'baja');

      // No debe archivar nada todavía — el periodo cerrado solo se
      // archiva en EmpleadoPeriodoLaboral al momento del Reingreso.
      final archivados = await empleadoRepo.listarPeriodosLaboralesArchivados(empleado.id);
      expect(archivados, isEmpty);
    });

    test('exige observaciones cuando el motivo es "otro"', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final resultado = await registrarBajaLaboral.ejecutar(
        empleadoId: empleado.id,
        fechaBaja: DateTime(2026, 6, 15),
        motivo: MotivoBajaEmpleado.otro,
      );
      expect(resultado, isA<RegistrarBajaLaboralObservacionesRequeridas>());

      final conObservaciones = await registrarBajaLaboral.ejecutar(
        empleadoId: empleado.id,
        fechaBaja: DateTime(2026, 6, 15),
        motivo: MotivoBajaEmpleado.otro,
        observaciones: 'Detalle del motivo',
      );
      expect(conObservaciones, isA<RegistrarBajaLaboralExitoso>());
    });

    test('rechaza dar de baja a un Empleado que ya está de baja', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;
      await registrarBajaLaboral.ejecutar(
        empleadoId: empleado.id,
        fechaBaja: DateTime(2026, 6, 15),
        motivo: MotivoBajaEmpleado.renuncia,
      );

      final resultado = await registrarBajaLaboral.ejecutar(
        empleadoId: empleado.id,
        fechaBaja: DateTime(2026, 6, 20),
        motivo: MotivoBajaEmpleado.renuncia,
      );
      expect(resultado, isA<RegistrarBajaLaboralYaDeBaja>());
    });

    test('rechaza una fecha de baja anterior al ingreso', () async {
      final creado = await crearEmpleadoDePrueba(fechaIngreso: DateTime(2026, 1, 1));
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final resultado = await registrarBajaLaboral.ejecutar(
        empleadoId: empleado.id,
        fechaBaja: DateTime(2025, 12, 31),
        motivo: MotivoBajaEmpleado.renuncia,
      );
      expect(resultado, isA<RegistrarBajaLaboralFechaInvalida>());
    });

    test('rechaza un Empleado inexistente', () async {
      final resultado = await registrarBajaLaboral.ejecutar(
        empleadoId: 'no-existe',
        fechaBaja: DateTime(2026, 6, 15),
        motivo: MotivoBajaEmpleado.renuncia,
      );
      expect(resultado, isA<RegistrarBajaLaboralNoExiste>());
    });
  });

  group('RegistrarReingresoUseCase', () {
    Future<EmpleadoData> crearYDarDeBaja({MotivoBajaEmpleado motivo = MotivoBajaEmpleado.renuncia}) async {
      final creado = await crearEmpleadoDePrueba(fechaIngreso: DateTime(2026, 1, 1));
      final empleado = (creado as CrearEmpleadoExitoso).empleado;
      final baja = await registrarBajaLaboral.ejecutar(
        empleadoId: empleado.id,
        fechaBaja: DateTime(2026, 6, 15),
        motivo: motivo,
      );
      return (baja as RegistrarBajaLaboralExitoso).empleado;
    }

    test('archiva el periodo cerrado, inicia uno nuevo y no crea un Empleado nuevo', () async {
      final empleado = await crearYDarDeBaja();

      final resultado = await registrarReingreso.ejecutar(empleadoId: empleado.id, fechaIngreso: DateTime(2026, 7, 1));

      expect(resultado, isA<RegistrarReingresoExitoso>());
      final actualizado = (resultado as RegistrarReingresoExitoso).empleado;
      expect(actualizado.id, empleado.id, reason: 'nunca debe crear un Empleado nuevo');
      expect(actualizado.numeroEmpleado, empleado.numeroEmpleado);
      expect(actualizado.estatus, 'activo');
      expect(actualizado.fechaIngreso, DateTime(2026, 7, 1));
      expect(actualizado.fechaBaja, isNull);
      expect(actualizado.motivoBaja, isNull);

      final archivados = await empleadoRepo.listarPeriodosLaboralesArchivados(empleado.id);
      expect(archivados, hasLength(1));
      expect(archivados.single.fechaIngreso, DateTime(2026, 1, 1));
      expect(archivados.single.fechaBaja, DateTime(2026, 6, 15));
      expect(archivados.single.motivoBaja, 'renuncia');

      final eventos = await empleadoRepo.listarEventos(empleado.id);
      expect(eventos.last.tipoEvento, 'reingreso');
    });

    test('la antigüedad del nuevo periodo nunca acumula el periodo anterior', () async {
      final empleado = await crearYDarDeBaja();
      final reingreso = await registrarReingreso.ejecutar(empleadoId: empleado.id, fechaIngreso: DateTime(2026, 7, 1));
      final actualizado = (reingreso as RegistrarReingresoExitoso).empleado;

      final ciclo = calcularCicloLaboralEmpleado(actualizado, hoy: DateTime(2026, 7, 15));
      expect(ciclo.diasLaborados, 14, reason: 'solo cuenta desde el nuevo ingreso, nunca desde el periodo anterior');
    });

    test('conserva expediente/documentación/evaluaciones/historial administrativo', () async {
      final empleado = await crearYDarDeBaja();
      await registrarPerfilPsicologico.ejecutar(empleadoId: empleado.id, fecha: DateTime(2026, 3, 1));

      final reingreso = await registrarReingreso.ejecutar(empleadoId: empleado.id, fechaIngreso: DateTime(2026, 7, 1));
      final actualizado = (reingreso as RegistrarReingresoExitoso).empleado;

      expect(actualizado.curp, empleado.curp);
      expect(actualizado.fechaEvaluacionPsicologica, DateTime(2026, 3, 1), reason: 'las evaluaciones no se borran en un reingreso');

      final eventos = await empleadoRepo.listarEventos(empleado.id);
      expect(eventos.map((e) => e.tipoEvento), containsAll(['creado', 'bajaLaboral', 'perfilPsicologicoActualizado', 'reingreso']));
    });

    test('rechaza reingresar a un Empleado que sigue activo', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final resultado = await registrarReingreso.ejecutar(empleadoId: empleado.id, fechaIngreso: DateTime(2026, 7, 1));
      expect(resultado, isA<RegistrarReingresoNoEstaDeBaja>());
    });

    test('rechaza una fecha de reingreso anterior a la baja anterior', () async {
      final empleado = await crearYDarDeBaja();

      final resultado = await registrarReingreso.ejecutar(empleadoId: empleado.id, fechaIngreso: DateTime(2026, 6, 1));
      expect(resultado, isA<RegistrarReingresoFechaInvalida>());
    });

    test('rechaza un Empleado inexistente', () async {
      final resultado = await registrarReingreso.ejecutar(empleadoId: 'no-existe', fechaIngreso: DateTime(2026, 7, 1));
      expect(resultado, isA<RegistrarReingresoNoExiste>());
    });

    test('un numeroEmpleado utilizado nunca vuelve a asignarse: la baja no lo libera', () async {
      final primero = (await crearEmpleadoDePrueba(curp: 'PEXJ900101HDFXXX01', rfc: 'PEXJ900101AB1') as CrearEmpleadoExitoso)
          .empleado;
      final segundo = await crearYDarDeBaja(); // numeroEmpleado 2, ahora de baja
      expect(segundo.numeroEmpleado, 2);

      final reingreso = await registrarReingreso.ejecutar(empleadoId: segundo.id, fechaIngreso: DateTime(2026, 7, 1));
      final reingresado = (reingreso as RegistrarReingresoExitoso).empleado;
      expect(reingresado.numeroEmpleado, 2, reason: 'el reingreso conserva el mismo número, nunca genera uno nuevo');

      final tercero = await crearEmpleadoDePrueba(curp: 'GOMJ900101HDFXXX02', rfc: 'GOMJ900101AB2');
      expect(
        (tercero as CrearEmpleadoExitoso).empleado.numeroEmpleado,
        3,
        reason: 'la secuencia sigue avanzando; el número 2 nunca se reutiliza para un Empleado distinto',
      );
      expect(primero.numeroEmpleado, 1);
    });
  });

  group('calcularCicloLaboralEmpleado', () {
    test('antigüedad y días laborados se calculan sobre el periodo vigente activo', () async {
      final creado = await crearEmpleadoDePrueba(fechaIngreso: DateTime(2024, 1, 1));
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final ciclo = calcularCicloLaboralEmpleado(empleado, hoy: DateTime(2026, 6, 1));
      expect(ciclo.antiguedadAnios, 2);
      expect(ciclo.antiguedadMeses, 5);
      expect(ciclo.fechaProximoAniversario, DateTime(2027, 1, 1));
    });

    test('un Empleado de baja calcula hasta fechaBaja, no hasta hoy, y sin próximo aniversario', () async {
      final creado = await crearEmpleadoDePrueba(fechaIngreso: DateTime(2024, 1, 1));
      final empleado = (creado as CrearEmpleadoExitoso).empleado;
      final baja = await registrarBajaLaboral.ejecutar(
        empleadoId: empleado.id,
        fechaBaja: DateTime(2025, 1, 1),
        motivo: MotivoBajaEmpleado.renuncia,
      );
      final actualizado = (baja as RegistrarBajaLaboralExitoso).empleado;

      final ciclo = calcularCicloLaboralEmpleado(actualizado, hoy: DateTime(2026, 6, 1));
      expect(ciclo.antiguedadAnios, 1);
      expect(ciclo.antiguedadMeses, 0);
      expect(ciclo.fechaProximoAniversario, isNull);
    });
  });

  group('calcularAlertaRecontratacion', () {
    test('sin bajas previas no hay advertencia', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;

      final alerta = calcularAlertaRecontratacion(empleado, const []);
      expect(alerta.tieneAdvertencia, isFalse);
    });

    test('un motivo que genera advertencia (p. ej. robo) en el periodo vigente cerrado sí advierte', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;
      final baja = await registrarBajaLaboral.ejecutar(
        empleadoId: empleado.id,
        fechaBaja: DateTime(2026, 6, 15),
        motivo: MotivoBajaEmpleado.robo,
      );
      final actualizado = (baja as RegistrarBajaLaboralExitoso).empleado;

      final alerta = calcularAlertaRecontratacion(actualizado, const []);
      expect(alerta.tieneAdvertencia, isTrue);
      expect(alerta.motivos, contains(MotivoBajaEmpleado.robo));
    });

    test('un motivo neutro (renuncia) no genera advertencia', () async {
      final creado = await crearEmpleadoDePrueba();
      final empleado = (creado as CrearEmpleadoExitoso).empleado;
      final baja = await registrarBajaLaboral.ejecutar(
        empleadoId: empleado.id,
        fechaBaja: DateTime(2026, 6, 15),
        motivo: MotivoBajaEmpleado.renuncia,
      );
      final actualizado = (baja as RegistrarBajaLaboralExitoso).empleado;

      final alerta = calcularAlertaRecontratacion(actualizado, const []);
      expect(alerta.tieneAdvertencia, isFalse);
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
