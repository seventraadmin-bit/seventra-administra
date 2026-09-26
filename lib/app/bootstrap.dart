import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/attachments/attachment_storage.dart';
import '../core/codigos/codigo_secuencia_service.dart';
import '../core/config/app_info.dart';
import '../core/config/app_paths.dart';
import '../core/config/env.dart';
import '../core/database/app_database.dart';
import '../core/di/providers.dart';
import '../core/error/error_boundary.dart';
import '../core/logging/app_logger.dart';
import '../core/security/almacen_ranuras_clave.dart';
import '../features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import '../features/finanzas/data/repositories/deuda_repository_impl.dart';
import '../features/finanzas/data/repositories/egreso_repository_impl.dart';
import '../features/inventario/data/repositories/asignacion_repository_impl.dart';
import '../features/nomina/data/repositories/nomina_repository_impl.dart';
import '../features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import '../features/nomina/domain/usecases/reconciliar_estatus_pago_nomina_usecase.dart';
import '../features/organizacion/data/repositories/empresa_repository_impl.dart';
import '../features/organizacion/data/repositories/servicio_repository_impl.dart';
import '../features/organizacion/domain/usecases/adoptar_logo_heredado_usecase.dart';
import '../features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import '../features/personal/data/repositories/empleado_repository_impl.dart';
import '../features/respaldo/domain/portable/coordinador_restauracion_portable.dart';
import '../features/respaldo/domain/portable/validador_base_restaurada.dart';
import '../features/respaldo/domain/portable/verificar_respaldo_portable_usecase.dart';
import '../features/respaldo/domain/usecases/aplicar_restauracion_pendiente_usecase.dart';
import '../features/respaldo/domain/usecases/crear_respaldo_usecase.dart';
import '../features/respaldo/domain/usecases/preparar_restauracion_usecase.dart';
import '../features/respaldo/domain/usecases/validar_paquete_respaldo_usecase.dart';
import '../features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import '../features/usuarios/data/repositories/permiso_usuario_repository_impl.dart';
import '../features/usuarios/data/repositories/usuario_repository_impl.dart';
import '../features/usuarios/domain/sesion_usuario.dart';
import '../features/usuarios/domain/usecases/restaurar_sesion_recordada_usecase.dart';
import '../features/usuarios/presentation/sesion_controller.dart';
import 'apertura_base_restaurada.dart';
import 'app.dart';

/// Estado inicial fijo de la sesión (Etapa 15) — cuando `bootstrap()`
/// ya validó una sesión recordada antes de `runApp`, este override
/// evita que `SesionController` empiece en `null` y tenga que
/// "alcanzar" ese estado después. Mismo mecanismo que decenas de
/// pruebas de este proyecto ya usan para fijar una sesión sin pasar por
/// `LoginUseCase` (`sesionControllerProvider.overrideWith(...)`), ahora
/// en código de producción.
class _SesionControllerPrecargada extends SesionController {
  _SesionControllerPrecargada(this._inicial);
  final SesionUsuario? _inicial;
  @override
  SesionUsuario? build() => _inicial;
}

/// Orquesta el arranque completo de RISEG ONE, en orden:
/// logging → manejo de errores → rutas de datos → base de datos → `runApp`.
///
/// Todo ocurre dentro de una misma zona protegida ([runGuardedApp]) para que
/// ningún error de inicialización, incluidos los asíncronos, se pierda.
void bootstrap() {
  final env = Env.resolve();
  final logger = AppLogger.console();

  runGuardedApp(logger, () async {
    WidgetsFlutterBinding.ensureInitialized();
    installErrorBoundary(logger);

    logger.info('Iniciando RISEG ONE — entorno: ${env.name}');

    final appPaths = await AppPaths.resolve(env);
    logger.info('Carpeta de datos: ${appPaths.rootDir}');

    // Si hay una restauración pendiente (Etapa 14C), se aplica aquí —
    // antes de abrir la base de datos — para nunca intentar sustituir
    // un archivo que la propia conexión Drift ya tiene abierto.
    final restaurador = AplicarRestauracionPendienteUseCase(
      databaseFile: appPaths.databaseFile,
      attachmentsDir: appPaths.attachmentsDir,
      restorePendingDir: appPaths.restorePendingDir,
      restorePendingMarkerFile: appPaths.restorePendingMarkerFile,
      restoreOldDir: appPaths.restoreOldDir,
    );
    // Antes de aplicar hay que saber QUÉ clase de restauración es. Una
    // recuperación portable (Etapa 4D) trae, además de archivos, una clave
    // de cifrado distinta que hay que promover en el mismo acto. Si se
    // aplicara por la vía normal, la base quedaría restaurada y la clave
    // seguiría siendo la de este equipo — exactamente la situación que no
    // puede ocurrir: base de allá con clave de aquí.
    final marcador = await restaurador.leerMarcador();
    final esPortable = marcador != null && marcador[CamposRestauracionPortable.operacion] != null;

    if (esPortable) {
      final resultado = await _coordinadorPortable(appPaths, restaurador).aplicarYConfirmar();
      switch (resultado) {
        case RestauracionPortableConfirmada(:final restoreOperationId, :final keyId):
          logger.info('Recuperación portable completada — operación: $restoreOperationId, clave: $keyId');
        case RestauracionPortableRevertida(:final motivo, :final estadoAnteriorRepuesto):
          // Se registra si el estado anterior volvió o no: son dos
          // situaciones muy distintas para quien tenga que atender esto.
          final nombreMotivo = motivo.name;
          logger.error(
            'La recuperación portable se abortó ($nombreMotivo). '
            'Estado anterior repuesto: $estadoAnteriorRepuesto',
          );
        case RestauracionPortableEstadoAmbiguo(:final detalle):
          logger.error('La recuperación portable quedó en un estado que no se puede interpretar: $detalle');
        case SinRestauracionPortablePendiente():
          logger.info('No había recuperación portable pendiente.');
      }
    }

    // Basura en claro de operaciones portables que no llegaron a terminar
    // (Etapa 4D). Mientras se verifica o se recupera un paquete, su
    // contenido descifrado vive un rato en esta carpeta; quien la usa la
    // borra al acabar, pero un corte de luz a medio camino la deja ahí. Este
    // es el único momento en que se puede vaciar sin riesgo: nadie la está
    // usando todavía. Se hace DESPUÉS de la fase 2 portable, porque esa sí
    // la usa.
    _vaciarEspacioDeTrabajoPortable(appPaths, logger);

    // La vía normal (Etapa 14C/4B). Si acaba de correr la portable, el
    // marcador ya no existe y esto es un no-op.
    final resultadoRestauracion = await restaurador.ejecutar();
    if (resultadoRestauracion is RestauracionFallidaConEvidencia) {
      // No se borró nada: el estado anterior sigue completo en disco.
      // Se registra dónde, que es lo único útil que se puede hacer
      // desde aquí sin arriesgar los datos.
      logger.error(
        'La restauración no pudo completarse. El estado anterior quedó en: '
        '${resultadoRestauracion.carpetaEstadoAnterior}',
        resultadoRestauracion.detalle,
      );
    }

    // Si acaba de aplicarse una restauración, abrirla es sólo el
    // principio: hasta que la base migre completa, quede en el esquema
    // esperado, pase sus PRAGMAs y sus adjuntos coincidan, la
    // restauración NO se confirma y el estado anterior sigue apartado.
    // Esa es toda la razón de que no se borre antes (ver
    // `abrirConfirmandoRestauracion`).
    final AppDatabase database;
    if (resultadoRestauracion is RestauracionAplicadaPendienteConfirmar) {
      final apertura = await abrirConfirmandoRestauracion(
        databaseFile: appPaths.databaseFile,
        restaurador: restaurador,
        logger: logger,
      );
      database = apertura.database;
    } else {
      database = AppDatabase(openAppDatabaseConnection(appPaths.databaseFile));
    }
    final metadata = await database.ensureMetadata(appVersion: kAppVersion);
    logger.info(
      'Metadata de instalación — id: ${metadata.installationId}, '
      'instalada: ${metadata.installedAt}, último acceso: ${metadata.lastOpenedAt}',
    );

    // Reparación de datos históricos (Etapa 15, bug real reportado por
    // Marlon): `PagoNominaRepository.sincronizarEstatusPago` solo
    // corrige `NominaEmpleado.estatusPago`/`Nomina.estatus` la próxima
    // vez que se escribe `totalAPagar` — una Nómina ya `cerrada`/
    // `pagada` nunca vuelve a pasar por ahí sola. Se reconcilia aquí,
    // antes de `runApp`, sobre TODAS las Nóminas existentes en cada
    // arranque — es un no-op instantáneo (sin escrituras) en cuanto los
    // datos ya están correctos, así que repetirlo en cada arranque es
    // seguro y barato (ver el doc comment de
    // `ReconciliarEstatusPagoNominaUseCase`).
    final reconciliacion = await ReconciliarEstatusPagoNominaUseCase(
      NominaRepositoryImpl(
        database,
        AsignacionRepositoryImpl(database),
        DescuentoProgramadoRepositoryImpl(database, EgresoRepositoryImpl(database), CodigoSecuenciaService(database)),
        TiempoExtraRepositoryImpl(
          database,
          EgresoRepositoryImpl(database),
          DeudaRepositoryImpl(database, EgresoRepositoryImpl(database)),
          CodigoSecuenciaService(database),
          EmpleadoRepositoryImpl(database, AsignacionServicioRepositoryImpl(database)),
          ServicioRepositoryImpl(database, AsignacionServicioRepositoryImpl(database)),
        ),
        PagoNominaRepositoryImpl(database, EgresoRepositoryImpl(database), DescuentoProgramadoRepositoryImpl(database, EgresoRepositoryImpl(database), CodigoSecuenciaService(database))),
      ),
      PagoNominaRepositoryImpl(database, EgresoRepositoryImpl(database), DescuentoProgramadoRepositoryImpl(database, EgresoRepositoryImpl(database), CodigoSecuenciaService(database))),
    ).ejecutar();
    if (reconciliacion.renglonesCorregidos > 0 || reconciliacion.nominasActualizadas > 0) {
      logger.info(
        'Reconciliación de estatus de pago de Nómina — renglones corregidos: '
        '${reconciliacion.renglonesCorregidos}, Nóminas actualizadas: ${reconciliacion.nominasActualizadas}.',
      );
    }

    // Adopción del logotipo heredado (Etapa 5B.2) — transición de datos,
    // no una regla del producto.
    //
    // Hasta 5B.1 el logotipo de la Empresa era un asset dentro de la
    // aplicación. Ahora pertenece a la Empresa, así que una instalación que
    // viene de antes lo adopta una sola vez y sigue viéndolo sin que nadie
    // tenga que volver a cargarlo. Es idempotente y no mira quién es la
    // Empresa: en una instalación nueva no encuentra nada que adoptar.
    //
    // Cuando ya no queden instalaciones anteriores, este bloque y su caso de
    // uso se retiran enteros sin tocar nada más.
    final empresaRepo = EmpresaRepositoryImpl(database);
    try {
      final empresaActiva = await empresaRepo.obtenerActiva();
      final adopcion = await AdoptarLogoHeredadoUseCase(
        empresaRepo,
        AttachmentStorage(appPaths.attachmentsDir),
        () async {
          try {
            final datos = await rootBundle.load('assets/images/logo.png');
            return datos.buffer.asUint8List();
          } catch (_) {
            // Sin asset heredado no hay nada que adoptar, y eso es lo normal
            // en cuanto el archivo deje de distribuirse.
            return null;
          }
        },
      ).ejecutar(empresaActiva.id);

      if (adopcion is LogoHeredadoAdoptado) {
        logger.info('Logotipo heredado adoptado como adjunto de la Empresa.');
      }
    } catch (e) {
      // Nunca puede impedir el arranque: sin logotipo la aplicación funciona
      // igual, y la Empresa puede cargarlo desde su expediente.
      logger.error('No se pudo adoptar el logotipo heredado', e);
    }

    // "Recuérdame en este equipo" (Etapa 15) — se resuelve aquí, antes
    // de `runApp`, porque el `redirect` del router lee la sesión de
    // forma síncrona. Sin nada que recordar, o si el token ya no es
    // válido (Usuario eliminado/desactivado, o esta es una base
    // restaurada de la Etapa 14C con otros Usuarios), `sesionRecordada`
    // queda `null` y la app arranca en `/login` exactamente igual que
    // hoy.
    final sesionRecordada = await RestaurarSesionRecordadaUseCase(
      UsuarioRepositoryImpl(database),
      PermisoUsuarioRepositoryImpl(database),
    ).ejecutar();
    if (sesionRecordada != null) {
      logger.info('Sesión recordada restaurada — usuario: ${sesionRecordada.nombreUsuario}');
    }

    runApp(
      ProviderScope(
        overrides: [
          envProvider.overrideWithValue(env),
          appLoggerProvider.overrideWithValue(logger),
          appPathsProvider.overrideWithValue(appPaths),
          appDatabaseProvider.overrideWithValue(database),
          if (sesionRecordada != null)
            sesionControllerProvider.overrideWith(() => _SesionControllerPrecargada(sesionRecordada)),
        ],
        child: RisegOneApp(),
      ),
    );
  });
}

/// El coordinador de la fase 2 de una recuperación portable, construido a
/// mano porque aquí todavía no existe ningún `ProviderContainer`: esto
/// corre antes de `runApp`, y precisamente antes de abrir la base de datos.
///
/// Recibe el mismo [aplicar] que usa la vía normal, no otro: los dos tienen
/// que mirar el mismo marcador y las mismas carpetas.
CoordinadorRestauracionPortable _coordinadorPortable(AppPaths appPaths, AplicarRestauracionPendienteUseCase aplicar) {
  final validador = ValidadorBaseRestaurada(
    abrirBase: () => AppDatabase(openAppDatabaseConnection(appPaths.databaseFile)),
  );
  return CoordinadorRestauracionPortable(
    // La fase 2 no vuelve a abrir el paquete —ya no está, el usuario se
    // llevó su memoria USB— pero el constructor pide sus colaboradores
    // completos.
    verificador: VerificarRespaldoPortableUseCase(stagingDir: appPaths.portableStagingDir),
    preparar: PrepararRestauracionUseCase(
      backupsDir: appPaths.backupsDir,
      restorePendingDir: appPaths.restorePendingDir,
      restorePendingMarkerFile: appPaths.restorePendingMarkerFile,
      validar: ValidarPaqueteRespaldoUseCase(),
      crearRespaldo: CrearRespaldoUseCase(databaseFile: appPaths.databaseFile, attachmentsDir: appPaths.attachmentsDir),
    ),
    aplicar: aplicar,
    ranuras: const AlmacenRanurasClaveWindows(),
    stagingDir: appPaths.portableStagingDir,
    validarBaseRestaurada: validador.validar,
    claveAbreLoRestaurado: validador.claveAbreLoRestaurado,
  );
}

/// Vacía el espacio de trabajo de la recuperación portable.
///
/// Se hace en silencio y sin propagar fallos: no poder borrar restos no es
/// razón para que la aplicación no arranque. Se registra, eso sí, porque
/// restos que no se van son una pista de que algo más pasa (un antivirus
/// sosteniendo el archivo, un disco de sólo lectura).
void _vaciarEspacioDeTrabajoPortable(AppPaths appPaths, AppLogger logger) {
  final dir = Directory(appPaths.portableStagingDir);
  if (!dir.existsSync()) return;
  try {
    dir.deleteSync(recursive: true);
  } on FileSystemException catch (e) {
    logger.error('No se pudo vaciar el espacio de trabajo de recuperación portable: ${appPaths.portableStagingDir}', e);
  }
}
