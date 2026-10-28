// Pruebas de pantalla completa del horario personalizado de línea
// comercial (Etapa 15) — cubren específicamente los dos escenarios que
// solo pueden verificarse contra el árbol real (precarga real de
// "Corregir" y "Nueva vigencia"):
//  - "Corregir" precarga el horario real ya capturado, día por día;
//  - "Nueva vigencia" copia ese horario como punto de partida editable,
//    pero modificarlo NUNCA altera el horario de la vigencia histórica
//    de la que vino — cada vigencia conserva su propio horario, igual
//    que conserva su propio precio/sueldo/bono.

import 'package:drift/drift.dart' hide isNull, isNotNull;
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
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/shared/horario_input.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/servicio_expediente_screen.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../../support/sesion_en_base.dart';

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

void main() {
  late AppDatabase db;
  late ServicioComercialRepositoryImpl comercialRepo;
  late String servicioId;
  late String lineaId;
  late String vigenciaOriginalId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-prueba'),
            nombre: 'Usuario de prueba',
            nombreUsuario: 'usuario-prueba',
            passwordHash: 'x',
          ),
        );

    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final clienteRepo = ClienteRepositoryImpl(db);
    final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    final catalogoRepo = CatalogoRepositoryImpl(db);
    comercialRepo = ServicioComercialRepositoryImpl(db);
    final puestoRepo = PuestoRepositoryImpl(db);

    final cliente = await clienteRepo.crear(
      ClienteCompanion.insert(codigo: 'CLI-000077', nombreComercial: 'Vigilancia Horario Personalizado'),
    );
    final crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, ServicioValidator(clienteRepo, catalogoRepo));
    final creado = await crearServicio.ejecutar(
      clienteId: cliente.id,
      borrador: ServicioBorrador(
        nombre: 'Vigilancia Horario Personalizado',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    servicioId = (creado as GuardarServicioExitoso).servicio.id;

    final puesto = await puestoRepo.crear(
      PuestoCompanion.insert(
        codigo: 'PUE-NOC',
        nombre: 'Elemento Nocturno',
        areaId: SeedIds.areaOperaciones,
        tipo: 'operativo',
        nivelJerarquico: 5,
      ),
    );

    // Horario real: lunes 20:00→07:00 (nocturno), resto de la semana
    // en descanso — mismo patrón usado en las pruebas de dominio.
    final horarioOriginal = HorarioSemanalBorrador(
      dias: [
        for (var i = 0; i < 7; i++)
          i == 0 ? const HorarioDiaBorrador(abierto: true, horaInicioMinutos: 1200, horaFinMinutos: 420) : const HorarioDiaBorrador(abierto: false),
      ],
    );
    final resultadoLinea = await comercialRepo.crearLinea(
      servicioId: servicioId,
      datos: LineaComercialValidada(
        puestoId: puesto.id,
        modalidadTurnoId: SeedIds.modalidadTurnoPersonalizado,
        cantidadElementos: 1,
        precioUnitario: 1800000,
        tratamientoIva: TratamientoIva.masIva,
        fechaInicioVigencia: DateTime(2026, 1, 1),
        horario: validarHorarioSemanal(horarioOriginal).resultado,
      ),
    );
    lineaId = resultadoLinea.linea.id;
    vigenciaOriginalId = resultadoLinea.vigencia.id;
    // Etapa 3B: autorizar revalida contra la base, así que la
    // sesión de esta prueba tiene que corresponder a una cuenta real.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
  });

  tearDown(() => db.close());

  Future<AppLocalizations> pumpPantalla(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
          home: ServicioExpedienteScreen(servicioId: servicioId),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.delegate.load(const Locale('es'));
  }

  Future<void> abrirMenuYTocar(WidgetTester tester, String etiquetaAccion) async {
    final botonMenu = find.byKey(Key('servicio_comercial_linea_menu_$lineaId'));
    await tester.ensureVisible(botonMenu);
    await tester.tap(botonMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<VoidCallback>, etiquetaAccion).last);
    await tester.pumpAndSettle();
  }

  testWidgets('Corregir precarga el horario real ya capturado, día por día', (tester) async {
    final l10n = await pumpPantalla(tester);

    await abrirMenuYTocar(tester, l10n.servicioComercialBotonCorregir);
    expect(find.text(l10n.servicioComercialHorarioPersonalizadoTitulo), findsOneWidget);

    final switches = find.byType(Switch);
    expect(switches, findsNWidgets(7), reason: 'los 7 días siempre se muestran');
    expect(tester.widget<Switch>(switches.at(0)).value, isTrue, reason: 'lunes trabaja');
    for (var i = 1; i < 7; i++) {
      expect(tester.widget<Switch>(switches.at(i)).value, isFalse, reason: 'martes a domingo en descanso');
    }

    final camposHora = find.byType(RisegTimeField);
    expect(camposHora, findsNWidgets(2), reason: 'solo el lunes (único día activo) muestra entrada/salida');
    expect(tester.widget<RisegTimeField>(camposHora.first).value, const TimeOfDay(hour: 20, minute: 0));
    expect(tester.widget<RisegTimeField>(camposHora.last).value, const TimeOfDay(hour: 7, minute: 0));
  });

  testWidgets(
    'Nueva vigencia copia el horario anterior como punto de partida, pero modificarlo no altera la vigencia histórica',
    (tester) async {
      final l10n = await pumpPantalla(tester);

      await abrirMenuYTocar(tester, l10n.servicioComercialBotonNuevaVigencia);
      expect(find.text(l10n.servicioComercialHorarioPersonalizadoTitulo), findsOneWidget, reason: 'el horario anterior se copia como punto de partida');

      final switchesIniciales = find.byType(Switch);
      expect(tester.widget<Switch>(switchesIniciales.at(0)).value, isTrue, reason: 'lunes ya viene copiado como trabajado');

      // Modifica: activa también el martes con un horario distinto —
      // nunca debe tocar la vigencia histórica original.
      await tester.tap(switchesIniciales.at(1));
      await tester.pumpAndSettle();
      final camposHoraMartes = find.byType(RisegTimeField).at(2);
      final camposHoraMartesFin = find.byType(RisegTimeField).at(3);
      tester.widget<RisegTimeField>(camposHoraMartes).onChanged(const TimeOfDay(hour: 8, minute: 0));
      await tester.pumpAndSettle();
      tester.widget<RisegTimeField>(camposHoraMartesFin).onChanged(const TimeOfDay(hour: 20, minute: 0));
      await tester.pumpAndSettle();

      // Completa el resto del formulario para poder guardar — índices
      // desplazados por los 4 TextFormField del horario (lunes +
      // martes, ambos activos en este punto): cantidad(4), precio(5),
      // sueldo(6), bono(7), fecha de inicio(8).
      await tester.enterText(find.byType(TextFormField).at(4), '1');
      await tester.enterText(find.byType(TextFormField).at(5), '18000');
      final campoFechaInicio = find.byType(TextFormField).at(8);
      await tester.tap(campoFechaInicio);
      await tester.pumpAndSettle();
      final dialogoSelector = find.byType(Dialog).last;
      await tester.tap(find.descendant(of: dialogoSelector, matching: find.byType(TextButton)).last);
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.servicioVinculacionDialogoBotonGuardar).last);
      await tester.pumpAndSettle();

      expect(find.text(l10n.servicioComercialNuevaVigenciaExito), findsOneWidget);

      // La vigencia histórica original conserva EXACTAMENTE su propio
      // horario — nunca se le agrega el martes ni se le toca el lunes.
      final horarioOriginalTrasGuardar = await comercialRepo.obtenerHorario(vigenciaOriginalId);
      final lunesOriginal = horarioOriginalTrasGuardar.firstWhere((h) => h.diaSemana == 0);
      final martesOriginal = horarioOriginalTrasGuardar.firstWhere((h) => h.diaSemana == 1);
      expect(lunesOriginal.horaInicio, 1200);
      expect(lunesOriginal.horaFin, 420);
      expect(martesOriginal.activo, isFalse, reason: 'la vigencia histórica nunca gana el martes que se activó en la nueva');

      // La línea ahora tiene 2 vigencias — la nueva sí tiene el martes.
      final historial = await comercialRepo.listarHistorial(lineaId);
      expect(historial, hasLength(2));
      final vigenciaNueva = historial.firstWhere((v) => v.id != vigenciaOriginalId);
      final horarioNuevo = await comercialRepo.obtenerHorario(vigenciaNueva.id);
      expect(horarioNuevo.firstWhere((h) => h.diaSemana == 1).activo, isTrue);
    },
  );
}
