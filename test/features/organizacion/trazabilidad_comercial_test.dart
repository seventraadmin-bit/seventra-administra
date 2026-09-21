// Trazabilidad de Comercial — Cliente, Entidad fiscal y Servicio.
//
// Hueco que cierra: hasta ahora, TODO el bloque Comercial podía cambiar
// sin dejar rastro. Corregir la razón social de una Entidad fiscal,
// terminar un Servicio o suspender a un Cliente no registraban ni quién,
// ni cuándo, ni por qué, ni qué había antes. Lo único auditado del área
// era la Agenda de documentos y la eliminación física.
//
// Lo que estas pruebas protegen:
//   1. actor + motivo + diff en cada operación sensible;
//   2. el diff trae SÓLO los campos que cambiaron, nunca el registro;
//   3. un alta no exige motivo — no hay nada que justificar todavía;
//   4. Auditoría central los proyecta con su módulo y acción correctos;
//   5. cada acción deja UN evento, nunca tres copias del mismo hecho.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/cliente_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/comercial_evento_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_ciclo_vida_entidad_fiscal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_entidad_fiscal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cliente_expediente_input.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_entidad_fiscal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/entidad_fiscal_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_entidad_fiscal_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_expediente_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/usuarios/data/repositories/auditoria_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/buscar_auditoria_usecase.dart';
import 'package:riseg_one/app/shell/shell_permissions.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/destino_auditoria.dart';

const _actor = 'usuario-auditor';

void main() {
  late AppDatabase db;
  late ClienteRepositoryImpl clienteRepo;
  late EntidadFiscalRepositoryImpl entidadFiscalRepo;
  late ServicioRepositoryImpl servicioRepo;
  late AuditoriaRepositoryImpl auditoriaRepo;

  late CambiarEstatusClienteUseCase cambiarEstatusCliente;
  late GuardarExpedienteClienteUseCase guardarExpedienteCliente;
  late CrearEntidadFiscalUseCase crearEntidadFiscal;
  late ActualizarEntidadFiscalUseCase actualizarEntidadFiscal;
  late CambiarCicloVidaEntidadFiscalUseCase cambiarCicloVidaEntidadFiscal;
  late ActualizarServicioUseCase actualizarServicio;
  late CambiarEstatusServicioUseCase cambiarEstatusServicio;

  var consecutivo = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value(_actor),
            nombre: 'Auditor de prueba',
            nombreUsuario: 'auditor',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );

    clienteRepo = ClienteRepositoryImpl(db);
    entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    auditoriaRepo = AuditoriaRepositoryImpl(db);

    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    cambiarEstatusCliente = CambiarEstatusClienteUseCase(clienteRepo);
    guardarExpedienteCliente = GuardarExpedienteClienteUseCase(clienteRepo);
    final validadorFiscal = EntidadFiscalValidator(clienteRepo, entidadFiscalRepo);
    crearEntidadFiscal = CrearEntidadFiscalUseCase(entidadFiscalRepo, generarCodigo, validadorFiscal);
    actualizarEntidadFiscal = ActualizarEntidadFiscalUseCase(entidadFiscalRepo, validadorFiscal);
    cambiarCicloVidaEntidadFiscal = CambiarCicloVidaEntidadFiscalUseCase(entidadFiscalRepo);
    actualizarServicio = ActualizarServicioUseCase(servicioRepo, ServicioValidator(clienteRepo, CatalogoRepositoryImpl(db)));
    cambiarEstatusServicio = CambiarEstatusServicioUseCase(servicioRepo, clienteRepo);
    consecutivo = 0;
  });

  tearDown(() => db.close());

  Future<ClienteData> crearCliente({String nombre = 'Sportium'}) {
    final n = (++consecutivo).toString().padLeft(6, '0');
    return clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-$n', nombreComercial: nombre));
  }

  Future<ServicioData> crearServicio(String clienteId, {String nombre = 'Vigilancia Satélite'}) async {
    final n = (++consecutivo).toString().padLeft(6, '0');
    return servicioRepo.crear(
      codigoServicio: 'SRV-$n',
      clienteId: clienteId,
      nombre: nombre,
      tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
      fechaInicio: DateTime(2026, 1, 1),
      codigoUbicacionRaiz: 'UBI-$n',
    );
  }

  Future<List<ClienteEventoData>> eventosDeCliente(String clienteId) {
    return (db.select(db.clienteEvento)..where((t) => t.clienteId.equals(clienteId))).get();
  }

  Future<List<ServicioEventoData>> eventosDeServicio(String servicioId) {
    return (db.select(db.servicioEvento)..where((t) => t.servicioId.equals(servicioId))).get();
  }

  Map<String, dynamic> json(String? texto) => jsonDecode(texto!) as Map<String, dynamic>;

  group('Cliente', () {
    test('corregir el nombre deja actor, motivo y un diff con SÓLO ese campo', () async {
      final cliente = await crearCliente(nombre: 'Sportium');

      final resultado = await guardarExpedienteCliente.ejecutar(
        clienteId: cliente.id,
        input: const ClienteExpedienteInput(
          datosGenerales: ClienteDatosGeneralesInput(nombreComercial: 'Sportium Satélite'),
        ),
        motivo: 'El cliente cambió su nombre comercial',
        actorUsuarioId: _actor,
      );
      expect(resultado, isA<GuardarExpedienteClienteExitoso>());

      final eventos = await eventosDeCliente(cliente.id);
      expect(eventos, hasLength(1), reason: 'una corrección deja UN evento, no tres copias');

      final evento = eventos.single;
      expect(evento.tipoEvento, TipoEventoCliente.corregido.name);
      expect(evento.actorUsuarioId, _actor);
      expect(evento.observacion, 'El cliente cambió su nombre comercial');
      expect(evento.fechaHora, isNotNull);

      expect(json(evento.estadoAnterior), {'nombreComercial': 'Sportium'});
      expect(json(evento.estadoNuevo), {'nombreComercial': 'Sportium Satélite'});
      expect(json(evento.estadoNuevo).keys, hasLength(1), reason: 'nunca un snapshot del registro completo');
    });

    test('sin motivo no se corrige nada, y no queda evento', () async {
      final cliente = await crearCliente();

      final resultado = await guardarExpedienteCliente.ejecutar(
        clienteId: cliente.id,
        input: const ClienteExpedienteInput(
          datosGenerales: ClienteDatosGeneralesInput(nombreComercial: 'Otro nombre'),
        ),
        motivo: '   ',
        actorUsuarioId: _actor,
      );

      expect(resultado, isA<GuardarExpedienteClienteMotivoRequerido>());
      expect(await eventosDeCliente(cliente.id), isEmpty);
      final recargado = await clienteRepo.obtenerPorId(cliente.id);
      expect(recargado!.nombreComercial, 'Sportium', reason: 'ni se persistió el cambio');
    });

    test('cambiar el estatus registra la transición con su motivo', () async {
      final cliente = await crearCliente();

      final resultado = await cambiarEstatusCliente.ejecutar(
        clienteId: cliente.id,
        nuevo: EstatusCliente.suspendido,
        motivo: 'Adeudo vencido a 90 días',
        actorUsuarioId: _actor,
      );
      expect(resultado, isA<CambiarEstatusClienteExitoso>());

      final evento = (await eventosDeCliente(cliente.id)).single;
      expect(evento.tipoEvento, TipoEventoCliente.estatusCambiado.name);
      expect(evento.observacion, 'Adeudo vencido a 90 días');
      expect(json(evento.estadoAnterior)['estatus'], EstatusCliente.prospecto.name);
      expect(json(evento.estadoNuevo)['estatus'], EstatusCliente.suspendido.name);
    });

    test('una corrección que no cambia nada no inventa un evento', () async {
      final cliente = await crearCliente(nombre: 'Sportium');

      await guardarExpedienteCliente.ejecutar(
        clienteId: cliente.id,
        input: const ClienteExpedienteInput(
          datosGenerales: ClienteDatosGeneralesInput(nombreComercial: 'Sportium'),
        ),
        motivo: 'Revisión sin cambios',
        actorUsuarioId: _actor,
      );

      expect(await eventosDeCliente(cliente.id), isEmpty,
          reason: 'una "corrección" sin ningún campo modificado no es una corrección');
    });
  });

  group('Entidad fiscal', () {
    Future<EntidadFiscalData> crearEntidad(String clienteId) async {
      final resultado = await crearEntidadFiscal.ejecutar(
        clienteId: clienteId,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium SA de CV', rfc: 'SPO010101AB1'),
        actorUsuarioId: _actor,
      );
      return (resultado as GuardarEntidadFiscalExitoso).entidadFiscal;
    }

    test('el alta queda registrada con actor, y SIN motivo', () async {
      final cliente = await crearCliente();
      await crearEntidad(cliente.id);

      final evento = (await eventosDeCliente(cliente.id)).single;
      expect(evento.tipoEvento, TipoEventoCliente.entidadFiscalCreada.name);
      expect(evento.actorUsuarioId, _actor);
      expect(evento.observacion, isNull, reason: 'un alta no tiene nada que justificar');
      expect(json(evento.datosRelevantes)['rfc'], 'SPO010101AB1');
    });

    test('corregir razón social y RFC deja el diff exacto de ambos', () async {
      final cliente = await crearCliente();
      final entidad = await crearEntidad(cliente.id);

      final resultado = await actualizarEntidadFiscal.ejecutar(
        id: entidad.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium Toluca SA de CV', rfc: 'STO020202CD2'),
        motivo: 'Actualización de constancia de situación fiscal',
        actorUsuarioId: _actor,
      );
      expect(resultado, isA<GuardarEntidadFiscalExitoso>());

      final correccion = (await eventosDeCliente(cliente.id))
          .firstWhere((e) => e.tipoEvento == TipoEventoCliente.entidadFiscalCorregida.name);

      expect(correccion.actorUsuarioId, _actor);
      expect(correccion.observacion, 'Actualización de constancia de situación fiscal');
      expect(json(correccion.estadoAnterior), {'razonSocial': 'Sportium SA de CV', 'rfc': 'SPO010101AB1'});
      expect(json(correccion.estadoNuevo), {'razonSocial': 'Sportium Toluca SA de CV', 'rfc': 'STO020202CD2'});
      // El sub-registro concreto viaja en el evento: la bitácora cuelga
      // del Cliente, pero se sabe de cuál de sus entidades habla.
      expect(json(correccion.datosRelevantes)['entidadFiscalId'], entidad.id);
    });

    test('corregir el RFC NO reescribe los documentos ya emitidos con esa entidad', () async {
      final cliente = await crearCliente();
      final entidad = await crearEntidad(cliente.id);

      final documento = await db.into(db.documentoPorEmitir).insertReturning(
            DocumentoPorEmitirCompanion.insert(
              codigo: 'DOC-000001',
              clienteId: cliente.id,
              entidadFiscalId: Value(entidad.id),
              tipoDocumento: 'cfdi',
              agrupacion: 'porServicio',
              metodo: 'pue',
              periodoInicio: DateTime(2026, 1, 1),
              periodoFin: DateTime(2026, 1, 31),
              generationKey: 'GEN-1',
              importeBaseEsperado: 100000,
              importeFinalEsperado: 100000,
            ),
          );

      await actualizarEntidadFiscal.ejecutar(
        id: entidad.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Razón nueva SA', rfc: 'RNU030303EF3'),
        motivo: 'Corrección de RFC',
        actorUsuarioId: _actor,
      );

      final recargado = await (db.select(db.documentoPorEmitir)..where((t) => t.id.equals(documento.id))).getSingle();
      expect(recargado.importeFinalEsperado, documento.importeFinalEsperado);
      expect(recargado.entidadFiscalId, entidad.id, reason: 'el documento sigue apuntando a la MISMA entidad');
      // Y el valor anterior del RFC no se perdió: vive en el diff.
      final correccion = (await eventosDeCliente(cliente.id))
          .firstWhere((e) => e.tipoEvento == TipoEventoCliente.entidadFiscalCorregida.name);
      expect(json(correccion.estadoAnterior)['rfc'], 'SPO010101AB1');
    });

    test('archivar y reactivar quedan registrados con su motivo', () async {
      final cliente = await crearCliente();
      final entidad = await crearEntidad(cliente.id);

      await cambiarCicloVidaEntidadFiscal.ejecutar(
        entidadFiscalId: entidad.id,
        nuevo: CicloVidaRegistro.archivado,
        motivo: 'Entidad sin operaciones desde 2025',
        actorUsuarioId: _actor,
      );
      await cambiarCicloVidaEntidadFiscal.ejecutar(
        entidadFiscalId: entidad.id,
        nuevo: CicloVidaRegistro.activo,
        motivo: 'Se reanuda la facturación',
        actorUsuarioId: _actor,
      );

      final cicloVida = (await eventosDeCliente(cliente.id))
          .where((e) => e.tipoEvento == TipoEventoCliente.entidadFiscalCicloVidaCambiado.name)
          .toList();

      expect(cicloVida, hasLength(2));
      expect(json(cicloVida.first.estadoNuevo)['cicloVidaRegistro'], 'archivado');
      expect(cicloVida.first.observacion, 'Entidad sin operaciones desde 2025');
      expect(json(cicloVida.last.estadoNuevo)['cicloVidaRegistro'], 'activo');
      expect(cicloVida.last.observacion, 'Se reanuda la facturación');
    });

    test('sin motivo no se corrige el dato fiscal', () async {
      final cliente = await crearCliente();
      final entidad = await crearEntidad(cliente.id);

      final resultado = await actualizarEntidadFiscal.ejecutar(
        id: entidad.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Otra SA', rfc: 'OTR040404GH4'),
        motivo: '',
        actorUsuarioId: _actor,
      );

      expect(resultado, isA<GuardarEntidadFiscalMotivoRequerido>());
      final recargada = await entidadFiscalRepo.obtenerPorId(entidad.id);
      expect(recargada!.rfc, 'SPO010101AB1', reason: 'el RFC no se tocó');
    });
  });

  group('Servicio', () {
    test('corregir datos deja actor, motivo y diff', () async {
      final cliente = await crearCliente();
      final servicio = await crearServicio(cliente.id);

      final resultado = await actualizarServicio.ejecutar(
        id: servicio.id,
        borrador: ServicioBorrador(
          nombre: 'Vigilancia Satélite ampliada',
          tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
          fechaInicio: DateTime(2026, 1, 1),
        ),
        motivo: 'Se amplió el alcance del servicio',
        actorUsuarioId: _actor,
      );
      expect(resultado, isA<GuardarServicioExitoso>());

      final evento = (await eventosDeServicio(servicio.id)).single;
      expect(evento.tipoEvento, TipoEventoServicio.corregido.name);
      expect(evento.actorUsuarioId, _actor);
      expect(evento.observacion, 'Se amplió el alcance del servicio');
      expect(json(evento.estadoAnterior)['nombre'], 'Vigilancia Satélite');
      expect(json(evento.estadoNuevo)['nombre'], 'Vigilancia Satélite ampliada');
    });

    test('suspender y terminar quedan registrados, con la fecha de término en el diff', () async {
      final cliente = await crearCliente();
      await clienteRepo.cambiarEstatus(id: cliente.id, nuevo: EstatusCliente.activo, motivo: 'Alta', actorUsuarioId: _actor);
      final servicio = await crearServicio(cliente.id);

      await cambiarEstatusServicio.ejecutar(
        servicioId: servicio.id,
        nuevo: EstatusServicio.suspendido,
        motivo: 'Suspensión temporal solicitada por el cliente',
        actorUsuarioId: _actor,
      );
      await cambiarEstatusServicio.ejecutar(
        servicioId: servicio.id,
        nuevo: EstatusServicio.terminado,
        fechaTerminoEfectiva: DateTime(2026, 6, 30),
        motivo: 'Fin de contrato',
        actorUsuarioId: _actor,
      );

      final eventos = (await eventosDeServicio(servicio.id))
          .where((e) => e.tipoEvento == TipoEventoServicio.estatusCambiado.name)
          .toList();

      expect(eventos, hasLength(2));
      expect(eventos.first.observacion, 'Suspensión temporal solicitada por el cliente');
      expect(json(eventos.first.estadoNuevo)['estatus'], 'suspendido');
      expect(eventos.last.observacion, 'Fin de contrato');
      expect(json(eventos.last.estadoNuevo)['estatus'], 'terminado');
      expect(json(eventos.last.estadoNuevo)['fechaTermino'], DateTime(2026, 6, 30).toIso8601String());
    });

    test('sin motivo no se cambia el estatus', () async {
      final cliente = await crearCliente();
      final servicio = await crearServicio(cliente.id);

      final resultado = await cambiarEstatusServicio.ejecutar(
        servicioId: servicio.id,
        nuevo: EstatusServicio.suspendido,
        motivo: '  ',
        actorUsuarioId: _actor,
      );

      expect(resultado, isA<CambiarEstatusServicioMotivoRequerido>());
      expect(await eventosDeServicio(servicio.id), isEmpty);
      final recargado = await servicioRepo.obtenerPorId(servicio.id);
      expect(recargado!.estatus, EstatusServicio.cotizado.name);
    });
  });

  group('Auditoría central', () {
    test('proyecta los eventos de Comercial con su módulo, acción, actor, motivo y diff', () async {
      final cliente = await crearCliente(nombre: 'Sportium');
      final servicio = await crearServicio(cliente.id);

      await cambiarEstatusCliente.ejecutar(
        clienteId: cliente.id,
        nuevo: EstatusCliente.activo,
        motivo: 'Contrato firmado',
        actorUsuarioId: _actor,
      );
      await actualizarServicio.ejecutar(
        id: servicio.id,
        borrador: ServicioBorrador(
          nombre: 'Vigilancia Satélite II',
          tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
          fechaInicio: DateTime(2026, 1, 1),
        ),
        motivo: 'Renombrado por el cliente',
        actorUsuarioId: _actor,
      );

      final eventos = await BuscarAuditoriaUseCase(auditoriaRepo).ejecutar(const FiltroAuditoria());

      final delCliente = eventos.firstWhere((e) => e.modulo == 'clientes');
      expect(delCliente.accion, TipoEventoCliente.estatusCambiado.name);
      expect(delCliente.registroId, cliente.id);
      expect(delCliente.actorUsuarioId, _actor);
      expect(delCliente.motivo, 'Contrato firmado');
      expect(delCliente.entidadEtiqueta, 'Sportium', reason: 'contexto vivo, para saber de quién habla la fila');
      expect(delCliente.cambios.map((c) => c.campo), contains('estatus'));
      expect(delCliente.cambios.firstWhere((c) => c.campo == 'estatus').antes, EstatusCliente.prospecto.name);

      final delServicio = eventos.firstWhere((e) => e.modulo == 'servicios');
      expect(delServicio.accion, TipoEventoServicio.corregido.name);
      expect(delServicio.registroId, servicio.id);
      expect(delServicio.motivo, 'Renombrado por el cliente');
      expect(delServicio.cambios.map((c) => c.campo), contains('nombre'));
    });

    test('el filtro por módulo separa Clientes de Servicios', () async {
      final cliente = await crearCliente();
      final servicio = await crearServicio(cliente.id);
      await cambiarEstatusCliente.ejecutar(
        clienteId: cliente.id,
        nuevo: EstatusCliente.activo,
        motivo: 'Contrato firmado',
        actorUsuarioId: _actor,
      );
      await actualizarServicio.ejecutar(
        id: servicio.id,
        borrador: ServicioBorrador(
          nombre: 'Otro nombre',
          tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
          fechaInicio: DateTime(2026, 1, 1),
        ),
        motivo: 'Renombrado',
        actorUsuarioId: _actor,
      );

      final buscar = BuscarAuditoriaUseCase(auditoriaRepo);
      final soloClientes = await buscar.ejecutar(const FiltroAuditoria(modulo: 'clientes'));
      final soloServicios = await buscar.ejecutar(const FiltroAuditoria(modulo: 'servicios'));

      expect(soloClientes, hasLength(1));
      expect(soloClientes.single.registroId, cliente.id);
      expect(soloServicios, hasLength(1));
      expect(soloServicios.single.registroId, servicio.id);
    });

    test('la navegación lleva al expediente real, por id, y bajo el permiso del módulo origen', () async {
      final cliente = await crearCliente();
      await cambiarEstatusCliente.ejecutar(
        clienteId: cliente.id,
        nuevo: EstatusCliente.activo,
        motivo: 'Contrato firmado',
        actorUsuarioId: _actor,
      );

      final evento = (await BuscarAuditoriaUseCase(auditoriaRepo).ejecutar(const FiltroAuditoria())).single;
      final destino = destinoDeEvento(evento);

      expect(destino, isNotNull);
      expect(destino!.ruta, '/comercial/clientes/${cliente.id}');
      expect(destino.exigeMaestro, isFalse);
      // `auditoria.ver` deja ver QUE pasó; abrir el expediente lo sigue
      // decidiendo el permiso del módulo de origen.
      expect(permisosQueAbrenRuta(destino.ruta), ['comercial.ver']);
    });

    test('con volumen, el número de consultas NO crece con el número de eventos', () async {
      // 20 clientes y 20 servicios, cada uno con su corrección.
      for (var i = 0; i < 20; i++) {
        final cliente = await crearCliente(nombre: 'Cliente $i');
        final servicio = await crearServicio(cliente.id, nombre: 'Servicio $i');
        await cambiarEstatusCliente.ejecutar(
          clienteId: cliente.id,
          nuevo: EstatusCliente.activo,
          motivo: 'Contrato $i',
          actorUsuarioId: _actor,
        );
        await actualizarServicio.ejecutar(
          id: servicio.id,
          borrador: ServicioBorrador(
            nombre: 'Servicio $i renombrado',
            tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
            fechaInicio: DateTime(2026, 1, 1),
          ),
          motivo: 'Renombrado $i',
          actorUsuarioId: _actor,
        );
      }

      final eventos = await BuscarAuditoriaUseCase(auditoriaRepo).ejecutar(const FiltroAuditoria());
      final comerciales = eventos.where((e) => e.modulo == 'clientes' || e.modulo == 'servicios').toList();

      expect(comerciales, hasLength(40));
      // La etiqueta de contexto se resolvió para TODAS, en lote: si se
      // hubiera resuelto fila por fila, esto seguiría pasando pero con
      // 40 consultas — por eso la prueba de verdad es la de conteo, en
      // `auditoria_comercial_consultas_test.dart`.
      expect(comerciales.every((e) => (e.entidadEtiqueta ?? '').isNotEmpty), isTrue);
    });
  });
}
