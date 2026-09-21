// Etapa 4 (Nómina — corrección, cancelación y trazabilidad integral),
// Sección 15: escenario numérico integral contra BD real, exactamente
// el ejemplo del pedido — Empleado A $10,000/B $8,000/C $0, Nómina
// cerrada $18,000, pago parcial de A, corrección de A ($10,000 →
// $9,500) sin reescribir lo ya pagado, pago del resto, la Nómina llega
// a pagada, y cancelar el pago de A la reabre — cero pagos ficticios,
// cero doble conteo.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/codigos/generar_numero_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_posicion_de_caja_usecase.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cancelar_pago_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cerrar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/corregir_renglon_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/evaluar_renglones_requieren_revision_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/registrar_pago_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/resolver_sueldo_empleado_nomina.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/crear_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/empleado_validator.dart';
import 'package:riseg_one/features/dashboard/domain/usecases/obtener_proxima_nomina_usecase.dart';

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late NominaRepositoryImpl nominaRepo;
  late PagoNominaRepositoryImpl pagoNominaRepo;
  late CuentaFinancieraRepositoryImpl cuentaFinancieraRepo;
  late GenerarNominaUseCase generarNomina;
  late CerrarNominaUseCase cerrarNomina;
  late RegistrarPagoNominaUseCase registrarPagoNomina;
  late CancelarPagoNominaUseCase cancelarPagoNomina;
  late CorregirRenglonNominaUseCase corregirRenglon;
  late ObtenerProximaNominaUseCase obtenerProximaNomina;
  late ObtenerPosicionDeCajaUseCase obtenerPosicionDeCaja;
  late CrearEmpleadoUseCase crearEmpleado;
  var empleadoContador = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_nomina_correccion_integral_test_');
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(id: const Value('usuario-prueba'), nombre: 'Usuario de prueba', nombreUsuario: 'usuario-prueba', passwordHash: 'x'),
        );
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final egresoRepo = EgresoRepositoryImpl(db);
    final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    cuentaFinancieraRepo = CuentaFinancieraRepositoryImpl(db);
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionServicioRepo, servicioRepo, catalogoRepo);
    pagoNominaRepo = PagoNominaRepositoryImpl(db, egresoRepo, DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)));
    nominaRepo = NominaRepositoryImpl(
      db,
      AsignacionRepositoryImpl(db),
      DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)),
      TiempoExtraRepositoryImpl(db, egresoRepo, deudaRepo, CodigoSecuenciaService(db), empleadoRepo, servicioRepo),
      pagoNominaRepo,
    );
    generarNomina = GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    cerrarNomina = CerrarNominaUseCase(nominaRepo, EvaluarRenglonesRequierenRevisionUseCase(nominaRepo, empleadoRepo, resolverSueldo));
    registrarPagoNomina = RegistrarPagoNominaUseCase(pagoNominaRepo, nominaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)), CuentaFinancieraRepositoryImpl(db));
    cancelarPagoNomina = CancelarPagoNominaUseCase(pagoNominaRepo);
    corregirRenglon = CorregirRenglonNominaUseCase(nominaRepo, pagoNominaRepo);
    obtenerProximaNomina = ObtenerProximaNominaUseCase(nominaRepo);
    obtenerPosicionDeCaja = ObtenerPosicionDeCajaUseCase(cuentaFinancieraRepo);
    crearEmpleado = CrearEmpleadoUseCase(
      empleadoRepo,
      GenerarNumeroUseCase(CodigoSecuenciaService(db)),
      const EmpleadoValidator(),
      servicioRepo,
      ServicioComercialRepositoryImpl(db),
    );
  });

  tearDown(() {
    db.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<EmpleadoData> crearEmpleadoDePrueba() async {
    empleadoContador++;
    final n = empleadoContador.toString().padLeft(2, '0');
    final resultado = await crearEmpleado.ejecutar(
      nombres: 'Empleado$n',
      apellidoPaterno: 'Apellido$n',
      sexo: SexoEmpleado.masculino,
      fechaNacimiento: DateTime(1990, 1, 1),
      curp: 'PEXJ900101HDFXXX$n',
      rfc: 'PEXJ900101$n',
      nss: '100000000$n',
      estadoCivil: EstadoCivilEmpleado.soltero,
      fechaIngreso: DateTime(2025, 1, 1),
      aniosExperienciaSeguridad: 3,
      sueldoMensualAdministrativo: 100000,
    );
    return (resultado as CrearEmpleadoExitoso).empleado;
  }

  test(
    'Escenario integral (Sección 15): A \$10,000/B \$8,000/C \$0, Nómina cerrada \$18,000 -> paga A parcial \$4,000 '
    'desde BBVA -> corrige A a \$9,500 (nunca reescribe lo pagado) -> paga el resto -> Nómina pagada, fuera de '
    '"Próxima nómina" -> cancela el pago de \$5,500 de A -> reabre correctamente, cero doble conteo',
    () async {
      final bbva = await cuentaFinancieraRepo.crear(
        codigo: 'CTA-000001',
        nombre: 'BBVA',
        tipo: TipoCuentaFinanciera.banco.name,
        saldoInicial: 5000000,
        fechaSaldoInicial: DateTime(2026, 1, 1),
      );

      final empA = await crearEmpleadoDePrueba();
      final empB = await crearEmpleadoDePrueba();
      final empC = await crearEmpleadoDePrueba();

      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final nominaId = generado.nomina.id;

      Future<NominaEmpleadoData> renglonDe(String empleadoId) async {
        return (await nominaRepo.listarEmpleados(nominaId)).firstWhere((r) => r.empleadoId == empleadoId);
      }

      // Fuerza los 3 totales EXACTOS del pedido, todavía en Borrador —
      // vía `bono`/`otrosDescuentos` sobre el `importeBase` real que
      // ya resolvió `GenerarNominaUseCase` (nunca se inventa un total,
      // se ajusta con los mismos movimientos que ya existen).
      Future<void> forzarTotal(NominaEmpleadoData r, int totalObjetivo) {
        final bono = (totalObjetivo - r.importeBase).clamp(0, 1 << 30);
        final otrosDescuentos = (r.importeBase - totalObjetivo).clamp(0, 1 << 30);
        return nominaRepo.actualizarRenglon(
          nominaEmpleadoId: r.id,
          prestamo: 0,
          tiempoExtra: 0,
          bono: bono,
          bonoModificadoManualmente: true,
          faltas: 0,
          otrosDescuentos: otrosDescuentos,
          observaciones: null,
          tipoEvento: 'movimientoModificado',
        );
      }

      await forzarTotal(await renglonDe(empA.id), 1000000);
      await forzarTotal(await renglonDe(empB.id), 800000);
      await forzarTotal(await renglonDe(empC.id), 0);

      var renglonA = await renglonDe(empA.id);
      var renglonB = await renglonDe(empB.id);
      var renglonC = await renglonDe(empC.id);
      expect(renglonA.totalAPagar, 1000000);
      expect(renglonB.totalAPagar, 800000);
      expect(renglonC.totalAPagar, 0);
      expect(renglonC.estatusPago, 'pagado', reason: 'saneamiento de \$0: pagado sin ningún Pago/Egreso real');
      final pagosTrasGenerar = await pagoNominaRepo.listarPorNomina(nominaId);
      expect(pagosTrasGenerar, isEmpty, reason: 'C nunca genera un PagoNomina ficticio');

      await cerrarNomina.ejecutar(nominaId: nominaId);
      var nomina = (await nominaRepo.obtenerPorId(nominaId))!;
      expect(nomina.estatus, 'cerrada');

      // Pago parcial de A: $4,000 desde BBVA.
      final pagoParcial = await registrarPagoNomina.ejecutar(
        nominaId: nominaId,
        fechaPago: DateTime(2026, 1, 18),
        formaPago: 'transferencia',
        cuentaFinancieraId: bbva.id,
        aplicaciones: [(nominaEmpleadoId: renglonA.id, monto: 400000)],
      );
      expect(pagoParcial, isA<RegistrarPagoNominaExitoso>());

      var posicion = await obtenerPosicionDeCaja.ejecutar();
      expect(posicion.saldosPorCuenta[bbva.id], 4600000, reason: 'BBVA baja exactamente \$4,000 (de \$50,000 a \$46,000)');
      renglonA = await renglonDe(empA.id);
      expect(renglonA.totalAPagar - await pagoNominaRepo.saldoPendientePago(renglonA.id), 400000);
      expect(await pagoNominaRepo.saldoPendientePago(renglonA.id), 600000, reason: 'A pendiente \$6,000');
      renglonB = await renglonDe(empB.id);
      expect(await pagoNominaRepo.saldoPendientePago(renglonB.id), 800000, reason: 'B pendiente \$8,000 — nada tocado');
      nomina = (await nominaRepo.obtenerPorId(nominaId))!;
      expect(nomina.estatus, 'cerrada', reason: 'sigue cerrada, ni cerca de pagada');

      // Corrige A de $10,000 a $9,500 — nunca reescribe los $4,000 ya
      // pagados; evento before/after con motivo y actor reales.
      final corregidoA = await corregirRenglon.ejecutar(
        nominaEmpleadoId: renglonA.id,
        prestamo: renglonA.prestamo,
        tiempoExtra: renglonA.tiempoExtra,
        bono: renglonA.bono - 50000,
        faltas: renglonA.faltas,
        otrosDescuentos: renglonA.otrosDescuentos,
        observaciones: renglonA.observaciones,
        motivo: 'El bono real capturado fue menor',
        actorUsuarioId: 'usuario-prueba',
      );
      expect(corregidoA, isA<CorregirRenglonNominaExitoso>());
      renglonA = await renglonDe(empA.id);
      expect(renglonA.totalAPagar, 950000, reason: 'nuevo total \$9,500');
      expect(await pagoNominaRepo.saldoPendientePago(renglonA.id), 550000, reason: 'pendiente final \$5,500 = 9,500 - 4,000 ya pagado');
      final aplicacionOriginal = (await pagoNominaRepo.listarAplicacionesPorRenglon(renglonA.id)).single;
      expect(aplicacionOriginal.monto, 400000, reason: 'el pago histórico de \$4,000 NUNCA se reescribe');

      final eventoCorreccion = (await nominaRepo.listarEventos(nominaId))
          .where((e) => e.nominaEmpleadoId == renglonA.id && e.tipoEvento == 'corregida')
          .last;
      expect(eventoCorreccion.observacion, 'El bono real capturado fue menor');
      expect(eventoCorreccion.estadoAnterior, isNotNull);
      expect(eventoCorreccion.estadoNuevo, isNotNull);
      expect(eventoCorreccion.estadoAnterior!.contains('1000000'), isTrue, reason: 'estadoAnterior conserva el total viejo en centavos');
      expect(eventoCorreccion.estadoNuevo!.contains('950000'), isTrue, reason: 'estadoNuevo conserva el total nuevo en centavos');

      // Paga el resto: $5,500 de A y $8,000 de B.
      final pagoResto = await registrarPagoNomina.ejecutar(
        nominaId: nominaId,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: bbva.id,
        aplicaciones: [
          (nominaEmpleadoId: renglonA.id, monto: 550000),
          (nominaEmpleadoId: renglonB.id, monto: 800000),
        ],
      );
      expect(pagoResto, isA<RegistrarPagoNominaExitoso>());
      final pagoRestoExitoso = pagoResto as RegistrarPagoNominaExitoso;

      renglonA = await renglonDe(empA.id);
      renglonB = await renglonDe(empB.id);
      renglonC = await renglonDe(empC.id);
      expect(renglonA.estatusPago, 'pagado');
      expect(renglonB.estatusPago, 'pagado');
      expect(renglonC.estatusPago, 'pagado');
      nomina = (await nominaRepo.obtenerPorId(nominaId))!;
      expect(nomina.estatus, 'pagada');

      posicion = await obtenerPosicionDeCaja.ejecutar();
      expect(
        posicion.saldosPorCuenta[bbva.id],
        3250000,
        reason: 'BBVA baja \$4,000+\$5,500+\$8,000 = \$17,500 en total, de \$50,000 a \$32,500',
      );

      final proxima = await obtenerProximaNomina.ejecutar();
      expect(proxima, isNull, reason: 'una Nómina pagada nunca es "Próxima nómina"');

      // Cancela el pago de $5,500 de A (y $8,000 de B, mismo lote).
      final cancelado = await cancelarPagoNomina.ejecutar(pagoNominaId: pagoRestoExitoso.pagoNomina.id, motivo: 'Se registró por error en este lote');
      expect(cancelado, isA<CancelarPagoNominaExitoso>());

      posicion = await obtenerPosicionDeCaja.ejecutar();
      expect(
        posicion.saldosPorCuenta[bbva.id],
        4600000,
        reason: 'BBVA recupera exactamente \$13,500 (los \$5,500 de A + \$8,000 de B revertidos), de vuelta a \$46,000 '
            '— el mismo estado que justo después del primer pago parcial',
      );

      renglonA = await renglonDe(empA.id);
      renglonB = await renglonDe(empB.id);
      expect(await pagoNominaRepo.saldoPendientePago(renglonA.id), 550000, reason: 'A vuelve a pendiente \$5,500 exactos');
      expect(renglonA.estatusPago, 'parcial');
      expect(await pagoNominaRepo.saldoPendientePago(renglonB.id), 800000, reason: 'B también se revirtió en el mismo lote cancelado');

      nomina = (await nominaRepo.obtenerPorId(nominaId))!;
      expect(nomina.estatus, 'cerrada', reason: 'la Nómina deja pagada — ya no todos los renglones están pagados');

      final proximaTrasCancelar = await obtenerProximaNomina.ejecutar();
      expect(proximaTrasCancelar?.id, nominaId, reason: 'vuelve a considerarse "Próxima nómina" — Dashboard consistente con el estatus real');

      final eventoReabierta = (await nominaRepo.listarEventos(nominaId)).where((e) => e.tipoEvento == 'reabierta').toList();
      expect(eventoReabierta, isNotEmpty, reason: 'la transición pagada->cerrada queda auditada, a diferencia del código previo a esta etapa');
      final eventoPagada = (await nominaRepo.listarEventos(nominaId)).where((e) => e.tipoEvento == 'pagada').toList();
      expect(eventoPagada, isNotEmpty, reason: 'la transición cerrada->pagada también queda auditada');
    },
  );
}
