import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/asignacion_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_equipo_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/recarga_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/tables/linea_telefonica_table.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/adjuntar_comprobante_recarga_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/asignar_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/cambiar_asignacion_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/cambiar_estatus_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/crear_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/dar_de_baja_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/registrar_recarga_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';
import 'package:drift/drift.dart' show Value;

/// Cubre Recargas de Telefonía (Etapa 9C) — operación prepago,
/// deliberadamente mínima: fecha, importe, observaciones opcionales,
/// comprobante opcional. Sin Egreso automático. Cubre también el punto
/// más importante de 9C: la derivación histórica de a quién
/// correspondía una línea el día de una recarga, sin snapshot
/// redundante (ver el doc comment de `DestinoHistoricoRecarga`).
const _cuentaRecargaDePrueba = 'cuenta-recarga-de-prueba';

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late LineaTelefonicaRepositoryImpl lineaRepo;
  late AsignacionLineaTelefonicaRepositoryImpl asignacionLineaRepo;
  late RecargaLineaTelefonicaRepositoryImpl recargaRepo;
  late CrearLineaTelefonicaUseCase crearLinea;
  late DarDeBajaLineaTelefonicaUseCase darDeBaja;
  late CambiarEstatusLineaTelefonicaUseCase cambiarEstatus;
  late AsignarLineaTelefonicaUseCase asignarLinea;
  late CambiarAsignacionLineaTelefonicaUseCase cambiarAsignacion;
  late RegistrarRecargaLineaTelefonicaUseCase registrarRecarga;
  late AdjuntarComprobanteRecargaLineaTelefonicaUseCase adjuntarComprobante;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // Cuenta REAL para las recargas: el dominio exige saber de dónde
    // salió el dinero de una recarga nueva.
    await db.into(db.cuentaFinanciera).insert(
          CuentaFinancieraCompanion.insert(
            id: const Value(_cuentaRecargaDePrueba),
            codigo: 'CTA-REC',
            nombre: 'BBVA Empresarial',
            tipo: TipoCuentaFinanciera.banco.name,
            saldoInicial: 100000000,
            fechaSaldoInicial: DateTime(2026, 1, 1),
          ),
        );
    tempDir = Directory.systemTemp.createTempSync('riseg_recarga_linea_telefonica_test_');
    asignacionLineaRepo = AsignacionLineaTelefonicaRepositoryImpl(db);
    final equipoRepo = LineaTelefonicaEquipoRepositoryImpl(db, asignacionLineaRepo, AsignacionRepositoryImpl(db));
    lineaRepo = LineaTelefonicaRepositoryImpl(db, asignacionLineaRepo, equipoRepo);
    recargaRepo = RecargaLineaTelefonicaRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db));
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    crearLinea = CrearLineaTelefonicaUseCase(lineaRepo, generarCodigo);
    darDeBaja = DarDeBajaLineaTelefonicaUseCase(lineaRepo);
    cambiarEstatus = CambiarEstatusLineaTelefonicaUseCase(lineaRepo);
    asignarLinea = AsignarLineaTelefonicaUseCase(lineaRepo, asignacionLineaRepo, equipoRepo);
    cambiarAsignacion = CambiarAsignacionLineaTelefonicaUseCase(asignacionLineaRepo, equipoRepo, lineaRepo);
    registrarRecarga = RegistrarRecargaLineaTelefonicaUseCase(recargaRepo, lineaRepo, DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)));
    adjuntarComprobante = AdjuntarComprobanteRecargaLineaTelefonicaUseCase(recargaRepo, AttachmentStorage(tempDir.path));
  });

  tearDown(() {
    db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<LineaTelefonicaData> crearLineaDePrueba({String? numero}) async {
    final resultado = await crearLinea.ejecutar(numero: numero, operador: 'telcel', modalidadSim: 'fisica');
    return (resultado as CrearLineaTelefonicaExitoso).linea;
  }

  Future<EmpleadoData> crearEmpleadoDePrueba({int numeroEmpleado = 1}) {
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: numeroEmpleado,
            nombres: 'Juan',
            apellidoPaterno: 'Pérez',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX0$numeroEmpleado',
            rfc: 'PEXJ900101AB$numeroEmpleado',
            nss: '1234567890$numeroEmpleado',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
  }

  Future<ServicioData> crearServicioDePrueba({String codigo = 'SER-000001'}) async {
    final tipoServicio = await db
        .into(db.tipoServicio)
        .insertReturning(TipoServicioCompanion.insert(id: 'tipo-servicio-$codigo', codigo: 'VIGILANCIA_FIJA', nombre: 'Vigilancia fija'));
    final cliente =
        await db.into(db.cliente).insertReturning(ClienteCompanion.insert(codigo: 'CLI-$codigo', nombreComercial: 'Sportium'));
    return db.into(db.servicio).insertReturning(
          ServicioCompanion.insert(
            codigo: codigo,
            clienteId: cliente.id,
            nombre: 'Vigilancia Sportium Toluca',
            tipoServicioId: tipoServicio.id,
            fechaInicio: DateTime(2026, 1, 1),
          ),
        );
  }

  group('RegistrarRecargaLineaTelefonicaUseCase', () {
    test('registra una recarga', () async {
      final linea = await crearLineaDePrueba();

      final resultado = await registrarRecarga.ejecutar(
        lineaTelefonicaId: linea.id,
        fecha: DateTime(2026, 8, 5),
        importe: 20000,
        observaciones: 'Recarga mensual',
        formaPago: FormaPago.efectivo.name,
        cuentaFinancieraId: _cuentaRecargaDePrueba,
      );

      expect(resultado, isA<RegistrarRecargaLineaTelefonicaExitoso>());
      final recarga = (resultado as RegistrarRecargaLineaTelefonicaExitoso).recarga;
      expect(recarga.importe, 20000);
      expect(recarga.fecha, DateTime(2026, 8, 5));
      expect(recarga.observaciones, 'Recarga mensual');
    });

    test('observaciones son opcionales', () async {
      final linea = await crearLineaDePrueba();
      final resultado = await registrarRecarga.ejecutar(lineaTelefonicaId: linea.id, fecha: DateTime(2026, 8, 5), importe: 20000, formaPago: FormaPago.efectivo.name, cuentaFinancieraId: _cuentaRecargaDePrueba);
      expect(resultado, isA<RegistrarRecargaLineaTelefonicaExitoso>());
      expect((resultado as RegistrarRecargaLineaTelefonicaExitoso).recarga.observaciones, isNull);
    });

    test('rechaza importe cero o negativo', () async {
      final linea = await crearLineaDePrueba();

      final cero = await registrarRecarga.ejecutar(lineaTelefonicaId: linea.id, fecha: DateTime(2026, 8, 5), importe: 0, formaPago: FormaPago.efectivo.name, cuentaFinancieraId: _cuentaRecargaDePrueba);
      expect(cero, isA<RegistrarRecargaLineaTelefonicaImporteInvalido>());

      final negativo = await registrarRecarga.ejecutar(lineaTelefonicaId: linea.id, fecha: DateTime(2026, 8, 5), importe: -100, formaPago: FormaPago.efectivo.name, cuentaFinancieraId: _cuentaRecargaDePrueba);
      expect(negativo, isA<RegistrarRecargaLineaTelefonicaImporteInvalido>());
    });

    test('rechaza línea que no existe', () async {
      final resultado = await registrarRecarga.ejecutar(lineaTelefonicaId: 'no-existe', fecha: DateTime(2026, 8, 5), importe: 20000, formaPago: FormaPago.efectivo.name, cuentaFinancieraId: _cuentaRecargaDePrueba);
      expect(resultado, isA<RegistrarRecargaLineaTelefonicaLineaNoExiste>());
    });

    test('rechaza recarga a una línea dada de baja', () async {
      final linea = await crearLineaDePrueba();
      await darDeBaja.ejecutar(lineaTelefonicaId: linea.id, fechaBaja: DateTime(2026, 1, 1), motivoBaja: MotivoBajaLineaTelefonica.cancelacion);

      final resultado = await registrarRecarga.ejecutar(lineaTelefonicaId: linea.id, fecha: DateTime(2026, 8, 5), importe: 20000, formaPago: FormaPago.efectivo.name, cuentaFinancieraId: _cuentaRecargaDePrueba);
      expect(resultado, isA<RegistrarRecargaLineaTelefonicaLineaDeBaja>());
    });

    test(
      'permite recarga a una línea suspendida — recargar es, en la operación real, la acción que reactiva una línea suspendida',
      () async {
        final linea = await crearLineaDePrueba();
        await cambiarEstatus.ejecutar(lineaTelefonicaId: linea.id, estatus: 'suspendida');

        final resultado = await registrarRecarga.ejecutar(lineaTelefonicaId: linea.id, fecha: DateTime(2026, 8, 5), importe: 20000, formaPago: FormaPago.efectivo.name, cuentaFinancieraId: _cuentaRecargaDePrueba);
        expect(resultado, isA<RegistrarRecargaLineaTelefonicaExitoso>());
      },
    );
  });

  group('Historial, última recarga y totales', () {
    test('histórico ordenado descendente por fecha, la primera es la última recarga', () async {
      final linea = await crearLineaDePrueba();
      await registrarRecarga.ejecutar(lineaTelefonicaId: linea.id, fecha: DateTime(2026, 6, 2), importe: 15000, formaPago: FormaPago.efectivo.name, cuentaFinancieraId: _cuentaRecargaDePrueba);
      await registrarRecarga.ejecutar(lineaTelefonicaId: linea.id, fecha: DateTime(2026, 8, 5), importe: 20000, formaPago: FormaPago.efectivo.name, cuentaFinancieraId: _cuentaRecargaDePrueba);
      await registrarRecarga.ejecutar(lineaTelefonicaId: linea.id, fecha: DateTime(2026, 7, 3), importe: 20000, formaPago: FormaPago.efectivo.name, cuentaFinancieraId: _cuentaRecargaDePrueba);

      final historial = await recargaRepo.listarPorLinea(linea.id);
      expect(historial.map((r) => r.fecha), [DateTime(2026, 8, 5), DateTime(2026, 7, 3), DateTime(2026, 6, 2)]);
      expect(historial.first.importe, 20000, reason: '"última recarga" es siempre la primera del historial');
    });

    test('total por línea suma todas las recargas registradas', () async {
      final linea = await crearLineaDePrueba();
      await registrarRecarga.ejecutar(lineaTelefonicaId: linea.id, fecha: DateTime(2026, 6, 2), importe: 15000, formaPago: FormaPago.efectivo.name, cuentaFinancieraId: _cuentaRecargaDePrueba);
      await registrarRecarga.ejecutar(lineaTelefonicaId: linea.id, fecha: DateTime(2026, 7, 3), importe: 20000, formaPago: FormaPago.efectivo.name, cuentaFinancieraId: _cuentaRecargaDePrueba);

      expect(await recargaRepo.totalPorLinea(linea.id), 35000);
    });

    test('obtenerUltimasPorTodasLasLineas resuelve la más reciente de cada línea en una sola consulta', () async {
      final lineaA = await crearLineaDePrueba(numero: '7221111111');
      final lineaB = await crearLineaDePrueba(numero: '7222222222');
      await registrarRecarga.ejecutar(lineaTelefonicaId: lineaA.id, fecha: DateTime(2026, 6, 2), importe: 15000, formaPago: FormaPago.efectivo.name, cuentaFinancieraId: _cuentaRecargaDePrueba);
      await registrarRecarga.ejecutar(lineaTelefonicaId: lineaA.id, fecha: DateTime(2026, 8, 5), importe: 20000, formaPago: FormaPago.efectivo.name, cuentaFinancieraId: _cuentaRecargaDePrueba);
      await registrarRecarga.ejecutar(lineaTelefonicaId: lineaB.id, fecha: DateTime(2026, 7, 3), importe: 10000, formaPago: FormaPago.efectivo.name, cuentaFinancieraId: _cuentaRecargaDePrueba);

      final ultimas = await recargaRepo.obtenerUltimasPorTodasLasLineas();
      expect(ultimas[lineaA.id]!.fecha, DateTime(2026, 8, 5));
      expect(ultimas[lineaB.id]!.fecha, DateTime(2026, 7, 3));
    });

    test('total por rango de fechas', () async {
      final linea = await crearLineaDePrueba();
      await registrarRecarga.ejecutar(lineaTelefonicaId: linea.id, fecha: DateTime(2026, 5, 1), importe: 10000, formaPago: FormaPago.efectivo.name, cuentaFinancieraId: _cuentaRecargaDePrueba);
      await registrarRecarga.ejecutar(lineaTelefonicaId: linea.id, fecha: DateTime(2026, 6, 15), importe: 20000, formaPago: FormaPago.efectivo.name, cuentaFinancieraId: _cuentaRecargaDePrueba);
      await registrarRecarga.ejecutar(lineaTelefonicaId: linea.id, fecha: DateTime(2026, 7, 1), importe: 15000, formaPago: FormaPago.efectivo.name, cuentaFinancieraId: _cuentaRecargaDePrueba);

      final total = await recargaRepo.totalPorRango(desde: DateTime(2026, 6, 1), hasta: DateTime(2026, 6, 30));
      expect(total, 20000);
    });
  });

  group('Trazabilidad histórica (punto 3 de 9C — derivación, sin snapshot)', () {
    test('total por Empleado usa a quién correspondía la línea el día de cada recarga', () async {
      final linea = await crearLineaDePrueba();
      final empleado1 = await crearEmpleadoDePrueba(numeroEmpleado: 1);
      final empleado2 = await crearEmpleadoDePrueba(numeroEmpleado: 2);

      final asignacion1 = ((await asignarLinea.ejecutar(
        lineaTelefonicaId: linea.id,
        empleadoId: empleado1.id,
        fechaInicio: DateTime(2026, 1, 1),
      )) as AsignarLineaTelefonicaExitoso)
          .asignacion;
      await registrarRecarga.ejecutar(lineaTelefonicaId: linea.id, fecha: DateTime(2026, 2, 1), importe: 20000, formaPago: FormaPago.efectivo.name, cuentaFinancieraId: _cuentaRecargaDePrueba);

      await cambiarAsignacion.ejecutar(
        asignacionLineaTelefonicaActualId: asignacion1.id,
        fecha: DateTime(2026, 6, 1),
        nuevoEmpleadoId: empleado2.id,
      );
      await registrarRecarga.ejecutar(lineaTelefonicaId: linea.id, fecha: DateTime(2026, 7, 1), importe: 15000, formaPago: FormaPago.efectivo.name, cuentaFinancieraId: _cuentaRecargaDePrueba);

      expect(await recargaRepo.totalPorEmpleado(empleado1.id), 20000);
      expect(await recargaRepo.totalPorEmpleado(empleado2.id), 15000);
    });

    test('cambio posterior de asignación no reescribe a quién correspondió una recarga ya registrada', () async {
      final linea = await crearLineaDePrueba();
      final empleado1 = await crearEmpleadoDePrueba(numeroEmpleado: 1);
      final servicio = await crearServicioDePrueba();

      final asignacion1 = ((await asignarLinea.ejecutar(
        lineaTelefonicaId: linea.id,
        empleadoId: empleado1.id,
        fechaInicio: DateTime(2026, 1, 1),
      )) as AsignarLineaTelefonicaExitoso)
          .asignacion;
      final recargaExitosa = (await registrarRecarga.ejecutar(
        lineaTelefonicaId: linea.id,
        fecha: DateTime(2026, 2, 1),
        importe: 20000,
        formaPago: FormaPago.efectivo.name,
        cuentaFinancieraId: _cuentaRecargaDePrueba,
      )) as RegistrarRecargaLineaTelefonicaExitoso;

      // La línea cambia de responsable DESPUÉS de que la recarga ya fue
      // registrada — la atribución histórica de esa recarga concreta no
      // debe moverse al nuevo responsable.
      await cambiarAsignacion.ejecutar(
        asignacionLineaTelefonicaActualId: asignacion1.id,
        fecha: DateTime(2026, 6, 1),
        nuevoServicioId: servicio.id,
      );

      final destino = await recargaRepo.obtenerDestinoHistorico(recargaExitosa.recarga.id);
      expect(destino!.empleadoId, empleado1.id, reason: 'la recarga siguió correspondiendo a empleado1 en el momento en que se hizo');
      expect(destino.servicioId, isNull);
    });

    test('total por Servicio', () async {
      final linea = await crearLineaDePrueba();
      final servicio = await crearServicioDePrueba();
      await asignarLinea.ejecutar(lineaTelefonicaId: linea.id, servicioId: servicio.id, fechaInicio: DateTime(2026, 1, 1));
      await registrarRecarga.ejecutar(lineaTelefonicaId: linea.id, fecha: DateTime(2026, 2, 1), importe: 20000, formaPago: FormaPago.efectivo.name, cuentaFinancieraId: _cuentaRecargaDePrueba);

      expect(await recargaRepo.totalPorServicio(servicio.id), 20000);
    });

    test('recarga sin asignación vigente no corresponde a nadie', () async {
      final linea = await crearLineaDePrueba();
      final recarga = (await registrarRecarga.ejecutar(
        lineaTelefonicaId: linea.id,
        fecha: DateTime(2026, 2, 1),
        importe: 20000,
        formaPago: FormaPago.efectivo.name,
        cuentaFinancieraId: _cuentaRecargaDePrueba,
      )) as RegistrarRecargaLineaTelefonicaExitoso;

      final destino = await recargaRepo.obtenerDestinoHistorico(recarga.recarga.id);
      expect(destino, isNull);
    });
  });

  group('Consistencia con equipo/Inventario (permanece intacta)', () {
    test('registrar una recarga no toca asignación, equipo ni Inventario', () async {
      final linea = await crearLineaDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      await asignarLinea.ejecutar(lineaTelefonicaId: linea.id, empleadoId: empleado.id, fechaInicio: DateTime(2026, 1, 1));
      final asignacionAntes = await asignacionLineaRepo.obtenerActivaPorLinea(linea.id);

      await registrarRecarga.ejecutar(lineaTelefonicaId: linea.id, fecha: DateTime(2026, 2, 1), importe: 20000, formaPago: FormaPago.efectivo.name, cuentaFinancieraId: _cuentaRecargaDePrueba);

      final asignacionDespues = await asignacionLineaRepo.obtenerActivaPorLinea(linea.id);
      expect(asignacionDespues!.id, asignacionAntes!.id, reason: 'una recarga nunca modifica la asignación de la línea');
    });
  });

  group('Comprobante opcional', () {
    test('una recarga sin comprobante sigue siendo válida', () async {
      final linea = await crearLineaDePrueba();
      final resultado = await registrarRecarga.ejecutar(lineaTelefonicaId: linea.id, fecha: DateTime(2026, 2, 1), importe: 20000, formaPago: FormaPago.efectivo.name, cuentaFinancieraId: _cuentaRecargaDePrueba);
      expect(resultado, isA<RegistrarRecargaLineaTelefonicaExitoso>());
    });

    test('adjuntar comprobante a una recarga existente', () async {
      final linea = await crearLineaDePrueba();
      final recarga = (await registrarRecarga.ejecutar(
        lineaTelefonicaId: linea.id,
        fecha: DateTime(2026, 2, 1),
        importe: 20000,
        formaPago: FormaPago.efectivo.name,
        cuentaFinancieraId: _cuentaRecargaDePrueba,
      )) as RegistrarRecargaLineaTelefonicaExitoso;

      final archivo = '${tempDir.path}/comprobante.pdf';
      File(archivo).writeAsStringSync('contenido de prueba');

      final resultado = await adjuntarComprobante.ejecutar(
        recargaLineaTelefonicaId: recarga.recarga.id,
        sourceFilePath: archivo,
        originalFileName: 'comprobante.pdf',
        mimeType: 'application/pdf',
      );

      expect(resultado, isA<AdjuntarComprobanteRecargaLineaTelefonicaExitoso>());
    });

    test('rechaza adjuntar comprobante a una recarga inexistente', () async {
      final archivo = '${tempDir.path}/comprobante.pdf';
      File(archivo).writeAsStringSync('contenido de prueba');

      final resultado = await adjuntarComprobante.ejecutar(
        recargaLineaTelefonicaId: 'no-existe',
        sourceFilePath: archivo,
        originalFileName: 'comprobante.pdf',
        mimeType: 'application/pdf',
      );
      expect(resultado, isA<AdjuntarComprobanteRecargaLineaTelefonicaNoExiste>());
    });
  });
}
