import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../datos/usuarios_repositorio_http.dart';
import '../../../../core/fechas/fecha_en_pantalla.dart';
import '../modelos/evento_de_auditoria.dart';
import 'auditoria_legible.dart';

/// La auditoría de la empresa: **qué pasó, quién lo hizo y cuándo**.
///
/// ## Escrita para alguien que no programa
///
/// Cada fila dice una frase —«Creó el área Monitoreo», «Dio acceso a Juan Pérez»— y el
/// detalle es una lista de campos con etiquetas en español. **Nunca se muestra JSON**:
/// ni como respaldo ni cuando algo no se entiende. Toda la traducción vive en
/// [AuditoriaLegible], que se prueba sin tocar un widget.
///
/// ## Es una PESTAÑA DE CONFIGURACIÓN y carga lo suyo
///
/// Vive junto a Usuarios, como en el escritorio. Y **se abastece sola**: pide los
/// nombres de las personas y el catálogo de permisos por su cuenta, en vez de que se
/// los pase la pestaña vecina.
///
/// Parece un viaje de más y no lo es: `company.audit.read` **no es un permiso de
/// Maestro**, así que puede leer esta pantalla alguien que no pueda leer la lista de
/// accesos. Depender de que Usuarios la hubiera cargado habría dejado a esa persona
/// con una auditoría sin nombres y sin explicación.
///
/// ## Sólo aparece con `company.audit.read`
///
/// Y eso lo decide quien la monta, no esta clase. **Ocultarla no es autorizar** —el
/// servidor vuelve a decidir en cada petición—; es no ofrecer una puerta que va a
/// responder 403.
///
/// ## Lo que NO hace
///
/// **No filtra.** El servidor acepta filtros por fecha, actor, entidad y acción, y no
/// se exponen todavía: con un solo módulo mudado, la auditoría de una empresa cabe en
/// dos o tres páginas. Cuando haya volumen, los filtros van **al servidor**, no a un
/// `where` sobre lo ya descargado.
class AuditoriaWebScreen extends StatefulWidget {
  const AuditoriaWebScreen({
    required this.repositorio,
    required this.empresaId,
    super.key,
  });

  final UsuariosRepositorioHttp repositorio;
  final String empresaId;

  @override
  State<AuditoriaWebScreen> createState() => _AuditoriaWebScreenState();
}

class _AuditoriaWebScreenState extends State<AuditoriaWebScreen> {
  final _eventos = <EventoDeAuditoria>[];

  /// Quien traduce los códigos a español. **Arranca pelado y se enriquece**: la
  /// auditoría se puede leer sin nombres —un actor sale por su identidad abreviada—,
  /// así que no se bloquea la pantalla esperando los diccionarios.
  AuditoriaLegible _traductor = const AuditoriaLegible(
    nombrePorIdentidad: {},
    nombrePorPermiso: {},
  );

  String? _cursor;
  bool _hayMas = true;

  Failure? _fallo;
  bool _cargando = true;
  bool _cargandoMas = false;

  /// Qué filas tienen el detalle abierto, por id.
  final _abiertos = <String>{};

  @override
  void initState() {
    super.initState();
    _cargarPrimera();
  }

  Future<void> _cargarPrimera() async {
    setState(() {
      _cargando = true;
      _fallo = null;
      _eventos.clear();
      _cursor = null;
      _hayMas = true;
      _abiertos.clear();
    });

    await Future.wait([_pedir(), _cargarDiccionarios()]);
  }

  /// Los nombres de personas y de permisos, **los dos a prueba de fallo**.
  ///
  /// `listarMiembros` es SÓLO MAESTRO y aquí puede responder 403 legítimamente: quien
  /// tiene `company.audit.read` sin ser Maestro lee la auditoría y no el directorio.
  /// Eso **no es un error que mostrar** — los actores saldrán por su identidad
  /// abreviada, que es el comportamiento que esta pantalla ya promete.
  Future<void> _cargarDiccionarios() async {
    final (miembros, catalogo) = await (
      widget.repositorio.listarMiembros(widget.empresaId),
      widget.repositorio.listarCatalogo(widget.empresaId),
    ).wait;

    if (!mounted) return;

    setState(() {
      _traductor = AuditoriaLegible(
        nombrePorIdentidad: miembros.when(
          ok: (lista) => {for (final m in lista) m.identidadId: m.nombreVisible},
          failure: (_) => const {},
        ),
        nombrePorPermiso: catalogo.when(
          ok: (lista) => {for (final p in lista) p.codigo: p.nombre},
          failure: (_) => const {},
        ),
        // DEL MISMO CATÁLOGO, que ya estaba cargado. Antes estas etiquetas eran un
        // mapa de siete escrito en `apartados_web.dart`, y ya había derivado de
        // `app.platform_module` en dos: «Compras e inventario» por «Compras e
        // Inventario» y «Clientes y servicios» por «Clientes y Servicios».
        //
        // Se recorre el catálogo de PERMISOS porque es donde viaja el nombre; varios
        // permisos del mismo módulo escriben la misma entrada, que es inofensivo.
        nombrePorModulo: catalogo.when(
          ok: (lista) => {
            for (final p in lista)
              if (p.modulo != null && p.nombreDelModulo != null)
                p.modulo!: p.nombreDelModulo!,
          },
          failure: (_) => const {},
        ),
      );
    });
  }

  Future<void> _cargarMas() async {
    if (_cargandoMas || !_hayMas) return;

    setState(() => _cargandoMas = true);
    await _pedir();
  }

  Future<void> _pedir() async {
    final resultado = await widget.repositorio.auditoria(
      widget.empresaId,
      cursor: _cursor,
    );

    if (!mounted) return;

    resultado.when(
      ok: (pagina) => setState(() {
        _eventos.addAll(pagina.eventos);
        _cursor = pagina.siguienteCursor;
        _hayMas = pagina.hayMas;
        _cargando = false;
        _cargandoMas = false;
        _fallo = null;
      }),
      failure: (f) => setState(() {
        _fallo = f;
        _cargando = false;
        _cargandoMas = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // MISMO ENCABEZADO QUE USUARIOS, porque son dos pestañas del mismo apartado y sin
    // título la segunda parecía un listado suelto. El subtítulo dice el ORDEN, que es
    // lo primero que alguien se pregunta al mirar una traza — y es exacto: el servidor
    // ordena por `occurred_at DESC`.
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Auditoría', style: AppTypography.heading1),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Lo que se ha hecho en esta empresa, del más reciente al más antiguo.',
                style: AppTypography.caption.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(child: _cuerpo()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const Center(child: CircularProgressIndicator());

    // EL FALLO SÓLO BORRA LA PANTALLA SI NO HAY NADA. Si falló al pedir la segunda
    // página, lo ya traído sigue siendo útil y se avisa abajo.
    if (_fallo case final f? when _eventos.isEmpty) {
      return RisegEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudo cargar la auditoría',
        message: f.message,
        primaryAction: RisegButton(
          label: 'Intentar de nuevo',
          onPressed: _cargarPrimera,
        ),
      );
    }

    if (_eventos.isEmpty) {
      return const RisegEmptyState(
        icon: Icons.history_toggle_off_outlined,
        title: 'Todavía no hay nada registrado',
        message:
            'Aquí van a aparecer los cambios de esta empresa: quién dio un acceso, '
            'quién cambió un permiso, qué se creó y cuándo.',
      );
    }

    return ListView.separated(
      // +1 por el pie: el botón de «Cargar más» o el aviso de que no hay más.
      itemCount: _eventos.length + 1,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        if (i == _eventos.length) return _pie();

        final e = _eventos[i];

        return _FilaDeEvento(
          evento: e,
          traductor: _traductor,
          abierto: _abiertos.contains(e.id),
          onAbrirOCerrar: () => setState(() {
            if (!_abiertos.remove(e.id)) _abiertos.add(e.id);
          }),
        );
      },
    );
  }

  Widget _pie() {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: Column(
          children: [
            // SI FALLÓ PIDIENDO MÁS, SE DICE AQUÍ y lo ya traído se queda: borrar la
            // lista por un fallo de la página siguiente sería perder lo que sí llegó.
            if (_fallo case final f?) ...[
              Text(
                'No se pudo cargar más: ${f.message}',
                style: AppTypography.caption.copyWith(color: colors.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],

            if (_hayMas)
              RisegButton(
                label: _cargandoMas ? 'Cargando…' : 'Cargar más',
                variant: RisegButtonVariant.secondary,
                onPressed: _cargandoMas ? null : _cargarMas,
              )
            else
              Text(
                _eventos.length == 1
                    ? 'Un solo registro, y es todo.'
                    : '${_eventos.length} registros, y es todo.',
                style: AppTypography.caption.copyWith(color: colors.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Una fila
// ===========================================================================

class _FilaDeEvento extends StatelessWidget {
  const _FilaDeEvento({
    required this.evento,
    required this.traductor,
    required this.abierto,
    required this.onAbrirOCerrar,
  });

  final EventoDeAuditoria evento;
  final AuditoriaLegible traductor;
  final bool abierto;
  final VoidCallback onAbrirOCerrar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final campos = traductor.campos(evento);
    final aviso = traductor.avisoDeFormato(evento);
    final hayDetalle = campos.isNotEmpty || aviso != null;

    return InkWell(
      onTap: hayDetalle ? onAbrirOCerrar : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.md,
          horizontal: AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // LA FRASE, con el objeto nombrado. Es lo que se lee de un
                      // barrido vertical, y por eso va primera y en negrita.
                      Text(traductor.titulo(evento), style: AppTypography.bodyStrong),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        traductor.actor(evento),
                        style: AppTypography.caption.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),

                // LA FECHA, EN LOCAL Y COMPLETA. Nada de «hace 3 horas»: en una
                // auditoría la hora exacta es el dato, y un relativo obliga a
                // calcularla de cabeza.
                Text(
                  // EL FORMATEADOR ES COMPARTIDO y él hace el `toLocal()`: la hora de
                  // la bitácora se lee en la de quien mira, que es lo que quiere saber.
                  fechaYHora(evento.cuando),
                  style: AppTypography.caption.copyWith(
                    color: colors.textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),

                if (hayDetalle) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    abierto ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: colors.textMuted,
                  ),
                ],
              ],
            ),

            if (abierto) ...[
              const SizedBox(height: AppSpacing.sm),
              if (aviso case final a?)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    a,
                    style: AppTypography.caption.copyWith(color: colors.warning),
                  ),
                ),
              for (final campo in campos) _Campo(campo: campo),
            ],
          ],
        ),
      ),
    );
  }

}

// ===========================================================================
// Un campo del detalle
// ===========================================================================

class _Campo extends StatelessWidget {
  const _Campo({required this.campo});

  final CampoLegible campo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LA ETIQUETA, DE ANCHO FIJO, para que los valores queden alineados en
          // columna: una lista de pares con el separador bailando se lee peor.
          SizedBox(
            width: 150,
            child: Text(
              campo.etiqueta,
              style: AppTypography.caption.copyWith(color: colors.textMuted),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // ALINEADO A LA IZQUIERDA Y SIN ESTIRAR. Sin el `Align`, un chip de estado
          // dentro del `Expanded` se estiraba a todo el ancho de la fila y dejaba de
          // parecer una pastilla: en la lista de Áreas se ve compacto y aquí tiene
          // que verse igual.
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: campo.esCambio
                  // UN CAMBIO SE LEE «antes → después», con la flecha en medio. Es la
                  // forma más corta de decir las dos cosas sin dos renglones.
                  ? Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xxs,
                      children: [
                        _Valor(valor: campo.antes!, tachado: true),
                        Icon(
                          Icons.arrow_forward,
                          size: 14,
                          color: colors.textMuted,
                        ),
                        _Valor(valor: campo.despues!),
                      ],
                    )
                  : _Valor(valor: campo.despues ?? campo.antes!),
            ),
          ),
        ],
      ),
    );
  }
}

class _Valor extends StatelessWidget {
  const _Valor({required this.valor, this.tachado = false});

  final ValorLegible valor;

  /// El valor anterior va **en gris y tachado**: se ve de un golpe cuál de los dos es
  /// el que vale ahora, sin leer la dirección de la flecha.
  final bool tachado;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // UN ESTADO ES UN CHIP CON COLOR E ÍCONO. El ícono no es decoración: quien no
    // distingue verde de gris sigue viendo la diferencia.
    if (valor.forma == FormaDeValor.estado) {
      final tono = _tonoDe(valor.estadoCrudo);

      return Opacity(
        opacity: tachado ? 0.55 : 1,
        child: RisegStatusBadge(
          label: valor.texto,
          tone: tono.tono,
          icon: tono.icono,
        ),
      );
    }

    return Text(
      valor.texto,
      style: AppTypography.body.copyWith(
        color: tachado ? colors.textMuted : colors.textPrimary,
        decoration: tachado ? TextDecoration.lineThrough : null,
      ),
    );
  }

  /// **Un estado desconocido NO se pinta de verde.** Sale neutro con un ícono de
  /// interrogación: inventarle un color diría algo que no se sabe.
  static ({RisegStatusTone tono, IconData icono}) _tonoDe(String? estado) =>
      switch (estado) {
        'activa' => (
          tono: RisegStatusTone.success,
          icono: Icons.check_circle_outline,
        ),
        'inactiva' => (
          tono: RisegStatusTone.neutral,
          icono: Icons.remove_circle_outline,
        ),
        'revocada' => (tono: RisegStatusTone.error, icono: Icons.block_outlined),
        'draft' => (tono: RisegStatusTone.warning, icono: Icons.edit_outlined),
        _ => (tono: RisegStatusTone.neutral, icono: Icons.help_outline),
      };
}
