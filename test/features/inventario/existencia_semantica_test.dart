// Mini-etapa "Corrección semántica de existencia de inventario".
//
// El defecto: `ExistenciaArticulo.total` documentaba que "una baja es la
// única operación que reduce el total real", pero el getter también
// dejaba fuera `enProceso`. Consecuencia: mandar una prenda a la
// tintorería la borraba del inventario —y de su valor— hasta que
// volviera, como si RISEG hubiera dejado de ser su dueña por estar en
// lavado.
//
// Estas pruebas fijan los TRES conceptos por separado:
//
//  - Existencia real (propiedad): sube con la entrada, baja SOLO con la
//    baja real.
//  - Disponibilidad: subconjunto estricto; lavandería/reparación/
//    pendiente de desecho salen de aquí y siguen dentro de existencia.
//  - Baja real: `RegistrarBajaUnidadUseCase`, nunca `pendienteDesecho`.
//
// Se ejercitan los consumidores REALES (Inventario, Reportes,
// Dashboard) a través de sus providers, no un getter aislado: el riesgo
// que se quiere cubrir es que un módulo siga con la fórmula vieja.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart';
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart';
import 'package:riseg_one/features/inventario/data/tables/movimiento_inventario_table.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_baja_unidad_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_retorno_unidad_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/validar_linea_asignacion.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';
import 'package:riseg_one/features/inventario/presentation/articulos/articulos_controller.dart';
import 'package:riseg_one/features/inventario/presentation/reportes/reportes_controller.dart';
import 'package:riseg_one/features/reportes/reportes_providers.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/asociar_equipo_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentStorageProvider;
import 'package:riseg_one/features/telefonia/telefonia_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

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

/// Costo unitario de cada unidad sembrada: $150.00.
const _costoUnitario = 15000;

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  var consecutivo = 0;

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
      // El Dashboard lee `documentoPorEmitirRepositoryProvider`, que
      // depende de `path_provider` (no disponible bajo `flutter test`) —
      // mismo override que ya usan las pruebas de Dashboard y Agenda.
      attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
    ]);
    consecutivo = 0;
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  /// Un artículo serializado con [unidades] unidades disponibles, cada
  /// una con costo capturado (para poder valuar el inventario).
  Future<({String articuloId, List<String> unidadIds})> crearArticuloConUnidades({int unidades = 3}) async {
    final n = (++consecutivo).toString().padLeft(3, '0');
    final categoria = await db.into(db.categoriaArticulo).insertReturning(
          CategoriaArticuloCompanion.insert(nombre: 'Uniformes $n'),
        );
    final articulo = await ArticuloRepositoryImpl(db).crear(
      folio: 'ART-$n',
      categoriaId: categoria.id,
      nombre: 'Camisola $n',
      manejaVariante: false,
      manejaSerie: true,
    );

    final ids = <String>[];
    for (var i = 0; i < unidades; i++) {
      final unidad = await db.into(db.articuloUnidad).insertReturning(
            ArticuloUnidadCompanion.insert(
              articuloId: articulo.id,
              codigo: 'UNI-$n-$i',
              numeroSerie: 'S-$n-$i',
            ),
          );
      await db.into(db.movimientoInventario).insert(
            MovimientoInventarioCompanion.insert(
              articuloId: articulo.id,
              unidadId: Value(unidad.id),
              tipoMovimiento: TipoMovimientoInventario.entrada.name,
              cantidad: 1,
              costoUnitario: const Value(_costoUnitario),
              fecha: DateTime(2026, 1, 10),
            ),
          );
      ids.add(unidad.id);
    }
    return (articuloId: articulo.id, unidadIds: ids);
  }

  Future<EmpleadoData> crearEmpleado() async {
    final n = (++consecutivo).toString().padLeft(2, '0');
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: consecutivo,
            nombres: 'Empleado',
            apellidoPaterno: 'De prueba $n',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'CUXA900101HDFXXX$n',
            rfc: 'CUXA900101A$n',
            nss: '1234567$n',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2024, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
  }

  /// Asigna [unidadId] a un empleado nuevo y devuelve la asignación.
  Future<AsignacionData> asignar(String articuloId, String unidadId) async {
    final empleado = await crearEmpleado();
    return container.read(asignacionRepositoryProvider).crear(
          articuloId: articuloId,
          unidadId: unidadId,
          cantidad: 1,
          empleadoId: empleado.id,
          fechaEntrega: DateTime(2026, 2, 1),
        );
  }

  /// Cierra la asignación dejando la unidad en [ubicacion].
  ///
  /// Es el ÚNICO camino real para que una unidad llegue a lavandería o
  /// reparación: se recupera del empleado y se declara dónde queda. No
  /// existe (ni debe existir) un "mover a lavandería" suelto.
  Future<void> recuperarHacia(String asignacionId, EstatusArticuloUnidad ubicacion) async {
    await container.read(asignacionRepositoryProvider).cerrar(
          asignacionId: asignacionId,
          motivo: MotivoCierreAsignacion.desgaste.name,
          fechaCierre: DateTime(2026, 3, 1),
          ubicacionUnidad: ubicacion,
        );
  }

  Future<String> estatusDe(String unidadId) async {
    final unidad = await container.read(inventarioRepositoryProvider).obtenerUnidadPorId(unidadId);
    return unidad!.estatus;
  }

  Future<ExistenciaLeida> leerExistencia(String articuloId) async {
    final e = await container.read(inventarioRepositoryProvider).calcularExistenciaUnidades(articuloId);
    return ExistenciaLeida(total: e.total, disponible: e.disponible, asignado: e.asignado, enProceso: e.enProceso);
  }

  Future<bool> puedeAsignarse(String articuloId, String unidadId) async {
    final validacion = await validarLineaAsignacion(
      articuloRepository: container.read(articuloRepositoryProvider),
      inventarioRepository: container.read(inventarioRepositoryProvider),
      articuloId: articuloId,
      unidadId: unidadId,
      cantidad: 1,
    );
    return validacion is LineaAsignacionValida;
  }

  group('A. Lavandería — la existencia no se mueve, la disponibilidad sí', () {
    test('el ciclo completo disponible → lavandería → disponible no crea ni destruye existencia', () async {
      final articulo = await crearArticuloConUnidades(unidades: 3);
      final unidadId = articulo.unidadIds.first;

      final inicial = await leerExistencia(articulo.articuloId);
      expect(inicial.total, 3);
      expect(inicial.disponible, 3);

      final asignacion = await asignar(articulo.articuloId, unidadId);
      final asignada = await leerExistencia(articulo.articuloId);
      expect(asignada.total, 3, reason: 'asignar nunca cambió la existencia, y sigue sin cambiarla');
      expect(asignada.disponible, 2);

      await recuperarHacia(asignacion.id, EstatusArticuloUnidad.enLavanderia);

      final enLavanderia = await leerExistencia(articulo.articuloId);
      expect(await estatusDe(unidadId), EstatusArticuloUnidad.enLavanderia.name);
      expect(enLavanderia.total, 3, reason: 'LA CORRECCIÓN: la prenda sigue siendo de RISEG estando en la tintorería');
      expect(enLavanderia.disponible, 2, reason: 'pero no se puede entregar');
      expect(enLavanderia.enProceso, 1);
      expect(await puedeAsignarse(articulo.articuloId, unidadId), isFalse);

      final retorno = await container.read(registrarRetornoUnidadUseCaseProvider).ejecutar(
            unidadId: unidadId,
            desenlace: DesenlaceRetornoUnidad.disponible,
            fecha: DateTime(2026, 3, 10),
          );
      expect(retorno, isA<RegistrarRetornoUnidadExitoso>());

      final final_ = await leerExistencia(articulo.articuloId);
      expect(final_.total, 3, reason: 'el ciclo entero no movió la existencia ni una unidad');
      expect(final_.disponible, 3, reason: 'y vuelve a estar entregable');
      expect(final_.enProceso, 0);
      expect(await puedeAsignarse(articulo.articuloId, unidadId), isTrue);
    });
  });

  group('B. Reparación — sigue contando, no se puede reasignar', () {
    test('asignada → reparación → retorno, sin creación ni destrucción ficticia de stock', () async {
      final articulo = await crearArticuloConUnidades(unidades: 2);
      final unidadId = articulo.unidadIds.first;
      final asignacion = await asignar(articulo.articuloId, unidadId);

      await recuperarHacia(asignacion.id, EstatusArticuloUnidad.enReparacion);

      final enReparacion = await leerExistencia(articulo.articuloId);
      expect(await estatusDe(unidadId), EstatusArticuloUnidad.enReparacion.name);
      expect(enReparacion.total, 2);
      expect(enReparacion.enProceso, 1);
      expect(enReparacion.asignado, 0, reason: 'ya se recuperó del empleado');
      expect(await puedeAsignarse(articulo.articuloId, unidadId), isFalse);

      // Desenlace real: la reparación no sirvió y la unidad queda dañada.
      final retorno = await container.read(registrarRetornoUnidadUseCaseProvider).ejecutar(
            unidadId: unidadId,
            desenlace: DesenlaceRetornoUnidad.danado,
            fecha: DateTime(2026, 4, 1),
          );
      expect(retorno, isA<RegistrarRetornoUnidadExitoso>());

      final trasRetorno = await leerExistencia(articulo.articuloId);
      expect(trasRetorno.total, 2, reason: 'dañada sigue siendo propiedad de RISEG');
      expect(trasRetorno.enProceso, 0);
      expect(await puedeAsignarse(articulo.articuloId, unidadId), isFalse, reason: 'dañada tampoco es asignable');
    });
  });

  group('C. Pendiente de desecho — existe hasta que la baja real se ejecuta', () {
    test('pendienteDesecho cuenta en existencia; sólo RegistrarBajaUnidadUseCase la reduce', () async {
      final articulo = await crearArticuloConUnidades(unidades: 2);
      final unidadId = articulo.unidadIds.first;
      final asignacion = await asignar(articulo.articuloId, unidadId);

      await recuperarHacia(asignacion.id, EstatusArticuloUnidad.pendienteDesecho);

      final pendiente = await leerExistencia(articulo.articuloId);
      expect(await estatusDe(unidadId), EstatusArticuloUnidad.pendienteDesecho.name);
      expect(pendiente.total, 2, reason: 'decidir desecharla NO es haberla desechado');
      expect(pendiente.enProceso, 1);
      expect(await puedeAsignarse(articulo.articuloId, unidadId), isFalse);

      final baja = await container.read(registrarBajaUnidadUseCaseProvider).ejecutar(
            unidadId: unidadId,
            observaciones: 'Prenda al final de su vida útil, desechada',
          );
      expect(baja, isA<RegistrarBajaUnidadExitoso>());

      final trasBaja = await leerExistencia(articulo.articuloId);
      expect(await estatusDe(unidadId), EstatusArticuloUnidad.baja.name);
      expect(trasBaja.total, 1, reason: 'AHORA sí: la baja real es lo único que reduce la existencia');
      expect(trasBaja.enProceso, 0);
    });
  });

  group('D. Valuación — el activo no desaparece por ir a la tintorería', () {
    /// Valor del inventario según la pantalla de Reportes de Inventario.
    Future<int?> valorInventario() async {
      container.listen(reportesControllerProvider, (_, __) {}, fireImmediately: true);
      await container.read(reportesControllerProvider.notifier).reintentarCarga();
      return container.read(reportesControllerProvider).resumenValorInventario;
    }

    test('disponible → lavandería → disponible: el valor NO baja y vuelve a subir', () async {
      final articulo = await crearArticuloConUnidades(unidades: 3);
      final unidadId = articulo.unidadIds.first;

      final valorInicial = await valorInventario();
      expect(valorInicial, 3 * _costoUnitario);

      final asignacion = await asignar(articulo.articuloId, unidadId);
      await recuperarHacia(asignacion.id, EstatusArticuloUnidad.enLavanderia);

      expect(await valorInventario(), valorInicial,
          reason: 'antes el inventario perdía \$150 mientras la camisa estaba en lavado');

      await container.read(registrarRetornoUnidadUseCaseProvider).ejecutar(
            unidadId: unidadId,
            desenlace: DesenlaceRetornoUnidad.disponible,
            fecha: DateTime(2026, 3, 10),
          );
      expect(await valorInventario(), valorInicial, reason: 'y no hay un rebote artificial al regresar');
    });

    test('asignado → reparación: el valor tampoco se mueve', () async {
      final articulo = await crearArticuloConUnidades(unidades: 2);
      final valorInicial = await valorInventario();
      expect(valorInicial, 2 * _costoUnitario);

      final asignacion = await asignar(articulo.articuloId, articulo.unidadIds.first);
      expect(await valorInventario(), valorInicial, reason: 'asignar nunca cambió el valor');

      await recuperarHacia(asignacion.id, EstatusArticuloUnidad.enReparacion);
      expect(await valorInventario(), valorInicial);
    });

    test('la baja real SÍ se refleja, con la misma fórmula de valuación de siempre', () async {
      final articulo = await crearArticuloConUnidades(unidades: 2);
      final unidadId = articulo.unidadIds.first;
      final valorInicial = await valorInventario();

      final asignacion = await asignar(articulo.articuloId, unidadId);
      await recuperarHacia(asignacion.id, EstatusArticuloUnidad.pendienteDesecho);
      expect(await valorInventario(), valorInicial, reason: 'pendiente de desecho todavía vale');

      await container.read(registrarBajaUnidadUseCaseProvider).ejecutar(
            unidadId: unidadId,
            observaciones: 'Desechada',
          );
      expect(await valorInventario(), valorInicial! - _costoUnitario);
    });
  });

  group('E. No regresión — nada fuera de `disponible` se puede asignar', () {
    for (final estado in [
      EstatusArticuloUnidad.enLavanderia,
      EstatusArticuloUnidad.enReparacion,
      EstatusArticuloUnidad.pendienteDesecho,
    ]) {
      test('Inventario rechaza asignar una unidad en ${estado.name}', () async {
        final articulo = await crearArticuloConUnidades(unidades: 1);
        final unidadId = articulo.unidadIds.single;
        final asignacion = await asignar(articulo.articuloId, unidadId);
        await recuperarHacia(asignacion.id, estado);

        final validacion = await validarLineaAsignacion(
          articuloRepository: container.read(articuloRepositoryProvider),
          inventarioRepository: container.read(inventarioRepositoryProvider),
          articuloId: articulo.articuloId,
          unidadId: unidadId,
          cantidad: 1,
        );
        expect(validacion, isA<LineaAsignacionUnidadNoDisponible>());
      });

      test('Telefonía rechaza asociar un equipo en ${estado.name}', () async {
        // Telefonía consume la disponibilidad de `ArticuloUnidad`; sólo
        // se comprueba que sigue rechazando lo no disponible.
        final articulo = await crearArticuloConUnidades(unidades: 1);
        final unidadId = articulo.unidadIds.single;
        // Telefonía exige que la unidad esté dada de alta como equipo
        // telefónico antes de mirar su disponibilidad.
        await db.into(db.articuloUnidadTelefono).insert(ArticuloUnidadTelefonoCompanion.insert(unidadId: unidadId));
        final asignacion = await asignar(articulo.articuloId, unidadId);
        await recuperarHacia(asignacion.id, estado);

        final linea = await container.read(lineaTelefonicaRepositoryProvider).crear(
              codigo: 'LIN-${estado.index}',
              numero: '55100000${estado.index}',
              operador: 'telcel',
              modalidadSim: 'fisica',
            );

        final resultado = await container.read(asociarEquipoLineaTelefonicaUseCaseProvider).ejecutar(
              lineaTelefonicaId: linea.id,
              unidadId: unidadId,
              fechaInicio: DateTime(2026, 5, 1),
            );
        expect(resultado, isA<AsociarEquipoLineaTelefonicaUnidadNoDisponible>());
      });
    }
  });

  group('F. Consumidores — Inventario, Reportes y Dashboard alineados', () {
    test('las tres pantallas reportan la MISMA existencia durante la lavandería', () async {
      final articulo = await crearArticuloConUnidades(unidades: 4);
      final asignacion = await asignar(articulo.articuloId, articulo.unidadIds.first);
      await recuperarHacia(asignacion.id, EstatusArticuloUnidad.enLavanderia);

      // Inventario — listado de Artículos.
      container.listen(articulosControllerProvider, (_, __) {}, fireImmediately: true);
      await container.read(articulosControllerProvider.notifier).recargar();
      final inventario = container.read(articulosControllerProvider);
      expect(inventario.resumenUnidadesTotales, 4);
      expect(inventario.resumenUnidadesDisponibles, 3);
      expect(inventario.resumenUnidadesEnProceso, 1);
      expect(
        inventario.resumenUnidadesTotales,
        inventario.resumenUnidadesDisponibles +
            inventario.resumenUnidadesAsignadas +
            inventario.resumenUnidadesDanadasPerdidas +
            inventario.resumenUnidadesEnProceso,
        reason: 'el desglose visible tiene que sumar el total visible',
      );

      // Reportes — pestaña Operación (y el Dashboard, que consume el
      // mismo caso de uso).
      final reportes = await container.read(obtenerResumenInventarioUseCaseProvider).ejecutar();
      expect(reportes.existenciaTotal, 4, reason: 'Reportes no puede reportar una existencia distinta a Inventario');
      expect(reportes.valorAproximado, 4 * _costoUnitario);

      // Dashboard — cadena real de providers.
      container.listen(dashboardControllerProvider, (_, __) {}, fireImmediately: true);
      await container.read(dashboardControllerProvider.notifier).recargar();
      final dashboard = container.read(dashboardControllerProvider);
      expect(dashboard.resumenInventario?.existenciaTotal, 4);
      expect(dashboard.resumenInventario?.valorAproximado, 4 * _costoUnitario);
    });

    test('tras la baja real, las tres bajan a la vez', () async {
      final articulo = await crearArticuloConUnidades(unidades: 4);
      final unidadId = articulo.unidadIds.first;
      final asignacion = await asignar(articulo.articuloId, unidadId);
      await recuperarHacia(asignacion.id, EstatusArticuloUnidad.pendienteDesecho);
      await container.read(registrarBajaUnidadUseCaseProvider).ejecutar(
            unidadId: unidadId,
            observaciones: 'Desechada tras conciliación',
          );

      container.listen(articulosControllerProvider, (_, __) {}, fireImmediately: true);
      await container.read(articulosControllerProvider.notifier).recargar();
      expect(container.read(articulosControllerProvider).resumenUnidadesTotales, 3);

      final reportes = await container.read(obtenerResumenInventarioUseCaseProvider).ejecutar();
      expect(reportes.existenciaTotal, 3);
      expect(reportes.valorAproximado, 3 * _costoUnitario);

      container.listen(dashboardControllerProvider, (_, __) {}, fireImmediately: true);
      await container.read(dashboardControllerProvider.notifier).recargar();
      expect(container.read(dashboardControllerProvider).resumenInventario?.existenciaTotal, 3);
    });

    test('un artículo POR CANTIDAD no tiene estados intermedios y su total no cambia', () async {
      // La corrección sólo puede afectar a artículos serializados: la
      // ruta por cantidad nunca puebla `enProceso`.
      final categoria = await db.into(db.categoriaArticulo).insertReturning(
            CategoriaArticuloCompanion.insert(nombre: 'Consumibles'),
          );
      final articulo = await ArticuloRepositoryImpl(db).crear(
        folio: 'ART-CANT',
        categoriaId: categoria.id,
        nombre: 'Guantes',
        manejaVariante: false,
        manejaSerie: false,
      );
      await db.into(db.movimientoInventario).insert(
            MovimientoInventarioCompanion.insert(
              articuloId: articulo.id,
              tipoMovimiento: TipoMovimientoInventario.entrada.name,
              cantidad: 12,
              costoUnitario: const Value(1000),
              fecha: DateTime(2026, 1, 10),
            ),
          );

      final existencia = await container.read(inventarioRepositoryProvider).calcularExistencia(articuloId: articulo.id);
      expect(existencia.enProceso, 0);
      expect(existencia.total, 12);
      expect(existencia.total, existencia.disponible + existencia.asignado + existencia.danado + existencia.perdido);
    });
  });
}

/// Lectura plana de la existencia, para que las aserciones digan qué
/// cubeta se está mirando.
class ExistenciaLeida {
  const ExistenciaLeida({
    required this.total,
    required this.disponible,
    required this.asignado,
    required this.enProceso,
  });

  final int total;
  final int disponible;
  final int asignado;
  final int enProceso;
}
