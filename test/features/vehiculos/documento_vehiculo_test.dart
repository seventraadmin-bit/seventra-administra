import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_documento_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_table.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/adjuntar_archivo_documento_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/agrupar_documentos_vehiculo.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/calcular_estado_vigencia_documento.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/crear_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/dar_de_baja_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/registrar_documento_vehiculo_usecase.dart';

/// Cubre Documentos y alertas de vencimiento de Vehículos (Etapa 8C) —
/// las 11 pruebas explícitamente pedidas por Marlon: estados derivados
/// (sin vencimiento/vigente/próximo a vencer/vencido con el umbral de
/// 30 días), renovación como fila nueva (histórico intacto, nunca se
/// edita), adjuntos opcionales, `otro` exige descripción, y que la baja
/// del vehículo conserve documentos mientras las Alertas los excluyen
/// (esta última se verifica en `test/smoke_test.dart`, que sí puede
/// pumpear la pantalla real).
void main() {
  late AppDatabase db;
  late VehiculoRepositoryImpl vehiculoRepo;
  late VehiculoDocumentoRepositoryImpl documentoRepo;
  late AttachmentRepository attachmentRepo;
  late CrearVehiculoUseCase crearVehiculo;
  late DarDeBajaVehiculoUseCase darDeBaja;
  late RegistrarDocumentoVehiculoUseCase registrarDocumento;
  late AdjuntarArchivoDocumentoVehiculoUseCase adjuntarArchivo;
  late Directory tempDir;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    vehiculoRepo = VehiculoRepositoryImpl(db, AsignacionVehiculoRepositoryImpl(db));
    documentoRepo = VehiculoDocumentoRepositoryImpl(db);
    attachmentRepo = AttachmentRepository(db);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    crearVehiculo = CrearVehiculoUseCase(vehiculoRepo, generarCodigo);
    darDeBaja = DarDeBajaVehiculoUseCase(vehiculoRepo);
    registrarDocumento = RegistrarDocumentoVehiculoUseCase(documentoRepo, vehiculoRepo);

    tempDir = Directory.systemTemp.createTempSync('riseg_documento_vehiculo_test_');
    adjuntarArchivo = AdjuntarArchivoDocumentoVehiculoUseCase(documentoRepo, AttachmentStorage(tempDir.path));
  });

  tearDown(() {
    db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<VehiculoData> crearVehiculoDePrueba() async {
    final resultado = await crearVehiculo.ejecutar(marca: 'BMW', modelo: '320i', tipoVehiculo: 'sedan');
    return (resultado as CrearVehiculoExitoso).vehiculo;
  }

  group('calcularEstadoVigenciaDocumento', () {
    test('sin fecha de vencimiento → sinVencimiento', () {
      expect(calcularEstadoVigenciaDocumento(null), EstadoVigenciaDocumento.sinVencimiento);
    });

    test('vigente (fuera del umbral de 30 días)', () {
      final estado = calcularEstadoVigenciaDocumento(DateTime(2026, 12, 31), hoy: DateTime(2026, 8, 10));
      expect(estado, EstadoVigenciaDocumento.vigente);
    });

    test('próximo a vencer (dentro del umbral de 30 días)', () {
      final estado = calcularEstadoVigenciaDocumento(DateTime(2026, 8, 25), hoy: DateTime(2026, 8, 10));
      expect(estado, EstadoVigenciaDocumento.proximoAVencer);
    });

    test('vencido (fecha ya pasada)', () {
      final estado = calcularEstadoVigenciaDocumento(DateTime(2026, 8, 1), hoy: DateTime(2026, 8, 10));
      expect(estado, EstadoVigenciaDocumento.vencido);
    });
  });

  group('RegistrarDocumentoVehiculoUseCase', () {
    test('tipo otro exige descripción', () async {
      final vehiculo = await crearVehiculoDePrueba();

      final sinDescripcion = await registrarDocumento.ejecutar(vehiculoId: vehiculo.id, tipo: 'otro');
      expect(sinDescripcion, isA<RegistrarDocumentoVehiculoDescripcionRequerida>());

      final conDescripcion = await registrarDocumento.ejecutar(
        vehiculoId: vehiculo.id,
        tipo: 'otro',
        tipoOtroDescripcion: 'Constancia de no adeudo',
      );
      expect(conDescripcion, isA<RegistrarDocumentoVehiculoExitoso>());
    });

    test('rechaza fecha de vencimiento anterior a la de emisión', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final resultado = await registrarDocumento.ejecutar(
        vehiculoId: vehiculo.id,
        tipo: 'seguro',
        fechaEmision: DateTime(2026, 6, 1),
        fechaVencimiento: DateTime(2026, 1, 1),
      );
      expect(resultado, isA<RegistrarDocumentoVehiculoFechasInvalidas>());
    });

    test('documento sin archivo sigue siendo válido', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final resultado = await registrarDocumento.ejecutar(
        vehiculoId: vehiculo.id,
        tipo: 'tarjetaCirculacion',
        numeroFolio: 'TC-001',
      );
      expect(resultado, isA<RegistrarDocumentoVehiculoExitoso>());

      final documento = (resultado as RegistrarDocumentoVehiculoExitoso).documento;
      final adjuntos = await attachmentRepo.listarActivosPorVehiculoDocumento(documento.id);
      expect(adjuntos, isEmpty);
    });

    test('renovación conserva histórico — nunca edita la fila anterior', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final original = ((await registrarDocumento.ejecutar(
        vehiculoId: vehiculo.id,
        tipo: 'seguro',
        fechaEmision: DateTime(2025, 1, 1),
        fechaVencimiento: DateTime(2026, 1, 1),
      )) as RegistrarDocumentoVehiculoExitoso)
          .documento;

      final renovado = ((await registrarDocumento.ejecutar(
        vehiculoId: vehiculo.id,
        tipo: 'seguro',
        fechaEmision: DateTime(2026, 1, 1),
        fechaVencimiento: DateTime(2027, 1, 1),
      )) as RegistrarDocumentoVehiculoExitoso)
          .documento;

      final historial = await documentoRepo.listarPorVehiculo(vehiculo.id);
      expect(historial, hasLength(2), reason: 'la renovación es una fila nueva, la anterior no se toca');

      final anteriorIntacto = historial.singleWhere((d) => d.id == original.id);
      expect(anteriorIntacto.fechaVencimiento, DateTime(2026, 1, 1), reason: 'el histórico nunca se edita');

      final vigentes = documentosVigentesPorTipo(historial);
      expect(vigentes, hasLength(1));
      expect(vigentes.single.id, renovado.id, reason: 'el vigente de un tipo es el más reciente por fechaEmision');
    });

    test('múltiples documentos del mismo tipo en histórico — todos conservados, agrupados por tipo', () async {
      final vehiculo = await crearVehiculoDePrueba();
      await registrarDocumento.ejecutar(
        vehiculoId: vehiculo.id,
        tipo: 'verificacion',
        fechaEmision: DateTime(2025, 1, 1),
        fechaVencimiento: DateTime(2025, 7, 1),
      );
      await registrarDocumento.ejecutar(
        vehiculoId: vehiculo.id,
        tipo: 'verificacion',
        fechaEmision: DateTime(2025, 7, 2),
        fechaVencimiento: DateTime(2026, 1, 2),
      );
      final tercero = ((await registrarDocumento.ejecutar(
        vehiculoId: vehiculo.id,
        tipo: 'verificacion',
        fechaEmision: DateTime(2026, 1, 3),
        fechaVencimiento: DateTime(2026, 7, 3),
      )) as RegistrarDocumentoVehiculoExitoso)
          .documento;

      final historial = await documentoRepo.listarPorVehiculo(vehiculo.id);
      expect(historial, hasLength(3));

      final vigentes = documentosVigentesPorTipo(historial);
      expect(vigentes, hasLength(1), reason: 'un solo tipo — solo el más reciente cuenta como vigente');
      expect(vigentes.single.id, tercero.id);
    });

    test('archivo adjunto se guarda y puede consultarse (abrir)', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final documento = ((await registrarDocumento.ejecutar(vehiculoId: vehiculo.id, tipo: 'poliza'))
              as RegistrarDocumentoVehiculoExitoso)
          .documento;

      final archivo = '${tempDir.path}/poliza.pdf';
      File(archivo).writeAsStringSync('contenido de prueba');

      final resultado = await adjuntarArchivo.ejecutar(
        vehiculoDocumentoId: documento.id,
        sourceFilePath: archivo,
        originalFileName: 'poliza.pdf',
        mimeType: 'application/pdf',
      );
      expect(resultado, isA<AdjuntarArchivoDocumentoVehiculoExitoso>());

      final adjuntos = await attachmentRepo.listarActivosPorVehiculoDocumento(documento.id);
      expect(adjuntos, hasLength(1));
      expect(File(adjuntos.single.path).existsSync(), isTrue, reason: 'el archivo copiado sí existe en disco — se puede abrir');
    });

    test('vehículo dado de baja conserva sus documentos', () async {
      final vehiculo = await crearVehiculoDePrueba();
      await registrarDocumento.ejecutar(
        vehiculoId: vehiculo.id,
        tipo: 'tenenciaRefrendo',
        fechaEmision: DateTime(2026, 1, 1),
      );

      await darDeBaja.ejecutar(vehiculoId: vehiculo.id, fechaBaja: DateTime(2026, 3, 1), motivoBaja: MotivoBajaVehiculo.venta);

      final historial = await documentoRepo.listarPorVehiculo(vehiculo.id);
      expect(historial, hasLength(1), reason: 'la baja no borra ni oculta el histórico de documentos');
    });
  });
}
