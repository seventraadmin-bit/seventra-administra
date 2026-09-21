// Etapa 15 — Eliminación física de Nómina (Maestro), prueba funcional
// real reportada por Marlon (punto 3 de Nómina + limpieza segura de
// datos de prueba, punto H). Cubre: un Borrador sin PagoNomina se
// puede eliminar y sus `DescuentoInventario` aplicados vuelven a
// `pendiente` (nunca desaparecen); una Nómina Cerrada/Pagada, o con
// PagoNomina real, se bloquea siempre; motivo "Otro" sin detalle se
// rechaza; la auditoría (`EliminacionFisicaEvento`) sobrevive a la
// eliminación; no quedan registros huérfanos.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
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
import 'package:riseg_one/features/nomina/domain/usecases/eliminar_nomina_fisicamente_usecase.dart';
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
  late ArticuloRepositoryImpl articuloRepo;
  late InventarioRepositoryImpl inventarioRepo;
  late AsignacionRepositoryImpl asignacionRepo;
  late CrearAsignacionUseCase crearAsignacion;
  late CerrarAsignacionUseCase cerrarAsignacion;
  late NominaRepositoryImpl nominaRepo;
  late GenerarNominaUseCase generarNomina;
  late EliminarNominaFisicamenteUseCase eliminarNominaFisicamente;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    asignacionRepo = AsignacionRepositoryImpl(db);
    crearAsignacion = CrearAsignacionUseCase(asignacionRepo, articuloRepo, inventarioRepo);
    cerrarAsignacion = CerrarAsignacionUseCase(asignacionRepo);

    nominaRepo = NominaRepositoryImpl(db, asignacionRepo, DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)), TiempoExtraRepositoryImpl(db, EgresoRepositoryImpl(db), DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)), CodigoSecuenciaService(db), EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)), ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db))), PagoNominaRepositoryImpl(db, EgresoRepositoryImpl(db), DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db))));
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);
    final resolverSueldo = ResolverSueldoEmpleadoNomina(empleadoRepo, asignacionServicioRepo, servicioRepo, catalogoRepo);
    generarNomina =
        GenerarNominaUseCase(nominaRepo, empleadoRepo, puestoRepo, catalogoRepo, resolverSueldo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    eliminarNominaFisicamente = EliminarNominaFisicamenteUseCase(nominaRepo);

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
  Future<EmpleadoData> crearEmpleadoConSueldo(int sueldoMensualAdministrativo) async {
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

  var articuloContador = 0;
  Future<ArticuloData> crearArticuloDePrueba() async {
    articuloContador++;
    final categoria = (await CrearCategoriaArticuloUseCase(CategoriaArticuloRepositoryImpl(db)).ejecutar(nombre: 'Uniformes$articuloContador')
            as CrearCategoriaArticuloExitoso)
        .categoria;
    final resultado = await CrearArticuloUseCase(articuloRepo, CategoriaArticuloRepositoryImpl(db), GenerarCodigoUseCase(CodigoSecuenciaService(db)))
        .ejecutar(categoriaId: categoria.id, nombre: 'PANTALON NEGRO COMANDO $articuloContador', manejaVariante: false, manejaSerie: false);
    final articulo = (resultado as CrearArticuloExitoso).articulo;
    await RegistrarEntradaUseCase(inventarioRepo, articuloRepo).ejecutar(articuloId: articulo.id, cantidad: 1, fecha: DateTime(2026, 8, 20));
    return articulo;
  }

  Future<String> reportarPerdidaConCargo(String empleadoId, {int importe = 20000}) async {
    final articulo = await crearArticuloDePrueba();
    final creada = ((await crearAsignacion.ejecutar(
      articuloId: articulo.id,
      cantidad: 1,
      empleadoId: empleadoId,
      fechaEntrega: DateTime(2026, 8, 21),
    )) as CrearAsignacionExitoso)
        .asignacion;

    await cerrarAsignacion.ejecutar(
      asignacionId: creada.id,
      motivo: MotivoCierreAsignacion.perdida,
      fechaCierre: DateTime(2026, 8, 22),
      atribuibleAlEmpleado: true,
      generaDescuento: true,
      importeDescuento: importe,
      empleadoResponsableDescuentoId: empleadoId,
    );
    return articulo.id;
  }

  test('un Borrador sin PagoNomina se elimina físicamente, y sus descuentos aplicados vuelven a pendiente', () async {
    final empleado = await crearEmpleadoConSueldo(1500000);
    await reportarPerdidaConCargo(empleado.id, importe: 20000);

    final nomina = ((await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso).nomina;
    final renglon = (await nominaRepo.obtenerEmpleadoPorNominaYEmpleado(nominaId: nomina.id, empleadoId: empleado.id))!;
    expect(renglon.descuentosInventario, 20000);
    final descuentoAplicado = (await asignacionRepo.listarDescuentosPorEmpleado(empleado.id)).single;
    expect(descuentoAplicado.estatus, EstatusDescuentoInventario.aplicado.name);

    final resultado = await eliminarNominaFisicamente.ejecutar(
      nominaId: nomina.id,
      motivo: MotivoEliminacionFisicaNomina.nominaDePrueba,
      actorUsuarioId: 'usuario-maestro',
    );
    expect(resultado, isA<EliminarNominaFisicamenteExitoso>());

    expect(await nominaRepo.obtenerPorId(nomina.id), isNull, reason: 'no debe quedar ningún rastro de la Nómina');
    expect(
      await nominaRepo.obtenerEmpleadoPorNominaYEmpleado(nominaId: nomina.id, empleadoId: empleado.id),
      isNull,
      reason: 'sin renglones huérfanos',
    );

    final descuentoRevertido = (await asignacionRepo.listarDescuentosPorEmpleado(empleado.id)).single;
    expect(descuentoRevertido.estatus, EstatusDescuentoInventario.pendiente.name, reason: 'la deuda nunca debe desaparecer');
    expect(descuentoRevertido.nominaEmpleadoId, isNull);
    expect(descuentoRevertido.fechaAplicacion, isNull);

    final pendientesDeNuevo = await asignacionRepo.listarDescuentosPendientesPorEmpleado(empleado.id);
    expect(pendientesDeNuevo, hasLength(1));
  });

  test('motivo "Otro" sin detalle se rechaza, sin tocar la Nómina', () async {
    final empleado = await crearEmpleadoConSueldo(1500000);
    final nomina = ((await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso).nomina;
    expect((await nominaRepo.obtenerEmpleadoPorNominaYEmpleado(nominaId: nomina.id, empleadoId: empleado.id)), isNotNull);

    final resultado = await eliminarNominaFisicamente.ejecutar(nominaId: nomina.id, motivo: MotivoEliminacionFisicaNomina.otro);
    expect(resultado, isA<EliminarNominaFisicamenteDetalleRequerido>());
    expect(await nominaRepo.obtenerPorId(nomina.id), isNotNull);
  });

  test('motivo "Otro" con detalle se acepta', () async {
    await crearEmpleadoConSueldo(1500000);
    final nomina = ((await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso).nomina;

    final resultado = await eliminarNominaFisicamente.ejecutar(
      nominaId: nomina.id,
      motivo: MotivoEliminacionFisicaNomina.otro,
      detalle: 'Se generó por error al probar el periodo equivocado',
      actorUsuarioId: 'usuario-maestro',
    );
    expect(resultado, isA<EliminarNominaFisicamenteExitoso>());
    expect(await nominaRepo.obtenerPorId(nomina.id), isNull);
  });

  test('una Nómina Cerrada se bloquea con mensaje específico, nunca se borra a ciegas', () async {
    await crearEmpleadoConSueldo(1500000);
    final nomina = ((await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso).nomina;
    await cerrarNominaDePrueba(db, nomina.id);

    final resultado = await eliminarNominaFisicamente.ejecutar(nominaId: nomina.id, motivo: MotivoEliminacionFisicaNomina.nominaDePrueba);
    expect(resultado, isA<EliminarNominaFisicamenteTieneDependencias>());
    expect((resultado as EliminarNominaFisicamenteTieneDependencias).detalle, contains('Borrador'));
    expect(await nominaRepo.obtenerPorId(nomina.id), isNotNull, reason: 'nunca se elimina cuando está bloqueado');
  });

  test('una Nómina con PagoNomina real se bloquea, nunca se borra a ciegas', () async {
    final empleado = await crearEmpleadoConSueldo(1500000);
    final nomina = ((await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso).nomina;
    await cerrarNominaDePrueba(db, nomina.id);

    final egresoRepo = EgresoRepositoryImpl(db);
    final pagoNominaRepo = PagoNominaRepositoryImpl(db, egresoRepo, DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), CodigoSecuenciaService(db)));
    final registrarPagoNomina = RegistrarPagoNominaUseCase(pagoNominaRepo, nominaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)), CuentaFinancieraRepositoryImpl(db));
    final renglon = (await nominaRepo.obtenerEmpleadoPorNominaYEmpleado(nominaId: nomina.id, empleadoId: empleado.id))!;
    await registrarPagoNomina.ejecutar(
      nominaId: nomina.id,
      fechaPago: DateTime(2026, 8, 20),
      formaPago: 'transferencia',
      cuentaFinancieraId: await _cuentaDePrueba(db),
      aplicaciones: [(nominaEmpleadoId: renglon.id, monto: renglon.totalAPagar)],
    );

    final resultado = await eliminarNominaFisicamente.ejecutar(nominaId: nomina.id, motivo: MotivoEliminacionFisicaNomina.nominaDePrueba);
    expect(resultado, isA<EliminarNominaFisicamenteTieneDependencias>());
    expect(await nominaRepo.obtenerPorId(nomina.id), isNotNull);
  });

  test('la auditoría (EliminacionFisicaEvento) sobrevive a la eliminación física', () async {
    final empleado = await crearEmpleadoConSueldo(1500000);
    final nomina = ((await generarNomina.ejecutar(anio: 2026, mes: 8, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso).nomina;

    await eliminarNominaFisicamente.ejecutar(
      nominaId: nomina.id,
      motivo: MotivoEliminacionFisicaNomina.errorDeCaptura,
      actorUsuarioId: 'usuario-maestro',
    );

    final evento = await (db.select(db.eliminacionFisicaEvento)..where((t) => t.tipoEntidad.equals('nomina'))).getSingle();
    expect(evento.entidadIdOriginal, nomina.id);
    expect(evento.actorUsuarioId, 'usuario-maestro');
    expect(evento.motivoCodigo, MotivoEliminacionFisicaNomina.errorDeCaptura.name);
    expect(evento.motivo, MotivoEliminacionFisicaNomina.errorDeCaptura.etiqueta);
    expect(evento.snapshotJson, contains(empleado.nombres));
  });
}

/// Cierra una Nómina directamente (sin pasar por `CerrarNominaUseCase`,
/// que requiere resolver `EvaluarRenglonesRequierenRevisionUseCase`
/// contra Personal/Organización completos) — solo para dejarla en el
/// estado `cerrada` necesario para reproducir el bloqueo de
/// eliminación física, sin la maquinaria completa del motor de sueldos.
Future<void> cerrarNominaDePrueba(AppDatabase db, String nominaId) {
  return (db.update(db.nomina)..where((t) => t.id.equals(nominaId))).write(
    NominaCompanion(estatus: const Value('cerrada'), fechaCierre: Value(DateTime.now())),
  );
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
          saldoInicial: 0,
          fechaSaldoInicial: DateTime(2020, 1, 1),
        ),
      );
  return cuenta.id;
}
