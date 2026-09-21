// Etapa 14A (Búsqueda global) — pruebas de los `Buscar*UseCase` y de
// `BuscarGlobalUseCase`: coincidencia insensible a mayúsculas, corte a
// 5 resultados, y la guardia real de permiso (cada `incluirXxx` en
// `false` nunca invoca su use case correspondiente, verificado
// comprobando que el repositorio detrás de él tampoco se llamó).

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/articulo_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/cliente_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';
import 'package:riseg_one/features/telefonia/domain/repositories/linea_telefonica_repository.dart';
import 'package:riseg_one/features/usuarios/data/repositories/usuario_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/repositories/usuario_repository.dart';
import 'package:riseg_one/features/vehiculos/domain/repositories/vehiculo_repository.dart';

import 'package:riseg_one/features/busqueda/domain/usecases/buscar_articulos_usecase.dart';
import 'package:riseg_one/features/busqueda/domain/usecases/buscar_clientes_usecase.dart';
import 'package:riseg_one/features/busqueda/domain/usecases/buscar_compras_usecase.dart';
import 'package:riseg_one/features/busqueda/domain/usecases/buscar_empleados_usecase.dart';
import 'package:riseg_one/features/busqueda/domain/usecases/buscar_global_usecase.dart';
import 'package:riseg_one/features/busqueda/domain/usecases/buscar_lineas_telefonicas_usecase.dart';
import 'package:riseg_one/features/busqueda/domain/usecases/buscar_servicios_usecase.dart';
import 'package:riseg_one/features/busqueda/domain/usecases/buscar_usuarios_usecase.dart';
import 'package:riseg_one/features/busqueda/domain/usecases/buscar_vehiculos_usecase.dart';

class _EmpleadoRepoVacio implements EmpleadoRepository {
  var llamado = false;
  @override
  Future<List<EmpleadoReporteRow>> listarParaReporte({String? estatus}) async {
    llamado = true;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _ClienteRepoVacio implements ClienteRepository {
  var llamado = false;
  @override
  Future<List<ClienteData>> listarActivos() async {
    llamado = true;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _ServicioRepoVacio implements ServicioRepository {
  var llamado = false;
  @override
  Future<List<ServicioListItem>> listar() async {
    llamado = true;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _ArticuloRepoVacio implements ArticuloRepository {
  var llamado = false;
  @override
  Future<List<ArticuloData>> listar({String? categoriaId, bool soloActivos = true}) async {
    llamado = true;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _CompraRepoVacio implements CompraRepository {
  var llamado = false;
  @override
  Future<List<CompraData>> listar({DateTime? desde, DateTime? hasta, String? folio, String? proveedor, String? articuloId, String? estatus, String? formaPago}) async {
    llamado = true;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _VehiculoRepoVacio implements VehiculoRepository {
  var llamado = false;
  @override
  Future<List<VehiculoData>> listar({bool soloActivos = true}) async {
    llamado = true;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _LineaRepoVacio implements LineaTelefonicaRepository {
  var llamado = false;
  @override
  Future<List<LineaTelefonicaData>> listar({bool soloActivos = true}) async {
    llamado = true;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _UsuarioRepoVacio implements UsuarioRepository {
  var llamado = false;
  @override
  Future<List<UsuarioData>> listar({String? cicloVidaRegistro}) async {
    llamado = true;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

BuscarGlobalUseCase _buscarGlobalDePrueba({
  required EmpleadoRepository empleadoRepo,
  required ClienteRepository clienteRepo,
  required ServicioRepository servicioRepo,
  required ArticuloRepository articuloRepo,
  required CompraRepository compraRepo,
  required VehiculoRepository vehiculoRepo,
  required LineaTelefonicaRepository lineaRepo,
  required UsuarioRepository usuarioRepo,
}) {
  return BuscarGlobalUseCase(
    BuscarEmpleadosUseCase(empleadoRepo),
    BuscarClientesUseCase(clienteRepo),
    BuscarServiciosUseCase(servicioRepo),
    BuscarArticulosUseCase(articuloRepo),
    BuscarComprasUseCase(compraRepo),
    BuscarVehiculosUseCase(vehiculoRepo),
    BuscarLineasTelefonicasUseCase(lineaRepo),
    BuscarUsuariosUseCase(usuarioRepo),
  );
}

void main() {
  group('BuscarEmpleadosUseCase', () {
    late AppDatabase db;
    late EmpleadoRepository empleadoRepo;
    late BuscarEmpleadosUseCase buscarEmpleados;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      empleadoRepo = EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
      buscarEmpleados = BuscarEmpleadosUseCase(empleadoRepo);
      addTearDown(db.close);
    });

    Future<void> crearEmpleado({required String nombres, required String apellidoPaterno, required int numero}) {
      return db.into(db.empleado).insert(
            EmpleadoCompanion.insert(
              numeroEmpleado: numero,
              nombres: nombres,
              apellidoPaterno: apellidoPaterno,
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ90010${numero}HDFXXX0$numero',
              rfc: 'PEXJ90010${numero}AB$numero',
              nss: '123456789$numero',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2025, 1, 1),
              aniosExperienciaSeguridad: 1,
            ),
          );
    }

    test('coincide insensible a mayúsculas por nombre, apellido o número', () async {
      await crearEmpleado(nombres: 'Ana', apellidoPaterno: 'García', numero: 101);
      await crearEmpleado(nombres: 'Luis', apellidoPaterno: 'Pérez', numero: 102);

      expect((await buscarEmpleados.ejecutar('ana')), hasLength(1));
      expect((await buscarEmpleados.ejecutar('GARCÍA')), hasLength(1));
      expect((await buscarEmpleados.ejecutar('101')), hasLength(1));
      expect((await buscarEmpleados.ejecutar('nadie')), isEmpty);
    });

    test('corta a 5 resultados', () async {
      for (var i = 1; i <= 8; i++) {
        await crearEmpleado(nombres: 'Empleado', apellidoPaterno: 'Prueba$i', numero: i);
      }

      final resultado = await buscarEmpleados.ejecutar('Empleado');

      expect(resultado, hasLength(5));
    });

    test('la ruta de cada resultado apunta al expediente correcto', () async {
      await crearEmpleado(nombres: 'Ana', apellidoPaterno: 'García', numero: 1);
      final empleado = (await empleadoRepo.listarParaReporte()).single;

      final resultado = await buscarEmpleados.ejecutar('Ana');

      expect(resultado.single.ruta, '/personal/empleados/${empleado.id}');
    });
  });

  group('BuscarGlobalUseCase — guardia real de permiso', () {
    test('cada incluirXxx en false nunca invoca su repositorio', () async {
      final empleadoRepo = _EmpleadoRepoVacio();
      final clienteRepo = _ClienteRepoVacio();
      final servicioRepo = _ServicioRepoVacio();
      final articuloRepo = _ArticuloRepoVacio();
      final compraRepo = _CompraRepoVacio();
      final vehiculoRepo = _VehiculoRepoVacio();
      final lineaRepo = _LineaRepoVacio();
      final usuarioRepo = _UsuarioRepoVacio();

      final buscarGlobal = _buscarGlobalDePrueba(
        empleadoRepo: empleadoRepo,
        clienteRepo: clienteRepo,
        servicioRepo: servicioRepo,
        articuloRepo: articuloRepo,
        compraRepo: compraRepo,
        vehiculoRepo: vehiculoRepo,
        lineaRepo: lineaRepo,
        usuarioRepo: usuarioRepo,
      );

      final resultados = await buscarGlobal.ejecutar(
        'texto',
        incluirPersonal: false,
        incluirComercial: false,
        incluirInventario: false,
        incluirCompras: false,
        incluirVehiculos: false,
        incluirTelefonia: false,
        incluirUsuarios: false,
      );

      expect(resultados.sinResultados, isTrue);
      expect([empleadoRepo.llamado, clienteRepo.llamado, servicioRepo.llamado, articuloRepo.llamado, compraRepo.llamado, vehiculoRepo.llamado, lineaRepo.llamado, usuarioRepo.llamado], everyElement(isFalse));
    });

    test('incluirComercial: true invoca clientes y servicios, y solo esos dos', () async {
      final empleadoRepo = _EmpleadoRepoVacio();
      final clienteRepo = _ClienteRepoVacio();
      final servicioRepo = _ServicioRepoVacio();
      final articuloRepo = _ArticuloRepoVacio();
      final compraRepo = _CompraRepoVacio();
      final vehiculoRepo = _VehiculoRepoVacio();
      final lineaRepo = _LineaRepoVacio();
      final usuarioRepo = _UsuarioRepoVacio();

      final buscarGlobal = _buscarGlobalDePrueba(
        empleadoRepo: empleadoRepo,
        clienteRepo: clienteRepo,
        servicioRepo: servicioRepo,
        articuloRepo: articuloRepo,
        compraRepo: compraRepo,
        vehiculoRepo: vehiculoRepo,
        lineaRepo: lineaRepo,
        usuarioRepo: usuarioRepo,
      );

      final resultados = await buscarGlobal.ejecutar(
        'texto',
        incluirPersonal: false,
        incluirComercial: true,
        incluirInventario: false,
        incluirCompras: false,
        incluirVehiculos: false,
        incluirTelefonia: false,
        incluirUsuarios: false,
      );

      expect(resultados.clientes, isNotNull);
      expect(resultados.servicios, isNotNull);
      expect(clienteRepo.llamado, isTrue);
      expect(servicioRepo.llamado, isTrue);
      expect([empleadoRepo.llamado, articuloRepo.llamado, compraRepo.llamado, vehiculoRepo.llamado, lineaRepo.llamado, usuarioRepo.llamado], everyElement(isFalse));
    });
  });

  group('BuscarUsuariosUseCase — nunca expone passwordHash', () {
    late AppDatabase db;
    late BuscarUsuariosUseCase buscarUsuarios;
    const hashSecreto = r'pbkdf2$muy-secreto-nunca-debe-salir';

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.into(db.usuario).insert(
            UsuarioCompanion.insert(nombre: 'Ana García', nombreUsuario: 'ana.garcia', passwordHash: hashSecreto),
          );
      buscarUsuarios = BuscarUsuariosUseCase(UsuarioRepositoryImpl(db));
      addTearDown(db.close);
    });

    test('el resultado solo trae nombre/nombreUsuario, nunca el hash', () async {
      final resultado = await buscarUsuarios.ejecutar('ana');

      expect(resultado, hasLength(1));
      expect(resultado.single.titulo, 'Ana García');
      expect(resultado.single.subtitulo, 'ana.garcia');
      expect(resultado.single.titulo, isNot(contains(hashSecreto)));
      expect(resultado.single.subtitulo, isNot(contains(hashSecreto)));
      expect(resultado.single.id, isNot(contains(hashSecreto)));
    });
  });
}
