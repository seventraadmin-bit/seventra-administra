import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/cliente_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/contacto_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cliente_expediente_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cliente_expediente_input.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/contacto_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_contacto_resultado.dart';
import 'package:riseg_one/features/organizacion/presentation/clientes/cliente_expediente_controller.dart';
import 'package:riseg_one/features/organizacion/presentation/clientes/cliente_expediente_state.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String clienteId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final crear = CrearClienteUseCase(ClienteRepositoryImpl(db), GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    final creado = await crear.ejecutar(nombreComercial: 'Sportium');
    clienteId = creado.when(ok: (c) => c.id, failure: (f) => throw StateError(f.message));

    container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    container.listen(clienteExpedienteControllerProvider(clienteId), (_, _) {});
  });

  tearDown(() => db.close());

  Future<void> esperarCargaInicial() async {
    while (container.read(clienteExpedienteControllerProvider(clienteId)).cargando) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('carga inicial resuelve el Cliente creado', () async {
    await esperarCargaInicial();
    final state = container.read(clienteExpedienteControllerProvider(clienteId));

    expect(state.cargando, isFalse);
    expect(state.errorCarga, isNull);
    expect(state.datos?.cliente.nombreComercial, 'Sportium');
    expect(state.datos?.contactos, isEmpty);
    expect(state.modo, ClienteExpedienteModo.consulta);
  });

  test('entrarModoEdicion cambia a edición y limpia errores previos', () async {
    await esperarCargaInicial();
    final notifier = container.read(clienteExpedienteControllerProvider(clienteId).notifier);

    notifier.entrarModoEdicion();

    final state = container.read(clienteExpedienteControllerProvider(clienteId));
    expect(state.modo, ClienteExpedienteModo.edicion);
    expect(state.tieneCambiosSinGuardar, isFalse);
  });

  test('cancelarEdicion regresa a consulta y limpia el indicador de cambios', () async {
    await esperarCargaInicial();
    final notifier = container.read(clienteExpedienteControllerProvider(clienteId).notifier);
    notifier.entrarModoEdicion();
    notifier.marcarCambiosSinGuardar();

    notifier.cancelarEdicion();

    final state = container.read(clienteExpedienteControllerProvider(clienteId));
    expect(state.modo, ClienteExpedienteModo.consulta);
    expect(state.tieneCambiosSinGuardar, isFalse);
  });

  test('guardar con datos válidos persiste y regresa a consulta', () async {
    await esperarCargaInicial();
    final notifier = container.read(clienteExpedienteControllerProvider(clienteId).notifier);
    notifier.entrarModoEdicion();

    final exito = await notifier.guardar(
      const ClienteExpedienteInput(
        datosGenerales: ClienteDatosGeneralesInput(nombreComercial: 'Sportium Renombrado'),
        direccionReferencia: DireccionBorrador(
          calle: 'Reforma',
          numeroExterior: '123',
          colonia: 'Centro',
          municipioAlcaldia: 'Cuauhtémoc',
          estado: 'CDMX',
          codigoPostal: '06000',
        ),
      ),
    );

    expect(exito, isTrue);
    final state = container.read(clienteExpedienteControllerProvider(clienteId));
    expect(state.modo, ClienteExpedienteModo.consulta);
    expect(state.datos?.cliente.nombreComercial, 'Sportium Renombrado');
    expect(state.datos?.direccionReferencia?.calle, 'Reforma');
  });

  test('guardar con nombre comercial vacío reporta el error estructurado sin persistir', () async {
    await esperarCargaInicial();
    final notifier = container.read(clienteExpedienteControllerProvider(clienteId).notifier);
    notifier.entrarModoEdicion();

    final exito = await notifier.guardar(
      const ClienteExpedienteInput(datosGenerales: ClienteDatosGeneralesInput(nombreComercial: '   ')),
    );

    expect(exito, isFalse);
    final state = container.read(clienteExpedienteControllerProvider(clienteId));
    expect(state.modo, ClienteExpedienteModo.edicion);
    expect(state.erroresGuardado, contains(isA<ErrorNombreComercialRequerido>()));
  });

  test('cambiarEstatus actualiza el estatus comercial', () async {
    await esperarCargaInicial();
    final notifier = container.read(clienteExpedienteControllerProvider(clienteId).notifier);

    final exito = await notifier.cambiarEstatus(EstatusCliente.activo);

    expect(exito, isTrue);
    expect(container.read(clienteExpedienteControllerProvider(clienteId)).datos?.cliente.estatus, 'activo');
  });

  test('agregarContacto exitoso refresca la lista de contactos sin salir de edición', () async {
    await esperarCargaInicial();
    final notifier = container.read(clienteExpedienteControllerProvider(clienteId).notifier);
    notifier.entrarModoEdicion();

    final resultado = await notifier.agregarContacto(
      const ContactoBorrador(nombre: 'Juan Pérez', tipo: TipoContacto.comercial, telefono: '5555555555'),
    );

    expect(resultado, isA<GuardarContactoExitoso>());
    final state = container.read(clienteExpedienteControllerProvider(clienteId));
    expect(state.datos?.contactos, hasLength(1));
    expect(state.datos?.contactos.single.nombre, 'Juan Pérez');
    // La sección de contactos es independiente del formulario principal
    // — agregar un contacto no debe sacar la pantalla de modo edición.
    expect(state.modo, ClienteExpedienteModo.edicion);
  });

  test('agregarContacto con datos inválidos no modifica la lista de contactos', () async {
    await esperarCargaInicial();
    final notifier = container.read(clienteExpedienteControllerProvider(clienteId).notifier);

    final resultado = await notifier.agregarContacto(
      const ContactoBorrador(nombre: '', tipo: null),
    );

    expect(resultado, isA<GuardarContactoErroresValidacion>());
    expect(container.read(clienteExpedienteControllerProvider(clienteId)).datos?.contactos, isEmpty);
  });

  test('archivarContacto lo retira de la lista visible', () async {
    await esperarCargaInicial();
    final notifier = container.read(clienteExpedienteControllerProvider(clienteId).notifier);

    final agregado = await notifier.agregarContacto(
      const ContactoBorrador(nombre: 'Juan Pérez', tipo: TipoContacto.comercial, telefono: '5555555555'),
    );
    final contactoId = (agregado as GuardarContactoExitoso).contacto.id;

    await notifier.archivarContacto(contactoId);

    expect(container.read(clienteExpedienteControllerProvider(clienteId)).datos?.contactos, isEmpty);
  });

  test('reintentarCarga vuelve a intentar tras un error de carga', () async {
    await esperarCargaInicial();
    final notifier = container.read(clienteExpedienteControllerProvider(clienteId).notifier);

    await notifier.reintentarCarga();

    final state = container.read(clienteExpedienteControllerProvider(clienteId));
    expect(state.cargando, isFalse);
    expect(state.datos, isNotNull);
  });
}
