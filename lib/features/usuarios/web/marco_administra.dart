import 'package:flutter/material.dart';

import '../../../app/shell/shell_breakpoints.dart';
import '../../../app/shell/shell_destinations.dart';
import '../../../app/shell/sidebar_mode_controller.dart';
import '../../../app/shell/widgets/app_breadcrumb.dart';
import '../../../app/shell/widgets/app_sidebar.dart';
import '../../../core/design_system/design_system_web.dart';

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
/// ⏳ Buscador global y notificaciones quedan para cuando esos módulos se muden.
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
    this.pestana,
    this.dentroDeLaPestana,
    this.alCambiarEmpresa,
    super.key,
  });

  final List<ShellDestination> destinos;
  final int indiceActivo;
  final ValueChanged<int> alElegirDestino;

  /// El nombre de la **empresa activa**, el que confirmó el servidor.
  final String empresa;

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

  /// Sólo cuando hay **más de una** empresa. En `null`, el nombre es texto plano:
  /// un botón que no hace nada es peor que ningún botón.
  final VoidCallback? alCambiarEmpresa;

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
class _PieDeEmpresa extends StatelessWidget {
  const _PieDeEmpresa({required this.marco, required this.colors});

  final MarcoAdministra marco;
  final AppColorScheme colors;

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
        if (marco.alCambiarEmpresa != null) ...[
          const SizedBox(width: AppSpacing.xs),
          Icon(Icons.unfold_more, size: 14, color: colors.textMuted),
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
        child: marco.alCambiarEmpresa == null
            ? etiqueta
            : InkWell(
                key: const Key('marco_cambiar_empresa'),
                onTap: marco.alCambiarEmpresa,
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
    );
  }
}
