import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/pdf/resguardo_pdf_renderer.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart';
import 'package:riseg_one/features/inventario/domain/usecases/adjuntar_resguardo_firmado_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/cerrar_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/generar_documento_resguardo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/reemplazar_asignacion_usecase.dart';
import 'package:riseg_one/features/organizacion/data/repositories/empresa_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';

/// `AttachmentStorage` sin efectos de proceso — `abrir` en producción
/// lanza el visor de PDF del sistema operativo (`cmd /c start` en
/// Windows), algo que una prueba automatizada nunca debe disparar.
class _AttachmentStorageDePrueba extends AttachmentStorage {
  _AttachmentStorageDePrueba(super.attachmentsDir);

  final rutasAbiertas = <String>[];

  @override
  Future<void> abrir(String path) async {
    rutasAbiertas.add(path);
  }
}

void main() {
  late AppDatabase db;
  late ArticuloRepositoryImpl articuloRepo;
  late InventarioRepositoryImpl inventarioRepo;
  late AsignacionRepositoryImpl asignacionRepo;
  late AttachmentRepository attachmentRepo;
  late _AttachmentStorageDePrueba storage;
  late CrearCategoriaArticuloUseCase crearCategoria;
  late CrearArticuloUseCase crearArticulo;
  late RegistrarEntradaUseCase registrarEntrada;
  late CrearAsignacionUseCase crearAsignacion;
  late CerrarAsignacionUseCase cerrarAsignacion;
  late ReemplazarAsignacionUseCase reemplazarAsignacion;
  late GenerarDocumentoResguardoUseCase generarDocumento;
  late AdjuntarResguardoFirmadoUseCase adjuntarFirmado;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    asignacionRepo = AsignacionRepositoryImpl(db);
    attachmentRepo = AttachmentRepository(db);
    storage = _AttachmentStorageDePrueba(Directory.systemTemp.path);
    final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
    final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
    final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
    final empresaRepo = EmpresaRepositoryImpl(db);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    crearCategoria = CrearCategoriaArticuloUseCase(categoriaRepo);
    crearArticulo = CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo);
    registrarEntrada = RegistrarEntradaUseCase(inventarioRepo, articuloRepo);
    crearAsignacion = CrearAsignacionUseCase(asignacionRepo, articuloRepo, inventarioRepo);
    cerrarAsignacion = CerrarAsignacionUseCase(asignacionRepo);
    reemplazarAsignacion = ReemplazarAsignacionUseCase(asignacionRepo, articuloRepo, inventarioRepo);
    generarDocumento = GenerarDocumentoResguardoUseCase(
      asignacionRepo,
      articuloRepo,
      inventarioRepo,
      empleadoRepo,
      servicioRepo,
      empresaRepo,
      attachmentRepo,
      storage,
      ResguardoPdfRenderer(),
    );
    adjuntarFirmado = AdjuntarResguardoFirmadoUseCase(asignacionRepo, storage);
  });

  tearDown(() => db.close());

  Future<ArticuloData> crearArticuloDePrueba({String nombre = 'Camisa RISEG'}) async {
    final categoria = (await crearCategoria.ejecutar(nombre: '$nombre-categoria') as CrearCategoriaArticuloExitoso).categoria;
    final resultado = await crearArticulo.ejecutar(categoriaId: categoria.id, nombre: nombre);
    return (resultado as CrearArticuloExitoso).articulo;
  }

  Future<EmpleadoData> crearEmpleadoDePrueba({int numeroEmpleado = 1}) {
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: numeroEmpleado,
            nombres: 'Juan',
            apellidoPaterno: 'Pérez',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX0$numeroEmpleado',
            rfc: 'PEXJ900101AB$numeroEmpleado',
            nss: '1234567890$numeroEmpleado',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
  }

  Future<AsignacionData> asignarDePrueba(ArticuloData articulo, String empleadoId, {int cantidad = 1}) async {
    await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 5, fecha: DateTime(2026, 1, 1));
    final resultado = await crearAsignacion.ejecutar(
      articuloId: articulo.id,
      cantidad: cantidad,
      empleadoId: empleadoId,
      fechaEntrega: DateTime(2026, 1, 5),
    );
    return (resultado as CrearAsignacionExitoso).asignacion;
  }

  group('GenerarDocumentoResguardoUseCase', () {
    test('genera el PDF para 1 y para N Asignaciones del mismo Empleado y lo abre para imprimir (sin persistir)', () async {
      final articulo1 = await crearArticuloDePrueba(nombre: 'Camisa');
      final articulo2 = await crearArticuloDePrueba(nombre: 'Chaleco');
      final empleado = await crearEmpleadoDePrueba();
      final asignacion1 = await asignarDePrueba(articulo1, empleado.id);
      final asignacion2 = await asignarDePrueba(articulo2, empleado.id);

      final resultado = await generarDocumento.ejecutar(asignacionIds: [asignacion1.id, asignacion2.id]);
      expect(resultado, isA<GenerarDocumentoResguardoExitoso>());
      expect(storage.rutasAbiertas, hasLength(1), reason: 'debe abrir el PDF generado para imprimir');

      final soloUno = await generarDocumento.ejecutar(asignacionIds: [asignacion1.id]);
      expect(soloUno, isA<GenerarDocumentoResguardoExitoso>());

      final adjuntosTrasGenerar = await attachmentRepo.listarActivosPorAsignacion(asignacion1.id);
      expect(adjuntosTrasGenerar, isEmpty, reason: 'generar el documento nunca inserta un Attachment');
    });

    test('genera correctamente el documento de una Asignación que viene de un reemplazo (reemplazos documentados)', () async {
      final articulo = await crearArticuloDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final vieja = await asignarDePrueba(articulo, empleado.id);

      final reemplazo = await reemplazarAsignacion.ejecutar(
        asignacionId: vieja.id,
        motivo: MotivoCierreAsignacion.defecto,
        fechaCierre: DateTime(2026, 1, 10),
        articuloIdReemplazo: articulo.id,
        cantidadReemplazo: 1,
      );
      final nueva = (reemplazo as ReemplazarAsignacionExitoso).nuevaAsignacion;

      final resultado = await generarDocumento.ejecutar(asignacionIds: [nueva.id]);
      expect(resultado, isA<GenerarDocumentoResguardoExitoso>(), reason: 'la línea "Sustituye a" no debe romper la generación');
    });

    test('rechaza Asignaciones de destinos distintos mezcladas', () async {
      final articulo = await crearArticuloDePrueba();
      final empleado1 = await crearEmpleadoDePrueba(numeroEmpleado: 1);
      final empleado2 = await crearEmpleadoDePrueba(numeroEmpleado: 2);
      final asignacion1 = await asignarDePrueba(articulo, empleado1.id);
      final asignacion2 = await asignarDePrueba(articulo, empleado2.id);

      final resultado = await generarDocumento.ejecutar(asignacionIds: [asignacion1.id, asignacion2.id]);
      expect(resultado, isA<GenerarDocumentoResguardoDestinoInvalido>());
    });

    test('rechaza una lista vacía', () async {
      final resultado = await generarDocumento.ejecutar(asignacionIds: const []);
      expect(resultado, isA<GenerarDocumentoResguardoSinAsignaciones>());
    });
  });

  group('AdjuntarResguardoFirmadoUseCase', () {
    test('liga el mismo Attachment a todas las Asignaciones seleccionadas — consultable desde cada una', () async {
      final articulo1 = await crearArticuloDePrueba(nombre: 'Camisa');
      final articulo2 = await crearArticuloDePrueba(nombre: 'Chaleco');
      final empleado = await crearEmpleadoDePrueba();
      final asignacion1 = await asignarDePrueba(articulo1, empleado.id);
      final asignacion2 = await asignarDePrueba(articulo2, empleado.id);

      final archivoOrigen = await _crearArchivoTemporalDePrueba();
      final resultado = await adjuntarFirmado.ejecutar(
        asignacionIds: [asignacion1.id, asignacion2.id],
        sourceFilePath: archivoOrigen.path,
        originalFileName: 'resguardo_firmado.pdf',
        mimeType: 'application/pdf',
      );
      expect(resultado, isA<AdjuntarResguardoFirmadoExitoso>());
      final attachmentId = (resultado as AdjuntarResguardoFirmadoExitoso).adjunto.id;

      final adjuntos1 = await attachmentRepo.listarActivosPorAsignacion(asignacion1.id);
      final adjuntos2 = await attachmentRepo.listarActivosPorAsignacion(asignacion2.id);
      expect(adjuntos1.map((a) => a.id), [attachmentId]);
      expect(adjuntos2.map((a) => a.id), [attachmentId]);

      await archivoOrigen.delete();
    });

    test('sigue accesible tras devolver la Asignación que cubre — nunca se oculta, solo se marca histórico en UI', () async {
      final articulo = await crearArticuloDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      final asignacion = await asignarDePrueba(articulo, empleado.id);

      final archivoOrigen = await _crearArchivoTemporalDePrueba();
      await adjuntarFirmado.ejecutar(
        asignacionIds: [asignacion.id],
        sourceFilePath: archivoOrigen.path,
        originalFileName: 'resguardo_firmado.pdf',
        mimeType: 'application/pdf',
      );
      await archivoOrigen.delete();

      final cierre = await cerrarAsignacion.ejecutar(
        asignacionId: asignacion.id,
        motivo: MotivoCierreAsignacion.desgaste,
        fechaCierre: DateTime(2026, 2, 1),
      );
      expect(cierre, isA<CerrarAsignacionExitoso>());

      final adjuntos = await attachmentRepo.listarActivosPorAsignacion(asignacion.id);
      expect(adjuntos, hasLength(1), reason: 'el documento sigue existiendo aunque la Asignación ya no esté activa');
    });

    test('rechaza destinos mezclados y lista vacía', () async {
      final articulo = await crearArticuloDePrueba();
      final empleado1 = await crearEmpleadoDePrueba(numeroEmpleado: 1);
      final empleado2 = await crearEmpleadoDePrueba(numeroEmpleado: 2);
      final asignacion1 = await asignarDePrueba(articulo, empleado1.id);
      final asignacion2 = await asignarDePrueba(articulo, empleado2.id);

      final archivoOrigen = await _crearArchivoTemporalDePrueba();
      final mezclado = await adjuntarFirmado.ejecutar(
        asignacionIds: [asignacion1.id, asignacion2.id],
        sourceFilePath: archivoOrigen.path,
        originalFileName: 'resguardo.pdf',
        mimeType: 'application/pdf',
      );
      expect(mezclado, isA<AdjuntarResguardoFirmadoDestinoInvalido>());

      final vacio = await adjuntarFirmado.ejecutar(
        asignacionIds: const [],
        sourceFilePath: archivoOrigen.path,
        originalFileName: 'resguardo.pdf',
        mimeType: 'application/pdf',
      );
      expect(vacio, isA<AdjuntarResguardoFirmadoSinAsignaciones>());

      await archivoOrigen.delete();
    });
  });
}

Future<File> _crearArchivoTemporalDePrueba() async {
  final file = File(p.join(Directory.systemTemp.path, 'resguardo_prueba_${DateTime.now().microsecondsSinceEpoch}.pdf'));
  await file.writeAsBytes([1, 2, 3]);
  return file;
}
