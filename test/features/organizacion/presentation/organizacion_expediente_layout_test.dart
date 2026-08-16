// Pruebas visuales del rediseño de layout de Organización (Etapa 15,
// hallazgo real) — Empresa/Sucursal/Puesto/Cliente/Servicio deben
// renderizar sin overflow tanto en ancho amplio (donde `RisegFieldGrid`
// muestra 2-3 columnas) como en ancho reducido (1 columna, el mínimo
// soportado hoy), en consulta y en edición. La verificación fina de
// "el grid realmente cambia de columnas" vive en
// `test/design_system/riseg_field_grid_test.dart`; aquí se confirma
// además sobre una pantalla real (Empresa) que dos campos contiguos
// comparten fila en ancho amplio y se apilan en ancho reducido.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';

import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/configuracion_cobro_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_portal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/sucursal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_etapa_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_entidad_fiscal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_puesto_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_sucursal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/entidad_fiscal_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_entidad_fiscal_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_puesto_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/puesto_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/data/repositories/area_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';

import 'package:riseg_one/features/organizacion/presentation/clientes/cliente_expediente_screen.dart';
import 'package:riseg_one/features/organizacion/presentation/empresa/empresa_expediente_screen.dart';
import 'package:riseg_one/features/organizacion/presentation/puestos/puesto_expediente_screen.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/servicio_expediente_screen.dart';
import 'package:riseg_one/features/organizacion/presentation/sucursales/sucursal_expediente_screen.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

const _anchoAmplio = 1600.0;
// 580 (no 500): a esa altura ya se comprueba el grid en 1 columna
// (por debajo de AppBreakpoints.compact = 600) sin disparar dos
// overflows preexistentes y ajenos a este rediseño — el toolbar de
// "Ubicaciones" en Sucursal (ubicaciones_arbol_widget.dart:237) y el
// estado vacío de "Dirección operativa" en Servicio
// (servicio_direccion_operativa_section.dart:38), ninguno de los dos
// usa `RisegFieldGrid` ni cambió en este hallazgo — quedan registrados
// aparte en project_riseg_one_pendientes_pruebas_funcionales.md.
const _anchoReducido = 580.0;

class _SesionControllerDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-prueba',
      nombre: 'Usuario de prueba',
      nombreUsuario: 'prueba',
      esMaestro: true,
      permisos: {},
    );
  }
}

Future<void> _fijarAncho(WidgetTester tester, double ancho) async {
  tester.view.physicalSize = Size(ancho, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(WidgetTester tester, AppDatabase db, Widget pantalla) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionControllerDePrueba.new),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: pantalla,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Empresa, a diferencia de Sucursal/Puesto/Cliente/Servicio, no trae
/// su propio `Scaffold` (se monta directo bajo `/organizacion`, sin
/// AppBar propio) — sin este envoltorio, sus `RisegTextField` en modo
/// edición no encuentran un `Material` ancestro (mismo criterio que
/// `empresa_expediente_screen_test.dart`).
Future<void> _pumpEmpresa(WidgetTester tester, AppDatabase db) => _pump(tester, db, const Scaffold(body: EmpresaExpedienteScreen()));

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('Empresa', () {
    testWidgets('ancho amplio: código y razón social comparten fila (grid de 3 columnas), sin overflow', (
      tester,
    ) async {
      await _fijarAncho(tester, _anchoAmplio);
      await _pumpEmpresa(tester, db);

      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      final yCodigo = tester.getTopLeft(find.text(l10n.empresaCampoCodigo)).dy;
      final yRazonSocial = tester.getTopLeft(find.text(l10n.empresaCampoRazonSocial)).dy;
      expect(yCodigo, yRazonSocial);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ancho reducido: código y razón social se apilan (1 columna), sin overflow', (tester) async {
      await _fijarAncho(tester, _anchoReducido);
      await _pumpEmpresa(tester, db);

      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      final yCodigo = tester.getTopLeft(find.text(l10n.empresaCampoCodigo)).dy;
      final yRazonSocial = tester.getTopLeft(find.text(l10n.empresaCampoRazonSocial)).dy;
      expect(yRazonSocial, greaterThan(yCodigo));
      expect(tester.takeException(), isNull);
    });

    testWidgets('edición: ancho amplio y reducido sin overflow', (tester) async {
      await _fijarAncho(tester, _anchoAmplio);
      await _pumpEmpresa(tester, db);
      await tester.tap(find.byKey(const Key('empresa_expediente_boton_editar')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await _fijarAncho(tester, _anchoReducido);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Sucursal', () {
    Future<String> crearSucursal() async {
      final crear = CrearSucursalUseCase(SucursalRepositoryImpl(db), GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      final r = await crear.ejecutar(nombre: 'Sucursal Norte', tipoSucursalId: SeedIds.tipoSucursalBaseOperativa);
      return r.when(ok: (s) => s.id, failure: (f) => throw StateError(f.message));
    }

    testWidgets('ancho amplio y reducido sin overflow, consulta y edición', (tester) async {
      final sucursalId = await crearSucursal();

      await _fijarAncho(tester, _anchoAmplio);
      await _pump(tester, db, SucursalExpedienteScreen(sucursalId: sucursalId));
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('sucursal_expediente_boton_editar')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await _fijarAncho(tester, _anchoReducido);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Puesto', () {
    Future<String> crearPuesto() async {
      final crear = CrearPuestoUseCase(
        PuestoRepositoryImpl(db),
        GenerarCodigoUseCase(CodigoSecuenciaService(db)),
        PuestoValidator(AreaRepositoryImpl(db)),
      );
      final r = await crear.ejecutar(
        const PuestoBorrador(nombre: 'Guardia Norte', areaId: SeedIds.areaOperaciones, tipo: TipoPuesto.operativo, nivelJerarquico: 1),
      );
      return (r as GuardarPuestoExitoso).puesto.id;
    }

    testWidgets('ancho amplio y reducido sin overflow, consulta y edición', (tester) async {
      final puestoId = await crearPuesto();

      await _fijarAncho(tester, _anchoAmplio);
      await _pump(tester, db, PuestoExpedienteScreen(puestoId: puestoId));
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('puesto_expediente_boton_editar')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await _fijarAncho(tester, _anchoReducido);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Cliente', () {
    Future<String> crearCliente() async {
      final crear = CrearClienteUseCase(ClienteRepositoryImpl(db), GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      final r = await crear.ejecutar(nombreComercial: 'Sportium');
      return r.when(ok: (c) => c.id, failure: (f) => throw StateError(f.message));
    }

    testWidgets('ancho amplio y reducido sin overflow, consulta y edición', (tester) async {
      final clienteId = await crearCliente();

      await _fijarAncho(tester, _anchoAmplio);
      await _pump(tester, db, ClienteExpedienteScreen(clienteId: clienteId));
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('cliente_expediente_boton_editar')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await _fijarAncho(tester, _anchoReducido);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // Etapa 15, punto 1: "datos completos no generan tarjetas estrechas
    // absurdas" — con Entidad fiscal y Contacto capturados (no solo el
    // caso vacío de arriba), y con el nuevo menú ⋮ de Maestro abierto.
    testWidgets('con Entidad fiscal y Contacto capturados, sin overflow en ancho reducido', (tester) async {
      final clienteId = await crearCliente();
      final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
      final crearEntidadFiscal = CrearEntidadFiscalUseCase(
        entidadFiscalRepo,
        GenerarCodigoUseCase(CodigoSecuenciaService(db)),
        EntidadFiscalValidator(ClienteRepositoryImpl(db), entidadFiscalRepo),
      );
      await crearEntidadFiscal.ejecutar(
        clienteId: clienteId,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium Club Uno SA de CV', rfc: 'SPO010101AA1'),
      );
      await ClienteRepositoryImpl(
        db,
      ).agregarContacto(ContactoCompanion.insert(clienteId: clienteId, nombre: 'Juan Pérez', tipo: 'comercial'));

      await _fijarAncho(tester, _anchoReducido);
      await _pump(tester, db, ClienteExpedienteScreen(clienteId: clienteId));
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('cliente_menu_acciones')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('cliente_accion_eliminar_fisicamente')), findsOneWidget);
    });
  });

  group('Servicio', () {
    Future<({String servicioId, String clienteId})> crearServicio() async {
      final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
      final clienteRepo = ClienteRepositoryImpl(db);
      final validator = ServicioValidator(clienteRepo, CatalogoRepositoryImpl(db));
      final crearCliente = CrearClienteUseCase(clienteRepo, generarCodigo);
      final crear = CrearServicioUseCase(ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)), generarCodigo, validator);

      final cliente = await crearCliente.ejecutar(nombreComercial: 'Sportium');
      final clienteId = cliente.when(ok: (c) => c.id, failure: (_) => throw StateError('no debería fallar'));
      final creado = await crear.ejecutar(
        clienteId: clienteId,
        borrador: ServicioBorrador(
          nombre: 'Vigilancia Sportium Toluca',
          tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
          fechaInicio: DateTime(2026, 1, 1),
        ),
      );
      return (servicioId: (creado as GuardarServicioExitoso).servicio.id, clienteId: clienteId);
    }

    testWidgets('ancho amplio y reducido sin overflow, consulta y edición', (tester) async {
      final servicioId = (await crearServicio()).servicioId;

      await _fijarAncho(tester, _anchoAmplio);
      await _pump(tester, db, ServicioExpedienteScreen(servicioId: servicioId));
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('servicio_expediente_boton_editar')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await _fijarAncho(tester, _anchoReducido);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // Etapa 15, punto 1: Vinculaciones (externas + internas), Configuración
    // comercial y Configuración de cobro con datos reales capturados — el
    // caso vacío de arriba no ejercita ninguno de los dos `RisegFieldGrid`
    // nuevos de `servicio_vinculaciones_section.dart`/
    // `servicio_personal_asignado_section.dart` ni las filas reales de las
    // tablas de Configuración comercial/cobro.
    testWidgets('con vinculaciones, línea comercial y Configuración de cobro, sin overflow en ancho reducido', (
      tester,
    ) async {
      final creado = await crearServicio();
      final servicioId = creado.servicioId;
      final clienteId = creado.clienteId;
      final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));

      final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
      final clientePortalRepo = ClientePortalRepositoryImpl(db);
      final crearEntidadFiscal = CrearEntidadFiscalUseCase(
        entidadFiscalRepo,
        GenerarCodigoUseCase(CodigoSecuenciaService(db)),
        EntidadFiscalValidator(ClienteRepositoryImpl(db), entidadFiscalRepo),
      );
      final entidad = (await crearEntidadFiscal.ejecutar(
        clienteId: clienteId,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium Club Uno SA de CV', rfc: 'SPO010101AA1'),
      )) as GuardarEntidadFiscalExitoso;
      await servicioRepo.asignarEntidadFiscal(servicioId: servicioId, entidadFiscalId: entidad.entidadFiscal.id);

      final contacto = await ClienteRepositoryImpl(
        db,
      ).agregarContacto(ContactoCompanion.insert(clienteId: clienteId, nombre: 'Juan Pérez', tipo: 'comercial'));
      await servicioRepo.asignarResponsableCliente(servicioId: servicioId, contactoId: contacto.id);

      final sucursal = await CrearSucursalUseCase(
        SucursalRepositoryImpl(db),
        GenerarCodigoUseCase(CodigoSecuenciaService(db)),
      ).ejecutar(nombre: 'Sucursal Centro', tipoSucursalId: SeedIds.tipoSucursalBaseOperativa);
      final sucursalId = sucursal.when(ok: (s) => s.id, failure: (_) => throw StateError('no debería fallar'));
      await servicioRepo.asignarSucursalAdministrativa(servicioId: servicioId, sucursalId: sucursalId);
      await servicioRepo.guardarResponsableInterno(servicioId: servicioId, texto: 'María López');

      final puesto = await PuestoRepositoryImpl(db).crear(
        PuestoCompanion.insert(
          codigo: 'PUE-0001',
          nombre: 'Guardia',
          areaId: SeedIds.areaOperaciones,
          tipo: 'operativo',
          nivelJerarquico: 5,
        ),
      );
      final catalogoRepo = CatalogoRepositoryImpl(db);
      final comercialRepo = ServicioComercialRepositoryImpl(db);
      final configuracionCobroRepo = ConfiguracionCobroRepositoryImpl(db);
      final crearLineaComercial = CrearLineaComercialUseCase(
        comercialRepo,
        servicioRepo,
        LineaComercialValidator(PuestoRepositoryImpl(db), catalogoRepo, servicioRepo, configuracionCobroRepo),
      );
      await crearLineaComercial.ejecutar(
        servicioId: servicioId,
        borrador: LineaComercialBorrador(
          puestoId: puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 2,
          precioUnitario: 1500000,
          tratamientoIva: TratamientoIva.noAplica,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );

      final crearConfiguracionCobro = CrearConfiguracionCobroUseCase(
        configuracionCobroRepo,
        servicioRepo,
        ConfiguracionCobroValidator(servicioRepo, entidadFiscalRepo, catalogoRepo, comercialRepo, clientePortalRepo),
        const ConfiguracionCobroEtapaValidator(),
      );
      await crearConfiguracionCobro.ejecutar(
        servicioId: servicioId,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );

      await _fijarAncho(tester, _anchoReducido);
      await _pump(tester, db, ServicioExpedienteScreen(servicioId: servicioId));
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('servicio_menu_acciones')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('servicio_accion_eliminar_fisicamente')), findsOneWidget);

      await _fijarAncho(tester, _anchoAmplio);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
