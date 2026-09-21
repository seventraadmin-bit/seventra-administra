// Reportes Etapa B — exportaciones y paridad de capas.
//
// Lo que se verifica aquí no es "que genere un archivo", sino que el
// archivo traiga el MISMO universo que la pantalla:
//
//  - CxC: una fila por cuenta, exactamente las filtradas.
//  - Pagos: una fila por Pago en la hoja principal (nunca duplicado por
//    aplicación) y las aplicaciones en su propia hoja.
//  - Deudas: resumen + movimientos, con el origen resuelto por FK.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentStorageProvider;
import 'package:riseg_one/features/reportes/data/xlsx/cobranza_xlsx_renderer.dart';
import 'package:riseg_one/features/reportes/domain/analitica/comparacion_periodo.dart';
import 'package:riseg_one/features/reportes/domain/analitica/obtener_analisis_cobranza_usecase.dart';
import 'package:riseg_one/features/reportes/domain/export/reporte_export_context.dart';
import 'package:riseg_one/features/reportes/reportes_providers.dart';
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

/// Contexto de exportación fijo — nada de esto depende del reloj.
final _contexto = ReporteExportContext(
  nombreReporte: 'Prueba',
  rangoInicio: DateTime(2026, 6, 1),
  rangoFin: DateTime(2026, 6, 30),
  generadoPor: 'Maestro de prueba',
  generadoEn: DateTime(2026, 6, 15),
);

/// Filas de datos de una hoja (sin el encabezado).
List<List<String>> _filas(Excel excel, String hoja) {
  final tabla = excel.tables[hoja]!;
  return [
    for (final fila in tabla.rows.skip(1))
      [for (final celda in fila) celda?.value?.toString() ?? ''],
  ];
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  var consecutivo = 0;
  final hoy = DateTime(2026, 6, 15);

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
      attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
    ]);
    consecutivo = 0;
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Future<String> crearCliente(String nombre) async {
    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-${++consecutivo}', nombreComercial: nombre),
        );
    return cliente.id;
  }

  Future<CuentaPorCobrarData> crearCuenta({
    required String clienteId,
    required int importe,
    DateTime? vencimiento,
  }) async {
    final n = ++consecutivo;
    final documento = await db.into(db.documentoPorEmitir).insertReturning(
          DocumentoPorEmitirCompanion.insert(
            codigo: 'DOC-$n',
            clienteId: clienteId,
            tipoDocumento: TipoDocumentoCobro.cfdi.name,
            agrupacion: AgrupacionCobro.porServicio.name,
            metodo: MetodoPagoCobro.pue.name,
            periodoInicio: DateTime(2026, 1, 1),
            periodoFin: DateTime(2026, 1, 31),
            generationKey: 'GEN-$n',
            importeBaseEsperado: importe,
            importeFinalEsperado: importe,
          ),
        );
    return container.read(cuentaPorCobrarRepositoryProvider).crear(
          documentoPorEmitirId: documento.id,
          clienteId: clienteId,
          tipoDocumento: TipoDocumentoCobro.cfdi.name,
          metodo: MetodoPagoCobro.pue.name,
          requiereComplemento: false,
          folioDocumento: 'FOL-$n',
          fechaEmisionReal: DateTime(2026, 1, 5),
          importeEmitido: importe,
          fechaVencimiento: vencimiento,
        );
  }

  group('Excel de Cuentas por cobrar', () {
    test('una fila por CxC y conserva EXACTAMENTE el filtro de la pantalla', () async {
      final a = await crearCliente('Cliente A');
      final b = await crearCliente('Cliente B');
      await crearCuenta(clienteId: a, importe: 600000, vencimiento: DateTime(2026, 5, 1));
      await crearCuenta(clienteId: b, importe: 400000, vencimiento: DateTime(2026, 7, 1));

      final soloA = await container
          .read(obtenerAnalisisCobranzaUseCaseProvider)
          .ejecutar(filtro: FiltroCobranza(clienteId: a), hoy: hoy);

      final bytes = CuentasPorCobrarXlsxRenderer().generar(contexto: _contexto, cuentas: soloA.cuentas);
      final excel = Excel.decodeBytes(bytes);
      final filas = _filas(excel, 'Cuentas por cobrar');

      expect(filas, hasLength(1), reason: 'el Excel trae el universo filtrado, no todas las cuentas');
      expect(filas.single.first, 'Cliente A');
      expect(filas.single.last, '6000', reason: 'saldo en pesos: 600,000 centavos');
    });

    test('sin atraso exporta un guion, nunca 0 días', () async {
      final cliente = await crearCliente('Al corriente');
      await crearCuenta(clienteId: cliente, importe: 100000, vencimiento: DateTime(2026, 7, 1));

      final analisis = await container.read(obtenerAnalisisCobranzaUseCaseProvider).ejecutar(hoy: hoy);
      final excel = Excel.decodeBytes(
        CuentasPorCobrarXlsxRenderer().generar(contexto: _contexto, cuentas: analisis.cuentas),
      );
      final fila = _filas(excel, 'Cuentas por cobrar').single;

      // Columna "Días de atraso" (índice 9).
      expect(fila[9], '—', reason: '0 días de atraso significaría "vence hoy"');
    });
  });

  group('Excel de Pagos', () {
    test('un pago N:M aparece UNA vez en la hoja principal y dos en Aplicaciones', () async {
      final cliente = await crearCliente('Sportium');
      final facturaA = await crearCuenta(clienteId: cliente, importe: 2000000);
      final facturaB = await crearCuenta(clienteId: cliente, importe: 3000000);

      final repo = container.read(pagoRepositoryProvider);
      final pago = await repo.crear(
        folioPago: 'PAG-000001',
        clienteId: cliente,
        montoTotal: 5000000,
        fechaPago: DateTime(2026, 6, 10),
        formaPago: FormaPago.transferencia.name,
      );
      await repo.aplicar(pagoId: pago.id, cuentaPorCobrarId: facturaA.id, monto: 2000000);
      await repo.aplicar(pagoId: pago.id, cuentaPorCobrarId: facturaB.id, monto: 3000000);

      final analisis = await container.read(obtenerAnalisisPagosUseCaseProvider).ejecutar(
            rango: RangoPeriodo(inicio: DateTime(2026, 6, 1), fin: DateTime(2026, 6, 30)),
          );
      final excel = Excel.decodeBytes(PagosXlsxRenderer().generar(contexto: _contexto, pagos: analisis.pagos));

      final hojaPagos = _filas(excel, 'Pagos');
      final hojaAplicaciones = _filas(excel, 'Aplicaciones');

      expect(hojaPagos, hasLength(1), reason: 'el pago NO se duplica en la hoja principal');
      expect(hojaPagos.single[7], '50000', reason: 'importe en pesos, una sola vez');
      expect(hojaAplicaciones, hasLength(2), reason: 'las aplicaciones viven en su propia hoja');
      expect(
        hojaAplicaciones.map((f) => double.parse(f[4])).reduce((a, b) => a + b),
        50000,
        reason: 'las aplicaciones suman el pago, no lo multiplican',
      );
    });
  });

  group('Excel de Deudas', () {
    test('resumen y movimientos en hojas separadas, con origen por FK', () async {
      final tarjeta = await container.read(registrarDeudaAutorizadoProvider)(
        nombre: 'TDC corporativa',
        tipo: TipoDeuda.tarjetaCredito.name,
        fechaOrigen: DateTime(2026, 1, 1),
        importeOriginal: 10000000,
        saldoInicial: 500000,
        fechaSaldoInicial: DateTime(2026, 6, 5),
        tarjetaLimiteCredito: 10000000,
      );
      expect(tarjeta, isA<RegistrarDeudaExitoso>());

      final analisis = await container.read(obtenerAnalisisDeudaUseCaseProvider).ejecutar(
            rango: RangoPeriodo(inicio: DateTime(2026, 6, 1), fin: DateTime(2026, 6, 30)),
            hoy: hoy,
          );
      final excel = Excel.decodeBytes(DeudasXlsxRenderer().generar(contexto: _contexto, analisis: analisis));

      final deudas = _filas(excel, 'Deudas');
      final movimientos = _filas(excel, 'Movimientos');

      expect(deudas, hasLength(1));
      expect(deudas.single[2], '5000', reason: 'saldo actual en pesos');
      expect(deudas.single[3], '100000', reason: 'límite capturado');
      expect(movimientos, hasLength(1), reason: 'el alta inicial es un movimiento real del periodo');
      expect(movimientos.single[3], 'Apertura', reason: 'el origen se resuelve por tipo/FK, no por texto libre');
    });

    test('una tarjeta sin límite exporta guion, no 0', () async {
      final r = await container.read(registrarDeudaAutorizadoProvider)(
        nombre: 'TDC sin límite',
        tipo: TipoDeuda.tarjetaCredito.name,
        saldoInicial: 300000,
        fechaSaldoInicial: DateTime(2026, 6, 5),
      );
      expect(r, isA<RegistrarDeudaExitoso>());

      final analisis = await container.read(obtenerAnalisisDeudaUseCaseProvider).ejecutar(
            rango: RangoPeriodo(inicio: DateTime(2026, 6, 1), fin: DateTime(2026, 6, 30)),
            hoy: hoy,
          );
      final excel = Excel.decodeBytes(DeudasXlsxRenderer().generar(contexto: _contexto, analisis: analisis));
      final fila = _filas(excel, 'Deudas').single;

      expect(fila[3], '—', reason: 'no saber el límite no es tener cero');
      expect(fila[4], '—');
      expect(fila[5], '—');
    });
  });

  group('Paridad pantalla ↔ exportación', () {
    test('la suma del Excel de CxC es exactamente el KPI de saldo', () async {
      final cliente = await crearCliente('Paridad');
      await crearCuenta(clienteId: cliente, importe: 700000, vencimiento: DateTime(2026, 5, 1));
      await crearCuenta(clienteId: cliente, importe: 300000, vencimiento: DateTime(2026, 7, 1));

      final analisis = await container.read(obtenerAnalisisCobranzaUseCaseProvider).ejecutar(hoy: hoy);
      final excel = Excel.decodeBytes(
        CuentasPorCobrarXlsxRenderer().generar(contexto: _contexto, cuentas: analisis.cuentas),
      );
      final sumaExcel = _filas(excel, 'Cuentas por cobrar')
          .map((f) => double.parse(f.last))
          .reduce((a, b) => a + b);

      expect(sumaExcel * 100, analisis.saldoPendiente.toDouble());
      expect(analisis.totalAging, analisis.saldoPendiente, reason: 'y el aging también cuadra con el mismo KPI');
    });
  });
}
