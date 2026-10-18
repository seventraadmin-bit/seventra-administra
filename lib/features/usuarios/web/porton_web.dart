import 'package:flutter/material.dart';

import '../../../core/auth/gestor_de_sesion.dart';
import '../../../core/auth/sesion_remota.dart';
import '../../../core/company/company_remota.dart';
import '../../../core/company/gestor_de_company.dart';
import '../../organizacion/web/datos/areas_repositorio_http.dart';
import '../../../app/shell/module_placeholder_screen.dart';
import '../../../app/shell/shell_destinations.dart';
import '../../organizacion/web/presentation/areas_web_screen.dart';
import 'login_web_screen.dart';
import 'marca_seventra.dart';
import 'marco_administra.dart';
import 'mensajes_humanos.dart';
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
    super.key,
  });

  final GestorDeSesion gestorDeSesion;
  final GestorDeCompany gestorDeCompany;
  final AreasRepositorioHttp repositorioDeAreas;

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

  /// Qué sección del menú se está viendo. Vive aquí y no en una URL porque la web
  /// todavía no tiene router: lo que se ve depende de la sesión y de la empresa,
  /// no de una dirección que alguien pueda escribir.
  int _indiceDeSeccion = 0;

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
  /// propia barra lateral, las cuatro acabarían pareciéndose sólo por casualidad, y
  /// la quinta ya no.
  Widget _conMarco(CompanyContext contexto) {
    final sesion = widget.gestorDeSesion.estado;
    final identidad = sesion is Autenticado ? sesion.sesion : null;

    // SÓLO SE OFRECE CAMBIAR DE EMPRESA SI HAY A DÓNDE. `disponibles` es la última
    // lista que devolvió el servidor; con una sola, el nombre es texto plano.
    final varias = widget.gestorDeCompany.disponibles.length > 1;

    final destinos = _destinosDeEstructura;
    final destino = destinos[_indiceDeSeccion];

    return MarcoAdministra(
      destinos: destinos,
      indiceActivo: _indiceDeSeccion,
      alElegirDestino: (i) => setState(() => _indiceDeSeccion = i),
      empresa: contexto.companyName,
      // El nombre puede no venir: `/auth/refresh` responde con `displayName` nulo,
      // así que una sesión restaurada no lo trae y hay que tolerar su ausencia.
      usuario: identidad?.displayName ?? '',
      correo: identidad?.email ?? '',
      alCerrarSesion: _cerrarSesion,
      alCambiarEmpresa: varias
          ? () => widget.gestorDeCompany.olvidarSeleccion()
          : null,
      cuerpo: destino.path == _rutaDeAreas
          ? AreasWebScreen(
              repositorio: widget.repositorioDeAreas,
              // EL `companyId` SALE DEL CONTEXTO QUE EL SERVIDOR CONFIRMÓ, nunca de
              // la lista, de la preferencia guardada ni de la URL. Es el único valor
              // que ya pasó por `/context`.
              empresaId: contexto.companyId,
            )
          // LO QUE TODAVÍA NO SE MUDA USA LA PANTALLA DEL PROPIO ESCRITORIO.
          //
          // La versión anterior marcaba esas entradas como «pendiente» y las dejaba
          // sin responder. Era lo que hace Console, no lo que hace Administra: aquí
          // el destino existe, se llega a él, y la pantalla dice que el módulo
          // todavía no está. Reutilizar `ModulePlaceholderScreen` evita además que
          // el rótulo «pendiente» robe el ancho de la etiqueta —que es por lo que
          // «Tipos de sucursal» salía cortado—.
          : ModulePlaceholderScreen(destination: destino),
    );
  }

  /// Dónde está la pantalla de Áreas dentro de la lista. Se compara por `path` y no
  /// por posición: reordenar el menú no debe cambiar qué pantalla se abre.
  static const String _rutaDeAreas = '/areas';

  /// Los cuatro destinos de Estructura, en el orden del escritorio.
  ///
  /// Son `ShellDestination`, el MISMO tipo que usa el escritorio, con los mismos
  /// íconos que `buildShellDestinations` asigna a Organización. No se inventa una
  /// clase de destino para la web.
  static const List<ShellDestination> _destinosDeEstructura = [
    ShellDestination(
      path: _rutaDeAreas,
      label: 'Áreas',
      icon: Icons.account_tree_outlined,
    ),
    ShellDestination(
      path: '/puestos',
      label: 'Puestos',
      icon: Icons.badge_outlined,
    ),
    ShellDestination(
      path: '/sucursales',
      label: 'Sucursales',
      icon: Icons.store_outlined,
    ),
    ShellDestination(
      path: '/tipos-de-sucursal',
      label: 'Tipos de sucursal',
      icon: Icons.category_outlined,
    ),
  ];

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
