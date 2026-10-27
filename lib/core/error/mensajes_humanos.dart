import 'failure.dart';

/// Traduce un [Failure] a **una frase que una persona puede leer y usar**.
///
/// ## Por qué vive en `core/error/` y ya no en la pantalla de entrada
///
/// Nació en `features/usuarios/web/` porque el login fue la primera pantalla de la web,
/// y se quedó ahí hasta C1. Lo que lo movió es que **su asunto es el `Failure`**, no el
/// login: traduce fallos para toda la web, y desde C1 lo necesitan dos features. Con el
/// archivo dentro de una, la segunda tenía que importar de la primera —«Comercial
/// importa de Organización»— o copiar las frases, que es cómo dos pantallas acaban
/// explicando el mismo 402 de dos maneras.
///
/// POR QUÉ EXISTE Y NO SE MUESTRA `failure.message` TAL CUAL. Los mensajes de los
/// `Failure` están escritos para quien programa: nombran el transporte, el contrato
/// y los campos que faltan. «La respuesta de autenticación no trae: accessToken» es
/// exacta y es inútil en una pantalla de entrada.
///
/// LA REGLA DE ESTE ARCHIVO, y es la que hay que respetar al añadir casos:
///
///   1. **qué pasó**, en lenguaje de negocio;
///   2. **qué puede hacer** quien lo lee, cuando puede hacer algo;
///   3. **nada más**: ni código, ni nombre de clase, ni `statusCode`, ni URL.
///
/// 🚫 **NO DICE SI EL CORREO EXISTE.** El backend responde lo mismo para una
/// contraseña equivocada y para una cuenta que no existe —un solo
/// `credenciales_invalidas`— precisamente para no ser el oráculo que permite
/// averiguar quién tiene cuenta. Separarlos aquí tiraría esa defensa desde el
/// cliente.
abstract final class MensajesHumanos {
  /// El mensaje del fallo de un **inicio de sesión**.
  ///
  /// Los cuatro desenlaces del backend se distinguen porque **no se arreglan igual**:
  /// escribir otra vez la contraseña, esperar, buscar un correo o hablar con alguien.
  /// Colapsarlos en «no se pudo entrar» dejaría a quien lo lee sin saber qué hacer.
  static String deLogin(Failure fallo) {
    if (fallo is ApiHttpFailure) {
      switch (fallo.codigo) {
        case 'credenciales_invalidas':
          return 'Correo o contraseña incorrectos.';

        case 'cuenta_bloqueada':
          // 423. El backend bloquea tras varios intentos fallidos. Se dice que es
          // temporal, porque sin eso se lee como «me cerraron la cuenta».
          return 'Hubo demasiados intentos fallidos. Espera unos minutos y '
              'vuelve a intentarlo.';

        case 'email_no_verificado':
          return 'Todavía no has confirmado tu correo. Busca el mensaje que te '
              'enviamos y abre el enlace.';

        case 'cuenta_suspendida':
          return 'Esta cuenta está suspendida. Pide ayuda a quien administra tu '
              'empresa.';
      }

      // El limitador de peticiones, que no trae código propio. No es lo mismo que
      // `cuenta_bloqueada` —ahí la cuenta está cerrada un rato; aquí es el servidor
      // frenando la ráfaga— pero para quien lo lee la salida es la misma: esperar.
      if (fallo.statusCode == 429) {
        return 'Demasiados intentos seguidos. Espera un momento y vuelve a '
            'intentarlo.';
      }

      if (fallo.statusCode >= 500) return _servidorConProblemas;

      // Un 4xx que no reconocemos. **No se cuela el mensaje del servidor**: puede
      // venir de un proxy y estar en inglés, o nombrar un campo del contrato.
      return _noSePudoEntrar;
    }

    return _deTransporte(fallo) ?? _noSePudoEntrar;
  }

  /// El mensaje del fallo que impide **arrancar**.
  ///
  /// Hoy sólo puede ser uno —`ApiConfig.resolve()` devuelve siempre
  /// `ApiConfigFailure`—, y aun así pasa por el traductor común en vez de devolver
  /// la constante: si mañana el arranque valida algo más, el caso nuevo cae en su
  /// sitio en lugar de mostrar el mensaje de la configuración.
  static String deArranque(Failure fallo) =>
      _deTransporte(fallo) ?? 'La aplicación no pudo arrancar.';

  /// El mensaje del fallo al **comprobar una sesión guardada**.
  ///
  /// SEPARADO DE [deEmpresa] A PROPÓSITO, y no por simetría. Aquí sólo pueden llegar
  /// fallos de transporte: un 401 no pasa por este camino —el gestor lo trata como
  /// cierre definitivo y publica `NoAutenticado`—, así que lo que queda es red,
  /// plazo o un 5xx.
  ///
  /// Usar [deEmpresa] para esto era un error con una consecuencia concreta: ante un
  /// **404 de un proxy** respondería «esta empresa ya no está disponible para ti»,
  /// que no tiene nada que ver con lo que pasó y manda a buscar un problema de
  /// permisos donde hay uno de red.
  static String deSesion(Failure fallo) =>
      _deTransporte(fallo) ?? _noSeComproboLaSesion;

  /// El mensaje del fallo al **resolver la empresa** o al pedir sus datos.
  static String deEmpresa(Failure fallo) {
    if (fallo is ApiHttpFailure) {
      // 402 — la suscripción está restringida. **No es una revocación ni un error
      // de quien entra**, y el mensaje tiene que dejarlo claro: lo que falta es un
      // pago, y no lo resuelve esta persona desde esta pantalla.
      if (fallo.statusCode == 402) {
        return 'Esta empresa tiene su suscripción limitada. Puedes consultar la '
            'información, pero no guardar cambios.';
      }

      if (fallo.codigo == 'module_disabled') {
        return 'Esta parte no está incluida en lo que tu empresa tiene '
            'contratado.';
      }

      if (fallo.codigo == 'permission_missing') {
        return 'No tienes permiso para ver esto. Pídelo a quien administra tu '
            'empresa.';
      }

      if (fallo.statusCode == 404) {
        return 'Esta empresa ya no está disponible para ti.';
      }

      if (fallo.statusCode >= 500) return _servidorConProblemas;

      return 'No se pudo abrir la empresa.';
    }

    // La sesión se cayó entre medias. Se dice qué hacer, que es volver a entrar.
    if (fallo is ApiSinSesionFailure) {
      return 'Tu sesión se cerró. Vuelve a iniciar sesión.';
    }

    return _deTransporte(fallo) ?? 'No se pudo abrir la empresa.';
  }

  /// El rechazo de una MUTACIÓN, dicho para quien lo lee.
  ///
  /// ## Por qué no basta con el mensaje del servidor
  ///
  /// Porque en las mutaciones hay **dos familias de rechazo y sólo una se explica bien
  /// desde el servidor**:
  ///
  ///  · **El de negocio** —«Tiene 3 puesto(s) registrado(s)»— lo escribe el servidor y es
  ///    el bueno: es el único que sabe el conteo, y el conteo es lo que cambia qué hace la
  ///    persona. Ése pasa tal cual.
  ///  · **El de autorización** —402, módulo apagado, permiso que falta— llega en
  ///    vocabulario del backend. «La suscripción de la organización no permite la operación
  ///    normal» es exacto y no le dice a nadie qué hacer.
  ///
  /// ## Lo que esto cierra (D-46)
  ///
  /// La web **no escuchaba el 402**: una suscripción limitada mostraba ese texto del
  /// servidor en una barra de error, indistinguible de un fallo cualquiera. El mensaje
  /// humano ya existía —en [deEmpresa], para cuando falla ABRIR la empresa— y no lo usaba
  /// nadie al GUARDAR, que es justo cuando el 402 ocurre.
  ///
  /// NO SE ADIVINA POR ADELANTADO desde `CompanyContext.restricted`: lo que manda es la
  /// respuesta del servidor, que es quien tiene la verdad en el momento del intento. El
  /// estado del contexto sirve para avisar antes —y ése es otro acto—, nunca para suponer
  /// que una escritura va a fallar.
  static String deMutacion(Failure fallo) {
    if (fallo is ApiHttpFailure) {
      if (fallo.statusCode == 402) {
        return 'La suscripción de esta empresa está limitada: puedes consultar la '
            'información, pero no guardar cambios. Lo resuelve quien administra el pago.';
      }

      if (fallo.codigo == 'module_disabled') {
        return 'Esta parte no está incluida en lo que tu empresa tiene contratado, así '
            'que no se puede modificar.';
      }

      if (fallo.codigo == 'permission_missing') {
        return 'No tienes permiso para hacer este cambio. Pídelo a quien administra tu '
            'empresa.';
      }

      if (fallo.statusCode >= 500) return _servidorConProblemas;

      // EL RESTO ES EL MENSAJE DEL SERVIDOR, que para un rechazo de negocio es el mejor
      // texto que existe. Vacío sólo pasaría con un contrato roto, y entonces se dice algo
      // en lugar de mostrar una barra sin texto.
      return fallo.message.trim().isEmpty ? 'No se pudo guardar el cambio.' : fallo.message;
    }

    if (fallo is ApiSinSesionFailure) {
      return 'Tu sesión se cerró. Vuelve a iniciar sesión.';
    }

    return _deTransporte(fallo) ?? 'No se pudo guardar el cambio.';
  }

  /// Lo que no es una respuesta del servidor: red, plazo, configuración y contrato.
  ///
  /// Devuelve `null` cuando el fallo no es de esta familia, para que quien llama
  /// ponga su propio texto por omisión en vez de recibir uno genérico de aquí.
  static String? _deTransporte(Failure fallo) => switch (fallo) {
    // ESTE CASO YA COSTÓ MEDIA HORA DE DIAGNÓSTICO, y conviene que conste.
    //
    // En el navegador, un origen que la API no autoriza (CORS) y un servidor
    // apagado llegan **idénticos**: `XMLHttpRequest error`. El navegador oculta
    // la diferencia a propósito, así que el cliente **no puede** distinguirlas y
    // cualquier mensaje que lo intente mentirá la mitad de las veces.
    //
    // Por eso aquí se dice lo único que es cierto en los dos casos, y **no se
    // reenvía el texto del fallo**: en web dice «la conexión se interrumpió»,
    // que sugiere que empezó, cuando lo normal es que ni saliera.
    ApiSinConexionFailure() =>
      'No se pudo contactar con el servidor. Revisa tu conexión e inténtalo de '
          'nuevo.',

    ApiTimeoutFailure() =>
      'El servidor tardó demasiado en responder. Inténtalo de nuevo.',

    // Falta `--dart-define=SEVENTRA_API_BASE_URL`, o está mal escrito. Es un error
    // de cómo se compiló esta aplicación: quien lo lee no puede arreglarlo, así que
    // el mensaje no le pide nada, le dice a quién avisar.
    ApiConfigFailure() =>
      'Esta aplicación no está configurada para conectarse a ningún servidor. '
          'Avisa a quien la instaló.',

    // El servidor contestó algo que no cuadra con lo esperado. Puede ser un proxy
    // devolviendo una página de error, o un desacuerdo de versión entre esta
    // aplicación y la API.
    ApiJsonInvalidoFailure() || ApiRespuestaInesperadaFailure() =>
      'El servidor respondió algo que no entendimos. Si vuelve a pasar, avisa a '
          'quien instaló la aplicación.',

    _ => null,
  };

  static const String _noSePudoEntrar =
      'No se pudo iniciar sesión. Inténtalo de nuevo.';

  static const String _servidorConProblemas =
      'El servidor tuvo un problema. Inténtalo de nuevo en unos minutos.';

  /// **No dice «tu sesión expiró»**, porque no es eso: la credencial sigue siendo
  /// buena y el gestor no la ha borrado. Lo que no se pudo es preguntar.
  static const String _noSeComproboLaSesion =
      'No se pudo comprobar tu sesión. Inténtalo de nuevo.';
}
