import 'package:drift/drift.dart' show Value;
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
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/contacto_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/entidad_fiscal_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_contacto_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_domicilio_fiscal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_entidad_fiscal_resultado.dart';
import 'package:riseg_one/features/organizacion/presentation/clientes/cliente_expediente_controller.dart';
import 'package:riseg_one/features/organizacion/presentation/clientes/cliente_expediente_state.dart';
import 'package:riseg_one/features/organizacion/presentation/clientes/clientes_list_controller.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

/// Sesión Maestro fija — Etapa 11C activó autorización real en
/// `ClienteExpedienteController`; sin este override todas las acciones
/// serían rechazadas por `AuthorizationService` (mismo criterio que
/// `areas_list_screen_test.dart`).
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
  late ProviderContainer container;
  late String clienteId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // El actor de la bitácora es una FK real contra `Usuario`: la
    // sesión de prueba tiene que existir, igual que en producción.
    await db.into(db.usuario).insert(
      UsuarioCompanion.insert(
        id: const Value('usuario-prueba'),
        nombre: 'Usuario de prueba',
        nombreUsuario: 'prueba',
        passwordHash: 'x',
        esMaestro: const Value(true),
      ),
    );
    final crear = CrearClienteUseCase(ClienteRepositoryImpl(db), GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    final creado = await crear.ejecutar(nombreComercial: 'Sportium');
    clienteId = creado.when(ok: (c) => c.id, failure: (f) => throw StateError(f.message));

    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionControllerDePrueba.new),
      ],
    );
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
      motivo: 'Motivo de prueba',
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
      motivo: 'Motivo de prueba',
    );

    expect(exito, isFalse);
    final state = container.read(clienteExpedienteControllerProvider(clienteId));
    expect(state.modo, ClienteExpedienteModo.edicion);
    expect(state.erroresGuardado, contains(isA<ErrorNombreComercialRequerido>()));
  });

  test('cambiarEstatus actualiza el estatus comercial', () async {
    await esperarCargaInicial();
    final notifier = container.read(clienteExpedienteControllerProvider(clienteId).notifier);

    final exito = await notifier.cambiarEstatus(EstatusCliente.activo, motivo: 'Motivo de prueba');

    expect(exito, isTrue);
    expect(container.read(clienteExpedienteControllerProvider(clienteId)).datos?.cliente.estatus, 'activo');
  });

  // Etapa 15, hallazgo real: un Cliente cambiado a Activo desde el
  // expediente seguía viendo "Prospecto" en el listado hasta navegar a
  // otra pestaña y volver — `ClientesListController` nunca se
  // invalidaba tras `cambiarEstatus`. Esta prueba nunca llama
  // `recargar()` a mano: el listado debe reflejar el estatus real
  // solo por la invalidación que `cambiarEstatus` dispara.
  test('cambiarEstatus desde el expediente refleja el nuevo estatus en el listado sin recargar manualmente', () async {
    await esperarCargaInicial();
    container.listen(clientesListControllerProvider, (_, _) {});
    while (container.read(clientesListControllerProvider).cargando) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(
      container.read(clientesListControllerProvider).clientes.singleWhere((c) => c.id == clienteId).estatus,
      'prospecto',
    );

    final notifier = container.read(clienteExpedienteControllerProvider(clienteId).notifier);
    final exito = await notifier.cambiarEstatus(EstatusCliente.activo, motivo: 'Motivo de prueba');
    expect(exito, isTrue);

    // `invalidate` reprograma la reconstrucción para el siguiente
    // microtask — se espera esa vuelta antes de leer, sin tocar
    // `recargar()` ni ningún mecanismo manual.
    await Future<void>.delayed(Duration.zero);
    while (container.read(clientesListControllerProvider).cargando) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(
      container.read(clientesListControllerProvider).clientes.singleWhere((c) => c.id == clienteId).estatus,
      'activo',
    );
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

    await notifier.archivarContacto(contactoId, motivo: 'Motivo de prueba');

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

  group('Entidades fiscales', () {
    test('agregarEntidadFiscal exitoso refresca la lista sin salir de edición', () async {
      await esperarCargaInicial();
      final notifier = container.read(clienteExpedienteControllerProvider(clienteId).notifier);
      notifier.entrarModoEdicion();

      final resultado = await notifier.agregarEntidadFiscal(
        const EntidadFiscalBorrador(razonSocial: 'Sportium Toluca SA de CV', rfc: 'STO010101AB1'),
      );

      expect(resultado, isA<GuardarEntidadFiscalExitoso>());
      final state = container.read(clienteExpedienteControllerProvider(clienteId));
      expect(state.datos?.entidadesFiscales, hasLength(1));
      expect(state.datos?.entidadesFiscales.single.entidadFiscal.codigo, 'ENF-0001');
      expect(state.datos?.contactos, isEmpty, reason: 'no debe afectar la lista de contactos ya cargada');
      expect(state.modo, ClienteExpedienteModo.edicion);
    });

    test('permite más de una Entidad fiscal por Cliente (caso Sportium)', () async {
      await esperarCargaInicial();
      final notifier = container.read(clienteExpedienteControllerProvider(clienteId).notifier);

      await notifier.agregarEntidadFiscal(
        const EntidadFiscalBorrador(razonSocial: 'Sportium Toluca SA de CV', rfc: 'STO010101AB1'),
      );
      await notifier.agregarEntidadFiscal(
        const EntidadFiscalBorrador(razonSocial: 'Sportium Interlomas SA de CV', rfc: 'SIN010101AB2'),
      );

      final state = container.read(clienteExpedienteControllerProvider(clienteId));
      expect(state.datos?.entidadesFiscales, hasLength(2));
    });

    test('agregarEntidadFiscal con RFC duplicado no modifica la lista', () async {
      await esperarCargaInicial();
      final notifier = container.read(clienteExpedienteControllerProvider(clienteId).notifier);

      await notifier.agregarEntidadFiscal(
        const EntidadFiscalBorrador(razonSocial: 'Sportium SA de CV', rfc: 'STO010101AB1'),
      );
      final resultado = await notifier.agregarEntidadFiscal(
        const EntidadFiscalBorrador(razonSocial: 'Otra razón social SA', rfc: 'STO010101AB1'),
      );

      expect(resultado, isA<GuardarEntidadFiscalErroresValidacion>());
      expect(container.read(clienteExpedienteControllerProvider(clienteId)).datos?.entidadesFiscales, hasLength(1));
    });

    test('actualizarEntidadFiscal refresca los datos mostrados', () async {
      await esperarCargaInicial();
      final notifier = container.read(clienteExpedienteControllerProvider(clienteId).notifier);
      final agregado = await notifier.agregarEntidadFiscal(
        const EntidadFiscalBorrador(razonSocial: 'Sportium SA de CV', rfc: 'STO010101AB1'),
      );
      final entidadId = (agregado as GuardarEntidadFiscalExitoso).entidadFiscal.id;

      await notifier.actualizarEntidadFiscal(
        entidadId,
        const EntidadFiscalBorrador(razonSocial: 'Sportium Toluca SA de CV', rfc: 'STO010101AB1'),
        motivo: 'Motivo de prueba',
      );

      final state = container.read(clienteExpedienteControllerProvider(clienteId));
      expect(state.datos?.entidadesFiscales.single.entidadFiscal.razonSocial, 'Sportium Toluca SA de CV');
    });

    test('cambiarCicloVidaEntidadFiscal archiva y una edición posterior es rechazada', () async {
      await esperarCargaInicial();
      final notifier = container.read(clienteExpedienteControllerProvider(clienteId).notifier);
      final agregado = await notifier.agregarEntidadFiscal(
        const EntidadFiscalBorrador(razonSocial: 'Sportium SA de CV', rfc: 'STO010101AB1'),
      );
      final entidadId = (agregado as GuardarEntidadFiscalExitoso).entidadFiscal.id;

      final archivado = await notifier.cambiarCicloVidaEntidadFiscal(entidadId, CicloVidaRegistro.archivado, motivo: 'Motivo de prueba');
      expect(archivado, isTrue);

      var state = container.read(clienteExpedienteControllerProvider(clienteId));
      expect(state.datos?.entidadesFiscales.single.entidadFiscal.cicloVidaRegistro, 'archivado');

      final edicion = await notifier.actualizarEntidadFiscal(
        entidadId,
        const EntidadFiscalBorrador(razonSocial: 'Otro nombre SA', rfc: 'STO010101AB1'),
        motivo: 'Motivo de prueba',
      );
      expect(edicion, isA<GuardarEntidadFiscalArchivada>());

      final reactivado = await notifier.cambiarCicloVidaEntidadFiscal(entidadId, CicloVidaRegistro.activo, motivo: 'Motivo de prueba');
      expect(reactivado, isTrue);
      state = container.read(clienteExpedienteControllerProvider(clienteId));
      expect(state.datos?.entidadesFiscales.single.entidadFiscal.cicloVidaRegistro, 'activo');
    });

    test('guardarDomicilioFiscal actualiza "Datos fiscales incompletos"', () async {
      await esperarCargaInicial();
      final notifier = container.read(clienteExpedienteControllerProvider(clienteId).notifier);
      final agregado = await notifier.agregarEntidadFiscal(
        const EntidadFiscalBorrador(razonSocial: 'Sportium SA de CV', rfc: 'STO010101AB1'),
      );
      final entidadId = (agregado as GuardarEntidadFiscalExitoso).entidadFiscal.id;

      expect(
        container.read(clienteExpedienteControllerProvider(clienteId)).datos?.entidadesFiscales.single.datosFiscalesCompletos,
        isFalse,
      );

      final resultado = await notifier.guardarDomicilioFiscal(
        entidadId,
        const DireccionBorrador(
          calle: 'Av. Reforma',
          numeroExterior: '100',
          colonia: 'Juárez',
          municipioAlcaldia: 'Cuauhtémoc',
          estado: 'CDMX',
          codigoPostal: '06600',
        ),
      );

      expect(resultado, isA<GuardarDomicilioFiscalExitoso>());
      expect(
        container.read(clienteExpedienteControllerProvider(clienteId)).datos?.entidadesFiscales.single.datosFiscalesCompletos,
        isTrue,
      );
    });
  });
}
