// Etapa "Complemento de pago dependiente del Pago real" — decisiones
// ② (retirar la etapa calendario de capturas nuevas, conservar el
// histórico intacto) y §4 (PUE nunca exige Complemento).

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_portal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/configuracion_cobro_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_etapa_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_etapa_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/widgets/servicio_configuracion_cobro_section.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';

void main() {
  late AppDatabase db;
  late ConfiguracionCobroRepositoryImpl repo;
  late ConfiguracionCobroValidator validator;
  late CrearConfiguracionCobroUseCase crearConfiguracionCobro;
  late String servicioId;
  late String entidadFiscalId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final clienteRepo = ClienteRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    final catalogoRepo = CatalogoRepositoryImpl(db);
    repo = ConfiguracionCobroRepositoryImpl(db);
    validator = ConfiguracionCobroValidator(
      servicioRepo,
      EntidadFiscalRepositoryImpl(db),
      catalogoRepo,
      ServicioComercialRepositoryImpl(db),
      ClientePortalRepositoryImpl(db),
    );
    crearConfiguracionCobro =
        CrearConfiguracionCobroUseCase(repo, servicioRepo, validator, const ConfiguracionCobroEtapaValidator());

    final cliente = await clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-000030', nombreComercial: 'MORGAN'),
    );
    final servicio = await CrearServicioUseCase(
      servicioRepo,
      GenerarCodigoUseCase(CodigoSecuenciaService(db)),
      ServicioValidator(clienteRepo, catalogoRepo),
    ).ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(
        nombre: 'MORGAN ATLACOMULCO',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    servicioId = (servicio as GuardarServicioExitoso).servicio.id;

    final entidad = await EntidadFiscalRepositoryImpl(db).crear(
      EntidadFiscalCompanion.insert(
        codigo: 'ENF-000030',
        clienteId: cliente.id,
        razonSocial: 'MORGAN SA de CV',
        rfc: 'MOR260101AAA',
      ),
    );
    entidadFiscalId = entidad.id;
  });

  tearDown(() => db.close());

  /// PUE/PPD sólo existen con CFDI — un recibo de pago exige método
  /// `noAplica` (regla preexistente `metodoInvalidoParaRecibo`).
  ConfiguracionCobroBorrador borrador({
    required MetodoPagoCobro metodo,
    required bool requiereComplemento,
  }) =>
      ConfiguracionCobroBorrador(
        tipoDocumento:
            metodo == MetodoPagoCobro.noAplica ? TipoDocumentoCobro.reciboDePago : TipoDocumentoCobro.cfdi,
        frecuenciaId: SeedIds.frecuenciaCobroMensual,
        diaInicioPeriodo: 1,
        agrupacion: AgrupacionCobro.porServicio,
        metodo: metodo,
        requiereComplemento: requiereComplemento,
        fechaInicioVigencia: DateTime(2026, 4, 24),
        entidadFiscalId: metodo == MetodoPagoCobro.noAplica ? null : entidadFiscalId,
      );

  group('§4 — PUE nunca exige Complemento (protección de DOMINIO)', () {
    test('el validador NORMALIZA PUE + requiereComplemento a false', () async {
      final validacion = await validator.validar(
        servicioId: servicioId,
        borrador: borrador(metodo: MetodoPagoCobro.pue, requiereComplemento: true),
      );

      expect(validacion.errores, isEmpty);
      expect(
        validacion.resultado!.requiereComplemento,
        isFalse,
        reason: 'la combinación no puede PERSISTIRSE, venga de donde venga',
      );
    });

    test('"No aplica" tampoco lo admite', () async {
      final validacion = await validator.validar(
        servicioId: servicioId,
        borrador: borrador(metodo: MetodoPagoCobro.noAplica, requiereComplemento: true),
      );
      expect(validacion.resultado!.requiereComplemento, isFalse);
    });

    test('PPD sí lo conserva', () async {
      final validacion = await validator.validar(
        servicioId: servicioId,
        borrador: borrador(metodo: MetodoPagoCobro.ppd, requiereComplemento: true),
      );
      expect(validacion.resultado!.requiereComplemento, isTrue);
    });

    test('la fila persistida de una configuración PUE nunca queda con el flag encendido', () async {
      // Recibo de pago exige método `noAplica`; para PUE se usa CFDI.
      final resultado = await crearConfiguracionCobro.ejecutar(
        servicioId: servicioId,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: true,
          fechaInicioVigencia: DateTime(2026, 4, 24),
        ),
      );

      expect(resultado, isA<CrearConfiguracionCobroExitoso>());
      final vigencia = (resultado as CrearConfiguracionCobroExitoso).vigencia;
      expect(vigencia.requiereComplemento, isFalse);
    });
  });

  group('§② — la etapa calendario deja de ofrecerse, el histórico permanece', () {
    /// Una vigencia antigua CON la etapa `complementoPago`, tal como
    /// existen 5 en la base real.
    Future<ConfiguracionCobroVigenciaData> configuracionHistoricaConEtapaComplemento() async {
      final resultado = await crearConfiguracionCobro.ejecutar(
        servicioId: servicioId,
        borrador: borrador(metodo: MetodoPagoCobro.noAplica, requiereComplemento: false),
        etapas: const [
          EtapaCobroBorrador(
            id: 'e-emision',
            tipoSistema: TipoEventoCobro.emision,
            orden: 0,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: MesRelativoCobro.actual,
            diaDelMes: 3,
          ),
          EtapaCobroBorrador(
            id: 'e-complemento',
            tipoSistema: TipoEventoCobro.complementoPago,
            orden: 1,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: MesRelativoCobro.siguiente,
            diaDelMes: 5,
          ),
        ],
      );
      return (resultado as CrearConfiguracionCobroExitoso).vigencia;
    }

    test('el enum CONSERVA el valor: nada histórico deja de poder leerse', () {
      expect(TipoEventoCobro.values.map((e) => e.name), contains('complementoPago'));
    });

    test('una vigencia histórica con esa etapa se sigue leyendo, con su fecha intacta', () async {
      final vigencia = await configuracionHistoricaConEtapaComplemento();

      final etapas = await repo.listarEtapas(vigencia.id);
      final complemento = etapas.firstWhere((e) => e.tipoSistema == TipoEventoCobro.complementoPago.name);

      expect(complemento.tipoRegla, TipoReglaEvento.diaFijoDelMes.name);
      expect(complemento.mesRelativo, MesRelativoCobro.siguiente.name);
      expect(complemento.diaDelMes, 5, reason: 'no se reinterpreta ni se convierte en otra cosa');
    });

    testWidgets('el formulario NO ofrece agregar la etapa Complemento de pago', (tester) async {
      tester.view.physicalSize = const Size(1366, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ServicioConfiguracionCobroForm(
                frecuencias: const [],
                entidadesFiscales: const [],
                contactos: const [],
                portales: const [],
                onCambio: (_, __) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('servicio_cobro_boton_agregar_etapa_sistema_complementoPago')),
        findsNothing,
        reason: 'dejó de ser fuente de verdad: la obligación nace del Pago real',
      );
      // Pago esperado sí se sigue ofreciendo — es calendario comercial
      // legítimo.
      expect(
        find.byKey(const Key('servicio_cobro_boton_agregar_etapa_sistema_pagoEsperado')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('pero una vigencia histórica que la tiene SÍ la renderiza', (tester) async {
      tester.view.physicalSize = const Size(1366, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final vigencia = await configuracionHistoricaConEtapaComplemento();
      final etapas = await repo.listarEtapas(vigencia.id);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ServicioConfiguracionCobroForm(
                frecuencias: const [],
                entidadesFiscales: const [],
                contactos: const [],
                portales: const [],
                valoresIniciales: vigencia,
                etapasIniciales: etapas,
                onCambio: (_, __) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(
        find.text(l10n.servicioCobroEventoComplementoPago),
        findsWidgets,
        reason: 'el histórico no se esconde ni se borra',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('§15 — el histórico no cambia al crear vigencias nuevas', () {
    test('los hitos ya snapshoteados con esa etapa permanecen', () async {
      // Un `DocumentoPorEmitirHito` histórico con `tipoSistema =
      // complementoPago`, como los 7 que existen en la base real.
      await db.into(db.documentoPorEmitir).insert(
            DocumentoPorEmitirCompanion.insert(
              id: const Value('doc-hist'),
              codigo: 'DPE-HIST',
              generationKey: 'gk-hist',
              clienteId: (await db.select(db.cliente).get()).first.id,
              tipoDocumento: 'cfdi',
              metodo: 'ppd',
              requiereComplemento: const Value(true),
              periodoInicio: DateTime(2026, 5, 1),
              periodoFin: DateTime(2026, 5, 31),
              agrupacion: 'porServicio',
              importeBaseEsperado: 100,
              importeFinalEsperado: 100,
            ),
          );
      await db.into(db.documentoPorEmitirHito).insert(
            DocumentoPorEmitirHitoCompanion.insert(
              documentoPorEmitirId: 'doc-hist',
              servicioId: servicioId,
              orden: 2,
              tipoSistema: const Value('complementoPago'),
              fechaProgramada: DateTime(2026, 6, 5),
            ),
          );

      // Crear configuración nueva (que ya no puede tener la etapa).
      await crearConfiguracionCobro.ejecutar(
        servicioId: servicioId,
        borrador: borrador(metodo: MetodoPagoCobro.noAplica, requiereComplemento: false),
      );

      final hitos = await (db.select(db.documentoPorEmitirHito)
            ..where((t) => t.tipoSistema.equals('complementoPago')))
          .get();
      expect(hitos, hasLength(1), reason: 'evidencia histórica intacta');
      expect(hitos.single.fechaProgramada, DateTime(2026, 6, 5), reason: 'su fecha no se recalcula');
    });
  });
}
