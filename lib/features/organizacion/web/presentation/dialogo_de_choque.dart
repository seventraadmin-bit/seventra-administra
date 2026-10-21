import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system_web.dart';
import '../modelos/choque_de_expediente.dart';

/// El aviso de «alguien más guardó», **sin perder lo que escribiste**.
///
/// ## Qué enseña, y qué NO
///
/// Sólo **los campos que de verdad chocan**: los que cambiamos los dos a cosas
/// distintas. Lo que sólo cambió la otra persona se **informa** aparte —merece saberse,
/// pero no hay nada que decidir— y lo que sólo cambié yo no aparece: se queda.
///
/// Con quince campos, la diferencia entre esto y «recarga» es entre dos decisiones y
/// quince, o entre dos decisiones y perder el trabajo.
///
/// ## Lo que pasa si se cierra sin decidir
///
/// Se conserva **lo mío** en cada choque. Está en [CampoComparado.porOmision] y es
/// deliberado: perder lo que alguien escribió por no contestar un diálogo sería
/// exactamente lo que este diálogo viene a evitar.
///
/// Devuelve el mapa de elecciones —`true` = me quedo lo suyo— o `null` si se canceló.
///
/// <b>Importa `design_system_web.dart`, NUNCA el barrel completo.</b>
Future<Map<String, bool>?> mostrarDialogoDeChoque({
  required BuildContext context,
  required ChoqueDeExpediente choque,
}) {
  // SI NO HAY CHOQUES NO SE PREGUNTA NADA. Es el caso frecuente —dos personas en
  // secciones distintas— y abrir un diálogo para que alguien confirme algo que no
  // chocaba es ruido que enseña a ignorar los avisos.
  if (!choque.hayChoque) return Future.value(const <String, bool>{});

  final elegidos = <String, bool>{};

  return RisegDialog.showForm<Map<String, bool>>(
    context: context,
    title: 'Alguien más guardó mientras editabas',
    confirmLabel: 'Guardar con estas decisiones',
    cancelLabel: 'Seguir editando',
    contentBuilder: (contexto) => _ContenidoDelChoque(
      choque: choque,
      elegidos: elegidos,
    ),
    onConfirm: () async => elegidos,
  );
}

class _ContenidoDelChoque extends StatefulWidget {
  const _ContenidoDelChoque({required this.choque, required this.elegidos});

  final ChoqueDeExpediente choque;

  /// **Se muta en su sitio**, y es a propósito: `showForm` devuelve lo que diga
  /// `onConfirm`, que se arma fuera de este widget. Pasar el mapa evita un segundo
  /// mecanismo —una devolución de llamada— para el mismo dato.
  final Map<String, bool> elegidos;

  @override
  State<_ContenidoDelChoque> createState() => _ContenidoDelChoqueState();
}

class _ContenidoDelChoqueState extends State<_ContenidoDelChoque> {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final choques = widget.choque.choques;
    final suyos = widget.choque.suyosSinChoque;

    return SizedBox(
      width: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            choques.length == 1
                ? 'Hay 1 dato en el que los dos escribieron algo distinto. '
                      'Elige cuál se queda.'
                : 'Hay ${choques.length} datos en los que los dos escribieron algo '
                      'distinto. Elige cuál se queda en cada uno.',
            style: AppTypography.body.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Lo que escribiste en los demás campos no se pierde: se conserva tal cual.',
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.md),

          // LOS DOS BOTONES DE «TODO» usan el mismo mecanismo que elegir uno por uno
          // —el mapa lleno con un valor—, no un camino aparte.
          //
          // ⚠️ `Wrap` Y NO `Row`, Y LO DESTAPÓ LA PRIMERA PRUEBA QUE MONTÓ ESTE
          // DIÁLOGO: «Quedarme con todo lo mío» y «Tomar todo lo suyo» en una fila se
          // pasaban **320 px** del ancho del diálogo. Desbordamiento real, no de la
          // prueba: nadie lo había visto porque el diálogo estaba escrito y sin
          // cablear, así que ninguna pantalla lo abría todavía.
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              RisegButton(
                label: 'Quedarme con todo lo mío',
                variant: RisegButtonVariant.secondary,
                size: RisegButtonSize.compact,
                onPressed: () => _todos(false),
              ),
              // SIN `SizedBox` ENTRE LOS DOS: `Wrap` ya separa con `spacing`, y un
              // hueco suelto contaría como un hijo más al repartir las filas.
              RisegButton(
                label: 'Tomar todo lo suyo',
                variant: RisegButtonVariant.secondary,
                size: RisegButtonSize.compact,
                onPressed: () => _todos(true),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final campo in choques) _filaDeChoque(campo),

                  if (suyos.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    const Divider(height: 1),
                    const SizedBox(height: AppSpacing.md),

                    // SE INFORMA, NO SE PREGUNTA. La otra persona cambió esto y yo no
                    // lo toqué: no hay nada que decidir, pero esconderlo haría que
                    // alguien guardara sin saber qué entró de fuera.
                    Text(
                      suyos.length == 1
                          ? 'Y cambió 1 dato que tú no habías tocado. Se queda su '
                                'versión:'
                          : 'Y cambió ${suyos.length} datos que tú no habías tocado. '
                                'Se queda su versión:',
                      style: AppTypography.caption.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    for (final campo in suyos) _filaInformativa(campo),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _todos(bool suyo) => setState(() {
    for (final campo in widget.choque.choques) {
      widget.elegidos[campo.campo] = suyo;
    }
  });

  /// Un choque: las dos versiones, una al lado de la otra, y la elección.
  ///
  /// **El valor de cada uno se muestra entero, no recortado.** Un «Segurid…» obliga a
  /// adivinar, y adivinar es justo lo que no se puede hacer al elegir entre dos
  /// versiones de un dato.
  Widget _filaDeChoque(CampoComparado campo) {
    final colors = context.colors;

    // NO HAY ELECCIÓN POR OMISIÓN MARCADA, y es deliberado: si una apareciera
    // seleccionada, alguien pulsaría «Guardar» creyendo que confirmó algo que no
    // miró. Sin marcar, el texto de abajo dice qué pasa si no elige.
    final elegido = widget.elegidos[campo.campo];

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(campo.etiqueta, style: AppTypography.bodyStrong),
          const SizedBox(height: AppSpacing.xxs),

          _opcion(
            etiqueta: 'Lo tuyo',
            // SE MUESTRA LO LEGIBLE Y SE COMPARA EL VALOR: el tipo de sucursal se
            // compara por id —es lo que se guarda— y se lee por su nombre.
            valor: campo.leer(campo.mio),
            elegida: elegido == false,
            alElegir: () => setState(() => widget.elegidos[campo.campo] = false),
          ),
          const SizedBox(height: AppSpacing.xxs),
          _opcion(
            etiqueta: 'Lo de la otra persona',
            valor: campo.leer(campo.suyo),
            elegida: elegido == true,
            alElegir: () => setState(() => widget.elegidos[campo.campo] = true),
          ),

          if (elegido == null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Si no eliges, se queda lo tuyo.',
              style: AppTypography.caption.copyWith(color: colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _opcion({
    required String etiqueta,
    required String? valor,
    required bool elegida,
    required VoidCallback alElegir,
  }) {
    final colors = context.colors;

    return InkWell(
      onTap: alElegir,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              elegida ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 18,
              color: elegida ? colors.accent : colors.textMuted,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    etiqueta,
                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                  ),
                  Text(
                    // UN CAMPO VACÍO SE DICE, no se deja en blanco: «(vacío)» es una
                    // elección legítima —borrar un dato— y un hueco se leería como un
                    // fallo de la pantalla.
                    (valor ?? '').trim().isEmpty ? '(vacío)' : valor!,
                    style: AppTypography.body.copyWith(color: colors.textPrimary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filaInformativa(CampoComparado campo) {
    final colors = context.colors;
    final suyo = campo.leer(campo.suyo);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Text(
        '${campo.etiqueta}: '
        '${(suyo ?? '').trim().isEmpty ? '(vacío)' : suyo}',
        style: AppTypography.caption.copyWith(color: colors.textPrimary),
      ),
    );
  }
}
