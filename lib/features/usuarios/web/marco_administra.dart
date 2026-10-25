import 'package:flutter/material.dart';

import '../../../app/shell/shell_breakpoints.dart';
import '../../../app/shell/shell_destinations.dart';
import '../../../app/shell/sidebar_mode_controller.dart';
import '../../../app/shell/widgets/app_breadcrumb.dart';
import '../../../app/shell/widgets/app_sidebar.dart';
import '../../../core/company/company_remota.dart';
import '../../../core/company/logotipos_de_empresa.dart';
import '../../../core/design_system/design_system_web.dart';
import 'tarjeta_de_empresa.dart';

/// El marco de **Administra en la nube**.
///
/// ⚠️ **NO DIBUJA UN MARCO PROPIO: REUTILIZA EL DEL ESCRITORIO.** La primera
/// versión de este archivo componía su propia barra lateral, con su propio azul
/// marino y su propia opción activa. Se veía bien y estaba mal: la web tiene que
/// verse **igual** que el producto que ya existe, no parecida.
///
/// Lo que se reutiliza, tal cual y sin copiar una línea:
///
/// ```
///   AppSidebar          la barra entera: color, ítems, hover, foco,
///                       encabezado con el logotipo, botón de encoger
///   AppBreadcrumb       el título de sección de la barra superior
///   ShellDestination    la forma de un destino
///   ShellBreakpoints    los anchos: 224 expandida, 80 encogida, umbrales
///   resolveSidebarCollapsed  cuándo se encoge sola
///   AppColorScheme      los colores, incluidos los del shell
/// ```
///
/// **`AppSidebar` se puede reutilizar porque fue escrito para eso**: su propio
/// documento dice que es «widget de presentación puro: no lee providers —recibe
/// `collapsed` ya resuelto y notifica hacia arriba—, así se puede probar y
/// reutilizar sin depender de Riverpod». Aquí se cobra esa decisión.
///
/// LO QUE SÍ ES PROPIO DE LA WEB, y sólo esto:
///
///  · **la barra superior**, porque la del escritorio (`AppTopBar`) es un
///    `ConsumerWidget` que depende de Riverpod, del buscador global y de las
///    notificaciones —dos features que la web todavía no tiene—. Se copia su
///    **geometría exacta**: 64 px de alto, fondo `colors.surface`, el mismo
///    `AppBreadcrumb` a la izquierda y el perfil a la derecha;
///  · **el pie de la barra con la empresa activa**, que el escritorio no tiene
///    porque allí no hay varias empresas.
///
/// ⏳(D-45) Buscador global y notificaciones quedan para cuando esos módulos se muden.
class MarcoAdministra extends StatefulWidget {
  const MarcoAdministra({
    required this.destinos,
    required this.indiceActivo,
    required this.alElegirDestino,
    required this.empresa,
    required this.usuario,
    required this.correo,
    required this.alCerrarSesion,
    required this.cuerpo,
    required this.logotipos,
    this.pestana,
    this.dentroDeLaPestana,
    this.empresas = const [],
    this.empresaActivaId,
    this.alElegirEmpresa,
    this.restringida = false,
    super.key,
  });

  final List<ShellDestination> destinos;
  final int indiceActivo;
  final ValueChanged<int> alElegirDestino;

  /// El nombre de la **empresa activa**, el que confirmó el servidor.
  final String empresa;

  /// Si la suscripción de esta empresa está **limitada**: se consulta, no se guarda.
  ///
  /// ## Por qué se avisa aquí y no sólo al fallar (D-46)
  ///
  /// Porque el 402 llega **después** de haber escrito el formulario, y enterarse entonces
  /// significa haber hecho el trabajo dos veces. Lo trae el contexto de la empresa
  /// —`CompanyContext.restricted`— y va en la franja del pie, que es donde vive el contexto
  /// permanente: no es una acción ni una alarma, es una propiedad de la empresa en la que
  /// se está trabajando.
  ///
  /// NO DESHABILITA NADA. Quien decide si una escritura procede es el servidor, y una
  /// pantalla que apaga sus botones por su cuenta acaba apagándolos cuando no debía — con
  /// el agravante de que nadie puede ver el mensaje que lo explica. Esto informa; el 402
  /// sigue siendo quien manda, traducido por `MensajesHumanos.deMutacion`.
  final bool restringida;

  /// La pestaña abierta dentro del apartado, para el rastro: «Configuración ›
  /// Usuarios».
  ///
  /// Nula cuando el apartado no tiene pestañas o tiene una sola — con una, repetir su
  /// nombre en el rastro no añade nada.
  final String? pestana;

  /// Lo que se abrió **dentro** de la pestaña: «Organización › Sucursales › Tipos de
  /// sucursal».
  ///
  /// Nula casi siempre. Hoy sólo la usa Tipos de sucursal, que **no es una pestaña**:
  /// vive dentro de Sucursales detrás de un botón, así que quien la abre tiene que
  /// avisar — el marco no puede adivinarlo.
  final String? dentroDeLaPestana;

  final String usuario;
  final String correo;

  final Future<void> Function() alCerrarSesion;

  /// Todas las empresas a las que se tiene acceso, para el menú de la barra.
  ///
  /// Vacía o con una sola, **no hay menú**: el nombre es texto plano, porque un botón
  /// que no lleva a ninguna parte es peor que ningún botón.
  final List<CompanyDisponible> empresas;

  /// El `companyId` de la activa, para marcarla en el menú y no ofrecerla.
  final String? empresaActivaId;

  /// Qué hacer cuando se elige otra empresa.
  ///
  /// **El marco no cambia de empresa, sólo dice cuál se eligió.** Preguntar por los
  /// cambios sin guardar, llamar al gestor y anunciar el resultado es del portón, que
  /// es quien tiene el gestor y el guardia de salida. Si el marco lo hiciera, el cambio
  /// de empresa viviría en la pieza que pinta la cáscara.
  final Future<void> Function(CompanyDisponible)? alElegirEmpresa;

  /// De dónde salen los logotipos de las tarjetas del menú.
  final LogotiposDeEmpresa logotipos;

  final Widget cuerpo;

  @override
  State<MarcoAdministra> createState() => _MarcoAdministraState();
}

class _MarcoAdministraState extends State<MarcoAdministra> {
  /// El modo lo decide quien usa la aplicación; si está encogida o no es un
  /// **resultado** de combinarlo con el tamaño disponible. Es exactamente el
  /// modelo del escritorio, y por eso se usa su mismo tipo y su misma función.
  ///
  /// En el escritorio esto vive en un controlador de Riverpod que lo recuerda
  /// entre arranques; aquí vive en el estado del widget. La diferencia es
  /// deliberada: la web todavía no tiene dónde guardar preferencias de interfaz,
  /// y fingir que las guarda sería peor que no hacerlo.
  SidebarMode _modo = SidebarMode.automatico;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      key: const Key('marco_administra'),
      body: LayoutBuilder(
        builder: (context, limites) {
          final encogida = resolveSidebarCollapsed(
            mode: _modo,
            availableWidth: limites.maxWidth,
            availableHeight: limites.maxHeight,
          );

          return Row(
            children: [
              // LA BARRA DEL ESCRITORIO, SIN TOCARLA. Trae su color —`tinta`—,
              // su opción activa con el velo blanco, su hover, su anillo de
              // foco, su encabezado con el logotipo y su botón de encoger.
              //
              // EN PANTALLA ANGOSTA NO SE VA ARRIBA: se encoge al raíl de 80 px
              // con sólo los íconos, que es lo que hace el escritorio. La barra
              // superior de navegación que tenía la versión anterior era un
              // invento, y además dejaba la aplicación con dos lenguajes de
              // navegación distintos según el ancho.
              AppSidebar(
                destinations: widget.destinos,
                activeIndex: widget.indiceActivo,
                collapsed: encogida,
                onDestinationSelected: widget.alElegirDestino,
                onToggleCollapse: () => setState(() {
                  _modo = encogida
                      ? SidebarMode.expandidoForzado
                      : SidebarMode.colapsadoForzado;
                }),
              ),
              Expanded(
                child: Column(
                  children: [
                    _BarraSuperior(marco: widget, encogida: encogida),
                    Expanded(
                      child: Container(
                        key: const Key('marco_area_de_contenido'),
                        // `scaffoldBackgroundColor` —el `canvas`—, NUNCA
                        // `surface`. Es la jerarquía de tres niveles del
                        // escritorio: barra en tinta, barra superior en
                        // `surface`, área de trabajo en `canvas`. Las tarjetas
                        // de cada pantalla usan `surface` por su cuenta, y por
                        // eso se separan del fondo.
                        //
                        // AQUÍ ESTABA LA «COLUMNA BLANCA CENTRADA»: la versión
                        // anterior metía el contenido en un `Center` con ancho
                        // máximo sobre un `Scaffold` blanco, y el resultado era
                        // una tira clara flotando. El contenido ocupa el ancho.
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: widget.cuerpo,
                      ),
                    ),
                    _PieDeEmpresa(marco: widget, colors: colors),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// La barra superior: **la geometría de `AppTopBar`, sin sus dependencias**.
///
/// 64 px, fondo `surface` y sin borde inferior —el bloque de color ya separa—.
/// A la izquierda el mismo `AppBreadcrumb` del escritorio; a la derecha, el
/// perfil. El buscador global, el selector de tema y las notificaciones **no
/// están**: son features que la web todavía no tiene, y dibujarlas apagadas
/// prometería algo que no responde.
class _BarraSuperior extends StatelessWidget {
  const _BarraSuperior({required this.marco, required this.encogida});

  final MarcoAdministra marco;
  final bool encogida;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final destino = marco.destinos[marco.indiceActivo];

    return Container(
      key: const Key('marco_barra_superior'),
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      color: colors.surface,
      child: LayoutBuilder(
        builder: (context, limites) {
          // El mismo umbral del escritorio: por debajo, el perfil deja de
          // mostrar el nombre y conserva lo esencial.
          final perfilCompacto =
              limites.maxWidth < ShellBreakpoints.topBarProfileCompact;

          return Row(
            children: [
              Expanded(
                child: AppBreadcrumb(
                  // EL APARTADO Y, SI LA HAY, LA PESTAÑA. Con sólo el apartado,
                  // «Configuración» se leía igual estando en Usuarios o en Auditoría.
                  segments: [
                    BreadcrumbSegment(label: destino.label),
                    if (marco.pestana case final p?) BreadcrumbSegment(label: p),
                    if (marco.dentroDeLaPestana case final d?)
                      BreadcrumbSegment(label: d),
                  ],
                  activeColor: colors.textPrimary,
                  mutedColor: colors.textMuted,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              if (!perfilCompacto) ...[
                Text(
                  marco.correo,
                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              CircleAvatar(
                radius: 16,
                backgroundColor: colors.accentSoftBg,
                child: Text(
                  _inicial(marco.usuario, marco.correo),
                  style: AppTypography.caption.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              IconButton(
                key: const Key('marco_cerrar_sesion'),
                tooltip: 'Cerrar sesión',
                onPressed: marco.alCerrarSesion,
                icon: Icon(Icons.logout, size: 20, color: colors.textMuted),
              ),
            ],
          );
        },
      ),
    );
  }

  /// La inicial del avatar. Del nombre si lo hay; si no, del correo —porque
  /// `/auth/refresh` no reenvía el nombre y una sesión restaurada llega sin él—.
  static String _inicial(String usuario, String correo) {
    final fuente = usuario.trim().isNotEmpty ? usuario.trim() : correo.trim();
    return fuente.isEmpty ? '?' : fuente.characters.first.toUpperCase();
  }
}

/// La franja de la empresa activa, al pie del área de contenido.
///
/// **No existe en el escritorio, y tiene que existir aquí:** allí se trabaja
/// siempre sobre la misma base, y en la nube una misma persona puede tener
/// acceso a varias empresas. Saber en cuál se está escribiendo no es un adorno.
///
/// Va abajo y no arriba a propósito: es contexto permanente, no una acción. Lo
/// que se consulta de vez en cuando no compite con el título de la sección.
///
/// ⚠️ **Y ES EL ÚNICO SITIO DONDE SE CAMBIA DE EMPRESA** (E1-B). Antes esta franja
/// llamaba a `olvidarSeleccion()`: borraba la preferencia y devolvía a la pantalla de
/// selección, desmontando la aplicación entera. Funcionaba, y era un portazo para algo
/// que debería ser un gesto pequeño. Ahora abre un menú y el cambio ocurre en el sitio.
class _PieDeEmpresa extends StatelessWidget {
  const _PieDeEmpresa({required this.marco, required this.colors});

  final MarcoAdministra marco;
  final AppColorScheme colors;

  /// Hay menú sólo con **más de una** empresa y con alguien que recoja la elección.
  bool get _hayMenu => marco.empresas.length > 1 && marco.alElegirEmpresa != null;

  Future<void> _abrirMenu(BuildContext context) async {
    // LA POSICIÓN SE MIDE, no se adivina: el menú tiene que salir pegado a la franja,
    // y la franja está donde el marco la haya puesto.
    final caja = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;

    if (caja == null || overlay == null) return;

    final esquina = caja.localToGlobal(Offset.zero, ancestor: overlay);

    final elegida = await showMenu<CompanyDisponible>(
      context: context,
      // SE ABRE HACIA ARRIBA. `showMenu` coloca el menú en el borde superior de este
      // rectángulo y lo sube si no cabe debajo; anclándolo al borde SUPERIOR de la
      // franja —que vive al pie— no cabe nada debajo, así que sube siempre.
      position: RelativeRect.fromLTRB(
        esquina.dx + AppSpacing.xl,
        esquina.dy,
        overlay.size.width - esquina.dx - caja.size.width,
        overlay.size.height - esquina.dy,
      ),
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
      items: [
        PopupMenuItem<CompanyDisponible>(
          enabled: false,
          height: 32,
          child: Text(
            'TUS EMPRESAS',
            style: AppTypography.caption.copyWith(
              color: colors.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
        for (final empresa in marco.empresas)
          PopupMenuItem<CompanyDisponible>(
            value: empresa,
            // LA ACTIVA NO SE PUEDE ELEGIR: cambiar a la que ya está sería un viaje al
            // servidor y un aviso para no mover nada. Se marca con ✓ y se queda.
            enabled: empresa.companyId != marco.empresaActivaId,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: TarjetaDeEmpresa(
              key: Key('menu_empresa_${empresa.companyId}'),
              empresa: empresa,
              logotipos: marco.logotipos,
              compacta: true,
              esLaActiva: empresa.companyId == marco.empresaActivaId,
              // SIN `alPulsar`: quien recoge el toque es el elemento del menú. Dos
              // superficies pulsables encajadas dejarían una de las dos sin disparar,
              // y cuál de ellas depende del orden de los `InkWell`.
              alPulsar: null,
            ),
          ),
      ],
    );

    if (elegida == null) return;

    await marco.alElegirEmpresa!(elegida);
  }

  @override
  Widget build(BuildContext context) {
    final etiqueta = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.apartment_outlined, size: 15, color: colors.textMuted),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            marco.empresa,
            style: AppTypography.caption.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (_hayMenu) ...[
          const SizedBox(width: AppSpacing.xs),
          Icon(Icons.unfold_more, size: 14, color: colors.textMuted),
        ],

        // LA SUSCRIPCIÓN LIMITADA, dicha antes de intentar guardar (D-46). Va junto al
        // nombre de la empresa porque es una propiedad de ESA empresa, y con el texto
        // completo: «limitada» a secas no dice qué se puede hacer.
        if (marco.restringida) ...[
          const SizedBox(width: AppSpacing.sm),
          Icon(Icons.lock_outline, size: 14, color: colors.warning),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              'Suscripción limitada: sólo consulta',
              key: const Key('marco_pie_suscripcion_limitada'),
              style: AppTypography.caption.copyWith(color: colors.warning),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );

    return Container(
      key: const Key('marco_pie_de_empresa'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: !_hayMenu
            ? etiqueta
            : Builder(
                // `Builder` PARA TENER EL CONTEXTO DE ESTE WIDGET, que es el que sabe
                // dónde está la franja en la pantalla. El contexto del `build` de
                // arriba apunta al `Container` entero y daría una posición distinta.
                builder: (contextoDelBoton) => InkWell(
                  key: const Key('marco_cambiar_empresa'),
                  onTap: () => _abrirMenu(contextoDelBoton),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: 2,
                    ),
                    child: etiqueta,
                  ),
                ),
              ),
      ),
    );
  }
}
