import 'package:flutter/material.dart';

import '../../../../core/branding/marca_producto.dart';
import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../../../usuarios/presentation/auth/widgets/auth_identity_panel.dart';
import '../datos/empresas_repositorio_http.dart';
import '../modelos/organizacion_propia.dart';
import 'campos_de_alta_de_empresa.dart';

/// Ancho mínimo para la composición de dos zonas. **El mismo número que el login y que
/// el selector de empresa**, y por el mismo motivo: por debajo, la zona decorativa se
/// oculta entera en vez de encogerse hasta no decir nada.
const double _anchoDosZonas = 900;

const double _anchoDelFormulario = 440;

/// E3 · **Crea tu primera empresa.**
///
/// ## Por qué existe
///
/// Una Organization recién vendida no tiene ninguna empresa, y hasta E3 eso era un
/// callejón sin salida: la pantalla que sabe crearlas —la administración de E2— vive
/// **dentro** del marco de la aplicación, detrás de un `CompanyContext` confirmado. Sin
/// empresa no hay contexto, sin contexto no hay pestañas, y sin pestañas no había forma
/// de crear la primera. Quien contrataba quedaba esperando a que SEVENTRA se la creara
/// por la API.
///
/// ## Es una ANTESALA, no una pestaña
///
/// Por eso lleva la estética del login y del selector de empresa —[AuthIdentityPanel],
/// la proporción 4 : 5, el umbral de 900 px— y **no** el marco de Administra: no hay
/// empresa, así que no hay barra inferior, no hay rastro y no hay menú. Es la cuarta
/// pantalla de esa secuencia visual, y quien llega aquí viene de las otras tres.
///
/// ## 🚫 Lo que esta pantalla NO decide
///
/// **Si quien mira puede crear una empresa.** Eso lo resuelve el portón antes de
/// montarla, leyendo `GET /organizations/{id}/membership` por cada Organization, y aquí
/// sólo llegan [organizaciones] **donde ya consta la autoridad**. Comprobarlo también
/// aquí serían dos sitios decidiendo lo mismo, y el día que uno cambiara discreparían.
///
/// **Cuánto incluye el plan.** Nada de «tu plan incluye una empresa»: esa cifra
/// necesita el lector de capacidad que Administra todavía no tiene, y escribirla a mano
/// sería inventarla. Si el servidor niega por capacidad, se enseña **su** mensaje, que
/// trae las dos cifras de verdad.
class PrimeraEmpresaScreen extends StatefulWidget {
  const PrimeraEmpresaScreen({
    required this.repositorio,
    required this.organizaciones,
    required this.alCreada,
    required this.alCerrarSesion,
    this.usuario = '',
    super.key,
  });

  final EmpresasRepositorioHttp repositorio;

  /// Las Organizations donde **ya consta** que esta persona puede crear empresas.
  ///
  /// Nunca llega vacía: sin ninguna, el portón enseña el mensaje de siempre y no monta
  /// esta pantalla.
  final List<OrganizacionPropia> organizaciones;

  /// Se llama **después** de que el servidor confirmó la creación.
  ///
  /// Quien la recibe vuelve a resolver la empresa activa, y con una sola empresa el
  /// gestor entra directo en ella. Esta pantalla no navega: igual que el login y el
  /// selector, sólo avisa y espera a que la desmonten.
  final Future<void> Function() alCreada;

  /// Para salir de una cuenta que no es la que se quería.
  final Future<void> Function() alCerrarSesion;

  /// El nombre de quien entró, para el saludo. **Puede venir vacío**, y entonces no hay
  /// saludo: `/auth/refresh` responde con `displayName` nulo, y un «Hola, » colgando
  /// sería peor que no saludar.
  final String usuario;

  @override
  State<PrimeraEmpresaScreen> createState() => _PrimeraEmpresaScreenState();
}

class _PrimeraEmpresaScreenState extends State<PrimeraEmpresaScreen> {
  /// Dónde va a nacer la empresa.
  ///
  /// **Con una sola Organization se elige sola**, que es la regla de E1-B aplicada
  /// aquí: con varias se pregunta siempre, con una no se pregunta nada. Con varias
  /// empieza nula y la pantalla enseña primero la lista.
  OrganizacionPropia? _donde;

  String _nombre = '';
  String _razonSocial = '';

  bool _creando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.organizaciones.length == 1) _donde = widget.organizaciones.single;
  }

  bool get _puedeCrear => _nombre.trim().isNotEmpty && !_creando;

  /// Elige la Organization donde nacerá la empresa. Sólo se llega aquí con varias.
  void _elegir(OrganizacionPropia organizacion) =>
      setState(() => _donde = organizacion);

  /// El nombre se anota CON `setState` porque de él depende el botón; la razón social
  /// no, porque no habilita nada y repintar en cada tecla sería trabajo para nada.
  void _anotarNombre(String valor) => setState(() => _nombre = valor);

  Future<void> _crear() async {
    // EL NOMBRE VACÍO NO LLEGA AL SERVIDOR. No es por ahorrar una petición: es que el
    // 400 que contestaría es indistinguible de un problema real para quien lo lee.
    if (!_puedeCrear) return;

    final donde = _donde;
    if (donde == null) return;

    setState(() {
      _creando = true;
      _error = null;
    });

    final resultado = await widget.repositorio.crear(
      organizationId: donde.organizationId,
      nombre: _nombre.trim(),
      // Vacía es ausente, y el servidor la normaliza igual. Se manda tal cual para que
      // la regla viva en un sitio y no en dos.
      razonSocial: _razonSocial.trim().isEmpty ? null : _razonSocial.trim(),
    );

    if (!mounted) return;

    await resultado.when(
      ok: (_) async {
        // NO SE APAGA `_creando` EN EL CAMINO FELIZ: la empresa existe y el portón está
        // a punto de desmontar esta pantalla. Devolver los campos a su estado editable
        // durante ese instante invitaría a un segundo clic, y un segundo clic crearía
        // una segunda empresa.
        await widget.alCreada();
      },
      failure: (fallo) async {
        if (!mounted) return;
        setState(() {
          _creando = false;
          _error = _humano(fallo);
        });
      },
    );
  }

  /// Lo que se le dice a una persona por cada respuesta del servidor.
  ///
  /// **La de capacidad se pasa tal cual**: el servidor manda las dos cifras —«tu plan
  /// permite N empresas y quedarían M»— y reescribirla las perdería.
  String _humano(Failure fallo) {
    if (fallo is! ApiHttpFailure) return fallo.message;

    return switch (fallo.codigo) {
      EmpresasRepositorioHttp.codigoSinAutoridad =>
        'Tu cuenta ya no tiene autoridad para crear empresas en esta '
            'organización. Pídelo a quien la administra.',

      // 404: la Organization dejó de estar disponible entre que se leyó la lista y se
      // envió el formulario. Se dice qué hacer, porque recargar SÍ lo arregla.
      'organizacion_no_disponible' =>
        'Esa organización ya no está disponible. Vuelve a entrar para '
            'actualizar la lista.',

      _ => fallo.message,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.canvas,
      body: LayoutBuilder(
        builder: (context, limites) {
          final contenido = _Contenido(estado: this, colors: colors);

          if (limites.maxWidth >= _anchoDosZonas) {
            return Row(
              children: [
                // LA MISMA PROPORCIÓN QUE EL LOGIN Y EL SELECTOR: 4 de panel, 5 de
                // contenido.
                const Expanded(
                  flex: 4,
                  child: AuthIdentityPanel(
                    bienvenidaTitulo: 'Bienvenido a Seventra Administra',
                    bienvenidaMensaje:
                        'Tu cuenta y tu plan ya están listos. Falta dar de alta '
                        'la empresa con la que vas a trabajar.',
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      child: contenido,
                    ),
                  ),
                ),
              ],
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: limites.maxHeight - AppSpacing.xl * 2,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const LogotipoProducto(
                    key: Key('primera_empresa_logo'),
                    ancho: 260,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  contenido,
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido({required this.estado, required this.colors});

  final _PrimeraEmpresaScreenState estado;
  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final nombre = estado.widget.usuario.trim();
    final donde = estado._donde;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _anchoDelFormulario),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (nombre.isNotEmpty) ...[
            Text(
              'Hola, $nombre',
              key: const Key('primera_empresa_saludo'),
              style: AppTypography.body.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: AppSpacing.xxs),
          ],

          if (donde == null) ...[
            const Text('¿Dónde creas tu empresa?', style: AppTypography.heading2),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              // SE PREGUNTA, NO SE ELIGE POR OMISIÓN: dónde nace una empresa es una
              // decisión demasiado grande para tomarla en silencio. Es la misma regla
              // que E1-B aplicó al selector.
              'Administras ${estado.widget.organizaciones.length} organizaciones. '
              'Elige en cuál.',
              style: AppTypography.body.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: AppSpacing.xl),

            for (final organizacion in estado.widget.organizaciones)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: RisegButton(
                  key: Key('primera_empresa_org_${organizacion.organizationId}'),
                  label: organizacion.nombre,
                  variant: RisegButtonVariant.secondary,
                  onPressed: () => estado._elegir(organizacion),
                ),
              ),
          ] else ...[
            const Text('Crea tu primera empresa', style: AppTypography.heading2),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              // SE DICE POR QUÉ, porque es la primera vez que alguien ve esto y la
              // pregunta natural es «¿y esto para qué?».
              'Administra organiza el personal, las sucursales y los clientes '
              'dentro de una empresa, así que es lo primero.',
              style: AppTypography.body.copyWith(color: colors.textMuted),
            ),

            // DÓNDE VA A NACER, dicho sólo cuando se eligió entre varias: con una sola
            // organización, nombrarla no añade nada y parece una decisión que no hubo.
            if (estado.widget.organizaciones.length > 1) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'En ${donde.nombre}.',
                key: const Key('primera_empresa_donde'),
                style: AppTypography.caption.copyWith(color: colors.textMuted),
              ),
            ],

            const SizedBox(height: AppSpacing.xl),

            if (estado._error != null) ...[
              _Aviso(mensaje: estado._error!, colors: colors),
              const SizedBox(height: AppSpacing.md),
            ],

            CamposDeAltaDeEmpresa(
              alEscribirNombre: estado._anotarNombre,
              alEscribirRazonSocial: (v) => estado._razonSocial = v,
              habilitado: !estado._creando,
              alEnviar: estado._crear,
            ),

            const SizedBox(height: AppSpacing.lg),

            RisegButton(
              key: const Key('primera_empresa_crear'),
              label: 'Crear empresa y entrar',
              loading: estado._creando,
              onPressed: estado._puedeCrear ? estado._crear : null,
            ),
          ],

          const SizedBox(height: AppSpacing.sm),
          Center(
            child: TextButton(
              key: const Key('primera_empresa_otra_cuenta'),
              onPressed: estado._creando ? null : estado.widget.alCerrarSesion,
              style: TextButton.styleFrom(foregroundColor: colors.textMuted),
              child: const Text('Entrar con otra cuenta'),
            ),
          ),
        ],
      ),
    );
  }
}

/// El aviso de que algo falló.
///
/// **Sin icono de alarma ni fondo rojo saturado**, igual que en el login y el selector:
/// lo más común aquí es que la capacidad del plan no alcance, y eso no es una
/// catástrofe, es una cifra.
class _Aviso extends StatelessWidget {
  const _Aviso({required this.mensaje, required this.colors});

  final String mensaje;
  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('primera_empresa_aviso'),
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    decoration: BoxDecoration(
      color: colors.errorBg,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Text(
      mensaje,
      style: AppTypography.body.copyWith(color: colors.error),
    ),
  );
}
