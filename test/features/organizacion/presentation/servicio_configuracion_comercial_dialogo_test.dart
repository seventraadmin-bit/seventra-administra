// Reproducción del hallazgo real reportado por Marlon (Etapa 15,
// Comercial): en MORGAN ATLACOMULCO, una línea comercial vigente con
// historia real (ya generó Agenda) parecía no mostrar ningún menú de
// acciones — solo "Agregar línea". Esta prueba arma el mismo escenario
// con datos reales (Puesto Elemento Operativo, turno Mixto, cantidad 3,
// precio $16,450.00, vigente desde 24/04/2026) y genera un
// `DocumentoPorEmitirLinea` real contra esa vigencia (la misma señal
// que usa `esCorregible`) para confirmar, contra la UI real, que:
//  - el botón ⋮ siempre existe cuando hay acciones de fila;
//  - "Corregir" se oculta correctamente cuando ya no es legal
//    corregir in-place (hay historia real);
//  - "Nueva vigencia", "Historial", "Cerrar línea" y "Eliminar
//    físicamente" (Maestro) NO desaparecen por eso — nunca se
//    condicionó el menú completo, ni esa acción en particular, a
//    `esCorregible`.
// Una segunda prueba, con una línea recién creada (sin historia),
// confirma el caso contrario: "Corregir" sí aparece, y "Eliminar
// físicamente" sí puede completarse (ruta segura para limpiar datos de
// prueba sin historia real).
//
// La primera versión de estas pruebas usaba `tester.ensureVisible(...)`
// antes de tocar el botón ⋮, y ningún ancho de ventana explícito — eso
// las hacía pasar aunque el ⋮ estuviera realmente fuera del viewport
// visible (`ensureVisible` desplaza el scroll programáticamente, algo
// que un usuario real con mouse no puede hacer si no hay ninguna señal
// de que existe contenido oculto a la derecha). Esa fue exactamente la
// causa real del reporte de Marlon: `RisegTableBase._minTableWidth()`
// exigía más ancho del que la página realmente tiene disponible
// (`AppBreakpoints.wide` menos el padding de página y de `RisegCard`),
// forzando un scroll horizontal que dejaba la columna de acciones (56px)
// fuera de vista, sin ninguna barra de scroll prominente. Estas pruebas
// ahora fijan un ancho realista (~1400px, el mismo orden que la captura
// real de Marlon) y verifican la posición geométrica del botón ⋮ ANTES
// de cualquier `ensureVisible` — nunca dan la visibilidad por sentada.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';

import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/configuracion_cobro_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/documento_por_emitir_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_portal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_etapa_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_documento_manual_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/ensamblar_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/servicio_expediente_screen.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

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

/// Ancho ~1400px, mismo orden de magnitud que la captura real de
/// Marlon — deliberadamente SIN `ensureVisible` en las pruebas que
/// consumen este host: si el ⋮ no cabe en este viewport, la prueba debe
/// fallar de forma honesta, no ocultarlo con un scroll programático.
/// Altura generosa (2400) deliberada: el expediente completo de
/// Servicio es más alto que cualquier ventana real — el scroll VERTICAL
/// de página sí es esperado y sí tiene una barra visible (a diferencia
/// del scroll horizontal interno de la tabla, que es el bug real). Se
/// fija así para que la prueba verifique específicamente el eje
/// horizontal, sin que el vertical la contamine.
const _anchoVentanaReal = Size(1400, 2400);

Future<void> _pump(WidgetTester tester, AppDatabase db, Widget pantalla, {Size? viewport}) async {
  if (viewport != null) {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

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

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // Fila real de Usuario para el `usuarioId` de `_SesionControllerDePrueba`
    // (Etapa 11D): `actorUsuarioId` es una FK real hacia `Usuario` en
    // `EliminacionFisicaEvento` — sin esta fila, "Eliminar físicamente"
    // sin dependencias bloqueantes falla al insertar el evento de
    // auditoría (mismo hallazgo real que en otros archivos de prueba de
    // esta etapa).
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-prueba'),
            nombre: 'Usuario de prueba',
            nombreUsuario: 'usuario-prueba',
            passwordHash: 'x',
          ),
        );
  });

  tearDown(() => db.close());

  /// Arma exactamente el escenario reportado por Marlon: Servicio
  /// "Vigilancia Morgan Atlacomulco", una línea comercial (Elemento
  /// Operativo, turno Mixto, cantidad 3, $16,450.00, vigente desde
  /// 24/04/2026) y, si [conHistoriaReal], un documento de Agenda real
  /// generado contra esa vigencia (misma señal que usa `esCorregible`
  /// en producción — nunca se simula el booleano directamente).
  Future<({String servicioId, String lineaId})> crearMorganAtlacomulco({required bool conHistoriaReal}) async {
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final clienteRepo = ClienteRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    final clientePortalRepo = ClientePortalRepositoryImpl(db);
    final comercialRepo = ServicioComercialRepositoryImpl(db);
    final configuracionCobroRepo = ConfiguracionCobroRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);

    final crearCliente = CrearClienteUseCase(clienteRepo, generarCodigo);
    final cliente = await crearCliente.ejecutar(nombreComercial: 'Morgan Atlacomulco');
    final clienteId = cliente.when(ok: (c) => c.id, failure: (_) => throw StateError('no debería fallar'));

    final crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, ServicioValidator(clienteRepo, catalogoRepo));
    final creado = await crearServicio.ejecutar(
      clienteId: clienteId,
      borrador: ServicioBorrador(
        nombre: 'Vigilancia Morgan Atlacomulco',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 4, 1),
      ),
    );
    final servicioId = (creado as GuardarServicioExitoso).servicio.id;

    final puesto = await puestoRepo.crear(
      PuestoCompanion.insert(
        codigo: 'PUE-MORGAN',
        nombre: 'Elemento Operativo',
        areaId: SeedIds.areaOperaciones,
        tipo: 'operativo',
        nivelJerarquico: 5,
      ),
    );

    final crearLineaComercial = CrearLineaComercialUseCase(
      comercialRepo,
      servicioRepo,
      LineaComercialValidator(puestoRepo, catalogoRepo, servicioRepo, configuracionCobroRepo),
    );
    final resultadoLinea = await crearLineaComercial.ejecutar(
      servicioId: servicioId,
      borrador: LineaComercialBorrador(
        puestoId: puesto.id,
        modalidadTurnoId: SeedIds.modalidadTurnoMixto,
        cantidadElementos: 3,
        precioUnitario: 1645000,
        tratamientoIva: TratamientoIva.noAplica,
        fechaInicioVigencia: DateTime(2026, 4, 24),
      ),
    );
    final linea = (resultadoLinea as CrearLineaComercialExitoso).linea;

    if (conHistoriaReal) {
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
          fechaInicioVigencia: DateTime(2026, 4, 24),
        ),
        etapas: const [],
      );

      final documentoRepo = DocumentoPorEmitirRepositoryImpl(db, AttachmentRepository(db), CuentaPorCobrarRepositoryImpl(db));
      final ensamblar = EnsamblarDocumentoPorEmitirUseCase(comercialRepo, configuracionCobroRepo);
      final crearManual = CrearDocumentoManualUseCase(documentoRepo, configuracionCobroRepo, servicioRepo, ensamblar, generarCodigo);

      // Mismo camino real que Agenda usaría — genera un
      // `DocumentoPorEmitirLinea` que referencia esta vigencia
      // comercial, la única señal que `tieneDocumentosGenerados` (y por
      // lo tanto `esCorregible`) consulta en producción.
      await crearManual.ejecutar(
        clienteId: clienteId,
        servicioIds: [servicioId],
        periodoInicio: DateTime(2026, 4, 24),
        periodoFin: DateTime(2026, 5, 23),
      );
    }

    return (servicioId: servicioId, lineaId: linea.id);
  }

  testWidgets(
    'MORGAN con historia real, ~1400px: el ⋮ es visible dentro del viewport SIN scroll horizontal, con '
    'Nueva vigencia/Historial/Cerrar línea/Eliminar físicamente — Corregir se oculta solo',
    (tester) async {
      final morgan = await crearMorganAtlacomulco(conHistoriaReal: true);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await _pump(tester, db, ServicioExpedienteScreen(servicioId: morgan.servicioId), viewport: _anchoVentanaReal);
      expect(tester.takeException(), isNull);

      final botonMenu = find.byKey(Key('servicio_comercial_linea_menu_${morgan.lineaId}'));
      expect(botonMenu, findsOneWidget, reason: 'el ⋮ debe existir siempre que haya al menos una acción disponible');

      // Geometría real, ANTES de cualquier `ensureVisible` — la
      // reproducción exacta del reporte: sin fijar esto, la prueba
      // podría "pasar" aunque el botón esté desplazado fuera del
      // viewport por el scroll horizontal forzado de la tabla.
      final rect = tester.getRect(botonMenu);
      expect(
        rect.right,
        lessThanOrEqualTo(_anchoVentanaReal.width),
        reason: 'el ⋮ debe caber dentro del ancho visible sin necesitar scroll horizontal',
      );
      expect(rect.left, greaterThanOrEqualTo(0), reason: 'no debe estar desplazado fuera del borde izquierdo tampoco');

      // Toque directo, sin `ensureVisible` — así es como un usuario real
      // interactúa: si esto falla, el botón está ahí pero cubierto o
      // fuera de alcance real del puntero.
      await tester.tap(botonMenu);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.widgetWithText(PopupMenuItem<VoidCallback>, 'Nueva vigencia'), findsOneWidget);
      expect(find.widgetWithText(PopupMenuItem<VoidCallback>, 'Historial'), findsOneWidget);
      expect(find.widgetWithText(PopupMenuItem<VoidCallback>, 'Cerrar línea'), findsOneWidget);
      expect(
        find.widgetWithText(PopupMenuItem<VoidCallback>, 'Corregir'),
        findsNothing,
        reason: 'ya generó Agenda — corregir in-place reescribiría historia real',
      );
      expect(
        find.widgetWithText(PopupMenuItem<VoidCallback>, l10n.eliminacionFisicaAccionMenu),
        findsOneWidget,
        reason: '"Eliminar físicamente" ya no se oculta por esCorregible == false — la decide el caso de uso, no la UI',
      );

      // Intentarlo de verdad: debe rechazarse con el mensaje específico
      // de dependencias reales, sin borrar nada — nunca un CASCADE
      // silencioso.
      await tester.tap(find.widgetWithText(PopupMenuItem<VoidCallback>, l10n.eliminacionFisicaAccionMenu).last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, 'prueba');
      await tester.tap(find.text(l10n.eliminacionFisicaBotonConfirmar).last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Ya generó documentos de Agenda'), findsOneWidget);
      expect(
        find.byKey(Key('servicio_comercial_linea_menu_${morgan.lineaId}')),
        findsOneWidget,
        reason: 'la línea sigue existiendo — el rechazo no debe borrar nada',
      );
    },
  );

  testWidgets(
    'línea recién creada, sin historia, ~1400px: el ⋮ es visible sin scroll; Corregir aparece y '
    '"Eliminar físicamente" sí completa (ruta segura para limpiar datos de prueba sin historia real)',
    (tester) async {
      final morgan = await crearMorganAtlacomulco(conHistoriaReal: false);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await _pump(tester, db, ServicioExpedienteScreen(servicioId: morgan.servicioId), viewport: _anchoVentanaReal);

      final botonMenu = find.byKey(Key('servicio_comercial_linea_menu_${morgan.lineaId}'));
      expect(botonMenu, findsOneWidget);

      final rect = tester.getRect(botonMenu);
      expect(rect.right, lessThanOrEqualTo(_anchoVentanaReal.width));

      await tester.tap(botonMenu);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(PopupMenuItem<VoidCallback>, 'Corregir'), findsOneWidget);
      expect(find.widgetWithText(PopupMenuItem<VoidCallback>, 'Nueva vigencia'), findsOneWidget);

      await tester.tap(find.widgetWithText(PopupMenuItem<VoidCallback>, l10n.eliminacionFisicaAccionMenu).last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, 'limpieza de datos de prueba');
      await tester.tap(find.text(l10n.eliminacionFisicaBotonConfirmar).last);
      await tester.pumpAndSettle();

      expect(find.text(l10n.eliminacionFisicaExito), findsOneWidget);
      expect(
        find.byKey(Key('servicio_comercial_linea_menu_${morgan.lineaId}')),
        findsNothing,
        reason: 'sin historia real, la línea de prueba sí puede eliminarse por completo',
      );
    },
  );
}
