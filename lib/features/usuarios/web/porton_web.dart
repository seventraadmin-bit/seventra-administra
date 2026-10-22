import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/auth/gestor_de_sesion.dart';
import '../../../core/auth/sesion_remota.dart';
import '../../../core/company/company_remota.dart';
import '../../../core/company/gestor_de_company.dart';
import '../../../core/company/guardia_de_salida.dart';
import '../../../core/company/logotipos_de_empresa.dart';
import '../../../core/error/failure.dart';
import '../../../app/shell/apartados_web.dart' as apartados;
import '../../../app/shell/shell_destinations.dart';
import '../../../core/design_system/design_system_web.dart';
import '../../../core/company/autoridad_de_organizacion.dart';
import '../../organizacion/web/datos/areas_repositorio_http.dart';
import '../../organizacion/web/datos/empresas_repositorio_http.dart';
import '../../organizacion/web/datos/expedientes_repositorio_http.dart';
import '../../organizacion/web/datos/logotipo_repositorio_http.dart';
import '../../organizacion/web/datos/puestos_repositorio_http.dart';
import '../../organizacion/web/datos/sucursales_repositorio_http.dart';
import '../../organizacion/web/presentation/areas_web_screen.dart';
import '../../organizacion/web/presentation/empresas_web_screen.dart';
import '../../organizacion/web/presentation/puestos_web_screen.dart';
import '../../organizacion/web/presentation/sucursales_web_screen.dart';

import 'datos/usuarios_repositorio_http.dart';
import 'login_web_screen.dart';
import 'marca_seventra.dart';
import 'marco_administra.dart';
import 'mensajes_humanos.dart';
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
/// **NO HAY `go_router` AQUÍ**, y es deliberado. Lo que se muestra no depende de una
/// URL sino de dos estados del servidor, y una ruta que se pudiera escribir a mano
/// prometería una pantalla que la sesión quizá no permite. El router entra cuando
/// haya varias pantallas **dentro**, que es la etapa siguiente de la mudanza.
///
/// ⏳ **No se escucha `restricted` todavía.** El contexto de la empresa lo trae
/// —`CompanyContext.restricted`— y aquí no se usa: el aviso de suscripción limitada
/// es de la etapa que conecte las mutaciones, porque hoy Áreas sólo lee. Lo que sí
/// está escrito es el mensaje que le corresponde, en [MensajesHumanos.deEmpresa].
class PortonWeb extends StatefulWidget {
  const PortonWeb({
    required this.repositorioDeLogotipos,
    required this.gestorDeSesion,
    required this.gestorDeCompany,
    required this.repositorioDeAreas,
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
  final AreasRepositorioHttp repositorioDeAreas;

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

  /// Qué apartado se está viendo, **por su ruta**. Vive aquí y no en una URL porque la
  /// web todavía no tiene router: lo que se ve depende de la sesión y de la empresa, no
  /// de una dirección que alguien pueda escribir.
  ///
  /// `null` significa «todavía no has elegido», y entonces se abre el primero con
  /// pantalla. **No se inicializa a `/dashboard`**: ese apartado no está mudado, y
  /// recibir a todo el mundo con un «Próximamente» haría pensar que no hay nada hecho.
  String? _rutaDeSeccion;

  /// Qué pestaña se eligió en cada apartado, **por id y no por posición**.
  ///
  /// Por posición se rompería al cambiar de empresa: si en la nueva una pestaña ya no
  /// aparece —porque allí no eres Maestro—, la posición recordada señalaría otra cosa
  /// sin avisar. Y se recuerda por apartado para que volver a Configuración te deje
  /// donde estabas, que es lo que hace el escritorio.
  final Map<String, String> _pestanaPorApartado = {};

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

  /// Quién tiene trabajo sin guardar ahora mismo.
  ///
  /// El portón lo crea y lo reparte; la pantalla que tenga un formulario se registra al
  /// montarse. Es lo que permite que **la barra** pregunte antes de cambiar de empresa,
  /// cuando antes la pregunta sólo existía dentro de la pantalla de Empresa.
  final GuardiaDeSalida _guardia = GuardiaDeSalida();

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

  /// Lo que se abrio DENTRO de una pestana, para el tercer segmento del rastro.
  ///
  /// Hoy solo Tipos de sucursal, que no es una pestana: vive dentro de Sucursales
  /// detras de un boton. El portoon no se enteraria por su cuenta, asi que la
  /// pantalla se lo dice.
  ///
  /// **Se limpia al cambiar de apartado o de pestana**, porque si no el rastro
  /// seguiria diciendo «Tipos de sucursal» estando en Areas.
  String? _rastroDentro;

  @override
  void initState() {
    super.initState();

    widget.gestorDeSesion.estadoObservable.addListener(_alCambiarLaSesion);
    widget.gestorDeCompany.estadoObservable.addListener(_repintar);

    // El arranque empieza preguntando si hay una sesión guardada. El resultado lo
    // publica el gestor, así que aquí no hace falta el `Future`.
    widget.gestorDeSesion.restaurar();
  }

  @override
  void dispose() {
    widget.gestorDeSesion.estadoObservable.removeListener(_alCambiarLaSesion);
    widget.gestorDeCompany.estadoObservable.removeListener(_repintar);
    super.dispose();
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

      // Y LOS LOGOTIPOS TAMBIÉN. La lista de empresas de la siguiente persona no tiene
      // por qué parecerse a la de ésta, y una caché con logotipos ajenos es una imagen
      // de otro cliente esperando a que alguien la pinte.
      _logotipos.olvidar();
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

  /// Cambiar de empresa desde la barra inferior. **El único camino que hay.**
  ///
  /// Vive aquí y no en el marco porque son tres pasos que no son de pintar una cáscara:
  /// preguntar por lo que se perdería, pedirle el cambio al gestor, y decir qué pasó.
  Future<void> _cambiarEmpresa(CompanyDisponible empresa) async {
    // 1 · LO QUE SE PERDERÍA. La pantalla de encima es la que sabe; el guardia sólo
    // transmite. Sin nadie registrado no hay cambios, y eso es deliberado: lo explica
    // `GuardiaDeSalida`.
    if (_guardia.hayCambiosSinGuardar) {
      final confirmado = await RisegDialog.showConfirmation(
        context: context,
        title: 'Hay cambios sin guardar',
        message:
            'Si cambias a ${empresa.companyName} se perderá lo que escribiste.',
        confirmLabel: 'Cambiar y descartar',
        cancelLabel: 'Seguir aquí',
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

    final activo = _apartadoActivo(visibles, esMaestro: esMaestro, permisos: permisos);
    final pestanaActiva = _pestanaElegida(activo.apartado, activo.pestanas);

    return MarcoAdministra(
      destinos: destinos,
      indiceActivo: visibles.indexOf(activo),
      alElegirDestino: (i) => setState(() {
        _rutaDeSeccion = visibles[i].apartado.ruta;
        // EL RASTRO DE DENTRO SE LIMPIA AL MOVERSE. Sin esto seguiria diciendo
        // «Tipos de sucursal» estando en Configuracion.
        _rastroDentro = null;
      }),
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
      logotipos: _logotipos,
      // EL RASTRO DICE LAS DOS COSAS: «Configuración › Usuarios». Con sólo el
      // apartado, dos pestañas distintas se leían igual.
      pestana: activo.pestanas.length > 1 ? pestanaActiva?.nombre : null,
      // EL TERCER SEGMENTO, cuando se abrio algo dentro de la pestana: «Organizacion
      // › Sucursales › Tipos de sucursal».
      dentroDeLaPestana: _rastroDentro,
      cuerpo: _cuerpoDelApartado(activo.apartado, activo.pestanas, contexto),
    );
  }

  /// Qué apartado se está viendo.
  ///
  /// **AL ENTRAR SE ABRE EL PRIMERO QUE TIENE PANTALLA, NO EL PRIMERO DEL MENÚ.** El
  /// menú empieza por Dashboard, que todavía no está mudado: recibir a todo el mundo
  /// con un «Próximamente» haría pensar que no hay nada hecho. Y sale del **mismo
  /// registro**, así que el día que Dashboard se mude, la sesión empezará ahí sin
  /// tocar una línea de aquí.
  ///
  /// Se recuerda **por ruta y no por posición**: al cambiar de empresa la lista puede
  /// perder un apartado —quien era Maestro en una y no en la otra— y la posición
  /// señalaría otra cosa sin avisar.
  ({apartados.ApartadoDeAdministra apartado, List<apartados.PestanaDeApartado> pestanas})
  _apartadoActivo(
    List<({apartados.ApartadoDeAdministra apartado, List<apartados.PestanaDeApartado> pestanas})>
    visibles, {
    required bool esMaestro,
    required Set<String> permisos,
  }) {
    final recordada = _rutaDeSeccion;

    if (recordada != null) {
      for (final v in visibles) {
        if (v.apartado.ruta == recordada) return v;
      }
    }

    final primero = apartados.primerApartadoConPantalla(
      esMaestro: esMaestro,
      permisos: permisos,
    );

    for (final v in visibles) {
      if (v.apartado.ruta == primero?.ruta) return v;
    }

    // NINGUNO DE LOS VISIBLES ES «EL PRIMERO CON PANTALLA»: no debería pasar, porque
    // los dos salen del mismo registro. Si pasara, se abre el primero visible, que
    // por definición tiene algo dentro.
    //
    // Y LA LISTA NO PUEDE ESTAR VACÍA AQUÍ: quien no tiene ningún apartado visible no
    // llega a este método — el `build` lo recibe antes con la bienvenida.
    return visibles.first;
  }

  /// Qué se pinta dentro del apartado activo: el aviso amable, una pantalla, o las
  /// pestañas con la pantalla de la elegida.
  Widget _cuerpoDelApartado(
    apartados.ApartadoDeAdministra apartado,
    List<apartados.PestanaDeApartado> pestanas,
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

    final elegida = _pestanaElegida(apartado, pestanas);

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
        : _pantallaDe(elegida, contexto);

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
            onChanged: (i) => setState(() {
              _pestanaPorApartado[apartado.ruta] = pestanas[i].id;
              _rastroDentro = null;
            }),
          ),
        ),
        Expanded(child: pantalla),
      ],
    );
  }

  /// Qué pestaña está elegida en este apartado.
  ///
  /// Se recuerda **por id y no por posición**: si una pestaña aparece o desaparece
  /// —porque cambió la empresa y con ella los permisos—, la posición señalaría otra
  /// cosa sin avisar.
  ///
  /// Sin nada recordado se abre **la primera DISPONIBLE**, no la primera de la lista:
  /// Organización empieza por Empresa, que todavía no tiene pantalla, y abrir ahí
  /// recibiría a todo el mundo con un «Próximamente» teniendo Sucursales al lado.
  apartados.PestanaDeApartado? _pestanaElegida(
    apartados.ApartadoDeAdministra apartado,
    List<apartados.PestanaDeApartado> pestanas,
  ) {
    if (pestanas.isEmpty) return null;

    final recordada = _pestanaPorApartado[apartado.ruta];

    for (final p in pestanas) {
      if (p.id == recordada) return p;
    }

    return apartados.primeraDisponible(pestanas) ?? pestanas.first;
  }

  /// La pantalla de una pestaña.
  ///
  /// EL `companyId` SALE DEL CONTEXTO QUE EL SERVIDOR CONFIRMÓ, nunca de la lista, de
  /// la preferencia guardada ni de la URL: es el único valor que ya pasó por
  /// `/context`.
  Widget _pantallaDe(
    apartados.PestanaDeApartado pestana,
    CompanyContext contexto,
  ) => switch (pestana.id) {
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
      guardia: _guardia,
      // E2 — la pestaña de administración, que **sólo existe con autoridad de
      // Organization**. Nula es el caso de la mayoría: un Maestro que no gobierna la
      // organización ve la ficha y nada más.
      organizationId: contexto.organizationId,
      autoridad: _autoridad,
      repositorioDeEmpresas: widget.repositorioDeEmpresas,
      cacheDeLogotipos: _logotipos,
      // CUANDO LA ADMINISTRACIÓN CAMBIA ALGO, el menú de la barra tiene que enterarse:
      // una empresa desactivada o descartada desaparece de él. Lo pide el gestor, que es
      // el dueño de la lista.
      alCambiarLasEmpresas: () => widget.gestorDeCompany.resolver(),
      puedeEditar: apartados.puedeEditarLaConfiguracionDeLaEmpresa(
        contexto.effectivePermissions,
      ),
      alCambiarElRastro: (dentro) => setState(() => _rastroDentro = dentro),
    ),
    'areas' => AreasWebScreen(
      repositorio: widget.repositorioDeAreas,
      empresaId: contexto.companyId,
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
      // EL RASTRO BAJA A LO QUE SE ABRA DENTRO. Tipos de sucursal no es una pestaña
      // —vive dentro de Sucursales, detrás de un botón—, así que el portón no se
      // enteraría de que se entró ahí y el rastro se quedaba en «› Sucursales».
      alCambiarElRastro: (nombre) => setState(() => _rastroDentro = nombre),
    ),
    'puestos' => PuestosWebScreen(
      repositorio: widget.repositorioDePuestos,
      // LAS ÁREAS, PARA EL SELECTOR Y PARA LA LISTA: el servidor manda `areaId`, no
      // el nombre, y un UUID en una lista no le dice nada a nadie.
      repositorioDeAreas: widget.repositorioDeAreas,
      empresaId: contexto.companyId,
      esMaestro: contexto.isMaestro,
      // El rol no basta, igual que en Áreas y Sucursales.
      capacidades: apartados.CapacidadesDeModulo.deLaOrganizacion(
        contexto.effectivePermissions,
      ),
      // SIN UN ÁREA ACTIVA NO SE PUEDE CREAR UN PUESTO, y quien decide qué pestaña
      // está abierta es el portón: la pantalla pide el cambio, no lo hace.
      alIrAAreas: () => setState(
        () => _pestanaPorApartado['/organizacion'] = 'areas',
      ),
    ),
    'usuarios' => UsuariosWebScreen(
      repositorio: widget.repositorioDeUsuarios,
      empresaId: contexto.companyId,
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
        return _Mensaje(
          titulo: 'Todavía no tienes ninguna empresa',
          cuerpo:
              'Tu cuenta está lista, pero nadie te ha dado acceso a una empresa. '
              'Pídelo a quien administra la tuya.',
          alCerrarSesion: _cerrarSesion,
        );

      case SeleccionDeCompanyRequerida(:final disponibles, :final recordada):
        final sesion = widget.gestorDeSesion.estado;

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
          usuario: sesion is Autenticado ? sesion.sesion.displayName ?? '' : '',
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
