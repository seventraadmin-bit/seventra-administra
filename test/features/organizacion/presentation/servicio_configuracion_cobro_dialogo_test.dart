// Pruebas de widget del flujo dinámico de etapas de cobro (Etapa 15,
// Parte B) — verifica que Corregir/Nueva vigencia realmente prellenan
// la secuencia de etapas ya capturada (no solo las 3 fijas de antes),
// que agregar/reordenar/quitar una etapa personalizada funciona desde
// la UI real, y que el formulario (con varias etapas expandidas a la
// vez) no produce overflow ni en ancho normal ni en ancho reducido —
// mismo criterio y mismos anchos que `organizacion_expediente_layout_test.dart`.
// Las etapas se modifican únicamente a través de este mismo ciclo
// Corregir/Nueva vigencia (nunca una edición independiente), así que
// esta es la única superficie de UI que necesita cubrirse.

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
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_etapa_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_etapa_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/servicio_expediente_screen.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/widgets/servicio_configuracion_cobro_section.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

const _anchoAmplio = 1600.0;
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

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  /// Servicio real con una Configuración de cobro de 4 etapas
  /// encadenadas (mismo escenario Sportium de
  /// `documento_por_emitir_test.dart`/`calcular_fechas_cobro_test.dart`):
  /// Emisión → Validación por correo → Carga a portal → Pago esperado.
  Future<String> crearServicioConEtapasSportium() async {
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final clienteRepo = ClienteRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    final clientePortalRepo = ClientePortalRepositoryImpl(db);
    final comercialRepo = ServicioComercialRepositoryImpl(db);
    final configuracionCobroRepo = ConfiguracionCobroRepositoryImpl(db);

    final crearCliente = CrearClienteUseCase(clienteRepo, generarCodigo);
    final cliente = await crearCliente.ejecutar(nombreComercial: 'Sportium');
    final clienteId = cliente.when(ok: (c) => c.id, failure: (_) => throw StateError('no debería fallar'));

    final crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, ServicioValidator(clienteRepo, catalogoRepo));
    final creado = await crearServicio.ejecutar(
      clienteId: clienteId,
      borrador: ServicioBorrador(
        nombre: 'Club Sportium Toluca',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    final servicioId = (creado as GuardarServicioExitoso).servicio.id;

    final crearConfiguracionCobro = CrearConfiguracionCobroUseCase(
      configuracionCobroRepo,
      servicioRepo,
      ConfiguracionCobroValidator(servicioRepo, entidadFiscalRepo, catalogoRepo, comercialRepo, clientePortalRepo),
      const ConfiguracionCobroEtapaValidator(),
    );

    const emisionId = 'etapa-emision';
    const validacionId = 'etapa-validacion';
    const portalId = 'etapa-portal';
    const pagoId = 'etapa-pago';

    await crearConfiguracionCobro.ejecutar(
      servicioId: servicioId,
      borrador: ConfiguracionCobroBorrador(
        tipoDocumento: TipoDocumentoCobro.reciboDePago,
        frecuenciaId: SeedIds.frecuenciaCobroMensual,
        diaInicioPeriodo: 21,
        agrupacion: AgrupacionCobro.porServicio,
        metodo: MetodoPagoCobro.noAplica,
        requiereComplemento: false,
        fechaInicioVigencia: DateTime(2026, 1, 1),
      ),
      etapas: const [
        EtapaCobroBorrador(
          id: emisionId,
          tipoSistema: TipoEventoCobro.emision,
          orden: 0,
          tipoRegla: TipoReglaEvento.diaFijoDelMes,
          mesRelativo: MesRelativoCobro.siguiente,
          diaDelMes: 21,
        ),
        EtapaCobroBorrador(
          id: validacionId,
          nombre: 'Validación por correo',
          orden: 1,
          tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe,
          offsetDias: 0,
          etapaReferenciaId: emisionId,
        ),
        EtapaCobroBorrador(
          id: portalId,
          nombre: 'Carga a portal',
          orden: 2,
          tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe,
          offsetDias: 4,
          etapaReferenciaId: validacionId,
        ),
        EtapaCobroBorrador(
          id: pagoId,
          tipoSistema: TipoEventoCobro.pagoEsperado,
          orden: 3,
          tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe,
          offsetDias: 7,
          etapaReferenciaId: portalId,
        ),
      ],
    );

    return servicioId;
  }

  testWidgets(
    'Corregir: prellena las 4 etapas reales (no solo Emisión/Pago) y no produce overflow en ancho amplio ni reducido',
    (tester) async {
      final servicioId = await crearServicioConEtapasSportium();
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await _fijarAncho(tester, _anchoAmplio);
      await _pump(tester, db, ServicioExpedienteScreen(servicioId: servicioId));
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.byKey(const Key('servicio_cobro_boton_corregir')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('servicio_cobro_boton_corregir')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // La pantalla de fondo repite algunos textos (secuencia visual +
      // fechas calculadas) detrás del diálogo — todo lo específico del
      // formulario se busca dentro del `Dialog`, nunca en la pantalla
      // completa.
      final dialogo = find.byType(Dialog);
      expect(dialogo, findsOneWidget);
      expect(find.descendant(of: dialogo, matching: find.text(l10n.servicioCobroCorregirDialogoTitulo)), findsOneWidget);

      // Las 4 etapas reales, no las 3 fijas del modelo viejo.
      expect(find.descendant(of: dialogo, matching: find.byType(EtapaCobroFormRow)), findsNWidgets(4));
      expect(find.descendant(of: dialogo, matching: find.text('Validación por correo')), findsOneWidget);
      expect(find.descendant(of: dialogo, matching: find.text('Carga a portal')), findsOneWidget);

      await _fijarAncho(tester, _anchoReducido);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Expandir una etapa personalizada en ancho reducido — el
      // formulario completo de su regla (Select de tipo de regla +
      // Select de referencia) es el punto de mayor riesgo de overflow.
      await tester.tap(find.descendant(of: dialogo, matching: find.text('Carga a portal')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.descendant(of: dialogo, matching: find.text(l10n.servicioCobroCampoTipoRegla)), findsOneWidget);

      await tester.tap(find.descendant(of: dialogo, matching: find.text(l10n.servicioVinculacionDialogoBotonCancelar)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Nueva vigencia en ancho reducido: agregar una etapa personalizada, reordenarla y quitarla, sin overflow',
    (tester) async {
      final servicioId = await crearServicioConEtapasSportium();
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      await _fijarAncho(tester, _anchoReducido);
      await _pump(tester, db, ServicioExpedienteScreen(servicioId: servicioId));
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text(l10n.servicioCobroBotonNuevaVigencia));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.servicioCobroBotonNuevaVigencia));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final dialogo = find.byType(Dialog);
      expect(find.descendant(of: dialogo, matching: find.text(l10n.servicioCobroNuevaVigenciaDialogoTitulo)), findsOneWidget);
      expect(find.byType(EtapaCobroFormRow), findsNWidgets(4), reason: 'prellenada con la vigencia actual, igual que Corregir');

      await tester.tap(find.byKey(const Key('servicio_cobro_boton_agregar_etapa')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(EtapaCobroFormRow), findsNWidgets(5));

      // La etapa nueva se agrega expandida — captura el nombre libre.
      // Se lee el valor directo del controller (no el texto del
      // encabezado, que solo se repinta si esa fila vuelve a
      // reconstruirse) para no depender del momento exacto del rebuild.
      final filaNueva = find.byType(EtapaCobroFormRow).last;
      final campoNombre = find.descendant(of: filaNueva, matching: find.byType(TextFormField)).first;
      await tester.enterText(campoNombre, 'Autorización final');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'formulario completo de una etapa personalizada expandida, ancho reducido');
      expect(tester.widget<TextFormField>(campoNombre).controller!.text, 'Autorización final');

      // Quitar la etapa personalizada recién agregada (sigue siendo la
      // última fila — nada la reordenó todavía).
      final botonQuitar = find.descendant(of: filaNueva, matching: find.byIcon(Icons.close));
      await tester.tap(botonQuitar);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(EtapaCobroFormRow), findsNWidgets(4), reason: 'de vuelta a las 4 etapas originales');

      // Reordenar: bajar Emisión (sigue sin ser removible, pero sí
      // puede cambiar de posición — "La secuencia debe ser ordenable").
      final filaEmision = find.widgetWithText(EtapaCobroFormRow, l10n.servicioCobroEventoEmision);
      expect(find.descendant(of: filaEmision, matching: find.byIcon(Icons.close)), findsNothing, reason: 'Emisión nunca es removible');
      await tester.tap(find.descendant(of: filaEmision, matching: find.byIcon(Icons.arrow_downward)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(of: find.byType(EtapaCobroFormRow).first, matching: find.text(l10n.servicioCobroEventoEmision)),
        findsNothing,
        reason: 'Emisión ya no es la primera fila tras bajarla',
      );

      await _fijarAncho(tester, _anchoAmplio);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
