// Rebanada 3 — cierre de Telefonía.
//
// Fija los cuatro compromisos que no estaban cubiertos:
//   §1A  pendiente de recuperación NO es una inconsistencia;
//   §1B  la sincronización automática se distingue de un cambio manual
//        en la bitácora, y no equivale a un permiso de Telefonía;
//   §8/§9 el Egreso de una recarga se reconoce como de Telefonía, se
//        navega por FK real y deja de ser corregible desde Finanzas;
//   §14  el secreto de la credencial no sale sin su permiso.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_financiera_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_origen_automatico_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/inventario/domain/usecases/cambiar_responsable_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';
import 'package:riseg_one/features/reportes/domain/usecases/clasificar_egresos_por_origen_usecase.dart'
    show OrigenEgreso;
import 'package:riseg_one/features/reportes/reportes_providers.dart';
import 'package:riseg_one/features/telefonia/data/tables/asignacion_linea_telefonica_table.dart';
import 'package:riseg_one/features/telefonia/data/tables/linea_telefonica_table.dart';
import 'package:riseg_one/features/telefonia/domain/coherencia_linea_equipo.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/asociar_equipo_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/cambiar_asignacion_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/revelar_credencial_equipo_telefonico_usecase.dart';
import 'package:riseg_one/features/telefonia/telefonia_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/egresos_controller.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/cambiar_contrasena_equipo_telefonico_usecase.dart';
import 'package:riseg_one/core/security/credential_cipher.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/equipo_telefonico_repository_impl.dart';

const _mensajePermiso = 'No tiene permiso para realizar esta acción.';

class _AlmacenClaveEnMemoria implements AlmacenClaveCifrado {
  String? _clave;

  @override
  Future<String?> leer() async => _clave;

  @override
  Future<void> escribir(String valor) async => _clave = valor;
}

class _SesionFija extends SesionController {
  _SesionFija(this._sesion);
  final SesionUsuario? _sesion;

  @override
  SesionUsuario? build() => _sesion;
}

SesionUsuario _sesionCon(Set<String> permisos) => SesionUsuario(
      usuarioId: 'usuario-prueba',
      nombre: 'Usuario de prueba',
      nombreUsuario: 'prueba',
      esMaestro: false,
      permisos: permisos,
    );

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-prueba'),
            nombre: 'Usuario de prueba',
            nombreUsuario: 'usuario-prueba',
            passwordHash: 'x',
          ),
        );
  });

  tearDown(() => db.close());

  ProviderContainer contenedor(Set<String> permisos) {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(() => _SesionFija(_sesionCon(permisos))),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  // ---------------------------------------------------------------
  // Andamiaje mínimo, por los caminos reales.
  // ---------------------------------------------------------------
  Future<String> crearLinea(ProviderContainer c, {String numero = '7291220187'}) async {
    final linea = await c.read(lineaTelefonicaRepositoryProvider).crear(
          codigo: 'LIN-${numero.substring(numero.length - 4)}',
          numero: numero,
          operador: OperadorTelefonico.bait.name,
          modalidadSim: ModalidadSim.fisica.name,
        );
    return linea.id;
  }

  Future<EmpleadoData> crearEmpleado({int n = 1}) {
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: n,
            nombres: 'Juan',
            apellidoPaterno: 'Pérez',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX0$n',
            rfc: 'PEXJ900101AB$n',
            nss: '1234567890$n',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
  }

  Future<({String articuloId, String unidadId})> crearTelefono({String serie = 'SN-0001'}) async {
    final categoria =
        await db.into(db.categoriaArticulo).insertReturning(CategoriaArticuloCompanion.insert(nombre: 'Teléfonos'));
    final articulo = await db.into(db.articulo).insertReturning(
          ArticuloCompanion.insert(
            folio: 'ART-$serie',
            categoriaId: categoria.id,
            nombre: 'Smartphone',
            manejaSerie: const Value(true),
          ),
        );
    final unidad = await db.into(db.articuloUnidad).insertReturning(
          ArticuloUnidadCompanion.insert(articuloId: articulo.id, codigo: 'UNI-$serie', numeroSerie: serie),
        );
    await db.into(db.articuloUnidadTelefono).insert(
          ArticuloUnidadTelefonoCompanion.insert(unidadId: unidad.id, imei: const Value('351234567890123')),
        );
    return (articuloId: articulo.id, unidadId: unidad.id);
  }

  Future<String> crearCuenta(ProviderContainer c) async {
    final cuenta = await db.into(db.cuentaFinanciera).insertReturning(
          CuentaFinancieraCompanion.insert(
            codigo: 'CTA-0001',
            nombre: 'BBVA Empresarial',
            tipo: TipoCuentaFinanciera.banco.name,
            saldoInicial: 10000000,
            fechaSaldoInicial: DateTime(2026, 1, 1),
          ),
        );
    return cuenta.id;
  }

  // ===============================================================
  // §1A — pendiente de recuperación NO es una inconsistencia
  // ===============================================================
  group('§1A — pendiente de recuperación', () {
    test('la regla pura lo distingue de una inconsistencia, por la marca REAL de Inventario', () {
      const custodia = DestinoTelefonia.empleado('emp-1');

      final sinMarca = evaluarCoherenciaLineaEquipo(
        unidadId: 'uni-1',
        destinoLinea: null,
        destinoEquipo: custodia,
      );
      expect(sinMarca.estado, EstadoCoherenciaLineaEquipo.lineaSinAsignacion);
      expect(sinMarca.esInconsistencia, isTrue);
      expect(sinMarca.esPendienteRecuperacion, isFalse);

      final conMarca = evaluarCoherenciaLineaEquipo(
        unidadId: 'uni-1',
        destinoLinea: null,
        destinoEquipo: custodia,
        pendienteRecuperacionDesde: DateTime(2026, 6, 1),
      );
      expect(conMarca.estado, EstadoCoherenciaLineaEquipo.equipoPendienteRecuperacion);
      expect(conMarca.esPendienteRecuperacion, isTrue);
      expect(
        conMarca.esInconsistencia,
        isFalse,
        reason: 'dos ciclos de vida distintos avanzando bien no son un dato corrupto',
      );
    });

    test('resolverlo NO es una corrección: no se ofrece asignar la línea al ex-empleado', () {
      const custodia = DestinoTelefonia.empleado('emp-1');
      final cambio = evaluarCambioAsignacionLinea(
        unidadId: 'uni-1',
        destinoLineaActual: null,
        destinoEquipo: custodia,
        destinoPropuesto: custodia,
        pendienteRecuperacionDesde: DateTime(2026, 6, 1),
      );
      // `antes` es pendiente, no inconsistencia: reasignar la línea no
      // "corrige" nada y por tanto tampoco se trata como resolución.
      expect(cambio.esResolucionDeInconsistencia, isFalse);
    });

    test('un equipo pendiente de recuperación no puede empezar a traer una línea', () async {
      final c = contenedor({'telefonia.ver', 'telefonia.crear', 'telefonia.modificar', 'inventario.ver'});
      final lineaId = await crearLinea(c);
      final empleado = await crearEmpleado();
      final tel = await crearTelefono();

      final asignacion = await c.read(asignacionRepositoryProvider).crear(
            articuloId: tel.articuloId,
            unidadId: tel.unidadId,
            cantidad: 1,
            empleadoId: empleado.id,
            fechaEntrega: DateTime(2026, 1, 1),
          );
      await c.read(asignacionRepositoryProvider).marcarPendienteRecuperacion(
            asignacionId: asignacion.id,
            fecha: DateTime(2026, 6, 1),
          );

      final r = await c.read(asociarEquipoLineaTelefonicaUseCaseProvider).ejecutar(
            lineaTelefonicaId: lineaId,
            unidadId: tel.unidadId,
            fechaInicio: DateTime(2026, 7, 1),
            alinearLineaConCustodia: true,
          );

      expect(r, isA<AsociarEquipoLineaTelefonicaEquipoPendienteRecuperacion>());
      expect(await db.select(db.lineaTelefonicaEquipo).get(), isEmpty);
      expect(await db.select(db.asignacionLineaTelefonica).get(), isEmpty,
          reason: 'jamás se le asigna la línea a quien ya no trabaja aquí');
    });
  });

  // ===============================================================
  // §1B — la sincronización automática se distingue, y no es permiso
  // ===============================================================
  group('§1B — sincronización automática por Inventario', () {
    /// Teléfono entregado a [empleadoId] con su línea alineada, por el
    /// camino real.
    Future<({String lineaId, String asignacionId, String unidadId})> armar(
      ProviderContainer c,
      String empleadoId,
    ) async {
      final lineaId = await crearLinea(c);
      final tel = await crearTelefono();
      final asignacion = await c.read(asignacionRepositoryProvider).crear(
            articuloId: tel.articuloId,
            unidadId: tel.unidadId,
            cantidad: 1,
            empleadoId: empleadoId,
            fechaEntrega: DateTime(2026, 1, 1),
          );
      final asociado = await c.read(asociarEquipoLineaTelefonicaUseCaseProvider).ejecutar(
            lineaTelefonicaId: lineaId,
            unidadId: tel.unidadId,
            fechaInicio: DateTime(2026, 1, 2),
            alinearLineaConCustodia: true,
          );
      expect(asociado, isA<AsociarEquipoLineaTelefonicaExitoso>(), reason: '$asociado');
      return (lineaId: lineaId, asignacionId: asignacion.id, unidadId: tel.unidadId);
    }

    test('deja un asiento propio: actor, antes/después, equipo y la operación de Inventario que la causó', () async {
      final c = contenedor({'telefonia.ver', 'telefonia.crear', 'telefonia.modificar', 'inventario.ver', 'inventario.corregir'});
      final empleadoA = await crearEmpleado(n: 1);
      final empleadoB = await crearEmpleado(n: 2);
      final armado = await armar(c, empleadoA.id);

      final r = await c.read(cambiarResponsableAsignacionAutorizadoProvider)(
        asignacionId: armado.asignacionId,
        nuevoEmpleadoId: empleadoB.id,
        fecha: DateTime(2026, 5, 1),
      );
      expect(r, isA<CambiarResponsableAsignacionExitoso>(), reason: '$r');

      final eventos = await c.read(lineaTelefonicaRepositoryProvider).listarEventos(armado.lineaId);
      final sincronizacion = eventos
          .where((e) => e.tipoEvento == TipoEventoLineaTelefonica.asignacionSincronizadaPorInventario.name)
          .toList();
      expect(sincronizacion, hasLength(1));
      final evento = sincronizacion.single;
      expect(evento.actorUsuarioId, 'usuario-prueba', reason: 'el actor causante queda registrado');
      expect(evento.fechaHora, DateTime(2026, 5, 1));
      expect(evento.estadoAnterior, contains(empleadoA.id));
      expect(evento.estadoNuevo, contains(empleadoB.id));
      expect(evento.estadoNuevo, contains(armado.unidadId), reason: 'el equipo involucrado');
      expect(evento.estadoNuevo, contains('origenAsignacionInventario'),
          reason: 'la operación de Inventario que la causó, por id real');
      expect(evento.observacion, contains('automáticamente'));

      // Y el cierre del periodo anterior no se confunde con un cambio
      // hecho a mano.
      final cerrada = (await c.read(asignacionLineaTelefonicaRepositoryProvider).listarPorLinea(armado.lineaId))
          .firstWhere((a) => a.fechaTermino != null);
      expect(cerrada.motivoTermino, MotivoTerminoAsignacionLineaTelefonica.sincronizacionCustodiaInventario.name);
    });

    test('un cambio MANUAL de línea no produce ese asiento — así se distinguen', () async {
      final c = contenedor({'telefonia.ver', 'telefonia.crear', 'telefonia.modificar', 'inventario.ver'});
      final lineaId = await crearLinea(c);
      final empleadoA = await crearEmpleado(n: 1);
      final empleadoB = await crearEmpleado(n: 2);
      final vigente = await c.read(asignacionLineaTelefonicaRepositoryProvider).crear(
            lineaTelefonicaId: lineaId,
            empleadoId: empleadoA.id,
            fechaInicio: DateTime(2026, 1, 1),
          );

      final r = await c.read(cambiarAsignacionLineaTelefonicaAutorizadoProvider)(
        asignacionLineaTelefonicaActualId: vigente.id,
        fecha: DateTime(2026, 5, 1),
        nuevoEmpleadoId: empleadoB.id,
      );
      expect(r, isA<CambiarAsignacionLineaTelefonicaExitoso>(), reason: '$r');

      final eventos = await c.read(lineaTelefonicaRepositoryProvider).listarEventos(lineaId);
      expect(
        eventos.where((e) => e.tipoEvento == TipoEventoLineaTelefonica.asignacionSincronizadaPorInventario.name),
        isEmpty,
      );
      final cerrada = (await c.read(asignacionLineaTelefonicaRepositoryProvider).listarPorLinea(lineaId))
          .firstWhere((a) => a.fechaTermino != null);
      expect(cerrada.motivoTermino, MotivoTerminoAsignacionLineaTelefonica.cambioResponsable.name);
    });

    test('permiso de Inventario NO concede capacidad manual sobre Telefonía', () async {
      final soloInventario = contenedor({'inventario.ver', 'inventario.corregir', 'telefonia.ver'});
      final maestroDeDatos =
          contenedor({'telefonia.ver', 'telefonia.crear', 'telefonia.modificar', 'inventario.ver'});

      final empleadoA = await crearEmpleado(n: 1);
      final empleadoB = await crearEmpleado(n: 2);
      final armado = await armar(maestroDeDatos, empleadoA.id);

      // 1. Por la fachada de Telefonía: denegado, y nada se mueve.
      final vigenteAntes =
          (await soloInventario.read(asignacionLineaTelefonicaRepositoryProvider).obtenerActivaPorLinea(armado.lineaId))!;
      final manual = await soloInventario.read(cambiarAsignacionLineaTelefonicaAutorizadoProvider)(
        asignacionLineaTelefonicaActualId: vigenteAntes.id,
        fecha: DateTime(2026, 5, 1),
        nuevoEmpleadoId: empleadoB.id,
      );
      expect(manual, isA<CambiarAsignacionLineaTelefonicaErrorInesperado>());
      expect((manual as CambiarAsignacionLineaTelefonicaErrorInesperado).mensaje, _mensajePermiso);
      expect(
        (await soloInventario.read(asignacionLineaTelefonicaRepositoryProvider).obtenerActivaPorLinea(armado.lineaId))!.id,
        vigenteAntes.id,
        reason: 'sin telefonia.modificar la línea no se toca a mano',
      );

      // 2. Por su propia operación autorizada de Inventario: sí, y la
      //    línea sigue a la custodia como consecuencia sistémica.
      final transferencia = await soloInventario.read(cambiarResponsableAsignacionAutorizadoProvider)(
        asignacionId: armado.asignacionId,
        nuevoEmpleadoId: empleadoB.id,
        fecha: DateTime(2026, 5, 1),
      );
      expect(transferencia, isA<CambiarResponsableAsignacionExitoso>(), reason: '$transferencia');

      final vigenteDespues =
          (await soloInventario.read(asignacionLineaTelefonicaRepositoryProvider).obtenerActivaPorLinea(armado.lineaId))!;
      expect(vigenteDespues.empleadoId, empleadoB.id);

      // 3. Y la bitácora dice que fue automática, no manual.
      final eventos = await soloInventario.read(lineaTelefonicaRepositoryProvider).listarEventos(armado.lineaId);
      expect(
        eventos.map((e) => e.tipoEvento),
        contains(TipoEventoLineaTelefonica.asignacionSincronizadaPorInventario.name),
      );
    });
  });

  // ===============================================================
  // §8 / §9 — el Egreso de una recarga
  // ===============================================================
  group('§8/§9 — recarga y Finanzas', () {
    Future<({String lineaId, String recargaId, String egresoId})> recargarDesdeCuenta(ProviderContainer c) async {
      final lineaId = await crearLinea(c);
      final cuentaId = await crearCuenta(c);
      final recarga = await c.read(recargaLineaTelefonicaRepositoryProvider).registrar(
            lineaTelefonicaId: lineaId,
            fecha: DateTime(2026, 3, 1),
            importe: 20000,
            formaPago: FormaPago.transferencia.name,
            cuentaFinancieraId: cuentaId,
          );
      return (lineaId: lineaId, recargaId: recarga.id, egresoId: recarga.egresoId!);
    }

    test('se clasifica como Telefonía, nunca como Manual', () async {
      final c = contenedor({'telefonia.ver', 'telefonia.recargar', 'finanzas.ver'});
      final r = await recargarDesdeCuenta(c);

      final clasificado = await c.read(clasificarEgresosPorOrigenUseCaseProvider).ejecutar();
      final detalle = clasificado.detalle.firstWhere((e) => e.egreso.id == r.egresoId);
      expect(detalle.origen, OrigenEgreso.telefonia);
      expect(clasificado.totalManual, 0, reason: 'un Egreso automático nunca es manual');
      expect(clasificado.totalTelefonia, 20000);
    });

    test('su origen automático apunta a la línea por FK real, nunca por concepto ni importe', () async {
      final c = contenedor({'telefonia.ver', 'telefonia.recargar', 'finanzas.ver'});
      final r = await recargarDesdeCuenta(c);

      final origen = await c.read(obtenerOrigenAutomaticoEgresoUseCaseProvider).ejecutar(r.egresoId);
      expect(origen, isA<OrigenAutomaticoEgresoTelefonia>());
      final telefonia = origen! as OrigenAutomaticoEgresoTelefonia;
      expect(telefonia.lineaTelefonicaId, r.lineaId);
      expect(telefonia.recargaLineaTelefonicaId, r.recargaId);
      expect(telefonia.folio, startsWith('LIN-'), reason: 'el código de la línea, nunca su número');

      // Y a la inversa: del Egreso a la recarga, también por FK.
      final recarga = await c.read(recargaLineaTelefonicaRepositoryProvider).obtenerPorEgresoId(r.egresoId);
      expect(recarga!.id, r.recargaId);
    });

    test('deja de ser corregible y cancelable desde Finanzas: se resuelve desde Telefonía', () async {
      final c = contenedor({'telefonia.ver', 'telefonia.recargar', 'finanzas.ver', 'egresos.corregir', 'egresos.cancelar'});
      final r = await recargarDesdeCuenta(c);

      final notifier = c.read(egresosControllerProvider.notifier);
      final corregido = await notifier.corregir(
        egresoId: r.egresoId,
        monto: 50000,
        motivo: 'Intento indebido desde Finanzas',
      );
      expect(corregido, isA<CorregirEgresoOrigenAutomatico>());

      final cancelado = await notifier.cancelar(
        egresoId: r.egresoId,
        motivo: 'Intento indebido desde Finanzas',
      );
      expect(cancelado, isA<CancelarEgresoOrigenAutomatico>());

      final egreso = (await db.select(db.egreso).get()).single;
      expect(egreso.monto, 20000, reason: 'el Egreso de la recarga no se tocó');
    });
  });

  // ===============================================================
  // §14 — el secreto de la credencial
  // ===============================================================
  group('§14 — credenciales', () {
    // El cifrador real guarda su clave en el almacén seguro del SO, que
    // no responde bajo `flutter test`. Se inyecta uno en memoria — el
    // MISMO patrón de `equipo_telefonico_test.dart`.
    Future<String> equipoConCredencial(CredentialCipher cipher) async {
      final tel = await crearTelefono();
      final repo = EquipoTelefonicoRepositoryImpl(db);
      final cambio = await CambiarContrasenaEquipoTelefonicoUseCase(
        InventarioRepositoryImpl(db),
        repo,
        cipher,
      ).ejecutar(unidadId: tel.unidadId, contrasena: 'SuperSecreta123');
      expect(cambio, isA<CambiarContrasenaEquipoTelefonicoExitoso>(), reason: '$cambio');
      return tel.unidadId;
    }

    test('sin telefonia.verCredenciales el secreto no sale: la fachada deniega antes de descifrar', () async {
      final cipher = CredentialCipher(almacen: _AlmacenClaveEnMemoria());
      final unidadId = await equipoConCredencial(cipher);

      final sinPermiso = contenedor({'telefonia.ver', 'telefonia.modificar'});
      final r = await sinPermiso.read(revelarCredencialEquipoTelefonicoAutorizadoProvider)(
        unidadId: unidadId,
        accion: AccionRevelacionCredencial.mostrar,
      );
      expect(r, isA<RevelarCredencialEquipoTelefonicoErrorInesperado>());
      expect((r as RevelarCredencialEquipoTelefonicoErrorInesperado).mensaje, _mensajePermiso);
    });

    test('lo que se guarda y lo que se proyecta a la UI es el cifrado, nunca el texto', () async {
      final cipher = CredentialCipher(almacen: _AlmacenClaveEnMemoria());
      final unidadId = await equipoConCredencial(cipher);

      final credencial = await EquipoTelefonicoRepositoryImpl(db).obtenerCredencial(unidadId);
      expect(credencial!.contrasenaCifrada, isNot(contains('SuperSecreta123')));
      expect(credencial.contrasenaCifrada, startsWith(r'aesgcm$'));

      // Ni en la bitácora del equipo, que es lo que llega a Auditoría.
      final eventos = await db.select(db.equipoTelefonicoEvento).get();
      expect(eventos, isNotEmpty);
      for (final e in eventos) {
        expect(e.observacion ?? '', isNot(contains('SuperSecreta123')));
      }
      // Y la tabla de eventos ni siquiera tiene dónde guardarlo: su
      // única columna de texto libre es `observacion`.
    });

    test('con la clave correcta el secreto sí se revela — la guardia no es un muro ciego', () async {
      final cipher = CredentialCipher(almacen: _AlmacenClaveEnMemoria());
      final unidadId = await equipoConCredencial(cipher);

      final r = await RevelarCredencialEquipoTelefonicoUseCase(
        InventarioRepositoryImpl(db),
        EquipoTelefonicoRepositoryImpl(db),
        cipher,
      ).ejecutar(unidadId: unidadId, accion: AccionRevelacionCredencial.mostrar);
      expect(r, isA<RevelarCredencialEquipoTelefonicoExitoso>(), reason: '$r');
      expect((r as RevelarCredencialEquipoTelefonicoExitoso).contrasena, 'SuperSecreta123');
    });
  });

  // ===============================================================
  // §23 — regresión financiera: la UX no rompió la Rebanada 1
  // ===============================================================
  group('§23 — invariantes financieras', () {
    test('Cuenta → exactamente UN Egreso; cancelar lo revierte una vez', () async {
      final c = contenedor({'telefonia.ver', 'telefonia.recargar', 'finanzas.ver'});
      final lineaId = await crearLinea(c);
      final cuentaId = await crearCuenta(c);
      final repo = c.read(recargaLineaTelefonicaRepositoryProvider);

      final recarga = await repo.registrar(
        lineaTelefonicaId: lineaId,
        fecha: DateTime(2026, 3, 1),
        importe: 20000,
        formaPago: FormaPago.transferencia.name,
        cuentaFinancieraId: cuentaId,
      );
      expect(await db.select(db.egreso).get(), hasLength(1));
      expect(await db.select(db.movimientoDeuda).get(), isEmpty);

      await repo.cancelar(recargaLineaTelefonicaId: recarga.id, motivo: 'Duplicada');
      final egresos = await db.select(db.egreso).get();
      expect(egresos, hasLength(1), reason: 'se cancela el mismo, no se crea otro');
      expect(egresos.single.estatus, 'cancelado');
      expect(await repo.totalPorLinea(lineaId), 0);
    });

    test('una recarga legacy sin origen no adquiere cuenta al mostrarse', () async {
      final c = contenedor({'telefonia.ver', 'finanzas.ver'});
      final lineaId = await crearLinea(c);
      await db.into(db.recargaLineaTelefonica).insert(
            RecargaLineaTelefonicaCompanion.insert(
              lineaTelefonicaId: lineaId,
              fecha: DateTime(2025, 12, 1),
              importe: 20000,
            ),
          );

      final historial = await c.read(recargaLineaTelefonicaRepositoryProvider).listarPorLinea(lineaId);
      expect(historial.single.egresoId, isNull);
      expect(historial.single.deudaId, isNull);
      expect(historial.single.formaPago, isNull);
      expect(await db.select(db.egreso).get(), isEmpty);
    });
  });
}
