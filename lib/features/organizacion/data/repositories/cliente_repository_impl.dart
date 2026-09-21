import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/database/tables/direccion_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/cliente_table.dart';
import 'package:uuid/uuid.dart';

import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/auditoria/enmascarar_identificador.dart';

import '../../domain/repositories/cliente_repository.dart';
import '../tables/comercial_evento_table.dart';
import 'comercial_evento_writer.dart';
import '../../domain/shared/direccion_input.dart';
import '../../domain/usecases/eliminar_cliente_fisicamente_usecase.dart';

class ClienteRepositoryImpl implements ClienteRepository {
  ClienteRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<ClienteData> crear(ClienteCompanion datos) {
    return _db.into(_db.cliente).insertReturning(datos);
  }

  @override
  Future<ClienteData?> obtenerPorId(String id) {
    return (_db.select(_db.cliente)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<ClienteData>> listarActivos() {
    return (_db.select(_db.cliente)
          ..where((t) => t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name)))
        .get();
  }

  @override
  Future<Map<String, ClienteData>> listarPorIds(Iterable<String> ids) async {
    final unicos = ids.toSet();
    if (unicos.isEmpty) return {};
    final filas = await (_db.select(_db.cliente)..where((t) => t.id.isIn(unicos))).get();
    return {for (final f in filas) f.id: f};
  }

  @override
  Future<ClienteData> cambiarEstatus({
    required String id,
    required EstatusCliente nuevo,
    String? motivo,
    String? actorUsuarioId,
  }) {
    // El evento va DENTRO de la transacción del cambio: o quedan los
    // dos, o no queda ninguno. Un estatus cambiado sin bitácora sería
    // exactamente el hueco que esta etapa cierra.
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.cliente)..where((t) => t.id.equals(id))).getSingle();
      await (_db.update(_db.cliente)..where((t) => t.id.equals(id))).write(
        ClienteCompanion(estatus: Value(nuevo.name), updatedAt: Value(DateTime.now())),
      );

      final diff = DiffEvento()..anotar('estatus', anterior.estatus, nuevo.name);
      if (diff.hayCambios) {
        await registrarEventoCliente(
          _db,
          clienteId: id,
          tipoEvento: TipoEventoCliente.estatusCambiado,
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          observacion: motivo,
          actorUsuarioId: actorUsuarioId,
        );
      }
      return (_db.select(_db.cliente)..where((t) => t.id.equals(id))).getSingle();
    });
  }

  @override
  Future<DireccionData?> obtenerDireccionReferencia(String clienteId) {
    return (_db.select(_db.direccion)
          ..where(
            (t) =>
                t.clienteId.equals(clienteId) &
                t.tipoDireccion.equals(TipoDireccion.referencia.name) &
                t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
          ))
        .getSingleOrNull();
  }

  @override
  Future<Map<String, DireccionData>> listarDireccionesReferencia(List<String> clienteIds) async {
    if (clienteIds.isEmpty) return {};
    final filas = await (_db.select(_db.direccion)
          ..where(
            (t) =>
                t.clienteId.isIn(clienteIds) &
                t.tipoDireccion.equals(TipoDireccion.referencia.name) &
                t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
          ))
        .get();
    return {for (final d in filas) d.clienteId!: d};
  }

  @override
  Future<ClienteExpedienteRaw> guardarExpediente({
    required String clienteId,
    required ClienteCompanion datosGenerales,
    required DireccionInput? direccionReferencia,
    String? motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.cliente)..where((t) => t.id.equals(clienteId))).getSingle();
      await (_db.update(_db.cliente)..where((t) => t.id.equals(clienteId))).write(
        datosGenerales.copyWith(updatedAt: Value(DateTime.now())),
      );
      final clienteActualizado = await (_db.select(_db.cliente)..where((t) => t.id.equals(clienteId))).getSingle();

      final direccionResultante = await _guardarDireccionReferencia(clienteId, direccionReferencia);

      // Sólo los campos comerciales que de verdad cambiaron. Guardar
      // el registro completo convertiría la bitácora en ruido.
      final diff = DiffEvento()
        ..anotar('nombreComercial', anterior.nombreComercial, clienteActualizado.nombreComercial)
        ..anotar('estatus', anterior.estatus, clienteActualizado.estatus)
        ..anotar('observaciones', anterior.observaciones, clienteActualizado.observaciones);
      if (diff.hayCambios) {
        await registrarEventoCliente(
          _db,
          clienteId: clienteId,
          tipoEvento: TipoEventoCliente.corregido,
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          observacion: motivo,
          actorUsuarioId: actorUsuarioId,
        );
      }

      return ClienteExpedienteRaw(cliente: clienteActualizado, direccionReferencia: direccionResultante);
    });
  }

  /// Busca la dirección de referencia de este Cliente sin importar
  /// `cicloVidaRegistro` — a diferencia de Empresa/Sucursal (`.unique()`
  /// real), `Direccion.clienteId` es 1:N (permite varias por tipo
  /// distinto), así que se busca explícitamente por `tipo_direccion =
  /// 'referencia'`. Esta pantalla solo administra una, por eso basta con
  /// buscar la única fila de ese tipo que exista, si existe.
  Future<DireccionData?> _buscarDireccionReferencia(String clienteId) {
    return (_db.select(_db.direccion)
          ..where((t) => t.clienteId.equals(clienteId) & t.tipoDireccion.equals(TipoDireccion.referencia.name)))
        .getSingleOrNull();
  }

  Future<DireccionData?> _guardarDireccionReferencia(String clienteId, DireccionInput? input) async {
    final existente = await _buscarDireccionReferencia(clienteId);

    if (input == null) {
      // Sección vacía: si había una dirección activa, se archiva — nunca
      // se borra físicamente la fila (mismo patrón que Empresa/Sucursal).
      if (existente != null && existente.cicloVidaRegistro == CicloVidaRegistro.activo.name) {
        await (_db.update(_db.direccion)..where((t) => t.id.equals(existente.id))).write(
          DireccionCompanion(
            cicloVidaRegistro: Value(CicloVidaRegistro.archivado.name),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
      return null;
    }

    final cambios = DireccionCompanion(
      cicloVidaRegistro: Value(CicloVidaRegistro.activo.name),
      calle: Value(input.calle),
      numeroExterior: Value(input.numeroExterior),
      numeroInterior: Value(input.numeroInterior),
      colonia: Value(input.colonia),
      municipioAlcaldia: Value(input.municipioAlcaldia),
      ciudadLocalidad: Value(input.ciudadLocalidad),
      estado: Value(input.estado),
      codigoPostal: Value(input.codigoPostal),
      pais: Value(input.pais),
      referencias: Value(input.referencias),
      updatedAt: Value(DateTime.now()),
    );

    if (existente != null) {
      // Reactiva (si venía archivada) y actualiza — nunca un segundo
      // `INSERT`, que dejaría dos filas de referencia para el mismo
      // Cliente.
      final actualizada = existente.copyWithCompanion(cambios);
      await _db.update(_db.direccion).replace(actualizada);
      return actualizada;
    }

    return _db.into(_db.direccion).insertReturning(
          DireccionCompanion.insert(
            clienteId: Value(clienteId),
            tipoDireccion: TipoDireccion.referencia.name,
            calle: input.calle,
            numeroExterior: input.numeroExterior,
            numeroInterior: Value(input.numeroInterior),
            colonia: input.colonia,
            municipioAlcaldia: input.municipioAlcaldia,
            ciudadLocalidad: Value(input.ciudadLocalidad),
            estado: input.estado,
            codigoPostal: input.codigoPostal,
            pais: Value(input.pais),
            referencias: Value(input.referencias),
          ),
        );
  }

  @override
  Future<ContactoData> agregarContacto(ContactoCompanion datos, {String? actorUsuarioId}) {
    return _db.transaction(() async {
      if (datos.esPrincipal.present && datos.esPrincipal.value) {
        await _retirarPrincipalDelMismoTipo(clienteId: datos.clienteId.value, tipo: datos.tipo.value);
      }
      final creado = await _db.into(_db.contacto).insertReturning(datos);

      // Teléfono y correo van ENMASCARADOS ya en la fuente. Un evento
      // es append-only: lo que entra ahí no se vuelve a sacar, y la
      // bitácora no debe convertirse en un segundo directorio de
      // contactos consultable con `auditoria.ver`. Mismo criterio que
      // Telefonía con ICCID/IMEI.
      await registrarEventoCliente(
        _db,
        clienteId: creado.clienteId,
        tipoEvento: TipoEventoCliente.contactoAgregado,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'contactoId': creado.id,
          'nombre': creado.nombre,
          'puesto': creado.puesto,
          'tipo': creado.tipo,
          'telefono': enmascararIdentificador(creado.telefono),
          'correo': enmascararCorreo(creado.correo),
        },
      );
      return creado;
    });
  }

  @override
  Future<ContactoData> actualizarContacto({
    required String id,
    required ContactoCompanion cambios,
    String? motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final antes = await (_db.select(_db.contacto)..where((t) => t.id.equals(id))).getSingle();
      if (cambios.esPrincipal.present && cambios.esPrincipal.value) {
        final tipoDestino = cambios.tipo.present ? cambios.tipo.value : antes.tipo;
        await _retirarPrincipalDelMismoTipo(clienteId: antes.clienteId, tipo: tipoDestino, exceptoId: id);
      }

      await (_db.update(_db.contacto)..where((t) => t.id.equals(id))).write(
        cambios.copyWith(updatedAt: Value(DateTime.now())),
      );
      final despues = await (_db.select(_db.contacto)..where((t) => t.id.equals(id))).getSingle();

      // Nombre, puesto y tipo se guardan completos: identifican a la
      // persona dentro del Cliente y no son un canal de contacto.
      // Teléfono y correo, enmascarados — se ve QUE cambiaron, no a
      // qué valor.
      final diff = DiffEvento()
        ..anotar('nombre', antes.nombre, despues.nombre)
        ..anotar('puesto', antes.puesto, despues.puesto)
        ..anotar('tipo', antes.tipo, despues.tipo)
        ..anotar('esPrincipal', antes.esPrincipal, despues.esPrincipal)
        ..anotar(
          'telefono',
          enmascararIdentificador(antes.telefono),
          enmascararIdentificador(despues.telefono),
        )
        ..anotar('correo', enmascararCorreo(antes.correo), enmascararCorreo(despues.correo));
      if (diff.hayCambios) {
        await registrarEventoCliente(
          _db,
          clienteId: despues.clienteId,
          tipoEvento: TipoEventoCliente.contactoCorregido,
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          observacion: motivo,
          actorUsuarioId: actorUsuarioId,
          datosRelevantes: {'contactoId': id},
        );
      }
      return despues;
    });
  }

  /// Retira la marca de principal de cualquier otro contacto activo del
  /// mismo Cliente y tipo — garantiza que, tras esta llamada, a lo más
  /// uno quede marcado como principal de ese tipo (la unicidad real la
  /// exige además el índice de la base de datos; esto la aplica también
  /// del lado de la aplicación, sin depender únicamente de que el
  /// `INSERT`/`UPDATE` posterior falle).
  Future<void> _retirarPrincipalDelMismoTipo({
    required String clienteId,
    required String tipo,
    String? exceptoId,
  }) async {
    var query = _db.update(_db.contacto)
      ..where(
        (t) =>
            t.clienteId.equals(clienteId) &
            t.tipo.equals(tipo) &
            t.esPrincipal.equals(true) &
            t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
      );
    if (exceptoId != null) {
      query = query..where((t) => t.id.equals(exceptoId).not());
    }
    await query.write(ContactoCompanion(esPrincipal: const Value(false), updatedAt: Value(DateTime.now())));
  }

  @override
  Future<ContactoData> archivarContacto(String id, {String? motivo, String? actorUsuarioId}) {
    return _db.transaction(() async {
      final antes = await (_db.select(_db.contacto)..where((t) => t.id.equals(id))).getSingle();
      await (_db.update(_db.contacto)..where((t) => t.id.equals(id))).write(
        ContactoCompanion(
          cicloVidaRegistro: Value(CicloVidaRegistro.archivado.name),
          updatedAt: Value(DateTime.now()),
        ),
      );
      final despues = await (_db.select(_db.contacto)..where((t) => t.id.equals(id))).getSingle();

      final diff = DiffEvento()
        ..anotar('cicloVidaRegistro', antes.cicloVidaRegistro, despues.cicloVidaRegistro);
      if (diff.hayCambios) {
        await registrarEventoCliente(
          _db,
          clienteId: despues.clienteId,
          tipoEvento: TipoEventoCliente.contactoArchivado,
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          observacion: motivo,
          actorUsuarioId: actorUsuarioId,
          datosRelevantes: {'contactoId': id, 'nombre': despues.nombre},
        );
      }
      return despues;
    });
  }

  @override
  Future<List<ContactoData>> obtenerContactos(String clienteId) {
    return (_db.select(_db.contacto)
          ..where(
            (t) =>
                t.clienteId.equals(clienteId) &
                t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
          ))
        .get();
  }

  @override
  Future<ContactoData?> obtenerContactoPorId(String id) {
    return (_db.select(_db.contacto)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Eliminación física extraordinaria (Etapa 15, mismo patrón que la
  /// Etapa 11D) — a diferencia de Sucursal/Servicio, `crear` es un
  /// `insert` simple sin ninguna fila automática (confirmado: sin
  /// transacción, sin Ubicación ni equivalente estructural), así que no
  /// existe ninguna excepción de "estructura automática" que
  /// distinguir — un Cliente recién creado, sin actividad real, ya es
  /// el caso elegible. Se verifican, en orden, las 7 dependencias
  /// reales confirmadas en el grafo de FK: `Servicio`, `Contacto`,
  /// `EntidadFiscal`, `ClienteAttachment`, `DocumentoPorEmitir`, `Pago`
  /// (todas `onDelete: restrict`) y `Direccion` (FK declarada como SQL
  /// crudo en `core/database/tables/direccion_table.dart`, invisible a
  /// una búsqueda superficial de `references(Cliente,`).
  /// `CuentaPorCobrar.clienteId` no es una FK real (es un snapshot
  /// copiado del documento de origen, según su propio doc comment) —
  /// no se verifica aparte; cualquier CxC real ya implica un
  /// `DocumentoPorEmitir`, que sí se verifica. Todo — validación,
  /// snapshot, registro de auditoría y `DELETE` — ocurre en una sola
  /// transacción; nunca `CASCADE`.
  @override
  Future<EliminarClienteFisicamenteResultado> eliminarFisicamente({
    required String clienteId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final cliente = await (_db.select(_db.cliente)..where((t) => t.id.equals(clienteId))).getSingleOrNull();
      if (cliente == null) return EliminarClienteFisicamenteNoExiste();

      final servicios = await (_db.select(_db.servicio)..where((t) => t.clienteId.equals(clienteId))).get();
      if (servicios.isNotEmpty) {
        return EliminarClienteFisicamenteTieneDependencias(
          'Tiene ${servicios.length} servicio(s) registrado(s).',
        );
      }

      final contactos = await (_db.select(_db.contacto)..where((t) => t.clienteId.equals(clienteId))).get();
      if (contactos.isNotEmpty) {
        return EliminarClienteFisicamenteTieneDependencias(
          'Tiene ${contactos.length} contacto(s) registrado(s).',
        );
      }

      final entidadesFiscales =
          await (_db.select(_db.entidadFiscal)..where((t) => t.clienteId.equals(clienteId))).get();
      if (entidadesFiscales.isNotEmpty) {
        return EliminarClienteFisicamenteTieneDependencias(
          'Tiene ${entidadesFiscales.length} entidad(es) fiscal(es) registrada(s).',
        );
      }

      final adjuntos =
          await (_db.select(_db.clienteAttachment)..where((t) => t.clienteId.equals(clienteId))).get();
      if (adjuntos.isNotEmpty) {
        return EliminarClienteFisicamenteTieneDependencias(
          'Tiene ${adjuntos.length} documento(s) adjunto(s) registrado(s).',
        );
      }

      final documentos =
          await (_db.select(_db.documentoPorEmitir)..where((t) => t.clienteId.equals(clienteId))).get();
      if (documentos.isNotEmpty) {
        return EliminarClienteFisicamenteTieneDependencias(
          'Tiene ${documentos.length} documento(s) por emitir registrado(s).',
        );
      }

      final pagos = await (_db.select(_db.pago)..where((t) => t.clienteId.equals(clienteId))).get();
      if (pagos.isNotEmpty) {
        return EliminarClienteFisicamenteTieneDependencias('Tiene ${pagos.length} pago(s) registrado(s).');
      }

      final direcciones = await (_db.select(_db.direccion)..where((t) => t.clienteId.equals(clienteId))).get();
      if (direcciones.isNotEmpty) {
        return EliminarClienteFisicamenteTieneDependencias(
          'Tiene ${direcciones.length} dirección(es) registrada(s).',
        );
      }

      await _db.into(_db.eliminacionFisicaEvento).insert(
            EliminacionFisicaEventoCompanion.insert(
              tipoEntidad: 'cliente',
              entidadIdOriginal: clienteId,
              fechaHora: DateTime.now(),
              motivo: motivo,
              snapshotJson: jsonEncode(cliente.toJson()),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );
      await (_db.delete(_db.cliente)..where((t) => t.id.equals(clienteId))).go();

      return EliminarClienteFisicamenteExitoso();
    });
  }

  @override
  Future<AttachmentData> adjuntarLogo({
    required String clienteId,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
  }) {
    return _db.transaction(() async {
      final adjunto = await _db.into(_db.attachment).insertReturning(
            AttachmentCompanion.insert(
              id: const Uuid().v4(),
              categoria: const Value('logo'),
              originalFileName: originalFileName,
              storedFileName: storedFileName,
              path: path,
              mimeType: mimeType,
              sizeBytes: sizeBytes,
            ),
          );
      await _db.into(_db.clienteAttachment).insert(
            ClienteAttachmentCompanion.insert(attachmentId: adjunto.id, clienteId: clienteId),
          );
      return adjunto;
    });
  }

  @override
  Future<ClienteData> actualizarLogo({required String clienteId, required String attachmentId}) async {
    await (_db.update(_db.cliente)..where((t) => t.id.equals(clienteId))).write(
      ClienteCompanion(logoAttachmentId: Value(attachmentId), updatedAt: Value(DateTime.now())),
    );
    return (_db.select(_db.cliente)..where((t) => t.id.equals(clienteId))).getSingle();
  }

  @override
  Future<ClienteData> eliminarLogo(String clienteId) async {
    await (_db.update(_db.cliente)..where((t) => t.id.equals(clienteId))).write(
      ClienteCompanion(logoAttachmentId: const Value(null), updatedAt: Value(DateTime.now())),
    );
    return (_db.select(_db.cliente)..where((t) => t.id.equals(clienteId))).getSingle();
  }
}
