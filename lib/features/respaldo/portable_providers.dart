import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_info.dart';
import '../../core/database/app_database.dart';
import '../../core/di/providers.dart';
import '../../core/permissions/authorization_service.dart';
import '../../core/security/almacen_ranuras_clave.dart';
import '../../core/security/credential_cipher.dart';
import '../usuarios/usuarios_providers.dart';
import 'data/repositories/configuracion_recuperacion_repository_impl.dart';
import 'domain/portable/autorizar_restauracion_portable.dart';
import 'domain/portable/configuracion_recuperacion.dart';
import 'domain/portable/configurar_recuperacion_usecase.dart';
import 'domain/portable/coordinador_restauracion_portable.dart';
import 'domain/portable/crear_respaldo_portable_usecase.dart';
import 'domain/portable/evaluador_instalacion.dart';
import 'domain/portable/resultado_recuperacion.dart';
import 'domain/portable/sobre_portable.dart';
import 'domain/portable/validador_base_restaurada.dart';
import 'domain/portable/verificar_respaldo_portable_usecase.dart';
import 'domain/usecases/aplicar_restauracion_pendiente_usecase.dart';
import 'respaldo_providers.dart';

/// Etapa 4D — recuperación portable.
///
/// Las piezas de criptografía se exponen como providers por una razón
/// concreta: Argon2id reserva 64 MiB cada vez que se construye, y eso no
/// debe ocurrir una vez por pulsación. Ninguna guarda secretos entre
/// llamadas: la frase, la clave maestra y la clave de la aplicación viven
/// en variables locales que mueren con la operación.

/// Las tres ranuras de clave de este equipo. En Windows viven en el
/// Almacén de Credenciales; la ranura principal **es** la clave con la que
/// la aplicación descifra sus datos.
final almacenRanurasClaveProvider = Provider<AlmacenRanurasClave>((ref) {
  return const AlmacenRanurasClaveWindows();
});

/// Sobre de envoltura. Sin argumentos usa `Random.secure()` y el Argon2id
/// real: en producción no hay atajos.
final sobrePortableProvider = Provider<SobrePortable>((ref) => SobrePortable());

final configuracionRecuperacionRepositoryProvider = Provider<ConfiguracionRecuperacionRepositoryImpl>((ref) {
  return ConfiguracionRecuperacionRepositoryImpl(ref.watch(appDatabaseProvider));
});

/// La configuración vigente, o `null` si la recuperación portable aún no
/// se ha configurado. La pantalla la observa para saber qué ofrecer.
final configuracionRecuperacionProvider = FutureProvider<ConfiguracionRecuperacion?>((ref) {
  return ref.watch(configuracionRecuperacionRepositoryProvider).obtener();
});

final configurarRecuperacionUseCaseProvider = Provider<ConfigurarRecuperacionUseCase>((ref) {
  return ConfigurarRecuperacionUseCase(sobre: ref.watch(sobrePortableProvider));
});

final verificarRespaldoPortableUseCaseProvider = Provider<VerificarRespaldoPortableUseCase>((ref) {
  return VerificarRespaldoPortableUseCase(
    stagingDir: ref.watch(appPathsProvider).portableStagingDir,
    sobre: ref.watch(sobrePortableProvider),
  );
});

final crearRespaldoPortableUseCaseProvider = Provider<CrearRespaldoPortableUseCase>((ref) {
  final rutas = ref.watch(appPathsProvider);
  return CrearRespaldoPortableUseCase(
    databaseFile: rutas.databaseFile,
    attachmentsDir: rutas.attachmentsDir,
    stagingDir: rutas.portableStagingDir,
    appVersion: kAppVersion,
    cipher: CredentialCipher(),
    sobre: ref.watch(sobrePortableProvider),
    verificador: ref.watch(verificarRespaldoPortableUseCaseProvider),
  );
});

/// Validador de la base ya instalada. Abre una conexión **propia**, aparte
/// de la de la aplicación, porque su trabajo es justamente juzgar un
/// archivo que la aplicación todavía no ha adoptado.
final validadorBaseRestauradaProvider = Provider<ValidadorBaseRestaurada>((ref) {
  final rutas = ref.watch(appPathsProvider);
  return ValidadorBaseRestaurada(abrirBase: () => AppDatabase(openAppDatabaseConnection(rutas.databaseFile)));
});

final aplicarRestauracionPendienteUseCaseProvider = Provider<AplicarRestauracionPendienteUseCase>((ref) {
  final rutas = ref.watch(appPathsProvider);
  return AplicarRestauracionPendienteUseCase(
    databaseFile: rutas.databaseFile,
    attachmentsDir: rutas.attachmentsDir,
    restorePendingDir: rutas.restorePendingDir,
    restorePendingMarkerFile: rutas.restorePendingMarkerFile,
    restoreOldDir: rutas.restoreOldDir,
  );
});

final coordinadorRestauracionPortableProvider = Provider<CoordinadorRestauracionPortable>((ref) {
  final rutas = ref.watch(appPathsProvider);
  final validador = ref.watch(validadorBaseRestauradaProvider);
  return CoordinadorRestauracionPortable(
    verificador: ref.watch(verificarRespaldoPortableUseCaseProvider),
    preparar: ref.watch(prepararRestauracionUseCaseProvider),
    aplicar: ref.watch(aplicarRestauracionPendienteUseCaseProvider),
    ranuras: ref.watch(almacenRanurasClaveProvider),
    stagingDir: rutas.portableStagingDir,
    validarBaseRestaurada: validador.validar,
    claveAbreLoRestaurado: validador.claveAbreLoRestaurado,
  );
});

/// ¿Hay en este equipo algo que una restauración pudiera destruir?
///
/// Se construye con la conexión ya abierta de la aplicación porque ésta es
/// la vía de la interfaz, con sesión iniciada. El arranque previo a la
/// autenticación construye el suyo con su propia conexión.
final evaluadorInstalacionProvider = Provider<EvaluadorInstalacion>((ref) {
  final rutas = ref.watch(appPathsProvider);
  return EvaluadorInstalacion(
    db: ref.watch(appDatabaseProvider),
    attachmentsDir: rutas.attachmentsDir,
    restorePendingDir: rutas.restorePendingDir,
    restorePendingMarkerFile: rutas.restorePendingMarkerFile,
    restoreOldDir: rutas.restoreOldDir,
  );
});

// ---------------------------------------------------------------------------
// Vías autorizadas
//
// Configurar la recuperación, crear un paquete, cambiar la frase y
// regenerar la clave de recuperación tocan la aplicación entera, igual que
// los respaldos de la Etapa 14C: los cuatro exigen Maestro con
// `exigirMaestro`, nunca un permiso de `PermisoUsuario`.
// ---------------------------------------------------------------------------

/// Convierte en resultado lo que de otro modo sería una excepción suelta.
///
/// Las tres operaciones de configuración escriben en la base de datos, y un
/// fallo ahí no puede llegar a la interfaz como una excepción sin manejar:
/// quien está configurando su recuperación vería la aplicación romperse en
/// medio de la operación en vez de un mensaje que le diga qué pasó.
///
/// No se registra el contenido del error más allá de su texto, y ese texto
/// nunca lleva la frase ni la clave: ninguna de las dos entra en los
/// mensajes de las capas de abajo.
Future<ResultadoRecuperacion> _sinExcepciones(Future<ResultadoRecuperacion> Function() operacion) async {
  try {
    return await operacion();
  } catch (e) {
    return RecuperacionErrorInesperado(e.toString());
  }
}

typedef ConfigurarRecuperacionAutorizado = Future<ResultadoRecuperacion> Function({required String frase});

/// Configura por primera vez y **persiste antes de devolver**.
///
/// El orden importa: si se devolviera la clave de recuperación y luego
/// fallara el guardado, alguien apuntaría en papel una clave que no abre
/// nada. Se guarda primero; sólo si eso salió bien se entrega el texto.
final configurarRecuperacionAutorizadoProvider = Provider<ConfigurarRecuperacionAutorizado>((ref) {
  return ({required String frase}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => _sinExcepciones(() async {
        if (frase.trim().length < ConfigurarRecuperacionUseCase.longitudMinimaFrase) {
          return RecuperacionFraseDemasiadoCorta(ConfigurarRecuperacionUseCase.longitudMinimaFrase);
        }
        final resultado = ref.read(configurarRecuperacionUseCaseProvider).ejecutar(frase: frase);
        await ref.read(configuracionRecuperacionRepositoryProvider).guardar(resultado.configuracion);
        ref.invalidate(configuracionRecuperacionProvider);
        return RecuperacionLista(resultado);
      }),
      RecuperacionNoAutorizada.new,
    );
  };
});

typedef CambiarFraseAutorizado =
    Future<ResultadoRecuperacion> Function({required String fraseActual, required String fraseNueva});

final cambiarFraseAutorizadoProvider = Provider<CambiarFraseAutorizado>((ref) {
  return ({required String fraseActual, required String fraseNueva}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => _sinExcepciones(() async {
        if (fraseNueva.trim().length < ConfigurarRecuperacionUseCase.longitudMinimaFrase) {
          return RecuperacionFraseDemasiadoCorta(ConfigurarRecuperacionUseCase.longitudMinimaFrase);
        }
        final repo = ref.read(configuracionRecuperacionRepositoryProvider);
        final actual = await repo.obtener();
        if (actual == null) return RecuperacionNoConfigurada();

        final nueva = ref
            .read(configurarRecuperacionUseCaseProvider)
            .cambiarFrase(actual: actual, fraseActual: fraseActual, fraseNueva: fraseNueva);
        if (nueva == null) return RecuperacionFraseIncorrecta();

        await repo.guardar(nueva);
        ref.invalidate(configuracionRecuperacionProvider);
        return RecuperacionFraseCambiada();
      }),
      RecuperacionNoAutorizada.new,
    );
  };
});

typedef RegenerarClaveRecuperacionAutorizado = Future<ResultadoRecuperacion> Function({required String frase});

final regenerarClaveRecuperacionAutorizadoProvider = Provider<RegenerarClaveRecuperacionAutorizado>((ref) {
  return ({required String frase}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => _sinExcepciones(() async {
        final repo = ref.read(configuracionRecuperacionRepositoryProvider);
        final actual = await repo.obtener();
        if (actual == null) return RecuperacionNoConfigurada();

        final resultado = ref
            .read(configurarRecuperacionUseCaseProvider)
            .regenerarClaveRecuperacion(actual: actual, frase: frase);
        if (resultado == null) return RecuperacionFraseIncorrecta();

        await repo.guardar(resultado.configuracion);
        ref.invalidate(configuracionRecuperacionProvider);
        return RecuperacionLista(resultado);
      }),
      RecuperacionNoAutorizada.new,
    );
  };
});

typedef CrearRespaldoPortableAutorizado =
    Future<ResultadoCrearPortable> Function({required String destino, required String frase});

final crearRespaldoPortableAutorizadoProvider = Provider<CrearRespaldoPortableAutorizado>((ref) {
  return ({required String destino, required String frase}) {
    return exigirMaestro(ref.read(permissionServiceProvider), () async {
      final configuracion = await ref.read(configuracionRecuperacionRepositoryProvider).obtener();
      if (configuracion == null) return PortableSinConfiguracion();
      return ref
          .read(crearRespaldoPortableUseCaseProvider)
          .ejecutar(
            destino: destino,
            frase: frase,
            configuracion: configuracion,
            appSchemaVersion: ref.read(appSchemaVersionProvider),
          );
    }, PortableErrorInesperado.new);
  };
});

typedef VerificarRespaldoPortableAutorizado =
    Future<ResultadoVerificarPortable> Function({
      required String rutaPaquete,
      String? frase,
      String? claveRecuperacionTexto,
    });

/// Verificar de verdad un paquete lo descifra por completo: la misma clase
/// de acceso que restaurarlo, así que exige el mismo Maestro. Mirar sólo
/// la cabecera es otra cosa y va sin envoltura, más abajo.
final verificarRespaldoPortableAutorizadoProvider = Provider<VerificarRespaldoPortableAutorizado>((ref) {
  return ({required String rutaPaquete, String? frase, String? claveRecuperacionTexto}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref
          .read(verificarRespaldoPortableUseCaseProvider)
          .ejecutar(
            rutaPaquete: rutaPaquete,
            appSchemaVersionActual: ref.read(appSchemaVersionProvider),
            frase: frase,
            claveRecuperacionTexto: claveRecuperacionTexto,
          ),
      PortableVerificarErrorInesperado.new,
    );
  };
});

/// Mirar la cabecera de un paquete: fecha, versión y qué puertas tiene.
///
/// Va **sin** `exigirMaestro`, y es deliberado. No hace falta ninguna
/// credencial para leerla, no descifra nada, y es lo único que se puede
/// ofrecer en una instalación vacía, donde todavía no existe usuario que
/// pudiera autorizar. Nunca dice "verificado": eso exige haber recorrido
/// el paquete entero.
typedef InspeccionarPaquetePortable = Future<InformacionPortable> Function({required String rutaPaquete});

final inspeccionarPaquetePortableProvider = Provider<InspeccionarPaquetePortable>((ref) {
  return ({required String rutaPaquete}) =>
      ref.read(verificarRespaldoPortableUseCaseProvider).inspeccionar(rutaPaquete: rutaPaquete);
});

// ---------------------------------------------------------------------------
// Restaurar: la compuerta aparte
//
// Ver `autorizar_restauracion_portable.dart` para el razonamiento. Aquí
// sólo se aplica: se pregunta primero en qué estado está la instalación y
// se exige Maestro salvo cuando no hay absolutamente nada que perder.
// ---------------------------------------------------------------------------

typedef PrepararRestauracionPortableAutorizado =
    Future<ResultadoPrepararPortable> Function({
      required String rutaPaquete,
      String? frase,
      String? claveRecuperacionTexto,
    });

final prepararRestauracionPortableAutorizadoProvider = Provider<PrepararRestauracionPortableAutorizado>((ref) {
  return ({required String rutaPaquete, String? frase, String? claveRecuperacionTexto}) async {
    Future<ResultadoPrepararPortable> preparar() => ref
        .read(coordinadorRestauracionPortableProvider)
        .preparar(
          rutaPaquete: rutaPaquete,
          appSchemaVersionActual: ref.read(appSchemaVersionProvider),
          frase: frase,
          claveRecuperacionTexto: claveRecuperacionTexto,
        );

    // Si el estado del disco no se puede leer, no se asume lo cómodo: se
    // trata como instalación con datos, que es la lectura prudente.
    EstadoInstalacion estado;
    try {
      estado = await ref.read(evaluadorInstalacionProvider).evaluar();
    } catch (_) {
      estado = EstadoInstalacion.indeterminada;
    }

    return switch (puertaSegunInstalacion(estado)) {
      PuertaRestauracionPortable.sinCredencial => preparar(),
      PuertaRestauracionPortable.exigeMaestro => exigirMaestro(
        ref.read(permissionServiceProvider),
        preparar,
        RestauracionPortableNoAutorizada.new,
      ),
    };
  };
});

/// Fase 2, en el arranque. No lleva compuerta de autorización y **no puede
/// llevarla**: se ejecuta antes de que exista una sesión, sobre una
/// decisión que un Maestro ya tomó cuando dejó el marcador. Lo que la
/// protege no es un permiso sino el marcador mismo: sin él, esto no hace
/// nada (ver `SinRestauracionPortablePendiente`).
final aplicarRestauracionPortableProvider = Provider<Future<ResultadoAplicarPortable> Function()>((ref) {
  return () => ref.read(coordinadorRestauracionPortableProvider).aplicarYConfirmar();
});
