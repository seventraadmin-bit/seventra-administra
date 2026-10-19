import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:http/http.dart' as http;

import 'core/api/api_client.dart';
import 'core/api/api_client_autenticado.dart';
import 'core/auth/almacen_sesion_remota_web.dart';
import 'core/auth/auth_api.dart';
import 'core/auth/gestor_de_sesion.dart';
import 'core/company/almacen_company_recordada.dart';
import 'core/company/company_api.dart';
import 'core/company/gestor_de_company.dart';
import 'core/config/api_config.dart';
import 'core/error/result.dart';
import 'core/logging/app_logger.dart';
import 'features/organizacion/web/datos/areas_repositorio_http.dart';
import 'features/organizacion/web/datos/sucursales_repositorio_http.dart';
import 'features/usuarios/web/datos/usuarios_repositorio_http.dart';
import 'features/usuarios/web/marca_seventra.dart';
import 'features/usuarios/web/mensajes_humanos.dart';
import 'features/usuarios/web/porton_web.dart';

/// El arranque de **Administra en el navegador**.
///
/// Se compila con `-t lib/main_web.dart`, y es un punto de entrada SEPARADO de
/// `lib/main.dart` a propósito. La razón es medible: `app/bootstrap.dart` abre Drift,
/// que importa `dart:ffi`, y resuelve rutas de archivos con `dart:io`. Ninguno de los
/// dos existe en el navegador, así que compartir el arranque no es «más limpio»: es
/// imposible.
///
/// **Esta es la composición completa, y no hay Riverpod.** `core/api/api_providers.dart`
/// importa `core/di/providers.dart`, que es el archivo raíz que arrastra medio
/// proyecto —base local incluida—; usarlo aquí traería a la web todo lo que la
/// mudanza todavía no ha movido. Son once objetos en una función, se leen de arriba
/// abajo, y cuando el árbol web crezca lo suficiente para necesitar un contenedor, se
/// pone entonces.
///
/// LO QUE NO SE DESECHA, y conste que es una decisión: los dos gestores viven
/// mientras viva la pestaña, así que no hay `dispose`. En el escritorio el contenedor
/// de Riverpod los suelta porque allí hay pruebas que crean y destruyen contenedores;
/// aquí el único final posible es cerrar la página, y el navegador se lleva todo.
void main() {
  // ANTES DE CUALQUIER PLUGIN. `flutter_secure_storage` y `shared_preferences`
  // hablan por un canal de plataforma, y sin el enlace inicializado la primera
  // llamada falla con un error que no menciona esta línea.
  WidgetsFlutterBinding.ensureInitialized();

  final logger = AppLogger.console();

  _nuncaLaPantallaRoja(logger);

  // LA CONFIGURACIÓN SE RESUELVE ANTES DE `runApp`, y un fallo aquí NO arranca la
  // aplicación de verdad: muestra el motivo y se queda ahí.
  //
  // Es exactamente lo que `ApiConfig` pide en su documentación —«una URL mal
  // configurada tiene que impedir el arranque con un mensaje legible»— y lo que
  // evita el peor caso: una compilación sin `--dart-define` abre, parece funcionar y
  // falla en el login, donde el síntoma no se parece a su causa.
  final configuracion = ApiConfig.resolve();

  switch (configuracion) {
    case Err(:final failure):
      logger.error('La aplicación web no puede arrancar: ${failure.message}');

      runApp(
        _AdministraWeb(
          child: _PantallaDeArranqueFallido(
            // El mensaje del `Failure` nombra el `--dart-define`, que es técnico
            // pero también es exactamente lo que hay que corregir. Así que se
            // muestran los dos: la frase para quien lo lee, y el detalle para quien
            // lo arregla.
            mensaje: MensajesHumanos.deArranque(failure),
            detalle: failure.message,
          ),
        ),
      );

      return;

    case Ok(value: final config):
      logger.info('Administra web contra ${config.baseUrl}');

      // UN SOLO `http.Client` PARA TODA LA APLICACIÓN. En web resuelve a
      // `BrowserClient`, que es quien convierte un fallo de red —o un origen que la
      // API no autoriza— en la `ClientException` que `ApiClient` sí traduce.
      final transporte = http.Client();

      final cliente = ApiClient(
        config: config,
        cliente: transporte,
        logger: logger,
      );

      // EL ORDEN DE ESTAS TRES LÍNEAS ES EL ÚNICO POSIBLE, y vale decir por qué:
      // `AuthApi` toma el cliente DESNUDO, porque el decorador autenticado le pide
      // el token al gestor y el gestor llama a `AuthApi`. Si `AuthApi` usara el
      // decorador, pedir un token necesitaría un token.
      final gestorDeSesion = GestorDeSesion(
        api: AuthApi(cliente),
        almacen: const AlmacenSesionRemotaWeb(),
        logger: logger,
      );

      final autenticado = ApiClientAutenticado(
        cliente: cliente,
        gestor: gestorDeSesion,
      );

      final gestorDeCompany = GestorDeCompany(
        api: CompanyApi(autenticado),
        almacen: const AlmacenCompanyRecordadaPreferencias(),
        logger: logger,
      );

      runApp(
        _AdministraWeb(
          child: PortonWeb(
            gestorDeSesion: gestorDeSesion,
            gestorDeCompany: gestorDeCompany,
            repositorioDeAreas: AreasRepositorioHttp(autenticado),
            repositorioDeSucursales: SucursalesRepositorioHttp(autenticado),
            repositorioDeUsuarios: UsuariosRepositorioHttp(autenticado),
          ),
        ),
      );
  }
}

/// Sustituye la **pantalla roja de Flutter** por un aviso que una persona puede leer.
///
/// QUÉ ES LA PANTALLA ROJA Y POR QUÉ NO PUEDE SALIR AQUÍ. Cuando el `build` de un
/// widget lanza, Flutter pinta en su lugar un recuadro rojo con el mensaje de la
/// excepción y, en una build de release, un rectángulo gris sin explicación. Para
/// quien programa es información; para quien usa la aplicación es una avería
/// incomprensible —y además enseña por dentro nombres de clases y de campos—.
///
/// **No tapa el error: lo recoloca.** El fallo sigue yendo al registro completo, con
/// su traza, que es donde sirve. Lo que cambia es lo que ve la persona.
///
/// SON DOS CAMINOS DISTINTOS Y HACEN FALTA LOS DOS:
///
///  · [ErrorWidget.builder] cubre lo que falla **construyendo** la interfaz —el caso
///    de `context.colors` sin la extensión del tema—, y es lo único que puede
///    sustituir ese recuadro;
///  · [FlutterError.onError] cubre lo que falla **fuera** de un `build` y no tiene
///    widget que sustituir; ahí sólo cabe registrarlo.
void _nuncaLaPantallaRoja(AppLogger logger) {
  ErrorWidget.builder = (detalles) {
    // Al registro va todo lo que hay: el error, su origen y la traza. Es lo
    // que permite arreglarlo sin pedirle a nadie que describa un recuadro rojo.
    logger.error(
      'Fallo al construir la interfaz web: ${detalles.exceptionAsString()}',
      detalles.exception,
      detalles.stack,
    );

    return const _AlgoSalioMal();
  };

  FlutterError.onError = (detalles) {
    FlutterError.presentError(detalles);

    logger.error(
      'Error de Flutter fuera de un build: ${detalles.exceptionAsString()}',
      detalles.exception,
      detalles.stack,
    );
  };
}

/// Lo que se ve en lugar del recuadro rojo.
///
/// **No tiene botón de reintentar**, y es deliberado: lo que falló es la construcción
/// de esta parte de la pantalla, así que volver a construirla volvería a fallar. Lo
/// único que de verdad rehace el estado es recargar, y eso ya sabe hacerlo cualquiera
/// que use un navegador.
///
/// No dice qué clase lanzó ni qué campo faltaba: eso está en el registro.
class _AlgoSalioMal extends StatelessWidget {
  const _AlgoSalioMal();

  @override
  Widget build(BuildContext context) => Container(
    // COLORES LITERALES Y NO `context.colors`, a propósito: este widget existe
    // precisamente para cuando el tema o algo de su alrededor está mal, así que no
    // puede depender de nada que pueda faltar. Si él mismo lanzara, Flutter volvería
    // a la pantalla roja.
    color: const Color(0xFFF7F6F2),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(24),
    child: const Text(
      'Algo salió mal. Vuelve a intentarlo.',
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      style: TextStyle(
        color: Color(0xFF0F1B2D),
        fontSize: 15,
        height: 1.4,
        // SIN `decoration: none` el texto suelto de un `ErrorWidget` sale SUBRAYADO
        // en amarillo: fuera de un `Material`, el estilo por omisión de Flutter es
        // el de depuración.
        decoration: TextDecoration.none,
      ),
    ),
  );
}

/// El envoltorio de la aplicación.
///
/// **Sin `MaterialApp.router`**, que es lo que usa el escritorio. Aquí no hay rutas
/// todavía: lo que se ve depende de la sesión y de la empresa, no de la URL, y
/// publicar rutas antes de tener pantallas dentro prometería direcciones que la
/// sesión quizá no permite. El router entra con la segunda pantalla de la mudanza.
class _AdministraWeb extends StatelessWidget {
  const _AdministraWeb({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    // Lo que el navegador pone en la pestaña. **SEVENTRA y no RISEG ONE**: es la
    // misma decisión que la pantalla de entrada.
    onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
    debugShowCheckedModeBanner: false,
    // ⚠️ NO SE CONSTRUYE UN `ThemeData` A MANO AQUI. La razon esta en
    // `MarcaSeventra.tema()`, y resumida: el Design System exige la extension
    // `AppColorScheme`, y sin ella la primera linea del `build` de Areas lanza
    // «Unexpected null value». Medido.
    theme: MarcaSeventra.tema(),
    // LOS WIDGETS DEL ESCRITORIO QUE LA WEB REUTILIZA LEEN SUS TEXTOS DE AQUI.
    //
    // `AppSidebar`, `ModulePlaceholderScreen` y el login llaman a
    // `AppLocalizations.of(context)!`, que sin estos delegados devuelve nulo y
    // lanza. Son los MISMOS que registra `RisegOneApp` en el escritorio: la web
    // no tiene su propio juego de textos, usa el del producto.
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

/// Lo que se ve cuando la aplicación no está configurada para hablar con ningún
/// servidor. **No tiene reintentar**: no hay nada que reintentar, el valor se fija al
/// compilar.
class _PantallaDeArranqueFallido extends StatelessWidget {
  const _PantallaDeArranqueFallido({
    required this.mensaje,
    required this.detalle,
  });

  final String mensaje;
  final String detalle;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: MarcaSeventra.fondo,
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: LogotipoSeventra(alto: 28)),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: MarcaSeventra.borde),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      mensaje,
                      style: const TextStyle(
                        color: MarcaSeventra.tinta,
                        fontSize: 15,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: MarcaSeventra.fondo,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        detalle,
                        style: const TextStyle(
                          color: MarcaSeventra.suave,
                          fontSize: 12.5,
                          height: 1.4,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
