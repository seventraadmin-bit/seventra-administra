/// El router de Administra en la web: **quién puede estar dónde**.
///
/// ## Por qué entra, y qué deuda paga
///
/// Hasta C1 el portón guardaba a mano tres cosas que son, literalmente, una dirección:
/// qué apartado, qué pestaña, y qué se había abierto dentro de la pestaña. La tercera
/// no se puede deducir desde arriba —vive dentro de la pantalla—, así que la pantalla
/// **avisaba hacia arriba con un callback** para que el rastro no mintiera. Eso era la
/// deuda **D-39**: no que la vía estuviera mal escrita, sino que existiera. Quien sabe
/// dónde estás es la dirección.
///
/// ## La regla que el router NO rompe
///
/// > **Lo que se ve depende de la sesión y de la empresa, no de la URL.**
///
/// El router no la cambia: la implementa. Tres consecuencias que no se negocian:
///
///  1. **Una dirección escrita a mano no concede nada.** Mientras no haya empresa
///     activa, [redireccion] no toca la dirección y el portón sigue decidiendo qué se
///     ve —login, selector, espera o aviso—. Cuando la empresa abre, la dirección
///     pedida se recupera **sólo si esta sesión la puede ver**.
///  2. **Los permisos siguen saliendo del servidor.** Una ruta visible no es un
///     permiso: cada pantalla recibe sus capacidades del contexto que confirmó el
///     servidor. El router decide *dónde estás*, nunca *qué puedes*.
///  3. **La empresa no va en la URL** (E1-B). Ver [UbicacionWeb].
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/design_system_web.dart';
import '../../core/trabajo_sin_guardar/guardia_de_salida.dart';
import 'apartados_web.dart' as apartados;
import 'rutas_web.dart';

/// A dónde hay que ir, o nulo para quedarse donde está.
///
/// **ES PURA Y SE PRUEBA SOLA**, y por eso vive aparte del [GoRouter]: es la regla de
/// §7 del diseño —las cinco direcciones raras— y comprobarla no debería necesitar
/// bombear una pantalla.
///
/// - `esMaestro` y `permisos` son **los del contexto que confirmó el servidor**. Con
///   `null` significa que todavía no hay empresa abierta, y entonces **no se redirige
///   nada**: el portón está enseñando el login, el selector o una espera, y moverle la
///   dirección debajo sólo cambiaría la barra del navegador.
String? redireccion(
  String direccion, {
  required bool? esMaestro,
  required Set<String>? permisos,
}) {
  if (esMaestro == null || permisos == null) return null;

  final primera = _primeraDireccion(esMaestro: esMaestro, permisos: permisos);

  // NINGÚN APARTADO VISIBLE: no hay a dónde mandar a nadie, y el portón ya tiene su
  // pantalla para eso —la bienvenida sin accesos—. Devolver una dirección inventada
  // haría un bucle de redirecciones.
  if (primera == null) return null;

  final ubicacion = leerUbicacion(direccion);

  // Una dirección que no es de ningún apartado —la raíz, o una errata— lleva al primer
  // apartado CON PANTALLA, que no es el primero del menú: Dashboard no está mudado, y
  // recibir a todo el mundo con un «Próximamente» haría pensar que no hay nada hecho.
  if (ubicacion == null) return primera;

  final apartado = apartados.apartados.firstWhere(
    (a) => a.ruta == ubicacion.apartado,
  );

  // UN APARTADO QUE ESTA SESIÓN NO VE lleva al primero que sí. No es un 404: la
  // dirección existe, lo que pasa es que no es para esta persona —o es de un módulo
  // que su empresa no contrató—, y las dos cosas se resuelven igual.
  if (apartados.queHacerCon(apartado, esMaestro: esMaestro, permisos: permisos) !=
      apartados.QueHacerConElApartado.seAbre) {
    return primera;
  }

  final visibles = apartados.pestanasPara(
    apartado,
    esMaestro: esMaestro,
    permisos: permisos,
  );

  // El apartado sin pestaña: se completa con la primera disponible, para que la
  // dirección diga siempre dónde estás.
  if (ubicacion.pestana == null) {
    final primeraPestana = apartados.primeraDisponible(visibles) ?? visibles.firstOrNull;

    return primeraPestana == null
        ? primera
        : direccionDe(apartado.ruta, primeraPestana.id);
  }

  // UNA PESTAÑA QUE ESTA SESIÓN NO VE —una de Maestro, sin serlo— lleva a la primera
  // visible DE SU APARTADO, no al primer apartado: quien pidió Configuración quería
  // Configuración, y echarlo a Organización sería perderle el sitio.
  final existe = visibles.any((p) => p.id == ubicacion.pestana);

  if (!existe) {
    final primeraPestana = apartados.primeraDisponible(visibles) ?? visibles.firstOrNull;

    return primeraPestana == null
        ? primera
        : direccionDe(apartado.ruta, primeraPestana.id);
  }

  return null;
}

/// La dirección con la que empieza una sesión: el primer apartado **con pantalla**.
String? _primeraDireccion({
  required bool esMaestro,
  required Set<String> permisos,
}) {
  final apartado = apartados.primerApartadoConPantalla(
    esMaestro: esMaestro,
    permisos: permisos,
  );

  if (apartado == null) return null;

  final pestana = apartados.primeraDisponible(
    apartados.pestanasPara(apartado, esMaestro: esMaestro, permisos: permisos),
  );

  return pestana == null ? apartado.ruta : direccionDe(apartado.ruta, pestana.id);
}

/// Qué se perdería, dicho para la pregunta.
///
/// **La frase genérica es el respaldo y no el caso normal.** La pone el formulario al
/// registrarse —«el expediente de la empresa», «el expediente de la sucursal Centro»—
/// porque es lo único que el router no puede saber; si no la diera, o si su cálculo
/// fallara, **la pregunta sale igual**: el nombre adorna, la pregunta protege el trabajo.
String _loQueSePierde(GuardiaDeSalida guardia) =>
    guardia.queSePierde ?? 'este formulario';

/// ¿Se puede salir de aquí sin tirar lo que alguien escribió? (D-56)
///
/// ## Por qué la pregunta vive en el router y NO en la pantalla
///
/// Hasta C1 la hacía la pantalla de Empresa, y estaba bien mientras salir pasara por ella.
/// Con la dirección como estado **cambiarla ya no pasa por la pantalla**: el botón «atrás»
/// del navegador, una pestaña del menú o un enlace pegado la mueven desde fuera. El
/// `onExit` de una ruta es **el único punto por el que pasan todos esos caminos**.
///
/// Y por eso la pantalla **dejó de preguntar**: con las dos, cancelar el expediente
/// preguntaba dos veces —la pantalla, y el router cuando la pantalla navegara—.
///
/// ⚠️ **NO SE SABE A DÓNDE VA.** go_router entrega el estado de la ruta que se **abandona**,
/// nunca la de destino, así que la pregunta no puede decir «si eliges administrar las
/// empresas…». Lo que sí nombra es **qué tiene cambios**, que sale del guardia.
///
/// **El caso frecuente no cuesta un frame:** sin nada que perder devuelve `true` de forma
/// síncrona, y go_router resuelve un `bool` sin esperar —comprueba `exitFuture is bool`—,
/// así que navegar por la aplicación sigue siendo inmediato.
Future<bool> seguroDeSalir(BuildContext context, GuardiaDeSalida guardia) async {
  if (!guardia.hayCambiosSinGuardar) return true;

  final confirmado = await RisegDialog.showConfirmation(
    context: context,
    title: '¿Salir sin guardar?',
    message: 'Tienes cambios sin guardar en ${_loQueSePierde(guardia)}.',
    confirmLabel: 'Salir sin guardar',
    cancelLabel: 'Seguir editando',
  );

  // CERRAR EL DIÁLOGO SIN ELEGIR —Esc, o tocar fuera— ES «NO SALGO». Es la postura segura:
  // de los dos errores posibles, quedarse donde estabas se arregla pulsando otra vez, y
  // salir se lleva el trabajo.
  return confirmado ?? false;
}

/// Arma el router con **una sola ruta que lo cubre todo**.
///
/// ## Por qué una y no una por pantalla
///
/// Quien sabe construir cada pantalla es el portón: tiene los repositorios, el
/// contexto que confirmó el servidor y la caché de logotipos, y es **el único sitio
/// que lee `isMaestro` y los permisos efectivos**. Repartir eso en veinte
/// constructores de ruta obligaría a pasarle el contexto a cada uno por un
/// `InheritedWidget`, y entonces habría dos sitios decidiendo qué se ve — que es
/// exactamente lo que el portón vino a evitar.
///
/// Así que el router hace lo que sólo él puede hacer —la dirección, el historial del
/// navegador y el guardia de §7— y el portón sigue haciendo lo que ya hacía bien.
///
/// `refreshListenable` son **los dos gestores**: sin él, [redireccion] se evaluaría
/// con la sesión a medio resolver y se quedaría ahí, porque nada volvería a
/// preguntarle al abrir la empresa.
GoRouter construirRouterWeb({
  required Widget porton,
  required Listenable gestores,
  required ({bool esMaestro, Set<String> permisos})? Function() autoridad,
  required GuardiaDeSalida guardia,
  String initialLocation = '/',
}) => GoRouter(
  initialLocation: initialLocation,
  refreshListenable: gestores,
  redirect: (context, state) {
    final quien = autoridad();

    return redireccion(
      state.uri.path,
      esMaestro: quien?.esMaestro,
      permisos: quien?.permisos,
    );
  },
  routes: [
    // ⚠️ `ShellRoute` Y NO DOS RUTAS SUELTAS, y la diferencia costó un fallo medido.
    //
    // Con dos `GoRoute` hermanas —una para `/` y otra para lo demás—, moverse de la
    // primera a la segunda **cambia de ruta**, así que Flutter monta una página nueva y
    // el portón pierde su `State`: la caché de logotipos, la autoridad de Organization
    // ya leída, el «ya pedí la empresa» y el oyente del ciclo de vida. El síntoma fue
    // una prueba de P2 —al volver la pestaña al frente el contexto se pone al día— que
    // dejó de ver la segunda lectura, porque el portón que la pedía ya no era el mismo.
    //
    // Una `ShellRoute` existe justo para esto: **su widget se conserva** mientras las
    // rutas de dentro cambian.
    ShellRoute(
      builder: (_, _, _) => porton,
      routes: [
        // ───────────────────────────────────────────────────────────────────────
        // D-56 · **TODAS LAS RUTAS LLEVAN `onExit`**, y es una reversa medida
        // ───────────────────────────────────────────────────────────────────────
        //
        // LAS RUTAS DE DENTRO SÓLO MARCAN LA DIRECCIÓN, y por eso no construyen nada:
        // quien pinta es el portón, que ignora el hijo. La de `/` hace falta porque
        // `/:resto(.*)` no casa con `/` a secas.
        //
        // ## 🚫 LO QUE ESTABA ANTES, Y POR QUÉ SE CAYÓ
        //
        // Hasta el 11 de noviembre de 2026 el `onExit` estaba **sólo en tres rutas con
        // formulario** —el expediente de la empresa, el de una sucursal y la edición de
        // un cliente—, con este argumento escrito: «un `onExit` que se dispara en cada
        // navegación y tiene que decidir *¿esta importa?* es peor que uno que sólo
        // existe donde hay algo que perder».
        //
        // El argumento era bonito y **la regla que dejaba era la mala**: «cada formulario
        // nuevo añade su ruta aquí». El dueño probando C2 escribió un nombre en
        // `/comercial/servicios/nuevo`, cambió a la pestaña Clientes y **el alta se fue
        // sin preguntar**: la pantalla sí se registraba en el guardia —el candado de
        // `guardia_cubre_los_formularios_test.dart` lo comprobaba— pero **su ruta no
        // estaba en esta lista**, y una ruta sin `onExit` no pregunta. Lo mismo pasaba
        // con el expediente de un servicio.
        //
        // ⚠️ **EL CANDADO DE D-56 MEDÍA MEDIA REGLA.** «El formulario se registra» y
        // «su dirección pregunta» son dos cosas, y la primera verde con la segunda roja
        // se ve igual que todo bien.
        //
        // ## Por qué el comodín SÍ puede llevarlo
        //
        // Porque **quien decide no es la dirección: es el guardia**, y sin nadie
        // registrado con cambios [seguroDeSalir] devuelve `true` sin pintar nada. El
        // miedo de antes era «preguntaría entre pestañas con un panel sucio abierto sin
        // que nadie salga de un formulario», y ese estado **no existe**: si el guardia
        // está sucio hay un formulario montado con algo escrito, y cambiar de dirección
        // lo desmonta —las hojas modales incluidas, que `SeCierraAlCambiarLaDireccion`
        // cierra—. Es decir: sí había algo que perder, y antes se perdía callado.
        //
        // ⚠️ **TIENEN QUE SER `GoRoute`.** Un `onExit` en la `ShellRoute` compila, no se
        // llama nunca y no avisa: el recorrido de go_router recoge sólo los `GoRoute`.
        //
        // LA REGLA QUE ESTO DEJA: **ninguna ruta nueva se olvida, porque no hay nada que
        // acordarse de añadir.** Y lo vigila `rutas_con_salida_vigilada_test.dart`, que
        // lee este archivo y exige `onExit` en cada `GoRoute`.
        GoRoute(
          path: '/',
          builder: (_, _) => const SizedBox.shrink(),
          onExit: (context, _) => seguroDeSalir(context, guardia),
        ),
        GoRoute(
          path: '/:resto(.*)',
          builder: (_, _) => const SizedBox.shrink(),
          onExit: (context, _) => seguroDeSalir(context, guardia),
        ),
      ],
    ),
  ],
);

/// Un [Listenable] que se dispara cuando cualquiera de los dos cambia.
///
/// Existe porque `GoRouter` acepta **uno** y aquí hay dos estados que deciden lo
/// mismo: quién eres y con qué empresa. `Listenable.merge` ya lo hace, y esto le pone
/// el nombre para que en el arranque se lea qué se está escuchando.
Listenable losDosGestores(Listenable sesion, Listenable empresa) =>
    Listenable.merge([sesion, empresa]);
