import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/database/tables/direccion_table.dart';
import 'package:uuid/uuid.dart';

import '../../domain/repositories/empresa_repository.dart';
import '../../domain/shared/direccion_input.dart';
import '../../domain/shared/medio_contacto_input.dart';

/// Etiqueta fija que identifica de forma determinista "el" medio de
/// contacto que administra 4B — nunca "la primera fila encontrada".
const _etiquetaMedioContactoPrincipal = 'principal';

class EmpresaRepositoryImpl implements EmpresaRepository {
  EmpresaRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<EmpresaData> obtenerActiva() async {
    final activas = await (_db.select(_db.empresa)
          ..where((t) => t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name)))
        .get();

    if (activas.isEmpty) {
      throw StateError('No existe ninguna Empresa activa — la siembra inicial debió crear RSG-01.');
    }
    if (activas.length > 1) {
      throw StateError('Invariante violado: hay ${activas.length} empresas activas simultáneamente.');
    }
    return activas.single;
  }

  @override
  Future<void> actualizarDatosGenerales(EmpresaCompanion cambios) async {
    final activa = await obtenerActiva();
    await (_db.update(_db.empresa)..where((t) => t.id.equals(activa.id))).write(
      cambios.copyWith(updatedAt: Value(DateTime.now())),
    );
  }

  @override
  Future<void> archivar(String id) async {
    final activa = await obtenerActiva();
    if (activa.id == id) {
      throw StateError(
        'No se puede archivar la única Empresa activa sin una operación administrativa especial.',
      );
    }
    await (_db.update(_db.empresa)..where((t) => t.id.equals(id))).write(
      EmpresaCompanion(
        cicloVidaRegistro: Value(CicloVidaRegistro.archivado.name),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<DireccionData?> obtenerDireccionFiscal(String empresaId) {
    return (_db.select(_db.direccion)
          ..where(
            (t) =>
                t.empresaId.equals(empresaId) &
                t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
          ))
        .getSingleOrNull();
  }

  @override
  Future<MedioContactoData?> obtenerMedioContactoPrincipal(String empresaId) {
    return (_db.select(_db.medioContacto)
          ..where(
            (t) =>
                t.empresaId.equals(empresaId) &
                t.etiqueta.equals(_etiquetaMedioContactoPrincipal) &
                t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
          ))
        .getSingleOrNull();
  }

  @override
  Future<EmpresaExpedienteRaw> guardarExpediente({
    required String empresaId,
    required EmpresaCompanion datosGenerales,
    required DireccionInput? direccionFiscal,
    required MedioContactoInput? medioContacto,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.empresa)..where((t) => t.id.equals(empresaId))).write(
        datosGenerales.copyWith(updatedAt: Value(DateTime.now())),
      );
      final empresaActualizada =
          await (_db.select(_db.empresa)..where((t) => t.id.equals(empresaId))).getSingle();

      final direccionResultante = await _guardarDireccionFiscal(empresaId, direccionFiscal);
      final contactoResultante = await _guardarMedioContactoPrincipal(empresaId, medioContacto);

      return EmpresaExpedienteRaw(
        empresa: empresaActualizada,
        direccionFiscal: direccionResultante,
        medioContacto: contactoResultante,
      );
    });
  }

  /// Busca la fila de Dirección de esta Empresa sin importar
  /// `cicloVidaRegistro` — `empresaId` tiene un `.unique()` real en la
  /// tabla (no condicionado a estar activa), así que solo puede existir
  /// una fila por Empresa en toda su historia. Sin esto, recapturar una
  /// dirección después de haberla archivado intentaría un `INSERT` que
  /// choca contra esa fila archivada (bug real encontrado al construir
  /// el mismo patrón para Sucursal en la Etapa 4C).
  Future<DireccionData?> _buscarDireccionDeEmpresa(String empresaId) {
    return (_db.select(_db.direccion)..where((t) => t.empresaId.equals(empresaId))).getSingleOrNull();
  }

  Future<DireccionData?> _guardarDireccionFiscal(String empresaId, DireccionInput? input) async {
    final existente = await _buscarDireccionDeEmpresa(empresaId);

    if (input == null) {
      // Sección vacía: si había una dirección activa, se archiva — nunca
      // se borra físicamente la fila.
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
      // `INSERT`, que chocaría con el `.unique()` de `empresaId`.
      final actualizada = existente.copyWithCompanion(cambios);
      await _db.update(_db.direccion).replace(actualizada);
      return actualizada;
    }

    return _db.into(_db.direccion).insertReturning(
          DireccionCompanion.insert(
            empresaId: Value(empresaId),
            tipoDireccion: TipoDireccion.fiscal.name,
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

  Future<MedioContactoData?> _guardarMedioContactoPrincipal(
    String empresaId,
    MedioContactoInput? input,
  ) async {
    final existente = await obtenerMedioContactoPrincipal(empresaId);

    if (input == null) {
      if (existente != null) {
        await (_db.update(_db.medioContacto)..where((t) => t.id.equals(existente.id))).write(
          MedioContactoCompanion(
            cicloVidaRegistro: Value(CicloVidaRegistro.archivado.name),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
      return null;
    }

    final cambios = MedioContactoCompanion(
      telefono: Value(input.telefono),
      correo: Value(input.correo),
      sitioWeb: Value(input.sitioWeb),
      updatedAt: Value(DateTime.now()),
    );

    if (existente != null) {
      final actualizado = existente.copyWithCompanion(cambios);
      await _db.update(_db.medioContacto).replace(actualizado);
      return actualizado;
    }

    return _db.into(_db.medioContacto).insertReturning(
          MedioContactoCompanion.insert(
            empresaId: Value(empresaId),
            etiqueta: const Value(_etiquetaMedioContactoPrincipal),
            telefono: Value(input.telefono),
            correo: Value(input.correo),
            sitioWeb: Value(input.sitioWeb),
          ),
        );
  }

  @override
  Future<EmpresaData?> obtenerPorId(String id) {
    return (_db.select(_db.empresa)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<AttachmentData> adjuntarLogo({
    required String empresaId,
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
          categoria: const Value(categoriaLogo),
          originalFileName: originalFileName,
          storedFileName: storedFileName,
          path: path,
          mimeType: mimeType,
          sizeBytes: sizeBytes,
        ),
      );
      await _db.into(_db.empresaAttachment).insert(
        EmpresaAttachmentCompanion.insert(attachmentId: adjunto.id, empresaId: empresaId),
      );
      return adjunto;
    });
  }

  @override
  Future<EmpresaData> actualizarLogo({required String empresaId, required String attachmentId}) async {
    await (_db.update(_db.empresa)..where((t) => t.id.equals(empresaId))).write(
      EmpresaCompanion(logoAttachmentId: Value(attachmentId), updatedAt: Value(DateTime.now())),
    );
    return (_db.select(_db.empresa)..where((t) => t.id.equals(empresaId))).getSingle();
  }

  @override
  Future<EmpresaData> eliminarLogo(String empresaId) async {
    await (_db.update(_db.empresa)..where((t) => t.id.equals(empresaId))).write(
      EmpresaCompanion(logoAttachmentId: const Value(null), updatedAt: Value(DateTime.now())),
    );
    return (_db.select(_db.empresa)..where((t) => t.id.equals(empresaId))).getSingle();
  }

  @override
  Future<List<AttachmentData>> historialLogos(String empresaId) {
    final consulta = _db.select(_db.attachment).join([
      innerJoin(_db.empresaAttachment, _db.empresaAttachment.attachmentId.equalsExp(_db.attachment.id)),
    ])..where(_db.empresaAttachment.empresaId.equals(empresaId) & _db.attachment.categoria.equals(categoriaLogo));

    return consulta.map((fila) => fila.readTable(_db.attachment)).get();
  }
}
