// Etapa 15 (Agenda) — pruebas de UI del detalle de documento:
// acciones contextuales según tipo/estatus (Generar recibo PDF solo
// para Recibo de pago, nunca CFDI; menú ⋮ de Eliminar físicamente solo
// para Maestro) y layout sin overflow en ancho normal/reducido.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/configuracion_cobro_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentStorageProvider;
import 'package:riseg_one/features/organizacion/presentation/agenda/widgets/agenda_detalle_dialog.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

class _SesionControllerDePrueba extends SesionController {
  _SesionControllerDePrueba(this._esMaestro);
  final bool _esMaestro;

  @override
  SesionUsuario? build() {
    return SesionUsuario(
      usuarioId: 'usuario-prueba',
      nombre: 'Usuario de prueba',
      nombreUsuario: 'prueba',
      esMaestro: _esMaestro,
      permisos: const {},
    );
  }
}

Future<void> _fijarAncho(WidgetTester tester, double ancho) async {
  tester.view.physicalSize = Size(ancho, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(WidgetTester tester, AppDatabase db, String documentoPorEmitirId, {bool esMaestro = true}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(() => _SesionControllerDePrueba(esMaestro)),
        // `documentoPorEmitirRepositoryProvider` ahora depende de
        // `attachmentStorageProvider` (Etapa 15, eliminación física
        // ampliada) — se sobreescribe directo para no necesitar
        // `appPathsProvider` (requiere `path_provider`, no disponible en
        // pruebas de widget); ninguna prueba de este archivo ejecuta de
        // verdad un borrado físico de archivos.
        attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // `Scaffold` real: `RisegFeedback` (bloqueo por pago aplicado)
        // necesita un `ScaffoldMessenger` ancestro.
        home: Scaffold(body: AgendaDetalleDialog(documentoPorEmitirId: documentoPorEmitirId)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;
  late String clienteId;
  late String servicioId;
  late String vigenciaId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());

    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final clienteRepo = ClienteRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    final comercialRepo = ServicioComercialRepositoryImpl(db);
    final crearServicio = CrearServicioUseCase(
      servicioRepo,
      generarCodigo,
      ServicioValidator(clienteRepo, CatalogoRepositoryImpl(db)),
    );

    final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'));
    clienteId = cliente.id;
    final creado = await crearServicio.ejecutar(
      clienteId: clienteId,
      borrador: ServicioBorrador(
        nombre: 'Vigilancia Sportium',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    servicioId = (creado as GuardarServicioExitoso).servicio.id;

    final puesto = await PuestoRepositoryImpl(db).crear(
      PuestoCompanion.insert(
        codigo: 'PUE-0001',
        nombre: 'Guardia',
        areaId: SeedIds.areaOperaciones,
        tipo: 'operativo',
        nivelJerarquico: 5,
      ),
    );
    final crearLinea = CrearLineaComercialUseCase(
      comercialRepo,
      servicioRepo,
      LineaComercialValidator(PuestoRepositoryImpl(db), CatalogoRepositoryImpl(db), servicioRepo, ConfiguracionCobroRepositoryImpl(db)),
    );
    final lineaCreada = await crearLinea.ejecutar(
      servicioId: servicioId,
      borrador: LineaComercialBorrador(
        puestoId: puesto.id,
        modalidadTurnoId: SeedIds.modalidadTurno24x24,
        cantidadElementos: 2,
        precioUnitario: 1500000,
        tratamientoIva: TratamientoIva.noAplica,
        fechaInicioVigencia: DateTime(2026, 1, 1),
      ),
    ) as CrearLineaComercialExitoso;
    vigenciaId = lineaCreada.vigencia.id;
  });

  tearDown(() => db.close());

  Future<String> crearDocumentoDePrueba({
    String codigo = 'DOC-0001',
    String tipoDocumento = 'reciboDePago',
    String estatus = 'pendiente',
  }) async {
    final documento = await db.into(db.documentoPorEmitir).insertReturning(
          DocumentoPorEmitirCompanion.insert(
            codigo: codigo,
            clienteId: clienteId,
            tipoDocumento: tipoDocumento,
            agrupacion: 'porServicio',
            metodo: 'noAplica',
            periodoInicio: DateTime(2026, 6, 1),
            periodoFin: DateTime(2026, 6, 30),
            generationKey: 'GK-$codigo',
            importeBaseEsperado: 2180000,
            importeFinalEsperado: 2180000,
            estatus: Value(estatus),
          ),
        );
    await db.into(db.documentoPorEmitirServicio).insert(
          DocumentoPorEmitirServicioCompanion.insert(documentoPorEmitirId: documento.id, servicioId: servicioId),
        );
    await db.into(db.documentoPorEmitirLinea).insert(
          DocumentoPorEmitirLineaCompanion.insert(
            documentoPorEmitirId: documento.id,
            servicioId: servicioId,
            lineaComercialVigenciaId: vigenciaId,
            puestoNombre: 'Guardia',
            modalidadTurnoNombre: '24x24',
            cantidadElementos: 2,
            precioUnitario: 1500000,
            tratamientoIva: 'noAplica',
            diasAplicables: 30,
            subtotalProporcional: 3000000,
          ),
        );
    return documento.id;
  }

  testWidgets('Recibo de pago: muestra "Generar recibo PDF"', (tester) async {
    final documentoId = await crearDocumentoDePrueba();
    await _pump(tester, db, documentoId);

    expect(find.byKey(const Key('agenda_detalle_boton_generar_recibo_pdf')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CFDI: nunca muestra "Generar recibo PDF" — RISEG ONE no timbra', (tester) async {
    final documentoId = await crearDocumentoDePrueba(tipoDocumento: 'cfdi');
    await _pump(tester, db, documentoId);

    expect(find.byKey(const Key('agenda_detalle_boton_generar_recibo_pdf')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Maestro ve el menú ⋮ con Eliminar físicamente, siempre habilitado — el estatus ya no bloquea', (
    tester,
  ) async {
    final documentoId = await crearDocumentoDePrueba(estatus: 'pendiente');
    await _pump(tester, db, documentoId, esMaestro: true);

    expect(find.byKey(const Key('agenda_detalle_menu_acciones')), findsOneWidget);
    await tester.tap(find.byKey(const Key('agenda_detalle_menu_acciones')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    final item = tester.widget<PopupMenuItem<VoidCallback>>(
      find.ancestor(of: find.text(l10n.eliminacionFisicaAccionMenu), matching: find.byType(PopupMenuItem<VoidCallback>)),
    );
    expect(item.enabled, isTrue, reason: 'Pendiente ya no bloquea la eliminación física (Etapa 15, ampliación)');
  });

  testWidgets('usuario normal (no Maestro) nunca ve el menú ⋮ de eliminación física', (tester) async {
    final documentoId = await crearDocumentoDePrueba();
    await _pump(tester, db, documentoId, esMaestro: false);

    expect(find.byKey(const Key('agenda_detalle_menu_acciones')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Eliminar físicamente abre confirmación dinámica con el impacto real (sin dependencias)', (
    tester,
  ) async {
    final documentoId = await crearDocumentoDePrueba(estatus: 'pendiente');
    await _pump(tester, db, documentoId, esMaestro: true);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('agenda_detalle_menu_acciones')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.eliminacionFisicaAccionMenu).last);
    await tester.pumpAndSettle();

    expect(find.text(l10n.agendaDetalleEliminarResumenSinDependencias), findsOneWidget);
  });

  testWidgets('Eliminar físicamente con una Cuenta por cobrar sin pagos: la confirmación lo menciona explícitamente', (
    tester,
  ) async {
    final documentoId = await crearDocumentoDePrueba(estatus: 'procesadoAceptado');
    await db.into(db.cuentaPorCobrar).insert(
          CuentaPorCobrarCompanion.insert(
            documentoPorEmitirId: documentoId,
            clienteId: clienteId,
            tipoDocumento: 'reciboDePago',
            metodo: 'noAplica',
            fechaEmisionReal: DateTime(2026, 1, 5),
            importeEmitido: 0,
            saldoOriginal: 2180000,
            saldoPendiente: 2180000,
          ),
        );
    await _pump(tester, db, documentoId, esMaestro: true);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('agenda_detalle_menu_acciones')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.eliminacionFisicaAccionMenu).last);
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.agendaDetalleEliminarResumenMensaje(l10n.agendaDetalleEliminarResumenCuentaPorCobrar)),
      findsOneWidget,
    );
  });

  testWidgets('Eliminar físicamente con un pago real aplicado: bloquea de inmediato, sin abrir el diálogo de motivo', (
    tester,
  ) async {
    final documentoId = await crearDocumentoDePrueba(estatus: 'procesadoAceptado');
    final cuenta = await db.into(db.cuentaPorCobrar).insertReturning(
          CuentaPorCobrarCompanion.insert(
            documentoPorEmitirId: documentoId,
            clienteId: clienteId,
            tipoDocumento: 'reciboDePago',
            metodo: 'noAplica',
            fechaEmisionReal: DateTime(2026, 1, 5),
            importeEmitido: 2180000,
            saldoOriginal: 2180000,
            saldoPendiente: 0,
          ),
        );
    final pago = await db.into(db.pago).insertReturning(
          PagoCompanion.insert(
            folioPago: 'PAG-WIDGET-0001',
            clienteId: clienteId,
            montoTotal: 2180000,
            fechaPago: DateTime(2026, 1, 6),
            formaPago: 'transferencia',
          ),
        );
    await db.into(db.aplicacionPago).insert(
          AplicacionPagoCompanion.insert(
            pagoId: pago.id,
            cuentaPorCobrarId: cuenta.id,
            monto: 2180000,
            saldoAntes: 2180000,
            saldoDespues: 0,
          ),
        );
    await _pump(tester, db, documentoId, esMaestro: true);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.tap(find.byKey(const Key('agenda_detalle_menu_acciones')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.eliminacionFisicaAccionMenu).last);
    await tester.pumpAndSettle();

    expect(find.textContaining('pago(s) aplicado(s)'), findsOneWidget);
    expect(find.text(l10n.eliminacionFisicaCampoMotivo), findsNothing, reason: 'nunca debe abrirse el diálogo de motivo');
  });

  testWidgets('Registrar emisión: el importe emitido llega prellenado con el importe final esperado', (
    tester,
  ) async {
    final documentoId = await crearDocumentoDePrueba();
    await _pump(tester, db, documentoId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.ensureVisible(find.text(l10n.agendaDetalleBotonRegistrarEmision));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.agendaDetalleBotonRegistrarEmision));
    await tester.pumpAndSettle();

    final campoImporte = find.descendant(
      of: find.widgetWithText(RisegTextField, l10n.agendaDetalleCampoImporteEmitido),
      matching: find.byType(TextFormField),
    );
    final controller = tester.widget<TextFormField>(campoImporte).controller!;
    expect(controller.text, '21800.00', reason: 'importeFinalEsperado del documento de prueba es 2180000 centavos');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Registrar emisión: si el usuario borra el importe, se rechaza en vez de guardar 0 en silencio', (
    tester,
  ) async {
    final documentoId = await crearDocumentoDePrueba();
    await _pump(tester, db, documentoId);
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));

    await tester.ensureVisible(find.text(l10n.agendaDetalleBotonRegistrarEmision));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.agendaDetalleBotonRegistrarEmision));
    await tester.pumpAndSettle();

    final campoImporte = find.descendant(
      of: find.widgetWithText(RisegTextField, l10n.agendaDetalleCampoImporteEmitido),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(campoImporte, '');
    await tester.tap(find.text(l10n.agendaRegistrarEmisionBotonConfirmar).last);
    await tester.pumpAndSettle();

    // El error inline solo se muestra si el diálogo de captura sigue
    // abierto (nunca llegó a cerrarse ni a guardar nada).
    expect(find.text(l10n.agendaRegistrarEmisionErrorImporteRequerido), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Dialog).last, matching: find.byType(TextFormField)),
      findsWidgets,
      reason: 'el formulario de captura sigue montado',
    );
  });

  testWidgets('layout: ancho amplio y reducido sin overflow', (tester) async {
    final documentoId = await crearDocumentoDePrueba();

    await _fijarAncho(tester, 1600);
    await _pump(tester, db, documentoId);
    expect(tester.takeException(), isNull);

    await _fijarAncho(tester, 580);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
