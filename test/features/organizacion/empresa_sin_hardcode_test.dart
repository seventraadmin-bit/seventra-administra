// Etapa 5B.3 — RISEG deja de ser la empresa implícita del producto.
//
// Lo que estas pruebas fijan es una sola regla: **el nombre de la empresa
// que aparece en una pantalla o en un documento sale de la Empresa
// almacenada, y de ningún otro sitio**. Ni de un literal, ni de un asset,
// ni del nombre del producto.
//
// El contenido de un PDF no se puede leer aquí (el paquete `pdf` comprime
// los flujos de texto y el proyecto no tiene parser), así que el nombre se
// verifica **diferencialmente**: dos empresas distintas no pueden producir
// el mismo documento.

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/config/app_paths.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_data.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/inventario/data/pdf/resguardo_pdf_renderer.dart';
import 'package:riseg_one/features/inventario/domain/usecases/resguardo_data.dart';
import 'package:riseg_one/features/organizacion/data/pdf/tarjeta_fiscal_pdf_renderer.dart';
import 'package:riseg_one/features/organizacion/data/repositories/empresa_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/shared/direccion_input.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/generar_tarjeta_fiscal_pdf_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/obtener_empresa_activa_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/obtener_expediente_empresa_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/tarjeta_fiscal_data.dart';
import 'package:riseg_one/features/personal/data/tables/conciliacion_baja_table.dart';
import 'package:riseg_one/features/reportes/data/pdf/reporte_general_pdf_renderer.dart';
import 'package:riseg_one/features/reportes/domain/export/reporte_export_context.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_general_usecase.dart';
import 'package:riseg_one/features/respaldo/domain/portable/clave_recuperacion.dart';
import 'package:riseg_one/features/respaldo/domain/portable/contenedor_portable.dart';
import 'package:riseg_one/features/respaldo/domain/rutas_paquete.dart';

/// Dos nombres que no se parecen en nada, a propósito: si un documento
/// saliera igual para los dos, el nombre no estaría llegando.
const _empresaA = 'Extintores del Bajio';
const _empresaB = 'Vigilancia Costa Norte';

/// `AttachmentStorage.abrir` llamaría a `cmd /c start` de verdad.
class _StorageDePrueba extends AttachmentStorage {
  _StorageDePrueba(super.attachmentsDir);

  @override
  Future<void> abrir(String path) async {}
}

/// ¿Alguna cadena del archivo nombra a la empresa piloto? Sólo cadenas:
/// los comentarios pueden seguir explicando la historia, y de hecho lo hacen.
Iterable<String> _literalesConEmpresaPiloto(String ruta) {
  final fuente = File(ruta).readAsStringSync();
  final literales = RegExp('\'[^\']*\'').allMatches(fuente).map((m) => m.group(0)!);
  return literales.where((l) {
    final mayus = l.toUpperCase();
    return mayus.contains('RISEG') || mayus.contains('RIZEG');
  });
}

void main() {
  group('A. El código ya no nombra a ninguna empresa concreta', () {
    // Los seis documentos que imprimían un rótulo fijo con la empresa
    // piloto. Si alguien vuelve a escribirlo, esta prueba lo caza.
    const renderers = [
      'lib/features/organizacion/data/pdf/tarjeta_fiscal_pdf_renderer.dart',
      'lib/features/organizacion/data/pdf/recibo_pago_pdf_renderer.dart',
      'lib/features/personal/data/pdf/ficha_tecnica_pdf_renderer.dart',
      'lib/features/inventario/data/pdf/resguardo_pdf_renderer.dart',
      'lib/features/nomina/data/pdf/nomina_dispersion_pdf_renderer.dart',
      'lib/features/reportes/data/pdf/reporte_pdf_encabezado.dart',
    ];

    for (final ruta in renderers) {
      test('ningún literal de empresa en ${ruta.split('/').last}', () {
        expect(
          _literalesConEmpresaPiloto(ruta),
          isEmpty,
          reason: 'un documento no puede nombrar por su cuenta a una empresa',
        );
      });
    }

    test('los cuatro documentos que lo reciben lo toman de la Empresa', () {
      // Guarda de cableado: el caso de uso debe pasar el nombre desde la
      // Empresa que acaba de leer, nunca uno propio.
      const casosDeUso = [
        'lib/features/inventario/domain/usecases/generar_documento_resguardo_usecase.dart',
        'lib/features/personal/domain/usecases/generar_ficha_tecnica_empleado_usecase.dart',
        'lib/features/nomina/domain/usecases/generar_nomina_dispersion_pdf_usecase.dart',
        'lib/features/reportes/domain/usecases/exportar_reporte_general_pdf_usecase.dart',
      ];
      for (final ruta in casosDeUso) {
        expect(
          File(ruta).readAsStringSync(),
          contains('empresaNombreComercial: empresa.nombreComercial'),
          reason: '$ruta debe tomar el nombre de la Empresa',
        );
      }
    });

    test('el catálogo de textos no menciona a la empresa piloto', () {
      final arb = File('lib/l10n/app_es.arb').readAsStringSync().toUpperCase();
      expect(arb.contains('RISEG'), isFalse);
      expect(arb.contains('RIZEG'), isFalse);
    });

    test('el enum de responsable de costo habla de la empresa, no de una', () {
      // Se guarda como texto libre vía `.name`, así que el valor nuevo es
      // el que verán las filas futuras.
      expect(ResponsableCostoResguardo.values.map((v) => v.name).toList(), ['empresa', 'trabajador']);
    });
  });

  group('B. El nombre llega al documento, y sólo desde la Empresa', () {
    ResguardoData resguardo() => ResguardoData(
      empleadoNombre: 'Juan Perez',
      fechaGeneracion: DateTime(2026, 3, 1),
      items: const [ResguardoItem(articuloNombre: 'Radio', cantidad: 1)],
    );

    test('resguardo: dos empresas distintas no producen el mismo documento', () async {
      final renderer = ResguardoPdfRenderer();
      final data = resguardo();

      final deA = await renderer.renderizar(data: data, empresaNombreComercial: _empresaA);
      final deB = await renderer.renderizar(data: data, empresaNombreComercial: _empresaB);
      final sinEmpresa = await renderer.renderizar(data: data);

      expect(deA, isNot(equals(deB)), reason: 'el nombre de la Empresa llega al PDF');
      expect(deA, isNot(equals(sinEmpresa)));
      for (final bytes in [deA, deB, sinEmpresa]) {
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      }
    });

    test('resguardo: sin nombre de Empresa el documento se emite igual', () async {
      // Ausencia de dato empresarial no es un error y no inventa un nombre.
      final bytes = await ResguardoPdfRenderer().renderizar(data: resguardo());
      expect(bytes, isNotEmpty);
    });

    test('encabezado de reportes: el nombre de la Empresa cambia el PDF', () async {
      final contexto = ReporteExportContext(
        nombreReporte: 'Reporte general',
        rangoInicio: DateTime(2026, 1, 1),
        rangoFin: DateTime(2026, 1, 31),
        generadoPor: 'Maestro',
        generadoEn: DateTime(2026, 2, 1),
      );
      const resumen = ResumenGeneralReportes();
      final renderer = ReporteGeneralPdfRenderer();

      final deA = await renderer.renderizar(
        contexto: contexto,
        resumen: resumen,
        empresaNombreComercial: _empresaA,
      );
      final deB = await renderer.renderizar(
        contexto: contexto,
        resumen: resumen,
        empresaNombreComercial: _empresaB,
      );

      expect(deA, isNot(equals(deB)));
    });

    test('tarjeta fiscal: el documento sigue al nombre guardado en la Empresa', () async {
      final renderer = TarjetaFiscalPdfRenderer();
      TarjetaFiscalData data(String nombre) => TarjetaFiscalData(
        nombreComercial: nombre,
        razonSocial: '$nombre S.A. de C.V.',
        rfc: 'XAXX010101000',
        domicilioLineas: const ['Calle 1'],
        generadoEn: DateTime(2026, 2, 1),
      );

      final deA = await renderer.renderizar(data: data(_empresaA));
      final deB = await renderer.renderizar(data: data(_empresaB));
      expect(deA, isNot(equals(deB)));
    });
  });

  group('B2. La siembra nace neutral y jamás reescribe lo que ya existe', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('instalación nueva: la Empresa inicial nace con código neutral', () async {
      final empresa = await db.select(db.empresa).getSingle();
      expect(empresa.codigo, 'EMP-01');
      expect(empresa.codigo.toUpperCase(), isNot(contains('RSG')));
      expect(empresa.nombreComercial.toUpperCase(), isNot(contains('RISEG')));
      expect(empresa.id, SeedIds.empresaInicial, reason: 'el UUID sembrado no cambia nunca');
    });

    test('instalación nueva: el prefijo de códigos de Empresa es neutral', () async {
      final secuencia = await (db.select(
        db.codigoSecuencia,
      )..where((t) => t.entityType.equals('empresa'))).getSingle();
      expect(secuencia.prefijo, 'EMP');
      // La Empresa inicial ya consumió el 01.
      expect(secuencia.contadorActual, 1);
    });

    test('instalación EXISTENTE: volver a sembrar no le toca su RSG-01', () async {
      // Esto es exactamente lo que le pasa a la instalación real de RISEG en
      // cada arranque y en cada `onUpgrade`: la siembra vuelve a correr.
      // `insertOrIgnore` sobre el mismo id —y sobre el mismo `entityType`—
      // no reescribe nada, así que aquí NO hay migración de datos.
      await (db.update(db.empresa)..where((t) => t.id.equals(SeedIds.empresaInicial))).write(
        const EmpresaCompanion(codigo: Value('RSG-01'), nombreComercial: Value('Seguridad Privada RISEG')),
      );
      await (db.update(db.codigoSecuencia)..where((t) => t.entityType.equals('empresa'))).write(
        const CodigoSecuenciaCompanion(prefijo: Value('RSG')),
      );

      await runSeed(db);

      final empresa = await db.select(db.empresa).getSingle();
      expect(empresa.codigo, 'RSG-01', reason: 'la Empresa existente conserva su código');
      expect(empresa.nombreComercial, 'Seguridad Privada RISEG', reason: 'y su nombre');

      final secuencia = await (db.select(
        db.codigoSecuencia,
      )..where((t) => t.entityType.equals('empresa'))).getSingle();
      expect(secuencia.prefijo, 'RSG', reason: 'sus códigos futuros siguen la serie que ya venía usando');
    });
  });

  group('C. Una Empresa que no es la piloto funciona igual', () {
    late AppDatabase db;
    late Directory tempDir;
    late EmpresaRepositoryImpl empresaRepo;
    late GenerarTarjetaFiscalPdfUseCase generar;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      tempDir = Directory.systemTemp.createTempSync('riseg_5b3_test_');
      empresaRepo = EmpresaRepositoryImpl(db);
      generar = GenerarTarjetaFiscalPdfUseCase(
        ObtenerExpedienteEmpresaUseCase(ObtenerEmpresaActivaUseCase(empresaRepo), empresaRepo),
        AttachmentRepository(db),
        _StorageDePrueba(tempDir.path),
        '${tempDir.path}/datos_fiscales',
        TarjetaFiscalPdfRenderer(),
      );
    });

    tearDown(() async {
      await db.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    Future<void> renombrar(String nombre) async {
      final activa = await empresaRepo.obtenerActiva();
      await empresaRepo.guardarExpediente(
        empresaId: activa.id,
        datosGenerales: EmpresaCompanion(
          nombreComercial: Value(nombre),
          razonSocial: Value('$nombre S.A. de C.V.'),
          rfc: const Value('XAXX010101000'),
        ),
        direccionFiscal: const DireccionInput(
          calle: 'Av. Reforma',
          numeroExterior: '100',
          colonia: 'Centro',
          municipioAlcaldia: 'Cuauhtemoc',
          estado: 'Ciudad de Mexico',
          codigoPostal: '06600',
        ),
        medioContacto: null,
      );
    }

    test('la siembra no nace con el nombre de la empresa piloto', () async {
      final activa = await empresaRepo.obtenerActiva();
      expect(activa.nombreComercial.toUpperCase(), isNot(contains('RISEG')));
      expect(activa.logoAttachmentId, isNull, reason: 'tampoco hereda un logotipo');
    });

    test('renombrada, su tarjeta fiscal se emite con sus propios datos', () async {
      await renombrar(_empresaA);
      final primero = await generar.ejecutar();
      expect(primero, isA<GenerarTarjetaFiscalPdfExitoso>());
      final bytesA = await File((primero as GenerarTarjetaFiscalPdfExitoso).rutaArchivo).readAsBytes();
      expect(bytesA, isNotEmpty);

      // Y el documento cambia al cambiar la Empresa: la fuente es la BD.
      await renombrar(_empresaB);
      final segundo = await generar.ejecutar() as GenerarTarjetaFiscalPdfExitoso;
      final bytesB = await File(segundo.rutaArchivo).readAsBytes();
      expect(bytesA, isNot(equals(bytesB)));
    });

    test('sin logotipo la generación no se bloquea (5B.2 no retrocede)', () async {
      await renombrar(_empresaA);
      final activa = await empresaRepo.obtenerActiva();
      expect(activa.logoAttachmentId, isNull);
      expect(await generar.ejecutar(), isA<GenerarTarjetaFiscalPdfExitoso>());
    });

    test('si la Empresa SE LLAMA RISEG, sus documentos lo dicen — porque es un dato', () async {
      // La empresa piloto no pierde nada: su identidad vive en la base.
      // Lo que se eliminó es que el producto la diera por supuesta.
      await renombrar('Seguridad Privada RISEG');
      final activa = await empresaRepo.obtenerActiva();
      expect(activa.nombreComercial, 'Seguridad Privada RISEG');

      final conRiseg = await generar.ejecutar();
      expect(conRiseg, isA<GenerarTarjetaFiscalPdfExitoso>());
      final bytesRiseg = await File((conRiseg as GenerarTarjetaFiscalPdfExitoso).rutaArchivo).readAsBytes();

      await renombrar(_empresaA);
      final otro = await generar.ejecutar() as GenerarTarjetaFiscalPdfExitoso;
      expect(bytesRiseg, isNot(equals(await File(otro.rutaArchivo).readAsBytes())));
    });
  });

  group('D. Los identificadores técnicos congelados siguen intactos', () {
    test('formato del respaldo portable', () {
      expect(ContenedorPortable.magic, 'RISEGBKP');
      expect(ContenedorPortable.extension, '.risegbkp');
      expect(RutasPaquete.nombreBaseDatos, 'riseg_one.sqlite');
      expect(ClaveRecuperacion.prefijoPresentacion, 'RISEG');
    });

    test('rutas de datos ancladas', () {
      expect(AppPaths.carpetaFabricante, 'RISEG');
      expect(AppPaths.carpetaProducto, 'RISEG ONE');
    });

    test('la etiqueta AAD del bloque de recuperación no cambió', () {
      final fuente = File(
        'lib/features/respaldo/domain/portable/configuracion_recuperacion.dart',
      ).readAsStringSync();
      expect(fuente, contains(r"'RISEG-BKP-v1 recovery-block $backupSetId'"));
    });
  });
}
