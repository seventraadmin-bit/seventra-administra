import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/categoria_articulo_table.dart' show AplicacionEspecializadaCategoriaArticulo;
import 'package:riseg_one/features/inventario/domain/usecases/actualizar_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/archivar_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/archivar_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/corregir_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_variante_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/existencia_articulo.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_ajuste_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_baja_unidad_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_baja_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_unidad_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_usecase.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_de_unidad_coordinador.dart';

void main() {
  late AppDatabase db;
  late CategoriaArticuloRepositoryImpl categoriaRepo;
  late ArticuloRepositoryImpl articuloRepo;
  late InventarioRepositoryImpl inventarioRepo;
  late CrearCategoriaArticuloUseCase crearCategoria;
  late ArchivarCategoriaArticuloUseCase archivarCategoria;
  late ActualizarCategoriaArticuloUseCase actualizarCategoria;
  late CrearArticuloUseCase crearArticulo;
  late CorregirArticuloUseCase corregirArticulo;
  late ArchivarArticuloUseCase archivarArticulo;
  late CrearVarianteArticuloUseCase crearVariante;
  late RegistrarEntradaUseCase registrarEntrada;
  late RegistrarEntradaUnidadUseCase registrarEntradaUnidad;
  late RegistrarBajaUseCase registrarBaja;
  late RegistrarBajaUnidadUseCase registrarBajaUnidad;
  late RegistrarAjusteUseCase registrarAjuste;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    categoriaRepo = CategoriaArticuloRepositoryImpl(db);
    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    crearCategoria = CrearCategoriaArticuloUseCase(categoriaRepo);
    archivarCategoria = ArchivarCategoriaArticuloUseCase(categoriaRepo);
    actualizarCategoria = ActualizarCategoriaArticuloUseCase(categoriaRepo);
    crearArticulo = CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo);
    corregirArticulo = CorregirArticuloUseCase(articuloRepo, categoriaRepo);
    archivarArticulo = ArchivarArticuloUseCase(articuloRepo);
    crearVariante = CrearVarianteArticuloUseCase(articuloRepo);
    registrarEntrada = RegistrarEntradaUseCase(inventarioRepo, articuloRepo);
    registrarEntradaUnidad = RegistrarEntradaUnidadUseCase(inventarioRepo, articuloRepo, generarCodigo);
    registrarBaja = RegistrarBajaUseCase(inventarioRepo, articuloRepo);
    registrarBajaUnidad = RegistrarBajaUnidadUseCase(inventarioRepo, LineaTelefonicaDeUnidadCoordinador.desde(db));
    registrarAjuste = RegistrarAjusteUseCase(inventarioRepo, articuloRepo);
  });

  tearDown(() => db.close());

  Future<CategoriaArticuloData> crearCategoriaDePrueba({String nombre = 'Camisa'}) async {
    final resultado = await crearCategoria.ejecutar(nombre: nombre);
    return (resultado as CrearCategoriaArticuloExitoso).categoria;
  }

  Future<ArticuloData> crearArticuloDePrueba({
    String nombre = 'Camisa RISEG',
    bool manejaVariante = false,
    bool manejaSerie = false,
    String? categoriaId,
  }) async {
    final categoria = categoriaId ?? (await crearCategoriaDePrueba()).id;
    final resultado = await crearArticulo.ejecutar(
      categoriaId: categoria,
      nombre: nombre,
      manejaVariante: manejaVariante,
      manejaSerie: manejaSerie,
    );
    return (resultado as CrearArticuloExitoso).articulo;
  }

  group('CategoriaArticulo', () {
    test('crea y archiva una categoría', () async {
      final categoria = await crearCategoriaDePrueba(nombre: 'Radio');
      expect(categoria.nombre, 'Radio');
      expect((await categoriaRepo.listar()).map((c) => c.id), contains(categoria.id));

      final archivada = await archivarCategoria.ejecutar(categoria.id);
      expect(archivada, isA<ArchivarCategoriaArticuloExitoso>());
      expect((await categoriaRepo.listar()).map((c) => c.id), isNot(contains(categoria.id)));
    });

    test('rechaza nombre vacío', () async {
      final resultado = await crearCategoria.ejecutar(nombre: '   ');
      expect(resultado, isA<CrearCategoriaArticuloNombreRequerido>());
    });

    test('actualizar: una categoría nace genérica (aplicacionEspecializada null)', () async {
      final categoria = await crearCategoriaDePrueba(nombre: 'Teléfonos');
      expect(categoria.aplicacionEspecializada, isNull);
    });

    test('actualizar: marca una categoría existente como telefonia', () async {
      final categoria = await crearCategoriaDePrueba(nombre: 'Teléfonos');
      final resultado = await actualizarCategoria.ejecutar(
        categoriaId: categoria.id,
        nombre: categoria.nombre,
        aplicacionEspecializada: AplicacionEspecializadaCategoriaArticulo.telefonia,
      );
      expect(resultado, isA<ActualizarCategoriaArticuloExitoso>());
      final actualizada = (resultado as ActualizarCategoriaArticuloExitoso).categoria;
      expect(actualizada.aplicacionEspecializada, AplicacionEspecializadaCategoriaArticulo.telefonia.name);
    });

    test('actualizar: limpiarAplicacionEspecializada vuelve la categoría a genérica', () async {
      final categoria = await crearCategoriaDePrueba(nombre: 'Teléfonos');
      await actualizarCategoria.ejecutar(
        categoriaId: categoria.id,
        nombre: categoria.nombre,
        aplicacionEspecializada: AplicacionEspecializadaCategoriaArticulo.telefonia,
      );
      final resultado = await actualizarCategoria.ejecutar(
        categoriaId: categoria.id,
        nombre: categoria.nombre,
        limpiarAplicacionEspecializada: true,
      );
      final actualizada = (resultado as ActualizarCategoriaArticuloExitoso).categoria;
      expect(actualizada.aplicacionEspecializada, isNull);
    });

    test('actualizar: cambia el nombre sin tocar aplicacionEspecializada si no se pide limpiar', () async {
      final categoria = await crearCategoriaDePrueba(nombre: 'Teléfonos');
      await actualizarCategoria.ejecutar(
        categoriaId: categoria.id,
        nombre: categoria.nombre,
        aplicacionEspecializada: AplicacionEspecializadaCategoriaArticulo.telefonia,
      );
      final resultado = await actualizarCategoria.ejecutar(categoriaId: categoria.id, nombre: 'Equipos telefónicos');
      final actualizada = (resultado as ActualizarCategoriaArticuloExitoso).categoria;
      expect(actualizada.nombre, 'Equipos telefónicos');
      expect(actualizada.aplicacionEspecializada, AplicacionEspecializadaCategoriaArticulo.telefonia.name);
    });

    test('actualizar: rechaza nombre vacío', () async {
      final categoria = await crearCategoriaDePrueba();
      final resultado = await actualizarCategoria.ejecutar(categoriaId: categoria.id, nombre: '   ');
      expect(resultado, isA<ActualizarCategoriaArticuloNombreRequerido>());
    });

    test('actualizar: rechaza categoría inexistente', () async {
      final resultado = await actualizarCategoria.ejecutar(categoriaId: 'no-existe', nombre: 'X');
      expect(resultado, isA<ActualizarCategoriaArticuloNoExiste>());
    });
  });

  group('Articulo', () {
    test('crea un artículo por cantidad, con folio y ART-######', () async {
      final articulo = await crearArticuloDePrueba();
      expect(articulo.folio, startsWith('ART-'));
      expect(articulo.manejaVariante, isFalse);
      expect(articulo.manejaSerie, isFalse);
    });

    test('corrige metadatos sin tocar manejaVariante/manejaSerie', () async {
      final articulo = await crearArticuloDePrueba(manejaVariante: true);
      final resultado = await corregirArticulo.ejecutar(articuloId: articulo.id, nombre: 'Camisa RISEG v2');
      final actualizado = (resultado as CorregirArticuloExitoso).articulo;
      expect(actualizado.nombre, 'Camisa RISEG v2');
      expect(actualizado.manejaVariante, isTrue, reason: 'CorregirArticuloUseCase nunca toca esta bandera');
    });

    test('archiva un artículo', () async {
      final articulo = await crearArticuloDePrueba();
      final resultado = await archivarArticulo.ejecutar(articulo.id);
      expect(resultado, isA<ArchivarArticuloExitoso>());
      expect((await articuloRepo.listar()).map((a) => a.id), isNot(contains(articulo.id)));
    });

    test('rechaza categoría inexistente', () async {
      final resultado = await crearArticulo.ejecutar(categoriaId: 'no-existe', nombre: 'Camisa');
      expect(resultado, isA<CrearArticuloCategoriaNoExiste>());
    });
  });

  group('ArticuloVariante', () {
    test('crea una talla y rechaza duplicados', () async {
      final articulo = await crearArticuloDePrueba(manejaVariante: true);
      final variante = await crearVariante.ejecutar(articuloId: articulo.id, valor: 'M');
      expect(variante, isA<CrearVarianteArticuloExitoso>());

      final duplicado = await crearVariante.ejecutar(articuloId: articulo.id, valor: 'M');
      expect(duplicado, isA<CrearVarianteArticuloValorDuplicado>());
    });

    test('rechaza variante para un Artículo que no la maneja', () async {
      final articulo = await crearArticuloDePrueba();
      final resultado = await crearVariante.ejecutar(articuloId: articulo.id, valor: 'M');
      expect(resultado, isA<CrearVarianteArticuloArticuloNoManejaVariante>());
    });
  });

  group('RegistrarEntradaUseCase y existencia derivada (artículo por cantidad)', () {
    test('una entrada aumenta Disponible; una baja reduce el Total real', () async {
      final articulo = await crearArticuloDePrueba(manejaVariante: true);
      final variante = ((await crearVariante.ejecutar(articuloId: articulo.id, valor: 'M'))
              as CrearVarianteArticuloExitoso)
          .variante;

      await registrarEntrada.ejecutar(
        articuloId: articulo.id,
        varianteId: variante.id,
        cantidad: 20,
        costoUnitario: 25000,
        fecha: DateTime(2026, 1, 1),
      );

      var existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id, varianteId: variante.id);
      expect(existencia.disponible, 20);
      expect(existencia.total, 20);

      final baja = await registrarBaja.ejecutar(
        articuloId: articulo.id,
        varianteId: variante.id,
        cantidad: 3,
        observaciones: 'Merma detectada en conteo físico',
      );
      expect(baja, isA<RegistrarBajaExitoso>());

      existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id, varianteId: variante.id);
      expect(existencia.disponible, 17, reason: 'la baja sí reduce el Total real, a diferencia de un ajuste');
    });

    test('rechaza una entrada para un Artículo serializado', () async {
      final articulo = await crearArticuloDePrueba(manejaSerie: true);
      final resultado =
          await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 5, fecha: DateTime(2026, 1, 1));
      expect(resultado, isA<RegistrarEntradaArticuloManejaSerie>());
    });

    test('rechaza una entrada sin variante cuando el Artículo la maneja', () async {
      final articulo = await crearArticuloDePrueba(manejaVariante: true);
      final resultado =
          await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 5, fecha: DateTime(2026, 1, 1));
      expect(resultado, isA<RegistrarEntradaVarianteInvalida>());
    });

    test('rechaza una baja que excede el Disponible', () async {
      final articulo = await crearArticuloDePrueba();
      await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 5, fecha: DateTime(2026, 1, 1));

      final resultado = await registrarBaja.ejecutar(articuloId: articulo.id, cantidad: 10, observaciones: 'Prueba');
      expect(resultado, isA<RegistrarBajaSobrepasaDisponible>());
      expect((resultado as RegistrarBajaSobrepasaDisponible).disponible, 5);
    });

    test('rechaza una baja sin observaciones', () async {
      final articulo = await crearArticuloDePrueba();
      await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 5, fecha: DateTime(2026, 1, 1));

      final resultado = await registrarBaja.ejecutar(articuloId: articulo.id, cantidad: 1, observaciones: '  ');
      expect(resultado, isA<RegistrarBajaObservacionesRequeridas>());
    });
  });

  group('RegistrarAjusteUseCase', () {
    test('un ajusteEntrada aumenta Disponible sin afectar reportes de entrada real', () async {
      final articulo = await crearArticuloDePrueba();
      await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 10, fecha: DateTime(2026, 1, 1));

      final resultado = await registrarAjuste.ejecutar(
        articuloId: articulo.id,
        cantidad: 2,
        esEntrada: true,
        observaciones: 'Conteo físico encontró 2 más',
      );
      expect(resultado, isA<RegistrarAjusteExitoso>());

      final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existencia.disponible, 12);
    });

    test('rechaza un ajusteSalida que excede el Disponible', () async {
      final articulo = await crearArticuloDePrueba();
      await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 3, fecha: DateTime(2026, 1, 1));

      final resultado = await registrarAjuste.ejecutar(
        articuloId: articulo.id,
        cantidad: 5,
        esEntrada: false,
        observaciones: 'Conteo físico',
      );
      expect(resultado, isA<RegistrarAjusteSobrepasaDisponible>());
    });
  });

  group('Unidades serializadas (radios, teléfonos)', () {
    test('registra la entrada de un teléfono con IMEI/número, separado de la tabla genérica', () async {
      final articulo = await crearArticuloDePrueba(nombre: 'Teléfono', manejaSerie: true);

      final resultado = await registrarEntradaUnidad.ejecutar(
        articuloId: articulo.id,
        numeroSerie: 'SN-TEL-0001',
        marca: 'Samsung',
        modelo: 'A15',
        imei: '123456789012345',
        numeroTelefonico: '5551234567',
        fecha: DateTime(2026, 1, 1),
      );

      expect(resultado, isA<RegistrarEntradaUnidadExitoso>());
      final unidad = (resultado as RegistrarEntradaUnidadExitoso).unidad;
      expect(unidad.codigo, startsWith('UNI-'));
      expect(unidad.estatus, 'disponible');

      final telefono = await inventarioRepo.obtenerTelefono(unidad.id);
      expect(telefono, isNotNull);
      expect(telefono!.imei, '123456789012345');

      final existencia = await inventarioRepo.calcularExistenciaUnidades(articulo.id);
      expect(existencia.disponible, 1);
      expect(existencia.total, 1);
    });

    test('rechaza dos unidades con el mismo número de serie', () async {
      final articulo = await crearArticuloDePrueba(nombre: 'Radio', manejaSerie: true);
      await registrarEntradaUnidad.ejecutar(articuloId: articulo.id, numeroSerie: 'SN-DUP', fecha: DateTime(2026, 1, 1));

      final resultado =
          await registrarEntradaUnidad.ejecutar(articuloId: articulo.id, numeroSerie: 'SN-DUP', fecha: DateTime(2026, 1, 1));
      expect(resultado, isA<RegistrarEntradaUnidadErrorInesperado>());
    });

    test('da de baja una unidad y dobla como error en un segundo intento', () async {
      final articulo = await crearArticuloDePrueba(nombre: 'Radio', manejaSerie: true);
      final unidad = ((await registrarEntradaUnidad.ejecutar(
        articuloId: articulo.id,
        numeroSerie: 'SN-0099',
        fecha: DateTime(2026, 1, 1),
      )) as RegistrarEntradaUnidadExitoso)
          .unidad;

      final resultado = await registrarBajaUnidad.ejecutar(unidadId: unidad.id, observaciones: 'Equipo obsoleto');
      expect(resultado, isA<RegistrarBajaUnidadExitoso>());

      final existencia = await inventarioRepo.calcularExistenciaUnidades(articulo.id);
      expect(existencia.total, 0, reason: 'una unidad dada de baja sale del Total real');

      final segundoIntento = await registrarBajaUnidad.ejecutar(unidadId: unidad.id, observaciones: 'De nuevo');
      expect(segundoIntento, isA<RegistrarBajaUnidadYaDeBaja>());
    });

    test(
      'Etapa 0 (bug real corregido): rechaza dar de baja una unidad ASIGNADA — el estatus/existencia nunca cambian, '
      'y el repositorio (no solo el caso de uso) también la bloquea',
      () async {
        final articulo = await crearArticuloDePrueba(nombre: 'Radio', manejaSerie: true);
        final unidad = ((await registrarEntradaUnidad.ejecutar(
          articuloId: articulo.id,
          numeroSerie: 'SN-ASIGNADA',
          fecha: DateTime(2026, 1, 1),
        )) as RegistrarEntradaUnidadExitoso)
            .unidad;
        // Simula custodia activa sin depender de todo el aparato de
        // Asignaciones (fuera del alcance de este archivo) — el punto
        // de esta prueba es el guard sobre `ArticuloUnidad.estatus`,
        // no el flujo de Asignación en sí.
        await (db.update(db.articuloUnidad)..where((t) => t.id.equals(unidad.id)))
            .write(const ArticuloUnidadCompanion(estatus: Value('asignado')));

        final resultado = await registrarBajaUnidad.ejecutar(unidadId: unidad.id, observaciones: 'Intento indebido');
        expect(resultado, isA<RegistrarBajaUnidadAsignada>());

        final unidadTras = await (db.select(db.articuloUnidad)..where((t) => t.id.equals(unidad.id))).getSingle();
        expect(unidadTras.estatus, 'asignado', reason: 'el estatus nunca cambia si la corrección se rechaza');
        final movimientos = await db.select(db.movimientoInventario).get();
        expect(movimientos.where((m) => m.unidadId == unidad.id), hasLength(1), reason: 'solo el movimiento de entrada original — ninguno de baja');

        // El repositorio en sí también rechaza (defensa en profundidad,
        // sin importar el llamador) — mismo criterio que
        // `_validarNoNegativo`/`_validarVarianteCoherente`.
        await expectLater(
          inventarioRepo.registrarBajaUnidad(unidadId: unidad.id, observaciones: 'Directo al repositorio'),
          throwsA(isA<UnidadAsignadaException>()),
        );
      },
    );

    test('rechaza registrar una unidad para un Artículo que no maneja serie', () async {
      final articulo = await crearArticuloDePrueba();
      final resultado =
          await registrarEntradaUnidad.ejecutar(articuloId: articulo.id, numeroSerie: 'SN-1', fecha: DateTime(2026, 1, 1));
      expect(resultado, isA<RegistrarEntradaUnidadArticuloNoManejaSerie>());
    });
  });
}
