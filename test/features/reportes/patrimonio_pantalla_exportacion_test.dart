// Reportes Etapa C — pantalla de Patrimonio y bajas: contenido real,
// permisos y exportación.
//
// El barrido de `reportes_responsive_tema_test.dart` sólo demuestra que
// la pestaña no desborda. Aquí se demuestra lo otro, que es lo que de
// verdad importa: que además **muestra algo**, que lo que muestra separa
// pendiente de perdido, que sin los dos permisos no muestra nada, y que
// el archivo exportado trae el MISMO universo que la pantalla.
//
// Las hojas del XLSX son proyecciones disjuntas del mismo conjunto: un
// bien está en "Pendientes" o en "Recuperados", nunca en las dos — si un
// día alguien las convierte en un join, estas pruebas lo detienen.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:riseg_one/app/app.dart';
import 'package:riseg_one/app/router/app_router.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/movimiento_inventario_table.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentStorageProvider;
import 'package:riseg_one/features/personal/data/tables/conciliacion_baja_table.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/conciliar_baja_empleado_usecase.dart';
import 'package:riseg_one/features/personal/personal_providers.dart';
import 'package:riseg_one/features/reportes/data/pdf/reporte_patrimonio_pdf_renderer.dart';
import 'package:riseg_one/features/reportes/data/xlsx/patrimonio_xlsx_renderer.dart';
import 'package:riseg_one/features/reportes/domain/analitica/comparacion_periodo.dart';
import 'package:riseg_one/features/reportes/domain/analitica/obtener_analisis_patrimonio_usecase.dart';
import 'package:riseg_one/features/reportes/domain/export/reporte_export_context.dart';
import 'package:riseg_one/features/reportes/reportes_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';
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

/// Sesión con permisos explícitos: sirve para probar que Patrimonio
/// exige **ambos** lados (Personal e Inventario) y no sólo uno.
class _SesionConPermisos extends SesionController {
  _SesionConPermisos(this._permisos);

  final Set<String> _permisos;

  @override
  SesionUsuario? build() => SesionUsuario(
        usuarioId: 'acotado',
        nombre: 'Usuario acotado',
        nombreUsuario: 'acotado',
        esMaestro: false,
        permisos: _permisos,
      );
}

/// Costo capturado de cada bien sembrado: $200.00.
const _costoBien = 20000;

/// Siembra una baja conciliada con los cuatro desenlaces que el pedido
/// exige no confundir, sobre la base [db].
///
/// Devuelve el contenedor ya desechado: sólo existe para poder invocar
/// la cadena real de conciliación (nunca se insertan renglones a mano).
Future<void> sembrarBajas(AppDatabase db, {required DateTime fechaBaja, bool conVehiculo = false}) async {
  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db),
    sesionControllerProvider.overrideWith(_SesionMaestro.new),
    attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
  ]);
  var n = 0;

  Future<EmpleadoData> crearEmpleado(String nombres, String apellido, {bool administrativo = false}) async {
    n++;
    final sufijo = n.toString().padLeft(2, '0');
    String? sucursalId;
    if (administrativo) {
      final sucursal = await db.into(db.sucursal).insertReturning(
            SucursalCompanion.insert(
              codigo: 'SUCX-$sufijo',
              nombre: 'Corporativo',
              tipoSucursalId: SeedIds.tipoSucursalOficinaAdministrativa,
            ),
          );
      sucursalId = sucursal.id;
    }
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: 500 + n,
            nombres: nombres,
            apellidoPaterno: apellido,
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'CUXA900101HDFXXX$sufijo',
            rfc: 'CUXA900101A$sufijo',
            nss: '1234567$sufijo',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(fechaBaja.year - 2, 1, 1),
            aniosExperienciaSeguridad: 3,
            sucursalId: Value(sucursalId),
          ),
        );
  }

  Future<({String articuloId, String unidadId})> crearBien(String nombre) async {
    n++;
    final sufijo = n.toString().padLeft(3, '0');
    final categoria = await db.into(db.categoriaArticulo).insertReturning(
          CategoriaArticuloCompanion.insert(nombre: 'Categoria $sufijo'),
        );
    final articulo = await ArticuloRepositoryImpl(db).crear(
      folio: 'ARX-$sufijo',
      categoriaId: categoria.id,
      nombre: nombre,
      manejaVariante: false,
      manejaSerie: true,
    );
    final unidad = await db.into(db.articuloUnidad).insertReturning(
          ArticuloUnidadCompanion.insert(articuloId: articulo.id, codigo: 'UNX-$sufijo', numeroSerie: 'SX-$sufijo'),
        );
    await db.into(db.movimientoInventario).insert(
          MovimientoInventarioCompanion.insert(
            articuloId: articulo.id,
            unidadId: Value(unidad.id),
            tipoMovimiento: TipoMovimientoInventario.entrada.name,
            cantidad: 1,
            costoUnitario: const Value(_costoBien),
            fecha: DateTime(fechaBaja.year, 1, 10),
          ),
        );
    return (articuloId: articulo.id, unidadId: unidad.id);
  }

  Future<String> asignar(String empleadoId, ({String articuloId, String unidadId}) bien) async {
    final asignacion = await container.read(asignacionRepositoryProvider).crear(
          articuloId: bien.articuloId,
          unidadId: bien.unidadId,
          cantidad: 1,
          empleadoId: empleadoId,
          fechaEntrega: DateTime(fechaBaja.year, 1, 15),
        );
    return asignacion.id;
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

  final autorizador = await crearEmpleado('Maria Fernanda', 'Del Castillo', administrativo: true);
  final receptor = await crearEmpleado('Ricardo Emmanuel', 'Zepeda Montelongo', administrativo: true);

  final exEmpleado = await crearEmpleado('Jose Guadalupe Alejandro', 'Hernandez de la Torre');
  // Adscripción real, vigente en la fecha de baja: el reporte tiene que
  // resolverla por vigencia, no por el servicio actual de nadie.
  final cliente = await db.into(db.cliente).insertReturning(
        ClienteCompanion.insert(codigo: 'CLIX-01', nombreComercial: 'Sportium'),
      );
  final servicio = await db.into(db.servicio).insertReturning(
        ServicioCompanion.insert(
          codigo: 'SERX-01',
          clienteId: cliente.id,
          nombre: 'Vigilancia Sportium Toluca',
          tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
          fechaInicio: DateTime(fechaBaja.year, 1, 1),
        ),
      );
  await db.into(db.asignacionServicio).insert(
        AsignacionServicioCompanion.insert(
          empleadoId: exEmpleado.id,
          servicioId: servicio.id,
          fechaInicio: DateTime(fechaBaja.year, 1, 5),
        ),
      );
  final camisola = await crearBien('Camisola tactica con bordado institucional');
  final chaleco = await crearBien('Chaleco antibalas nivel IIIA');
  final radio = await crearBien('Radio portatil digital UHF');
  final lampara = await crearBien('Lampara tactica recargable');

  await conciliar(exEmpleado.id, [
    // Recuperado y fuera de disponibilidad — NO pendiente.
    ResolucionResguardo(
      asignacionId: await asignar(exEmpleado.id, camisola),
      resolucion: ResolucionResguardoBaja.devuelto,
      condicion: CondicionDevolucionResguardo.sucio,
      destino: DestinoDevolucionResguardo.lavanderia,
      receptorEmpleadoId: receptor.id,
    ),
    // Recuperado, esperando baja física — tampoco pendiente.
    ResolucionResguardo(
      asignacionId: await asignar(exEmpleado.id, chaleco),
      resolucion: ResolucionResguardoBaja.devuelto,
      condicion: CondicionDevolucionResguardo.danado,
      destino: DestinoDevolucionResguardo.desecho,
      receptorEmpleadoId: receptor.id,
      autorizadorEmpleadoId: autorizador.id,
      motivoNoCobro: 'Chaleco al final de su vida util certificada',
    ),
    // Sigue con la persona: PENDIENTE, con obligación económica real.
    ResolucionResguardo(
      asignacionId: await asignar(exEmpleado.id, radio),
      resolucion: ResolucionResguardoBaja.noEntregado,
      motivoNoEntrega: MotivoNoEntregaResguardo.abandonoServicio,
      generaDescuento: true,
      importeDescuento: 125000,
      conceptoDescuento: 'Radio portatil no entregado',
      numeroCuotasDescuento: 4,
    ),
    // Resolución declarada: PERDIDO, que no es pendiente.
    ResolucionResguardo(
      asignacionId: await asignar(exEmpleado.id, lampara),
      resolucion: ResolucionResguardoBaja.perdido,
      generaDescuento: true,
      importeDescuento: 32000,
      conceptoDescuento: 'Lampara extraviada',
    ),
  ]);

  // Transferencia — ni recuperado ni pendiente: sale del denominador de
  // la tasa, y la pantalla lo tiene que decir en vez de sobreentenderlo.
  final exTransferido = await crearEmpleado('Luis Angel', 'Barrera Nunez');
  final sucesor = await crearEmpleado('Diego Armando', 'Sarmiento Pineda');
  final detector = await crearBien('Detector de metales de mano');
  await conciliar(exTransferido.id, [
    ResolucionResguardo(
      asignacionId: await asignar(exTransferido.id, detector),
      resolucion: ResolucionResguardoBaja.transferido,
      nuevoResponsableEmpleadoId: sucesor.id,
    ),
  ]);

  if (conVehiculo) {
    final exVehiculo = await crearEmpleado('Ana Karen', 'Mondragon Ibarra');
    final vehiculo = await container.read(vehiculoRepositoryProvider).crear(
          codigo: 'VEHX-01',
          marca: 'Nissan',
          modelo: 'NP300 Doble Cabina',
          anio: 2022,
          tipoVehiculo: TipoVehiculo.pickup.name,
          placas: 'ABX-001',
        );
    final asignacionVehiculo = await container.read(asignacionVehiculoRepositoryProvider).crear(
          vehiculoId: vehiculo.id,
          empleadoId: exVehiculo.id,
          fechaInicio: DateTime(fechaBaja.year, 1, 15),
        );
    await conciliar(exVehiculo.id, [
      ResolucionResguardo(
        asignacionVehiculoId: asignacionVehiculo.id,
        resolucion: ResolucionResguardoBaja.devuelto,
        condicion: CondicionDevolucionResguardo.usado,
        receptorEmpleadoId: receptor.id,
        lugarEntrega: 'Corporativo Toluca',
        combustible: 'Medio tanque',
        danos: 'Rayon en puerta trasera derecha',
      ),
    ]);
  }

  container.dispose();
}

/// Filas de datos de una hoja (sin el encabezado).
List<List<String>> _filas(Excel excel, String hoja) {
  final tabla = excel.tables[hoja];
  expect(tabla, isNotNull, reason: 'la hoja "$hoja" debe existir en el archivo');
  return [
    for (final fila in tabla!.rows.skip(1)) [for (final celda in fila) celda?.value?.toString() ?? ''],
  ];
}

void main() {
  group('Pantalla de Patrimonio — contenido real y permisos', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    /// Levanta la app completa y navega a [ruta].
    ///
    /// La pantalla arranca con un `CircularProgressIndicator` cuya
    /// animación no termina nunca: `pumpAndSettle` se quedaría girando.
    /// Por eso la carga se resuelve en tiempo real con `runAsync` —
    /// SQLite no avanza con el reloj falso del test— y después se pintan
    /// frames fijos.
    Future<GoRouter> pintarApp(
      WidgetTester tester, {
      required SesionController Function() sesion,
      required String ruta,
      Size tamano = const Size(1440, 1000),
    }) async {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final router = createAppRouter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            contarUsuariosProvider.overrideWith((ref) async => 1),
            sesionControllerProvider.overrideWith(sesion),
            attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
          ],
          child: RisegOneApp(router: router),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
      await tester.pump();

      router.go(ruta);
      await tester.pump();
      // Tiempo real: SQLite no avanza con el reloj falso del test.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 900)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      return router;
    }

    testWidgets('Maestro con bajas conciliadas: la pestaña existe y la pantalla muestra cifras reales',
        (tester) async {
      final hoy = DateTime.now();
      await sembrarBajas(db, fechaBaja: DateTime(hoy.year, hoy.month, 1));

      await pintarApp(tester, sesion: _SesionMaestro.new, ruta: '/reportes/patrimonio');
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(Tab, l10n.reportesTabPatrimonio), findsOneWidget);
      expect(find.text(l10n.reportesPatrimonioSinPermiso), findsNothing);

      // No vacuidad del barrido responsive: la pantalla SÍ pinta
      // contenido, no un estado vacío ni un spinner eterno.
      expect(find.text(l10n.reportesPatrimonioBajasConciliadas), findsOneWidget);
      expect(find.text(l10n.reportesPatrimonioPendientes), findsOneWidget);
      expect(find.text(l10n.reportesPatrimonioPerdidos), findsOneWidget);
      expect(find.text(l10n.reportesPatrimonioDetalleTitulo), findsOneWidget);
      expect(find.text(l10n.reportesPatrimonioVacio), findsNothing);

      // §17: pendiente y perdido se ven distintos en la tabla, con su
      // propia etiqueta — no comparten una sola categoría "no volvió".
      expect(find.text(l10n.reportesPatrimonioResolucionNoEntregado), findsOneWidget);
      expect(find.text(l10n.reportesPatrimonioResolucionPerdido), findsOneWidget);
      expect(find.text(l10n.reportesPatrimonioResolucionDevuelto), findsNWidgets(2));

      // El desenlace "recuperado pero fuera de disponibilidad" se
      // muestra como estado físico, no como pendiente.
      expect(find.text(l10n.unidadEstatusEnLavanderia), findsWidgets);
      expect(find.text(l10n.unidadEstatusPendienteDesecho), findsWidgets);

      // Se sabe quién autorizó no cobrar y quién recibió el bien.
      expect(find.textContaining('Del Castillo'), findsWidgets);
      expect(find.textContaining('Zepeda'), findsWidgets);

      // §16 — lo excluido del denominador es visible, no implícito.
      expect(find.text(l10n.reportesPatrimonioTransferidos), findsOneWidget);
      expect(find.text(l10n.reportesPatrimonioTransferidosNota), findsOneWidget);
      // Un transferido excluido; ningún «autorizado a conservarlo»
      // (el abandono de servicio deja pendiente, no exime de devolver).
      expect(find.text(l10n.reportesPatrimonioTasaExcluidos(1, 0)), findsOneWidget);
      expect(find.text(l10n.reportesPatrimonioTasaNota), findsNothing,
          reason: 'con exclusiones, la nota genérica escondería el motivo de la tasa');
    });

    testWidgets('sólo personal.ver: la pestaña no aparece y la ruta directa no expone ninguna cifra', (tester) async {
      final hoy = DateTime.now();
      await sembrarBajas(db, fechaBaja: DateTime(hoy.year, hoy.month, 1));

      await pintarApp(
        tester,
        sesion: () => _SesionConPermisos(const {'reportes.ver', 'personal.ver'}),
        ruta: '/reportes/patrimonio',
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      // «Patrimonio y bajas» también es el título de la pantalla: se
      // busca el Tab de la franja, no cualquier texto igual.
      expect(find.widgetWithText(Tab, l10n.reportesTabPatrimonio), findsNothing,
          reason: 'sin inventario.ver no debe verse la pestaña');
      // La guardia real vive en el controller: un bookmark obsoleto no
      // alcanza a ver nada.
      expect(find.text(l10n.reportesPatrimonioSinPermiso), findsOneWidget);
      expect(find.text(l10n.reportesPatrimonioBajasConciliadas), findsNothing);
      expect(find.text(l10n.reportesPatrimonioDetalleTitulo), findsNothing);
      expect(find.textContaining(r'$'), findsNothing, reason: 'ninguna cifra sin autorización');
    });

    testWidgets('sólo inventario.ver: mismo bloqueo por el otro lado', (tester) async {
      final hoy = DateTime.now();
      await sembrarBajas(db, fechaBaja: DateTime(hoy.year, hoy.month, 1));

      await pintarApp(
        tester,
        sesion: () => _SesionConPermisos(const {'reportes.ver', 'inventario.ver'}),
        ruta: '/reportes/patrimonio',
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(Tab, l10n.reportesTabPatrimonio), findsNothing,
          reason: 'sin personal.ver tampoco se ve');
      expect(find.text(l10n.reportesPatrimonioSinPermiso), findsOneWidget);
      expect(find.textContaining(r'$'), findsNothing);
    });

    testWidgets('con personal.ver + inventario.ver: la pestaña aparece y el reporte carga', (tester) async {
      final hoy = DateTime.now();
      await sembrarBajas(db, fechaBaja: DateTime(hoy.year, hoy.month, 1));

      await pintarApp(
        tester,
        sesion: () => _SesionConPermisos(const {'reportes.ver', 'personal.ver', 'inventario.ver'}),
        ruta: '/reportes/patrimonio',
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(Tab, l10n.reportesTabPatrimonio), findsOneWidget);
      expect(find.text(l10n.reportesPatrimonioSinPermiso), findsNothing);
      expect(find.text(l10n.reportesPatrimonioBajasConciliadas), findsOneWidget);
    });

    testWidgets('el servicio histórico se ve en la tabla y en el ranking, con su propia pregunta', (tester) async {
      final hoy = DateTime.now();
      await sembrarBajas(db, fechaBaja: DateTime(hoy.year, hoy.month, 1));

      await pintarApp(tester, sesion: _SesionMaestro.new, ruta: '/reportes/patrimonio');
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.reportesPatrimonioServicioColumna), findsOneWidget);
      expect(find.text(l10n.reportesPatrimonioServiciosTitulo), findsOneWidget);
      expect(find.text(l10n.reportesPatrimonioServiciosPregunta), findsOneWidget);

      // El servicio resuelto aparece con su nombre real.
      expect(find.text('Vigilancia Sportium Toluca'), findsWidgets);
      // Lo no resoluble NUNCA es una celda vacía: lo dice con texto.
      expect(find.text(l10n.reportesPatrimonioServicioSinResolver), findsWidgets,
          reason: 'las bajas sin adscripción tienen que decirlo');
    });

    testWidgets('los tres filtros buscables existen y conservan su catálogo con un filtro puesto',
        (tester) async {
      final hoy = DateTime.now();
      await sembrarBajas(db, fechaBaja: DateTime(hoy.year, hoy.month, 1));

      // Viewport alto a propósito: los filtros viven al pie de una
      // pantalla larga y el panel buscable se ancla DEBAJO del campo.
      await pintarApp(
        tester,
        sesion: _SesionMaestro.new,
        ruta: '/reportes/patrimonio',
        tamano: const Size(1440, 2600),
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(find.byKey(const Key('patrimonio_filtro_empleado')), findsOneWidget);
      expect(find.byKey(const Key('patrimonio_filtro_autorizador')), findsOneWidget);
      expect(find.byKey(const Key('patrimonio_filtro_servicio')), findsOneWidget);

      // Se abre el panel del filtro de personas y se elige a alguien.
      // Se toca el campo de texto, que es lo que toma el foco y abre el
      // panel anclado; la Key envuelve al Column con su etiqueta.
      await tester.tap(find.descendant(
        of: find.byKey(const Key('patrimonio_filtro_empleado')),
        matching: find.byType(TextField),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // Acotado al panel: el mismo nombre también está en la tabla de
      // detalle que se ve detrás.
      final opcionLuis = find.descendant(of: find.byKey(panelBuscable), matching: find.text('Luis Angel Barrera Nunez'));
      expect(opcionLuis, findsOneWidget, reason: 'el panel lista el catálogo');

      await tester.tap(opcionLuis);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 700)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);

      // El filtro activo se ve, y se puede quitar.
      expect(find.text(l10n.reportesPatrimonioFiltrosActivos), findsOneWidget);
      expect(find.text(l10n.reportesPatrimonioFiltroChipEmpleado('Luis Angel Barrera Nunez')), findsOneWidget);
      expect(find.text(l10n.reportesPatrimonioFiltrosLimpiar), findsOneWidget);

      // Y el catálogo NO se recortó: las otras personas del periodo
      // siguen ahí, así que el filtro se puede cambiar sin limpiarlo.
      // Se toca el campo de texto, que es lo que toma el foco y abre el
      // panel anclado; la Key envuelve al Column con su etiqueta.
      await tester.tap(find.descendant(
        of: find.byKey(const Key('patrimonio_filtro_empleado')),
        matching: find.byType(TextField),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.descendant(
          of: find.byKey(panelBuscable),
          matching: find.text('Jose Guadalupe Alejandro Hernandez de la Torre'),
        ),
        findsOneWidget,
        reason: 'el catálogo sale del periodo sin filtrar, no del resultado',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('base sin ninguna baja conciliada: estado vacío explícito, sin excepción', (tester) async {
      await pintarApp(tester, sesion: _SesionMaestro.new, ruta: '/reportes/patrimonio');
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.reportesPatrimonioVacio), findsOneWidget);
      expect(find.text(l10n.reportesPatrimonioSerieVacia), findsOneWidget);
      expect(find.text(l10n.reportesPatrimonioEstadosVacia), findsOneWidget);
      expect(find.text(l10n.reportesPatrimonioDescuentosVacia), findsOneWidget);
    });
  });

  group('Exportación de Patrimonio — mismo universo que la pantalla', () {
    late AppDatabase db;
    late ProviderContainer container;

    final rango = RangoPeriodo(inicio: DateTime(2026, 1, 1), fin: DateTime(2026, 12, 31));
    final fechaBaja = DateTime(2026, 6, 15);
    final contexto = ReporteExportContext(
      nombreReporte: 'Patrimonio y bajas',
      rangoInicio: rango.inicio,
      rangoFin: rango.fin,
      generadoPor: 'Maestro de prueba',
      generadoEn: DateTime(2026, 6, 20),
    );

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
      await sembrarBajas(db, fechaBaja: fechaBaja, conVehiculo: true);
      container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestro.new),
        attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
      ]);
    });

    tearDown(() {
      container.dispose();
      db.close();
    });

    Future<AnalisisPatrimonio> analizar({FiltroPatrimonio filtro = const FiltroPatrimonio()}) {
      return container.read(obtenerAnalisisPatrimonioUseCaseProvider).ejecutar(rango: rango, filtro: filtro);
    }

    test('el XLSX trae las seis hojas de detalle más Info, y Pendientes/Recuperados son disjuntas', () async {
      final analisis = await analizar();
      final excel = Excel.decodeBytes(PatrimonioXlsxRenderer().generar(contexto: contexto, analisis: analisis));

      expect(
        excel.tables.keys,
        containsAll(<String>[
          'Info',
          'Resumen',
          'Estados físicos',
          'Pendientes',
          'Recuperados',
          'Descuentos',
          'Servicios',
          'Autorizaciones',
          'Vehículos',
        ]),
      );

      final pendientes = _filas(excel, 'Pendientes');
      final recuperados = _filas(excel, 'Recuperados');

      expect(pendientes, hasLength(analisis.pendientes), reason: 'una fila por bien pendiente, ni más ni menos');
      expect(recuperados, hasLength(analisis.recuperados));

      // Columna 3 = "Bien" (0 empleado, 1 fecha, 2 servicio histórico):
      // ningún bien puede estar en las dos hojas.
      final bienesPendientes = pendientes.map((f) => f[3]).toSet();
      final bienesRecuperados = recuperados.map((f) => f[3]).toSet();
      expect(bienesPendientes.intersection(bienesRecuperados), isEmpty, reason: 'un bien no puede estar en ambas');
      expect(bienesPendientes, hasLength(pendientes.length), reason: 'sin filas duplicadas por join');

      // El bien perdido no está en ninguna de las dos: no se espera y no volvió.
      expect(bienesPendientes.any((b) => b.contains('Lampara')), isFalse);
      expect(bienesRecuperados.any((b) => b.contains('Lampara')), isFalse);
    });

    test('el Resumen del XLSX repite exactamente los KPI del análisis — una sola fuente', () async {
      final analisis = await analizar();
      final excel = Excel.decodeBytes(PatrimonioXlsxRenderer().generar(contexto: contexto, analisis: analisis));

      final resumen = {for (final fila in _filas(excel, 'Resumen')) fila[0]: fila[1]};

      expect(resumen['Bajas conciliadas'], '${analisis.bajasConciliadas}');
      expect(resumen['Bienes recuperados'], '${analisis.recuperados}');
      expect(resumen['Pendientes de recuperar'], '${analisis.pendientes}');
      expect(resumen['Bienes perdidos'], '${analisis.perdidos}');
      expect((double.parse(resumen['Descuentos generados']!) * 100).round(), analisis.importeDescuentos);
      expect(resumen['Denominador de la tasa'], '${analisis.tasaRecuperacion.debianRecuperarse}');

      // Coherencia interna: el denominador es la suma de los tres.
      expect(
        analisis.tasaRecuperacion.debianRecuperarse,
        analisis.recuperados + analisis.pendientes + analisis.perdidos,
      );
    });

    test('la hoja Descuentos sólo lista obligaciones vinculadas a la conciliación', () async {
      final analisis = await analizar();
      final excel = Excel.decodeBytes(PatrimonioXlsxRenderer().generar(contexto: contexto, analisis: analisis));

      final descuentos = _filas(excel, 'Descuentos');
      final conDescuento = analisis.renglones.where((r) => r.descuento != null).toList();

      expect(descuentos, hasLength(conDescuento.length));
      expect(descuentos, isNotEmpty, reason: 'la siembra genera dos descuentos reales');

      final suma = descuentos.fold<double>(0, (acumulado, fila) => acumulado + double.parse(fila[4]));
      expect((suma * 100).round(), analisis.importeDescuentos, reason: 'la hoja suma lo mismo que el KPI');

      // Todos salen de un renglón con FK, nunca de un préstamo personal.
      for (final renglon in conDescuento) {
        expect(renglon.descuento!.tipo, 'resguardo');
      }

      // Las cuotas son las REALES del descuento (una consulta agregada),
      // no el `numeroCuotasDescuento` que se capturó al conciliar.
      final radio = conDescuento.firstWhere((r) => r.bienDescripcion.contains('Radio'));
      final lampara = conDescuento.firstWhere((r) => r.bienDescripcion.contains('Lampara'));
      expect(radio.cuotasDescuento, 4);
      expect(lampara.cuotasDescuento, 1);

      final cuotasEnHoja = {for (final fila in descuentos) fila[0]: int.parse(fila[5])};
      expect(cuotasEnHoja[radio.descuento!.folio], 4);
      expect(cuotasEnHoja[lampara.descuento!.folio], 1);
    });

    test('el panel de estados físicos cuenta sólo lo recuperado: un pendiente no se disfraza de «Asignada»', () async {
      final analisis = await analizar();

      // La exclusión hace trabajo real: la unidad del bien pendiente
      // SIGUE en `asignado` —no se cerró la asignación, porque el bien
      // no volvió— y aun así no aparece como una ubicación de resguardo.
      final pendiente = analisis.renglones.singleWhere((r) => r.estaPendiente);
      expect(pendiente.estatusUnidad, 'asignado');

      expect(analisis.unidadesPorEstatus.keys, containsAll(<String>['enLavanderia', 'pendienteDesecho']));
      expect(analisis.unidadesPorEstatus['asignado'], isNull, reason: 'el pendiente sigue con la persona');
      expect(analisis.unidadesPorEstatus['perdido'], isNull, reason: 'perdido es un KPI, no una ubicación');

      final total = analisis.unidadesPorEstatus.values.fold<int>(0, (a, b) => a + b);
      expect(total, analisis.renglones.where((r) => r.fueRecuperado && r.estatusUnidad != null).length);
      expect(total, lessThanOrEqualTo(analisis.recuperados), reason: 'la gráfica nunca puede superar su KPI');

      // La hoja del XLSX proyecta exactamente el mismo mapa.
      final excel = Excel.decodeBytes(PatrimonioXlsxRenderer().generar(contexto: contexto, analisis: analisis));
      final estados = _filas(excel, 'Estados físicos');
      expect(estados, hasLength(analisis.unidadesPorEstatus.length));
      expect(estados.fold<int>(0, (a, fila) => a + int.parse(fila[1])), total);
    });

    test('el XLSX trae el servicio histórico, y los casos no resolubles con texto, nunca en blanco', () async {
      final analisis = await analizar();
      final excel = Excel.decodeBytes(PatrimonioXlsxRenderer().generar(contexto: contexto, analisis: analisis));

      // Columna 2 de las hojas de bienes = Servicio (a la baja).
      final servicios = [
        ..._filas(excel, 'Pendientes').map((f) => f[2]),
        ..._filas(excel, 'Recuperados').map((f) => f[2]),
      ];
      expect(servicios, isNotEmpty);
      expect(servicios.every((v) => v.trim().isNotEmpty), isTrue, reason: 'nunca una celda en blanco');
      expect(servicios, contains('Vigilancia Sportium Toluca'));

      // El vehículo es de otra persona, sin adscripción: lo dice.
      expect(_filas(excel, 'Vehículos').single[2], 'Sin servicio histórico resoluble');
    });

    test('la hoja Servicios cuadra con los KPI y no reparte lo no resoluble', () async {
      final analisis = await analizar();
      final excel = Excel.decodeBytes(PatrimonioXlsxRenderer().generar(contexto: contexto, analisis: analisis));

      final filas = _filas(excel, 'Servicios');
      expect(filas, hasLength(analisis.problemasPorServicio.length));
      expect(filas.map((f) => f[0]), contains('Vigilancia Sportium Toluca'));
      expect(filas.map((f) => f[0]), contains('Sin servicio histórico resoluble'));

      expect(filas.fold<int>(0, (a, f) => a + int.parse(f[1])), analisis.bajasConciliadas);
      expect(filas.fold<int>(0, (a, f) => a + int.parse(f[2])), analisis.pendientes);
      expect(filas.fold<int>(0, (a, f) => a + int.parse(f[3])), analisis.perdidos);
    });

    test('filtrar por servicio exporta sólo ese servicio, con el mismo universo que el análisis', () async {
      final completo = await analizar();
      final servicioId = completo.catalogo.servicios.single.servicioId;

      final filtrado = await analizar(filtro: FiltroPatrimonio(servicioId: servicioId));
      final excel = Excel.decodeBytes(PatrimonioXlsxRenderer().generar(contexto: contexto, analisis: filtrado));

      final bienes = [..._filas(excel, 'Pendientes'), ..._filas(excel, 'Recuperados')];
      expect(bienes, isNotEmpty);
      expect(bienes.every((f) => f[2] == 'Vigilancia Sportium Toluca'), isTrue);
      expect(_filas(excel, 'Vehículos'), isEmpty, reason: 'el vehículo no pertenece a ese servicio');
      expect(_filas(excel, 'Servicios'), hasLength(1));

      // El catálogo del archivo filtrado sigue completo: exportar no
      // puede dejar la pantalla sin opciones a las que volver.
      expect(filtrado.catalogo.servicios, hasLength(completo.catalogo.servicios.length));
      expect(filtrado.catalogo.empleados, hasLength(completo.catalogo.empleados.length));
    });

    test('la hoja Vehículos trae el detalle propio del vehículo y no duplica el inventario', () async {
      final analisis = await analizar();
      final excel = Excel.decodeBytes(PatrimonioXlsxRenderer().generar(contexto: contexto, analisis: analisis));

      final vehiculos = _filas(excel, 'Vehículos');
      expect(vehiculos, hasLength(1));
      expect(vehiculos.single[3], contains('Nissan'));
      expect(vehiculos.single[5], 'Corporativo Toluca');
      expect(vehiculos.single[7], contains('Rayon'));
      expect(vehiculos.single[8], contains('Zepeda'), reason: 'sí se sabe quién lo recibió');
    });

    test('exportar con filtro exporta lo filtrado, no todo', () async {
      final soloPendientes = await analizar(filtro: const FiltroPatrimonio(soloPendientes: true));
      final excel = Excel.decodeBytes(PatrimonioXlsxRenderer().generar(contexto: contexto, analisis: soloPendientes));

      expect(_filas(excel, 'Recuperados'), isEmpty, reason: 'el filtro de pantalla viaja al archivo');
      expect(_filas(excel, 'Pendientes'), hasLength(soloPendientes.renglones.length));
      expect(_filas(excel, 'Vehículos'), isEmpty, reason: 'el vehículo devuelto no es un pendiente');
    });

    test('el PDF ejecutivo se genera y separa pendientes de perdidos', () async {
      final analisis = await analizar();
      final bytes = await ReportePatrimonioPdfRenderer().renderizar(contexto: contexto, analisis: analisis);

      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(bytes.length, greaterThan(1000));
      // El resumen ejecutivo imprime pendientes y perdidos en renglones
      // distintos porque el análisis los tiene separados: ningún bien
      // cae en las dos categorías.
      expect(analisis.renglones.where((r) => r.estaPendiente && r.sePerdio), isEmpty);
      expect(analisis.renglones.where((r) => r.estaPendiente), hasLength(analisis.pendientes));
      expect(analisis.renglones.where((r) => r.sePerdio), hasLength(analisis.perdidos));
    });

    test('el PDF con la base vacía tampoco truena', () async {
      final vacio = await container.read(obtenerAnalisisPatrimonioUseCaseProvider).ejecutar(
            rango: RangoPeriodo(inicio: DateTime(2020, 1, 1), fin: DateTime(2020, 12, 31)),
          );
      final bytes = await ReportePatrimonioPdfRenderer().renderizar(contexto: contexto, analisis: vacio);

      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(vacio.tasaRecuperacion.tasa, isNull, reason: 'sin base no se afirma 0 %');
    });
  });
}
