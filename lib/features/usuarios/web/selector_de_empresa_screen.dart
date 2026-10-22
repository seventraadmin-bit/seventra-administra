import 'package:flutter/material.dart';

import '../../../core/company/company_remota.dart';
import '../../../core/company/gestor_de_company.dart';
import '../../../core/company/logotipos_de_empresa.dart';
import '../../../core/design_system/design_system_web.dart';
import '../../../core/branding/marca_producto.dart';
import '../presentation/auth/widgets/auth_identity_panel.dart';
import 'mensajes_humanos.dart';
import 'tarjeta_de_empresa.dart';

/// Ancho mínimo para la composición de dos zonas. **El mismo número que el login**, y
/// por el mismo motivo: por debajo, la zona decorativa se oculta entera en vez de
/// encogerse hasta no decir nada.
const double _anchoDosZonas = 900;

/// Las tarjetas son más anchas que el formulario del login —380— porque llevan un
/// recuadro de logotipo, tres líneas de texto y una insignia. A 380 la razón social se
/// parte en dos renglones en el caso más común.
const double _anchoDeLasTarjetas = 440;

/// Elegir con qué empresa entrar.
///
/// 🚫 **ESTA PANTALLA NO SE VE CUANDO HAY UNA SOLA EMPRESA**, y no porque aquí se
/// compruebe: `GestorDeCompany` resuelve ese caso antes de publicar un estado. Si además
/// se comprobara aquí, habría dos sitios decidiendo lo mismo y podrían discrepar. Esta
/// pantalla sólo existe para el estado [SeleccionDeCompanyRequerida], y el portón es
/// quien la monta.
///
/// ⚠️ **CON VARIAS EMPRESAS SE PREGUNTA SIEMPRE** (E1-B, 21 de octubre de 2026). Antes,
/// una preferencia válida abría su empresa sin preguntar y esta pantalla sólo se veía la
/// primera vez. Se cambió por dos razones: entrar a trabajar en una empresa sin haberlo
/// pedido es la misma clase de sorpresa que hizo retirar la lista de Organización ›
/// Empresa, y la insignia «Última vez» no se podía ver nunca.
///
/// **ES LA ESTÉTICA DEL LOGIN, NO UNA PARECIDA.** Reutiliza [AuthIdentityPanel] —el
/// panel oscuro con la palomita recortada contra el borde—, la proporción 4 : 5 y el
/// umbral de 900 px. La primera versión de esta pantalla componía su propia tarjeta
/// centrada sobre fondo claro, y al lado del login parecía de otro producto.
///
/// **El orden es el del servidor —por Organization y luego por nombre— con una sola
/// excepción: la recordada va primera.** No se reordena por nada más: sería duplicar una
/// decisión ya tomada, y divergiría el día que el backend la cambie.
class SelectorDeEmpresaScreen extends StatefulWidget {
  const SelectorDeEmpresaScreen({
    required this.gestor,
    required this.disponibles,
    required this.logotipos,
    required this.alCerrarSesion,
    this.recordada,
    this.usuario = '',
    super.key,
  });

  final GestorDeCompany gestor;

  /// Las empresas a elegir, **tal como llegaron en el estado**.
  ///
  /// Se reciben en vez de leerse de `gestor.disponibles` para que lo que se pinta sea
  /// exactamente lo que el estado dijo. Leerlas del gestor abriría la ventana de pintar
  /// una lista que otra resolución ya cambió.
  final List<CompanyDisponible> disponibles;

  /// De dónde salen los logotipos. Se recibe por constructor: esta pantalla no habla con
  /// la capa HTTP, y el guardia de arquitectura lo comprueba.
  final LogotiposDeEmpresa logotipos;

  /// El `companyId` de la última empresa usada, si sigue siendo accesible.
  final String? recordada;

  /// El nombre de quien entró, para el saludo.
  ///
  /// **Puede venir vacío, y entonces no hay saludo.** `/auth/refresh` responde con
  /// `displayName` nulo, así que una sesión restaurada no lo trae. Un «Hola, » colgando
  /// sería peor que no saludar, y el correo de relleno convertiría un saludo en un dato
  /// técnico.
  final String usuario;

  /// Para salir de una cuenta que no es la que se quería. Sin esto, quien entra con el
  /// correo equivocado se queda mirando empresas ajenas sin ninguna salida.
  final Future<void> Function() alCerrarSesion;

  @override
  State<SelectorDeEmpresaScreen> createState() =>
      _SelectorDeEmpresaScreenState();
}

class _SelectorDeEmpresaScreenState extends State<SelectorDeEmpresaScreen> {
  /// Cuál se está abriendo. Es el id y no un `bool` porque hay que señalar **esa**
  /// tarjeta mientras las demás se apagan; un `bool` las haría parpadear todas.
  String? _abriendo;

  String? _error;

  /// Las empresas en el orden en que se pintan: **la recordada primero**, el resto tal
  /// como las entregó el servidor.
  ///
  /// Se calcula una vez por construcción y no se guarda en el estado: depende sólo de lo
  /// que llegó por constructor, y guardarlo abriría la posibilidad de que el orden y la
  /// lista se desincronizaran.
  List<CompanyDisponible> get _enOrden {
    final recordada = widget.recordada;
    if (recordada == null) return widget.disponibles;

    final primera = <CompanyDisponible>[];
    final resto = <CompanyDisponible>[];

    for (final empresa in widget.disponibles) {
      (empresa.companyId == recordada ? primera : resto).add(empresa);
    }

    return [...primera, ...resto];
  }

  Future<void> _abrir(CompanyDisponible empresa) async {
    setState(() {
      _abriendo = empresa.companyId;
      _error = null;
    });

    final resultado = await widget.gestor.cambiarA(empresa.companyId);

    if (!mounted) return;

    resultado.when(
      // NO SE NAVEGA DESDE AQUÍ, igual que en el login: el gestor publica
      // `CompanyActiva` y el portón decide. Esta pantalla sólo se queda esperando a que
      // la desmonten.
      ok: (_) => setState(() => _abriendo = null),
      failure: (fallo) => setState(() {
        _abriendo = null;
        _error = MensajesHumanos.deEmpresa(fallo);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.canvas,
      body: LayoutBuilder(
        builder: (context, limites) {
          final dosZonas = limites.maxWidth >= _anchoDosZonas;
          final eleccion = _Eleccion(estado: this, colors: colors);

          if (dosZonas) {
            return Row(
              children: [
                // LA MISMA PROPORCIÓN QUE EL LOGIN: 4 de panel, 5 de contenido.
                const Expanded(
                  flex: 4,
                  child: AuthIdentityPanel(
                    bienvenidaTitulo: 'Bienvenido a Seventra Administra',
                    bienvenidaMensaje:
                        'Elige con qué empresa quieres trabajar. '
                        'Podrás cambiar en cualquier momento desde la barra de abajo.',
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      child: eleccion,
                    ),
                  ),
                ),
              ],
            );
          }

          // Angosto: el panel decorativo se va entero y queda el logotipo arriba, igual
          // que en el login.
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
                    key: Key('selector_logo'),
                    ancho: 260,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  eleccion,
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Eleccion extends StatelessWidget {
  const _Eleccion({required this.estado, required this.colors});

  final _SelectorDeEmpresaScreenState estado;
  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final abriendo = estado._abriendo != null;
    final empresas = estado._enOrden;
    final nombre = estado.widget.usuario.trim();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _anchoDeLasTarjetas),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // EL SALUDO SÓLO SI HAY NOMBRE. Lo explica `SelectorDeEmpresaScreen.usuario`.
          if (nombre.isNotEmpty) ...[
            Text(
              'Hola, $nombre',
              key: const Key('selector_saludo'),
              style: AppTypography.body.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: AppSpacing.xxs),
          ],
          const Text('Elige una empresa', style: AppTypography.heading2),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            // SE DICE CUÁNTAS, porque es la respuesta a «¿por qué me preguntan esto?».
            'Tienes acceso a ${empresas.length}. Podrás cambiar después.',
            style: AppTypography.body.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.xl),

          if (estado._error != null) ...[
            _Aviso(mensaje: estado._error!, colors: colors),
            const SizedBox(height: AppSpacing.md),
          ],

          for (final empresa in empresas)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: TarjetaDeEmpresa(
                key: Key('selector_empresa_${empresa.companyId}'),
                empresa: empresa,
                logotipos: estado.widget.logotipos,
                ultimaVez: empresa.companyId == estado.widget.recordada,
                ocupada: estado._abriendo == empresa.companyId,
                // Mientras una se abre, las demás se apagan: dos selecciones a la vez
                // dejarían a la segunda ganando la carrera, y se entraría a la que no
                // se pulsó último. La que se está abriendo **no** se apaga: lleva el
                // giro, y apagarla además la haría parecer descartada.
                apagada: abriendo && estado._abriendo != empresa.companyId,
                alPulsar: abriendo ? null : () => estado._abrir(empresa),
              ),
            ),

          const SizedBox(height: AppSpacing.sm),
          Center(
            child: TextButton(
              key: const Key('selector_otra_cuenta'),
              onPressed: abriendo ? null : estado.widget.alCerrarSesion,
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
/// **Sin icono de alarma ni fondo rojo saturado**, igual que en el login: lo más común
/// aquí es un 402 de suscripción restringida o un bache de red, y pintarlo como
/// catástrofe convierte un reintento en un sobresalto.
class _Aviso extends StatelessWidget {
  const _Aviso({required this.mensaje, required this.colors});

  final String mensaje;
  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('selector_aviso'),
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
