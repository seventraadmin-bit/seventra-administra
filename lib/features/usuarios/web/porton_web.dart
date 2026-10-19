import 'package:flutter/material.dart';

import '../../../core/auth/gestor_de_sesion.dart';
import '../../../core/auth/sesion_remota.dart';
import '../../../core/company/company_remota.dart';
import '../../../core/company/gestor_de_company.dart';
import '../../../app/shell/apartados_web.dart' as apartados;
import '../../../app/shell/shell_destinations.dart';
import '../../../core/design_system/design_system_web.dart';
import '../../organizacion/web/datos/areas_repositorio_http.dart';
import '../../organizacion/web/datos/sucursales_repositorio_http.dart';
import '../../organizacion/web/presentation/areas_web_screen.dart';
import '../../organizacion/web/presentation/sucursales_web_screen.dart';

import 'datos/usuarios_repositorio_http.dart';
import 'login_web_screen.dart';
import 'marca_seventra.dart';
import 'marco_administra.dart';
import 'mensajes_humanos.dart';
import 'presentation/auditoria_web_screen.dart';
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
    required this.gestorDeSesion,
    required this.gestorDeCompany,
    required this.repositorioDeAreas,
    required this.repositorioDeSucursales,
    required this.repositorioDeUsuarios,
    super.key,
  });

  final GestorDeSesion gestorDeSesion;
  final GestorDeCompany gestorDeCompany;
  final AreasRepositorioHttp repositorioDeAreas;
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

  /// La empresa activa, dentro del marco de Administra.
  ///
  /// EL MARCO SE MONTA AQUÍ Y NO DENTRO DE CADA PANTALLA, y es la misma razón por la
  /// que el portón es el único que decide qué se ve: si cada sección dibujara su
  /// propia barra lateral, las nueve acabarían pareciéndose sólo por casualidad.
  ///
  /// **EL MENÚ COMPLETO ESTÁ DESDE EL PRIMER DÍA.** Los nueve apartados salen de
  /// `apartados_web.dart`, y los que todavía no tienen pantalla aparecen con
  /// «Próximamente». Enseñar sólo lo mudado dejaría a un cliente sin saber si el resto
  /// llegará o si el producto no lo tiene.
  Widget _conMarco(CompanyContext contexto) {
    final sesion = widget.gestorDeSesion.estado;
    final identidad = sesion is Autenticado ? sesion.sesion : null;

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
    // SE DISTINGUEN TRES CASOS, Y CONFUNDIR LOS DOS ÚLTIMOS SERÍA MENTIR:
    //
    //  · tiene algo que abrir para ti            → se abre;
    //  · NO está mudado                          → «Próximamente»;
    //  · mudado pero nada para ti                → **no aparece**.
    //
    // El tercero es real: alguien que no es Maestro y no puede leer la auditoría no
    // tiene nada que hacer en Configuración. Ponerle «Próximamente» le diría que está
    // por llegar, cuando lo que pasa es que no es para él.
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

    final destinos = [
      for (final v in visibles)
        ShellDestination(
          path: v.apartado.ruta,
          label: v.apartado.nombre,
          icon: v.apartado.icono,
          // PRÓXIMAMENTE SIGNIFICA «NO ESTÁ MUDADO», y nada más. Es la única lectura
          // que no engaña a nadie.
          proximamente: !v.apartado.mudado,
        ),
    ];

    final activo = _apartadoActivo(visibles, esMaestro: esMaestro, permisos: permisos);
    final pestanaActiva = _pestanaElegida(activo.apartado, activo.pestanas);

    return MarcoAdministra(
      destinos: destinos,
      indiceActivo: visibles.indexOf(activo),
      alElegirDestino: (i) =>
          setState(() => _rutaDeSeccion = visibles[i].apartado.ruta),
      empresa: contexto.companyName,
      // El nombre puede no venir: `/auth/refresh` responde con `displayName` nulo,
      // así que una sesión restaurada no lo trae y hay que tolerar su ausencia.
      usuario: identidad?.displayName ?? '',
      correo: identidad?.email ?? '',
      alCerrarSesion: _cerrarSesion,
      alCambiarEmpresa: varias
          ? () => widget.gestorDeCompany.olvidarSeleccion()
          : null,
      // EL RASTRO DICE LAS DOS COSAS: «Configuración › Usuarios». Con sólo el
      // apartado, dos pestañas distintas se leían igual.
      pestana: activo.pestanas.length > 1 ? pestanaActiva?.nombre : null,
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

    // NINGÚN APARTADO CON PANTALLA sería un producto sin nada dentro. No debería
    // pasar —siempre hay estructura— y si pasara, abrir el primero del menú es lo
    // único que queda; su propio «Próximamente» lo explica.
    return visibles.first;
  }

  /// Qué se pinta dentro del apartado activo: el aviso amable, una pantalla, o las
  /// pestañas con la pantalla de la elegida.
  Widget _cuerpoDelApartado(
    apartados.ApartadoDeAdministra apartado,
    List<apartados.PestanaDeApartado> pestanas,
    CompanyContext contexto,
  ) {
    if (pestanas.isEmpty) {
      return _Proximamente(titulo: apartado.nombre, icono: apartado.icono);
    }

    final elegida = _pestanaElegida(apartado, pestanas);

    // UNA PESTAÑA SIN PANTALLA DICE LO MISMO QUE UN APARTADO SIN PANTALLA, y con su
    // propio nombre: «Puestos — Próximamente», no el del apartado.
    final pantalla = elegida == null || !elegida.mudada
        ? _Proximamente(
            titulo: elegida?.nombre ?? apartado.nombre,
            icono: apartado.icono,
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
            tabs: [for (final p in pestanas) RisegTabItem(label: p.nombre)],
            // `indexOf(null)` daría -1 y rompería la barra; con pestañas no vacías
            // `elegida` nunca es nula, y el `?? 0` lo deja escrito en vez de confiado.
            selectedIndex: elegida == null ? 0 : pestanas.indexOf(elegida),
            onChanged: (i) => setState(
              () => _pestanaPorApartado[apartado.ruta] = pestanas[i].id,
            ),
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
    'areas' => AreasWebScreen(
      repositorio: widget.repositorioDeAreas,
      empresaId: contexto.companyId,
    ),
    'sucursales' => SucursalesWebScreen(
      repositorio: widget.repositorioDeSucursales,
      empresaId: contexto.companyId,
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

      case SeleccionDeCompanyRequerida(:final disponibles):
        return SelectorDeEmpresaScreen(
          gestor: widget.gestorDeCompany,
          disponibles: disponibles,
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
/// **NO ES UN ERROR Y NO SE DISCULPA DE MÁS.** Dice qué va a haber ahí y dónde está
/// hoy, que es lo único que una persona puede hacer con esa información: seguir
/// usando el escritorio para eso. Un «no disponible» a secas deja a alguien pensando
/// que compró algo que no funciona.
class _Proximamente extends StatelessWidget {
  const _Proximamente({required this.titulo, required this.icono});

  final String titulo;
  final IconData icono;

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
                Text(
                  'Este apartado todavía se usa desde la aplicación de escritorio. '
                  'Lo estamos trayendo a la web módulo por módulo, y cuando llegue '
                  'aparecerá aquí sin que tengas que hacer nada.',
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
