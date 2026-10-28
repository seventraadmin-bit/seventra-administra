// Servicios Eventuales — Rebanada 3: cierre integral.
//
// Auditoría central (§23), permisos (§24) y coherencia financiera
// (§21): lo que hay que demostrar antes de declarar el módulo cerrado.

import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/permissions/modulos_permiso.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart' show TipoMovimientoDeuda;
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_pago_aplicado_usecase.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/tables/servicio_eventual_table.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/totales_venta_eventual.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/agregar_cobertura_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/agregar_costo_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/agregar_participante_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/corregir_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/crear_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/pagar_cobertura_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/pagar_costo_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/registrar_cobro_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/usecases/revertir_pago_cobertura_servicio_eventual_usecase.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/usuarios/data/repositories/auditoria_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/buscar_auditoria_usecase.dart';

void main() {
  group('§24 — Permisos', () {
    test('el módulo declara exactamente las facultades implementadas', () {
      final modulo = modulosPermiso.firstWhere((m) => m.codigo == 'serviciosEventuales');

      expect(
        modulo.accionesEspeciales.toSet(),
        {
          'serviciosEventuales.crear',
          'serviciosEventuales.corregir',
          'serviciosEventuales.cancelar',
          'serviciosEventuales.pagar',
          'serviciosEventuales.revertirPago',
          'serviciosEventuales.cobrar',
          'serviciosEventuales.facturar',
        },
      );

      // §24: nunca un `ver` sin consumidor. La ruta la gatea
      // `comercial.ver`, igual que Clientes y Servicios.
      expect(modulo.accionesEspeciales, isNot(contains('serviciosEventuales.ver')));
      expect(modulo.accionesBase, isEmpty);
      expect(modulo.grupoVisual, 'comercial');
    });

    test('pagar y cobrar son facultades DISTINTAS de corregir', () {
      // Pagar a un guardia y cobrarle al cliente mueven dinero; corregir
      // el nombre del evento no. Que sean códigos distintos es lo que
      // permite dárselas a personas distintas.
      final modulo = modulosPermiso.firstWhere((m) => m.codigo == 'serviciosEventuales');
      for (final financiera in ['pagar', 'revertirPago', 'cobrar', 'facturar']) {
        expect(
          modulo.accionesEspeciales,
          contains('serviciosEventuales.$financiera'),
          reason: '$financiera tiene que poder otorgarse por separado',
        );
      }
    });
  });

  group('§11/§24 — ninguna etiqueta técnica llega al usuario', () {
    test('el módulo y sus siete permisos están traducidos', () {
      // Se lee el catálogo de etiquetas directo: un permiso sin entrada
      // cae en el `_ => codigo` final y la matriz mostraría el código
      // crudo. Montar AppLocalizations aquí sería mucho aparato para
      // comprobar una tabla de traducción.
      final etiquetas =
          File('lib/features/usuarios/presentation/widgets/permiso_labels.dart').readAsStringSync();
      expect(etiquetas, contains("'serviciosEventuales' =>"));

      final modulo = modulosPermiso.firstWhere((m) => m.codigo == 'serviciosEventuales');
      for (final codigo in modulo.accionesEspeciales) {
        expect(
          etiquetas,
          contains("'$codigo' =>"),
          reason: '$codigo se mostraría como código crudo en la matriz de permisos',
        );
      }
    });
  });

  group('Integral', () {
    late AppDatabase db;
    late CuentaPorCobrarRepositoryImpl cuentaRepo;
    late PagoRepositoryImpl pagoRepo;
    late DeudaRepositoryImpl deudaRepo;
    late ServicioEventualRepositoryImpl repo;
    late AuditoriaRepositoryImpl auditoriaRepo;

    late CrearServicioEventualUseCase crear;
    late CorregirServicioEventualUseCase corregir;
    late RegistrarCobroServicioEventualUseCase cobrar;
    late AgregarParticipanteServicioEventualUseCase agregarParticipante;
    late AgregarCoberturaServicioEventualUseCase agregarCobertura;
    late AgregarCostoServicioEventualUseCase agregarCosto;
    late PagarCoberturaServicioEventualUseCase pagarCobertura;
    late PagarCostoServicioEventualUseCase pagarCosto;
    late RevertirPagoCoberturaServicioEventualUseCase revertirPagoCobertura;

    late CuentaFinancieraData cuentaBanco;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      final codigoSecuencia = CodigoSecuenciaService(db);
      final egresoRepo = EgresoRepositoryImpl(db);
      deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
      cuentaRepo = CuentaPorCobrarRepositoryImpl(db);
      pagoRepo = PagoRepositoryImpl(db);
      repo = ServicioEventualRepositoryImpl(db, egresoRepo, deudaRepo, codigoSecuencia, cuentaRepo, pagoRepo);
      auditoriaRepo = AuditoriaRepositoryImpl(db);

      crear = CrearServicioEventualUseCase(repo, ClienteRepositoryImpl(db), EntidadFiscalRepositoryImpl(db));
      corregir = CorregirServicioEventualUseCase(repo, cuentaRepo, pagoRepo);
      cobrar = RegistrarCobroServicioEventualUseCase(
        repo,
        RegistrarPagoAplicadoUseCase(pagoRepo, cuentaRepo, GenerarCodigoUseCase(codigoSecuencia)),
      );
      agregarParticipante = AgregarParticipanteServicioEventualUseCase(repo, EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)));
      agregarCobertura = AgregarCoberturaServicioEventualUseCase(repo);
      agregarCosto = AgregarCostoServicioEventualUseCase(repo);
      pagarCobertura = PagarCoberturaServicioEventualUseCase(repo, deudaRepo);
      pagarCosto = PagarCostoServicioEventualUseCase(repo, deudaRepo);
      revertirPagoCobertura = RevertirPagoCoberturaServicioEventualUseCase(repo);

      cuentaBanco = await db.into(db.cuentaFinanciera).insertReturning(
            CuentaFinancieraCompanion.insert(
              codigo: 'CF-BBVA',
              nombre: 'BBVA',
              tipo: 'cuenta',
              saldoInicial: 100000000, // fondeada: la v91 rechaza salidas sin saldo
              fechaSaldoInicial: DateTime(2026, 1, 1),
            ),
          );
    });

    tearDown(() => db.close());

    Future<CrearServicioEventualExitoso> vender({int importe = 1000000}) async {
      final resultado = await crear.ejecutar(
        nombre: 'Concierto plaza',
        fechaHoraInicio: DateTime(2026, 5, 1),
        fechaHoraFin: DateTime(2026, 5, 2),
        importeAcordado: importe,
        tipoSolicitante: TipoSolicitanteServicioEventual.eventual,
        solicitanteNombre: 'Promotora Norte',
        tratamientoIva: TratamientoIva.masIva,
      );
      return resultado as CrearServicioEventualExitoso;
    }

    Future<ServicioEventualCoberturaData> nuevaCobertura(String eventualId, {int importe = 200000}) async {
      final participante = ((await agregarParticipante.ejecutar(
        servicioEventualId: eventualId,
        nombreExterno: 'Refuerzo externo',
      )) as AgregarParticipanteServicioEventualExitoso)
          .participante;
      return ((await agregarCobertura.ejecutar(
        servicioEventualId: eventualId,
        participanteId: participante.id,
        fecha: DateTime(2026, 5, 1),
        horaInicioMinutos: 8 * 60,
        horaFinMinutos: 20 * 60,
        importeAcordado: importe,
      )) as AgregarCoberturaServicioEventualExitoso)
          .cobertura;
    }

    group('§23 — Auditoría central', () {
      test('los eventos del eventual llegan a Auditoría con actor, acción, motivo y diff', () async {
        await db.into(db.usuario).insert(
              UsuarioCompanion.insert(
                id: const Value('usuario-1'),
                nombre: 'Operador',
                nombreUsuario: 'operador',
                passwordHash: r'pbkdf2$1$c2FsdA==$aGFzaA==',
              ),
            );

        final venta = await crear.ejecutar(
          nombre: 'Concierto plaza',
          fechaHoraInicio: DateTime(2026, 5, 1),
          fechaHoraFin: DateTime(2026, 5, 2),
          importeAcordado: 1000000,
          tipoSolicitante: TipoSolicitanteServicioEventual.eventual,
          solicitanteNombre: 'Promotora Norte',
          tratamientoIva: TratamientoIva.noAplica,
          actorUsuarioId: 'usuario-1',
        ) as CrearServicioEventualExitoso;

        await corregir.ejecutar(
          servicioEventualId: venta.servicioEventual.id,
          importeAcordado: 1500000,
          motivo: 'Se renegoció el precio',
          actorUsuarioId: 'usuario-1',
        );

        final eventos = await auditoriaRepo.buscar(const FiltroAuditoria());
        final delEventual = eventos.where((e) => e.modulo == 'serviciosEventuales').toList();

        expect(delEventual, isNotEmpty, reason: 'crear la tabla NO la integra: hay que declararla en Auditoría');
        expect(delEventual.map((e) => e.accion), contains('creado'));

        final correccion = delEventual.firstWhere((e) => e.accion == 'corregido');
        expect(correccion.actorUsuarioId, 'usuario-1');
        expect(correccion.motivo, 'Se renegoció el precio');
        expect(correccion.entidadEtiqueta, venta.servicioEventual.folio);
        expect(correccion.cambios, isNotEmpty, reason: 'el diff antes/después tiene que viajar');
        expect(
          correccion.cambios.map((c) => c.campo),
          contains('importeAcordado'),
        );
      });

      test('la etiqueta es el folio, nunca el nombre del solicitante ocasional', () async {
        final venta = await vender();
        final eventos = await auditoriaRepo.buscar(const FiltroAuditoria());
        final delEventual = eventos.where((e) => e.modulo == 'serviciosEventuales');

        for (final evento in delEventual) {
          expect(evento.entidadEtiqueta, venta.servicioEventual.folio);
          expect(evento.entidadEtiqueta, isNot(contains('Promotora')));
        }
      });

      test('el Egreso de una cobertura NO se duplica como evento del eventual', () async {
        final venta = await vender();
        final cobertura = await nuevaCobertura(venta.servicioEventual.id);
        await pagarCobertura.ejecutar(
          coberturaId: cobertura.id,
          formaPago: FormaPago.transferencia.name,
          cuentaFinancieraId: cuentaBanco.id,
        );

        final eventos = await auditoriaRepo.buscar(const FiltroAuditoria());
        // El pago aparece UNA vez como hecho comercial del eventual...
        expect(
          eventos.where((e) => e.modulo == 'serviciosEventuales' && e.accion == 'coberturaPagada'),
          hasLength(1),
        );
        // ...y el Egreso conserva su propia bitácora, que es otro hecho.
        expect(eventos.where((e) => e.modulo == 'egresos').length, lessThanOrEqualTo(1));
      });
    });

    group('§21 — Finanzas: exactamente una vez', () {
      test('cobro al cliente → un Ingreso, ni más ni menos', () async {
        final venta = await vender(importe: 1000000);
        await cobrar.ejecutar(
          servicioEventualId: venta.servicioEventual.id,
          monto: 1160000,
          fechaPago: DateTime(2026, 5, 10),
          formaPago: FormaPago.transferencia.name,
          cuentaFinancieraId: cuentaBanco.id,
        );
        expect(await db.select(db.ingreso).get(), hasLength(1));
        expect(await db.select(db.egreso).get(), isEmpty, reason: 'cobrar no genera gasto');
      });

      test('cobertura con Cuenta → un Egreso y cero cargos; con TDC al revés', () async {
        final venta = await vender();
        final conCuenta = await nuevaCobertura(venta.servicioEventual.id);
        await pagarCobertura.ejecutar(
          coberturaId: conCuenta.id,
          formaPago: FormaPago.transferencia.name,
          cuentaFinancieraId: cuentaBanco.id,
        );
        expect(await db.select(db.egreso).get(), hasLength(1));
        expect(await db.select(db.movimientoDeuda).get(), isEmpty);

        final tarjeta = await db.into(db.deuda).insertReturning(
              DeudaCompanion.insert(
                folio: 'DEU-TDC',
                nombre: 'TDC',
                tipo: 'tarjetaCredito',
                saldoActual: 0,
                tarjetaLimiteCredito: const Value(5000000),
              ),
            );
        final conTarjeta = await nuevaCobertura(venta.servicioEventual.id, importe: 150000);
        await pagarCobertura.ejecutar(
          coberturaId: conTarjeta.id,
          formaPago: FormaPago.tarjeta.name,
          deudaIdTarjeta: tarjeta.id,
        );
        expect(await db.select(db.egreso).get(), hasLength(1), reason: 'la TDC NO genera un Egreso');
        final movimientos = await db.select(db.movimientoDeuda).get();
        expect(movimientos, hasLength(1));
        expect(movimientos.single.tipo, TipoMovimientoDeuda.cargoCompra.name);
      });

      test('un costo se comporta igual que una cobertura', () async {
        final venta = await vender();
        final costo = ((await agregarCosto.ejecutar(
          servicioEventualId: venta.servicioEventual.id,
          concepto: 'Traslado',
          monto: 90000,
          fecha: DateTime(2026, 5, 1),
        )) as AgregarCostoServicioEventualExitoso)
            .costo;
        await pagarCosto.ejecutar(
          costoId: costo.id,
          formaPago: FormaPago.transferencia.name,
          cuentaFinancieraId: cuentaBanco.id,
        );
        expect(await db.select(db.egreso).get(), hasLength(1));
      });

      test('revertir elimina el efecto exactamente una vez, y sólo el suyo', () async {
        final venta = await vender();
        final cobertura = await nuevaCobertura(venta.servicioEventual.id);
        await pagarCobertura.ejecutar(
          coberturaId: cobertura.id,
          formaPago: FormaPago.transferencia.name,
          cuentaFinancieraId: cuentaBanco.id,
        );
        await cobrar.ejecutar(
          servicioEventualId: venta.servicioEventual.id,
          monto: 500000,
          fechaPago: DateTime(2026, 5, 10),
          formaPago: FormaPago.transferencia.name,
          cuentaFinancieraId: cuentaBanco.id,
        );

        await revertirPagoCobertura.ejecutar(coberturaId: cobertura.id, motivo: 'Error');

        // §18: cada acción afecta sólo su concepto. Revertir el pago al
        // guardia NO toca el cobro al cliente.
        expect((await db.select(db.egreso).get()).single.estatus, 'cancelado');
        expect((await db.select(db.ingreso).get()).single.estatus, 'registrado');
        expect((await cuentaRepo.obtenerPorId(venta.cuenta.id))!.saldoPendiente, 660000);
      });
    });

    group('§19 — estados derivados, no cacheados', () {
      test('cobrado y pendiente salen de la CxC, no de una copia en el eventual', () async {
        final venta = await vender(importe: 1000000);
        await cobrar.ejecutar(
          servicioEventualId: venta.servicioEventual.id,
          monto: 400000,
          fechaPago: DateTime(2026, 5, 10),
          formaPago: FormaPago.transferencia.name,
          cuentaFinancieraId: cuentaBanco.id,
        );

        final cuenta = (await repo.obtenerCuentaPorCobrar(venta.servicioEventual.id))!;
        expect(cuenta.saldoOriginal - cuenta.saldoPendiente, 400000);

        // El eventual no guarda ni un peso de eso.
        final eventual = (await repo.obtenerPorId(venta.servicioEventual.id))!;
        expect(eventual.importeAcordado, 1000000, reason: 'sigue siendo lo capturado, sin cobranza dentro');
      });
    });

    group('Política de saldo (v91) — Servicios Eventuales', () {
      test('A) con saldo suficiente: la cobertura se paga', () async {
        final venta = await vender();
        final cobertura = await nuevaCobertura(venta.servicioEventual.id);
        final resultado = await pagarCobertura.ejecutar(
          coberturaId: cobertura.id,
          formaPago: FormaPago.transferencia.name,
          cuentaFinancieraId: cuentaBanco.id,
        );
        expect(resultado, isA<PagarCoberturaServicioEventualExitoso>());
      });

      test('B y C) sin saldo: rechaza y NO deja persistencia parcial', () async {
        final venta = await vender();
        final cobertura = await nuevaCobertura(venta.servicioEventual.id);
        final vacia = await db.into(db.cuentaFinanciera).insertReturning(
          CuentaFinancieraCompanion.insert(
            codigo: 'CF-VACIA',
            nombre: 'Cuenta sin fondos',
            tipo: 'cuenta',
            saldoInicial: 1,
            fechaSaldoInicial: DateTime(2026, 1, 1),
          ),
        );
        final egresosAntes = (await db.select(db.egreso).get()).length;

        await expectLater(
          pagarCobertura.ejecutar(
            coberturaId: cobertura.id,
            formaPago: FormaPago.transferencia.name,
            cuentaFinancieraId: vacia.id,
          ),
          throwsA(isA<SaldoInsuficienteException>()),
        );

        final recargada = (db.select(db.servicioEventualCobertura)
              ..where((t) => t.id.equals(cobertura.id)))
            .getSingle();
        expect((await recargada).egresoId, isNull, reason: 'la cobertura sigue sin pagar');
        expect(
          (await db.select(db.egreso).get()).length,
          egresosAntes,
          reason: 'ni el Egreso',
        );
        expect(
          (await db.select(db.egresoFuente).get()).where((f) => f.cuentaFinancieraId == vacia.id),
          isEmpty,
          reason: 'ni su fuente',
        );
      });
    });
  });

}
