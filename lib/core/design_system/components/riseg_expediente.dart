/// **LAS PIEZAS DEL ESTILO B · PESTAÑAS**, compartidas por todo apartado que tenga un
/// expediente.
///
/// ## De dónde salen, y por qué viven aquí y no en Comercial
///
/// El dueño eligió el **estilo B** el 11 de noviembre de 2026, después de probar C2 en
/// pantalla, y lo dijo con esta condición: *«Es la base visual para Clientes, Servicios y
/// todos los apartados siguientes. Los componentes nuevos —resumen fijo, pestañas,
/// tarjetas— van en un lugar compartido para que C3 en adelante los use sin copiarlos»*.
///
/// Eso no es una preferencia de organización: **Personal, Organización y Comercial ya
/// tienen expediente**, y C3 a C6 traen cuatro más. Cinco copias de una cabecera divergen
/// en la tercera sin que nada falle — es lo mismo que pasó con los diez campos de un
/// domicilio antes de que fueran una tabla.
///
/// ## Los cuatro problemas que el estilo B resuelve, y cómo
///
/// El dueño los enumeró así: *«todos los campos son cajas grises iguales en tres
/// columnas, el expediente es una página larga sin jerarquía, mucho texto auxiliar bajo
/// cada campo, y la vista se ve casi igual que la edición»*. Son **uno**: la pantalla
/// trataba todo igual, así que nada guiaba la vista.
///
/// | Problema | Qué lo resuelve aquí |
/// |---|---|
/// | la vista se ve como la edición | [RisegDatoEnLinea] — **el modo vista es TEXTO**, nunca un cuadro apagado |
/// | página larga sin jerarquía | [RisegExpedienteHeader] + [RisegTabs] — lo que identifica arriba, y **un asunto a la vez** |
/// | cajas iguales en tres columnas | [RisegCuadricula] — **cada campo mide lo que se escribe en él** |
/// | texto auxiliar bajo cada campo | [RisegTarjeta] con `nota` — la letra chica va **una vez por sección** |
///
/// ⚠️ **LO QUE NINGUNA DE ESTAS PIEZAS HACE: decidir qué se puede hacer.** Los permisos,
/// el modo —consulta o edición— y qué acciones existen los decide la pantalla, que es
/// quien conoce su recurso. Esto pinta.
library;

import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_breakpoints.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

// ===========================================================================
// El dato leído: texto, nunca una caja apagada
// ===========================================================================

/// Un dato **en modo vista**, como lista de definición: etiqueta a la izquierda, valor a
/// la derecha.
///
/// 🚫 **ES LA PIEZA QUE ARREGLA «LA VISTA SE VE CASI IGUAL QUE LA EDICIÓN».** Un
/// `RisegTextField` con `enabled: false` y el dato dentro **parece un campo que no te
/// dejan tocar**, no un dato: la persona intenta escribir en él antes de entender que
/// está consultando.
///
/// **Ausencia se dice, no se deja en blanco:** un valor vacío sale como [vacioDice] en
/// gris —«No registrado»—, porque un hueco no distingue «no hay dato» de «no cargó».
class RisegDatoEnLinea extends StatelessWidget {
  const RisegDatoEnLinea({
    required this.etiqueta,
    required this.valor,
    this.vacioDice = 'No registrado',
    this.alFinal,
    super.key,
  });

  final String etiqueta;

  /// Nulo o vacío se pintan igual: los dos son «no hay dato».
  final String? valor;

  final String vacioDice;

  /// Lo que va a la derecha del valor: un botón de un vínculo, una insignia.
  final Widget? alFinal;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hay = (valor ?? '').trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: LayoutBuilder(
        builder: (context, caja) {
          final etiquetaWidget = Text(
            etiqueta,
            style: AppTypography.body.copyWith(color: colors.textMuted),
          );

          final valorWidget = Text(
            hay ? valor!.trim() : vacioDice,
            style: hay
                ? AppTypography.bodyStrong
                : AppTypography.body.copyWith(color: colors.textDisabled),
          );

          // EN ESTRECHO SE APILA, y no se encoge la etiqueta: con 210 px de etiqueta en
          // un teléfono, al valor le quedan cuarenta y se corta cada palabra.
          if (caja.maxWidth < AppBreakpoints.compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                etiquetaWidget,
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(child: valorWidget),
                    if (alFinal case final a?) a,
                  ],
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 210, child: etiquetaWidget),
              Expanded(child: valorWidget),
              if (alFinal case final a?) a,
            ],
          );
        },
      ),
    );
  }
}

/// Un dato **apilado**: etiqueta en versalita encima, valor debajo.
///
/// Es la forma de las **cifras** —las de la cabecera y las del resumen fijo—, donde lo
/// que se compara son los valores entre sí y por eso van alineados en una fila.
class RisegDatoApilado extends StatelessWidget {
  const RisegDatoApilado({
    required this.etiqueta,
    required this.valor,
    this.nota,
    this.vacioDice = 'No registrado',
    super.key,
  });

  final String etiqueta;
  final String? valor;
  final String? nota;
  final String vacioDice;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hay = (valor ?? '').trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          etiqueta.toUpperCase(),
          style: AppTypography.label.copyWith(
            color: colors.textMuted,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          hay ? valor!.trim() : vacioDice,
          style: hay
              ? AppTypography.bodyStrong
              : AppTypography.body.copyWith(color: colors.textDisabled),
        ),
        if (nota case final n?)
          Text(n, style: AppTypography.caption.copyWith(color: colors.textMuted)),
      ],
    );
  }
}

// ===========================================================================
// La cuadrícula donde cada campo mide lo que le toca
// ===========================================================================

/// Una celda de [RisegCuadricula], con **cuánto ocupa**.
@immutable
class RisegCelda {
  const RisegCelda(this.hijo, {this.ancho = 1});

  final Widget hijo;

  /// Cuántas columnas ocupa, de las cuatro que hay en pantalla ancha.
  final int ancho;

  /// La celda que ocupa **la fila entera** — unas observaciones, unas referencias.
  const RisegCelda.ancha(this.hijo) : ancho = 4;

  /// Media fila: un cliente, un tipo de servicio.
  const RisegCelda.media(this.hijo) : ancho = 2;
}

/// Campos en cuadrícula **donde cada uno declara su ancho**.
///
/// 🚫 **ES LA PIEZA QUE ARREGLA «CAJAS GRISES IGUALES EN TRES COLUMNAS».** `RisegFieldGrid`
/// reparte todo en celdas idénticas, y entonces un **código postal** y una **calle** miden
/// lo mismo: la vista no tiene dónde apoyarse y el formulario se lee como una rejilla.
///
/// Son **cuatro** columnas en pantalla ancha —no tres— porque cuatro admite medios y
/// cuartos sin dejar huecos: un ancho 2 es media fila y dos anchos 1 caben al lado.
/// En pantalla media son **dos**, y en estrecho **una**; el ancho de cada celda se recorta
/// a las columnas que haya, así que un ancho 4 nunca desborda.
class RisegCuadricula extends StatelessWidget {
  const RisegCuadricula({required this.celdas, super.key});

  final List<RisegCelda> celdas;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, caja) {
      final columnas = _columnas(caja.maxWidth);

      if (columnas == 1) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final c in celdas)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: c.hijo,
              ),
          ],
        );
      }

      final unidad =
          (caja.maxWidth - AppSpacing.md * (columnas - 1)) / columnas;

      return Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          for (final c in celdas)
            SizedBox(
              // SE RECORTA A LAS COLUMNAS QUE HAY: un ancho 4 en dos columnas ocupa dos,
              // no cuatro — si no, desbordaría y `Wrap` no avisa, recorta.
              width: _ancho(c.ancho, columnas, unidad),
              child: c.hijo,
            ),
        ],
      );
    },
  );

  static double _ancho(int ancho, int columnas, double unidad) {
    final cuantas = ancho.clamp(1, columnas);

    return unidad * cuantas + AppSpacing.md * (cuantas - 1);
  }

  static int _columnas(double ancho) {
    if (ancho >= AppBreakpoints.medium) return 4;
    if (ancho >= AppBreakpoints.compact) return 2;

    return 1;
  }
}

// ===========================================================================
// La tarjeta de una sección
// ===========================================================================

/// Una sección del expediente **en tarjeta**, con su título y su letra chica.
///
/// La `nota` es **la única letra chica de la sección**: era el cuarto problema del dueño
/// —«mucho texto auxiliar bajo cada campo»—, y la regla que deja es que lo que explica la
/// sección se dice **una vez arriba** y no debajo de cada cuadro, donde no se lee.
class RisegTarjeta extends StatelessWidget {
  const RisegTarjeta({
    required this.hijo,
    this.titulo,
    this.nota,
    this.alDerecha,
    super.key,
  });

  final Widget hijo;

  /// Nulo cuando la tarjeta ya está dentro de una pestaña que la nombra: repetir el
  /// nombre de la pestaña como título de su única tarjeta es decirlo dos veces.
  final String? titulo;

  final String? nota;

  /// Una acción de la sección entera, arriba a la derecha.
  final Widget? alDerecha;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.borderSubtle),
        borderRadius: AppRadius.lgRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (titulo != null || nota != null || alDerecha != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (titulo case final t?)
                        Text(t, style: AppTypography.heading3),
                      if (nota case final n?) ...[
                        if (titulo != null) const SizedBox(height: 2),
                        Text(
                          n,
                          style: AppTypography.caption.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (alDerecha case final a?) a,
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          hijo,
        ],
      ),
    );
  }
}

// ===========================================================================
// La cabecera del expediente
// ===========================================================================

/// Una cifra de la cabecera: lo que se mira primero.
@immutable
class RisegCifra {
  const RisegCifra(this.etiqueta, this.valor, {this.nota, this.clave});

  final String etiqueta;
  final String? valor;
  final String? nota;

  /// La llave del widget, **para quien tenga que distinguir ESTA cifra de un texto igual
  /// en otra parte de la pantalla**. La razón social del cliente es el caso real: sale en
  /// la cabecera y otra vez en la lista de sus entidades fiscales.
  final Key? clave;
}

/// La cabecera de un expediente: **lo que identifica y lo que se puede hacer, juntos.**
///
/// 🚫 **ARREGLA «UNA PÁGINA LARGA SIN JERARQUÍA».** Antes el nombre, las insignias, los
/// indicadores y los botones estaban repartidos por la página, así que para saber qué
/// servicio se está mirando y qué se puede hacer con él había que recorrerla.
///
/// Lleva cuatro cosas y en este orden, que es el de las preguntas: **quién es** (identidad
/// y título), **cómo está** (insignias), **qué se puede hacer** (acciones) y **cuánto**
/// (cifras).
class RisegExpedienteHeader extends StatelessWidget {
  const RisegExpedienteHeader({
    required this.titulo,
    this.subtitulo,
    this.identidad,
    this.insignias = const [],
    this.acciones = const [],
    this.cifras = const [],
    this.compacta = true,
    super.key,
  });

  final String titulo;
  final String? subtitulo;

  /// El logotipo o las iniciales. Lo construye la pantalla: en un cliente es su logotipo
  /// con el respaldo de iniciales, y eso **no es cosa del sistema de diseño**.
  final Widget? identidad;

  final List<Widget> insignias;
  final List<Widget> acciones;
  final List<RisegCifra> cifras;

  /// En el estilo B va compacta, porque las pestañas van justo debajo.
  final bool compacta;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.borderSubtle),
        borderRadius: AppRadius.lgRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, caja) {
              final nombre = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: compacta
                        ? AppTypography.heading2
                        : AppTypography.heading1,
                  ),
                  if (subtitulo case final s?) ...[
                    const SizedBox(height: 2),
                    Text(
                      s,
                      style: AppTypography.caption.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                  if (insignias.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xxs,
                      children: insignias,
                    ),
                  ],
                ],
              );

              final botones = Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xxs,
                children: acciones,
              );

              // EN ESTRECHO LAS ACCIONES BAJAN, y no se aprietan al lado del nombre: dos
              // botones y un título de dos líneas en 400 px no caben en una fila, y un
              // `Row` que no cabe **recorta sin avisar**.
              if (caja.maxWidth < AppBreakpoints.compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (identidad case final i?) ...[
                          i,
                          const SizedBox(width: AppSpacing.md),
                        ],
                        Expanded(child: nombre),
                      ],
                    ),
                    if (acciones.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      botones,
                    ],
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (identidad case final i?) ...[
                    i,
                    const SizedBox(width: AppSpacing.md),
                  ],
                  Expanded(child: nombre),
                  botones,
                ],
              );
            },
          ),
          if (cifras.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Container(height: 1, color: colors.borderSubtle),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xxl,
              runSpacing: AppSpacing.sm,
              children: [
                for (final c in cifras)
                  RisegDatoApilado(
                    key: c.clave,
                    etiqueta: c.etiqueta,
                    valor: c.valor,
                    nota: c.nota,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ===========================================================================
// El resumen fijo de un alta
// ===========================================================================

/// El panel fijo de un alta: **qué se va a crear**, y las acciones.
///
/// Con quince campos, lo que se está creando se pierde de vista y el botón de guardar
/// queda al final de una página que hay que recorrer para encontrarlo. Esto lo pone
/// donde se ve: **las acciones viven con el resumen**, no al pie del formulario.
///
/// ⚠️ **NO SE ENCOGE POR DEBAJO DE [AppBreakpoints.medium].** En pantalla media y
/// estrecha no hay sitio para dos columnas, así que quien lo use lo pone **arriba** del
/// formulario en vez de al lado — y eso lo decide la pantalla con [RisegAltaConResumen].
class RisegPanelDeResumen extends StatelessWidget {
  const RisegPanelDeResumen({
    required this.titulo,
    required this.datos,
    required this.acciones,
    this.nota,
    super.key,
  });

  final String titulo;
  final List<RisegCifra> datos;

  /// En orden: la primera es la que se va a pulsar.
  final List<Widget> acciones;

  final String? nota;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        border: Border.all(color: colors.borderSubtle),
        borderRadius: AppRadius.lgRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: AppTypography.heading3),
          if (nota case final n?) ...[
            const SizedBox(height: 2),
            Text(
              n,
              style: AppTypography.caption.copyWith(color: colors.textMuted),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          for (final d in datos) ...[
            RisegDatoApilado(
              etiqueta: d.etiqueta,
              valor: d.valor,
              nota: d.nota,
              vacioDice: 'Sin elegir',
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          const SizedBox(height: AppSpacing.xs),
          for (final a in acciones) ...[
            SizedBox(width: double.infinity, child: a),
            const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

/// Un alta **con su resumen fijo**: el formulario a la izquierda y el panel a la derecha.
///
/// Existe para que ninguna pantalla repita la decisión de **qué pasa cuando no caben dos
/// columnas**: por debajo de [AppBreakpoints.medium] el resumen se va **arriba** del
/// formulario, porque apretarlo a 200 px lo haría ilegible y esconderlo dejaría el alta
/// sin botón de guardar.
class RisegAltaConResumen extends StatelessWidget {
  const RisegAltaConResumen({
    required this.formulario,
    required this.resumen,
    super.key,
  });

  final Widget formulario;
  final Widget resumen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, caja) {
      if (caja.maxWidth < AppBreakpoints.medium) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            resumen,
            const SizedBox(height: AppSpacing.md),
            formulario,
          ],
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: formulario),
          const SizedBox(width: AppSpacing.lg),
          SizedBox(width: 300, child: resumen),
        ],
      );
    },
  );
}
