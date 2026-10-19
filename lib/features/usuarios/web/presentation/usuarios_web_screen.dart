import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../datos/usuarios_repositorio_http.dart';
import '../modelos/capacidad_de_accesos.dart';
import '../modelos/miembro_de_empresa.dart';
import '../modelos/permiso_de_empresa.dart';
import '../../../../app/shell/apartados_web.dart' as apartados;

/// Configuración › Usuarios, en la web. **Etapa 2A.**
///
/// Quién puede entrar a esta empresa y qué puede hacer. Es la pantalla que faltaba
/// para dar de alta a un cliente: sin ella, el Maestro no puede delegar nada.
///
/// ## Las dos cifras van SEPARADAS, y es la decisión que más cuesta ver
///
/// «3 personas con acceso a esta empresa» sale de contar la lista. «4 de 10 accesos de
/// tu plan, en todas tus empresas» viene del servidor y es de **toda la organización**.
/// Juntarlas —«3 de 10»— haría creer que quedan 7 para esta empresa, cuando el cliente
/// quizá ya los gastó en otra. Son dos cosas distintas y se escriben distinto.
///
/// ## El cliente informa; el servidor decide
///
/// Ninguna acción se apaga por una cuenta hecha aquí. Si no hay cupo, el servidor
/// rechaza y la pantalla **traduce su código**. Un botón apagado por aritmética del
/// navegador sería una segunda fuente de verdad sobre la capacidad, y el día que
/// discrepara ganaría la equivocada: la pantalla se vería coherente y la petición
/// fallaría.
///
/// ## Lo que NO entra aquí
///
///  · **Dar de alta a alguien nuevo** — es 2B, por invitación al correo. Hoy el acceso
///    se concede sobre una identidad que ya existe, y pedir un UUID a mano no es una
///    pantalla.
///  · **Las plantillas de permisos** — entran con Personal (M4), cuando haya puestos
///    que las hagan significar algo.
///
/// <b>Importa `design_system_web.dart`, NUNCA el barrel completo</b>, que arrastra
/// `dart:io` y rompe la build web sin que nada aquí parezca mal.
class UsuariosWebScreen extends StatefulWidget {
  const UsuariosWebScreen({
    required this.repositorio,
    required this.empresaId,
    super.key,
  });

  final UsuariosRepositorioHttp repositorio;
  final String empresaId;

  @override
  State<UsuariosWebScreen> createState() => _UsuariosWebScreenState();
}

class _UsuariosWebScreenState extends State<UsuariosWebScreen> {

  List<MiembroDeEmpresa>? _miembros;
  List<PermisoDeEmpresa>? _catalogo;

  /// **Puede faltar sin que la pantalla deje de servir**, y por eso tiene su propio
  /// fallo en vez de compartir el de la lista: la lista de personas es útil aunque el
  /// contador del plan no se haya podido leer. Lo que no se hace es **inventar un
  /// cero**: «0 de 0 accesos» diría que el plan no incluye ninguno.
  CapacidadDeAccesos? _capacidad;
  Failure? _falloDeCapacidad;

  Failure? _fallo;
  bool _cargando = true;

  final _buscador = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    // Liberar el controller no es opcional, y en este proyecto ya costó una vez.
    _buscador.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _fallo = null;
      _falloDeCapacidad = null;
    });

    // LAS TRES A LA VEZ. Son independientes, y en serie la pantalla tardaría el triple
    // en pintar algo.
    final (miembros, catalogo, capacidad) = await (
      widget.repositorio.listarMiembros(widget.empresaId),
      widget.repositorio.listarCatalogo(widget.empresaId),
      widget.repositorio.capacidadDeAccesos(widget.empresaId),
    ).wait;

    if (!mounted) return;

    setState(() {
      _cargando = false;

      // EL FALLO QUE MANDA ES EL DE LA LISTA. Sin ella no hay pantalla; sin el
      // catálogo no se pueden editar permisos, y eso se dice al abrir el panel.
      miembros.when(
        ok: (m) => _miembros = m,
        failure: (f) => _fallo = f,
      );

      catalogo.when(
        ok: (c) => _catalogo = c,
        failure: (f) => _fallo ??= f,
      );

      capacidad.when(
        ok: (c) {
          _capacidad = c;
          _falloDeCapacidad = null;
        },
        failure: (f) {
          _capacidad = null;
          _falloDeCapacidad = f;
        },
      );
    });
  }


  /// Filtrado por el buscador. **Mira nombre Y correo**: quien escribe «ana» puede
  /// estar buscando a Ana o `ana@...`, y no tiene por qué saber cuál coincide.
  List<MiembroDeEmpresa> get _visibles {
    final todos = _miembros ?? const <MiembroDeEmpresa>[];
    final texto = _buscador.text.trim().toLowerCase();

    if (texto.isEmpty) return todos;

    return todos
        .where(
          (m) =>
              m.nombreVisible.toLowerCase().contains(texto) ||
              m.correo.toLowerCase().contains(texto),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Encabezado(
                personas: _miembros?.length ?? 0,
                capacidad: _capacidad,
                falloDeCapacidad: _falloDeCapacidad,
                onReintentarCapacidad: _cargando ? null : _cargar,
              ),

              // LAS PESTAÑAS YA NO VIVEN AQUÍ: subieron al apartado, igual que en el
              // escritorio. `Configuración → Usuarios · Auditoría` lo monta el portón,
              // así que esta pantalla es sólo Usuarios y Auditoría es su hermana.
              const SizedBox(height: AppSpacing.md),
              RisegSearchField(
                hint: 'Buscar por nombre o correo',
                controller: _buscador,
                onChanged: (_) => setState(() {}),
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

    if (_fallo case final f?) {
      return RisegEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudieron cargar los usuarios',
        message: f.message,
        primaryAction: RisegButton(label: 'Intentar de nuevo', onPressed: _cargar),
      );
    }

    // ESTE VACÍO ES CASI IMPOSIBLE y aun así se escribe: toda empresa nace con un
    // Maestro, así que la lista no puede estar vacía salvo que algo esté muy mal. Un
    // `ListView` sobre cero elementos pintaría una pantalla en blanco sin explicación.
    if ((_miembros ?? const <MiembroDeEmpresa>[]).isEmpty) {
      return RisegEmptyState(
        icon: Icons.people_outline,
        title: 'Esta empresa no tiene a nadie con acceso',
        message:
            'Toda empresa se crea con un Maestro, así que esto no debería pasar. '
            'Vuelve a cargar; si sigue igual, avísanos.',
        primaryAction: RisegButton(label: 'Intentar de nuevo', onPressed: _cargar),
      );
    }

    if (_visibles.isEmpty) {
      return RisegEmptyState(
        icon: Icons.search_off_outlined,
        title: 'Nadie coincide',
        message:
            'Ninguna persona con acceso se llama o se escribe como '
            '«${_buscador.text.trim()}».',
      );
    }

    return ListView.separated(
      itemCount: _visibles.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) => _Fila(
        miembro: _visibles[i],
        onTocar: () => _abrirPermisos(_visibles[i]),
      ),
    );
  }

  /// **Panel lateral, no diálogo centrado**, igual que en Áreas: deja ver la lista
  /// detrás, que es el contexto de lo que se está cambiando.
  Future<void> _abrirPermisos(MiembroDeEmpresa miembro) async {
    final catalogo = _catalogo;

    if (catalogo == null) {
      RisegFeedback.showError(
        context,
        'No se pudo cargar el catálogo de permisos. Vuelve a cargar la pantalla.',
      );
      return;
    }

    final cambio = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PanelDePermisos(
        miembro: miembro,
        catalogo: catalogo,
        empresaId: widget.empresaId,
        repositorio: widget.repositorio,
      ),
    );

    // SE RECARGA TODO, no sólo esa fila: `permissionCount` cambió, y el contador del
    // plan no —pero recargarlo de más cuesta una petición y evita dos caminos.
    if (cambio ?? false) await _cargar();
  }
}

// ===========================================================================
// Encabezado y las dos cifras
// ===========================================================================

class _Encabezado extends StatelessWidget {
  const _Encabezado({
    required this.personas,
    required this.capacidad,
    required this.falloDeCapacidad,
    required this.onReintentarCapacidad,
  });

  final int personas;
  final CapacidadDeAccesos? capacidad;
  final Failure? falloDeCapacidad;
  final VoidCallback? onReintentarCapacidad;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Usuarios', style: AppTypography.heading1),
        const SizedBox(height: AppSpacing.xxs),

        // CIFRA 1 — de ESTA empresa, contada de la lista que se está viendo.
        Text(
          personas == 1
              ? '1 persona con acceso a esta empresa'
              : '$personas personas con acceso a esta empresa',
          style: AppTypography.caption.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: AppSpacing.xxs),

        // CIFRA 2 — del PLAN, de toda la organización. En su propia línea, con sus
        // propias palabras, para que no se lean como una sola cosa.
        _LineaDelPlan(
          capacidad: capacidad,
          fallo: falloDeCapacidad,
          onReintentar: onReintentarCapacidad,
        ),
      ],
    );
  }
}

class _LineaDelPlan extends StatelessWidget {
  const _LineaDelPlan({
    required this.capacidad,
    required this.fallo,
    required this.onReintentar,
  });

  final CapacidadDeAccesos? capacidad;
  final Failure? fallo;
  final VoidCallback? onReintentar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // NO SE PUDO AVERIGUAR ≠ CERO. Se dice que no se pudo, y se ofrece reintentar.
    if (capacidad == null) {
      return Row(
        children: [
          Icon(Icons.help_outline, size: 14, color: colors.textMuted),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              fallo == null
                  ? 'No se pudo leer el uso de tu plan.'
                  : 'No se pudo leer el uso de tu plan: ${fallo!.message}',
              style: AppTypography.caption.copyWith(color: colors.textMuted),
            ),
          ),
          if (onReintentar != null) ...[
            const SizedBox(width: AppSpacing.xs),
            InkWell(
              onTap: onReintentar,
              child: Text(
                'Reintentar',
                style: AppTypography.caption.copyWith(
                  color: colors.accent,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      );
    }

    final c = capacidad!;
    final origen = c.origenDelTotal;

    return Row(
      children: [
        // SIN CUPO SE AVISA, pero no se bloquea nada: quien decide es el servidor.
        Icon(
          c.libres == 0 ? Icons.warning_amber_outlined : Icons.workspace_premium_outlined,
          size: 14,
          color: c.libres == 0 ? colors.warning : colors.textMuted,
        ),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(
            '${c.usados} de ${c.total} accesos de tu plan, en todas tus empresas'
            '${origen == null ? '' : ' ($origen)'}',
            style: AppTypography.caption.copyWith(
              color: c.libres == 0 ? colors.warning : colors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Una fila
// ===========================================================================

class _Fila extends StatelessWidget {
  const _Fila({required this.miembro, required this.onTocar});

  final MiembroDeEmpresa miembro;
  final VoidCallback onTocar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      onTap: onTocar,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.md,
          horizontal: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(miembro.nombreVisible, style: AppTypography.bodyStrong),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    miembro.correo,
                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),

            // QUÉ PUEDE HACER, DICHO EN PALABRAS. Antes decía «6 + su rol», que es
            // jerga: sólo se entiende sabiendo que los permisos de un Maestro no son
            // filas. Lo que una persona necesita leer es qué alcance tiene.
            Text(
              miembro.alcanceVisible,
              style: AppTypography.caption.copyWith(color: colors.textMuted),
            ),
            const SizedBox(width: AppSpacing.md),

            RisegStatusBadge(
              label: miembro.esMaestro ? 'Maestro' : 'Usuario',
              tone: miembro.esMaestro
                  ? RisegStatusTone.info
                  : RisegStatusTone.neutral,
              icon: miembro.esMaestro
                  ? Icons.shield_outlined
                  : Icons.person_outline,
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.chevron_right, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// El panel de permisos
// ===========================================================================

/// Los permisos de un **periodo de acceso**.
///
/// ## Se guarda la DIFERENCIA, no el conjunto
///
/// El servidor concede y retira de uno en uno —no hay ruta que reciba la lista
/// entera—, así que al guardar se mandan sólo los que cambiaron. Mandar los 103 cada
/// vez funcionaría, pero escribiría en la auditoría cien hechos que no pasaron.
///
/// ## Los seis protegidos van en su propio bloque
///
/// Sueldo, expediente sensible y portales de cliente. **Ni el Maestro los recibe por
/// su rol**, y se conceden uno por uno con su aviso, nunca de paquete. Mezclarlos con
/// los demás los volvería una casilla más entre cien, y es exactamente lo que no son.
///
/// Y el bloque **enseña una diferencia real que confunde a todo el mundo**: el PRIMER
/// Maestro de una empresa nace con los seis ya concedidos —se le dan al crear la
/// empresa—, mientras que un Maestro añadido después empieza sin ninguno. Verlos
/// marcados en uno y vacíos en otro es la única forma de entenderlo.
class _PanelDePermisos extends StatefulWidget {
  const _PanelDePermisos({
    required this.miembro,
    required this.catalogo,
    required this.empresaId,
    required this.repositorio,
  });

  final MiembroDeEmpresa miembro;
  final List<PermisoDeEmpresa> catalogo;
  final String empresaId;
  final UsuariosRepositorioHttp repositorio;

  @override
  State<_PanelDePermisos> createState() => _PanelDePermisosState();
}

class _PanelDePermisosState extends State<_PanelDePermisos> {
  /// Lo que el servidor dice que tiene **ahora**. Es la base de la diferencia.
  Set<String>? _original;

  /// Lo que la pantalla muestra marcado.
  Set<String> _marcados = {};

  Failure? _fallo;
  bool _cargando = true;
  bool _guardando = false;

  final _buscador = TextEditingController();

  /// Grupos cerrados. **Arranca vacío: todo abierto**, que es lo útil cuando se
  /// explora el catálogo por primera vez. Igual que en el escritorio.
  final _cerrados = <String>{};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _fallo = null;
    });

    final resultado = await widget.repositorio.permisosDe(
      widget.empresaId,
      widget.miembro.accesoId,
    );

    if (!mounted) return;

    resultado.when(
      ok: (p) => setState(() {
        _original = p;
        _marcados = Set.of(p);
        _cargando = false;
      }),
      failure: (f) => setState(() {
        _fallo = f;
        _cargando = false;
      }),
    );
  }

  /// Los seis protegidos, **sin filtrar por módulo y a propósito**.
  ///
  /// Sus módulos —Personal y Clientes— todavía no están mudados, así que por la regla
  /// general no deberían verse. **Se exceptúan**, y conviene decir por qué: este bloque
  /// existe precisamente para enseñar que el primer Maestro nace con los seis y que uno
  /// añadido después no los tiene. Esconderlo esconde lo único que casi nadie entiende
  /// a la primera.
  ///
  /// Y conceder uno ahora no hace daño: el módulo que lo lee sigue en el escritorio, y
  /// el permiso quedará esperándolo.
  List<PermisoDeEmpresa> get _protegidos =>
      widget.catalogo.where((p) => p.protegido).toList();

  /// Los ordinarios **de los módulos que ya están en la nube**.
  ///
  /// LA REGLA: los permisos de un módulo aparecen cuando ese módulo se muda. Mostrar
  /// hoy los 103 haría que un Maestro concediera `nomina.ver` y no pasara nada —el
  /// módulo que lo lee sigue en SQLite—, y una casilla que se marca sin surtir efecto
  /// es peor que una que no está: parece que el trabajo quedó hecho.
  ///
  /// **Qué está mudado se declara en un solo sitio**, `apartados_web.dart`, y se
  /// amplía un módulo por línea.
  List<PermisoDeEmpresa> get _ordinarios => widget.catalogo
      .where((p) => !p.protegido && apartados.permisosVisiblesDe(p.modulo))
      .toList();

  /// Cuántos del catálogo quedan fuera por tener su módulo en el escritorio.
  ///
  /// **Se dice en la pantalla.** Un panel que muestra 10 de 103 permisos sin explicar
  /// los otros 93 parece un catálogo incompleto, o un fallo.
  int get _ocultosPorModulo => widget.catalogo
      .where((p) => !p.protegido && !apartados.permisosVisiblesDe(p.modulo))
      .length;

  /// Los ordinarios agrupados por módulo, **en el orden en que vinieron**: el
  /// servidor los manda ordenados por módulo y código, y reordenar aquí sería
  /// duplicar una decisión ya tomada.
  Map<String?, List<PermisoDeEmpresa>> get _porModulo {
    final grupos = <String?, List<PermisoDeEmpresa>>{};

    for (final p in _ordinarios) {
      if (!_coincide(p)) continue;
      grupos.putIfAbsent(p.modulo, () => []).add(p);
    }

    return grupos;
  }

  bool _coincide(PermisoDeEmpresa p) {
    final texto = _buscador.text.trim().toLowerCase();
    if (texto.isEmpty) return true;

    return p.nombre.toLowerCase().contains(texto) ||
        p.codigo.toLowerCase().contains(texto) ||
        apartados.nombreDelGrupoDePermisos(p.modulo).toLowerCase().contains(texto);
  }

  /// ¿Este permiso lo tiene ya por ser Maestro, sin necesidad de concederlo?
  ///
  /// Un Maestro ejerce **todos los ordinarios por su rol** —eso lo resuelve el
  /// autorizador del servidor, no una fila—, así que su casilla se ve marcada y no se
  /// puede tocar. Los protegidos **no** entran aquí: ésos ni el Maestro los recibe.
  bool _incluidoPorRol(PermisoDeEmpresa p) =>
      widget.miembro.esMaestro && !p.protegido;

  /// Cómo se ve la casilla. **No es lo mismo que [_marcados]**, que son las filas
  /// concedidas de verdad y es lo único que viaja al guardar.
  bool _marcadoVisualmente(PermisoDeEmpresa p) =>
      _marcados.contains(p.codigo) || _incluidoPorRol(p);

  /// Lo que cambió, en las dos direcciones. **Vacío significa que no hay nada que
  /// guardar**, y entonces el botón no manda nada.
  (Set<String> conceder, Set<String> retirar) get _diferencia {
    final original = _original ?? const <String>{};

    return (
      _marcados.difference(original),
      original.difference(_marcados),
    );
  }

  bool get _hayCambios {
    final (conceder, retirar) = _diferencia;
    return conceder.isNotEmpty || retirar.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // MISMA FORMA QUE EL PANEL DE ÁREAS: pegado a la derecha, de alto completo, sobre
    // un fondo transparente. No se rediseña — si la web ya tiene un panel lateral, el
    // segundo se ve igual que el primero.
    //
    // **Más ancho que el de Áreas (520 contra 420)**, y por una razón medida: aquí
    // caben cien casillas con su nombre completo, y a 420 los nombres largos de
    // permiso se parten en tres líneas.
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: colors.surfaceSunken,
        child: SizedBox(
          width: 520,
          height: double.infinity,
          child: Column(
            children: [
              _CabeceraDelPanel(miembro: widget.miembro),
              // EL SCROLL VIVE DENTRO, para que el pie con Guardar quede siempre
              // visible: con cien permisos, un pie que se va con el scroll obliga a
              // bajar hasta el final para guardar.
              Expanded(child: _contenido()),
              _PieDelPanel(
                hayCambios: _hayCambios,
                guardando: _guardando,
                resumen: _resumenDeCambios(),
                onCancelar: () => Navigator.of(context).pop(false),
                onGuardar: _hayCambios && !_guardando ? _guardar : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _resumenDeCambios() {
    final (conceder, retirar) = _diferencia;
    if (conceder.isEmpty && retirar.isEmpty) return null;

    final partes = <String>[
      if (conceder.isNotEmpty) '${conceder.length} por conceder',
      if (retirar.isNotEmpty) '${retirar.length} por retirar',
    ];

    return partes.join(' · ');
  }

  Widget _contenido() {
    if (_cargando) return const Center(child: CircularProgressIndicator());

    if (_fallo case final f?) {
      return RisegEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudieron cargar sus permisos',
        message: f.message,
        primaryAction: RisegButton(label: 'Intentar de nuevo', onPressed: _cargar),
      );
    }

    final grupos = _porModulo;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      children: [
        RisegSearchField(
          hint: 'Buscar un permiso o un módulo',
          controller: _buscador,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.md),

        if (grupos.isEmpty && _buscador.text.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Text(
              'Ningún permiso coincide con «${_buscador.text.trim()}».',
              style: AppTypography.body.copyWith(color: context.colors.textMuted),
            ),
          ),

        for (final entrada in grupos.entries)
          _Grupo(
            titulo: apartados.nombreDelGrupoDePermisos(entrada.key),
            permisos: entrada.value,
            marcadoDe: _marcadoVisualmente,
            incluidoPorRol: _incluidoPorRol,
            cerrado: _cerrados.contains(entrada.key ?? _claveDelNucleo),
            onAbrirOCerrar: () => setState(() {
              final clave = entrada.key ?? _claveDelNucleo;
              if (!_cerrados.remove(clave)) _cerrados.add(clave);
            }),
            onAlternar: _alternar,
            onTodoElGrupo: (marcar) => setState(() {
              final codigos = entrada.value.map((p) => p.codigo);
              if (marcar) {
                _marcados.addAll(codigos);
              } else {
                _marcados.removeAll(codigos);
              }
            }),
          ),

        // LOS PROTEGIDOS, AL FINAL Y APARTE. No los filtra el buscador: son seis y
        // esconderlos por una búsqueda haría pensar que no existen.
        if (_protegidos.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _BloqueProtegidos(
            permisos: _protegidos,
            marcados: _marcados,
            esMaestro: widget.miembro.esMaestro,
            onAlternar: _alternar,
          ),
        ],

        // LOS 93 QUE NO SE VEN, DICHOS EN VOZ ALTA. Un panel con 10 permisos cuando
        // el producto tiene 103 parece un catálogo incompleto si nadie explica el
        // resto.
        if (_ocultosPorModulo > 0) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Hay $_ocultosPorModulo permisos más de módulos que todavía se usan '
            'desde la aplicación de escritorio. Van a aparecer aquí cuando cada '
            'módulo se mude a la web.',
            style: AppTypography.caption.copyWith(color: context.colors.textMuted),
          ),
        ],
      ],
    );
  }

  /// La clave con la que se recuerda el grupo del núcleo, que no tiene código de
  /// módulo. No viaja a ninguna parte: es sólo para el conjunto de cerrados.
  static const String _claveDelNucleo = '\u0000nucleo';

  void _alternar(String codigo, bool marcado) => setState(() {
    if (marcado) {
      _marcados.add(codigo);
    } else {
      _marcados.remove(codigo);
    }
  });

  /// Manda la diferencia, **de uno en uno y parando en el primer fallo**.
  ///
  /// NO SE SIGUE ADELANTE TRAS UN ERROR, y es deliberado: si el tercero falla por
  /// permiso o por suscripción, los siguientes fallarían igual y el usuario vería un
  /// montón de errores sobre la misma causa. Se para, se dice qué pasó, y **se
  /// recarga** — porque los dos primeros sí se aplicaron, y dejar la pantalla
  /// mostrando lo que se intentó sería mentirle.
  Future<void> _guardar() async {
    final (conceder, retirar) = _diferencia;

    setState(() => _guardando = true);

    for (final codigo in conceder) {
      final r = await widget.repositorio.conceder(
        empresaId: widget.empresaId,
        accesoId: widget.miembro.accesoId,
        permiso: codigo,
      );

      if (!mounted) return;
      if (r case Err(:final failure)) return _rendirse(failure);
    }

    for (final codigo in retirar) {
      final r = await widget.repositorio.retirar(
        empresaId: widget.empresaId,
        accesoId: widget.miembro.accesoId,
        permiso: codigo,
      );

      if (!mounted) return;
      if (r case Err(:final failure)) return _rendirse(failure);
    }

    if (!mounted) return;

    RisegFeedback.showSuccess(context, 'Permisos actualizados.');
    Navigator.of(context).pop(true);
  }

  void _rendirse(Failure fallo) {
    setState(() => _guardando = false);

    RisegFeedback.showError(context, fallo.message);

    // SE CIERRA DEVOLVIENDO «SÍ HUBO CAMBIO» aunque haya fallado a medias: parte se
    // aplicó, y la lista de fuera tiene que volver a leer lo que de verdad quedó.
    Navigator.of(context).pop(true);
  }
}

class _CabeceraDelPanel extends StatelessWidget {
  const _CabeceraDelPanel({required this.miembro});

  final MiembroDeEmpresa miembro;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(miembro.nombreVisible, style: AppTypography.heading2),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  miembro.correo,
                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                ),
                if (miembro.esMaestro) ...[
                  const SizedBox(height: AppSpacing.xs),
                  // AHORA LAS CASILLAS LO DICEN SOLAS —marcadas, en gris y con
                  // «Incluido por ser Maestro»—, así que esta línea ya no tiene que
                  // explicar lo que no se ve. Sólo señala qué SÍ se decide aquí.
                  Text(
                    'Esta persona administra la empresa. Lo que se decide uno por uno '
                    'son los permisos protegidos, abajo.',
                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(false),
            tooltip: 'Cerrar',
          ),
        ],
      ),
    );
  }
}

class _PieDelPanel extends StatelessWidget {
  const _PieDelPanel({
    required this.hayCambios,
    required this.guardando,
    required this.resumen,
    required this.onCancelar,
    required this.onGuardar,
  });

  final bool hayCambios;
  final bool guardando;
  final String? resumen;
  final VoidCallback onCancelar;
  final VoidCallback? onGuardar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: [
          // EL RESUMEN DE LO QUE SE VA A MANDAR, antes de mandarlo.
          Expanded(
            child: Text(
              resumen ?? 'Sin cambios',
              style: AppTypography.caption.copyWith(color: colors.textMuted),
            ),
          ),
          RisegButton(
            label: 'Cancelar',
            variant: RisegButtonVariant.secondary,
            onPressed: guardando ? null : onCancelar,
          ),
          const SizedBox(width: AppSpacing.sm),
          RisegButton(
            label: guardando ? 'Guardando…' : 'Guardar',
            onPressed: onGuardar,
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Un grupo de permisos
// ===========================================================================

class _Grupo extends StatelessWidget {
  const _Grupo({
    required this.titulo,
    required this.permisos,
    required this.marcadoDe,
    required this.incluidoPorRol,
    required this.cerrado,
    required this.onAbrirOCerrar,
    required this.onAlternar,
    required this.onTodoElGrupo,
  });

  final String titulo;
  final List<PermisoDeEmpresa> permisos;

  /// Cómo se ve la casilla. **No es «está en la lista de concedidos»**: un Maestro los
  /// tiene por su rol y se ven marcados sin ser filas.
  final bool Function(PermisoDeEmpresa) marcadoDe;

  /// ¿Lo tiene por su rol, y por tanto no se puede tocar?
  final bool Function(PermisoDeEmpresa) incluidoPorRol;

  final bool cerrado;
  final VoidCallback onAbrirOCerrar;
  final void Function(String codigo, bool marcado) onAlternar;
  final ValueChanged<bool> onTodoElGrupo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final puestos = permisos.where(marcadoDe).length;
    final todos = puestos == permisos.length;

    // SI TODO EL GRUPO LO DA EL ROL, NO HAY NADA QUE MARCAR. «Marcar todo» sobre un
    // grupo entero deshabilitado sería un botón que no hace nada.
    final sePuedeTocar = permisos.any((p) => !incluidoPorRol(p));

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onAbrirOCerrar,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Icon(
                    cerrado ? Icons.expand_more : Icons.expand_less,
                    size: 20,
                    color: colors.textMuted,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Expanded(child: Text(titulo, style: AppTypography.bodyStrong)),
                  // EL CONTADOR DEL GRUPO: cuántos de cuántos, sin abrirlo.
                  Text(
                    '$puestos/${permisos.length}',
                    style: AppTypography.caption.copyWith(
                      color: colors.textMuted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (sePuedeTocar) ...[
                    const SizedBox(width: AppSpacing.sm),
                    TextButton(
                      onPressed: () => onTodoElGrupo(!todos),
                      child: Text(todos ? 'Quitar todo' : 'Marcar todo'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!cerrado)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final p in permisos)
                    RisegCheckbox(
                      label: p.nombre,
                      value: marcadoDe(p),
                      // MARCADA Y DESHABILITADA, CON SU RAZÓN AL LADO. Un Maestro ya
                      // los ejerce por su rol, así que desmarcarlos no haría nada: una
                      // casilla que acepta el clic y no cambia nada parece un fallo.
                      enabled: !incluidoPorRol(p),
                      nota: incluidoPorRol(p) ? 'Incluido por ser Maestro' : null,
                      onChanged: (v) => onAlternar(p.codigo, v),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Los seis protegidos
// ===========================================================================

class _BloqueProtegidos extends StatelessWidget {
  const _BloqueProtegidos({
    required this.permisos,
    required this.marcados,
    required this.esMaestro,
    required this.onAlternar,
  });

  final List<PermisoDeEmpresa> permisos;
  final Set<String> marcados;
  final bool esMaestro;
  final void Function(String codigo, bool marcado) onAlternar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final puestos = permisos.where((p) => marcados.contains(p.codigo)).length;

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline, size: 18, color: colors.warning),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text('Permisos protegidos', style: AppTypography.bodyStrong),
              ),
              Text(
                '$puestos/${permisos.length}',
                style: AppTypography.caption.copyWith(
                  color: colors.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            // NO HAY «MARCAR TODO» AQUÍ, Y ES LA DECISIÓN DEL BLOQUE. Un botón que los
            // conceda de golpe convertiría seis decisiones deliberadas en un clic.
            'Sueldos, expediente sensible y accesos a portales de cliente. '
            '${esMaestro ? 'Ni un Maestro los recibe por su rol' : 'No se conceden por plantilla'}: '
            'se marcan uno por uno, a conciencia. No hay «marcar todo».',
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
          if (esMaestro && puestos == 0) ...[
            const SizedBox(height: AppSpacing.xs),
            // ESTO ES LO QUE CONFUNDE A TODO EL MUNDO, y se explica donde se ve.
            Text(
              'Este Maestro no los tiene. El primer Maestro de la empresa nace con '
              'los seis concedidos; uno añadido después empieza sin ninguno.',
              style: AppTypography.caption.copyWith(color: colors.warning),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          for (final p in permisos)
            RisegCheckbox(
              label: p.nombre,
              value: marcados.contains(p.codigo),
              onChanged: (v) => onAlternar(p.codigo, v),
            ),
        ],
      ),
    );
  }
}

