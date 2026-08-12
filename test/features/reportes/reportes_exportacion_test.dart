// Etapa 12D (Reportes generales — Exportación) — pruebas de renderers,
// use cases de exportación y utilidades compartidas. No usa la UI:
// solo construye los DTOs ya autorizados a mano (mismo objeto que un
// controller real produciría) y verifica los bytes resultantes, para
// no depender de tocar botones reales (que invocarían
// `AttachmentStorage.abrir` — un proceso real del sistema operativo).

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart' as xlsx;

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/repositories/empresa_repository_impl.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';
import 'package:riseg_one/features/reportes/data/pdf/reporte_general_pdf_renderer.dart';
import 'package:riseg_one/features/reportes/data/xlsx/compras_periodo_xlsx_renderer.dart';
import 'package:riseg_one/features/reportes/data/xlsx/personal_eventos_xlsx_renderer.dart';
import 'package:riseg_one/features/reportes/domain/export/exportar_reporte_resultado.dart';
import 'package:riseg_one/features/reportes/domain/export/guardar_y_abrir_reporte.dart';
import 'package:riseg_one/features/reportes/domain/export/reporte_export_context.dart';
import 'package:riseg_one/features/reportes/domain/export/sanitizar_nombre_archivo.dart';
import 'package:riseg_one/features/reportes/domain/usecases/exportar_reporte_general_pdf_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_compras_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_general_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_personal_usecase.dart';

/// `AttachmentStorage.abrir` invocaría `cmd /c start` real — se
/// sobreescribe para solo registrar la llamada, mismo patrón que
/// `_AttachmentStorageDePrueba` en `resguardo_integration_test.dart`.
class _AttachmentStorageDePrueba extends AttachmentStorage {
  _AttachmentStorageDePrueba(super.attachmentsDir);
  final rutasAbiertas = <String>[];

  @override
  Future<void> abrir(String path) async {
    rutasAbiertas.add(path);
  }
}

void main() {
  group('sanitizarNombreArchivo', () {
    test('sin acentos, espacios ni caracteres inválidos', () {
      final nombre = sanitizarNombreArchivo(
        base: 'Reporte General (Compras/Nómina) — Área "Norte"',
        generadoEn: DateTime(2026, 8, 11, 14, 32, 5),
        extension: 'pdf',
      );

      expect(nombre, matches(RegExp(r'^[a-z0-9_\-.]+$')));
      expect(nombre, isNot(contains(' ')));
      expect(nombre, isNot(contains('ó')));
      expect(nombre, endsWith('.pdf'));
      expect(nombre, contains('20260811-143205'));
    });

    test('dos llamadas en distinto segundo producen nombres distintos', () {
      final a = sanitizarNombreArchivo(base: 'x', generadoEn: DateTime(2026, 1, 1, 0, 0, 0), extension: 'xlsx');
      final b = sanitizarNombreArchivo(base: 'x', generadoEn: DateTime(2026, 1, 1, 0, 0, 1), extension: 'xlsx');
      expect(a, isNot(equals(b)));
    });
  });

  group('guardarYAbrirReporte', () {
    late Directory tempDir;
    late _AttachmentStorageDePrueba storage;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('riseg_reportes_export_test_');
      storage = _AttachmentStorageDePrueba(tempDir.path);
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('escribe el archivo, lo abre, y retorna la ruta real', () async {
      final resultado = await guardarYAbrirReporte(
        bytes: [1, 2, 3, 4],
        nombreBase: 'reporte de prueba',
        extension: 'pdf',
        generadoEn: DateTime(2026, 1, 1),
        reportesDir: '${tempDir.path}/reportes',
        attachmentStorage: storage,
      );

      expect(resultado, isA<ExportarReporteExitoso>());
      final ruta = (resultado as ExportarReporteExitoso).rutaArchivo;
      final archivo = File(ruta);
      expect(archivo.existsSync(), isTrue);
      expect(archivo.lengthSync(), greaterThan(0));
      expect(storage.rutasAbiertas, [ruta]);
    });
  });

  group('ReporteGeneralPdfRenderer', () {
    test('resumen con todas las secciones autorizadas produce un PDF válido y no vacío', () async {
      final bytes = await ReporteGeneralPdfRenderer().renderizar(
        contexto: ReporteExportContext(
          nombreReporte: 'Reporte General',
          rangoInicio: DateTime(2026, 8, 1),
          rangoFin: DateTime(2026, 8, 11),
          generadoPor: 'Usuario de prueba',
          generadoEn: DateTime(2026, 8, 11),
        ),
        resumen: const ResumenGeneralReportes(
          totalIngresos: 500000,
          totalEgresos: 300000,
          resultadoOperativo: 200000,
          totalComprasPeriodo: 100000,
          totalNominaPagadaPeriodo: 150000,
          personalActivoActual: 42,
          serviciosActivosActual: 7,
        ),
      );

      expect(bytes.length, greaterThan(0));
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('resumen sin ninguna sección autorizada (todo null) igual produce un PDF válido', () async {
      final bytes = await ReporteGeneralPdfRenderer().renderizar(
        contexto: ReporteExportContext(
          nombreReporte: 'Reporte General',
          rangoInicio: null,
          rangoFin: null,
          generadoPor: 'Usuario de prueba',
          generadoEn: DateTime(2026, 8, 11),
        ),
        resumen: const ResumenGeneralReportes(),
      );

      expect(bytes.length, greaterThan(0));
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });

  group('PersonalEventosXlsxRenderer', () {
    test('genera una hoja por tipo de evento con las filas correctas', () {
      final bytes = PersonalEventosXlsxRenderer().generar(
        contexto: ReporteExportContext(
          nombreReporte: 'Eventos de Personal',
          rangoInicio: DateTime(2026, 8, 1),
          rangoFin: DateTime(2026, 8, 11),
          generadoPor: 'Usuario de prueba',
          generadoEn: DateTime(2026, 8, 11),
        ),
        resumen: ResumenPersonalReportes(
          totalActivos: 1,
          totalAdministrativos: 0,
          totalOperativos: 1,
          personalPorServicio: const {},
          altasEnPeriodo: [
            EmpleadoReporteRow(
              id: 'emp-1',
              numeroEmpleado: 101,
              nombres: 'Ana',
              apellidoPaterno: 'García',
              estatus: 'activo',
              fechaIngreso: DateTime(2026, 8, 5),
            ),
          ],
          reingresosEnPeriodo: const [],
          bajasEnPeriodo: [
            BajaEnPeriodo(
              empleadoId: 'emp-2',
              nombreCompleto: 'Luis Pérez',
              fechaBaja: DateTime(2026, 8, 3),
              motivoBaja: MotivoBajaEmpleado.renuncia,
            ),
          ],
          motivosBajaConteo: const {},
          proximosAniversarios: const [],
          alertasRecontratacion: const [],
        ),
      );

      final leido = xlsx.Excel.decodeBytes(bytes);
      expect(leido.tables.keys, containsAll(['Info', 'Altas', 'Reingresos', 'Bajas', 'Proximos aniversarios', 'Alertas recontratacion']));

      final altas = leido.tables['Altas']!;
      expect(altas.maxRows, 2); // encabezado + 1 fila
      expect(altas.rows[1][1]?.value.toString(), 'Ana García');

      final bajas = leido.tables['Bajas']!;
      expect(bajas.maxRows, 2);
      expect(bajas.rows[1][0]?.value.toString(), 'Luis Pérez');
    });
  });

  group('ComprasPeriodoXlsxRenderer', () {
    test('genera las tres hojas de desglose con los totales correctos', () {
      final bytes = ComprasPeriodoXlsxRenderer().generar(
        contexto: ReporteExportContext(
          nombreReporte: 'Compras del periodo',
          rangoInicio: DateTime(2026, 8, 1),
          rangoFin: DateTime(2026, 8, 11),
          generadoPor: 'Usuario de prueba',
          generadoEn: DateTime(2026, 8, 11),
        ),
        resumen: const ResumenComprasReportes(
          totalComprado: 500050,
          totalCanceladas: 0,
          totalInventario: 300000,
          totalGastoDirecto: 200050,
          porProveedor: [TotalPorClave(clave: 'Proveedor Uno', total: 500050)],
          porFormaPago: [TotalPorClave(clave: 'transferencia', total: 500050)],
          porArticuloOConcepto: [TotalPorClave(clave: 'Uniformes', total: 300000), TotalPorClave(clave: 'Papelería', total: 200050)],
        ),
      );

      final leido = xlsx.Excel.decodeBytes(bytes);
      expect(leido.tables.keys, containsAll(['Info', 'Por proveedor', 'Por forma de pago', 'Por articulo o concepto']));

      final porProveedor = leido.tables['Por proveedor']!;
      expect(porProveedor.rows[1][0]?.value.toString(), 'Proveedor Uno');
      expect((porProveedor.rows[1][1]?.value as xlsx.DoubleCellValue).value, 5000.5);

      final porArticulo = leido.tables['Por articulo o concepto']!;
      expect(porArticulo.maxRows, 3); // encabezado + 2 conceptos
    });
  });

  group('ExportarReporteGeneralPdfUseCase — integración con Empresa/AttachmentStorage reales', () {
    late AppDatabase db;
    late Directory tempDir;
    late _AttachmentStorageDePrueba storage;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      tempDir = Directory.systemTemp.createTempSync('riseg_reportes_export_usecase_test_');
      storage = _AttachmentStorageDePrueba(tempDir.path);
    });

    tearDown(() async {
      await db.close();
      tempDir.deleteSync(recursive: true);
    });

    test('genera el PDF, lo guarda en reportesDir, y lo abre — sin persistir ningún Attachment', () async {
      final empresaRepo = EmpresaRepositoryImpl(db);
      final attachmentRepo = AttachmentRepository(db);
      final usecase = ExportarReporteGeneralPdfUseCase(
        ReporteGeneralPdfRenderer(),
        empresaRepo,
        attachmentRepo,
        storage,
        '${tempDir.path}/reportes',
      );

      final resultado = await usecase.ejecutar(
        contexto: ReporteExportContext(
          nombreReporte: 'Reporte General',
          rangoInicio: DateTime(2026, 8, 1),
          rangoFin: DateTime(2026, 8, 11),
          generadoPor: 'Usuario de prueba',
          generadoEn: DateTime(2026, 8, 11),
        ),
        resumen: const ResumenGeneralReportes(totalIngresos: 100000, totalEgresos: 50000, resultadoOperativo: 50000),
      );

      expect(resultado, isA<ExportarReporteExitoso>());
      final ruta = (resultado as ExportarReporteExitoso).rutaArchivo;
      final bytes = await File(ruta).readAsBytes();
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(storage.rutasAbiertas, [ruta]);

      final conteoAttachments = await (db.select(db.attachment)..limit(1)).get();
      expect(conteoAttachments, isEmpty, reason: 'el reporte generado no es adjunto de ninguna entidad de negocio');
    });
  });
}
