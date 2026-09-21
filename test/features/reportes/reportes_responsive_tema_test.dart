// Rediseño de Reportes — evidencia visual.
//
// Mismo criterio de siempre en RISEG ONE: sin herramienta de captura, la
// prueba es "cero overflow / cero excepción" (`tester.takeException()`)
// en cada breakpoint y en ambos temas, nunca comparación de píxeles ni
// capturas inventadas.
//
// Los datos son deliberadamente hostiles al layout nuevo: importes de
// siete cifras (los ejes de las gráficas los tienen que abreviar),
// nombres de proveedor largos (la leyenda de composición los tiene que
// truncar), unidades repartidas en seis estados físicos distintos (la
// barra apilada tiene que seguir mostrando el segmento más chico) y un
// rango anual (que fuerza granularidad mensual en la serie temporal).
//
// Cada pantalla se prueba dos veces: con datos y con la base vacía —
// los estados vacíos son parte del diseño, no un descuido.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/compras/presentation/compras_controller.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_ingreso_manual_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/movimiento_inventario_table.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentStorageProvider;
import 'package:riseg_one/features/personal/data/tables/conciliacion_baja_table.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/conciliar_baja_empleado_usecase.dart';
import 'package:riseg_one/features/personal/personal_providers.dart';
import 'package:riseg_one/features/reportes/presentation/finanzas/reportes_finanzas_controller.dart';
import 'package:riseg_one/features/reportes/presentation/finanzas/reportes_finanzas_screen.dart';
import 'package:riseg_one/features/reportes/presentation/finanzas/reportes_finanzas_state.dart';
import 'package:riseg_one/features/reportes/presentation/general/reportes_general_controller.dart';
import 'package:riseg_one/features/reportes/presentation/general/reportes_general_screen.dart';
import 'package:riseg_one/features/reportes/presentation/operacion/reportes_operacion_controller.dart';
import 'package:riseg_one/features/reportes/presentation/operacion/reportes_operacion_screen.dart';
import 'package:riseg_one/features/reportes/domain/analitica/obtener_analisis_patrimonio_usecase.dart';
import 'package:riseg_one/features/reportes/presentation/patrimonio/reportes_patrimonio_controller.dart';
import 'package:riseg_one/features/reportes/presentation/patrimonio/reportes_patrimonio_screen.dart';
import 'package:riseg_one/features/reportes/presentation/personal_nomina/reportes_personal_nomina_controller.dart';
import 'package:riseg_one/features/reportes/presentation/personal_nomina/reportes_personal_nomina_screen.dart';
import 'package:riseg_one/features/reportes/presentation/reportes_rango_controller.dart';
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

const _anchos = <String, Size>{
  '1536': Size(1536, 1100),
  '1366': Size(1366, 1000),
  '1024': Size(1024, 1000),
  '700': Size(700, 1000),
  '500': Size(500, 1000),
};

const _proveedorLargo =
    'Distribuidora Integral de Uniformes y Equipo Táctico del Valle de Toluca S.A. de C.V.';

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late ProviderContainer container;

  Future<void> abrirContenedor() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_reportes_responsive_');
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestro.new),
        attachmentStorageProvider.overrideWithValue(AttachmentStorage(tempDir.path)),
      ],
    );
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: r'pbkdf2$1$c2FsdA==$aGFzaA==',
            esMaestro: const Value(true),
          ),
        );
  }

  Future<void> cerrarContenedor() async {
    container.dispose();
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  }

  /// Siembra bajas conciliadas con TODO el abanico de resoluciones.
  ///
  /// Es deliberadamente hostil al layout: nombres de persona y de
  /// articulo largos (las columnas los tienen que truncar), bienes
  /// repartidos en los cuatro estados que el pedido exige no confundir
  /// -pendiente, perdido, pendiente de desecho y lavanderia/reparacion-,
  /// un vehiculo con danos en texto libre, autorizaciones sin cobro y
  /// tres bajas distintas para que el ranking de impacto tenga mas de un
  /// renglon.
  Future<void> sembrarPatrimonio() async {
    final hoy = DateTime.now();
    // Primer dia del mes en curso: la baja cae dentro del rango anual y
    // tambien dentro del preset por omision.
    final fechaBaja = DateTime(hoy.year, hoy.month, 1, 10);
    var n = 0;

    Future<EmpleadoData> crearEmpleado(String nombres, String apellido, {bool administrativo = false}) async {
      n++;
      final sufijo = n.toString().padLeft(2, '0');
      String? sucursalId;
      if (administrativo) {
        final sucursal = await db.into(db.sucursal).insertReturning(
              SucursalCompanion.insert(
                codigo: 'SUCP-$sufijo',
                nombre: 'Corporativo',
                tipoSucursalId: SeedIds.tipoSucursalOficinaAdministrativa,
              ),
            );
        sucursalId = sucursal.id;
      }
      return db.into(db.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: 900 + n,
              nombres: nombres,
              apellidoPaterno: apellido,
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'CUXA900101HDFXXX$sufijo',
              rfc: 'CUXA900101A$sufijo',
              nss: '1234567$sufijo',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(hoy.year - 2, 1, 1),
              aniosExperienciaSeguridad: 3,
              sucursalId: Value(sucursalId),
            ),
          );
    }

    Future<({String articuloId, String unidadId})> crearBien(String nombre) async {
      n++;
      final sufijo = n.toString().padLeft(3, '0');
      final categoria = await db.into(db.categoriaArticulo).insertReturning(
            CategoriaArticuloCompanion.insert(nombre: 'Equipo de proteccion $sufijo'),
          );
      final articulo = await ArticuloRepositoryImpl(db).crear(
        folio: 'ARP-$sufijo',
        categoriaId: categoria.id,
        nombre: nombre,
        manejaVariante: false,
        manejaSerie: true,
      );
      final unidad = await db.into(db.articuloUnidad).insertReturning(
            ArticuloUnidadCompanion.insert(
              articuloId: articulo.id,
              codigo: 'UNP-$sufijo',
              numeroSerie: 'SP-$sufijo',
            ),
          );
      // Costo real capturado: el reporte puede valorar sin inventar.
      await db.into(db.movimientoInventario).insert(
            MovimientoInventarioCompanion.insert(
              articuloId: articulo.id,
              unidadId: Value(unidad.id),
              tipoMovimiento: TipoMovimientoInventario.entrada.name,
              cantidad: 1,
              costoUnitario: const Value(1287500),
              fecha: DateTime(hoy.year, 1, 10),
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
            fechaEntrega: DateTime(hoy.year, 1, 15),
          );
    }

    Future<AsignacionVehiculoData> asignarVehiculo(String empleadoId) async {
      n++;
      final sufijo = n.toString().padLeft(3, '0');
      final vehiculo = await container.read(vehiculoRepositoryProvider).crear(
            codigo: 'VEHP-$sufijo',
            marca: 'Nissan',
            modelo: 'NP300 Doble Cabina Estaquitas',
            anio: 2022,
            tipoVehiculo: TipoVehiculo.pickup.name,
            placas: 'ABP-$sufijo',
          );
      return container.read(asignacionVehiculoRepositoryProvider).crear(
            vehiculoId: vehiculo.id,
            empleadoId: empleadoId,
            fechaInicio: DateTime(hoy.year, 1, 15),
          );
    }

    Future<void> conciliar(String empleadoId, List<ResolucionResguardo> resoluciones) async {
      final resultado = await container.read(conciliarBajaEmpleadoUseCaseProvider).ejecutar(
            empleadoId: empleadoId,
            fechaBaja: fechaBaja,
            motivo: MotivoBajaEmpleado.renuncia,
            resoluciones: resoluciones,
          );
      expect(resultado, isA<ConciliarBajaEmpleadoExitoso>());
    }

    final autorizador = await crearEmpleado('Maria Fernanda Guadalupe', 'Del Castillo Villasenor', administrativo: true);
    final receptor = await crearEmpleado('Ricardo Emmanuel', 'Zepeda Montelongo', administrativo: true);

    // Baja 1 - el abanico completo en una persona de nombre largo:
    // lavanderia, reparacion, pendiente de desecho, no entregado con
    // descuento y perdido. Los cinco tienen que verse distintos.
    /// Servicio real con su cliente, para la adscripcion historica.
    Future<ServicioData> crearServicio(String nombre, String clienteNombre) async {
      n++;
      final sufijo = n.toString().padLeft(3, '0');
      final cliente = await db.into(db.cliente).insertReturning(
            ClienteCompanion.insert(codigo: 'CLIP-$sufijo', nombreComercial: clienteNombre),
          );
      return db.into(db.servicio).insertReturning(
            ServicioCompanion.insert(
              codigo: 'SERP-$sufijo',
              clienteId: cliente.id,
              nombre: nombre,
              tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
              fechaInicio: DateTime(hoy.year, 1, 1),
            ),
          );
    }

    Future<void> adscribir(String empleadoId, String servicioId, {DateTime? termino}) {
      return db.into(db.asignacionServicio).insert(
            AsignacionServicioCompanion.insert(
              empleadoId: empleadoId,
              servicioId: servicioId,
              fechaInicio: DateTime(hoy.year, 1, 5),
              fechaTermino: Value(termino),
            ),
          );
    }

    final exUno = await crearEmpleado('Jose Guadalupe Alejandro', 'Hernandez de la Torre Villanueva');
    // Nombre largo a proposito: la columna de Servicio lo tiene que
    // truncar igual que las demas.
    final servicioLargo = await crearServicio(
      'Vigilancia intramuros y control de accesos - Corporativo Santa Fe, turno mixto',
      'Inmobiliaria y Desarrollos Metropolitanos del Valle S.A. de C.V.',
    );
    await adscribir(exUno.id, servicioLargo.id);
    final camisola = await crearBien('Camisola tactica manga larga con bordado institucional');
    final pantalon = await crearBien('Pantalon tactico reforzado con rodillera desmontable');
    final chaleco = await crearBien('Chaleco antibalas nivel IIIA con placa ceramica frontal');
    final radio = await crearBien('Radio portatil digital UHF con cargador y bateria extendida');
    final lampara = await crearBien('Lampara tactica recargable de alta intensidad');

    await conciliar(exUno.id, [
      ResolucionResguardo(
        asignacionId: (await asignar(exUno.id, camisola)).id,
        resolucion: ResolucionResguardoBaja.devuelto,
        condicion: CondicionDevolucionResguardo.sucio,
        destino: DestinoDevolucionResguardo.lavanderia,
        receptorEmpleadoId: receptor.id,
        costoLimpieza: 8000,
        responsableCostoLimpieza: ResponsableCostoResguardo.trabajador,
        generaDescuento: true,
        importeDescuento: 8000,
        conceptoDescuento: 'Limpieza de camisola tactica',
      ),
      ResolucionResguardo(
        asignacionId: (await asignar(exUno.id, pantalon)).id,
        resolucion: ResolucionResguardoBaja.devuelto,
        condicion: CondicionDevolucionResguardo.malEstado,
        destino: DestinoDevolucionResguardo.reparacion,
        receptorEmpleadoId: receptor.id,
      ),
      ResolucionResguardo(
        asignacionId: (await asignar(exUno.id, chaleco)).id,
        resolucion: ResolucionResguardoBaja.devuelto,
        condicion: CondicionDevolucionResguardo.danado,
        destino: DestinoDevolucionResguardo.desecho,
        receptorEmpleadoId: receptor.id,
        autorizadorEmpleadoId: autorizador.id,
        motivoNoCobro: 'Chaleco al final de su vida util certificada',
      ),
      ResolucionResguardo(
        asignacionId: (await asignar(exUno.id, radio)).id,
        resolucion: ResolucionResguardoBaja.noEntregado,
        motivoNoEntrega: MotivoNoEntregaResguardo.abandonoServicio,
        generaDescuento: true,
        importeDescuento: 1250000,
        conceptoDescuento: 'Radio portatil no entregado tras abandono de servicio',
        numeroCuotasDescuento: 4,
      ),
      ResolucionResguardo(
        asignacionId: (await asignar(exUno.id, lampara)).id,
        resolucion: ResolucionResguardoBaja.perdido,
        generaDescuento: true,
        importeDescuento: 320000,
        conceptoDescuento: 'Lampara extraviada',
      ),
    ]);

    // Baja 2 - vehiculo devuelto con danos descritos, mas un bien
    // autorizado a conservar (sale del denominador de la tasa).
    final exDos = await crearEmpleado('Ana Karen', 'Mondragon Ibarra');
    final gorra = await crearBien('Gorra institucional bordada con visera rigida');
    await conciliar(exDos.id, [
      ResolucionResguardo(
        asignacionVehiculoId: (await asignarVehiculo(exDos.id)).id,
        resolucion: ResolucionResguardoBaja.devuelto,
        condicion: CondicionDevolucionResguardo.usado,
        receptorEmpleadoId: receptor.id,
        lugarEntrega: 'Estacionamiento del corporativo Toluca, caseta 2',
        combustible: 'Medio tanque',
        danos: 'Rayon profundo en puerta trasera derecha y espejo lateral flojo',
      ),
      ResolucionResguardo(
        asignacionId: (await asignar(exDos.id, gorra)).id,
        resolucion: ResolucionResguardoBaja.noEntregado,
        motivoNoEntrega: MotivoNoEntregaResguardo.autorizadoAConservarlo,
        autorizadorEmpleadoId: autorizador.id,
        motivoNoCobro: 'Prenda personalizada sin valor de reuso',
      ),
    ]);

    // Baja 3 - transferencia: ni pendiente ni recuperado. Ademas, dato
    // historico roto: dos vigencias cubriendo la fecha de baja, para que
    // el renglon de 'Inconsistencia de asignacion' tambien se pinte.
    final exTres = await crearEmpleado('Luis Angel', 'Barrera Nunez');
    final servicioA = await crearServicio('Rondin nocturno zona industrial', 'Grupo Textil del Bajio');
    final servicioB = await crearServicio('Monitoreo remoto CCTV', 'Grupo Textil del Bajio');
    await adscribir(exTres.id, servicioA.id, termino: DateTime(hoy.year, 12, 31));
    await adscribir(exTres.id, servicioB.id, termino: DateTime(hoy.year, 12, 31));
    final sucesor = await crearEmpleado('Diego Armando', 'Sarmiento Pineda');
    final detector = await crearBien('Detector de metales de mano con alarma audible');
    await conciliar(exTres.id, [
      ResolucionResguardo(
        asignacionId: (await asignar(exTres.id, detector)).id,
        resolucion: ResolucionResguardoBaja.transferido,
        nuevoResponsableEmpleadoId: sucesor.id,
      ),
    ]);
  }

  /// Siembra movimientos reales repartidos a lo largo del año en curso,
  /// para que la serie temporal tenga varias cubetas pobladas.
  Future<void> sembrarDatos() async {
    final hoy = DateTime.now();
    DateTime enMes(int mes, int dia) => DateTime(hoy.year, mes, dia, 11);

    for (var mes = 1; mes <= 6; mes++) {
      final r = await container.read(registrarIngresoManualUseCaseProvider).ejecutar(
            monto: 120000000 + mes * 3500000, // más de un millón de pesos
            fecha: enMes(mes, 5),
            formaPago: 'transferencia',
            concepto: 'Cobro de servicio de seguridad intramuros — mes $mes',
          );
      expect(r, isA<RegistrarIngresoManualExitoso>());

      final e = await container.read(registrarEgresoUseCaseProvider).ejecutar(
            monto: 80000000 + mes * 2100000,
            fecha: enMes(mes, 12),
            formaPago: 'transferencia',
            concepto: 'Gasto operativo del mes $mes',
          );
      expect(e, isA<RegistrarEgresoExitoso>());
    }

    // Tarjeta + compra con TDC + pago: pone en juego las tres piezas del
    // panel "Cómo se financió el gasto" a la vez.
    final tarjeta = await container.read(registrarDeudaAutorizadoProvider)(
      nombre: 'TDC corporativa',
      tipo: TipoDeuda.tarjetaCredito.name,
      fechaOrigen: DateTime(hoy.year, 1, 1),
      importeOriginal: 500000000,
      saldoInicial: 1,
      tarjetaLimiteCredito: 500000000,
    );
    final deudaId = (tarjeta as RegistrarDeudaExitoso).deuda.id;

    final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
    final categoria = await categoriaRepo.crear(nombre: 'Uniformes');
    final articulo = await ArticuloRepositoryImpl(db).crear(
      folio: 'ART-000001',
      categoriaId: categoria.id,
      nombre: 'Camisola táctica',
      manejaVariante: false,
      manejaSerie: true,
    );

    final compra = await container.read(comprasControllerProvider.notifier).registrarCompra(
          fecha: enMes(3, 20),
          formaPago: 'tarjeta',
          deudaId: deudaId,
          proveedor: _proveedorLargo,
          partidas: [
            PartidaCompraInput(
              destino: 'inventario',
              articuloId: articulo.id,
              cantidad: 6,
              costoUnitario: 4500000,
              numerosSerie: const ['S-1', 'S-2', 'S-3', 'S-4', 'S-5', 'S-6'],
            ),
          ],
        );
    expect(compra, isA<RegistrarCompraExitosa>());

    await container.read(registrarPagoDeudaAutorizadoProvider)(
      deudaId: deudaId,
      fecha: enMes(4, 2),
      importe: 10000000,
      formaPago: 'transferencia',
    );

    // Las seis unidades se reparten en todos los estados físicos —
    // incluidos los intermedios, que son justo lo que el panel de
    // Inventario tiene que dejar de esconder.
    const estados = [
      EstatusArticuloUnidad.disponible,
      EstatusArticuloUnidad.asignado,
      EstatusArticuloUnidad.enLavanderia,
      EstatusArticuloUnidad.enReparacion,
      EstatusArticuloUnidad.pendienteDesecho,
      EstatusArticuloUnidad.danado,
    ];
    final unidades = await db.select(db.articuloUnidad).get();
    for (final (indice, unidad) in unidades.indexed) {
      await (db.update(db.articuloUnidad)..where((t) => t.id.equals(unidad.id)))
          .write(ArticuloUnidadCompanion(estatus: Value(estados[indice % estados.length].name)));
    }

    await sembrarPatrimonio();
  }

  Widget envolver({required bool oscuro, required Widget child}) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: oscuro ? AppTheme.dark() : AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
  }

  void fijarTamano(WidgetTester tester, Size tamano) {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Deja los cuatro controladores cargados ANTES de pintar.
  ///
  /// Es obligatorio y no una optimización: mientras `cargando` es true
  /// la pantalla muestra un `CircularProgressIndicator`, cuya animación
  /// nunca termina, y `pumpAndSettle` se quedaría girando para siempre.
  /// Además la carga real toca SQLite, que no avanza con el reloj falso
  /// de un widget test — tiene que resolverse aquí, en tiempo real.
  Future<void> precargarPestanas() async {
    // `listen` y no `read`: los controladores son autoDispose y sin una
    // suscripción viva se destruirían antes de terminar de cargar.
    container.listen(reportesGeneralControllerProvider, (_, __) {}, fireImmediately: true);
    container.listen(reportesFinanzasControllerProvider, (_, __) {}, fireImmediately: true);
    container.listen(reportesPersonalNominaControllerProvider, (_, __) {}, fireImmediately: true);
    container.listen(reportesOperacionControllerProvider, (_, __) {}, fireImmediately: true);
    container.listen(reportesPatrimonioControllerProvider, (_, __) {}, fireImmediately: true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
  }

  Future<void> pintar(WidgetTester tester, {required Size tamano, required bool oscuro, required Widget pantalla}) async {
    fijarTamano(tester, tamano);
    await tester.pumpWidget(envolver(oscuro: oscuro, child: pantalla));
    // Frames fijos en vez de `pumpAndSettle`: suficiente para que se
    // asiente el layout, sin quedar atrapado en una animación infinita
    // si algo siguiera cargando.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  const pantallas = <String, Widget>{
    'General': ReportesGeneralScreen(),
    'Finanzas': ReportesFinanzasScreen(),
    'Personal · Nómina': ReportesPersonalNominaScreen(),
    'Operación': ReportesOperacionScreen(),
    'Patrimonio': ReportesPatrimonioScreen(),
  };

  group('Reportes — con datos, rango anual (granularidad mensual)', () {
    setUp(() async {
      await abrirContenedor();
      await sembrarDatos();
      // Año actual: obliga a la serie a agrupar por mes y a los ejes a
      // abreviar importes de siete cifras.
      container.read(reportesRangoControllerProvider.notifier).aplicarPreset(PresetRangoReportes.anioActual);
      await precargarPestanas();
    });

    tearDown(cerrarContenedor);

    for (final pantalla in pantallas.entries) {
      for (final ancho in _anchos.entries) {
        for (final oscuro in [false, true]) {
          testWidgets(
            '${pantalla.key} a ${ancho.key}px, tema ${oscuro ? 'oscuro' : 'claro'}: sin overflow',
            (tester) async {
              await pintar(tester, tamano: ancho.value, oscuro: oscuro, pantalla: pantalla.value);
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  });

  group('Reportes — base vacía, estados vacíos explícitos', () {
    setUp(() async {
      await abrirContenedor();
      await precargarPestanas();
    });
    tearDown(cerrarContenedor);

    for (final pantalla in pantallas.entries) {
      for (final ancho in _anchos.entries) {
        testWidgets(
          '${pantalla.key} a ${ancho.key}px sin ningún dato: estado vacío, sin excepción',
          (tester) async {
            await pintar(tester, tamano: ancho.value, oscuro: false, pantalla: pantalla.value);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  group('Reportes — rango de un solo día (granularidad diaria, una sola barra)', () {
    setUp(() async {
      await abrirContenedor();
      await sembrarDatos();
      final hoy = DateTime.now();
      final controller = container.read(reportesRangoControllerProvider.notifier);
      controller.cambiarInicio(DateTime(hoy.year, hoy.month, hoy.day));
      controller.cambiarFin(DateTime(hoy.year, hoy.month, hoy.day));
      await precargarPestanas();
    });

    tearDown(cerrarContenedor);

    for (final ancho in _anchos.entries) {
      testWidgets('General a ${ancho.key}px con un rango de un día: sin excepción', (tester) async {
        await pintar(tester, tamano: ancho.value, oscuro: false, pantalla: const ReportesGeneralScreen());
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Reportes — cada sección de Finanzas (Etapa B)', () {
    setUp(() async {
      await abrirContenedor();
      await sembrarDatos();
      await precargarPestanas();
    });

    tearDown(cerrarContenedor);

    for (final seccion in SeccionFinanzas.values) {
      for (final ancho in _anchos.entries) {
        for (final oscuro in [false, true]) {
          testWidgets(
            'Finanzas · ${seccion.name} a ${ancho.key}px, tema ${oscuro ? 'oscuro' : 'claro'}: sin overflow',
            (tester) async {
              container.read(reportesFinanzasControllerProvider.notifier).cambiarSeccion(seccion);
              await pintar(tester, tamano: ancho.value, oscuro: oscuro, pantalla: const ReportesFinanzasScreen());
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  });

  group('Reportes — secciones de Finanzas con la base vacía', () {
    setUp(() async {
      await abrirContenedor();
      await precargarPestanas();
    });

    tearDown(cerrarContenedor);

    for (final seccion in SeccionFinanzas.values) {
      for (final ancho in _anchos.entries) {
        testWidgets('Finanzas · ${seccion.name} a ${ancho.key}px sin datos: estado vacío, sin excepción', (tester) async {
          container.read(reportesFinanzasControllerProvider.notifier).cambiarSeccion(seccion);
          await pintar(tester, tamano: ancho.value, oscuro: false, pantalla: const ReportesFinanzasScreen());
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
  group('Patrimonio — con filtros activos (chips de nombre largo)', () {
    setUp(() async {
      await abrirContenedor();
      await sembrarDatos();
      container.read(reportesRangoControllerProvider.notifier).aplicarPreset(PresetRangoReportes.anioActual);
      await precargarPestanas();

      // El filtro se arma con el CATÁLOGO real ya cargado: así los chips
      // llevan los nombres largos de verdad, que son los que aprietan el
      // layout a 500px.
      final catalogo = container.read(reportesPatrimonioControllerProvider).analisis!.catalogo;
      container.read(reportesPatrimonioControllerProvider.notifier).cambiarFiltro(
            FiltroPatrimonio(
              empleadoId: catalogo.empleados.first.empleadoId,
              servicioId: catalogo.servicios.isEmpty ? null : catalogo.servicios.first.servicioId,
              resolucion: ResolucionResguardoBaja.devuelto,
              soloPendientes: false,
            ),
          );
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });

    tearDown(cerrarContenedor);

    for (final ancho in _anchos.entries) {
      for (final oscuro in [false, true]) {
        testWidgets(
          'Patrimonio filtrado a ${ancho.key}px, tema ${oscuro ? 'oscuro' : 'claro'}: sin overflow',
          (tester) async {
            await pintar(tester, tamano: ancho.value, oscuro: oscuro, pantalla: const ReportesPatrimonioScreen());
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });
}