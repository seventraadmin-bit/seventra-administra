import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/asignacion_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_equipo_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_plan_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/tables/linea_telefonica_table.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/cambiar_estatus_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/corregir_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/crear_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/dar_de_baja_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/registrar_plan_linea_telefonica_usecase.dart';

/// Cubre la fundación del dominio Telefonía (Etapa 9A) — alta,
/// unicidad condicional del número, `operador == otro`, corrección,
/// cambios de estatus manuales, baja terminal y plan/costo (variante
/// simplificada de vigencia). Asignación/equipo/documentos llegan en
/// etapas futuras (9B/9C).
void main() {
  late AppDatabase db;
  late LineaTelefonicaRepositoryImpl lineaRepo;
  late LineaTelefonicaPlanRepositoryImpl planRepo;
  late CrearLineaTelefonicaUseCase crearLinea;
  late CorregirLineaTelefonicaUseCase corregirLinea;
  late CambiarEstatusLineaTelefonicaUseCase cambiarEstatus;
  late DarDeBajaLineaTelefonicaUseCase darDeBaja;
  late RegistrarPlanLineaTelefonicaUseCase registrarPlan;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final asignacionLineaRepo = AsignacionLineaTelefonicaRepositoryImpl(db);
    final equipoRepo = LineaTelefonicaEquipoRepositoryImpl(
      db,
      asignacionLineaRepo,
      AsignacionRepositoryImpl(db),
      InventarioRepositoryImpl(db),
    );
    lineaRepo = LineaTelefonicaRepositoryImpl(db, asignacionLineaRepo, equipoRepo);
    planRepo = LineaTelefonicaPlanRepositoryImpl(db);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    crearLinea = CrearLineaTelefonicaUseCase(lineaRepo, generarCodigo);
    corregirLinea = CorregirLineaTelefonicaUseCase(lineaRepo);
    cambiarEstatus = CambiarEstatusLineaTelefonicaUseCase(lineaRepo);
    darDeBaja = DarDeBajaLineaTelefonicaUseCase(lineaRepo);
    registrarPlan = RegistrarPlanLineaTelefonicaUseCase(planRepo, lineaRepo);
  });

  tearDown(() => db.close());

  Future<LineaTelefonicaData> crearLineaDePrueba({String? numero}) async {
    final resultado = await crearLinea.ejecutar(
      numero: numero,
      operador: 'telcel',
      modalidadSim: 'fisica',
    );
    return (resultado as CrearLineaTelefonicaExitoso).linea;
  }

  group('CrearLineaTelefonicaUseCase', () {
    test('da de alta con código consecutivo y estatus activa por defecto', () async {
      final resultado = await crearLinea.ejecutar(numero: '7221234567', operador: 'telcel', modalidadSim: 'fisica');

      expect(resultado, isA<CrearLineaTelefonicaExitoso>());
      final linea = (resultado as CrearLineaTelefonicaExitoso).linea;
      expect(linea.codigo, 'TEL-000001');
      expect(linea.estatus, 'activa');
      expect(linea.numero, '7221234567');
    });

    test('número es opcional — línea sin número permitida', () async {
      final resultado = await crearLinea.ejecutar(operador: 'telcel', modalidadSim: 'esim');
      expect(resultado, isA<CrearLineaTelefonicaExitoso>());
      expect((resultado as CrearLineaTelefonicaExitoso).linea.numero, isNull);
    });

    test('dos líneas sin número coexisten sin conflicto', () async {
      final r1 = await crearLinea.ejecutar(operador: 'telcel', modalidadSim: 'fisica');
      final r2 = await crearLinea.ejecutar(operador: 'att', modalidadSim: 'esim');
      expect(r1, isA<CrearLineaTelefonicaExitoso>());
      expect(r2, isA<CrearLineaTelefonicaExitoso>());
    });

    test('rechaza número duplicado', () async {
      await crearLinea.ejecutar(numero: '7221234567', operador: 'telcel', modalidadSim: 'fisica');

      final resultado = await crearLinea.ejecutar(numero: '7221234567', operador: 'att', modalidadSim: 'esim');
      expect(resultado, isA<CrearLineaTelefonicaNumeroDuplicado>());
    });

    test('operador == otro exige operadorOtroNombre', () async {
      final sinNombre = await crearLinea.ejecutar(operador: 'otro', modalidadSim: 'fisica');
      expect(sinNombre, isA<CrearLineaTelefonicaOperadorOtroNombreRequerido>());

      final conNombre = await crearLinea.ejecutar(operador: 'otro', operadorOtroNombre: 'Unefon', modalidadSim: 'fisica');
      expect(conNombre, isA<CrearLineaTelefonicaExitoso>());
      expect((conNombre as CrearLineaTelefonicaExitoso).linea.operadorOtroNombre, 'Unefon');
    });
  });

  group('CorregirLineaTelefonicaUseCase', () {
    test('corrige metadatos y permite limpiar campos opcionales', () async {
      final linea = await crearLineaDePrueba(numero: '7221234567');

      final resultado = await corregirLinea.ejecutar(lineaTelefonicaId: linea.id, iccid: '8952140061234567890');
      expect(resultado, isA<CorregirLineaTelefonicaExitoso>());
      expect((resultado as CorregirLineaTelefonicaExitoso).linea.iccid, '8952140061234567890');

      final limpiado = await corregirLinea.ejecutar(lineaTelefonicaId: linea.id, limpiarIccid: true);
      expect((limpiado as CorregirLineaTelefonicaExitoso).linea.iccid, isNull);
    });

    test('rechaza número duplicado contra otra línea, pero permite conservar el propio', () async {
      await crearLineaDePrueba(numero: '7221111111');
      final linea2 = await crearLineaDePrueba(numero: '7222222222');

      final duplicado = await corregirLinea.ejecutar(lineaTelefonicaId: linea2.id, numero: '7221111111');
      expect(duplicado, isA<CorregirLineaTelefonicaNumeroDuplicado>());

      final propio = await corregirLinea.ejecutar(lineaTelefonicaId: linea2.id, numero: '7222222222');
      expect(propio, isA<CorregirLineaTelefonicaExitoso>());
    });
  });

  group('CambiarEstatusLineaTelefonicaUseCase', () {
    test('cambia entre activa y suspendida', () async {
      final linea = await crearLineaDePrueba();

      final suspendida = await cambiarEstatus.ejecutar(lineaTelefonicaId: linea.id, estatus: 'suspendida');
      expect((suspendida as CambiarEstatusLineaTelefonicaExitoso).linea.estatus, 'suspendida');

      final activa = await cambiarEstatus.ejecutar(lineaTelefonicaId: linea.id, estatus: 'activa');
      expect((activa as CambiarEstatusLineaTelefonicaExitoso).linea.estatus, 'activa');
    });

    test('rechaza destino baja (usa DarDeBajaLineaTelefonicaUseCase)', () async {
      final linea = await crearLineaDePrueba();
      final resultado = await cambiarEstatus.ejecutar(lineaTelefonicaId: linea.id, estatus: 'baja');
      expect(resultado, isA<CambiarEstatusLineaTelefonicaDestinoInvalido>());
    });
  });

  group('DarDeBajaLineaTelefonicaUseCase', () {
    test('da de baja y conserva el expediente', () async {
      final linea = await crearLineaDePrueba(numero: '7221234567');

      final resultado = await darDeBaja.ejecutar(
        lineaTelefonicaId: linea.id,
        fechaBaja: DateTime(2026, 3, 1),
        motivoBaja: MotivoBajaLineaTelefonica.cancelacion,
      );
      expect(resultado, isA<DarDeBajaLineaTelefonicaExitoso>());
      final actualizada = (resultado as DarDeBajaLineaTelefonicaExitoso).linea;
      expect(actualizada.estatus, 'baja');
      expect(actualizada.fechaBaja, DateTime(2026, 3, 1));

      final consultada = await lineaRepo.obtenerPorId(linea.id);
      expect(consultada!.numero, '7221234567', reason: 'el expediente se conserva, nunca se borra');
    });

    test('perdidaDelNumero/otro exigen observaciones', () async {
      final linea = await crearLineaDePrueba();
      final resultado = await darDeBaja.ejecutar(
        lineaTelefonicaId: linea.id,
        fechaBaja: DateTime(2026, 3, 1),
        motivoBaja: MotivoBajaLineaTelefonica.perdidaDelNumero,
      );
      expect(resultado, isA<DarDeBajaLineaTelefonicaObservacionesRequeridas>());
    });

    test('rechaza dar de baja una línea ya de baja', () async {
      final linea = await crearLineaDePrueba();
      await darDeBaja.ejecutar(lineaTelefonicaId: linea.id, fechaBaja: DateTime(2026, 3, 1), motivoBaja: MotivoBajaLineaTelefonica.cancelacion);

      final resultado = await darDeBaja.ejecutar(
        lineaTelefonicaId: linea.id,
        fechaBaja: DateTime(2026, 3, 2),
        motivoBaja: MotivoBajaLineaTelefonica.cancelacion,
      );
      expect(resultado, isA<DarDeBajaLineaTelefonicaYaDeBaja>());
    });
  });

  group('RegistrarPlanLineaTelefonicaUseCase', () {
    test('registra el primer plan de una línea', () async {
      final linea = await crearLineaDePrueba();

      final resultado = await registrarPlan.ejecutar(
        lineaTelefonicaId: linea.id,
        nombre: 'Plan Amigo 399',
        costoMensual: 39900,
        fechaInicioVigencia: DateTime(2026, 1, 1),
      );
      expect(resultado, isA<RegistrarPlanLineaTelefonicaExitoso>());

      final vigente = await planRepo.obtenerVigentePorLinea(linea.id);
      expect(vigente!.costoMensual, 39900);
      expect(vigente.fechaFinVigencia, isNull);
    });

    test('cambiar plan cierra el anterior y abre uno nuevo, histórico intacto', () async {
      final linea = await crearLineaDePrueba();
      await registrarPlan.ejecutar(
        lineaTelefonicaId: linea.id,
        nombre: 'Plan 399',
        costoMensual: 39900,
        fechaInicioVigencia: DateTime(2026, 1, 1),
      );

      await registrarPlan.ejecutar(
        lineaTelefonicaId: linea.id,
        nombre: 'Plan 449',
        costoMensual: 44900,
        fechaInicioVigencia: DateTime(2026, 7, 1),
      );

      final historial = await planRepo.listarPorLinea(linea.id);
      expect(historial, hasLength(2), reason: 'la renovación es una fila nueva, la anterior no se toca');

      final anterior = historial.singleWhere((p) => p.nombre == 'Plan 399');
      expect(anterior.fechaFinVigencia, DateTime(2026, 6, 30), reason: 'se cierra el día anterior al nuevo inicio');
      expect(anterior.costoMensual, 39900, reason: 'el histórico nunca se edita');

      final vigente = await planRepo.obtenerVigentePorLinea(linea.id);
      expect(vigente!.nombre, 'Plan 449');
    });

    test('rechaza nombre vacío', () async {
      final linea = await crearLineaDePrueba();
      final resultado = await registrarPlan.ejecutar(
        lineaTelefonicaId: linea.id,
        nombre: '   ',
        costoMensual: 39900,
        fechaInicioVigencia: DateTime(2026, 1, 1),
      );
      expect(resultado, isA<RegistrarPlanLineaTelefonicaNombreRequerido>());
    });

    test('rechaza costo mensual negativo', () async {
      final linea = await crearLineaDePrueba();
      final resultado = await registrarPlan.ejecutar(
        lineaTelefonicaId: linea.id,
        nombre: 'Plan',
        costoMensual: -1,
        fechaInicioVigencia: DateTime(2026, 1, 1),
      );
      expect(resultado, isA<RegistrarPlanLineaTelefonicaCostoInvalido>());
    });

    test('rechaza fecha de fin de permanencia anterior al inicio de vigencia', () async {
      final linea = await crearLineaDePrueba();
      final resultado = await registrarPlan.ejecutar(
        lineaTelefonicaId: linea.id,
        nombre: 'Plan',
        costoMensual: 39900,
        fechaInicioVigencia: DateTime(2026, 6, 1),
        fechaFinPermanencia: DateTime(2026, 1, 1),
      );
      expect(resultado, isA<RegistrarPlanLineaTelefonicaPermanenciaInvalida>());
    });

    test('rechaza registrar plan para una línea dada de baja', () async {
      final linea = await crearLineaDePrueba();
      await darDeBaja.ejecutar(lineaTelefonicaId: linea.id, fechaBaja: DateTime(2026, 1, 1), motivoBaja: MotivoBajaLineaTelefonica.cancelacion);

      final resultado = await registrarPlan.ejecutar(
        lineaTelefonicaId: linea.id,
        nombre: 'Plan',
        costoMensual: 39900,
        fechaInicioVigencia: DateTime(2026, 2, 1),
      );
      expect(resultado, isA<RegistrarPlanLineaTelefonicaLineaDeBaja>());
    });
  });
}
