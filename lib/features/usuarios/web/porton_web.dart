import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell/rutas_web.dart' as rutas;
import '../../../core/auth/gestor_de_sesion.dart';
import '../../../core/auth/sesion_remota.dart';
import '../../../core/company/company_remota.dart';
import '../../../core/company/gestor_de_company.dart';
// D-56 · EL AVISO DE `beforeunload` SÓLO EXISTE EN EL NAVEGADOR, y esta aplicación
// también compila para Windows: la importación condicional deja el escritorio —y la
// suite, que corre en la VM— con la versión que no hace nada. Es el mismo patrón que
// `candado_entre_pestanas_web.dart` ya usa para la Web Locks API.
import '../../../core/trabajo_sin_guardar/aviso_de_salida.dart';
import '../../../core/trabajo_sin_guardar/aviso_de_salida_web.dart'
    if (dart.library.io) '../../../core/trabajo_sin_guardar/aviso_de_salida_io.dart';
import '../../../core/trabajo_sin_guardar/guardia_de_salida.dart';
import '../../../core/company/logotipos_de_empresa.dart';
import '../../../core/error/failure.dart';
import '../../../core/error/mensajes_humanos.dart';
import '../../../app/shell/apartados_web.dart' as apartados;
import '../../../app/shell/shell_destinations.dart';
import '../../../core/design_system/design_system_web.dart';
import '../../../core/company/autoridad_de_organizacion.dart';
import '../../comercial/web/datos/clientes_repositorio_http.dart';
import '../../comercial/web/presentation/clientes_web_screen.dart';
import '../../organizacion/web/datos/areas_repositorio_http.dart';
import '../../organizacion/web/datos/empresas_repositorio_http.dart';
import '../../organizacion/web/datos/expedientes_repositorio_http.dart';
import '../../organizacion/web/datos/logotipo_repositorio_http.dart';
import '../../organizacion/web/datos/puestos_repositorio_http.dart';
import '../../organizacion/web/datos/sucursales_repositorio_http.dart';
import '../../organizacion/web/modelos/organizacion_propia.dart';
import '../../organizacion/web/presentation/areas_web_screen.dart';
import '../../organizacion/web/presentation/empresas_web_screen.dart';
import '../../organizacion/web/presentation/primera_empresa_screen.dart';
import '../../organizacion/web/presentation/puestos_web_screen.dart';
import '../../organizacion/web/presentation/sucursales_web_screen.dart';

import 'datos/usuarios_repositorio_http.dart';
import 'login_web_screen.dart';
import 'marca_seventra.dart';
import 'marco_administra.dart';
import 'presentation/auditoria_web_screen.dart';
import 'presentation/sin_accesos_web_screen.dart';
import 'presentation/usuarios_web_screen.dart';
import 'selector_de_empresa_screen.dart';

/// El portón de Administra en la nube: **quién entra, a qué empresa, y qué ve**.
///
/// ES EL ÚNICO SITIO QUE DECIDE QUÉ PANTALLA SE MUESTRA, y por eso ni el login ni el
/// selector navegan: publican su resultado en su gestor y éste reacciona. Dos sitios
/// decidiendo lo mismo es cómo se acaba viendo el selector después de haber entrado.
///
/// LAS DOS PREGUNTAS SON SEPARADAS Y SE RESUELVEN EN ORDEN:
///
/// ```
/// ¿quién eres?            ¿con qué empresa?
/// ─────────────           ─────────────────
/// sin resolver  → espera
/// no autenticado → LOGIN
/// sin confirmar → aviso y reintentar     (hay credencial, no hubo respuesta)
/// autenticado   →        sin resolver     → resolver() y espera
///                        sin acceso       → aviso, sin salida más que salir
///                        hay que elegir   → SELECTOR
///                        activa           → ÁREAS
///                        no resuelta      → aviso y reintentar
/// ```
///
/// ✅ **YA HAY ROUTER, Y LAS DOS PREGUNTAS DE ARRIBA SIGUEN MANDANDO** (D-39). Aquí decía
/// «no hay `go_router` y es deliberado», con su razón: una ruta que se pudiera escribir a
/// mano prometería una pantalla que la sesión quizá no permite. **Esa razón no se
/// abandonó: se implementó.** Mientras no hay empresa abierta el guardia del router no
/// toca la dirección y este portón sigue decidiendo qué se ve —login, selector, espera o
/// aviso—; cuando la empresa abre, la dirección pedida se recupera **sólo si esta sesión
/// la puede ver**.
///
/// Así que de la dirección sale **dónde estás** —apartado, pestaña y lo que se abrió
/// dentro— y del contexto que confirmó el servidor sale **qué puedes**. Nunca al revés.
///
/// ✅ **`restricted` SE ESCUCHA desde C1** (era la deuda D-46), por los dos lados y en ese
/// orden de autoridad:
///
///  · **al intentar**, que es quien manda: el 402 del servidor lo traduce
///    [MensajesHumanos.deMutacion] en un solo sitio, para las dieciséis mutaciones que
///    antes mostraban «no permite la operación normal» tal como llegaba;
///  · **antes de intentar**, en la franja del pie: «Suscripción limitada: sólo consulta»,
///    para no enterarse después de haber llenado un formulario.
///
/// **No se deshabilita ningún botón.** Quien decide si una escritura procede es el
/// servidor, y una pantalla que los apaga por su cuenta acaba apagándolos cuando no debía
/// —y entonces nadie puede ver el mensaje que lo explica—.
class PortonWeb extends StatefulWidget {
  const PortonWeb({
    required this.repositorioDeLogotipos,
    required this.gestorDeSesion,
    required this.gestorDeCompany,
    required this.guardia,
    required this.repositorioDeAreas,
    required this.repositorioDeClientes,
    required this.repositorioDeEmpresas,
    required this.repositorioDeExpedientes,
    required this.repositorioDePuestos,
    required this.repositorioDeSucursales,
    required this.repositorioDeUsuarios,
    super.key,
  });

  /// El del logotipo de la empresa. **Llega construido, como los otros seis**: ninguna
  /// pantalla toca el cliente HTTP, y hay un guardia que lo vigila.
  final LogotipoRepositorioHttp repositorioDeLogotipos;

  final GestorDeSesion gestorDeSesion;
  final GestorDeCompany gestorDeCompany;

  /// Quién tiene trabajo sin guardar ahora mismo (D-56).
  ///
  /// ⚠️ **SE RECIBE Y NO SE CREA, y el cambio es de D-56.** Nacía aquí, y lo movió al
  /// arranque una dependencia circular: el `onExit` del router tiene que preguntarle, y el
  /// router es quien construye este portón. **Es uno por sesión** — dos guardias serían
  /// dos respuestas distintas a la misma pregunta, y la que mandara sería la del azar.
  final GuardiaDeSalida guardia;

  final AreasRepositorioHttp repositorioDeAreas;

  /// C1 — la cartera comercial. **El primer repositorio de un módulo CONTRATADO**: los
  /// seis anteriores son del núcleo, y éste sólo responde si la empresa tiene
  /// `clients_services` habilitado. No hace falta comprobarlo aquí: los permisos
  /// efectivos ya excluyen los de un módulo apagado, así que la pestaña no se ofrece.
  final ClientesRepositorioHttp repositorioDeClientes;

  /// E2 — la administración de empresas de la Organization, y la lectura de **la
  /// autoridad propia** sobre ella. Es otro plano que los expedientes: otra puerta
  /// —`companies.manage`, y Owner para descartar— y otras rutas.
  final EmpresasRepositorioHttp repositorioDeEmpresas;

  /// Los dos expedientes —empresa y sucursal—, que comparten repositorio porque
  /// comparten la forma del domicilio y las dos respuestas de error que nadie más
  /// tiene.
  final ExpedientesRepositorioHttp repositorioDeExpedientes;

  final PuestosRepositorioHttp repositorioDePuestos;
  final SucursalesRepositorioHttp repositorioDeSucursales;
  final UsuariosRepositorioHttp repositorioDeUsuarios;

  @override
  State<PortonWeb> createState() => _PortonWebState();
}

class _PortonWebState extends State<PortonWeb> {
  /// Si ya se pidió resolver la empresa para la sesión actual.
  ///
  /// NO ES UNA OPTIMIZACIÓN. `resolver()` es «single-flight» y una segunda llamada
  /// simultánea es inofensiva, pero una que llegue **después** de que la primera
  /// termine sí vuelve a pedir. Y como `CompanyNoResuelta` es un estado publicado,
  /// reaccionar a él llamando a `resolver()` otra vez construiría un bucle contra un
  /// servidor caído. Así que se pide una vez por sesión, y reintentar es del usuario.
  bool _empresaPedida = false;

  /// La última dirección visitada de cada apartado, **para que volver te deje donde
  /// estabas**.
  ///
  /// ## Por qué hace falta aunque ya haya router
  ///
  /// **Es la única función que el router NO regala.** La dirección guarda dónde estás
  /// AHORA; no guarda que hace cinco minutos estabas en Configuración › Auditoría. Sin
  /// este mapa, pulsar «Configuración» en el menú te llevaría siempre a su primera
  /// pestaña, y el escritorio no hace eso.
  ///
  /// Se guarda la **dirección completa** y no el id de la pestaña, porque así también
  /// se vuelve a lo que estuviera abierto dentro de ella.
  final Map<String, String> _ultimaDireccionPorApartado = {};

  /// Los logotipos de las empresas, pedidos una vez cada uno.
  ///
  /// Vive aquí y no en cada pantalla porque lo usan **dos**: el selector al entrar y el
  /// menú de la barra. Con una caché por pantalla, abrir el menú volvería a descargar lo
  /// que el selector acababa de traer.
  late final LogotiposDeEmpresa _logotipos = LogotiposDeEmpresa(_leerLogotipo);

  /// La autoridad de Organization de esta persona, **pedida una vez por organización**.
  ///
  /// Vive aquí y no en la pantalla de Empresa por la misma razón que los permisos de
  /// Company: el portón es el único que lee autoridad, y si cada pantalla la pidiera, dos
  /// partes de la interfaz podrían discrepar sobre lo que dijo el servidor.
  ///
  /// **Nula significa dos cosas y las dos llevan al mismo sitio:** que no se ha pedido
  /// todavía, o que esta persona **no es miembro** de la Organization —el caso de la
  /// mayoría: un Maestro administra *su* empresa y no gobierna la organización—. En las
  /// dos, la pestaña de administración no existe.
  AutoridadDeOrganizacion? _autoridad;

  /// De qué organización es [_autoridad], para volver a pedirla si se cambia de empresa
  /// a otra de **otra** organización. Sin esto, alguien con acceso a dos clientes
  /// arrastraría la autoridad del primero.
  String? _autoridadDe;

  /// Cómo se suelta el aviso del navegador de antes de recargar o cerrar la pestaña.
  ///
  /// Se instala en [initState] y se suelta en [dispose], como un oyente cualquiera. En el
  /// escritorio no instala nada —y la suite corre ahí—, que es lo que explica
  /// `aviso_de_salida_io.dart`.
  late final SoltarAvisoDeSalida _soltarElAviso;

  /// Adapta el repositorio a lo que la caché espera.
  ///
  /// ⚠️ **UN FALLO SE LANZA, NO SE DEVUELVE COMO NULO.** Nulo significa «esta empresa no
  /// tiene logotipo» y la caché lo recuerda para no volver a preguntar; un bache de red
  /// significa «no se pudo preguntar» y **no se puede recordar**, o la empresa se
  /// quedaría con iniciales el resto de la sesión por un segundo malo. La caché atrapa la
  /// excepción, enseña las iniciales y deja la puerta abierta al siguiente intento.
  Future<Uint8List?> _leerLogotipo(String companyId) async {
    final resultado = await widget.repositorioDeLogotipos.leer(companyId);

    return resultado.when(
      ok: (bytes) => bytes,
      failure: (fallo) => throw _NoSePudoLeerElLogotipo(fallo),
    );
  }

  /// E3 · Si esta persona puede crear su **primera** empresa, y dónde.
  ///
  /// ## Por qué esto vive en el portón y no en el gestor
  ///
  /// `GestorDeCompany` responde una sola pregunta —«¿qué empresa está abierta?»— y la
  /// sigue respondiendo igual. Esto es del plano de **Organization**, y meterlo dentro
  /// de la puerta de Company habría hecho que la puerta llamara a rutas de
  /// organización y cambiado un contrato que ya tiene pruebas.
  ///
  /// ## Por qué hace falta una averiguación y no basta con lo que ya hay
  ///
  /// Con cero empresas, `GET /companies` responde `[]`, y esa respuesta **no lleva
  /// ningún `organizationId` dentro**. Sin él no hay a quién preguntarle por la
  /// autoridad, así que la rama de «no tienes ninguna empresa» necesita dos lecturas
  /// más: la lista de organizaciones y, por cada una, la membresía.
  ///
  /// Nulo = todavía no se ha preguntado. Se pide **una vez por sesión** y se olvida al
  /// cerrarla, igual que la empresa.
  _DondeCrear? _dondeCrear;

  /// Qué averiguación es la vigente.
  ///
  /// ⚠️ **ES UN CANDADO CONTRA UNA FUGA ENTRE CUENTAS, no una optimización.** Si alguien
  /// cierra sesión y entra otra persona mientras las lecturas están en vuelo, la
  /// respuesta de la primera llegaría después y le enseñaría a la segunda **las
  /// organizaciones de la primera**. Con el contador, una respuesta de otra generación se
  /// descarta sin tocar nada. Es el mismo mecanismo que `GestorDeCompany` usa para no
  /// publicar la empresa de una resolución que ya caducó.
  int _generacionDeDondeCrear = 0;

  /// Cómo se llama cada fila cuyo expediente alguien abrió, para el rastro.
  ///
  /// ## Por qué esto NO es la vía que D-39 quitó
  ///
  /// Lo que la pantalla publicaba antes era **dónde estabas** —«se abrió Tipos de
  /// sucursal»—, y eso es navegación: un aviso que alguien tenía que acordarse de
  /// mandar, y que mentía si se olvidaba. Pasó: el rastro se quedó diciendo «Editar»
  /// estando en la administración de empresas.
  ///
  /// Lo que se guarda aquí es **cómo se llama una fila que la pantalla ya tiene
  /// cargada**, que es un dato y no un estado. Si no llega, el rastro sigue siendo
  /// correcto —dice «Expediente»—, sólo menos específico. **No hay nada que pueda
  /// quedarse pegado**, porque quien decide si se enseña es la dirección.
  ///
  /// **Y el nombre NO va en la URL**, que es la decisión del dueño del 25 de octubre de
  /// 2026: sería estado disfrazado de dirección, y quedaría viejo en cuanto alguien
  /// renombrara la sucursal.
  final Map<String, String> _nombrePorId = {};

  /// El tercer segmento del rastro, **leído de la dirección**.
  ///
  /// `/organizacion/sucursales/tipos` → «Tipos de sucursal».
  /// `/organizacion/sucursales/<id>/expediente` → «Expediente», y «Expediente de
  /// Matriz» en cuanto la pantalla haya cargado esa sucursal.
  String? _rastroDeDentro(String? pestanaId, rutas.UbicacionWeb? ubicacion) {
    final dentro = ubicacion?.dentro;
    final pestana = pestanaId ?? '';

    // LO QUE LA PANTALLA NO ABRE, EL RASTRO NO LO NOMBRA. Hoy la única dirección que
    // puede llegar hasta aquí sin abrirse es la administración de empresas, que pide
    // autoridad de Organization — y la regla vive en `rutas_web.dart`, probada sola.
    if (!rutas.seAbreLoDeDentro(
      pestana,
      dentro,
      puedeAdministrarEmpresas: _autoridad?.puedeAdministrarEmpresas ?? false,
    )) {
      return null;
    }

    return rutas.rastroConNombre(
      rutas.nombreDeLoDeDentro(pestana, dentro),
      _nombrePorId[rutas.idDeLoDeDentro(dentro)],
    );
  }

  /// Apunta cómo se llama una fila, para que el rastro la nombre.
  void _conocerElNombre(String id, String nombre) {
    if (!mounted || _nombrePorId[id] == nombre) return;

    setState(() => _nombrePorId[id] = nombre);
  }

  /// P2 · Escucha cuándo la pestaña vuelve al frente, para ponerse al día.
  ///
  /// ## Por qué el foco y no un sondeo
  ///
  /// El caso real es exactamente éste: a alguien le retiran un permiso **mientras está
  /// en otra ventana**. Al volver, lo primero que hace es mirar la pantalla — y es el
  /// único instante en el que una lectura de más vale la pena. Un sondeo periódico
  /// pediría el contexto cada minuto para enterarse de algo que pasa una vez al mes.
  ///
  /// La otra mitad la pone `VigilanteDeContexto`: si la pantalla ya estaba al frente y
  /// el servidor rechaza por permiso, se pone al día en ese momento.
  late final AppLifecycleListener _ciclo;

  @override
  void initState() {
    super.initState();

    widget.gestorDeSesion.estadoObservable.addListener(_alCambiarLaSesion);
    widget.gestorDeCompany.estadoObservable.addListener(_repintar);

    // `onResume` y no `onShow`: en la web, volver a la pestaña pasa por los dos, y
    // `onResume` es el que marca que la aplicación vuelve a ser la que manda.
    _ciclo = AppLifecycleListener(onResume: _alVolverAlFrente);

    // D-56 · EL TERCER CAMINO: recargar y cerrar la pestaña. No pasan por el router ni
    // por aquí —los decide el navegador y después no corre ni una línea de Dart—, así que
    // lo único que se puede hacer es dejarle la pregunta puesta.
    //
    // SE INSTALA UNA VEZ Y PREGUNTA CADA VEZ: lo que se le entrega es la pregunta, no la
    // respuesta. Con el valor capturado aquí, el aviso quedaría decidido para siempre con
    // lo que fuera verdad en el arranque — que es «no hay nada que perder».
    _soltarElAviso = instalarAvisoDeSalida(
      () => hayQueFrenarLaSalida(widget.guardia),
    );

    // El arranque empieza preguntando si hay una sesión guardada. El resultado lo
    // publica el gestor, así que aquí no hace falta el `Future`.
    widget.gestorDeSesion.restaurar();
  }

  @override
  void dispose() {
    _soltarElAviso();
    _ciclo.dispose();
    widget.gestorDeSesion.estadoObservable.removeListener(_alCambiarLaSesion);
    widget.gestorDeCompany.estadoObservable.removeListener(_repintar);
    super.dispose();
  }

  /// La pestaña volvió al frente: lo que se pinta puede llevar minutos viejo.
  ///
  /// **Sólo con una empresa abierta.** En el login o en el selector no hay contexto que
  /// poner al día, y el gestor ya lo comprueba; pedirlo desde aquí además sería una
  /// petición por cada vez que alguien cambia de pestaña sin haber entrado.
  void _alVolverAlFrente() {
    if (widget.gestorDeCompany.estado is! CompanyActiva) return;

    widget.gestorDeCompany.avisarDeContextoDesactualizado();
  }

  void _repintar() {
    if (mounted) setState(() {});
  }

  void _alCambiarLaSesion() {
    final estado = widget.gestorDeSesion.estado;

    // CERRAR SESIÓN TIENE QUE OLVIDAR LA EMPRESA, y no por limpieza: si no, el
    // siguiente que entre en este navegador vería un instante la empresa del
    // anterior mientras se resuelve la suya.
    if (estado is NoAutenticado) {
      _empresaPedida = false;
      widget.gestorDeCompany.olvidarSeleccion();

      // Y LA AVERIGUACIÓN DE E3 TAMBIÉN SE OLVIDA: es sobre las organizaciones de esta
      // persona, no de la siguiente que entre en este navegador. Subir la generación
      // invalida además la que pueda estar EN VUELO, que es lo que de verdad podría
      // enseñarle a la siguiente cuenta las organizaciones de la anterior.
      _dondeCrear = null;
      _generacionDeDondeCrear++;

      // Y LOS LOGOTIPOS TAMBIÉN. La lista de empresas de la siguiente persona no tiene
      // por qué parecerse a la de ésta, y una caché con logotipos ajenos es una imagen
      // de otro cliente esperando a que alguien la pinte.
      _logotipos.olvidar();

      // Y LOS NOMBRES DEL RASTRO, por lo mismo: son filas de la empresa de esta
      // persona, y aunque los ids sean irrepetibles, guardar nombres de otra cuenta
      // entre sesiones no tiene ninguna razón para existir.
      _nombrePorId.clear();
    }

    _repintar();
  }

  /// Pide resolver la empresa si toca. Se llama desde el `build`, **pero no cambia
  /// estado durante el build**: `resolver()` es asíncrono y publica después.
  void _pedirEmpresaSiHaceFalta() {
    if (_empresaPedida) return;

    _empresaPedida = true;
    widget.gestorDeCompany.resolver();
  }

  Future<void> _cerrarSesion() => widget.gestorDeSesion.cerrarSesion();

  /// Qué hacer cuando la administración de empresas (E2) cambió alguna.
  ///
  /// ⚠️ **ANTES ESTO LLAMABA A `resolver()` Y ERA UN DEFECTO**, de los que sólo se ven
  /// usando el producto: desde E1-B, resolver con varias empresas **siempre** publica
  /// «hay que elegir», así que crear, desactivar, reactivar o descartar devolvía a
  /// **«Elige una empresa»** y sacaba a la persona de donde estaba trabajando.
  ///
  /// La distinción es la que pidió el dueño, y es la correcta:
  ///
  ///  · **si la afectada es la empresa ABIERTA**, hay que resolver de verdad: su
  ///    contexto —permisos, módulos, nombre— acaba de cambiar o de dejar de existir, y
  ///    seguir pintando el anterior sería pintar algo que ya no es;
  ///  · **si es otra**, basta releer la lista y repintar. La empresa activa no se ha
  ///    movido, así que nadie tiene que volver a elegir nada.
  ///
  /// Hoy la pantalla **no ofrece** tocar la empresa abierta —el menú dice «cambia de
  /// empresa primero»— así que la primera rama no se alcanza desde ahí. Existe porque
  /// esta decisión no debe depender de que una pantalla siga comportándose así.
  Future<void> _refrescarTrasAdministrar(String? afectada, String activa) async {
    if (afectada == activa) {
      await widget.gestorDeCompany.resolver();
      return;
    }

    await widget.gestorDeCompany.refrescarDisponibles();

    // EL `setState` ES NECESARIO Y NO SOBRA: `refrescarDisponibles` no publica ningún
    // estado a propósito —la empresa activa no cambió—, así que nada repintaría el menú
    // de la barra, que lee la lista en el `build` del marco.
    if (mounted) setState(() {});
  }

  /// Cambiar de empresa desde la barra inferior. **El único camino que hay.**
  ///
  /// Vive aquí y no en el marco porque son tres pasos que no son de pintar una cáscara:
  /// preguntar por lo que se perdería, pedirle el cambio al gestor, y decir qué pasó.
  Future<void> _cambiarEmpresa(CompanyDisponible empresa) async {
    // 1 · LO QUE SE PERDERÍA. La pantalla de encima es la que sabe; el guardia sólo
    // transmite. Sin nadie registrado no hay cambios, y eso es deliberado: lo explica
    // `GuardiaDeSalida`.
    if (widget.guardia.hayCambiosSinGuardar) {
      // ⚠️ **ESTA PREGUNTA SE QUEDA AQUÍ Y NO SE FUE AL `onExit`** (D-56): cambiar de
      // empresa **no cambia la dirección** —cambia el contexto—, así que el router no se
      // entera. Es el único de los cuatro caminos que no es ni una navegación ni una
      // salida del navegador.
      //
      // Y DICE QUÉ TIENE CAMBIOS, igual que la del router, pero ésta **sí sabe a dónde
      // va**: la empresa está en el menú que se acaba de pulsar.
      final confirmado = await RisegDialog.showConfirmation(
        context: context,
        title: '¿Cambiar de empresa sin guardar?',
        message:
            'Tienes cambios sin guardar en '
            '${widget.guardia.queSePierde ?? 'este formulario'}. '
            'Si cambias a ${empresa.companyName}, se perderán.',
        confirmLabel: 'Cambiar sin guardar',
        cancelLabel: 'Seguir editando',
      );

      // CANCELAR NO HACE NADA, ni siquiera deja el menú abierto: el menú ya se cerró
      // al elegir, y volver a abrirlo sería devolver a alguien a un sitio del que
      // acaba de salir.
      if (confirmado != true || !mounted) return;
    }

    // 2 · EL CAMBIO. `cambiarA` es todo o nada: confirma el contexto antes de publicar,
    // y si falla la empresa anterior sigue activa. Recordar la nueva también es suyo.
    final resultado = await widget.gestorDeCompany.cambiarA(empresa.companyId);

    if (!mounted) return;

    // 3 · Y SE DICE. Cambiar de empresa cambia el menú, los permisos y los datos: un
    // cambio así de grande sin una palabra deja a cualquiera comprobando la barra para
    // saber si pasó algo.
    resultado.when(
      ok: (_) => RisegFeedback.showSuccess(
        context,
        'Ahora trabajas en ${empresa.companyName}',
      ),
      failure: (fallo) =>
          RisegFeedback.showError(context, MensajesHumanos.deEmpresa(fallo)),
    );
  }

  /// La empresa activa, dentro del marco de Administra.
  ///
  /// EL MARCO SE MONTA AQUÍ Y NO DENTRO DE CADA PANTALLA, y es la misma razón por la
  /// que el portón es el único que decide qué se ve: si cada sección dibujara su
  /// propia barra lateral, las nueve acabarían pareciéndose sólo por casualidad.
  ///
  /// **EL MENÚ ENSEÑA SÓLO LO QUE SE PUEDE ABRIR.**
  ///
  /// ⚠️ Hasta el 21 de octubre de 2026 enseñaba **los nueve apartados**, y los que no
  /// tenían pantalla salían con «Próximamente» y un aviso que decía «todavía se usa
  /// desde la aplicación de escritorio». Esa frase es interna: tiene sentido para
  /// RISEG, que es piloto y sí tiene escritorio, y ninguno para un cliente nuevo. El
  /// razonamiento de entonces —«enseñar sólo lo mudado dejaría a un cliente sin saber
  /// si el resto llegará»— se cambió por el del dueño: un menú de siete entradas que
  /// no llevan a ninguna parte tampoco dice nada bueno de lo que se compró.
  ///
  /// Y trae una consecuencia que antes no existía: **se puede quedar sin ningún
  /// apartado visible**. Pasa con quien no tiene ningún permiso, y se recibe con
  /// [_SinAccesos] en vez de una pantalla en blanco o un reventón.
  /// E3 · Averigua si quien no tiene ninguna empresa **puede crear la primera**.
  ///
  /// Dos lecturas: la lista de organizaciones con membresía activa y, por cada una, la
  /// membresía propia con sus permisos. Se queda con las organizaciones donde consta la
  /// autoridad —Owner, o `companies.manage`—.
  ///
  /// ⚠️ **UN FALLO NO SE CONVIERTE EN «no puedes».** Si cualquiera de las lecturas
  /// falla, el resultado es [_NoSePudoPreguntar] y la pantalla ofrece reintentar. Dos
  /// razones: *ausencia nunca es cero*, y con varias organizaciones un fallo parcial
  /// dejaría fuera un destino legítimo sin que nadie se enterara — y de esa lista sale
  /// dónde va a NACER una empresa.
  ///
  /// **No cambia estado durante el `build`**: publica después, igual que la resolución
  /// de la empresa y la autoridad.
  void _pedirDondeCrearSiHaceFalta() {
    if (_dondeCrear != null) return;

    _dondeCrear = const _Buscando();
    _averiguarDondeCrear(++_generacionDeDondeCrear);
  }

  Future<void> _averiguarDondeCrear(int generacion) async {
    /// Lo que publica un resultado **sólo si sigue siendo el vigente**.
    void publicar(_DondeCrear resultado) {
      if (!mounted || generacion != _generacionDeDondeCrear) return;
      setState(() => _dondeCrear = resultado);
    }

    final organizaciones = await widget.repositorioDeEmpresas
        .listarOrganizaciones();

    final lista = organizaciones.when(
      ok: (valor) => valor,
      failure: (_) => null,
    );

    if (lista == null) {
      publicar(const _NoSePudoPreguntar());
      return;
    }

    final conAutoridad = <OrganizacionPropia>[];

    for (final organizacion in lista) {
      // Si la generación cambió, se deja de preguntar: las respuestas que falten ya no
      // le sirven a nadie y las lecturas irían firmadas por otra sesión.
      if (!mounted || generacion != _generacionDeDondeCrear) return;

      final autoridad = await widget.repositorioDeEmpresas.leerAutoridad(
        organizacion.organizationId,
      );

      // Aquí un fallo SÍ para la averiguación entera, por lo dicho arriba: una lista de
      // destinos a la que le falte uno es peor que no tener lista.
      final fallo = autoridad.when(
        ok: (_) => false,
        failure: (_) => true,
      );

      if (fallo) {
        publicar(const _NoSePudoPreguntar());
        return;
      }

      final quienEs = autoridad.when(ok: (a) => a, failure: (_) => null);

      // `null` es un 404: no es miembro. No es un fallo y es el caso de la mayoría.
      if (quienEs != null && quienEs.puedeAdministrarEmpresas) {
        conAutoridad.add(organizacion);
      }
    }

    publicar(
      conAutoridad.isEmpty
          ? const _SinAutoridad()
          : _SePuedeCrear(conAutoridad),
    );
  }

  /// Volver a intentar la averiguación, después de un fallo de red.
  void _reintentarDondeCrear() {
    setState(() => _dondeCrear = const _Buscando());
    _averiguarDondeCrear(++_generacionDeDondeCrear);
  }

  /// El nombre de quien entró, para los saludos de la antesala.
  ///
  /// **Vacío cuando no lo hay**, y entonces no se saluda: `/auth/refresh` responde con
  /// `displayName` nulo, así que una sesión restaurada no lo trae, y un «Hola, »
  /// colgando sería peor que no saludar.
  String _nombreDeLaSesion() {
    final sesion = widget.gestorDeSesion.estado;
    return sesion is Autenticado ? sesion.sesion.displayName ?? '' : '';
  }

  /// La primera empresa ya existe: se vuelve a resolver y el gestor entra en ella.
  ///
  /// Con **una sola** empresa, `resolver()` carga su contexto y publica `CompanyActiva`
  /// sin preguntar nada, así que la persona pasa del formulario al escritorio de su
  /// empresa. Esta pantalla no navega: avisa y espera a que la desmonten.
  Future<void> _trasCrearLaPrimera() async {
    // Se olvida la averiguación: si alguna vez se volviera a esta rama, la pregunta hay
    // que hacerla otra vez y no reusar una respuesta de antes de que existiera la
    // empresa.
    _dondeCrear = null;
    _generacionDeDondeCrear++;

    await widget.gestorDeCompany.resolver();
  }

  /// Pide la autoridad de Organization si toca. **No cambia estado durante el `build`**:
  /// publica después, igual que la resolución de la empresa.
  void _pedirAutoridadSiHaceFalta(String organizationId) {
    if (_autoridadDe == organizationId) return;

    _autoridadDe = organizationId;

    widget.repositorioDeEmpresas.leerAutoridad(organizationId).then((resultado) {
      if (!mounted || _autoridadDe != organizationId) return;

      setState(() {
        // UN FALLO SE TRATA COMO «no hay autoridad», y es el lado seguro: la pestaña de
        // administración no aparece. Un bache de red no puede abrir una puerta.
        _autoridad = resultado.when(ok: (a) => a, failure: (_) => null);
      });
    });
  }

  Widget _conMarco(CompanyContext contexto) {
    final sesion = widget.gestorDeSesion.estado;
    final identidad = sesion is Autenticado ? sesion.sesion : null;

    _pedirAutoridadSiHaceFalta(contexto.organizationId);

    // SÓLO SE OFRECE CAMBIAR DE EMPRESA SI HAY A DÓNDE. `disponibles` es la última
    // lista que devolvió el servidor; con una sola, el nombre es texto plano.
    final varias = widget.gestorDeCompany.disponibles.length > 1;

    // AQUÍ SE LEE EL CONTEXTO, Y SÓLO AQUÍ. `isMaestro` y `effectivePermissions` no
    // se consultan en ninguna pantalla: si cada una los leyera, dos partes de la
    // interfaz podrían discrepar sobre lo que dijo el servidor. El portón es a la web
    // lo que `sesion_controller` al escritorio.
    //
    // LA DECISIÓN DE QUÉ HACER CON CADA APARTADO VIVE EN EL REGISTRO, no aquí:
    // `queHacerCon` es pura y se prueba sola. Aquí sólo se le entrega lo que el
    // servidor confirmó.
    //
    // DOS CASOS: se abre, o no aparece. Y «no aparece» cubre las dos razones —sin
    // mudar, o mudado y sin nada para esta persona— porque ella no puede hacer nada
    // distinto en un caso y en el otro.
    final esMaestro = contexto.isMaestro;
    final permisos = contexto.effectivePermissions;

    final visibles = [
      for (final a in apartados.apartados)
        if (apartados.queHacerCon(a, esMaestro: esMaestro, permisos: permisos) !=
            apartados.QueHacerConElApartado.noAparece)
          (
            apartado: a,
            pestanas: apartados.pestanasPara(
              a,
              esMaestro: esMaestro,
              permisos: permisos,
            ),
          ),
    ];

    // NINGÚN APARTADO VISIBLE: no hay marco que montar, porque un marco con un menú
    // vacío y un hueco en medio no explica nada. Se recibe con la bienvenida.
    //
    // ESTE CAMINO ES NUEVO y antes era inalcanzable: con los no mudados en el menú,
    // todo el mundo veía al menos Dashboard. Sin él, `visibles.first` reventaría.
    if (visibles.isEmpty) {
      return SinAccesosWebScreen(
        nombre: identidad?.displayName ?? '',
        empresa: contexto.companyName,
        alCerrarSesion: _cerrarSesion,
      );
    }

    // SIN LA INSIGNIA DE «PRÓXIMAMENTE»: lo que llega al menú ya se puede abrir. El
    // campo sigue existiendo en `ShellDestination` porque **el escritorio sí lo usa**
    // —allí el aviso es correcto, quien lo lee tiene el escritorio delante—.
    final destinos = [
      for (final v in visibles)
        ShellDestination(
          path: v.apartado.ruta,
          label: v.apartado.nombre,
          icon: v.apartado.icono,
        ),
    ];

    // LA DIRECCIÓN MANDA, y de ella sale lo demás. El guardia del router ya la dejó en
    // una que esta sesión puede ver —apartado visible y pestaña visible—, así que aquí
    // no se vuelve a decidir: se lee.
    final direccion = GoRouterState.of(context).uri.path;
    final ubicacion = rutas.leerUbicacion(direccion);

    final activo = _apartadoActivo(visibles, ubicacion);
    final pestanaActiva = _pestanaElegida(activo.pestanas, ubicacion);

    // SE RECUERDA DÓNDE ESTABAS EN ESTE APARTADO, que es lo único que el router no
    // regala: la dirección sabe dónde estás ahora y no dónde estabas.
    _ultimaDireccionPorApartado[activo.apartado.ruta] = direccion;

    return MarcoAdministra(
      destinos: destinos,
      indiceActivo: visibles.indexOf(activo),
      // EL MENÚ NAVEGA, no cambia un campo. Y vuelve a la última dirección de ese
      // apartado: pulsar «Configuración» después de haber estado en su Auditoría te
      // devuelve a Auditoría, igual que en el escritorio.
      alElegirDestino: (i) => context.go(
        _ultimaDireccionPorApartado[visibles[i].apartado.ruta] ??
            visibles[i].apartado.ruta,
      ),
      empresa: contexto.companyName,
      // El nombre puede no venir: `/auth/refresh` responde con `displayName` nulo,
      // así que una sesión restaurada no lo trae y hay que tolerar su ausencia.
      usuario: identidad?.displayName ?? '',
      correo: identidad?.email ?? '',
      alCerrarSesion: _cerrarSesion,
      // EL MENÚ DE LA BARRA, que sustituye al portazo. Hasta E1-B esto llamaba a
      // `olvidarSeleccion()`: borraba la preferencia y devolvía a la pantalla de
      // selección, desmontando la aplicación entera para un gesto pequeño.
      //
      // LA LISTA ES LA MISMA QUE ALIMENTÓ EL SELECTOR —la última que devolvió el
      // servidor—, así que el menú y la pantalla de entrada no pueden discrepar.
      empresas: widget.gestorDeCompany.disponibles,
      empresaActivaId: contexto.companyId,
      alElegirEmpresa: varias ? _cambiarEmpresa : null,
      // D-46: la suscripción limitada se dice en la franja, antes de intentar guardar. Lo
      // trae el contexto que confirmó el servidor, no una suposición de la pantalla.
      restringida: contexto.restricted,
      logotipos: _logotipos,
      // EL RASTRO DICE LAS DOS COSAS: «Configuración › Usuarios». Con sólo el
      // apartado, dos pestañas distintas se leían igual.
      pestana: activo.pestanas.length > 1 ? pestanaActiva?.nombre : null,
      // EL TERCER SEGMENTO, cuando se abrió algo dentro de la pestaña: «Organización ›
      // Sucursales › Tipos de sucursal».
      //
      // ✅ **SALE DE LA DIRECCIÓN** (D-39). Antes lo publicaba la pantalla con un
      // callback, y el portón tenía que recordar a qué pestaña pertenecía para que no
      // mintiera al cambiar de sitio.
      dentroDeLaPestana: _rastroDeDentro(pestanaActiva?.id, ubicacion),
      cuerpo: _cuerpoDelApartado(
        activo.apartado,
        activo.pestanas,
        ubicacion,
        contexto,
      ),
    );
  }

  /// Qué apartado se está viendo: **el de la dirección**.
  ///
  /// ## Por qué esto ya no decide nada
  ///
  /// Antes elegía: miraba lo recordado, y si no, el primer apartado con pantalla. Eso
  /// ahora lo hace el **guardia del router**, que es el único sitio donde vive la
  /// regla —y donde se prueba sin montar una pantalla—. Aquí sólo se busca en la lista
  /// de visibles el que la dirección nombra.
  ///
  /// **El respaldo sigue existiendo y no sobra:** entre que la empresa cambia y que el
  /// guardia corrige la dirección puede haber un repintado con la dirección vieja —un
  /// apartado que en la empresa nueva no existe—, y un `firstWhere` sin salida
  /// reventaría justo ahí. Se abre el primero visible, que por definición tiene algo
  /// dentro.
  ({apartados.ApartadoDeAdministra apartado, List<apartados.PestanaDeApartado> pestanas})
  _apartadoActivo(
    List<({apartados.ApartadoDeAdministra apartado, List<apartados.PestanaDeApartado> pestanas})>
    visibles,
    rutas.UbicacionWeb? ubicacion,
  ) {
    if (ubicacion != null) {
      for (final v in visibles) {
        if (v.apartado.ruta == ubicacion.apartado) return v;
      }
    }

    // LA LISTA NO PUEDE ESTAR VACÍA AQUÍ: quien no tiene ningún apartado visible no
    // llega a este método — el `build` lo recibe antes con la bienvenida.
    return visibles.first;
  }

  /// Qué se pinta dentro del apartado activo: el aviso amable, una pantalla, o las
  /// pestañas con la pantalla de la elegida.
  Widget _cuerpoDelApartado(
    apartados.ApartadoDeAdministra apartado,
    List<apartados.PestanaDeApartado> pestanas,
    rutas.UbicacionWeb? ubicacion,
    CompanyContext contexto,
  ) {
    // NO DEBERÍA PASAR DESDE QUE EL MENÚ SÓLO ENSEÑA LO ABRIBLE: un apartado sin
    // pestañas visibles ya no llega al menú. Se conserva porque es la red de un
    // producto, no una decisión: si llegara, un aviso es mejor que un hueco.
    if (pestanas.isEmpty) {
      return _TodaviaNoEstaEnLaWeb(
        titulo: apartado.nombre,
        icono: apartado.icono,
        esPestana: false,
      );
    }

    final elegida = _pestanaElegida(pestanas, ubicacion);

    // UNA PESTAÑA SIN PANTALLA DICE LO MISMO QUE UN APARTADO SIN PANTALLA, pero con
    // SU nombre y SU ícono: «Puestos» con su insignia, no «Organización» con el
    // edificio. Sin el ícono propio, todas las pestañas de un apartado salían
    // idénticas y parecían la misma cosa sin terminar.
    final pantalla = elegida == null || !elegida.mudada
        ? _TodaviaNoEstaEnLaWeb(
            titulo: elegida?.nombre ?? apartado.nombre,
            icono: elegida?.icono ?? apartado.icono,
            esPestana: elegida != null,
          )
        : _pantallaDe(apartado, elegida, ubicacion, contexto);

    // UNA SOLA PESTAÑA NO SE PINTA. Un rótulo que no lleva a ninguna parte ocupa
    // espacio y no dice nada; cuando aparezca la segunda, la barra aparece sola.
    if (pestanas.length == 1) return pantalla;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            0,
          ),
          // EL MISMO `RisegTabs` DEL ESCRITORIO —subrayado azul incluido—, no una
          // barra propia: si algo ya existe allá, la web lo reutiliza tal cual.
          child: RisegTabs(
            // LA QUE NO TIENE PANTALLA SE ATENÚA, igual de discreto que la segunda
            // línea gris del menú lateral: mismo alto, misma tipografía, sólo el
            // tono. Antes no se distinguía hasta abrirla.
            tabs: [
              for (final p in pestanas)
                RisegTabItem(label: p.nombre, atenuada: !p.mudada),
            ],
            // `indexOf(null)` daría -1 y rompería la barra; con pestañas no vacías
            // `elegida` nunca es nula, y el `?? 0` lo deja escrito en vez de confiado.
            selectedIndex: elegida == null ? 0 : pestanas.indexOf(elegida),
            // LA PESTAÑA NAVEGA. Y no hace falta limpiar nada de lo que se abrió
            // dentro: la dirección nueva no lo lleva, así que no hay estado viejo que
            // pueda quedarse diciendo «Tipos de sucursal» en otra pestaña.
            onChanged: (i) =>
                context.go(rutas.direccionDe(apartado.ruta, pestanas[i].id)),
          ),
        ),
        Expanded(child: pantalla),
      ],
    );
  }

  /// Qué pestaña está abierta: **la de la dirección**, por su `id`.
  ///
  /// **Por `id` y no por posición**, igual que antes: si una pestaña aparece o
  /// desaparece —porque cambió la empresa y con ella los permisos—, la posición
  /// señalaría otra cosa sin avisar.
  ///
  /// **El respaldo es el mismo caso que en [_apartadoActivo]**: un repintado con la
  /// dirección de la empresa anterior, entre el cambio y la corrección del guardia. Se
  /// abre **la primera DISPONIBLE**, no la primera de la lista: Organización empieza
  /// por Empresa, y si algún día no tuviera pantalla, abrir ahí recibiría a todo el
  /// mundo con un «Próximamente» teniendo Sucursales al lado.
  apartados.PestanaDeApartado? _pestanaElegida(
    List<apartados.PestanaDeApartado> pestanas,
    rutas.UbicacionWeb? ubicacion,
  ) {
    if (pestanas.isEmpty) return null;

    for (final p in pestanas) {
      if (p.id == ubicacion?.pestana) return p;
    }

    return apartados.primeraDisponible(pestanas) ?? pestanas.first;
  }

  /// La pantalla de una pestaña.
  ///
  /// EL `companyId` SALE DEL CONTEXTO QUE EL SERVIDOR CONFIRMÓ, nunca de la lista, de
  /// la preferencia guardada ni de la URL: es el único valor que ya pasó por
  /// `/context`.
  ///
  /// ⚠️ **DE LA URL SALE SÓLO DÓNDE ESTÁS, nunca qué puedes** (D-39). La dirección dice
  /// si está abierto el catálogo de tipos o el expediente de qué sucursal; los permisos
  /// siguen saliendo del contexto, y por eso el `id` de la URL se usa para **buscar** una
  /// fila en lo que el servidor ya devolvió, no para pedirla a ciegas.
  Widget _pantallaDe(
    apartados.ApartadoDeAdministra apartado,
    apartados.PestanaDeApartado pestana,
    rutas.UbicacionWeb? ubicacion,
    CompanyContext contexto,
  ) {
    // LA DIRECCIÓN DE ESTA PESTAÑA, para colgarle lo que se abra dentro.
    final deLaPestana = rutas.direccionDe(apartado.ruta, pestana.id);

    // LO QUE LA DIRECCIÓN DICE QUE ESTÁ ABIERTO DENTRO, y de qué fila.
    //
    // **Se comprueba que sea de ESTA pestaña**, y no sobra: entre que la empresa cambia
    // y que el guardia del router corrige la dirección hay un repintado con la dirección
    // vieja, y ahí la pestaña que se pinta puede no ser la que la dirección nombra.
    final dentro = ubicacion?.pestana == pestana.id ? ubicacion?.dentro : null;
    final abierto = dentro?.lastOrNull;
    final idDeDentro = rutas.idDeLoDeDentro(dentro);

    return switch (pestana.id) {
      // EL PERMISO SALE DE LOS EFECTIVOS QUE CONFIRMÓ EL SERVIDOR, que ya incluyen lo
      // que el Maestro recibe automáticamente. Sumarle un `|| esMaestro` aquí sería
      // reimplementar en la pantalla una regla que dejó de ser incondicional en el
      // servidor, y las dos discreparían el día que un permiso cambie de familia.
      // LA PESTAÑA EMPRESA ES AHORA LISTA → FICHA → EDITAR, y no un formulario siempre
      // abierto. El cambio es del 21 de octubre de 2026 y su razón está en
      // `EmpresasWebScreen`: con varias empresas no había dónde elegir, consultar y
      // editar se confundían, y los datos fiscales no se veían con la forma en que se
      // entregan.
      'empresa' => EmpresasWebScreen(
        repositorio: widget.repositorioDeExpedientes,
        logotipos: widget.repositorioDeLogotipos,
        gestorDeCompany: widget.gestorDeCompany,
        empresaActivaId: contexto.companyId,
        // DONDE SE REGISTRA EL TRABAJO SIN GUARDAR, para que la barra pueda preguntar
        // antes de cambiar de empresa.
        guardia: widget.guardia,
        // E2 — la pestaña de administración, que **sólo existe con autoridad de
        // Organization**. Nula es el caso de la mayoría: un Maestro que no gobierna la
        // organización ve la ficha y nada más.
        organizationId: contexto.organizationId,
        autoridad: _autoridad,
        repositorioDeEmpresas: widget.repositorioDeEmpresas,
        cacheDeLogotipos: _logotipos,
        // CUANDO LA ADMINISTRACIÓN CAMBIA ALGO, el menú de la barra tiene que enterarse:
        // una empresa desactivada o descartada desaparece de él, y una nueva aparece.
        alCambiarLasEmpresas: (companyId) =>
            _refrescarTrasAdministrar(companyId, contexto.companyId),
        puedeEditar: apartados.puedeEditarLaConfiguracionDeLaEmpresa(
          contexto.effectivePermissions,
        ),
        // DÓNDE ESTÁS, DE LA DIRECCIÓN (D-39): el formulario y la administración son
        // ahora dos direcciones, así que «atrás» devuelve a la ficha.
        editando: abierto == 'editar',
        administrando: abierto == 'administracion',
        // Y LA PANTALLA PIDE, no navega: quien conoce la ruta del apartado es el portón.
        alIrADentro: (aDonde) =>
            context.go(aDonde == null ? deLaPestana : '$deLaPestana/$aDonde'),
      ),
      'areas' => AreasWebScreen(
        repositorio: widget.repositorioDeAreas,
        empresaId: contexto.companyId,
        // D-56 · PARA EL PANEL DE ALTA Y EDICIÓN, que es el que tiene campos.
        guardia: widget.guardia,
        // SALE DEL CONTEXTO QUE EL SERVIDOR CONFIRMÓ, igual que el `companyId`: ni de
        // la lista de empresas, ni de una preferencia guardada, ni de la URL.
        esMaestro: contexto.isMaestro,
        // ⚠️ EL ROL NO ERA SUFICIENTE, Y ANTES SOLO SE PASABA EL ROL. Un usuario con
        // rol Usuario y CERO permisos veía «Nueva área» y el panel de edición
        // completo: el botón no estaba atado a nada y `esMaestro` sólo gobernaba el
        // borrado. Lo que no se puede hacer no se muestra.
        //
        // UN OBJETO Y NO TRES `bool`: cada acción pregunta por SU capacidad, y
        // añadir un módulo es una llamada a la fábrica. Los literales se quedan en
        // el shell, que es su dueño.
        capacidades: apartados.CapacidadesDeModulo.deLaOrganizacion(
          contexto.effectivePermissions,
        ),
      ),
      'sucursales' => SucursalesWebScreen(
        repositorio: widget.repositorioDeSucursales,
        // EL EXPEDIENTE DE UNA SUCURSAL SE ABRE DESDE AQUÍ DENTRO, no es una pestaña:
        // es de una sucursal concreta, y una pestaña tendría que preguntar cuál.
        repositorioDeExpedientes: widget.repositorioDeExpedientes,
        empresaId: contexto.companyId,
        esMaestro: contexto.isMaestro,
        // ⚠️ SE LLAMABA `puedeEditarExpedientes` Y GOBERNABA SÓLO EL EXPEDIENTE, así
        // que «Nueva sucursal», «Tipos de sucursal», «Cerrar temporalmente» y los
        // interruptores quedaban sin puerta.
        capacidades: apartados.CapacidadesDeModulo.deLaOrganizacion(
          contexto.effectivePermissions,
        ),
        // EL EXPEDIENTE VA APARTE, con el permiso del expediente: dentro de esta
        // pantalla se abre el de una sucursal, y es otra familia.
        puedeEditarExpedientes: apartados.puedeEditarLaConfiguracionDeLaEmpresa(
          contexto.effectivePermissions,
        ),
        // ✅ DÓNDE ESTÁS, DE LA DIRECCIÓN (D-39). Ni el catálogo de tipos ni el
        // expediente son pestañas —viven aquí dentro, detrás de un botón—, así que el
        // portón no se enteraba y la pantalla tenía que avisarle. Ahora son dos
        // direcciones: `…/sucursales/tipos` y `…/sucursales/<id>/expediente`.
        // D-56 · PARA QUE EL EXPEDIENTE DE UNA SUCURSAL REGISTRE LO QUE SE PERDERÍA.
        // Esta pantalla no lo usa: lo pasa.
        guardia: widget.guardia,
        viendoTipos: abierto == 'tipos',
        expedienteDe: abierto == 'expediente' ? idDeDentro : null,
        alVerTipos: (viendo) =>
            context.go(viendo ? '$deLaPestana/tipos' : deLaPestana),
        // **SÓLO EL ID EN LA URL.** El nombre no va ahí: sería estado disfrazado de
        // dirección, y quedaría viejo en cuanto alguien renombrara la sucursal.
        alVerExpediente: (sucursal) => context.go(
          sucursal == null
              ? deLaPestana
              : '$deLaPestana/${sucursal.id}/expediente',
        ),
        // Y EL NOMBRE PARA EL RASTRO, de los datos que la pantalla ya cargó.
        alConocerElNombre: _conocerElNombre,
      ),
      'puestos' => PuestosWebScreen(
        repositorio: widget.repositorioDePuestos,
        // D-56 · PARA EL PANEL DE ALTA Y EDICIÓN, que es el que tiene campos.
        guardia: widget.guardia,
        // LAS ÁREAS, PARA EL SELECTOR Y PARA LA LISTA: el servidor manda `areaId`, no
        // el nombre, y un UUID en una lista no le dice nada a nadie.
        repositorioDeAreas: widget.repositorioDeAreas,
        empresaId: contexto.companyId,
        esMaestro: contexto.isMaestro,
        // El rol no basta, igual que en Áreas y Sucursales.
        capacidades: apartados.CapacidadesDeModulo.deLaOrganizacion(
          contexto.effectivePermissions,
        ),
        // SIN UN ÁREA ACTIVA NO SE PUEDE CREAR UN PUESTO, y la pantalla pide el cambio
        // en lugar de hacerlo. Lo que cambió con el router es a qué se traduce: antes
        // movía un campo del portón, ahora NAVEGA — y por eso el botón de «ve a Áreas»
        // deja ahora una entrada en el historial del navegador, que es lo correcto:
        // «atrás» devuelve a Puestos, donde esa persona estaba.
        alIrAAreas: () => context.go(rutas.direccionDe(apartado.ruta, 'areas')),
      ),
      // C1 — LA PRIMERA PANTALLA DE UN MÓDULO CONTRATADO. El permiso vuelve a salir de
      // los efectivos que confirmó el servidor, que ya excluyen los de un módulo que la
      // empresa no tiene: aquí no se pregunta por `enabledModules`, porque sería una
      // segunda respuesta a la misma pregunta.
      'clientes' => ClientesWebScreen(
        repositorio: widget.repositorioDeClientes,
        empresaId: contexto.companyId,
        // D-56 · PARA EL PANEL DE ALTA, que es el que tiene campos. Esta pantalla no lo
        // usa: lo pasa.
        guardia: widget.guardia,
        // LAS TRES ESCRITURAS DE CLIENTES SON `clients_services.manage`, y la fábrica es
        // la que lo sabe: ninguna feature conoce un literal del catálogo.
        capacidades: apartados.CapacidadesDeModulo.deClientes(
          contexto.effectivePermissions,
        ),
      ),
      'usuarios' => UsuariosWebScreen(
        repositorio: widget.repositorioDeUsuarios,
        empresaId: contexto.companyId,
        // D-56 · PARA EL PANEL DE PERMISOS, que son doce casillas marcadas a mano.
        guardia: widget.guardia,
      ),
      'auditoria' => AuditoriaWebScreen(
        repositorio: widget.repositorioDeUsuarios,
        empresaId: contexto.companyId,
      ),
      // UNA PESTAÑA MARCADA COMO MUDADA SIN PANTALLA ES UN ERROR DE PROGRAMACIÓN, no un
      // estado del sistema: alguien puso `mudada: true` y olvidó el `case`. Se dice
      // así, en vez de caer en el aviso amable y parecer una decisión.
      _ => _FaltaConectar(pestana: pestana),
    };
  }

  Future<void> _reintentarEmpresa() async {
    setState(() {});
    await widget.gestorDeCompany.resolver();
  }

  @override
  Widget build(BuildContext context) => switch (widget.gestorDeSesion.estado) {
    // Todavía se está leyendo la credencial guardada. **No es «no hay sesión»**:
    // mostrar el login aquí haría parpadear la pantalla de entrada a quien tenía la
    // sesión abierta, y es exactamente lo que `AutenticacionSinResolver` evita.
    AutenticacionSinResolver() => const _Esperando(),

    NoAutenticado() => LoginWebScreen(gestor: widget.gestorDeSesion),

    // Hay una credencial guardada y el servidor no contestó NI UNA VEZ. Pedir la
    // contraseña sería inútil —el login también fallaría— y además haría pensar que
    // la sesión expiró, cuando lo que no hay es servidor.
    SesionRemotaSinConfirmar(:final motivo) => _Mensaje(
      titulo: 'No se pudo comprobar tu sesión',
      cuerpo: MensajesHumanos.deSesion(motivo),
      accion: 'Volver a intentar',
      alPulsar: () => widget.gestorDeSesion.restaurar(),
      alCerrarSesion: _cerrarSesion,
    ),

    Autenticado() => _conSesion(),
  };

  Widget _conSesion() {
    final estado = widget.gestorDeCompany.estado;

    switch (estado) {
      case CompanySinResolver():
        _pedirEmpresaSiHaceFalta();
        return const _Esperando();

      case SinAccesoACompanies():
        // NO ES UN FALLO Y EL MENSAJE NO DEBE SONAR A UNO. El caso normal es el
        // primer día: la cuenta existe y todavía nadie le dio acceso a una empresa.
        // Un Owner que nombró Maestro a otra persona llega aquí siempre, porque ser
        // Owner no concede acceso a datos.
        //
        // E3 AÑADIÓ UNA SALIDA, Y SÓLO PARA QUIEN PUEDE USARLA. Una Organization
        // recién vendida no tiene ninguna empresa, y hasta E3 esto era un callejón
        // sin salida: la pantalla que sabe crearlas vive dentro del marco, detrás de
        // un contexto de empresa que todavía no existe. Quien tiene autoridad para
        // crear la primera la crea aquí; **para todos los demás, este mensaje sigue
        // siendo exactamente el de antes**.
        _pedirDondeCrearSiHaceFalta();

        return switch (_dondeCrear) {
          // Se está preguntando. No se enseña el mensaje todavía: para un Owner sería
          // decirle «nadie te ha dado acceso» y desdecirse medio segundo después.
          null || _Buscando() => const _Esperando(),

          _SePuedeCrear(:final organizaciones) => PrimeraEmpresaScreen(
            repositorio: widget.repositorioDeEmpresas,
            organizaciones: organizaciones,
            alCreada: _trasCrearLaPrimera,
            alCerrarSesion: _cerrarSesion,
            // EL NOMBRE PARA EL SALUDO, y puede venir vacío: una sesión restaurada por
            // `/auth/refresh` no trae `displayName`, y entonces no hay saludo.
            usuario: _nombreDeLaSesion(),
          ),

          _SinAutoridad() => _Mensaje(
            titulo: 'Todavía no tienes ninguna empresa',
            cuerpo:
                'Tu cuenta está lista, pero nadie te ha dado acceso a una empresa. '
                'Pídelo a quien administra la tuya.',
            alCerrarSesion: _cerrarSesion,
          ),

          // UN BACHE DE RED NO DICE «no puedes». Mismo mensaje, más la salida que sí
          // arregla un fallo de red: volver a preguntar.
          _NoSePudoPreguntar() => _Mensaje(
            titulo: 'Todavía no tienes ninguna empresa',
            cuerpo:
                'Tu cuenta está lista, pero nadie te ha dado acceso a una empresa. '
                'Pídelo a quien administra la tuya.\n\n'
                'Tampoco se pudo comprobar si tú puedes crear una: si acabas de '
                'contratar, vuelve a intentarlo.',
            accion: 'Volver a intentar',
            alPulsar: _reintentarDondeCrear,
            alCerrarSesion: _cerrarSesion,
          ),
        };

      case SeleccionDeCompanyRequerida(:final disponibles, :final recordada):

        return SelectorDeEmpresaScreen(
          gestor: widget.gestorDeCompany,
          disponibles: disponibles,
          logotipos: _logotipos,
          // LA RECORDADA SE MARCA, NO DECIDE. El gestor ya no entra solo con varias
          // empresas: aquí sólo sirve para la insignia «Última vez» y para que esa
          // tarjeta salga primera.
          recordada: recordada,
          // EL NOMBRE PARA EL SALUDO, y puede venir vacío: una sesión restaurada por
          // `/auth/refresh` no trae `displayName`, y entonces no hay saludo.
          usuario: _nombreDeLaSesion(),
          alCerrarSesion: _cerrarSesion,
        );

      case CompanyActiva(:final contexto):
        return _conMarco(contexto);

      case CompanyNoResuelta(:final motivo):
        return _Mensaje(
          titulo: 'No se pudo abrir tu empresa',
          cuerpo: MensajesHumanos.deEmpresa(motivo),
          accion: 'Volver a intentar',
          alPulsar: _reintentarEmpresa,
          alCerrarSesion: _cerrarSesion,
        );
    }
  }
}

/// La espera del arranque.
///
/// **Sin texto.** Dura lo que tarda leer el almacenamiento local y, si hay sesión,
/// una llamada al servidor. Un «Cargando…» que aparece y desaparece en 200 ms se
/// lee como un parpadeo; el logotipo quieto, no.
/// «No se pudo preguntar por el logotipo», que **no** es «no tiene logotipo».
///
/// Existe para que la caché de logotipos pueda distinguir las dos cosas: la ausencia se
/// recuerda, el fallo no. Nunca llega a ninguna pantalla —la caché lo atrapa y enseña
/// las iniciales—, así que lleva el fallo dentro sólo para que una traza futura pueda
/// decir qué pasó.
class _NoSePudoLeerElLogotipo implements Exception {
  const _NoSePudoLeerElLogotipo(this.fallo);

  final Failure fallo;

  @override
  String toString() => 'No se pudo leer el logotipo: $fallo';
}

/// E3 · Qué se le puede ofrecer a quien **no tiene ninguna empresa**.
///
/// Cuatro estados y no un par de banderas, porque las cuatro respuestas son
/// distintas y «no sé todavía» no se puede confundir con «no puedes»:
///
///  · [_Buscando] — se está preguntando. No se enseña nada que pueda desdecirse;
///  · [_SinAutoridad] — pertenece a cero organizaciones, o a ninguna donde pueda
///    crear. **Es el caso normal** y el mensaje de siempre es la respuesta correcta;
///  · [_SePuedeCrear] — hay dónde, y entonces aparece la pantalla de E3;
///  · [_NoSePudoPreguntar] — una lectura falló. El mensaje de siempre **más** un
///    reintento, nunca un «no tienes autoridad» que sería mentira.
sealed class _DondeCrear {
  const _DondeCrear();
}

final class _Buscando extends _DondeCrear {
  const _Buscando();
}

final class _SinAutoridad extends _DondeCrear {
  const _SinAutoridad();
}

final class _SePuedeCrear extends _DondeCrear {
  const _SePuedeCrear(this.organizaciones);

  /// Nunca vacía: con cero, el estado es [_SinAutoridad].
  final List<OrganizacionPropia> organizaciones;
}

final class _NoSePudoPreguntar extends _DondeCrear {
  const _NoSePudoPreguntar();
}

class _Esperando extends StatelessWidget {
  const _Esperando();

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: MarcaSeventra.fondo,
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LogotipoSeventra(),
          SizedBox(height: 26),
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: MarcaSeventra.verde,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Una pantalla de un solo mensaje, con una acción opcional y **siempre** la salida.
///
/// LA SALIDA NO ES OPCIONAL, y es la lección de las tres situaciones que la usan:
/// en las tres, quien lo lee puede haber entrado con la cuenta equivocada, y sin un
/// «salir» se queda encerrado mirando un aviso que no le toca a él resolver.
class _Mensaje extends StatelessWidget {
  const _Mensaje({
    required this.titulo,
    required this.cuerpo,
    required this.alCerrarSesion,
    this.accion,
    this.alPulsar,
  });

  final String titulo;
  final String cuerpo;
  final Future<void> Function() alCerrarSesion;
  final String? accion;
  final VoidCallback? alPulsar;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: MarcaSeventra.fondo,
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: LogotipoSeventra(alto: 28)),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: MarcaSeventra.borde),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        color: MarcaSeventra.tinta,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      cuerpo,
                      style: const TextStyle(
                        color: MarcaSeventra.suave,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                    if (accion != null && alPulsar != null) ...[
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 44,
                        child: FilledButton(
                          onPressed: alPulsar,
                          style: FilledButton.styleFrom(
                            backgroundColor: MarcaSeventra.verde,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(accion!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: TextButton(
                  onPressed: alCerrarSesion,
                  style: TextButton.styleFrom(
                    foregroundColor: MarcaSeventra.suave,
                  ),
                  child: const Text('Cerrar sesión'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ===========================================================================
// Los apartados que todavía no tienen pantalla
// ===========================================================================

/// El aviso de algo que está en el menú y aún no se mudó.
///
/// Sirve para **un apartado y para una pestaña**: «Personal — Próximamente» y
/// «Puestos — Próximamente» dicen lo mismo, y el título es el de lo que se abrió, no
/// el de su contenedor.
///
/// **NO ES UN ERROR Y NO SE DISCULPA DE MÁS.** Un «no disponible» a secas deja a
/// alguien pensando que compró algo que no funciona.
///
/// ⚠️ **SE LLAMABA `_Proximamente` Y NOMBRABA LA APLICACIÓN DE ESCRITORIO:** «Este
/// apartado todavía se usa desde la aplicación de escritorio. Lo estamos trayendo a
/// la web módulo por módulo». Ese texto es interno —tiene sentido para RISEG, que es
/// cliente piloto y sí tiene escritorio, y ninguno para un cliente nuevo— y el dueño
/// lo vio probando con una cuenta de usuario.
///
/// Los APARTADOS sin mudar ya no llegan aquí: desde el 21 de octubre de 2026 no
/// aparecen en el menú. Esto queda para las PESTAÑAS, que sí se van a mudar a medias
/// —un módulo llega pantalla por pantalla— y entonces este aviso **lo lee un
/// cliente**. Por eso ya no nombra ningún producto que él no tenga.
class _TodaviaNoEstaEnLaWeb extends StatelessWidget {
  const _TodaviaNoEstaEnLaWeb({
    required this.titulo,
    required this.icono,
    required this.esPestana,
  });

  final String titulo;
  final IconData icono;

  /// ¿Lo que se abrió es una **pestaña** o un **apartado**?
  ///
  /// Sólo cambia una palabra —«Esta sección» frente a «Este apartado»— y por eso es
  /// fácil no darle importancia. Pero decirle «apartado» a una pestaña de Organización
  /// es llamarle a la parte como al todo, y quien lee se pregunta si lo que falta es
  /// Puestos o es Organización entera.
  final bool esPestana;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.surface,
      body: Center(
        child: ConstrainedBox(
          // ANCHO ACOTADO: un párrafo que cruza una pantalla de 27 pulgadas no se
          // lee, se barre.
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icono, size: 48, color: colors.textMuted),
                const SizedBox(height: AppSpacing.md),
                Text(
                  titulo,
                  style: AppTypography.heading2,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xs),
                const RisegStatusBadge(
                  label: 'Próximamente',
                  tone: RisegStatusTone.neutral,
                  icon: Icons.schedule_outlined,
                ),
                const SizedBox(height: AppSpacing.md),
                // SIN NOMBRAR NINGÚN OTRO PRODUCTO. Lo que una persona puede hacer
                // con esta información es saber que llegará y que no tiene que
                // pedirlo; decirle dónde está hoy sólo sirve si tiene el escritorio,
                // y un cliente nuevo no lo tiene.
                Text(
                  // SIN PRONOMBRE EN LA SEGUNDA FRASE: «la» concuerda con «sección» y
                  // choca con «apartado». Un texto que cambia de género a mitad es
                  // justo lo que la 0051 vino a corregir en la siembra.
                  '${esPestana ? 'Esta sección' : 'Este apartado'} todavía no está '
                  'disponible aquí. Se está habilitando por partes, y cuando llegue '
                  'aparecerá sin que tengas que hacer nada.',
                  style: AppTypography.body.copyWith(color: colors.textMuted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Una pestaña declarada como mudada **sin pantalla asignada**.
///
/// Es un error de programación, no un estado del sistema, y por eso no usa el aviso
/// amable: parecería una decisión. Dice que es nuestro para que nadie lo busque en lo
/// que hizo.
class _FaltaConectar extends StatelessWidget {
  const _FaltaConectar({required this.pestana});

  final apartados.PestanaDeApartado pestana;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bug_report_outlined, size: 48, color: colors.warning),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Falta conectar «${pestana.nombre}»',
                  style: AppTypography.heading2,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Esta pestaña está marcada como mudada pero no tiene pantalla '
                  'asignada. Es un error nuestro, no algo que hayas hecho.',
                  style: AppTypography.body.copyWith(color: colors.textMuted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
