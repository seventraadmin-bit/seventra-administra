// Etapa 15 — "Eliminar cadena de prueba" de Nómina (Maestro). A
// diferencia de `EliminarNominaFisicamenteUseCase` (solo Borrador sin
// PagoNomina), esta acción SÍ alcanza una Nómina Cerrada/Pagada junto
// con TODOS sus PagoNomina/Egresos — investigación previa confirmó que
// este dominio no tiene ningún punto irreversible fiscal/CFDI real
// (ComplementoPago solo existe del lado de ingresos/CxC, nunca de
// PagoNomina); el único chequeo real es la ambigüedad estructural de un
// Egreso compartido con una Compra (invariante de aplicación, no de
// esquema). Cubre los casos obligatorios: Borrador sin pago sigue
// usando la eliminación normal; Pagada con PagoNomina+Egreso se limpia
// por completo; un DescuentoInventario aplicado vuelve a pendiente
// (nunca se elimina) y queda disponible para una Nómina posterior; dos
// Nóminas nunca se afectan entre sí; una dependencia irreversible
// bloquea sin borrar nada; motivo "Otro" sin detalle se rechaza;
// auditoría sobrevive.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/egreso_repository.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart' show MotivoCierreAsignacion;
import 'package:riseg_one/features/inventario/data/tables/descuento_inventario_table.dart' show EstatusDescuentoInventario;
import 'package:riseg_one/features/inventario/domain/usecases/cerrar_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_usecase.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cerrar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/eliminar_cadena_prueba_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/eliminar_nomina_fisicamente_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/evaluar_renglones_requieren_revision_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/registrar_pago_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/resolver_sueldo_empleado_nomina.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';

void main() {
  late AppDatabase db;
  late EmpleadoRepositoryImpl empleadoRepo;
  late ArticuloRepositoryImpl articuloRepo;
  late InventarioRepositoryImpl inventarioRepo;
  late AsignacionRepositoryImpl asignacionRepo;
  late CrearAsignacionUseCase crearAsignacion;
  late CerrarAsignacionUseCase cerrarAsignacion;

  late GenerarNominaUseCase generarNomina;
  late CerrarNominaUseCase cerrarNomina;
  late NominaRepositoryImpl nominaRepo;
  late PagoNominaRepositoryImpl pagoNominaRepo;
  late RegistrarPagoNominaUseCase registrarPagoNomina;
  late EliminarNominaFisicamenteUseCase eliminarNominaFisicamente;
  late EliminarCadenaPruebaNominaUseCase eliminarCadenaPrueba;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final EgresoRepository egresoRepo = EgresoRepositoryImpl(db);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final codigoSecuencia = CodigoSecuenciaService(db);
    final generarCodigo = GenerarCodigoUseCase(codigoSecuencia);

    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    asignacionRepo = AsignacionRepositoryImpl(db);
    crearAsignacion = CrearAsignacionUseCase(asignacionRepo, articuloRepo, inventarioRepo);
    cerrarAsignacion = CerrarAsignacionUseCase(asignacionRepo);

    nominaRepo = NominaRepositoryImpl(db, asignacionRepo, DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)), TiempoExtraRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db), EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)), ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db))), PagoNominaRepositoryImpl(db, EgresoRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db))));
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionServicioRepo, servicioRepo, catalogoRepo);
    generarNomina = GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, generarCodigo);
    final evaluarRenglonesRequierenRevision = EvaluarRenglonesRequierenRevisionUseCase(nominaRepo, empleadoRepo, resolverSueldo);
    cerrarNomina = CerrarNominaUseCase(nominaRepo, evaluarRenglonesRequierenRevision);

    pagoNominaRepo = PagoNominaRepositoryImpl(db, egresoRepo, DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)));
    registrarPagoNomina = RegistrarPagoNominaUseCase(pagoNominaRepo, nominaRepo, generarCodigo, CuentaFinancieraRepositoryImpl(db));
    eliminarNominaFisicamente = EliminarNominaFisicamenteUseCase(nominaRepo);
    eliminarCadenaPrueba = EliminarCadenaPruebaNominaUseCase(nominaRepo);

    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );
  });

  tearDown(() => db.close());

  var empleadoContador = 0;
  Future<EmpleadoData> crearEmpleadoDePrueba({int sueldoMensualAdministrativo = 1500000}) async {
    empleadoContador++;
    final n = empleadoContador.toString().padLeft(2, '0');
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: empleadoContador,
            nombres: 'Empleado$n',
            apellidoPaterno: 'Apellido$n',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX$n',
            rfc: 'PEXJ900101$n',
            nss: '100000000$n',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2025, 1, 1),
            aniosExperienciaSeguridad: 3,
            sueldoMensualAdministrativo: Value(sueldoMensualAdministrativo),
          ),
        );
  }

  /// Genera y cierra una Nómina con un solo Empleado administrativo.
  Future<({NominaData nomina, NominaEmpleadoData renglon})> nominaCerradaDePrueba({
    int anio = 2026,
    int mes = 1,
    int sueldoMensualAdministrativo = 1500000,
  }) async {
    final empleado = await crearEmpleadoDePrueba(sueldoMensualAdministrativo: sueldoMensualAdministrativo);
    final generado = (await generarNomina.ejecutar(anio: anio, mes: mes, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    await cerrarNomina.ejecutar(nominaId: generado.nomina.id);
    final nomina = (await nominaRepo.obtenerPorId(generado.nomina.id))!;
    // Distintas llamadas a este helper reutilizan Empleados creados
    // antes (siguen activos en meses posteriores) — se filtra por el
    // Empleado recién creado, nunca por `.single` sobre todo el
    // listado.
    final renglon = (await nominaRepo.obtenerEmpleadoPorNominaYEmpleado(nominaId: nomina.id, empleadoId: empleado.id))!;
    return (nomina: nomina, renglon: renglon);
  }

  group('Eliminar cadena de prueba — no afecta la eliminación física normal', () {
    test('Borrador sin pago: la eliminación física normal sigue funcionando exactamente igual', () async {
      await crearEmpleadoDePrueba();
      final generado = (await generarNomina.ejecutar(anio: 2026, mes: 2, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;

      final r = await eliminarNominaFisicamente.ejecutar(nominaId: generado.nomina.id, motivo: MotivoEliminacionFisicaNomina.nominaDePrueba);
      expect(r, isA<EliminarNominaFisicamenteExitoso>());
      expect(await nominaRepo.obtenerPorId(generado.nomina.id), isNull);
    });
  });

  group('Eliminar cadena de prueba — casos permitidos', () {
    test('Nómina Pagada con PagoNomina+Egreso de prueba: la cadena completa se elimina', () async {
      final ctx = await nominaCerradaDePrueba();

      final pagoResultado = await registrarPagoNomina.ejecutar(
        nominaId: ctx.nomina.id,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: ctx.renglon.id, monto: ctx.renglon.totalAPagar)],
      );
      expect(pagoResultado, isA<RegistrarPagoNominaExitoso>());
      final pago = (pagoResultado as RegistrarPagoNominaExitoso).pagoNomina;
      final egresoId = pago.egresoId!;

      final nominaPagada = (await nominaRepo.obtenerPorId(ctx.nomina.id))!;
      expect(nominaPagada.estatus, 'pagada');

      // La eliminación física normal debe seguir bloqueada.
      final resumenNormal = await nominaRepo.obtenerResumenEliminacionFisica(ctx.nomina.id);
      expect(resumenNormal.bloqueado, isTrue);

      final resumenCadena = await eliminarCadenaPrueba.obtenerResumen(ctx.nomina.id);
      expect(resumenCadena.bloqueado, isFalse);
      expect(resumenCadena.pagos, hasLength(1));
      expect(resumenCadena.pagos.single.folioPagoNomina, pago.folioPagoNomina);

      final r = await eliminarCadenaPrueba.ejecutar(
        nominaId: ctx.nomina.id,
        motivo: MotivoCadenaPruebaNomina.nominaDePrueba,
        actorUsuarioId: 'usuario-maestro',
      );
      expect(r, isA<EliminarCadenaPruebaNominaExitoso>());

      expect(await nominaRepo.obtenerPorId(ctx.nomina.id), isNull, reason: 'Nómina y renglones desaparecen');
      expect(await (db.select(db.nominaEmpleado)..where((t) => t.nominaId.equals(ctx.nomina.id))).get(), isEmpty);
      expect(await (db.select(db.pagoNomina)..where((t) => t.id.equals(pago.id))).getSingleOrNull(), isNull, reason: 'el PagoNomina desaparece');
      expect(await (db.select(db.egreso)..where((t) => t.id.equals(egresoId))).getSingleOrNull(), isNull, reason: 'el Egreso generado desaparece');
      expect(await (db.select(db.aplicacionPagoNomina)..where((t) => t.pagoNominaId.equals(pago.id))).get(), isEmpty);
    });

    test('un DescuentoInventario aplicado vuelve a pendiente (no se elimina) y queda disponible para una Nómina posterior', () async {
      final empleado = await crearEmpleadoDePrueba();

      // Cadena Inventario: Artículo → Asignación → pérdida con cargo → DescuentoInventario pendiente.
      final categoria =
          (await CrearCategoriaArticuloUseCase(CategoriaArticuloRepositoryImpl(db)).ejecutar(nombre: 'Uniformes') as CrearCategoriaArticuloExitoso)
              .categoria;
      final articulo = (await CrearArticuloUseCase(articuloRepo, CategoriaArticuloRepositoryImpl(db), GenerarCodigoUseCase(CodigoSecuenciaService(db)))
              .ejecutar(categoriaId: categoria.id, nombre: 'PANTALON NEGRO COMANDO', manejaVariante: false, manejaSerie: false)
          as CrearArticuloExitoso)
          .articulo;
      await RegistrarEntradaUseCase(inventarioRepo, articuloRepo).ejecutar(articuloId: articulo.id, cantidad: 1, fecha: DateTime(2026, 1, 5));
      final asignacion = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 1, 6),
      )) as CrearAsignacionExitoso)
          .asignacion;
      await cerrarAsignacion.ejecutar(
        asignacionId: asignacion.id,
        motivo: MotivoCierreAsignacion.perdida,
        fechaCierre: DateTime(2026, 1, 7),
        atribuibleAlEmpleado: true,
        generaDescuento: true,
        importeDescuento: 20000,
        empleadoResponsableDescuentoId: empleado.id,
      );

      // Nómina de enero: aplica el descuento pendiente.
      final generadoEnero = (await generarNomina.ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      await cerrarNomina.ejecutar(nominaId: generadoEnero.nomina.id);
      final nominaEnero = (await nominaRepo.obtenerPorId(generadoEnero.nomina.id))!;
      final renglonEnero = (await nominaRepo.listarEmpleados(nominaEnero.id)).single;
      expect(renglonEnero.descuentosInventario, 20000);

      final descuento = (await asignacionRepo.listarDescuentosPorEmpleado(empleado.id)).single;
      expect(descuento.estatus, EstatusDescuentoInventario.aplicado.name);
      expect(descuento.nominaEmpleadoId, renglonEnero.id);

      // Se paga y se limpia como cadena de prueba.
      final pagoResultado = await registrarPagoNomina.ejecutar(
        nominaId: nominaEnero.id,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: renglonEnero.id, monto: renglonEnero.totalAPagar)],
      );
      expect(pagoResultado, isA<RegistrarPagoNominaExitoso>());

      final r = await eliminarCadenaPrueba.ejecutar(nominaId: nominaEnero.id, motivo: MotivoCadenaPruebaNomina.nominaDePrueba);
      expect(r, isA<EliminarCadenaPruebaNominaExitoso>());

      final descuentoTrasEliminar = (await asignacionRepo.obtenerDescuentoPorId(descuento.id))!;
      expect(descuentoTrasEliminar.estatus, EstatusDescuentoInventario.pendiente.name, reason: 'no se elimina, vuelve a pendiente');
      expect(descuentoTrasEliminar.nominaEmpleadoId, isNull, reason: 'se desvincula del renglón eliminado');
      expect(descuentoTrasEliminar.importe, 20000, reason: 'conserva importe/empleado/asignación/motivo intactos');
      expect(descuentoTrasEliminar.empleadoId, empleado.id);
      expect(descuentoTrasEliminar.asignacionId, asignacion.id);

      // El descuento queda disponible para una Nómina real posterior.
      final generadoFebrero = (await generarNomina.ejecutar(anio: 2026, mes: 2, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
      final renglonFebrero = (await nominaRepo.listarEmpleados(generadoFebrero.nomina.id)).single;
      expect(renglonFebrero.descuentosInventario, 20000, reason: 'se incorpora a la siguiente Nómina real, no se perdió');

      final descuentoFinal = (await asignacionRepo.obtenerDescuentoPorId(descuento.id))!;
      expect(descuentoFinal.estatus, EstatusDescuentoInventario.aplicado.name);
      expect(descuentoFinal.nominaEmpleadoId, renglonFebrero.id);
    });

    test('dos Nóminas distintas nunca se afectan entre sí', () async {
      final ctxA = await nominaCerradaDePrueba(mes: 1);
      final ctxB = await nominaCerradaDePrueba(mes: 2);

      final pagoB = (await registrarPagoNomina.ejecutar(
        nominaId: ctxB.nomina.id,
        fechaPago: DateTime(2026, 2, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: ctxB.renglon.id, monto: ctxB.renglon.totalAPagar)],
      ) as RegistrarPagoNominaExitoso)
          .pagoNomina;

      final r = await eliminarCadenaPrueba.ejecutar(nominaId: ctxA.nomina.id, motivo: MotivoCadenaPruebaNomina.nominaDePrueba);
      expect(r, isA<EliminarCadenaPruebaNominaExitoso>());

      expect(await nominaRepo.obtenerPorId(ctxA.nomina.id), isNull);
      final nominaB = await nominaRepo.obtenerPorId(ctxB.nomina.id);
      expect(nominaB, isNotNull, reason: 'la Nómina B es ajena, nunca debe tocarse');
      expect(await (db.select(db.pagoNomina)..where((t) => t.id.equals(pagoB.id))).getSingleOrNull(), isNotNull, reason: 'el pago de B sigue intacto');
      // La Nómina B de mes 2 también incluye al Empleado de A (sigue
      // activo) — lo relevante es que SU renglón y pago propios sigan
      // intactos, nunca que la tabla completa tenga un conteo exacto.
      final renglonBTrasEliminar = await nominaRepo.obtenerEmpleado(ctxB.renglon.id);
      expect(renglonBTrasEliminar, isNotNull);
      expect(renglonBTrasEliminar!.totalAPagar, ctxB.renglon.totalAPagar);
    });
  });

  group('Eliminar cadena de prueba — punto irreversible: bloquea sin borrar nada', () {
    test('el Egreso del pago también está referenciado por una Compra: bloquea toda la cadena', () async {
      final ctx = await nominaCerradaDePrueba();
      final pago = (await registrarPagoNomina.ejecutar(
        nominaId: ctx.nomina.id,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: ctx.renglon.id, monto: ctx.renglon.totalAPagar)],
      ) as RegistrarPagoNominaExitoso)
          .pagoNomina;

      // Simula la ambigüedad estructural: una Compra apunta al MISMO
      // Egreso (no debería ocurrir en el flujo real, pero no hay
      // constraint de esquema que lo impida — se verifica en código).
      await db.into(db.compra).insert(
            CompraCompanion.insert(
              folioCompra: 'COM-AMBIGUA',
              fecha: DateTime(2026, 1, 21),
              formaPago: 'efectivo',
              egresoId: Value(pago.egresoId),
            ),
          );

      final resumen = await eliminarCadenaPrueba.obtenerResumen(ctx.nomina.id);
      expect(resumen.bloqueado, isTrue);
      expect(resumen.detalleBloqueo, contains('COM-AMBIGUA'));

      final r = await eliminarCadenaPrueba.ejecutar(nominaId: ctx.nomina.id, motivo: MotivoCadenaPruebaNomina.nominaDePrueba);
      expect(r, isA<EliminarCadenaPruebaNominaTieneDependencias>());

      // Nada se tocó.
      expect(await nominaRepo.obtenerPorId(ctx.nomina.id), isNotNull);
      expect(await (db.select(db.pagoNomina)..where((t) => t.id.equals(pago.id))).getSingleOrNull(), isNotNull);
      expect(await (db.select(db.egreso)..where((t) => t.id.equals(pago.egresoId!))).getSingleOrNull(), isNotNull);
    });
  });

  group('Eliminar cadena de prueba — motivo y auditoría', () {
    test('motivo "Otro" sin detalle se rechaza', () async {
      final ctx = await nominaCerradaDePrueba();
      final r = await eliminarCadenaPrueba.ejecutar(nominaId: ctx.nomina.id, motivo: MotivoCadenaPruebaNomina.otro);
      expect(r, isA<EliminarCadenaPruebaNominaDetalleRequerido>());
      expect(await nominaRepo.obtenerPorId(ctx.nomina.id), isNotNull);
    });

    test('rechaza una Nómina inexistente', () async {
      final r = await eliminarCadenaPrueba.ejecutar(nominaId: 'no-existe', motivo: MotivoCadenaPruebaNomina.nominaDePrueba);
      expect(r, isA<EliminarCadenaPruebaNominaNoExiste>());
    });

    test('la auditoría (EliminacionFisicaEvento) sobrevive a la eliminación, sin FK a lo borrado', () async {
      final ctx = await nominaCerradaDePrueba();
      final r = await eliminarCadenaPrueba.ejecutar(
        nominaId: ctx.nomina.id,
        motivo: MotivoCadenaPruebaNomina.pruebasDeDesarrollo,
        actorUsuarioId: 'usuario-maestro',
      );
      expect(r, isA<EliminarCadenaPruebaNominaExitoso>());

      final evento = await (db.select(db.eliminacionFisicaEvento)..where((t) => t.entidadIdOriginal.equals(ctx.nomina.id))).getSingleOrNull();
      expect(evento, isNotNull);
      expect(evento!.tipoEntidad, 'nomina');
      expect(evento.motivoCodigo, MotivoCadenaPruebaNomina.pruebasDeDesarrollo.name);
      expect(evento.actorUsuarioId, 'usuario-maestro');
      expect(evento.snapshotJson, contains(ctx.nomina.folio));
    });
  });
}

/// La cuenta de origen de los pagos de Nómina en esta prueba.
///
/// Reutiliza la primera que el archivo ya haya creado; sólo inventa una
/// si no hay ninguna. Desde la Etapa de integridad financiera, un pago
/// de Nómina con monto > 0 exige cuenta: sin ella el Egreso nacería sin
/// origen y ningún saldo bajaría.
Future<String> _cuentaDePrueba(AppDatabase db) async {
  final existentes = await db.select(db.cuentaFinanciera).get();
  if (existentes.isNotEmpty) return existentes.first.id;
  final cuenta = await db.into(db.cuentaFinanciera).insertReturning(
        CuentaFinancieraCompanion.insert(
          codigo: 'CF-NOMINA-PRUEBA',
          nombre: 'Cuenta de prueba',
          tipo: 'banco',
          saldoInicial: 100000000, // fondeada: la v91 rechaza salidas sin saldo
          fechaSaldoInicial: DateTime(2020, 1, 1),
        ),
      );
  return cuenta.id;
}
