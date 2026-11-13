/// **LA CAMPANA DE AVISOS** de la barra superior.
///
/// ## Qué es, y qué NO es (CP-18, decidido el 25 de octubre de 2026)
///
/// 🚫 **LOS AVISOS SE DERIVAN AL LEER. No se materializan y NO HAY leído/no leído.** Es
/// como funciona la campana del escritorio, y la razón es de producto: un aviso de algo
/// por vencer **tiene que seguir visible mientras la condición exista** —hasta que se
/// renueve o se termine—, no desaparecer por haberlo visto. Una tabla de «leídos»
/// convertiría un aviso en un mensaje, y un mensaje se archiva.
///
/// Consecuencia práctica: **no hay nada que guardar**. Abrir la campana es volver a
/// preguntar, y por eso cada grupo es una lectura y nada más.
///
/// ## La forma, heredada del escritorio
///
/// **Grupos**, un **permiso por grupo**, **máximo cinco filas por grupo**, color por
/// urgencia y **un destino por fila**. Lo que cambia respecto del escritorio es de dónde
/// salen los datos.
///
/// ## Preparada para recibir grupos sin rehacerla
///
/// La campana **no sabe de servicios**: recibe [GrupoDeAvisos], que dicen cómo se llaman,
/// cómo se leen sus filas y a dónde lleva cada una. Añadir los contratos de CP-18 —60, 30
/// y 15 días— es construir otro grupo donde se construye éste; aquí no se toca nada.
///
/// ⚠️ **EL PERMISO NO SE COMPRUEBA AQUÍ**, y es a propósito: quien sabe qué permisos tiene
/// la sesión es el portón, que es el único sitio que lee `effectivePermissions`. La
/// campana pinta los grupos que le dan. Dos sitios decidiendo quién ve qué es cómo uno de
/// los dos se queda viejo.
library;

import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system_web.dart';

/// Una fila de aviso: **qué pasa, cuándo, y a dónde lleva**.
@immutable
class FilaDeAviso {
  const FilaDeAviso({
    required this.titulo,
    required this.detalle,
    required this.urgencia,
    required this.alAbrir,
  });

  /// Qué es: «Sportium Satélite».
  final String titulo;

  /// Por qué avisa: «Termina el 30/nov/2026».
  final String detalle;

  /// ⚠️ **EL COLOR ACOMPAÑA, NO SUSTITUYE.** El detalle dice la urgencia con palabras;
  /// el tono sólo la hace visible de un vistazo.
  final RisegStatusTone urgencia;

  /// **Un destino por fila**, y es lo que convierte un aviso en algo que se puede
  /// atender: sin él sería una noticia.
  final VoidCallback alAbrir;
}

/// Un grupo de avisos: **cómo se llama, cómo se leen y a dónde lleva «Ver todos»**.
@immutable
class GrupoDeAvisos {
  const GrupoDeAvisos({
    required this.nombre,
    required this.leer,
    required this.verTodos,
  });

  final String nombre;

  /// Lee las filas **ahora**. Se llama al abrir la campana y al montarla.
  ///
  /// Devuelve **hasta [maximoPorGrupo] + 1**: la de más es cómo se sabe que hay más sin
  /// contar, porque los listados paginan por cursor y no devuelven totales.
  final Future<List<FilaDeAviso>> Function() leer;

  /// A dónde va «Ver todos»: el listado completo, ya filtrado por lo mismo.
  final VoidCallback verTodos;
}

/// **Cinco filas por grupo**, como el escritorio. Lo que no cabe se ve en «Ver todos».
const int maximoPorGrupo = 5;

class CampanaDeAvisos extends StatefulWidget {
  const CampanaDeAvisos({required this.grupos, super.key});

  /// Los grupos que **esta sesión puede ver**: el portón ya filtró por permiso.
  final List<GrupoDeAvisos> grupos;

  @override
  State<CampanaDeAvisos> createState() => _CampanaDeAvisosState();
}

class _CampanaDeAvisosState extends State<CampanaDeAvisos> {
  /// Lo leído por grupo, en el orden de [CampanaDeAvisos.grupos].
  ///
  /// ⚠️ **VA POR `ValueNotifier` Y NO POR `setState`, y no es un gusto.** El panel vive
  /// dentro de un `PopupMenuButton`, que construye su hijo **una vez al abrir** y en su
  /// propio `Navigator`: un `setState` de aquí **no repinta el panel abierto**. Con
  /// `setState` la relectura al abrir llegaba al número de la campana y el panel seguía
  /// enseñando lo de la vez anterior —comprobado: la prueba de «abrir vuelve a leer»
  /// fallaba enseñando la fila de un servicio ya renovado—.
  final ValueNotifier<List<List<FilaDeAviso>>?> _porGrupo = ValueNotifier(null);

  bool _leyendo = false;

  @override
  void initState() {
    super.initState();
    _leer();
  }

  @override
  void dispose() {
    _porGrupo.dispose();
    super.dispose();
  }

  /// Vuelve a preguntar. **No hay caché**: el aviso es la condición, no el mensaje.
  Future<void> _leer() async {
    if (_leyendo) return;

    _leyendo = true;

    final leidos = await Future.wait(widget.grupos.map((g) => g.leer()));

    if (!mounted) return;

    _leyendo = false;
    _porGrupo.value = leidos;
  }

  /// Cuántos avisos hay, y **si son más de los que se pueden contar**.
  ///
  /// ⚠️ **NO ES UN TOTAL EXACTO CUANDO SE PASA DEL TOPE, y se dice con un «+»** en vez de
  /// mentir con un número redondo. Los listados paginan por cursor y **no devuelven
  /// totales** —decisión de D-67—, así que saber «cuántos son» costaría traerlos todos
  /// cada vez que alguien abre una pantalla. Lo que la campana promete es **que hay
  /// trabajo y cuánto cabe en ella**.
  ({int cuantos, bool hayMas}) _cuentaDe(List<List<FilaDeAviso>>? grupos) {
    if (grupos == null) return (cuantos: 0, hayMas: false);

    var cuantos = 0;
    var hayMas = false;

    for (final filas in grupos) {
      cuantos += filas.length > maximoPorGrupo ? maximoPorGrupo : filas.length;
      if (filas.length > maximoPorGrupo) hayMas = true;
    }

    return (cuantos: cuantos, hayMas: hayMas);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return PopupMenuButton<void>(
      key: const Key('campana_de_avisos'),
      tooltip: 'Avisos',
      // EL BOTÓN RESERVA LA CAJA ENTERA —campana más insignia—, en vez de dejar que el
      // número cuelgue fuera con un `Positioned` negativo: lo que se pinta fuera de su
      // caja depende de que ningún antepasado recorte, y eso no se controla desde aquí.
      iconSize: 30,
      // AL ABRIR SE VUELVE A LEER: derivar al leer significa exactamente esto.
      onOpened: _leer,
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 380, maxWidth: 420),
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          // EL PANEL SE SUSCRIBE: así la relectura del `onOpened` llega al panel que ya
          // está abierto, y no sólo al número de la campana.
          child: ValueListenableBuilder<List<List<FilaDeAviso>>?>(
            valueListenable: _porGrupo,
            builder: (context, porGrupo, _) =>
                _Panel(grupos: widget.grupos, porGrupo: porGrupo),
          ),
        ),
      ],
      icon: ValueListenableBuilder<List<List<FilaDeAviso>>?>(
        valueListenable: _porGrupo,
        builder: (context, porGrupo, _) {
          final cuenta = _cuentaDe(porGrupo);

          // LA INSIGNIA SE PINTA DENTRO DE LOS LÍMITES DEL BOTÓN: una caja con sitio
          // para la campana y para el número, en vez de un `Positioned` negativo que
          // cuelgue fuera.
          return SizedBox(
            width: 30,
            height: 26,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: Icon(
                    Icons.notifications_none_outlined,
                    size: 20,
                    color: colors.textMuted,
                  ),
                ),
                // 🚫 **SIN AVISOS NO HAY NÚMERO.** Un «0» pegado a una campana es una
                // mancha que no dice nada y que se aprende a ignorar — y el día que diga
                // «3» ya nadie lo mira.
                if (cuenta.cuantos > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: colors.error,
                        borderRadius: AppRadius.fullRadius,
                      ),
                      // ⚠️ **EL NÚMERO SE PINTA SEGÚN LO CLARO QUE SEA EL ROJO, no
                      // siempre en blanco:** el rojo del tema oscuro es claro, y el
                      // blanco encima se leía lavado. Lo cazó la captura en oscuro.
                      child: Text(
                        '${cuenta.cuantos}${cuenta.hayMas ? '+' : ''}',
                        style: AppTypography.label.copyWith(
                          color:
                              ThemeData.estimateBrightnessForColor(
                                    colors.error,
                                  ) ==
                                  Brightness.dark
                              ? Colors.white
                              : colors.textPrimary,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.grupos, required this.porGrupo});

  final List<GrupoDeAvisos> grupos;

  /// Lo leído, o **nulo mientras todavía no ha llegado nada** —que es lo único que
  /// justifica una rueda—. Una lista vacía es «no hay avisos», y eso **se dice con
  /// palabras**, no con una rueda que gira para siempre.
  final List<List<FilaDeAviso>>? porGrupo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final leidos = porGrupo;

    if (leidos == null) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final conFilas = [
      for (final (i, g) in grupos.indexed)
        if (i < leidos.length && leidos[i].isNotEmpty) (grupo: g, filas: leidos[i]),
    ];

    if (conFilas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, size: 18, color: colors.success),
            const SizedBox(width: AppSpacing.sm),
            const Text('Nada pendiente', style: AppTypography.body),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (grupo: g, filas: filas) in conFilas) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xxs,
            ),
            child: Text(
              g.nombre.toUpperCase(),
              style: AppTypography.label.copyWith(
                color: colors.textMuted,
                letterSpacing: 1,
              ),
            ),
          ),
          for (final fila in filas.take(maximoPorGrupo))
            _Fila(fila: fila),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              0,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  // SE CIERRA LA CAMPANA ANTES DE NAVEGAR: el menú vive en su propio
                  // `Navigator`, y dejarlo abierto encima de la pantalla nueva es el
                  // mismo fallo que las hojas modales ya tuvieron.
                  Navigator.of(context).pop();
                  g.verTodos();
                },
                child: Text(
                  filas.length > maximoPorGrupo
                      ? 'Ver todos'
                      : 'Ver en su listado',
                  style: AppTypography.caption.copyWith(color: colors.accent),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.fila});

  final FilaDeAviso fila;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final (color, fondo) = switch (fila.urgencia) {
      RisegStatusTone.success => (colors.success, colors.successBg),
      RisegStatusTone.warning => (colors.warning, colors.warningBg),
      RisegStatusTone.error => (colors.error, colors.errorBg),
      RisegStatusTone.info => (colors.info, colors.infoBg),
      RisegStatusTone.neutral => (colors.neutralText, colors.neutralBg),
    };

    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        fila.alAbrir();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            // LA URGENCIA, EN UNA BARRA Y NO SÓLO EN EL TEXTO: es lo que deja mirar
            // cinco filas y saber cuál primero sin leerlas.
            Container(
              width: 4,
              height: 34,
              decoration: BoxDecoration(
                color: color,
                borderRadius: AppRadius.fullRadius,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ⚠️ **EL COLOR VA EXPLÍCITO, y lo cazó una captura:** `bodyStrong` no
                  // trae color, así que heredaba el del `DefaultTextStyle` del menú —el
                  // apagado— y el título salía **más tenue que su propio detalle**, con
                  // la jerarquía al revés en los dos temas.
                  Text(
                    fila.titulo,
                    style: AppTypography.bodyStrong.copyWith(
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    fila.detalle,
                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: fondo,
                borderRadius: AppRadius.smRadius,
              ),
              child: Icon(Icons.chevron_right, size: 16, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
