import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/utils/clock.dart';

import '../../domain/repositories/configuracion_cobro_repository.dart';
import '../../domain/usecases/configuracion_cobro_con_vigencia.dart';
import '../../domain/usecases/configuracion_cobro_validator.dart';

class ConfiguracionCobroRepositoryImpl implements ConfiguracionCobroRepository {
  ConfiguracionCobroRepositoryImpl(this._db, {Clock clock = const SystemClock()}) : _clock = clock;

  final AppDatabase _db;
  final Clock _clock;

  @override
  Future<({ConfiguracionCobroData configuracion, ConfiguracionCobroVigenciaData vigencia})> crearConfiguracion({
    required String servicioId,
    required ConfiguracionCobroValidada datos,
  }) {
    return _db.transaction(() async {
      final configuracion = await _db.into(_db.configuracionCobro).insertReturning(
            ConfiguracionCobroCompanion.insert(servicioId: servicioId),
          );

      final vigencia = await _db.into(_db.configuracionCobroVigencia).insertReturning(
            ConfiguracionCobroVigenciaCompanion.insert(
              configuracionCobroId: configuracion.id,
              tipoDocumento: datos.tipoDocumento.name,
              frecuenciaId: datos.frecuenciaId,
              diaInicioPeriodo: datos.diaInicioPeriodo,
              agrupacion: datos.agrupacion.name,
              metodo: datos.metodo.name,
              requiereComplemento: Value(datos.requiereComplemento),
              entidadFiscalId: Value(datos.entidadFiscalId),
              portalNombre: Value(datos.portalNombre),
              portalUrl: Value(datos.portalUrl),
              portalUsuario: Value(datos.portalUsuario),
              portalContrasena: Value(datos.portalContrasena),
              portalObservaciones: Value(datos.portalObservaciones),
              cuentaBancaria: Value(datos.cuentaBancaria),
              observaciones: Value(datos.observaciones),
              fechaInicioVigencia: datos.fechaInicioVigencia,
            ),
          );

      for (final correo in datos.correos) {
        await _db.into(_db.configuracionCobroCorreo).insert(
              ConfiguracionCobroCorreoCompanion.insert(
                configuracionCobroVigenciaId: vigencia.id,
                correo: correo,
              ),
            );
      }

      return (configuracion: configuracion, vigencia: vigencia);
    });
  }

  @override
  Future<ConfiguracionCobroConVigencia?> obtenerConfiguracion(String servicioId) async {
    final configuracion =
        await (_db.select(_db.configuracionCobro)..where((t) => t.servicioId.equals(servicioId))).getSingleOrNull();
    if (configuracion == null) return null;

    final vigenciasActivas = await (_db.select(_db.configuracionCobroVigencia)
          ..where(
            (t) =>
                t.configuracionCobroId.equals(configuracion.id) &
                t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
          ))
        .get();

    final hoy = _clock.now();
    final (:vigente, :programadas) = clasificarVigenciasCobro(vigenciasActivas, hoy);
    final vigenciaParaDetalle = vigente ?? (programadas.isEmpty ? null : programadas.first);

    var correos = const <String>[];
    String? entidadFiscalRazonSocial;
    String? frecuenciaNombre;
    if (vigenciaParaDetalle != null) {
      final filasCorreo = await (_db.select(_db.configuracionCobroCorreo)
            ..where((t) => t.configuracionCobroVigenciaId.equals(vigenciaParaDetalle.id)))
          .get();
      correos = [for (final f in filasCorreo) f.correo];

      final entidadFiscalId = vigenciaParaDetalle.entidadFiscalId;
      if (entidadFiscalId != null) {
        final entidad =
            await (_db.select(_db.entidadFiscal)..where((t) => t.id.equals(entidadFiscalId))).getSingleOrNull();
        entidadFiscalRazonSocial = entidad?.razonSocial;
      }

      final frecuencia = await (_db.select(_db.tipoFrecuenciaCobro)
            ..where((t) => t.id.equals(vigenciaParaDetalle.frecuenciaId)))
          .getSingleOrNull();
      frecuenciaNombre = frecuencia?.nombre;
    }

    return ConfiguracionCobroConVigencia(
      configuracion: configuracion,
      vigenciaActual: vigente,
      vigenciasProgramadas: programadas,
      correos: correos,
      entidadFiscalRazonSocial: entidadFiscalRazonSocial,
      frecuenciaNombre: frecuenciaNombre,
    );
  }
}
