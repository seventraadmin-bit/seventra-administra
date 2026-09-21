// Reportes Etapa C — patrimonio, resguardos, bajas y recuperación.
//
// Los ocho casos del pedido se construyen con la cadena REAL de
// conciliación (`ConciliarBajaEmpleadoUseCase`), nunca insertando
// renglones a mano: lo que se prueba es que el reporte proyecta lo que
// el dominio realmente escribió.
//
// La distinción que estas pruebas defienden por encima de todo:
//
//   pendiente        -> sigue con la persona, se espera recuperar
//   perdido          -> resolución declarada, ya no vuelve
//   pendienteDesecho -> recuperado, esperando la baja física
//   lavandería/rep.  -> recuperado, fuera de disponibilidad
//
// Confundir cualquiera de esas cuatro era el riesgo principal.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart';
import 'package:riseg_one/features/inventario/data/tables/movimiento_inventario_table.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart';
import 'package:riseg_one/features/personal/data/tables/conciliacion_baja_table.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/conciliar_baja_empleado_usecase.dart';
import 'package:riseg_one/features/personal/personal_providers.dart';
import 'package:riseg_one/features/reportes/domain/analitica/comparacion_periodo.dart';
import 'package:riseg_one/features/reportes/domain/analitica/obtener_analisis_patrimonio_usecase.dart';
import 'package:riseg_one/features/reportes/reportes_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_table.dart';
import 'package:riseg_one/features/vehiculos/vehiculos_providers.dart';

class _SesionMaestro extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
        usuarioId: 'maestro',
        nombre: 'Maestro de prueba',
        nombreUsuario: 'maestro',
        esMaestro: true,
        permisos: {},
      );
}

/// Costo capturado de cada artículo sembrado: $200.00.
const _costoArticulo = 20000;

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  var consecutivo = 0;

  final rango = RangoPeriodo(inicio: DateTime(2026, 1, 1), fin: DateTime(2026, 12, 31));
  final fechaBaja = DateTime(2026, 6, 15);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(_SesionMaestro.new),
    ]);
    consecutivo = 0;
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Future<EmpleadoData> crearEmpleado({bool administrativo = false}) async {
    final n = (++consecutivo).toString().padLeft(2, '0');
    String? sucursalId;
    if (administrativo) {
      final sucursal = await db.into(db.sucursal).insertReturning(
            SucursalCompanion.insert(
              codigo: 'SUC-$n',
              nombre: 'Corporativo',
              tipoSucursalId: SeedIds.tipoSucursalOficinaAdministrativa,
            ),
          );
      sucursalId = sucursal.id;
    }
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: consecutivo,
            nombres: administrativo ? 'Admin' : 'Operativo',
            apellidoPaterno: 'Prueba $n',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'CUXA900101HDFXXX$n',
            rfc: 'CUXA900101A$n',
            nss: '1234567$n',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2024, 1, 1),
            aniosExperienciaSeguridad: 3,
            sucursalId: Value(sucursalId),
          ),
        );
  }


  /// Un Servicio real con su Cliente y tipo de catálogo.
  Future<ServicioData> crearServicio(String nombre) async {
    final n = (++consecutivo).toString().padLeft(3, '0');
    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-$n', nombreComercial: 'Cliente $n'),
        );
    return db.into(db.servicio).insertReturning(
          ServicioCompanion.insert(
            codigo: 'SER-$n',
            clienteId: cliente.id,
            nombre: nombre,
            tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
            fechaInicio: DateTime(2026, 1, 1),
          ),
        );
  }

  /// Escritura DIRECTA de la vigencia, a propósito.
  ///
  /// El dominio de Personal impide tener dos asignaciones vigentes a la
  /// vez (índice único parcial), así que la única forma de comprobar qué
  /// hace el reporte ante un dato histórico roto es sembrarlo tal cual.
  /// Reportes no puede arreglar ese dato: sólo tiene que reportarlo.
  Future<AsignacionServicioData> adscribir(
    String empleadoId,
    String servicioId, {
    required DateTime inicio,
    DateTime? termino,
  }) {
    return db.into(db.asignacionServicio).insertReturning(
          AsignacionServicioCompanion.insert(
            empleadoId: empleadoId,
            servicioId: servicioId,
            fechaInicio: inicio,
            fechaTermino: Value(termino),
          ),
        );
  }
  /// Un artículo serializado con una unidad y costo real capturado.
  Future<({String articuloId, String unidadId})> crearBien(String nombre) async {
    final n = (++consecutivo).toString().padLeft(3, '0');
    final categoria = await db.into(db.categoriaArticulo).insertReturning(
          CategoriaArticuloCompanion.insert(nombre: 'Cat $n'),
        );
    final articulo = await ArticuloRepositoryImpl(db).crear(
      folio: 'ART-$n',
      categoriaId: categoria.id,
      nombre: nombre,
      manejaVariante: false,
      manejaSerie: true,
    );
    final unidad = await db.into(db.articuloUnidad).insertReturning(
          ArticuloUnidadCompanion.insert(articuloId: articulo.id, codigo: 'UNI-$n', numeroSerie: 'S-$n'),
        );
    await db.into(db.movimientoInventario).insert(
          MovimientoInventarioCompanion.insert(
            articuloId: articulo.id,
            unidadId: Value(unidad.id),
            tipoMovimiento: TipoMovimientoInventario.entrada.name,
            cantidad: 1,
            costoUnitario: const Value(_costoArticulo),
            fecha: DateTime(2026, 1, 10),
          ),
        );
    return (articuloId: articulo.id, unidadId: unidad.id);
  }

  Future<AsignacionData> asignar(String empleadoId, ({String articuloId, String unidadId}) bien) {
    return container.read(asignacionRepositoryProvider).crear(
          articuloId: bien.articuloId,
          unidadId: bien.unidadId,
          cantidad: 1,
          empleadoId: empleadoId,
          fechaEntrega: DateTime(2026, 2, 1),
        );
  }

  Future<AsignacionVehiculoData> asignarVehiculo(String empleadoId) async {
    final n = (++consecutivo).toString().padLeft(3, '0');
    final vehiculo = await container.read(vehiculoRepositoryProvider).crear(
          codigo: 'VEH-$n',
          marca: 'Nissan',
          modelo: 'NP300',
          anio: 2022,
          tipoVehiculo: TipoVehiculo.pickup.name,
          placas: 'ABC-$n',
        );
    return container.read(asignacionVehiculoRepositoryProvider).crear(
          vehiculoId: vehiculo.id,
          empleadoId: empleadoId,
          fechaInicio: DateTime(2026, 2, 1),
        );
  }

  Future<void> conciliar(String empleadoId, List<ResolucionResguardo> resoluciones) async {
    final resultado = await container.read(conciliarBajaEmpleadoUseCaseProvider).ejecutar(
          empleadoId: empleadoId,
          fechaBaja: fechaBaja,
          motivo: MotivoBajaEmpleado.renuncia,
          resoluciones: resoluciones,
        );
    expect(resultado, isA<ConciliarBajaEmpleadoExitoso>(), reason: 'la conciliación debe completarse');
  }

  Future<AnalisisPatrimonio> analizar({FiltroPatrimonio filtro = const FiltroPatrimonio()}) {
    return container.read(obtenerAnalisisPatrimonioUseCaseProvider).ejecutar(rango: rango, filtro: filtro);
  }

  group('Caso A — baja limpia', () {
    test('todo devuelto: cero pendientes, cero descuentos, tasa de recuperación 100 %', () async {
      final empleado = await crearEmpleado();
      final camisa = await crearBien('Camisola');
      final asignacion = await asignar(empleado.id, camisa);

      await conciliar(empleado.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.devuelto,
          condicion: CondicionDevolucionResguardo.bueno,
          destino: DestinoDevolucionResguardo.inventarioDisponible,
        ),
      ]);

      final analisis = await analizar();

      expect(analisis.bajasConciliadas, 1);
      expect(analisis.recuperados, 1);
      expect(analisis.pendientes, 0);
      expect(analisis.perdidos, 0);
      expect(analisis.importeDescuentos, 0);
      expect(analisis.tasaRecuperacion.tasa, 1.0);
      expect(analisis.tasaRecuperacion.debianRecuperarse, 1);
      expect(analisis.renglones.single.estatusUnidad, EstatusArticuloUnidad.disponible.name);
    });
  });

  group('Caso B — abandono', () {
    test('dos bienes no entregados: uno con descuento y otro sin cobro autorizado', () async {
      final empleado = await crearEmpleado();
      final autorizador = await crearEmpleado(administrativo: true);
      final radio = await crearBien('Radio');
      final lampara = await crearBien('Lámpara');
      final asignacionRadio = await asignar(empleado.id, radio);
      final asignacionLampara = await asignar(empleado.id, lampara);

      await conciliar(empleado.id, [
        ResolucionResguardo(
          asignacionId: asignacionRadio.id,
          resolucion: ResolucionResguardoBaja.noEntregado,
          motivoNoEntrega: MotivoNoEntregaResguardo.abandonoServicio,
          generaDescuento: true,
          importeDescuento: 150000,
          conceptoDescuento: 'Radio no entregado',
          numeroCuotasDescuento: 3,
        ),
        ResolucionResguardo(
          asignacionId: asignacionLampara.id,
          resolucion: ResolucionResguardoBaja.noEntregado,
          motivoNoEntrega: MotivoNoEntregaResguardo.abandonoServicio,
          autorizadorEmpleadoId: autorizador.id,
          motivoNoCobro: 'Lámpara al final de su vida útil',
        ),
      ]);

      final analisis = await analizar();

      expect(analisis.pendientes, 2, reason: 'abandono deja pendiente: el bien sigue con la persona');
      expect(analisis.perdidos, 0, reason: 'PENDIENTE NO ES PERDIDO');
      expect(analisis.recuperados, 0);
      expect(analisis.importeDescuentos, 150000);
      expect(analisis.decisionesSinCobro, 1);
      expect(analisis.importeNoCobrado, _costoArticulo, reason: 'es el valor del bien, no un importe condonado');
      expect(analisis.tasaRecuperacion.tasa, 0.0);
      expect(analisis.tasaRecuperacion.debianRecuperarse, 2);

      final conDescuento = analisis.renglones.firstWhere((r) => r.descuento != null);
      expect(conDescuento.descuento!.importeOriginal, 150000);
      expect(conDescuento.descuento!.tipo, 'resguardo');
      expect(conDescuento.descuento!.asignacionOrigenId, asignacionRadio.id,
          reason: 'el vínculo es estructural, no por prefijo de folio');

      final sinCobro = analisis.renglones.firstWhere((r) => r.noCobroAutorizado);
      expect(sinCobro.autorizadorNombre, isNotNull);
      expect(sinCobro.renglon.autorizadorEmpleadoId, autorizador.id);
    });
  });

  group('Caso C — lavandería', () {
    test('prenda recuperada a lavandería con descuento de limpieza: recuperada, no pendiente', () async {
      final empleado = await crearEmpleado();
      final receptor = await crearEmpleado(administrativo: true);
      final camisa = await crearBien('Camisola');
      final asignacion = await asignar(empleado.id, camisa);

      await conciliar(empleado.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.devuelto,
          condicion: CondicionDevolucionResguardo.sucio,
          destino: DestinoDevolucionResguardo.lavanderia,
          receptorEmpleadoId: receptor.id,
          costoLimpieza: 8000,
          responsableCostoLimpieza: ResponsableCostoResguardo.trabajador,
          generaDescuento: true,
          importeDescuento: 8000,
          conceptoDescuento: 'Limpieza de camisola',
        ),
      ]);

      final analisis = await analizar();
      final renglon = analisis.renglones.single;

      expect(analisis.recuperados, 1);
      expect(analisis.pendientes, 0, reason: 'la prenda volvió: no está pendiente de recuperación');
      expect(renglon.estatusUnidad, EstatusArticuloUnidad.enLavanderia.name);
      expect(renglon.receptorNombre, isNotNull, reason: 'sí se sabe quién la recibió');
      expect(analisis.unidadesPorEstatus[EstatusArticuloUnidad.enLavanderia.name], 1);
      expect(analisis.importeDescuentos, 8000);
    });
  });

  group('Caso D — reparación', () {
    test('equipo recuperado a reparación: cuenta como recuperado y queda fuera de disponibilidad', () async {
      final empleado = await crearEmpleado();
      final radio = await crearBien('Radio');
      final asignacion = await asignar(empleado.id, radio);

      await conciliar(empleado.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.devuelto,
          condicion: CondicionDevolucionResguardo.malEstado,
          destino: DestinoDevolucionResguardo.reparacion,
        ),
      ]);

      final analisis = await analizar();

      expect(analisis.recuperados, 1);
      expect(analisis.pendientes, 0);
      expect(analisis.unidadesPorEstatus[EstatusArticuloUnidad.enReparacion.name], 1);
      expect(
        await container.read(inventarioRepositoryProvider).obtenerUnidadPorId(radio.unidadId).then((u) => u!.estatus),
        EstatusArticuloUnidad.enReparacion.name,
      );
    });
  });

  group('Caso E — pérdida', () {
    test('bien perdido con descuento: perdido no es pendiente', () async {
      final empleado = await crearEmpleado();
      final radio = await crearBien('Radio');
      final asignacion = await asignar(empleado.id, radio);

      await conciliar(empleado.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.perdido,
          generaDescuento: true,
          importeDescuento: 200000,
          conceptoDescuento: 'Radio extraviado',
        ),
      ]);

      final analisis = await analizar();

      expect(analisis.perdidos, 1);
      expect(analisis.pendientes, 0, reason: 'perdido es una resolución declarada, no una espera');
      expect(analisis.recuperados, 0);
      expect(analisis.valorPerdido, _costoArticulo);
      expect(analisis.valorPendiente, 0);
      expect(analisis.importeDescuentos, 200000);
      expect(analisis.tasaRecuperacion.debianRecuperarse, 1, reason: 'lo perdido SÍ debía recuperarse');
      expect(analisis.tasaRecuperacion.tasa, 0.0);
    });
  });

  group('Caso F — pendiente de desecho', () {
    test('recuperado y fuera de disponibilidad, pero aún sin baja física', () async {
      final empleado = await crearEmpleado();
      final camisa = await crearBien('Camisola');
      final asignacion = await asignar(empleado.id, camisa);
      final autorizador = await crearEmpleado(administrativo: true);

      await conciliar(empleado.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.devuelto,
          condicion: CondicionDevolucionResguardo.danado,
          destino: DestinoDevolucionResguardo.desecho,
          autorizadorEmpleadoId: autorizador.id,
          motivoNoCobro: 'Prenda al final de su vida útil',
        ),
      ]);

      final analisis = await analizar();

      expect(analisis.recuperados, 1, reason: 'volvió a RISEG');
      expect(analisis.pendientes, 0, reason: 'PENDIENTE DE DESECHO no es pendiente de recuperación');
      expect(analisis.unidadesPorEstatus[EstatusArticuloUnidad.pendienteDesecho.name], 1);
      expect(analisis.unidadesPorEstatus[EstatusArticuloUnidad.baja.name], isNull,
          reason: 'la baja física no se ejecutó');
    });
  });

  group('Caso G — vehículo', () {
    test('vehículo entregado con receptor administrativo', () async {
      final empleado = await crearEmpleado();
      final receptor = await crearEmpleado(administrativo: true);
      final asignacion = await asignarVehiculo(empleado.id);

      await conciliar(empleado.id, [
        ResolucionResguardo(
          asignacionVehiculoId: asignacion.id,
          resolucion: ResolucionResguardoBaja.devuelto,
          // El dominio exige condición también para un vehículo.
          condicion: CondicionDevolucionResguardo.usado,
          receptorEmpleadoId: receptor.id,
          lugarEntrega: 'Corporativo Toluca',
          combustible: 'Medio tanque',
          danos: 'Rayón en puerta trasera',
        ),
      ]);

      final analisis = await analizar();
      final renglon = analisis.renglones.single;

      expect(renglon.tipo, TipoBienConciliado.vehiculo);
      expect(renglon.bienDescripcion, contains('Nissan'));
      expect(renglon.receptorNombre, isNotNull);
      expect(renglon.renglon.lugarEntrega, 'Corporativo Toluca');
      expect(renglon.renglon.danos, contains('Rayón'));
      expect(renglon.estatusUnidad, isNull, reason: 'un vehículo no tiene ArticuloUnidad');
      expect(analisis.recuperados, 1);
      expect(analisis.pendientes, 0);

      final soloVehiculos = await analizar(filtro: const FiltroPatrimonio(tipoBien: TipoBienConciliado.vehiculo));
      expect(soloVehiculos.renglones, hasLength(1));
      final soloInventario =
          await analizar(filtro: const FiltroPatrimonio(tipoBien: TipoBienConciliado.inventario));
      expect(soloInventario.renglones, isEmpty);
    });
  });

  group('Caso H — autorización', () {
    test('una decisión sin cobro se agrupa por empleadoId del autorizador', () async {
      final autorizador = await crearEmpleado(administrativo: true);
      // Dos bajas distintas autorizadas por la MISMA persona.
      for (var i = 0; i < 2; i++) {
        final empleado = await crearEmpleado();
        final bien = await crearBien('Bien $i');
        final asignacion = await asignar(empleado.id, bien);
        await conciliar(empleado.id, [
          ResolucionResguardo(
            asignacionId: asignacion.id,
            resolucion: ResolucionResguardoBaja.noEntregado,
            motivoNoEntrega: MotivoNoEntregaResguardo.autorizadoAConservarlo,
            autorizadorEmpleadoId: autorizador.id,
          ),
        ]);
      }

      final analisis = await analizar();

      expect(analisis.autorizadores, hasLength(1), reason: 'agrupa por empleadoId, no por nombre');
      final actividad = analisis.autorizadores.single;
      expect(actividad.empleadoId, autorizador.id);
      expect(actividad.decisiones, 2);
      expect(actividad.decisionesSinCobro, 2);
      expect(actividad.importeInvolucrado, _costoArticulo * 2);

      // Y NO cuentan para la tasa: nunca debieron volver.
      expect(analisis.tasaRecuperacion.excluidosAutorizados, 2);
      expect(analisis.tasaRecuperacion.debianRecuperarse, 0);
      expect(analisis.tasaRecuperacion.tasa, isNull, reason: 'sin denominador no hay tasa, y 0 % mentiría');

      final delAutorizador = await analizar(filtro: FiltroPatrimonio(autorizadorId: autorizador.id));
      expect(delAutorizador.renglones, hasLength(2));
    });
  });

  group('Transferencia — excluida de la tasa', () {
    test('un bien transferido no cuenta como pendiente ni entra al denominador', () async {
      final empleado = await crearEmpleado();
      final sucesor = await crearEmpleado();
      final radio = await crearBien('Radio');
      final asignacion = await asignar(empleado.id, radio);

      await conciliar(empleado.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.transferido,
          nuevoResponsableEmpleadoId: sucesor.id,
        ),
      ]);

      final analisis = await analizar();

      expect(analisis.transferidos, 1);
      expect(analisis.pendientes, 0);
      expect(analisis.recuperados, 0);
      expect(analisis.tasaRecuperacion.excluidosTransferidos, 1);
      expect(analisis.tasaRecuperacion.debianRecuperarse, 0,
          reason: 'pasó a otra persona: nunca debió volver al almacén');
      expect(analisis.tasaRecuperacion.tasa, isNull);
    });
  });

  group('Misma fuente de verdad', () {
    test('KPI, tabla y agregados salen del MISMO universo filtrado', () async {
      final autorizador = await crearEmpleado(administrativo: true);
      final juan = await crearEmpleado();
      final pedro = await crearEmpleado();

      final bienJuan = await crearBien('Radio Juan');
      final bienPedro = await crearBien('Radio Pedro');
      final asignacionJuan = await asignar(juan.id, bienJuan);
      final asignacionPedro = await asignar(pedro.id, bienPedro);

      await conciliar(juan.id, [
        ResolucionResguardo(
          asignacionId: asignacionJuan.id,
          resolucion: ResolucionResguardoBaja.noEntregado,
          motivoNoEntrega: MotivoNoEntregaResguardo.noLocalizado,
          generaDescuento: true,
          importeDescuento: 90000,
          conceptoDescuento: 'Radio no recuperado',
        ),
      ]);
      await conciliar(pedro.id, [
        ResolucionResguardo(
          asignacionId: asignacionPedro.id,
          resolucion: ResolucionResguardoBaja.devuelto,
          condicion: CondicionDevolucionResguardo.bueno,
          destino: DestinoDevolucionResguardo.inventarioDisponible,
          receptorEmpleadoId: autorizador.id,
        ),
      ]);

      final todo = await analizar();
      expect(todo.renglones, hasLength(2));
      expect(todo.bajasConciliadas, 2);
      expect(
        todo.renglones.where((r) => r.estaPendiente).length,
        todo.pendientes,
        reason: 'el KPI de pendientes es exactamente la tabla filtrada',
      );
      expect(
        todo.renglones.fold<int>(0, (a, r) => a + r.importeDescuento),
        todo.importeDescuentos,
        reason: 'el KPI de descuentos es la suma de las obligaciones incluidas',
      );
      // El panel de estados físicos proyecta SÓLO lo recuperado: el
      // radio de Juan sigue con él (unidad en `asignado`) y no puede
      // aparecer como una ubicación de resguardo.
      expect(
        todo.renglones.where((r) => r.fueRecuperado && r.estatusUnidad != null).length,
        todo.unidadesPorEstatus.values.fold<int>(0, (a, b) => a + b),
        reason: 'los estados físicos suman exactamente los bienes recuperados del detalle',
      );
      expect(
        todo.unidadesPorEstatus.values.fold<int>(0, (a, b) => a + b),
        lessThanOrEqualTo(todo.recuperados),
        reason: 'la gráfica nunca puede superar su propio KPI',
      );
      expect(todo.unidadesPorEstatus['asignado'], isNull);

      // Filtrar recalcula todo sobre el subconjunto.
      final soloJuan = await analizar(filtro: FiltroPatrimonio(empleadoId: juan.id));
      expect(soloJuan.renglones, hasLength(1));
      expect(soloJuan.bajasConciliadas, 1);
      expect(soloJuan.pendientes, 1);
      expect(soloJuan.importeDescuentos, 90000);
      expect(soloJuan.impactoPorBaja, hasLength(1));

      final soloPendientes = await analizar(filtro: const FiltroPatrimonio(soloPendientes: true));
      expect(soloPendientes.renglones, hasLength(1));
      expect(soloPendientes.recuperados, 0, reason: 'el recuperado quedó fuera del filtro y del KPI');

      final conDescuento = await analizar(filtro: const FiltroPatrimonio(conDescuento: true));
      expect(conDescuento.renglones, hasLength(1));
      expect(conDescuento.importeDescuentos, 90000);

      final sinDescuento = await analizar(filtro: const FiltroPatrimonio(conDescuento: false));
      expect(sinDescuento.renglones, hasLength(1));
      expect(sinDescuento.importeDescuentos, 0);
    });

    test('el ranking de bajas ordena por bienes en riesgo', () async {
      final juan = await crearEmpleado();
      final pedro = await crearEmpleado();
      final autorizador = await crearEmpleado(administrativo: true);

      final resolucionesJuan = <ResolucionResguardo>[];
      for (var i = 0; i < 2; i++) {
        final bien = await crearBien('Bien juan $i');
        final asignacion = await asignar(juan.id, bien);
        resolucionesJuan.add(ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.noEntregado,
          motivoNoEntrega: MotivoNoEntregaResguardo.abandonoServicio,
          // Un bien no entregado por abandono SÍ genera costo: decidir
          // no cobrarlo exige motivo y autorizador (regla del dominio).
          autorizadorEmpleadoId: autorizador.id,
          motivoNoCobro: 'Importe menor al costo de cobranza',
        ));
      }
      await conciliar(juan.id, resolucionesJuan);

      final bienPedro = await crearBien('Bien pedro');
      final asignacionPedro = await asignar(pedro.id, bienPedro);
      await conciliar(pedro.id, [
        ResolucionResguardo(
          asignacionId: asignacionPedro.id,
          resolucion: ResolucionResguardoBaja.devuelto,
          condicion: CondicionDevolucionResguardo.bueno,
          destino: DestinoDevolucionResguardo.inventarioDisponible,
        ),
      ]);

      final analisis = await analizar();
      expect(analisis.impactoPorBaja.first.empleadoId, juan.id);
      expect(analisis.impactoPorBaja.first.bienesPendientes, 2);
      expect(analisis.impactoPorBaja.first.valorComprometido, _costoArticulo * 2);
      expect(analisis.impactoPorBaja.last.bienesEnRiesgo, 0);
    });

    test('la serie mensual usa fechas reales de baja y no cuenta la misma baja dos veces', () async {
      final empleado = await crearEmpleado();
      final autorizador = await crearEmpleado(administrativo: true);
      final resoluciones = <ResolucionResguardo>[];
      for (var i = 0; i < 3; i++) {
        final bien = await crearBien('Bien $i');
        final asignacion = await asignar(empleado.id, bien);
        resoluciones.add(ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.noEntregado,
          motivoNoEntrega: MotivoNoEntregaResguardo.abandonoServicio,
          autorizadorEmpleadoId: autorizador.id,
          motivoNoCobro: 'Importe menor al costo de cobranza',
        ));
      }
      await conciliar(empleado.id, resoluciones);

      final analisis = await analizar();
      expect(analisis.serieMensual, hasLength(1));
      final punto = analisis.serieMensual.single;
      expect(punto.mes, DateTime(2026, 6));
      expect(punto.bajas, 1, reason: 'una baja con tres bienes sigue siendo UNA baja');
      expect(punto.pendientesGenerados, 3);
    });

    test('un rango que no cubre la baja devuelve el análisis vacío', () async {
      final empleado = await crearEmpleado();
      final bien = await crearBien('Radio');
      final asignacion = await asignar(empleado.id, bien);
      await conciliar(empleado.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.devuelto,
          condicion: CondicionDevolucionResguardo.bueno,
          destino: DestinoDevolucionResguardo.inventarioDisponible,
        ),
      ]);

      final fuera = await container.read(obtenerAnalisisPatrimonioUseCaseProvider).ejecutar(
            rango: RangoPeriodo(inicio: DateTime(2025, 1, 1), fin: DateTime(2025, 12, 31)),
          );
      expect(fuera.renglones, isEmpty);
      expect(fuera.bajasConciliadas, 0);
      expect(fuera.tasaRecuperacion.tasa, isNull);
    });
  });

  group('Valor aproximado', () {
    test('un bien sin costo capturado no vale 0: se cuenta como sin valor conocido', () async {
      final empleado = await crearEmpleado();

      // Artículo SIN movimiento de entrada con costo.
      final n = (++consecutivo).toString().padLeft(3, '0');
      final categoria = await db.into(db.categoriaArticulo).insertReturning(
            CategoriaArticuloCompanion.insert(nombre: 'Cat sin costo $n'),
          );
      final articulo = await ArticuloRepositoryImpl(db).crear(
        folio: 'ART-SC-$n',
        categoriaId: categoria.id,
        nombre: 'Sin costo',
        manejaVariante: false,
        manejaSerie: true,
      );
      final unidad = await db.into(db.articuloUnidad).insertReturning(
            ArticuloUnidadCompanion.insert(articuloId: articulo.id, codigo: 'UNI-SC-$n', numeroSerie: 'SC-$n'),
          );
      await db.into(db.movimientoInventario).insert(
            MovimientoInventarioCompanion.insert(
              articuloId: articulo.id,
              unidadId: Value(unidad.id),
              tipoMovimiento: TipoMovimientoInventario.entrada.name,
              cantidad: 1,
              fecha: DateTime(2026, 1, 10),
            ),
          );
      final asignacion = await asignar(empleado.id, (articuloId: articulo.id, unidadId: unidad.id));
      final autorizador = await crearEmpleado(administrativo: true);

      await conciliar(empleado.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.noEntregado,
          motivoNoEntrega: MotivoNoEntregaResguardo.abandonoServicio,
          autorizadorEmpleadoId: autorizador.id,
          motivoNoCobro: 'Bien sin costo capturado',
        ),
      ]);

      final analisis = await analizar();
      expect(analisis.renglones.single.valorAproximado, isNull);
      expect(analisis.bienesSinValorConocido, 1);
      expect(analisis.valorEsParcial, isTrue, reason: 'la pantalla debe advertir que el valor es parcial');
      expect(analisis.valorPendiente, 0, reason: 'no se inventa un valor para poder sumar');
    });
  });
  group('Servicio histórico — sólo por vigencia real', () {
    /// Una baja sencilla, para colgarle la adscripción que toque.
    Future<({String empleadoId, String asignacionId})> bajaConUnBien() async {
      final empleado = await crearEmpleado();
      final radio = await crearBien('Radio');
      final asignacion = await asignar(empleado.id, radio);
      return (empleadoId: empleado.id, asignacionId: asignacion.id);
    }

    Future<void> conciliarPerdido(({String empleadoId, String asignacionId}) baja) async {
      await conciliar(baja.empleadoId, [
        ResolucionResguardo(
          asignacionId: baja.asignacionId,
          resolucion: ResolucionResguardoBaja.perdido,
          generaDescuento: true,
          importeDescuento: 50000,
          conceptoDescuento: 'Radio extraviado',
        ),
      ]);
    }

    test('una sola asignación vigente en la fecha de baja: ese es el servicio', () async {
      final baja = await bajaConUnBien();
      final servicio = await crearServicio('Vigilancia Sportium Toluca');
      await adscribir(baja.empleadoId, servicio.id, inicio: DateTime(2026, 1, 1));
      await conciliarPerdido(baja);

      final analisis = await analizar();
      final renglon = analisis.renglones.single;

      expect(renglon.servicioHistorico.estado, EstadoServicioHistorico.resuelto);
      expect(renglon.servicioHistorico.servicioId, servicio.id);
      expect(renglon.servicioHistorico.nombre, 'Vigilancia Sportium Toluca');
    });

    test('la conciliación cierra la adscripción en la fecha de baja y AUN ASÍ la resuelve', () async {
      final baja = await bajaConUnBien();
      final servicio = await crearServicio('Rondín Metepec');
      await adscribir(baja.empleadoId, servicio.id, inicio: DateTime(2026, 1, 1));
      await conciliarPerdido(baja);

      // `EmpleadoRepositoryImpl` cierra la AsignacionServicio con
      // fechaTermino = fechaBaja. Si el límite superior no fuera
      // inclusivo, TODA baja quedaría sin servicio.
      final adscripciones =
          await container.read(asignacionServicioRepositoryProvider).listarPorEmpleado(baja.empleadoId);
      expect(adscripciones.single.fechaTermino, isNotNull);

      final analisis = await analizar();
      expect(analisis.renglones.single.servicioHistorico.servicioId, servicio.id);
    });

    test('sin ninguna asignación: «sin servicio histórico resoluble», no un servicio inventado', () async {
      final baja = await bajaConUnBien();
      await conciliarPerdido(baja);

      final analisis = await analizar();
      final servicio = analisis.renglones.single.servicioHistorico;

      expect(servicio.estado, EstadoServicioHistorico.sinAsignacion);
      expect(servicio.servicioId, isNull);
      expect(servicio.nombre, isNull);
    });

    test('dos asignaciones históricas NO solapadas: gana la que cubre la fecha de baja', () async {
      final baja = await bajaConUnBien();
      final anterior = await crearServicio('Servicio anterior');
      final vigente = await crearServicio('Servicio al momento de la baja');
      final posterior = await crearServicio('Servicio posterior a la baja');
      // La anterior terminó ANTES de la baja (15/06/2026); la vigente la
      // cubre; y la posterior, sembrada después de conciliar, empieza
      // más tarde pero es la MÁS RECIENTE por fechaInicio: si alguien
      // resolviera 'la última conocida', ganaría ésta.
      await adscribir(baja.empleadoId, anterior.id, inicio: DateTime(2026, 1, 1), termino: DateTime(2026, 3, 31));
      await adscribir(baja.empleadoId, vigente.id, inicio: DateTime(2026, 4, 1), termino: DateTime(2026, 12, 31));
      await conciliarPerdido(baja);
      await adscribir(baja.empleadoId, posterior.id, inicio: DateTime(2026, 10, 1));

      final analisis = await analizar();
      final servicio = analisis.renglones.single.servicioHistorico;

      expect(servicio.estado, EstadoServicioHistorico.resuelto);
      expect(servicio.servicioId, vigente.id, reason: 'nunca la más reciente ni la actual: la que cubre la fecha');
      expect(servicio.nombre, 'Servicio al momento de la baja');
    });

    test('una baja anterior a toda adscripción tampoco se cuelga de la primera que haya', () async {
      final baja = await bajaConUnBien();
      final posterior = await crearServicio('Servicio que empezó después');
      // La adscripción se siembra DESPUÉS de conciliar, a propósito: el
      // dominio de Personal —con razón— no deja dar de baja a alguien
      // cuya asignación empieza después de la baja. Lo que se prueba
      // aquí es sólo el resolvedor ante ese dato: una vigencia que
      // empieza el 01/09/2026 no cubre una baja del 15/06/2026.
      await conciliarPerdido(baja);
      await adscribir(baja.empleadoId, posterior.id, inicio: DateTime(2026, 9, 1));

      final analisis = await analizar();
      expect(analisis.renglones.single.servicioHistorico.estado, EstadoServicioHistorico.sinAsignacion);
    });

    test('dos asignaciones SOLAPADAS en la fecha de baja: inconsistencia, no una elegida a dedo', () async {
      final baja = await bajaConUnBien();
      final uno = await crearServicio('Servicio A');
      final dos = await crearServicio('Servicio B');
      await adscribir(baja.empleadoId, uno.id, inicio: DateTime(2026, 1, 1), termino: DateTime(2026, 12, 31));
      await adscribir(baja.empleadoId, dos.id, inicio: DateTime(2026, 5, 1), termino: DateTime(2026, 12, 31));
      await conciliarPerdido(baja);

      final analisis = await analizar();
      final servicio = analisis.renglones.single.servicioHistorico;

      expect(servicio.estado, EstadoServicioHistorico.inconsistente);
      expect(servicio.candidatos, 2);
      expect(servicio.servicioId, isNull, reason: 'elegir una sería arbitrario');
      expect(servicio.nombre, isNull);

      // El ranking lo expone como su propio renglón, sin repartirlo.
      final fila = analisis.problemasPorServicio.single;
      expect(fila.estado, EstadoServicioHistorico.inconsistente);
      expect(fila.servicioId, isNull);
      expect(fila.bajas, 1);
    });

    test('el ranking por servicio suma exactamente lo mismo que los KPI', () async {
      final servicio = await crearServicio('Vigilancia Norte');

      final conServicio = await crearEmpleado();
      final radio = await crearBien('Radio');
      final asignacionRadio = await asignar(conServicio.id, radio);
      await adscribir(conServicio.id, servicio.id, inicio: DateTime(2026, 1, 1));
      await conciliar(conServicio.id, [
        ResolucionResguardo(
          asignacionId: asignacionRadio.id,
          resolucion: ResolucionResguardoBaja.noEntregado,
          motivoNoEntrega: MotivoNoEntregaResguardo.abandonoServicio,
          generaDescuento: true,
          importeDescuento: 70000,
          conceptoDescuento: 'Radio no entregado',
        ),
      ]);

      final sinServicio = await crearEmpleado();
      final lampara = await crearBien('Lámpara');
      final asignacionLampara = await asignar(sinServicio.id, lampara);
      await conciliar(sinServicio.id, [
        ResolucionResguardo(
          asignacionId: asignacionLampara.id,
          resolucion: ResolucionResguardoBaja.perdido,
          generaDescuento: true,
          importeDescuento: 30000,
          conceptoDescuento: 'Lámpara extraviada',
        ),
      ]);

      final analisis = await analizar();
      final ranking = analisis.problemasPorServicio;

      expect(ranking, hasLength(2));
      // El servicio resuelto primero; lo no resoluble nunca encabeza.
      expect(ranking.first.estado, EstadoServicioHistorico.resuelto);
      expect(ranking.last.estado, EstadoServicioHistorico.sinAsignacion);

      expect(ranking.fold<int>(0, (a, s) => a + s.bajas), analisis.bajasConciliadas);
      expect(ranking.fold<int>(0, (a, s) => a + s.pendientes), analisis.pendientes);
      expect(ranking.fold<int>(0, (a, s) => a + s.perdidos), analisis.perdidos);
      expect(ranking.fold<int>(0, (a, s) => a + s.importeDescuentos), analisis.importeDescuentos);
    });

    test('filtrar por servicio deja sólo lo adscrito a ese servicio, nunca lo no resoluble', () async {
      final servicio = await crearServicio('Vigilancia Norte');

      final conServicio = await crearEmpleado();
      final radio = await crearBien('Radio');
      final asignacionRadio = await asignar(conServicio.id, radio);
      await adscribir(conServicio.id, servicio.id, inicio: DateTime(2026, 1, 1));
      await conciliar(conServicio.id, [
        ResolucionResguardo(
          asignacionId: asignacionRadio.id,
          resolucion: ResolucionResguardoBaja.perdido,
          generaDescuento: true,
          importeDescuento: 70000,
          conceptoDescuento: 'Radio extraviado',
        ),
      ]);

      final sinServicio = await crearEmpleado();
      final lampara = await crearBien('Lámpara');
      final asignacionLampara = await asignar(sinServicio.id, lampara);
      await conciliar(sinServicio.id, [
        ResolucionResguardo(
          asignacionId: asignacionLampara.id,
          resolucion: ResolucionResguardoBaja.perdido,
          generaDescuento: true,
          importeDescuento: 30000,
          conceptoDescuento: 'Lámpara extraviada',
        ),
      ]);

      final filtrado = await analizar(filtro: FiltroPatrimonio(servicioId: servicio.id));

      expect(filtrado.renglones, hasLength(1));
      expect(filtrado.renglones.single.empleadoNombre, contains('Prueba'));
      expect(filtrado.renglones.single.servicioHistorico.servicioId, servicio.id);
      expect(filtrado.importeDescuentos, 70000, reason: 'el KPI se recalcula sobre el subconjunto');
      expect(
        filtrado.renglones.every((r) => r.servicioHistorico.esResuelto),
        isTrue,
        reason: 'una baja sin servicio resoluble jamás cae dentro de un servicio por descarte',
      );
    });
  });

  group('Catálogos de filtros — no se recortan por el resultado filtrado', () {
    /// Dos bajas distintas, con dos autorizadores y dos servicios.
    Future<({String empleadoUno, String autorizadorUno, String servicioUno})> sembrarDosBajas() async {
      final servicioUno = await crearServicio('Servicio Uno');
      final servicioDos = await crearServicio('Servicio Dos');
      final autorizadorUno = await crearEmpleado(administrativo: true);
      final autorizadorDos = await crearEmpleado(administrativo: true);

      final uno = await crearEmpleado();
      final bienUno = await crearBien('Radio');
      final asignacionUno = await asignar(uno.id, bienUno);
      await adscribir(uno.id, servicioUno.id, inicio: DateTime(2026, 1, 1));
      await conciliar(uno.id, [
        ResolucionResguardo(
          asignacionId: asignacionUno.id,
          resolucion: ResolucionResguardoBaja.perdido,
          autorizadorEmpleadoId: autorizadorUno.id,
          motivoNoCobro: 'Radio al final de su vida útil',
        ),
      ]);

      final dos = await crearEmpleado();
      final bienDos = await crearBien('Lámpara');
      final asignacionDos = await asignar(dos.id, bienDos);
      await adscribir(dos.id, servicioDos.id, inicio: DateTime(2026, 1, 1));
      await conciliar(dos.id, [
        ResolucionResguardo(
          asignacionId: asignacionDos.id,
          resolucion: ResolucionResguardoBaja.perdido,
          autorizadorEmpleadoId: autorizadorDos.id,
          motivoNoCobro: 'Lámpara al final de su vida útil',
        ),
      ]);

      return (empleadoUno: uno.id, autorizadorUno: autorizadorUno.id, servicioUno: servicioUno.id);
    }

    test('el catálogo sale del periodo SIN filtrar: filtrar por una persona no lo deja con una sola opción',
        () async {
      final sembrado = await sembrarDosBajas();

      final completo = await analizar();
      expect(completo.catalogo.empleados, hasLength(2));
      expect(completo.catalogo.autorizadores, hasLength(2));
      expect(completo.catalogo.servicios, hasLength(2));

      final porEmpleado = await analizar(filtro: FiltroPatrimonio(empleadoId: sembrado.empleadoUno));
      expect(porEmpleado.renglones, hasLength(1), reason: 'el RESULTADO sí se recorta');
      expect(porEmpleado.catalogo.empleados, hasLength(2), reason: 'el CATÁLOGO no: si no, no se podría cambiar');
      expect(porEmpleado.catalogo.autorizadores, hasLength(2));
      expect(porEmpleado.catalogo.servicios, hasLength(2));
    });

    test('tampoco se recorta al filtrar por autorizador ni por servicio', () async {
      final sembrado = await sembrarDosBajas();

      final porAutorizador = await analizar(filtro: FiltroPatrimonio(autorizadorId: sembrado.autorizadorUno));
      expect(porAutorizador.renglones, hasLength(1));
      expect(porAutorizador.catalogo.autorizadores, hasLength(2));
      expect(porAutorizador.catalogo.empleados, hasLength(2));

      final porServicio = await analizar(filtro: FiltroPatrimonio(servicioId: sembrado.servicioUno));
      expect(porServicio.renglones, hasLength(1));
      expect(porServicio.catalogo.servicios, hasLength(2));
    });

    test('combinar filtros sigue recalculando todo sobre la intersección, con el catálogo intacto', () async {
      final sembrado = await sembrarDosBajas();

      final coincide = await analizar(
        filtro: FiltroPatrimonio(
          empleadoId: sembrado.empleadoUno,
          autorizadorId: sembrado.autorizadorUno,
          servicioId: sembrado.servicioUno,
          resolucion: ResolucionResguardoBaja.perdido,
        ),
      );
      expect(coincide.renglones, hasLength(1));
      expect(coincide.perdidos, 1);
      expect(coincide.problemasPorServicio, hasLength(1));

      // Combinación imposible: la persona 1 con el autorizador de la 2.
      final sembrado2 = sembrado;
      final vacia = await analizar(
        filtro: FiltroPatrimonio(
          empleadoId: sembrado2.empleadoUno,
          resolucion: ResolucionResguardoBaja.devuelto,
        ),
      );
      expect(vacia.renglones, isEmpty);
      expect(vacia.problemasPorServicio, isEmpty);
      expect(vacia.catalogo.empleados, hasLength(2),
          reason: 'aunque no haya resultados, el filtro se tiene que poder cambiar');
    });

    test('el catálogo de personas trae el puesto cuando se puede resolver', () async {
      final puesto = await db.into(db.puesto).insertReturning(
            PuestoCompanion.insert(
              codigo: 'PUE-TEST',
              nombre: 'Guardia de seguridad',
              areaId: SeedIds.areaOperaciones,
              tipo: TipoPuesto.operativo.name,
              nivelJerarquico: 1,
            ),
          );
      final empleado = await crearEmpleado();
      await (db.update(db.empleado)..where((t) => t.id.equals(empleado.id)))
          .write(EmpleadoCompanion(puestoId: Value(puesto.id)));

      final radio = await crearBien('Radio');
      final asignacion = await asignar(empleado.id, radio);
      await conciliar(empleado.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.perdido,
          generaDescuento: true,
          importeDescuento: 10000,
          conceptoDescuento: 'Radio extraviado',
        ),
      ]);

      final analisis = await analizar();
      final opcion = analisis.catalogo.empleados.single;
      expect(opcion.puesto, 'Guardia de seguridad');
      expect(opcion.etiqueta, contains('Guardia de seguridad'));
    });
  });
  group('Valuación por variante — la talla real del resguardo', () {
    /// Un artículo POR CANTIDAD con dos tallas de costo muy distinto.
    ///
    /// $50 y $300: si alguien volviera al promedio global del artículo,
    /// ambos bienes valdrían $175 y ninguno sería correcto.
    Future<({String articuloId, String tallaA, String tallaB})> crearArticuloConTallas() async {
      final n = (++consecutivo).toString().padLeft(3, '0');
      final categoria = await db.into(db.categoriaArticulo).insertReturning(
            CategoriaArticuloCompanion.insert(nombre: 'Uniformes $n'),
          );
      final articulo = await ArticuloRepositoryImpl(db).crear(
        folio: 'ARV-$n',
        categoriaId: categoria.id,
        nombre: 'Camisola con talla',
        manejaVariante: true,
        manejaSerie: false,
      );
      final repo = ArticuloRepositoryImpl(db);
      final chica = await repo.crearVariante(articuloId: articulo.id, valor: 'Chica');
      final grande = await repo.crearVariante(articuloId: articulo.id, valor: 'Grande');

      await db.into(db.movimientoInventario).insert(
            MovimientoInventarioCompanion.insert(
              articuloId: articulo.id,
              varianteId: Value(chica.id),
              tipoMovimiento: TipoMovimientoInventario.entrada.name,
              cantidad: 10,
              costoUnitario: const Value(5000),
              fecha: DateTime(2026, 1, 10),
            ),
          );
      await db.into(db.movimientoInventario).insert(
            MovimientoInventarioCompanion.insert(
              articuloId: articulo.id,
              varianteId: Value(grande.id),
              tipoMovimiento: TipoMovimientoInventario.entrada.name,
              cantidad: 10,
              costoUnitario: const Value(30000),
              fecha: DateTime(2026, 1, 10),
            ),
          );

      return (articuloId: articulo.id, tallaA: chica.id, tallaB: grande.id);
    }

    Future<AsignacionData> asignarTalla(String empleadoId, String articuloId, String varianteId) {
      return container.read(asignacionRepositoryProvider).crear(
            articuloId: articuloId,
            varianteId: varianteId,
            cantidad: 1,
            empleadoId: empleadoId,
            fechaEntrega: DateTime(2026, 2, 1),
          );
    }

    test('dos tallas del mismo artículo se valúan cada una con SU costo, nunca con el promedio', () async {
      final prenda = await crearArticuloConTallas();
      final empleado = await crearEmpleado();
      final chica = await asignarTalla(empleado.id, prenda.articuloId, prenda.tallaA);
      final grande = await asignarTalla(empleado.id, prenda.articuloId, prenda.tallaB);

      await conciliar(empleado.id, [
        ResolucionResguardo(
          asignacionId: chica.id,
          resolucion: ResolucionResguardoBaja.perdido,
          generaDescuento: true,
          importeDescuento: 5000,
          conceptoDescuento: 'Camisola chica extraviada',
        ),
        ResolucionResguardo(
          asignacionId: grande.id,
          resolucion: ResolucionResguardoBaja.perdido,
          generaDescuento: true,
          importeDescuento: 30000,
          conceptoDescuento: 'Camisola grande extraviada',
        ),
      ]);

      final analisis = await analizar();
      final porTalla = {
        for (final r in analisis.renglones) r.renglon.asignacionId!: r.valorAproximado,
      };

      expect(porTalla[chica.id], 5000, reason: 'la talla chica vale lo que costó la talla chica');
      expect(porTalla[grande.id], 30000, reason: 'la talla grande vale lo que costó la talla grande');
      expect(porTalla.values, isNot(contains(17500)),
          reason: 'el promedio global del artículo no describe a ninguna de las dos');

      expect(analisis.bienesSinValorConocido, 0, reason: 'las dos tallas son resolubles');
      expect(analisis.valorEsParcial, isFalse);
      expect(analisis.valorPerdido, 35000, reason: '5000 + 30000, no 17500 x 2');
    });

    test('un bien serializado de un artículo con tallas sigue SIN valor conocido', () async {
      // `Asignacion` tiene CHECK (variante_id IS NULL OR unidad_id IS
      // NULL) y `ArticuloUnidad` no guarda variante: en un resguardo por
      // número de serie la talla no existe en ninguna parte. No se
      // inventa — se declara desconocida.
      final n = (++consecutivo).toString().padLeft(3, '0');
      final categoria = await db.into(db.categoriaArticulo).insertReturning(
            CategoriaArticuloCompanion.insert(nombre: 'Mixtos $n'),
          );
      final repo = ArticuloRepositoryImpl(db);
      final articulo = await repo.crear(
        folio: 'ARM-$n',
        categoriaId: categoria.id,
        nombre: 'Chaleco con talla y número de serie',
        manejaVariante: true,
        manejaSerie: true,
      );
      final talla = await repo.crearVariante(articuloId: articulo.id, valor: 'Grande');
      await db.into(db.movimientoInventario).insert(
            MovimientoInventarioCompanion.insert(
              articuloId: articulo.id,
              varianteId: Value(talla.id),
              tipoMovimiento: TipoMovimientoInventario.entrada.name,
              cantidad: 5,
              costoUnitario: const Value(88000),
              fecha: DateTime(2026, 1, 10),
            ),
          );
      final unidad = await db.into(db.articuloUnidad).insertReturning(
            ArticuloUnidadCompanion.insert(articuloId: articulo.id, codigo: 'UNV-$n', numeroSerie: 'SV-$n'),
          );

      final empleado = await crearEmpleado();
      final asignacion = await container.read(asignacionRepositoryProvider).crear(
            articuloId: articulo.id,
            unidadId: unidad.id,
            cantidad: 1,
            empleadoId: empleado.id,
            fechaEntrega: DateTime(2026, 2, 1),
          );
      expect(asignacion.varianteId, isNull, reason: 'variante y unidad son excluyentes por CHECK');

      await conciliar(empleado.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.perdido,
          generaDescuento: true,
          importeDescuento: 88000,
          conceptoDescuento: 'Chaleco extraviado',
        ),
      ]);

      final analisis = await analizar();
      expect(analisis.renglones.single.valorAproximado, isNull);
      expect(analisis.bienesSinValorConocido, 1);
      expect(analisis.valorEsParcial, isTrue, reason: 'la pantalla tiene que advertir que el valor es parcial');
      expect(analisis.valorPerdido, 0, reason: 'no se inventa un valor para poder sumar');
    });

    test('una talla sin costo capturado tampoco se rescata con el promedio del artículo', () async {
      final n = (++consecutivo).toString().padLeft(3, '0');
      final categoria = await db.into(db.categoriaArticulo).insertReturning(
            CategoriaArticuloCompanion.insert(nombre: 'Uniformes $n'),
          );
      final repo = ArticuloRepositoryImpl(db);
      final articulo = await repo.crear(
        folio: 'ARS-$n',
        categoriaId: categoria.id,
        nombre: 'Pantalón con talla',
        manejaVariante: true,
        manejaSerie: false,
      );
      final conCosto = await repo.crearVariante(articuloId: articulo.id, valor: 'Chica');
      final sinCosto = await repo.crearVariante(articuloId: articulo.id, valor: 'Extra grande');
      await db.into(db.movimientoInventario).insert(
            MovimientoInventarioCompanion.insert(
              articuloId: articulo.id,
              varianteId: Value(conCosto.id),
              tipoMovimiento: TipoMovimientoInventario.entrada.name,
              cantidad: 4,
              costoUnitario: const Value(6000),
              fecha: DateTime(2026, 1, 10),
            ),
          );
      // La talla extra grande entró SIN costo capturado.
      await db.into(db.movimientoInventario).insert(
            MovimientoInventarioCompanion.insert(
              articuloId: articulo.id,
              varianteId: Value(sinCosto.id),
              tipoMovimiento: TipoMovimientoInventario.entrada.name,
              cantidad: 4,
              fecha: DateTime(2026, 1, 10),
            ),
          );

      final empleado = await crearEmpleado();
      final asignacion = await asignarTalla(empleado.id, articulo.id, sinCosto.id);
      await conciliar(empleado.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.perdido,
          generaDescuento: true,
          importeDescuento: 6000,
          conceptoDescuento: 'Pantalón extraviado',
        ),
      ]);

      final analisis = await analizar();
      expect(analisis.renglones.single.valorAproximado, isNull,
          reason: 'la talla asignada no tiene costo; la otra talla no la representa');
      expect(analisis.bienesSinValorConocido, 1);
    });

    test('un costo suelto a nivel de artículo NO rescata a una talla sin costo', () async {
      final n = (++consecutivo).toString().padLeft(3, '0');
      final categoria = await db.into(db.categoriaArticulo).insertReturning(
            CategoriaArticuloCompanion.insert(nombre: 'Uniformes $n'),
          );
      final repo = ArticuloRepositoryImpl(db);
      final articulo = await repo.crear(
        folio: 'ARR-$n',
        categoriaId: categoria.id,
        nombre: 'Camisola con talla',
        manejaVariante: true,
        manejaSerie: false,
      );
      final talla = await repo.crearVariante(articuloId: articulo.id, valor: 'Extra grande');

      // Dato hostil a propósito: una entrada del artículo SIN
      // `varianteId`. El dominio de escritura lo impide
      // (`VarianteInvalidaException`), pero si alguna vez existiera, el
      // reporte no puede usarla para valuar una talla — ese número no
      // describe a esta prenda. Se siembra en crudo justo para eso.
      await db.into(db.movimientoInventario).insert(
            MovimientoInventarioCompanion.insert(
              articuloId: articulo.id,
              tipoMovimiento: TipoMovimientoInventario.entrada.name,
              cantidad: 1,
              costoUnitario: const Value(99900),
              fecha: DateTime(2026, 1, 10),
            ),
          );

      final empleado = await crearEmpleado();
      final asignacion = await asignarTalla(empleado.id, articulo.id, talla.id);
      await conciliar(empleado.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.perdido,
          generaDescuento: true,
          importeDescuento: 10000,
          conceptoDescuento: 'Camisola extraviada',
        ),
      ]);

      final analisis = await analizar();

      expect(analisis.renglones.single.valorAproximado, isNull,
          reason: 'sin costo de ESA talla, el valor es desconocido — nunca el del artículo');
      expect(analisis.valorPerdido, isNot(99900));
      expect(analisis.bienesSinValorConocido, 1);
    });

    test('conteo del dataset mixto: qué se recupera y qué sigue desconocido', () async {
      // Tres bienes de artículos CON tallas:
      //   1. talla chica, con costo      -> resoluble\$
      //   2. talla grande, con costo     -> resoluble\$
      //   3. serializado (sin variante)  -> desconocido
      final prenda = await crearArticuloConTallas();
      final empleado = await crearEmpleado();
      final chica = await asignarTalla(empleado.id, prenda.articuloId, prenda.tallaA);
      final grande = await asignarTalla(empleado.id, prenda.articuloId, prenda.tallaB);
      // Y un bien normal sin tallas, que ya se valuaba bien.
      final radio = await crearBien('Radio');
      final asignacionRadio = await asignar(empleado.id, radio);

      await conciliar(empleado.id, [
        ResolucionResguardo(
          asignacionId: chica.id,
          resolucion: ResolucionResguardoBaja.perdido,
          generaDescuento: true,
          importeDescuento: 5000,
          conceptoDescuento: 'Camisola chica',
        ),
        ResolucionResguardo(
          asignacionId: grande.id,
          resolucion: ResolucionResguardoBaja.perdido,
          generaDescuento: true,
          importeDescuento: 30000,
          conceptoDescuento: 'Camisola grande',
        ),
        ResolucionResguardo(
          asignacionId: asignacionRadio.id,
          resolucion: ResolucionResguardoBaja.perdido,
          generaDescuento: true,
          importeDescuento: 20000,
          conceptoDescuento: 'Radio',
        ),
      ]);

      final analisis = await analizar();
      final conValor = analisis.renglones.where((r) => r.valorAproximado != null).toList();

      expect(analisis.renglones, hasLength(3));
      expect(conValor, hasLength(3), reason: 'los tres tienen costo resoluble');
      expect(analisis.bienesSinValorConocido, 0);
      // 5000 (chica) + 30000 (grande) + 20000 (radio).
      expect(analisis.valorPerdido, 55000);
    });
  });
}