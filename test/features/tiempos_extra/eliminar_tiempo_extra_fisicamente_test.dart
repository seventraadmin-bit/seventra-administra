// Etapa "corrección real de Tiempo Extra" — eliminación física
// extraordinaria: solo elegible cuando ya está `cancelado` (su efecto
// financiero neto ya es cero), snapshotea todo en
// `EliminacionFisicaEvento` (tabla compartida entre dominios) y borra
// en orden FK-seguro (MovimientoDeuda del pago base/costos → TiempoExtra
// —cascada a costos/eventos— → Egresos).

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/tables/tiempo_extra_table.dart';
import 'package:riseg_one/features/tiempos_extra/domain/repositories/tiempo_extra_repository.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/eliminar_tiempo_extra_fisicamente_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/registrar_tiempo_extra_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/vacante_cobertura_reader.dart';

void main() {
  late AppDatabase db;
  late TiempoExtraRepositoryImpl tiempoExtraRepo;
  late RegistrarTiempoExtraUseCase registrar;
  late EliminarTiempoExtraFisicamenteUseCase eliminarFisicamente;
  late DeudaRepositoryImpl deudaRepo;
  late String servicioId;
  late String empleadoAusenteId;
  late String empleadoCubreId;
  late String turnoId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final clienteRepo = ClienteRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final egresoRepo = EgresoRepositoryImpl(db);
    final codigoSecuencia = CodigoSecuenciaService(db);

    deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
    final cuentaFinancieraRepo = CuentaFinancieraRepositoryImpl(db);
    tiempoExtraRepo = TiempoExtraRepositoryImpl(db, egresoRepo, deudaRepo, codigoSecuencia, empleadoRepo, servicioRepo);
    registrar = RegistrarTiempoExtraUseCase(tiempoExtraRepo, empleadoRepo, servicioRepo, deudaRepo, VacanteCoberturaReader(db));
    eliminarFisicamente = EliminarTiempoExtraFisicamenteUseCase(tiempoExtraRepo);

    final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'));
    final servicioCreado = await CrearServicioUseCase(servicioRepo, GenerarCodigoUseCase(codigoSecuencia), ServicioValidator(clienteRepo, catalogoRepo))
        .ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(nombre: 'Vigilancia Sportium', tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
    );
    servicioId = (servicioCreado as GuardarServicioExitoso).servicio.id;

    Future<String> crearEmpleado(int numero, String nombre) async {
      final n = numero.toString().padLeft(2, '0');
      final empleado = await db.into(db.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: numero,
              nombres: nombre,
              apellidoPaterno: 'Apellido$n',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ900101HDFXXX$n',
              rfc: 'PEXJ900101$n',
              nss: '100000000$n',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2025, 1, 1),
              aniosExperienciaSeguridad: 3,
            ),
          );
      return empleado.id;
    }

    empleadoAusenteId = await crearEmpleado(1, 'Monica');
    empleadoCubreId = await crearEmpleado(2, 'Juan');
    turnoId = SeedIds.modalidadTurno24x24;

    await cuentaFinancieraRepo.crear(
      codigo: 'CTA-000001', nombre: 'BBVA', tipo: TipoCuentaFinanciera.banco.name, saldoInicial: 5000000, fechaSaldoInicial: DateTime(2026, 1, 1));
  });

  tearDown(() => db.close());

  test('bloquea la eliminación física de un TiempoExtra que sigue registrado (no cancelado)', () async {
    final resultado = await registrar.ejecutar(
      fecha: DateTime(2026, 9, 3),
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
      empleadoCubreId: empleadoCubreId,
      turnoId: turnoId,
      montoTiempoExtra: 50000,
      formaPago: 'efectivo',
    );
    final tex = (resultado as RegistrarTiempoExtraExitoso).tiempoExtra;

    final eliminado = await eliminarFisicamente.ejecutar(tiempoExtraId: tex.id, motivo: MotivoEliminacionFisicaTiempoExtra.errorDeCaptura);
    expect(eliminado, isA<EliminarTiempoExtraFisicamenteTieneDependencias>());
    expect(await tiempoExtraRepo.obtenerPorId(tex.id), isNotNull);
  });

  test('elimina físicamente una cobertura cancelada con orígenes mixtos (Cuenta + TDC): borra todo, restaura saldos, y snapshotea', () async {
    final cuenta = (await db.select(db.cuentaFinanciera).getSingle());
    final konfio = (await RegistrarDeudaUseCase(deudaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db))).ejecutar(
      nombre: 'Konfío', tipo: TipoDeuda.tarjetaCredito.name, saldoInicial: 0, tarjetaLimiteCredito: 4000000,
    ) as RegistrarDeudaExitoso)
        .deuda;

    final resultado = await registrar.ejecutar(
      fecha: DateTime(2026, 9, 3),
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
      empleadoCubreId: empleadoCubreId,
      turnoId: turnoId,
      montoTiempoExtra: 50000,
      formaPago: 'transferencia',
      cuentaFinancieraId: cuenta.id,
      costosAdicionales: [
        CostoAdicionalInput(concepto: 'Uber', monto: 10000, formaPago: 'tarjeta', deudaIdTarjeta: konfio.id),
      ],
    );
    final tex = (resultado as RegistrarTiempoExtraExitoso).tiempoExtra;
    await tiempoExtraRepo.cancelar(tiempoExtraId: tex.id, motivo: 'Prueba de eliminación física');

    final eliminado = await eliminarFisicamente.ejecutar(
      tiempoExtraId: tex.id,
      motivo: MotivoEliminacionFisicaTiempoExtra.registroDePrueba,
      actorUsuarioId: null,
    );
    expect(eliminado, isA<EliminarTiempoExtraFisicamenteExitoso>());

    expect(await tiempoExtraRepo.obtenerPorId(tex.id), isNull);
    final costos = await (db.select(db.tiempoExtraCostoAdicional)..where((t) => t.tiempoExtraId.equals(tex.id))).get();
    expect(costos, isEmpty, reason: 'cascada al borrar TiempoExtra');
    final eventos = await (db.select(db.tiempoExtraEvento)..where((t) => t.tiempoExtraId.equals(tex.id))).get();
    expect(eventos, isEmpty, reason: 'cascada al borrar TiempoExtra');
    final movimientos = await (db.select(db.movimientoDeuda)..where((t) => t.tiempoExtraId.equals(tex.id))).get();
    expect(movimientos, isEmpty, reason: 'MovimientoDeuda del pago base ya limpiado (restrict, tuvo que borrarse antes)');
    final egresos = await db.select(db.egreso).get();
    expect(egresos, isEmpty, reason: 'el Egreso propio del pago base también se elimina, parte del mismo agregado');

    final konfioTras = await deudaRepo.obtenerPorId(konfio.id);
    expect(konfioTras!.saldoActual, 0, reason: 'ya estaba en 0 tras cancelar — la eliminación física no debe alterar el saldo (neto ya era cero)');

    final snapshotEvento = await (db.select(db.eliminacionFisicaEvento)..where((t) => t.tipoEntidad.equals('tiempoExtra'))).getSingle();
    expect(snapshotEvento.entidadIdOriginal, tex.id);
    expect(snapshotEvento.motivoCodigo, MotivoEliminacionFisicaTiempoExtra.registroDePrueba.name);
    final snapshot = jsonDecode(snapshotEvento.snapshotJson) as Map<String, dynamic>;
    expect(snapshot['tiempoExtra'], isNotNull);
    expect((snapshot['costosAdicionales'] as List).length, 1);
  });

  test('motivo "otro" exige detalle', () async {
    final resultado = await registrar.ejecutar(
      fecha: DateTime(2026, 9, 3),
      servicioId: servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
      empleadoCubreId: empleadoCubreId,
      turnoId: turnoId,
      montoTiempoExtra: 50000,
      formaPago: 'efectivo',
    );
    final tex = (resultado as RegistrarTiempoExtraExitoso).tiempoExtra;
    await tiempoExtraRepo.cancelar(tiempoExtraId: tex.id, motivo: 'Prueba');

    final eliminado = await eliminarFisicamente.ejecutar(tiempoExtraId: tex.id, motivo: MotivoEliminacionFisicaTiempoExtra.otro);
    expect(eliminado, isA<EliminarTiempoExtraFisicamenteDetalleRequerido>());
    expect(await tiempoExtraRepo.obtenerPorId(tex.id), isNotNull);
  });
}
