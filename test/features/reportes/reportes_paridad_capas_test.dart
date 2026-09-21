// Rediseño de Reportes — §16: una sola fuente de verdad.
//
// La regla que estas pruebas defienden: KPI, gráfica, tabla y
// exportación tienen que partir del mismo cálculo. Debe ser imposible
// que el KPI diga $100,000 y la gráfica $97,000.
//
// Se ejercita la cadena REAL de providers (nunca repositorios
// construidos a mano), porque el riesgo que se quiere cubrir no es
// aritmético sino de cableado: que una pantalla quede conectada a un
// cálculo y otra a otro.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/compras/presentation/compras_controller.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentStorageProvider;
import 'package:riseg_one/features/reportes/presentation/finanzas/reportes_finanzas_controller.dart';
import 'package:riseg_one/features/reportes/presentation/general/reportes_general_controller.dart';
import 'package:riseg_one/features/reportes/presentation/reportes_rango_controller.dart';
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

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  final hoy = DateTime.now();
  DateTime esteMes(int dia, [int hora = 10]) => DateTime(hoy.year, hoy.month, dia, hora);

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
      // Etapa B: Finanzas resuelve Servicio/Entidad fiscal de cada CxC
      // vía `DocumentoPorEmitirRepository`, que arrastra
      // `attachmentStorageProvider`.
      attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
    ]);
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  /// Escenario con las cuatro formas de mover dinero que el sistema
  /// distingue: ingreso, egreso en efectivo, gasto con tarjeta y pago de
  /// la tarjeta.
  Future<void> sembrar() async {
    await container.read(registrarIngresoManualUseCaseProvider).ejecutar(
          monto: 3000000,
          fecha: esteMes(2),
          formaPago: 'transferencia',
          concepto: 'Cobro de servicio',
        );
    await container.read(registrarEgresoUseCaseProvider).ejecutar(
          monto: 450000,
          fecha: esteMes(3),
          formaPago: 'transferencia',
          concepto: 'Papelería',
        );

    final tarjeta = await container.read(registrarDeudaAutorizadoProvider)(
      nombre: 'TDC corporativa',
      tipo: TipoDeuda.tarjetaCredito.name,
      fechaOrigen: DateTime(hoy.year, 1, 1),
      importeOriginal: 50000000,
      saldoInicial: 1,
      tarjetaLimiteCredito: 50000000,
    );
    final deudaId = (tarjeta as RegistrarDeudaExitoso).deuda.id;

    final compra = await container.read(comprasControllerProvider.notifier).registrarCompra(
          fecha: esteMes(4),
          formaPago: 'tarjeta',
          deudaId: deudaId,
          partidas: [
            const PartidaCompraInput(
              destino: 'gastoDirecto',
              concepto: 'Uniformes',
              cantidad: 1,
              costoUnitario: 800000,
            ),
          ],
        );
    expect(compra, isA<RegistrarCompraExitosa>());

    await container.read(registrarPagoDeudaAutorizadoProvider)(
      deudaId: deudaId,
      fecha: esteMes(6),
      importe: 800000,
      formaPago: 'transferencia',
    );
  }

  Future<void> cargarPestanas() async {
    // `listen` y no `read`: los controladores de pestaña son autoDispose,
    // así que sin una suscripción viva Riverpod los destruiría en cuanto
    // termina el `read` y la carga asíncrona se perdería.
    container.listen(reportesGeneralControllerProvider, (_, __) {}, fireImmediately: true);
    container.listen(reportesFinanzasControllerProvider, (_, __) {}, fireImmediately: true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  test('General y Finanzas muestran EXACTAMENTE el mismo gasto y resultado del periodo', () async {
    await sembrar();
    await cargarPestanas();

    final general = container.read(reportesGeneralControllerProvider).resumen;
    final finanzas = container.read(reportesFinanzasControllerProvider);

    expect(general, isNotNull);
    expect(general!.analisis, isNotNull);
    expect(general.gastoOperativo, finanzas.gastoOperativo,
        reason: 'dos pestañas del mismo módulo no pueden discrepar en el gasto del periodo');
    expect(general.resultadoOperativo, finanzas.resultadoOperativo);
    expect(general.totalIngresos, finanzas.totalIngresos);
    expect(general.salidasDeEfectivo, finanzas.salidasDeEfectivo);
  });

  test('KPI = gráfica = composición, en las dos pestañas', () async {
    await sembrar();
    await cargarPestanas();

    for (final analisis in [
      container.read(reportesGeneralControllerProvider).resumen!.analisis!,
      container.read(reportesFinanzasControllerProvider).analisis!,
    ]) {
      expect(analisis.puntos.fold<int>(0, (a, p) => a + p.ingresos), analisis.ingresos);
      expect(analisis.puntos.fold<int>(0, (a, p) => a + p.gastoOperativo), analisis.gastoOperativo);
      expect(analisis.composicion.fold<int>(0, (a, c) => a + c.importe), analisis.gastoOperativo);
    }
  });

  test('la tabla de Egresos por categoría suma exactamente las salidas de efectivo del KPI', () async {
    await sembrar();
    await cargarPestanas();

    final finanzas = container.read(reportesFinanzasControllerProvider);
    final sumaTabla = finanzas.egresosPorCategoria.fold<int>(0, (a, c) => a + c.total);

    expect(sumaTabla, finanzas.salidasDeEfectivo,
        reason: 'el desglose por categoría es esa misma cifra abierta, nunca otro universo de Egresos');
  });

  test('el detalle que se exporta a Excel suma exactamente las salidas de efectivo del KPI', () async {
    await sembrar();
    await cargarPestanas();

    final finanzas = container.read(reportesFinanzasControllerProvider);
    final detalle = finanzas.egresosPorOrigen!.detalle;
    final sumaExportacion = detalle.fold<int>(0, (a, e) => a + e.egreso.monto);

    expect(sumaExportacion, finanzas.salidasDeEfectivo,
        reason: 'lo que se abre en Excel tiene que cuadrar con lo que se ve en pantalla');
  });

  test('el gasto con tarjeta no se cuenta dos veces en ninguna capa', () async {
    await sembrar();
    await cargarPestanas();

    final finanzas = container.read(reportesFinanzasControllerProvider);

    // Efectivo: papelería $4,500 + pago de tarjeta $8,000.
    expect(finanzas.salidasDeEfectivo, 1250000);
    expect(finanzas.pagosDeDeuda, 800000);
    expect(finanzas.cargosDeTarjeta, 800000);
    // Gasto operativo: papelería $4,500 + uniformes $8,000. El pago de
    // la tarjeta NO suma: el peso ya se reconoció al comprar.
    expect(finanzas.gastoOperativo, 1250000);
    expect(finanzas.resultadoOperativo, 3000000 - 1250000);
  });

  group('el periodo es compartido entre pestañas', () {
    test('cambiar el rango en una pestaña lo cambia en todas', () async {
      await sembrar();
      await cargarPestanas();

      final rangoController = container.read(reportesRangoControllerProvider.notifier);
      rangoController.aplicarPreset(PresetRangoReportes.mesAnterior);
      await Future<void>.delayed(const Duration(milliseconds: 600));

      final general = container.read(reportesGeneralControllerProvider);
      final finanzas = container.read(reportesFinanzasControllerProvider);

      expect(general.seleccion.preset, PresetRangoReportes.mesAnterior);
      expect(finanzas.seleccion.preset, PresetRangoReportes.mesAnterior,
          reason: 'antes cada pestaña reiniciaba su propio rango al mes en curso');
      expect(general.rangoInicio, finanzas.rangoInicio);
      expect(general.rangoFin, finanzas.rangoFin);
    });

    test('mover una fecha a mano deja el periodo en "personalizado"', () async {
      final rangoController = container.read(reportesRangoControllerProvider.notifier);
      expect(container.read(reportesRangoControllerProvider).preset, PresetRangoReportes.esteMes);

      rangoController.cambiarInicio(DateTime(hoy.year, 1, 1));

      expect(container.read(reportesRangoControllerProvider).preset, PresetRangoReportes.personalizado,
          reason: 'marcar "Este mes" sobre un rango que ya no es el mes le mentiría al usuario');
    });

    test('los presets se calculan sobre el calendario, no sobre el reloj', () {
      final referencia = DateTime(2026, 9, 10, 15, 30);

      final esteMes = ReportesRangoController.calcular(PresetRangoReportes.esteMes, referencia);
      expect(esteMes.rango.inicio, DateTime(2026, 9, 1));
      expect(esteMes.rango.fin, DateTime(2026, 9, 10),
          reason: '"Este mes" termina hoy: incluir días que no han ocurrido fabricaría una caída mensual falsa');

      final mesAnterior = ReportesRangoController.calcular(PresetRangoReportes.mesAnterior, referencia);
      expect(mesAnterior.rango.inicio, DateTime(2026, 8, 1));
      expect(mesAnterior.rango.fin, DateTime(2026, 8, 31));

      final ultimos30 = ReportesRangoController.calcular(PresetRangoReportes.ultimos30Dias, referencia);
      expect(ultimos30.rango.dias, 30);
      expect(ultimos30.rango.fin, DateTime(2026, 9, 10));

      final anio = ReportesRangoController.calcular(PresetRangoReportes.anioActual, referencia);
      expect(anio.rango.inicio, DateTime(2026, 1, 1));
      expect(anio.rango.fin, DateTime(2026, 9, 10));
    });
  });
}
