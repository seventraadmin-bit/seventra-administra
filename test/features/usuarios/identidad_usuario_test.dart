// Etapa 3B — identidad híbrida Usuario ↔ Empleado.
//
// Lo que se fija aquí no es "que el campo se guarde": es de DÓNDE sale
// el nombre y el puesto que ve todo el sistema. La auditoría 3A
// encontró que `empleadoId` era una columna de sólo escritura —se
// capturaba y nada la leía jamás— así que una cuenta vinculada seguía
// mostrando su identidad propia y podía renombrarse desde Usuarios sin
// que nada lo detectara. Estas pruebas existen para que eso no pueda
// volver a pasar en silencio.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/auth/password_hasher.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/features/organizacion/data/repositories/area_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_puesto_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_puesto_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/puesto_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/usuarios/data/repositories/usuario_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/cambiar_vinculo_empleado_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/crear_usuario_usecase.dart';

void main() {
  late AppDatabase db;
  late UsuarioRepositoryImpl usuarioRepo;
  late EmpleadoRepositoryImpl empleadoRepo;
  late PuestoRepositoryImpl puestoRepo;
  late CrearUsuarioUseCase crearUsuario;
  late CambiarVinculoEmpleadoUseCase cambiarVinculo;
  late CrearPuestoUseCase crearPuesto;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    usuarioRepo = UsuarioRepositoryImpl(db);
    empleadoRepo = EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    puestoRepo = PuestoRepositoryImpl(db);
    const hasher = PasswordHasher(iteraciones: 1000);
    crearUsuario = CrearUsuarioUseCase(usuarioRepo, puestoRepo, hasher, empleadoRepo);
    cambiarVinculo = CambiarVinculoEmpleadoUseCase(usuarioRepo, empleadoRepo);
    crearPuesto = CrearPuestoUseCase(
      puestoRepo,
      GenerarCodigoUseCase(CodigoSecuenciaService(db)),
      PuestoValidator(AreaRepositoryImpl(db)),
    );
  });

  tearDown(() => db.close());

  Future<PuestoData> puestoFixture({String nombre = 'Recursos Humanos'}) async {
    final r = await crearPuesto.ejecutar(
      PuestoBorrador(
        nombre: nombre,
        areaId: SeedIds.areaOperaciones,
        tipo: TipoPuesto.administrativo,
        nivelJerarquico: 1,
      ),
    );
    return (r as GuardarPuestoExitoso).puesto;
  }

  /// Un Empleado mínimo. `puestoId` nulo a propósito por omisión: es un
  /// estado real y frecuente, y la Etapa 3B existe en parte porque ese
  /// caso dejaba el alta en un callejón sin salida.
  Future<String> empleadoFixture({
    String nombres = 'JUAN',
    String apellido = 'PEREZ',
    String? puestoId,
    String estatus = 'activo',
    int numero = 1,
  }) async {
    final fila = await db
        .into(db.empleado)
        .insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: numero,
            nombres: nombres,
            apellidoPaterno: apellido,
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX0$numero',
            rfc: 'PEXJ900101A$numero',
            nss: '1234567890$numero',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 3,
            puestoId: Value(puestoId),
            estatus: Value(estatus),
          ),
        );
    return fila.id;
  }

  Future<String> cuentaVinculada(String empleadoId, {String usuario = 'jperez'}) async {
    final r = await crearUsuario.ejecutar(
      nombre: 'IGNORADO',
      nombreUsuario: usuario,
      password: 'contrasena1',
      empleadoId: empleadoId,
    );
    return (r as CrearUsuarioExitoso).usuario.id;
  }

  group('Cuenta independiente — un estado legítimo, nunca un error', () {
    test('1. se crea sin Empleado y conserva su propia identidad', () async {
      final puesto = await puestoFixture();

      final r = await crearUsuario.ejecutar(
        nombre: 'ADMINISTRADOR EXTERNO',
        nombreUsuario: 'externo',
        password: 'contrasena1',
        puestoId: puesto.id,
      );

      expect(r, isA<CrearUsuarioExitoso>());
      final identidad = await usuarioRepo.obtenerConIdentidad((r as CrearUsuarioExitoso).usuario.id);
      expect(identidad!.estaVinculado, isFalse);
      expect(identidad.nombreEfectivo, 'ADMINISTRADOR EXTERNO');
      expect(identidad.nombrePuestoEfectivo, 'Recursos Humanos');
      expect(identidad.empleadoDeBaja, isFalse, reason: 'sin Empleado no hay estado laboral que contradecir');
    });

    test('2. un Maestro se crea sin Empleado', () async {
      final puesto = await puestoFixture();

      final r = await crearUsuario.ejecutar(
        nombre: 'MARLON',
        nombreUsuario: 'marlonrh',
        password: 'contrasena1',
        puestoId: puesto.id,
        esMaestro: true,
      );

      final usuario = (r as CrearUsuarioExitoso).usuario;
      expect(usuario.esMaestro, isTrue);
      expect(usuario.empleadoId, isNull, reason: 'el Maestro nunca necesita expediente laboral');
    });

    test('15. conserva nombre y puesto propios aunque existan Empleados con otros datos', () async {
      final puesto = await puestoFixture();
      await empleadoFixture(nombres: 'OTRO', apellido: 'DISTINTO');

      final r = await crearUsuario.ejecutar(
        nombre: 'CUENTA PROPIA',
        nombreUsuario: 'propia',
        password: 'contrasena1',
        puestoId: puesto.id,
      );

      final identidad = await usuarioRepo.obtenerConIdentidad((r as CrearUsuarioExitoso).usuario.id);
      expect(identidad!.nombreEfectivo, 'CUENTA PROPIA');
      expect(identidad.nombrePuestoEfectivo, 'Recursos Humanos');
    });
  });

  group('Cuenta vinculada — la identidad la manda Personal', () {
    test('3. el nombre efectivo sale del Empleado, no de Usuario.nombre', () async {
      final empleadoId = await empleadoFixture(nombres: 'JUAN', apellido: 'PEREZ');
      final usuarioId = await cuentaVinculada(empleadoId);

      final identidad = await usuarioRepo.obtenerConIdentidad(usuarioId);

      expect(identidad!.nombreEfectivo, 'JUAN PEREZ');
      expect(
        identidad.usuario.nombre,
        isNot('JUAN PEREZ'),
        reason: 'la columna propia queda como snapshot técnico y NO es la que se muestra',
      );
    });

    test('4. el puesto efectivo sale del Empleado', () async {
      final gerente = await puestoFixture(nombre: 'Gerente');
      final empleadoId = await empleadoFixture(puestoId: gerente.id);
      final usuarioId = await cuentaVinculada(empleadoId);

      final identidad = await usuarioRepo.obtenerConIdentidad(usuarioId);

      expect(identidad!.puestoEfectivoId, gerente.id);
      expect(identidad.nombrePuestoEfectivo, 'Gerente');
    });

    test('6. cambiar el nombre del Empleado se refleja en la cuenta, sin sincronizar nada', () async {
      final empleadoId = await empleadoFixture(nombres: 'JUAN', apellido: 'PEREZ');
      final usuarioId = await cuentaVinculada(empleadoId);

      await (db.update(db.empleado)..where((t) => t.id.equals(empleadoId))).write(
        const EmpleadoCompanion(nombres: Value('JUAN CARLOS'), apellidoPaterno: Value('PEREZ LOPEZ')),
      );

      final identidad = await usuarioRepo.obtenerConIdentidad(usuarioId);
      expect(identidad!.nombreEfectivo, 'JUAN CARLOS PEREZ LOPEZ');
      // Nadie copió nada: la fila de Usuario sigue igual que antes.
      expect(identidad.usuario.nombre, 'IGNORADO');
    });

    test('7. cambiar el puesto del Empleado se refleja en la cuenta', () async {
      final auxiliar = await puestoFixture(nombre: 'Auxiliar');
      final gerente = await puestoFixture(nombre: 'Gerente');
      final empleadoId = await empleadoFixture(puestoId: auxiliar.id);
      final usuarioId = await cuentaVinculada(empleadoId);

      await (db.update(db.empleado)..where((t) => t.id.equals(empleadoId)))
          .write(EmpleadoCompanion(puestoId: Value(gerente.id)));

      final identidad = await usuarioRepo.obtenerConIdentidad(usuarioId);
      expect(identidad!.nombrePuestoEfectivo, 'Gerente');
    });

    test('5. editar la cuenta NO puede crear una segunda identidad', () async {
      final empleadoId = await empleadoFixture(nombres: 'JUAN', apellido: 'PEREZ');
      final usuarioId = await cuentaVinculada(empleadoId);

      // Aunque alguien escriba directamente en la columna propia —que
      // es lo que el formulario permitía hacer antes de esta etapa— lo
      // que el sistema muestra sigue siendo el expediente.
      await (db.update(db.usuario)..where((t) => t.id.equals(usuarioId)))
          .write(const UsuarioCompanion(nombre: Value('NOMBRE INVENTADO')));

      final identidad = await usuarioRepo.obtenerConIdentidad(usuarioId);
      expect(
        identidad!.nombreEfectivo,
        'JUAN PEREZ',
        reason: 'el nombre propio de una cuenta vinculada no puede ganarle al expediente',
      );
    });

    test('8. un Empleado SIN puesto puede tener cuenta', () async {
      final empleadoId = await empleadoFixture();

      final r = await crearUsuario.ejecutar(
        nombre: 'IGNORADO',
        nombreUsuario: 'sinpuesto',
        password: 'contrasena1',
        empleadoId: empleadoId,
      );

      expect(
        r,
        isA<CrearUsuarioExitoso>(),
        reason: 'la falta de puesto se corrige en Personal, nunca bloqueando el alta de la cuenta',
      );
      final identidad = await usuarioRepo.obtenerConIdentidad((r as CrearUsuarioExitoso).usuario.id);
      expect(identidad!.nombrePuestoEfectivo, isNull, reason: 'la UI dirá "Sin puesto asignado"');
    });

    test('9. un puesto INACTIVO se sigue mostrando, no desaparece', () async {
      final puesto = await puestoFixture(nombre: 'Puesto retirado');
      final empleadoId = await empleadoFixture(puestoId: puesto.id);
      final usuarioId = await cuentaVinculada(empleadoId);

      await puestoRepo.cambiarCicloVida(id: puesto.id, nuevo: CicloVidaRegistro.inactivo);

      final identidad = await usuarioRepo.obtenerConIdentidad(usuarioId);
      expect(
        identidad!.nombrePuestoEfectivo,
        'Puesto retirado',
        reason: 'el puesto que la cuenta TIENE no deja de existir porque se haya desactivado',
      );

      // Y también en el listado, que es donde aparecía el "—".
      final lista = await usuarioRepo.listarConIdentidad();
      expect(lista.single.nombrePuestoEfectivo, 'Puesto retirado');
    });
  });

  group('Un Empleado, una sola cuenta', () {
    test('10. el caso de uso rechaza un segundo alta sobre el mismo Empleado', () async {
      final empleadoId = await empleadoFixture();
      await cuentaVinculada(empleadoId, usuario: 'primera');

      final r = await crearUsuario.ejecutar(
        nombre: 'IGNORADO',
        nombreUsuario: 'segunda',
        password: 'contrasena1',
        empleadoId: empleadoId,
      );

      expect(r, isA<CrearUsuarioEmpleadoYaTieneCuenta>());
      expect(await db.select(db.usuario).get(), hasLength(1), reason: 'no se escribió nada');
    });

    test('11. el índice único de la base lo impide aunque se esquive el dominio', () async {
      final empleadoId = await empleadoFixture();
      await cuentaVinculada(empleadoId, usuario: 'primera');

      // Escritura directa, saltándose el caso de uso por completo.
      expect(
        () => db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            nombre: 'DIRECTA',
            nombreUsuario: 'directa',
            passwordHash: 'x',
            empleadoId: Value(empleadoId),
          ),
        ),
        throwsA(anything),
        reason: 'idx_usuario_empleado_unico es la garantía final, no el caso de uso',
      );
    });

    test('11b. varias cuentas SIN Empleado conviven: el índice es parcial', () async {
      final puesto = await puestoFixture();
      for (final nombre in ['una', 'otra', 'tercera']) {
        final r = await crearUsuario.ejecutar(
          nombre: nombre,
          nombreUsuario: nombre,
          password: 'contrasena1',
          puestoId: puesto.id,
        );
        expect(r, isA<CrearUsuarioExitoso>());
      }
      expect(await db.select(db.usuario).get(), hasLength(3));
    });

    test('12. re-vincular a un Empleado que ya tiene cuenta se rechaza', () async {
      final ocupado = await empleadoFixture(numero: 1);
      final libre = await empleadoFixture(nombres: 'ANA', apellido: 'LOPEZ', numero: 2);
      await cuentaVinculada(ocupado, usuario: 'ocupada');
      final otra = await cuentaVinculada(libre, usuario: 'otra');

      final r = await cambiarVinculo.ejecutar(usuarioId: otra, empleadoIdNuevo: ocupado, motivo: 'prueba');

      expect(r, isA<CambiarVinculoEmpleadoYaTieneCuenta>());
    });

    test('13. un Empleado inexistente se rechaza', () async {
      final r = await crearUsuario.ejecutar(
        nombre: 'IGNORADO',
        nombreUsuario: 'fantasma',
        password: 'contrasena1',
        empleadoId: 'no-existe',
      );
      expect(r, isA<CrearUsuarioEmpleadoNoExiste>());
    });

    test('14. un Empleado dado de baja no es elegible para una cuenta nueva', () async {
      final empleadoId = await empleadoFixture(estatus: 'baja');

      final r = await crearUsuario.ejecutar(
        nombre: 'IGNORADO',
        nombreUsuario: 'debaja',
        password: 'contrasena1',
        empleadoId: empleadoId,
      );

      expect(r, isA<CrearUsuarioEmpleadoNoElegible>());
    });
  });

  group('Vincular, cambiar y desvincular', () {
    test('16. vincular una cuenta independiente: su identidad pasa a ser la del Empleado', () async {
      final puesto = await puestoFixture(nombre: 'Gerente');
      final empleadoId = await empleadoFixture(nombres: 'ANA', apellido: 'LOPEZ', puestoId: puesto.id);
      final r0 = await crearUsuario.ejecutar(
        nombre: 'CUENTA SUELTA',
        nombreUsuario: 'suelta',
        password: 'contrasena1',
        puestoId: puesto.id,
      );
      final usuarioId = (r0 as CrearUsuarioExitoso).usuario.id;

      final r = await cambiarVinculo.ejecutar(
        usuarioId: usuarioId,
        empleadoIdNuevo: empleadoId,
        motivo: 'La cuenta es de Ana',
      );

      expect(r, isA<CambiarVinculoEmpleadoExitoso>());
      final identidad = await usuarioRepo.obtenerConIdentidad(usuarioId);
      expect(identidad!.estaVinculado, isTrue);
      expect(identidad.nombreEfectivo, 'ANA LOPEZ');
    });

    test('17. cambiar de Empleado deja la identidad del nuevo', () async {
      final primero = await empleadoFixture(nombres: 'JUAN', apellido: 'PEREZ', numero: 1);
      final segundo = await empleadoFixture(nombres: 'ANA', apellido: 'LOPEZ', numero: 2);
      final usuarioId = await cuentaVinculada(primero);

      await cambiarVinculo.ejecutar(usuarioId: usuarioId, empleadoIdNuevo: segundo, motivo: 'Corrección');

      final identidad = await usuarioRepo.obtenerConIdentidad(usuarioId);
      expect(identidad!.nombreEfectivo, 'ANA LOPEZ');
      // El historial de la cuenta no se pierde al cambiar de persona.
      final eventos = await usuarioRepo.listarEventos(usuarioId);
      expect(eventos.length, greaterThanOrEqualTo(2));
    });

    test('18. desvincular CONGELA la identidad efectiva del momento, no resucita la vieja', () async {
      final puesto = await puestoFixture(nombre: 'Gerente');
      final empleadoId = await empleadoFixture(nombres: 'ANA', apellido: 'LOPEZ', puestoId: puesto.id);
      final usuarioId = await cuentaVinculada(empleadoId);

      final r = await cambiarVinculo.ejecutar(usuarioId: usuarioId, empleadoIdNuevo: null, motivo: 'Ya no aplica');

      expect(r, isA<CambiarVinculoEmpleadoExitoso>());
      final identidad = await usuarioRepo.obtenerConIdentidad(usuarioId);
      expect(identidad!.estaVinculado, isFalse);
      expect(
        identidad.nombreEfectivo,
        'ANA LOPEZ',
        reason: 'la cuenta sigue llamándose igual; desvincular no puede renombrarla sola',
      );
      expect(identidad.nombrePuestoEfectivo, 'Gerente');
      expect(identidad.usuario.nombre, 'ANA LOPEZ', reason: 'quedó congelado como identidad propia');
    });

    test('el vínculo exige motivo, y sin él no escribe nada', () async {
      final empleadoId = await empleadoFixture();
      final usuarioId = await cuentaVinculada(empleadoId);

      final r = await cambiarVinculo.ejecutar(usuarioId: usuarioId, empleadoIdNuevo: null, motivo: '   ');

      expect(r, isA<CambiarVinculoEmpleadoMotivoRequerido>());
      final identidad = await usuarioRepo.obtenerConIdentidad(usuarioId);
      expect(identidad!.estaVinculado, isTrue, reason: 'no se tocó nada');
    });

    test('pedir el vínculo que ya está vigente no genera un evento vacío', () async {
      final empleadoId = await empleadoFixture();
      final usuarioId = await cuentaVinculada(empleadoId);
      final antes = (await usuarioRepo.listarEventos(usuarioId)).length;

      final r = await cambiarVinculo.ejecutar(usuarioId: usuarioId, empleadoIdNuevo: empleadoId, motivo: 'otra vez');

      expect(r, isA<CambiarVinculoEmpleadoSinCambio>());
      expect((await usuarioRepo.listarEventos(usuarioId)).length, antes);
    });
  });

  group('Auditoría del vínculo', () {
    test('19. vincular queda registrado con actor y con nombres legibles', () async {
      final puesto = await puestoFixture();
      final empleadoId = await empleadoFixture(nombres: 'ANA', apellido: 'LOPEZ');
      final actor = (await crearUsuario.ejecutar(
        nombre: 'MARLON',
        nombreUsuario: 'marlon',
        password: 'contrasena1',
        puestoId: puesto.id,
        esMaestro: true,
      ) as CrearUsuarioExitoso).usuario;
      final r0 = await crearUsuario.ejecutar(
        nombre: 'SUELTA',
        nombreUsuario: 'suelta',
        password: 'contrasena1',
        puestoId: puesto.id,
      );
      final usuarioId = (r0 as CrearUsuarioExitoso).usuario.id;

      await cambiarVinculo.ejecutar(
        usuarioId: usuarioId,
        empleadoIdNuevo: empleadoId,
        motivo: 'La cuenta es de Ana',
        actorUsuarioId: actor.id,
      );

      final evento = (await usuarioRepo.listarEventos(usuarioId)).last;
      expect(evento.tipoEvento, 'vinculoEmpleadoModificado');
      expect(evento.actorUsuarioId, actor.id, reason: 'el actor humano viaja explícito');
      expect(evento.observacion, 'La cuenta es de Ana');
      expect(evento.datosRelevantes, contains('ANA LOPEZ'), reason: 'el historial se lee sin resolver UUID');
    });

    test('20. desvincular queda registrado, con el Empleado anterior nombrado', () async {
      final empleadoId = await empleadoFixture(nombres: 'ANA', apellido: 'LOPEZ');
      final usuarioId = await cuentaVinculada(empleadoId);

      await cambiarVinculo.ejecutar(usuarioId: usuarioId, empleadoIdNuevo: null, motivo: 'Ya no aplica');

      final evento = (await usuarioRepo.listarEventos(usuarioId)).last;
      expect(evento.tipoEvento, 'vinculoEmpleadoModificado');
      expect(evento.datosRelevantes, contains('ANA LOPEZ'));
      expect(evento.datosRelevantes, contains('"empleadoIdNuevo":null'));
    });

    test('21. ningún evento del vínculo contiene información sensible', () async {
      final empleadoId = await empleadoFixture();
      final usuarioId = await cuentaVinculada(empleadoId);
      await cambiarVinculo.ejecutar(usuarioId: usuarioId, empleadoIdNuevo: null, motivo: 'prueba');

      final usuario = await usuarioRepo.obtenerPorId(usuarioId);
      for (final evento in await usuarioRepo.listarEventos(usuarioId)) {
        final texto = '${evento.datosRelevantes ?? ''}${evento.observacion ?? ''}';
        expect(texto, isNot(contains('contrasena1')), reason: 'la contraseña jamás llega a un evento');
        expect(texto, isNot(contains(usuario!.passwordHash)), reason: 'el hash tampoco');
        expect(texto, isNot(contains('pbkdf2')));
      }
    });
  });

}
