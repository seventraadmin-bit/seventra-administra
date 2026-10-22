import 'package:flutter/material.dart';

import '../../../../core/company/autoridad_de_organizacion.dart';
import '../../../../core/company/logotipos_de_empresa.dart';
import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../usuarios/web/tarjeta_de_empresa.dart';
import '../datos/empresas_repositorio_http.dart';
import '../modelos/empresa_administrada.dart';

/// E2 · **Administración de empresas** de la Organization.
///
/// ## Para quién es, y por qué no es una pestaña del menú
///
/// Esta pantalla pide la autoridad de **Organization** —Owner, o Admin con
/// `companies.manage`—, que es otro plano que los permisos de Company con los que se
/// gobiernan las demás pestañas. El registro de apartados sólo entiende permisos de
/// Company, así que enseñarla desde ahí habría exigido enseñarle un segundo sistema de
/// autoridad. Vive **dentro** de Organización › Empresa, junto a la ficha.
///
/// **Un Maestro que no sea miembro de la Organization no la ve.** Administra *su*
/// empresa; no da de alta empresas nuevas.
///
/// ## Los cuatro verbos, y uno no es un borrado
///
/// Crear · Desactivar · Reactivar · **Descartar**. El borrado físico **no existe**: una
/// empresa descartada se queda en la base con su estado y desaparece de todas las
/// listas, porque su propia traza de auditoría la retiene — y conservarla es el punto.
///
/// 🚫 **Descartar no se revierte desde aquí**, y el diálogo lo dice antes de pedir el
/// nombre escrito. Recuperarla será cosa de SEVENTRA.
class EmpresasAdministracionScreen extends StatefulWidget {
  const EmpresasAdministracionScreen({
    required this.repositorio,
    required this.logotipos,
    required this.organizationId,
    required this.autoridad,
    required this.empresaActivaId,
    this.alCambiarLaLista,
    super.key,
  });

  final EmpresasRepositorioHttp repositorio;
  final LogotiposDeEmpresa logotipos;
  final String organizationId;

  /// Qué puede hacer esta persona. **Se recibe ya resuelta**: quien monta esta pantalla
  /// ya decidió que debe existir, y preguntarlo otra vez aquí daría dos respuestas.
  final AutoridadDeOrganizacion autoridad;

  /// La empresa en la que se está trabajando, para marcarla y para **no ofrecer
  /// desactivarla**: dejarse fuera a uno mismo de un clic no es una decisión, es un
  /// accidente.
  final String empresaActivaId;

  /// Para que el marco pueda refrescar su menú de empresas cuando esta pantalla cambia
  /// alguna. **No se recarga desde aquí**: la lista del marco tiene un dueño.
  final VoidCallback? alCambiarLaLista;

  @override
  State<EmpresasAdministracionScreen> createState() =>
      _EmpresasAdministracionScreenState();
}

class _EmpresasAdministracionScreenState
    extends State<EmpresasAdministracionScreen> {
  List<EmpresaAdministrada> _empresas = const [];
  Failure? _fallo;
  bool _cargando = true;

  /// Cuál está en medio de una operación. Es el id y no un `bool` porque hay que señalar
  /// **esa** fila mientras las demás se apagan.
  String? _ocupada;

  /// Si se enseñan las inactivas. **Ocultas por omisión**: en el caso normal son ruido.
  bool _conInactivas = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _fallo = null;
    });

    final leida = await widget.repositorio.listar(widget.organizationId);

    if (!mounted) return;

    setState(() {
      _cargando = false;

      leida.when(
        ok: (lista) => _empresas = lista,
        failure: (f) => _fallo = f,
      );
    });
  }

  List<EmpresaAdministrada> get _visibles => [
    for (final e in _empresas)
      if (_conInactivas || e.estaActiva) e,
  ];

  int get _activas => _empresas.where((e) => e.estaActiva).length;

  /// Ejecuta una operación y refresca. **Un solo sitio** para el patrón, porque los
  /// cuatro verbos comparten exactamente el mismo: apagar la fila, pedir, decir qué
  /// pasó, recargar y avisar al marco.
  Future<void> _operar({
    required String? companyId,
    required Future<Result<void>> Function() operacion,
    required String exito,
  }) async {
    setState(() => _ocupada = companyId ?? '—');

    final resultado = await operacion();

    if (!mounted) return;

    setState(() => _ocupada = null);

    await resultado.when(
      ok: (_) async {
        RisegFeedback.showSuccess(context, exito);

        await _cargar();

        // EL MENÚ DE LA BARRA TAMBIÉN CAMBIA: una empresa desactivada o descartada
        // desaparece de él, y una nueva aparece. Sin este aviso, la barra seguiría
        // ofreciendo entrar a una empresa que ya no admite a nadie.
        widget.alCambiarLaLista?.call();
      },
      failure: (f) async => RisegFeedback.showError(context, _humano(f)),
    );
  }

  /// El fallo, en palabras. **Los códigos se distinguen aquí y no en el mensaje del
  /// servidor**: cada uno tiene un arreglo distinto, y el de capacidad llega con cifras
  /// que conviene no reescribir.
  String _humano(Failure fallo) {
    if (fallo is! ApiHttpFailure) return fallo.message;

    return switch (fallo.codigo) {
      EmpresasRepositorioHttp.codigoUltimaActiva =>
        'Es la única empresa activa: activa o crea otra antes.',

      EmpresasRepositorioHttp.codigoSinCambio =>
        'Esa empresa ya estaba así. Vuelve a cargar la lista.',

      EmpresasRepositorioHttp.codigoConDatos =>
        'Esa empresa ya tiene datos registrados, así que no se puede descartar. '
            'Desactívala si ya no opera.',

      EmpresasRepositorioHttp.codigoDescartada =>
        'Esa empresa está descartada y desde aquí no se puede recuperar.',

      EmpresasRepositorioHttp.codigoSinAutoridad =>
        'No tienes autoridad para esta operación.',

      // LA DE CAPACIDAD SE PASA TAL CUAL: el servidor manda las dos cifras —«tu plan
      // permite 5 empresas y quedarían 6»— y reescribirla las perdería.
      _ => fallo.message,
    };
  }

  // =========================================================================
  // Los cuatro verbos
  // =========================================================================

  Future<void> _crear() async {
    final datos = await _pedirAlta(context);
    if (datos == null || !mounted) return;

    final nombre = datos.nombre.trim();

    // SIN NOMBRE NO SE MANDA NADA. El servidor lo rechazaría con un 422, y gastar un
    // viaje para que conteste lo que la pantalla ya sabe es ruido.
    if (nombre.isEmpty) {
      RisegFeedback.showError(context, 'Hace falta el nombre comercial.');
      return;
    }

    await _operar(
      companyId: null,
      operacion: () => widget.repositorio.crear(
        organizationId: widget.organizationId,
        nombre: nombre,
        razonSocial: datos.razonSocial,
      ),
      exito: 'Empresa «$nombre» creada. Ya puedes entrar en ella.',
    );
  }

  Future<void> _desactivar(EmpresaAdministrada empresa) async {
    final escrito = await _pedirMotivo(
      context,
      titulo: 'Desactivar ${empresa.nombre}',
      cuerpo:
          'Deja de operar y desaparece de «Elige una empresa» y del menú de la barra. '
          '${_quienQuedaFuera(empresa)}\n\n'
          'Se puede reactivar después, y conserva su equipo y sus datos.',
      accion: 'Desactivar',
    );

    if (escrito == null || !mounted) return;

    final motivo = escrito.motivo.trim();

    if (motivo.isEmpty) {
      RisegFeedback.showError(
        context,
        'Hace falta el motivo: no se desactivó nada.',
      );
      return;
    }

    await _operar(
      companyId: empresa.companyId,
      operacion: () => widget.repositorio.desactivar(
        organizationId: widget.organizationId,
        companyId: empresa.companyId,
        motivo: motivo,
      ),
      exito: '${empresa.nombre} quedó desactivada.',
    );
  }

  Future<void> _reactivar(EmpresaAdministrada empresa) => _operar(
    companyId: empresa.companyId,
    operacion: () => widget.repositorio.reactivar(
      organizationId: widget.organizationId,
      companyId: empresa.companyId,
    ),
    exito: '${empresa.nombre} vuelve a operar.',
  );

  Future<void> _descartar(EmpresaAdministrada empresa) async {
    final escrito = await _pedirMotivo(
      context,
      titulo: 'Descartar ${empresa.nombre}',
      cuerpo:
          'Para las empresas creadas por error. Desaparece de TODAS las listas, '
          'incluida ésta, y libera su lugar en el plan.\n\n'
          '⚠️ Desde Administra esto NO se puede deshacer: recuperarla tendría que '
          'hacerlo SEVENTRA.\n\n'
          'Sólo funciona si la empresa no tiene ningún dato registrado.',
      accion: 'Descartar',
      // LA CONFIRMACIÓN ESCRIBIENDO EL NOMBRE, y sólo aquí: es la defensa contra el
      // clic equivocado en lo único que no se deshace desde Administra.
      nombreAEscribir: empresa.nombre,
    );

    if (escrito == null || !mounted) return;

    final motivo = escrito.motivo.trim();

    if (motivo.isEmpty) {
      RisegFeedback.showError(context, 'Hace falta el motivo: no se descartó nada.');
      return;
    }

    // EL NOMBRE SE COMPARA EXACTO —con los extremos recortados, no el de dentro—: lo
    // que se busca es que la persona LO LEA y lo copie, no castigarla por un espacio
    // final. Y si no coincide **no se descarta nada y se dice**, en vez de cerrarse en
    // silencio: un diálogo que se cierra sin hacer nada parece que hizo algo.
    if (escrito.confirmacion.trim() != empresa.nombre.trim()) {
      RisegFeedback.showError(
        context,
        'El nombre no coincide: no se descartó nada.',
      );
      return;
    }

    await _operar(
      companyId: empresa.companyId,
      operacion: () => widget.repositorio.descartar(
        organizationId: widget.organizationId,
        companyId: empresa.companyId,
        motivo: motivo,
      ),
      exito: '${empresa.nombre} quedó descartada.',
    );
  }

  String _quienQuedaFuera(EmpresaAdministrada empresa) => switch (empresa.accesos) {
    0 => 'Nadie tiene acceso a ella ahora mismo.',
    1 => 'Una persona con acceso dejará de poder entrar.',
    final n => '$n personas con acceso dejarán de poder entrar.',
  };

  // =========================================================================
  // Pintar
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    final fallo = _fallo;

    if (fallo != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_humano(fallo), textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              RisegButton(label: 'Volver a intentar', onPressed: _cargar),
            ],
          ),
        ),
      );
    }

    final colors = context.colors;
    final inactivas = _empresas.length - _activas;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: RisegSectionHeader(
                  title: 'Empresas',
                  description:
                      '$_activas ${_activas == 1 ? 'activa' : 'activas'}'
                      '${inactivas == 0 ? '' : ' · $inactivas inactiva${inactivas == 1 ? '' : 's'}'}',
                ),
              ),
              RisegButton(
                key: const Key('admin_empresas_nueva'),
                label: 'Nueva empresa',
                onPressed: _ocupada == null ? _crear : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // LA CASILLA SÓLO SI HAY ALGO QUE ENSEÑAR: con cero inactivas, una casilla
          // que no cambia nada ocupa espacio y no dice nada.
          if (inactivas > 0)
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    key: const Key('admin_empresas_ver_inactivas'),
                    value: _conInactivas,
                    onChanged: (v) => setState(() => _conInactivas = v ?? false),
                  ),
                  Text(
                    'Mostrar las inactivas',
                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),

          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: ListView.separated(
              itemCount: _visibles.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, i) {
                final empresa = _visibles[i];

                return _Fila(
                  key: Key('admin_empresa_${empresa.companyId}'),
                  empresa: empresa,
                  logotipos: widget.logotipos,
                  esLaActiva: empresa.companyId == widget.empresaActivaId,
                  puedeDescartar: widget.autoridad.puedeEliminarEmpresas,
                  ocupada: _ocupada == empresa.companyId,
                  apagada: _ocupada != null && _ocupada != empresa.companyId,
                  alDesactivar: () => _desactivar(empresa),
                  alReactivar: () => _reactivar(empresa),
                  alDescartar: () => _descartar(empresa),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Una empresa en la lista de administración.
class _Fila extends StatelessWidget {
  const _Fila({
    required this.empresa,
    required this.logotipos,
    required this.esLaActiva,
    required this.puedeDescartar,
    required this.ocupada,
    required this.apagada,
    required this.alDesactivar,
    required this.alReactivar,
    required this.alDescartar,
    super.key,
  });

  final EmpresaAdministrada empresa;
  final LogotiposDeEmpresa logotipos;
  final bool esLaActiva;
  final bool puedeDescartar;
  final bool ocupada;
  final bool apagada;
  final VoidCallback alDesactivar;
  final VoidCallback alReactivar;
  final VoidCallback alDescartar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Opacity(
      opacity: apagada ? 0.5 : 1,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: esLaActiva ? colors.accent : colors.borderSubtle,
            width: esLaActiva ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            RecuadroDeLogotipo(
              companyId: empresa.companyId,
              nombre: empresa.nombre,
              logotipos: logotipos,
              lado: 40,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    empresa.nombre,
                    style: AppTypography.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // LA RAZÓN SOCIAL SE OMITE CUANDO NO HAY, igual que en la tarjeta de
                  // «Elige una empresa»: ausencia nunca es cero.
                  if (empresa.razonSocial != null)
                    Text(
                      empresa.razonSocial!,
                      style: AppTypography.caption.copyWith(color: colors.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    empresa.accesos == 1
                        ? '1 persona con acceso'
                        : '${empresa.accesos} personas con acceso',
                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),

            if (esLaActiva) ...[
              const RisegStatusBadge(
                label: 'Abierta',
                tone: RisegStatusTone.success,
                icon: Icons.check_circle_outline,
              ),
              const SizedBox(width: AppSpacing.xs),
            ],

            if (!empresa.estaActiva) ...[
              const RisegStatusBadge(
                label: 'Inactiva',
                tone: RisegStatusTone.neutral,
                icon: Icons.pause_circle_outline,
              ),
              const SizedBox(width: AppSpacing.xs),
            ],

            if (ocupada)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            else
              _Menu(
                empresa: empresa,
                esLaActiva: esLaActiva,
                puedeDescartar: puedeDescartar,
                habilitado: !apagada,
                alDesactivar: alDesactivar,
                alReactivar: alReactivar,
                alDescartar: alDescartar,
              ),
          ],
        ),
      ),
    );
  }
}

/// El menú de la fila: **sólo lo que aplica**, y cuando algo no aplica se dice por qué.
///
/// Un elemento deshabilitado sin explicación obliga a adivinar; uno ausente obliga a
/// buscarlo. Con el motivo escrito, ni una cosa ni la otra.
class _Menu extends StatelessWidget {
  const _Menu({
    required this.empresa,
    required this.esLaActiva,
    required this.puedeDescartar,
    required this.habilitado,
    required this.alDesactivar,
    required this.alReactivar,
    required this.alDescartar,
  });

  final EmpresaAdministrada empresa;
  final bool esLaActiva;
  final bool puedeDescartar;
  final bool habilitado;
  final VoidCallback alDesactivar;
  final VoidCallback alReactivar;
  final VoidCallback alDescartar;

  @override
  Widget build(BuildContext context) => PopupMenuButton<VoidCallback>(
    key: Key('admin_menu_${empresa.companyId}'),
    enabled: habilitado,
    tooltip: 'Más acciones',
    icon: const Icon(Icons.more_vert),
    onSelected: (accion) => accion(),
    itemBuilder: (_) => [
      if (empresa.estaActiva)
        PopupMenuItem<VoidCallback>(
          value: alDesactivar,
          // LA EMPRESA EN LA QUE SE ESTÁ TRABAJANDO NO SE OFRECE DESACTIVAR: dejarse
          // fuera a uno mismo de un clic no es una decisión, es un accidente. Y el
          // servidor tampoco lo impide, así que la defensa es ésta.
          enabled: !esLaActiva,
          child: Text(
            esLaActiva
                ? 'Desactivar — cambia de empresa primero'
                : 'Desactivar',
          ),
        )
      else
        PopupMenuItem<VoidCallback>(
          value: alReactivar,
          child: const Text('Reactivar'),
        ),

      // DESCARTAR SÓLO PARA EL OWNER. Si no puede, no aparece: un elemento que siempre
      // responde «no tienes autoridad» es ruido.
      if (puedeDescartar)
        PopupMenuItem<VoidCallback>(
          value: alDescartar,
          enabled: !esLaActiva,
          child: Text(
            esLaActiva
                ? 'Descartar — cambia de empresa primero'
                : 'Descartar…',
          ),
        ),
    ],
  );
}

/// Lo que se escribe en un diálogo, **mutable y compartido** con `onConfirm`.
///
/// Es la forma que ya usa `dialogo_de_choque.dart`: `RisegDialog.showForm` construye el
/// marco —título, botones, foco atrapado y el cierre completo de la ruta— y el contenido
/// escribe aquí. Montar un `AlertDialog` propio habría dejado esta pantalla fuera de
/// todo eso, que es justo lo que `RisegDialog` existe para no repetir.
class _LoEscrito {
  String nombre = '';
  String razonSocial = '';
  String motivo = '';
  String confirmacion = '';
}

/// El alta: nombre comercial y, si se quiere, razón social.
Future<_LoEscrito?> _pedirAlta(BuildContext context) {
  final escrito = _LoEscrito();

  return RisegDialog.showForm<_LoEscrito>(
    context: context,
    title: 'Nueva empresa',
    confirmLabel: 'Crear',
    cancelLabel: 'Cancelar',
    contentBuilder: (_) => _FormularioDeAlta(escrito: escrito),
    onConfirm: () async => escrito,
  );
}

class _FormularioDeAlta extends StatefulWidget {
  const _FormularioDeAlta({required this.escrito});

  final _LoEscrito escrito;

  @override
  State<_FormularioDeAlta> createState() => _FormularioDeAltaState();
}

class _FormularioDeAltaState extends State<_FormularioDeAlta> {
  final _nombre = TextEditingController();
  final _razonSocial = TextEditingController();

  @override
  void dispose() {
    // LIBERAR LOS CONTROLLERS NO ES OPCIONAL. En este proyecto ya costó una vez, y
    // `Future.delayed(300ms)` para «esperar la animación» está PROHIBIDO.
    _nombre.dispose();
    _razonSocial.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 420,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RisegTextField(
          key: const Key('alta_nombre'),
          label: 'Nombre comercial',
          controller: _nombre,
          autofocus: true,
          onChanged: (v) => widget.escrito.nombre = v,
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          key: const Key('alta_razon_social'),
          label: 'Razón social (opcional)',
          controller: _razonSocial,
          onChanged: (v) => widget.escrito.razonSocial = v,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          // SE DICE QUIÉN SERÁ EL MAESTRO, porque lo decide el servidor y no la
          // pantalla: elegir a otra persona exigiría resolver su identidad, y
          // Administra no tiene ninguna ruta que convierta un correo en identidad.
          'Tú serás su Maestro. Después puedes dar acceso a otras personas desde '
          'Configuración › Usuarios.',
          style: AppTypography.caption.copyWith(color: context.colors.textMuted),
        ),
      ],
    ),
  );
}

/// El motivo, y para descartar también el nombre escrito.
Future<_LoEscrito?> _pedirMotivo(
  BuildContext context, {
  required String titulo,
  required String cuerpo,
  required String accion,
  String? nombreAEscribir,
}) {
  final escrito = _LoEscrito();

  return RisegDialog.showForm<_LoEscrito>(
    context: context,
    title: titulo,
    confirmLabel: accion,
    cancelLabel: 'Cancelar',
    // DESTRUCTIVO SÓLO CUANDO PIDE EL NOMBRE, o sea al descartar: desactivar se
    // deshace, y pintarlo en rojo igualaría dos cosas que no son iguales.
    destructive: nombreAEscribir != null,
    contentBuilder: (_) => _FormularioDeMotivo(
      escrito: escrito,
      cuerpo: cuerpo,
      nombreAEscribir: nombreAEscribir,
    ),
    onConfirm: () async => escrito,
  );
}

class _FormularioDeMotivo extends StatefulWidget {
  const _FormularioDeMotivo({
    required this.escrito,
    required this.cuerpo,
    this.nombreAEscribir,
  });

  final _LoEscrito escrito;
  final String cuerpo;
  final String? nombreAEscribir;

  @override
  State<_FormularioDeMotivo> createState() => _FormularioDeMotivoState();
}

class _FormularioDeMotivoState extends State<_FormularioDeMotivo> {
  final _motivo = TextEditingController();
  final _confirmacion = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    _confirmacion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.cuerpo, style: AppTypography.body),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(
            key: const Key('motivo'),
            label: 'Motivo',
            controller: _motivo,
            autofocus: true,
            onChanged: (v) => widget.escrito.motivo = v,
          ),
          Text(
            'Queda en la auditoría, con tu nombre y la fecha.',
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
          if (widget.nombreAEscribir != null) ...[
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              key: const Key('nombre_a_escribir'),
              label: 'Escribe «${widget.nombreAEscribir}» para confirmar',
              controller: _confirmacion,
              onChanged: (v) => widget.escrito.confirmacion = v,
            ),
          ],
        ],
      ),
    );
  }
}
