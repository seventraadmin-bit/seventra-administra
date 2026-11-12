/// **ESCAPARATE DE ESTILOS — propuesta de diseño para Clientes y Servicios.**
///
/// ## Qué es esto, y qué NO es
///
/// Es una pantalla **de propuesta**, con datos inventados y sin repositorios: existe para
/// que el dueño vea los dos estilos y elija uno. **No se conecta a nada** y **no entra en
/// el producto**: ninguna ruta la abre, y vive fuera de `features/` a propósito, para que
/// los candados de pantallas de verdad —el guardia de salida, la jerga, los permisos— no
/// la midan como si fuera una.
///
/// Se abre con su propio punto de entrada:
///
/// ```
/// flutter run -d chrome --web-port=5310 --target lib/main_estilos.dart
/// ```
///
/// ## De dónde salió
///
/// Del dueño, el 11 de noviembre de 2026, probando C2 contra el ensayo:
///
/// > «Visualmente se ve anticuado: todos los campos son cajas grises iguales en tres
/// > columnas, el expediente es una página larga sin jerarquía, mucho texto auxiliar bajo
/// > cada campo, y la vista se ve casi igual que la edición.»
///
/// Los cuatro problemas son **uno**: la pantalla trata todo igual. Un dato que sólo se
/// lee, uno que se edita, un título y una nota al pie se pintan con el mismo peso, y
/// entonces nada guía la vista.
///
/// ## Los dos estilos, y en qué se diferencian de verdad
///
/// No son dos paletas: son **dos decisiones distintas sobre dónde va la jerarquía**.
///
/// **A · DOCUMENTO.** El expediente se lee como una ficha impresa: una cabecera con lo
/// que identifica y lo que se puede hacer, y debajo **secciones con título y datos como
/// texto**, sin una sola caja. Editar **cambia la pantalla**: ahí sí aparecen los campos.
/// La jerarquía la pone la **tipografía** y el espacio en blanco; los bordes casi
/// desaparecen. Una columna para leer, una o dos para capturar.
///
/// **B · PESTAÑAS.** El expediente es un panel de trabajo: cabecera compacta fija y
/// **pestañas** —General · Domicilio · Vínculos · Historial—, cada una con su tarjeta. La
/// jerarquía la pone la **estructura**: nunca se ve más de un asunto a la vez, así que la
/// página no crece. El dato se lee como **lista de definición** —etiqueta a la izquierda,
/// valor a la derecha—, que es lo que hace que no parezca un formulario apagado.
///
/// **Lo que los dos arreglan igual, porque no es cuestión de estilo:**
///
///  · **el modo vista es TEXTO**, nunca cajas deshabilitadas;
///  · **la letra chica se va** de debajo de cada campo: se queda sólo donde dice algo que
///    no se puede adivinar, y entonces va **una vez por sección**, no por campo;
///  · **tres columnas de cajas iguales desaparecen**: se agrupa por asunto y el ancho de
///    cada campo lo decide **lo que se escribe en él** —un código postal no mide lo mismo
///    que una calle—;
///  · **lo que identifica y lo que se puede hacer viven arriba**, juntos, y no al final de
///    una página larga.
library;

import 'package:flutter/material.dart';

import '../core/design_system/design_system_web.dart';

// ===========================================================================
// Los datos de mentira
// ===========================================================================

/// Un dato de una ficha: cómo se llama y qué dice.
class _Dato {
  const _Dato(this.etiqueta, this.valor, {this.ancho = 1, this.nota});

  final String etiqueta;
  final String valor;

  /// Cuánto ocupa en una cuadrícula: un código postal no mide lo que una calle.
  final int ancho;

  /// La poca letra chica que sobrevive, **por campo y casi nunca**.
  final String? nota;
}

class _Seccion {
  const _Seccion(this.titulo, this.datos, {this.nota});

  final String titulo;
  final List<_Dato> datos;
  final String? nota;
}

class _Fila {
  const _Fila({
    required this.titulo,
    required this.bajoTitulo,
    required this.ubicacion,
    required this.estatus,
    required this.tono,
    this.temporal,
  });

  final String titulo;
  final String bajoTitulo;
  final String ubicacion;
  final String estatus;
  final RisegStatusTone tono;
  final String? temporal;
}

const _serviciosEnLista = [
  _Fila(
    titulo: 'Sportium Satélite',
    bajoTitulo: 'Sportium · SRV-000001',
    ubicacion: 'Naucalpan, Estado de México',
    estatus: 'Activo',
    tono: RisegStatusTone.success,
    temporal: 'Termina el 30/nov/2026',
  ),
  _Fila(
    titulo: 'Sportium Interlomas',
    bajoTitulo: 'Sportium · SRV-000002',
    ubicacion: 'Huixquilucan, Estado de México',
    estatus: 'Activo',
    tono: RisegStatusTone.success,
    temporal: 'Vigente',
  ),
  _Fila(
    titulo: 'Patio Toluca',
    bajoTitulo: 'Deacero · SRV-000003',
    ubicacion: 'Toluca, Estado de México',
    estatus: 'Suspendido',
    tono: RisegStatusTone.warning,
    temporal: 'Vigente',
  ),
  _Fila(
    titulo: 'Bodega Vallejo',
    bajoTitulo: 'Deacero · SRV-000009',
    ubicacion: 'Azcapotzalco, Ciudad de México',
    estatus: 'Terminado',
    tono: RisegStatusTone.neutral,
    temporal: 'Terminó el 30/sep/2026',
  ),
  _Fila(
    titulo: 'Corporativo Reforma',
    bajoTitulo: 'Grupo Ríos · SRV-000011',
    ubicacion: 'Cuauhtémoc, Ciudad de México',
    estatus: 'Activo',
    tono: RisegStatusTone.success,
    temporal: 'Próximo',
  ),
];

const _clientesEnLista = [
  _Fila(
    titulo: 'Sportium',
    bajoTitulo: 'CLI-000004 · desde mar/2019',
    ubicacion: 'Naucalpan, Estado de México',
    estatus: 'Activo',
    tono: RisegStatusTone.success,
    temporal: '2 servicios',
  ),
  _Fila(
    titulo: 'Deacero',
    bajoTitulo: 'CLI-000007 · desde ene/2023',
    ubicacion: 'Toluca, Estado de México',
    estatus: 'Activo',
    tono: RisegStatusTone.success,
    temporal: '1 servicio · 1 suspendido',
  ),
  _Fila(
    titulo: 'Grupo Ríos',
    bajoTitulo: 'CLI-000011 · desde oct/2026',
    ubicacion: 'Cuauhtémoc, Ciudad de México',
    estatus: 'Activo',
    tono: RisegStatusTone.success,
    temporal: '1 servicio',
  ),
  _Fila(
    titulo: 'Gimnasios del Valle',
    bajoTitulo: 'CLI-000002 · desde jun/2021',
    ubicacion: 'No registrada',
    estatus: 'Terminado',
    tono: RisegStatusTone.neutral,
  ),
];

const _fichaDelServicio = [
  _Seccion('Generales', [
    _Dato('Cliente', 'Sportium', ancho: 2),
    _Dato('Tipo de servicio', 'Vigilancia intramuros', ancho: 2),
    _Dato('Inicio', '1/mar/2019'),
    _Dato('Término programado', '30/nov/2026'),
    _Dato('Observaciones', 'Dos accesos. Entrega de bitácora los lunes.', ancho: 4),
  ]),
  _Seccion('Domicilio operativo', [
    _Dato('Calle y número', 'Circuito Centro Comercial 40', ancho: 2),
    _Dato('Colonia', 'Ciudad Satélite'),
    _Dato('Código postal', '53100'),
    _Dato('Municipio', 'Naucalpan'),
    _Dato('Estado', 'Estado de México'),
    _Dato('Referencias', 'Frente a la plaza, acceso por la lateral', ancho: 2),
  ]),
  _Seccion(
    'Vínculos',
    [
      _Dato('Entidad fiscal', 'Deportes Sportium, S.A. de C.V.', ancho: 2),
      _Dato('Contacto responsable', 'Mariana Ruiz'),
      _Dato('Sucursal administrativa', 'Centro'),
      _Dato('Supervisor', 'Luis Ángel Pérez · empleado 104', ancho: 2),
    ],
    nota: 'Cambiar la entidad fiscal pide motivo: decide a quién se le factura.',
  ),
];

const _camposDelAlta = [
  _Seccion('Qué se presta y a quién', [
    _Dato('Nombre del servicio', 'Sportium Satélite', ancho: 2),
    _Dato('Cliente', 'Sportium', ancho: 2),
    _Dato('Tipo de servicio', 'Vigilancia intramuros', ancho: 2),
    _Dato('Fecha de inicio', '11/nov/2026', ancho: 2),
  ], nota: 'El cliente queda fijo: después no se puede cambiar.'),
  _Seccion('Dónde se presta', [
    _Dato('Calle', 'Circuito Centro Comercial', ancho: 3),
    _Dato('Número exterior', '40'),
    _Dato('Número interior', ''),
    _Dato('Colonia', 'Ciudad Satélite', ancho: 2),
    _Dato('Municipio o alcaldía', 'Naucalpan', ancho: 2),
    _Dato('Estado', 'Estado de México', ancho: 2),
    // LA ÚNICA NOTA QUE SOBREVIVE EN EL FORMULARIO ENTERO, y por eso se lee: dice algo que
    // no se puede adivinar mirando el cuadro. «Opcional.» debajo de cuatro campos no
    // dice nada que el asterisco de los obligatorios no diga mejor.
    _Dato('Código postal', '53100', nota: 'Cinco dígitos.'),
    _Dato('Ciudad', ''),
    _Dato('País', ''),
    _Dato('Referencias', '', ancho: 3),
  ]),
  _Seccion('Lo demás', [
    _Dato('Observaciones', '', ancho: 4),
  ]),
];

// ===========================================================================
// El escaparate
// ===========================================================================

enum _Estilo {
  documento('A · Documento'),
  pestanas('B · Pestañas');

  const _Estilo(this.comoSeLlama);

  final String comoSeLlama;
}

enum _Pantalla {
  listado('Listado'),
  expediente('Expediente (vista)'),
  alta('Alta');

  const _Pantalla(this.comoSeLlama);

  final String comoSeLlama;
}

enum _Modulo {
  servicios('Servicios'),
  clientes('Clientes');

  const _Modulo(this.comoSeLlama);

  final String comoSeLlama;
}

class EscaparateDeEstilos extends StatefulWidget {
  const EscaparateDeEstilos({super.key});

  @override
  State<EscaparateDeEstilos> createState() => _EscaparateDeEstilosState();
}

class _EscaparateDeEstilosState extends State<EscaparateDeEstilos> {
  _Estilo _estilo = _Estilo.documento;
  _Pantalla _pantalla = _Pantalla.expediente;
  _Modulo _modulo = _Modulo.servicios;

  bool get _esServicio => _modulo == _Modulo.servicios;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _barraDeControl(colors),
            Expanded(
              child: Container(
                color: colors.surface,
                width: double.infinity,
                child: _cuerpo(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// La barra de arriba **no es parte de la propuesta**: es el mando para comparar.
  Widget _barraDeControl(AppColorScheme colors) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.sm,
    ),
    color: colors.shellSurface,
    child: Wrap(
      spacing: AppSpacing.xl,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Propuesta de estilo',
          style: AppTypography.bodyStrong.copyWith(
            color: colors.shellForeground,
          ),
        ),
        _grupo<_Estilo>(
          colors,
          _Estilo.values,
          _estilo,
          (e) => e.comoSeLlama,
          (e) => setState(() => _estilo = e),
        ),
        _grupo<_Pantalla>(
          colors,
          _Pantalla.values,
          _pantalla,
          (p) => p.comoSeLlama,
          (p) => setState(() => _pantalla = p),
        ),
        _grupo<_Modulo>(
          colors,
          _Modulo.values,
          _modulo,
          (m) => m.comoSeLlama,
          (m) => setState(() => _modulo = m),
        ),
      ],
    ),
  );

  Widget _grupo<T>(
    AppColorScheme colors,
    List<T> valores,
    T elegido,
    String Function(T) comoSeLlama,
    void Function(T) alElegir,
  ) => Wrap(
    spacing: AppSpacing.xxs,
    children: [
      for (final v in valores)
        TextButton(
          onPressed: () => alElegir(v),
          style: TextButton.styleFrom(
            backgroundColor: v == elegido
                ? colors.shellOverlayStrong
                : Colors.transparent,
            foregroundColor: v == elegido
                ? colors.shellForeground
                : colors.shellForegroundMuted,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xxs,
            ),
            minimumSize: Size.zero,
          ),
          child: Text(comoSeLlama(v), style: AppTypography.caption),
        ),
    ],
  );

  Widget _cuerpo() => switch ((_pantalla, _estilo)) {
    (_Pantalla.listado, _Estilo.documento) => _ListadoDocumento(
      filas: _esServicio ? _serviciosEnLista : _clientesEnLista,
      modulo: _modulo,
    ),
    (_Pantalla.listado, _Estilo.pestanas) => _ListadoPestanas(
      filas: _esServicio ? _serviciosEnLista : _clientesEnLista,
      modulo: _modulo,
    ),
    (_Pantalla.expediente, _Estilo.documento) => _ExpedienteDocumento(
      modulo: _modulo,
    ),
    (_Pantalla.expediente, _Estilo.pestanas) => _ExpedientePestanas(
      modulo: _modulo,
    ),
    (_Pantalla.alta, _Estilo.documento) => const _AltaDocumento(),
    (_Pantalla.alta, _Estilo.pestanas) => const _AltaPestanas(),
  };
}

// ===========================================================================
// Piezas compartidas por los dos estilos
// ===========================================================================

/// Un título de sección **como título**, no como barra de color.
///
/// Es versalita pequeña con una línea de pelo debajo: dice «aquí empieza otro asunto»
/// sin dibujar una caja alrededor de todo.
class _TituloDeSeccion extends StatelessWidget {
  const _TituloDeSeccion(this.texto, {this.nota});

  final String texto;
  final String? nota;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          texto.toUpperCase(),
          style: AppTypography.label.copyWith(
            color: colors.textMuted,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Container(height: 1, color: colors.borderSubtle),
        if (nota case final n?) ...[
          const SizedBox(height: AppSpacing.xs),
          // ⚠️ **LA LETRA CHICA, UNA VEZ POR SECCIÓN Y NO POR CAMPO.** Era el cuarto
          // problema del dueño: con una nota bajo cada cuadro, ninguna se lee.
          Text(n, style: AppTypography.caption.copyWith(color: colors.textMuted)),
        ],
      ],
    );
  }
}

/// Un dato **en modo vista: etiqueta arriba, valor como TEXTO**.
///
/// 🚫 Nunca una caja deshabilitada. Era el problema de «la vista se ve casi igual que la
/// edición»: un cuadro gris con el texto apagado parece un campo que no te dejan tocar,
/// no un dato.
class _DatoLeido extends StatelessWidget {
  const _DatoLeido(this.dato);

  final _Dato dato;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          dato.etiqueta.toUpperCase(),
          style: AppTypography.label.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 2),
        Text(
          dato.valor.isEmpty ? 'No registrado' : dato.valor,
          style: dato.valor.isEmpty
              ? AppTypography.body.copyWith(color: colors.textDisabled)
              : AppTypography.bodyStrong,
        ),
      ],
    );
  }
}

/// Un dato en **lista de definición**: etiqueta a la izquierda, valor a la derecha.
class _DatoEnLinea extends StatelessWidget {
  const _DatoEnLinea(this.dato);

  final _Dato dato;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 210,
            child: Text(
              dato.etiqueta,
              style: AppTypography.body.copyWith(color: colors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              dato.valor.isEmpty ? 'No registrado' : dato.valor,
              style: dato.valor.isEmpty
                  ? AppTypography.body.copyWith(color: colors.textDisabled)
                  : AppTypography.bodyStrong,
            ),
          ),
        ],
      ),
    );
  }
}

/// Una cuadrícula de datos donde **cada uno mide lo que le toca**.
///
/// 🚫 Tres columnas iguales era el primer problema: un código postal y una calle con el
/// mismo ancho hacen que la vista no sepa dónde parar. [_Dato.ancho] dice cuántas
/// unidades de doce ocupa cada uno.
class _Cuadricula extends StatelessWidget {
  const _Cuadricula({required this.datos, required this.pintar});

  final List<_Dato> datos;
  final Widget Function(_Dato) pintar;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, caja) {
      final unidad = (caja.maxWidth - AppSpacing.lg * 3) / 4;

      return Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.md,
        children: [
          for (final d in datos)
            SizedBox(
              width: (unidad * d.ancho + AppSpacing.lg * (d.ancho - 1)).clamp(
                120.0,
                caja.maxWidth,
              ),
              child: pintar(d),
            ),
        ],
      );
    },
  );
}

/// La cabecera del expediente: **lo que identifica y lo que se puede hacer, juntos.**
class _Cabecera extends StatelessWidget {
  const _Cabecera({
    required this.modulo,
    required this.compacta,
  });

  final _Modulo modulo;

  /// En el estilo de pestañas va compacta, porque las pestañas van debajo.
  final bool compacta;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final esServicio = modulo == _Modulo.servicios;

    final titulo = esServicio ? 'Sportium Satélite' : 'Sportium';
    final bajo = esServicio
        ? 'SRV-000001 · Sportium · Vigilancia intramuros'
        : 'CLI-000004 · cliente desde mar/2019';

    final cifras = esServicio
        ? const [
            _Dato('Importe mensual', r'$48,500.00 MXN'),
            _Dato('Antigüedad', '7 años, 8 meses'),
            _Dato('Supervisor', 'Luis Ángel Pérez'),
          ]
        : const [
            _Dato('Servicios activos', '2'),
            _Dato('Suspendidos', '0'),
            _Dato('Importe mensual', r'$61,200.00 MXN'),
          ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.borderSubtle),
        borderRadius: AppRadius.lgRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegIniciales(id: 'cli-4', nombre: titulo, lado: compacta ? 40 : 52),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: compacta
                          ? AppTypography.heading2
                          : AppTypography.heading1,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      bajo,
                      style: AppTypography.caption.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xxs,
                      children: [
                        const RisegStatusBadge(
                          label: 'Activo',
                          tone: RisegStatusTone.success,
                          icon: Icons.check_circle_outline,
                        ),
                        if (esServicio)
                          const RisegStatusBadge(
                            label: 'Termina el 30/nov/2026',
                            tone: RisegStatusTone.warning,
                            icon: Icons.schedule,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  RisegButton(
                    label: 'Cambiar estatus',
                    variant: RisegButtonVariant.secondary,
                    size: RisegButtonSize.compact,
                    icon: Icons.swap_horiz,
                    onPressed: () {},
                  ),
                  RisegButton(
                    label: 'Editar',
                    size: RisegButtonSize.compact,
                    icon: Icons.edit_outlined,
                    onPressed: () {},
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(height: 1, color: colors.borderSubtle),
          const SizedBox(height: AppSpacing.md),
          // LAS CIFRAS QUE SE MIRAN PRIMERO, en la cabecera y no al final de la página.
          Wrap(
            spacing: AppSpacing.xxl,
            runSpacing: AppSpacing.sm,
            children: [for (final c in cifras) _DatoLeido(c)],
          ),
        ],
      ),
    );
  }
}

/// El marco de una pantalla: título, acción y el cuerpo con su ancho de lectura.
class _Marco extends StatelessWidget {
  const _Marco({
    required this.titulo,
    required this.bajoTitulo,
    required this.hijo,
    this.accion,
    this.ancho = 1100,
  });

  final String titulo;
  final String bajoTitulo;
  final Widget hijo;
  final Widget? accion;
  final double ancho;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Center(
        child: SizedBox(
          width: ancho,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titulo, style: AppTypography.heading1),
                        const SizedBox(height: 2),
                        Text(
                          bajoTitulo,
                          style: AppTypography.caption.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (accion case final a?) a,
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              hijo,
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// ESTILO A · DOCUMENTO
// ===========================================================================

class _ListadoDocumento extends StatelessWidget {
  const _ListadoDocumento({required this.filas, required this.modulo});

  final List<_Fila> filas;
  final _Modulo modulo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final esServicio = modulo == _Modulo.servicios;

    return _Marco(
      titulo: esServicio ? 'Servicios' : 'Clientes',
      bajoTitulo: esServicio
          ? '5 servicios · 4 vigentes'
          : '4 clientes · 3 activos',
      accion: RisegButton(
        label: esServicio ? 'Nuevo servicio' : 'Nuevo cliente',
        icon: Icons.add,
        onPressed: () {},
      ),
      hijo: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LOS FILTROS NO SON UNA BARRA DE CAJAS: son texto que se pulsa, y el que está
          // puesto se ve puesto. Con tres selectores grises arriba, la vista se gasta en
          // ellos antes de llegar a la primera fila.
          Row(
            children: [
              const _ChipDeFiltro('Vigentes', puesto: true),
              const _ChipDeFiltro('Finalizados'),
              if (esServicio) const _ChipDeFiltro('Por terminar'),
              const Spacer(),
              SizedBox(
                width: 260,
                child: TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: esServicio
                        ? 'Buscar por nombre o folio'
                        : 'Buscar por nombre o folio',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: AppRadius.mdRadius,
                      borderSide: BorderSide(color: colors.borderSubtle),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // LA TABLA SIN TARJETA: líneas de pelo y nada más. Lo que separa una fila de
          // otra es el espacio, no un borde por celda.
          for (final f in filas) _FilaDocumento(fila: f),
        ],
      ),
    );
  }
}

class _ChipDeFiltro extends StatelessWidget {
  const _ChipDeFiltro(this.texto, {this.puesto = false});

  final String texto;
  final bool puesto;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs + 2,
        ),
        decoration: BoxDecoration(
          color: puesto ? colors.accentSoftBg : Colors.transparent,
          borderRadius: AppRadius.fullRadius,
          border: Border.all(
            color: puesto ? colors.accent : colors.borderSubtle,
          ),
        ),
        child: Text(
          texto,
          style: AppTypography.caption.copyWith(
            color: puesto ? colors.accent : colors.textMuted,
            fontWeight: puesto ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _FilaDocumento extends StatelessWidget {
  const _FilaDocumento({required this.fila});

  final _Fila fila;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: [
          RisegIniciales(id: fila.bajoTitulo, nombre: fila.titulo, lado: 32),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fila.titulo, style: AppTypography.bodyStrong),
                Text(
                  fila.bajoTitulo,
                  style: AppTypography.caption.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              fila.ubicacion,
              style: AppTypography.body.copyWith(
                color: fila.ubicacion == 'No registrada'
                    ? colors.textDisabled
                    : colors.textPrimary,
              ),
            ),
          ),
          SizedBox(
            width: 210,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RisegStatusBadge(label: fila.estatus, tone: fila.tono),
                if (fila.temporal case final t?) ...[
                  const SizedBox(height: 2),
                  Text(
                    t,
                    style: AppTypography.caption.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: colors.textMuted),
        ],
      ),
    );
  }
}

class _ExpedienteDocumento extends StatelessWidget {
  const _ExpedienteDocumento({required this.modulo});

  final _Modulo modulo;

  @override
  Widget build(BuildContext context) => _Marco(
    titulo: modulo == _Modulo.servicios ? 'Servicios' : 'Clientes',
    bajoTitulo: 'Expediente',
    hijo: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Cabecera(modulo: modulo, compacta: false),
        const SizedBox(height: AppSpacing.xxl),
        // LAS SECCIONES, UNA DEBAJO DE OTRA Y SIN TARJETAS: lo que las separa es su
        // título y el aire. Cada dato es TEXTO, y por eso la vista no se parece a la
        // edición.
        for (final s in _fichaDelServicio) ...[
          _TituloDeSeccion(s.titulo, nota: s.nota),
          const SizedBox(height: AppSpacing.md),
          _Cuadricula(datos: s.datos, pintar: _DatoLeido.new),
          const SizedBox(height: AppSpacing.xxl),
        ],
        const _TituloDeSeccion('Historial'),
        const SizedBox(height: AppSpacing.md),
        const _Historial(),
      ],
    ),
  );
}

class _AltaDocumento extends StatelessWidget {
  const _AltaDocumento();

  @override
  Widget build(BuildContext context) => _Marco(
    // UNA COLUMNA DE LECTURA Y NO LA PANTALLA ENTERA: quince campos repartidos en 1 600
    // píxeles obligan a cruzar el monitor con la vista en cada salto.
    ancho: 760,
    titulo: 'Nuevo servicio',
    bajoTitulo: 'Lo que se le presta a un cliente en un lugar concreto',
    hijo: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in _camposDelAlta) ...[
          _TituloDeSeccion(s.titulo, nota: s.nota),
          const SizedBox(height: AppSpacing.md),
          _Cuadricula(datos: s.datos, pintar: _CampoDePrueba.new),
          const SizedBox(height: AppSpacing.xxl),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            RisegButton(
              label: 'Cancelar',
              variant: RisegButtonVariant.ghost,
              onPressed: () {},
            ),
            const SizedBox(width: AppSpacing.xs),
            RisegButton(
              label: 'Guardar',
              icon: Icons.save_outlined,
              onPressed: () {},
            ),
          ],
        ),
      ],
    ),
  );
}

/// Un campo de captura **sin letra chica debajo**, y con el ancho de lo que se escribe.
class _CampoDePrueba extends StatelessWidget {
  const _CampoDePrueba(this.dato);

  final _Dato dato;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(dato.etiqueta, style: AppTypography.label),
        const SizedBox(height: AppSpacing.xxs),
        TextField(
          controller: TextEditingController(text: dato.valor),
          maxLines: dato.etiqueta == 'Observaciones' ? 3 : 1,
          decoration: InputDecoration(
            isDense: true,
            // ⚠️ **SIN RELLENO GRIS.** Era el primer problema del dueño: con todos los
            // cuadros rellenos del mismo gris, la pantalla es una rejilla y no un
            // formulario. El borde basta para decir «aquí se escribe».
            filled: false,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs + 2,
            ),
            border: OutlineInputBorder(
              borderRadius: AppRadius.mdRadius,
              borderSide: BorderSide(color: colors.borderSubtle),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadius.mdRadius,
              borderSide: BorderSide(color: colors.borderSubtle),
            ),
          ),
        ),
        if (dato.nota case final n?) ...[
          const SizedBox(height: 2),
          Text(n, style: AppTypography.caption.copyWith(color: colors.textMuted)),
        ],
      ],
    );
  }
}

class _Historial extends StatelessWidget {
  const _Historial();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    const eventos = [
      ('11/nov/2026 09:14', 'Se programó el término para el 30/nov/2026', 'Ana Torres'),
      ('02/nov/2026 17:40', 'Se asignó el supervisor Luis Ángel Pérez', 'Ana Torres'),
      ('20/oct/2026 12:02', 'Se corrigió el nombre · motivo: cambió el rótulo', 'Beto Ríos'),
    ];

    return Column(
      children: [
        for (final (cuando, que, quien) in eventos)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 150,
                  child: Text(
                    cuando,
                    style: AppTypography.data.copyWith(color: colors.textMuted),
                  ),
                ),
                Expanded(child: Text(que, style: AppTypography.body)),
                Text(
                  quien,
                  style: AppTypography.caption.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ===========================================================================
// ESTILO B · PESTAÑAS
// ===========================================================================

class _ListadoPestanas extends StatelessWidget {
  const _ListadoPestanas({required this.filas, required this.modulo});

  final List<_Fila> filas;
  final _Modulo modulo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final esServicio = modulo == _Modulo.servicios;

    return _Marco(
      titulo: esServicio ? 'Servicios' : 'Clientes',
      bajoTitulo: esServicio
          ? '5 servicios · 4 vigentes'
          : '4 clientes · 3 activos',
      accion: RisegButton(
        label: esServicio ? 'Nuevo servicio' : 'Nuevo cliente',
        icon: Icons.add,
        onPressed: () {},
      ),
      hijo: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _ChipDeFiltro('Vigentes', puesto: true),
              const _ChipDeFiltro('Finalizados'),
              if (esServicio) const _ChipDeFiltro('Por terminar'),
              const Spacer(),
              SizedBox(
                width: 260,
                child: TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Buscar por nombre o folio',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: AppRadius.mdRadius,
                      borderSide: BorderSide(color: colors.borderSubtle),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // AQUÍ SÍ HAY TARJETA, y una franja de color por estatus: el listado es un
          // tablero de trabajo, y lo primero que se busca en él es «cuál está mal».
          Container(
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(color: colors.borderSubtle),
              borderRadius: AppRadius.lgRadius,
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppRadius.lg),
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 44),
                      Expanded(flex: 4, child: _Encabezado(esServicio ? 'Servicio' : 'Cliente')),
                      const Expanded(flex: 4, child: _Encabezado('Ubicación')),
                      const SizedBox(width: 210, child: _Encabezado('Estatus')),
                      const SizedBox(width: 24),
                    ],
                  ),
                ),
                for (final f in filas) _FilaConFranja(fila: f),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Text(
    texto.toUpperCase(),
    style: AppTypography.label.copyWith(
      color: context.colors.textMuted,
      letterSpacing: 1,
    ),
  );
}

class _FilaConFranja extends StatelessWidget {
  const _FilaConFranja({required this.fila});

  final _Fila fila;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final franja = switch (fila.tono) {
      RisegStatusTone.success => colors.success,
      RisegStatusTone.warning => colors.warning,
      RisegStatusTone.error => colors.error,
      RisegStatusTone.info => colors.info,
      RisegStatusTone.neutral => colors.borderSubtle,
    };

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.borderSubtle),
          left: BorderSide(color: franja, width: 3),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          RisegIniciales(id: fila.bajoTitulo, nombre: fila.titulo, lado: 32),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fila.titulo, style: AppTypography.bodyStrong),
                Text(
                  fila.bajoTitulo,
                  style: AppTypography.caption.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              fila.ubicacion,
              style: AppTypography.body.copyWith(
                color: fila.ubicacion == 'No registrada'
                    ? colors.textDisabled
                    : colors.textPrimary,
              ),
            ),
          ),
          SizedBox(
            width: 210,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RisegStatusBadge(label: fila.estatus, tone: fila.tono),
                if (fila.temporal case final t?) ...[
                  const SizedBox(height: 2),
                  Text(
                    t,
                    style: AppTypography.caption.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: colors.textMuted),
        ],
      ),
    );
  }
}

class _ExpedientePestanas extends StatefulWidget {
  const _ExpedientePestanas({required this.modulo});

  final _Modulo modulo;

  @override
  State<_ExpedientePestanas> createState() => _ExpedientePestanasState();
}

class _ExpedientePestanasState extends State<_ExpedientePestanas> {
  int _puesta = 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final pestanas = [
      for (final s in _fichaDelServicio) s.titulo,
      'Historial',
    ];

    return _Marco(
      titulo: widget.modulo == _Modulo.servicios ? 'Servicios' : 'Clientes',
      bajoTitulo: 'Expediente',
      hijo: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Cabecera(modulo: widget.modulo, compacta: true),
          const SizedBox(height: AppSpacing.lg),
          // LAS PESTAÑAS: nunca se ve más de un asunto a la vez, así que la página no
          // crece y nadie tiene que recordar qué había tres pantallas más abajo.
          Row(
            children: [
              for (var i = 0; i < pestanas.length; i++)
                _Pestana(
                  texto: pestanas[i],
                  puesta: i == _puesta,
                  alPulsar: () => setState(() => _puesta = i),
                ),
            ],
          ),
          Container(height: 1, color: colors.borderSubtle),
          const SizedBox(height: AppSpacing.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(color: colors.borderSubtle),
              borderRadius: AppRadius.lgRadius,
            ),
            child: _puesta == _fichaDelServicio.length
                ? const _Historial()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_fichaDelServicio[_puesta].nota case final n?) ...[
                        Text(
                          n,
                          style: AppTypography.caption.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      // LISTA DE DEFINICIÓN: etiqueta a la izquierda, dato a la derecha.
                      // Así un dato que sólo se lee **no puede** parecer un campo
                      // apagado, que era el cuarto problema.
                      for (final d in _fichaDelServicio[_puesta].datos)
                        _DatoEnLinea(d),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Pestana extends StatelessWidget {
  const _Pestana({
    required this.texto,
    required this.puesta,
    required this.alPulsar,
  });

  final String texto;
  final bool puesta;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      onTap: alPulsar,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: puesta ? colors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          texto,
          style: AppTypography.body.copyWith(
            color: puesta ? colors.accent : colors.textMuted,
            fontWeight: puesta ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _AltaPestanas extends StatelessWidget {
  const _AltaPestanas();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return _Marco(
      titulo: 'Nuevo servicio',
      bajoTitulo: 'Lo que se le presta a un cliente en un lugar concreto',
      hijo: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in _camposDelAlta) ...[
                  Container(
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
                        Text(s.titulo, style: AppTypography.heading3),
                        if (s.nota case final n?) ...[
                          const SizedBox(height: 2),
                          Text(
                            n,
                            style: AppTypography.caption.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        _Cuadricula(
                          datos: s.datos,
                          pintar: _CampoDePrueba.new,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          // EL RESUMEN FIJO: con quince campos, lo que se va a crear se pierde de vista.
          // Y las acciones viven aquí, no al final de la página.
          SizedBox(
            width: 280,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: colors.surfaceSunken,
                border: Border.all(color: colors.borderSubtle),
                borderRadius: AppRadius.lgRadius,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Vas a crear', style: AppTypography.heading3),
                  const SizedBox(height: AppSpacing.md),
                  const _DatoLeido(_Dato('Servicio', 'Sportium Satélite')),
                  const SizedBox(height: AppSpacing.sm),
                  const _DatoLeido(_Dato('Cliente', 'Sportium')),
                  const SizedBox(height: AppSpacing.sm),
                  const _DatoLeido(_Dato('Tipo', 'Vigilancia intramuros')),
                  const SizedBox(height: AppSpacing.sm),
                  const _DatoLeido(_Dato('Inicio', '11/nov/2026')),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: RisegButton(
                      label: 'Guardar',
                      icon: Icons.save_outlined,
                      onPressed: () {},
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    width: double.infinity,
                    child: RisegButton(
                      label: 'Cancelar',
                      variant: RisegButtonVariant.ghost,
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
