import 'package:flutter/material.dart';

// LAS CAPACIDADES VIENEN DEL SHELL: esta feature no importa el catálogo de permisos.
import '../../../../app/shell/apartados_web.dart' show CapacidadesDeModulo;
import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/mensajes_humanos.dart';
import '../../../../core/trabajo_sin_guardar/declara_su_trabajo_sin_guardar.dart';
import '../../../../core/trabajo_sin_guardar/guardia_de_salida.dart';
import '../datos/condiciones_repositorio_http.dart';
import '../modelos/condicion_comercial.dart';

/// Modalidades de turno: el catálogo con el que la empresa describe **cómo se cubre una
/// plaza**.
///
/// ## Por qué esta pantalla no existía, y qué costó
///
/// 🚫 **La ruta del servidor y el método del repositorio existían desde C3; la pantalla
/// no.** Los otros dos catálogos de la familia —tipos de servicio y tipos de sucursal— sí
/// la tenían, y el tercero se quedó sin ella sin que nadie lo decidiera. El dueño lo
/// encontró el **18 de noviembre de 2026** probando el ensayo: «Modalidad de turno» sólo
/// ofrecía «Sin modalidad», su empresa no tenía ni una fila, y **no había forma de dárselas
/// desde la aplicación**.
///
/// Desde la 0066 una empresa nueva **nace con las nueve recomendadas**, así que este botón
/// ya no es la única puerta — pero sigue hecho falta para recuperar lo que alguien borró y,
/// sobre todo, **para corregir el catálogo**: su explicación, si pide periodo y cómo se
/// captura su horario son datos de la empresa, no del código.
///
/// ## Las tres preguntas de una modalidad
///
/// | | |
/// |---|---|
/// | **Su explicación** | lo que se lee al elegirla, **con cuántas personas hacen falta para cubrir 24/7** |
/// | **¿Pide periodo?** | si la plaza es fija de día o de noche, y entonces hay que decir cuál |
/// | **¿Cómo se captura su horario?** | una sola **hora de cambio** —los turnos que rotan— o la **rejilla semanal** |
class ModalidadesDeTurnoWebScreen extends StatefulWidget {
  const ModalidadesDeTurnoWebScreen({
    required this.repositorio,
    required this.empresaId,
    required this.capacidades,
    required this.guardia,
    this.onVolver,
    super.key,
  });

  final CondicionesRepositorioHttp repositorio;
  final String empresaId;

  /// Dónde se registra que hay trabajo sin guardar (D-56). **Esta pantalla no lo usa: lo
  /// pasa** a su panel de alta y edición, que es el que tiene campos.
  final GuardiaDeSalida guardia;

  /// **El catálogo de un módulo usa el permiso de su módulo**: `/shift-modalities` exige
  /// `clients_services.read` para leer y `clients_services.manage` para escribir.
  final CapacidadesDeModulo capacidades;

  final VoidCallback? onVolver;

  @override
  State<ModalidadesDeTurnoWebScreen> createState() =>
      _ModalidadesDeTurnoWebScreenState();
}

class _ModalidadesDeTurnoWebScreenState extends State<ModalidadesDeTurnoWebScreen> {
  List<ModalidadDeTurno>? _modalidades;
  Failure? _fallo;
  bool _cargando = true;
  bool _agregandoRecomendadas = false;

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

    final resultado = await widget.repositorio.modalidades(widget.empresaId);

    if (!mounted) return;

    resultado.when(
      ok: (lista) => setState(() {
        _modalidades = lista;
        _cargando = false;
      }),
      failure: (f) => setState(() {
        _fallo = f;
        _cargando = false;
      }),
    );
  }

  /// Agrega las recomendadas que falten. **Es idempotente**: el servidor salta las que ya
  /// existen **por código**, así que pulsarlo dos veces no duplica nada y la segunda crea
  /// cero — que es un resultado distinto de un error y se dice distinto.
  Future<void> _agregarRecomendadas() async {
    final antes = _modalidades?.length ?? 0;

    setState(() => _agregandoRecomendadas = true);

    final resultado = await widget.repositorio.agregarModalidadesRecomendadas(
      widget.empresaId,
    );

    if (!mounted) return;

    resultado.when(
      ok: (catalogo) {
        setState(() {
          _modalidades = catalogo;
          _agregandoRecomendadas = false;
        });

        final creadas = catalogo.length - antes;

        RisegFeedback.showSuccess(
          context,
          creadas == 0
              ? 'Ya estaban todas: no se agregó ninguna.'
              : 'Se agregaron $creadas.',
        );
      },
      failure: (f) {
        setState(() => _agregandoRecomendadas = false);
        RisegFeedback.showError(context, MensajesHumanos.deMutacion(f));
      },
    );
  }

  Future<void> _editar(ModalidadDeTurno? modalidad) async {
    final guardada = await mostrarPanelDeModalidad(
      context,
      repositorio: widget.repositorio,
      empresaId: widget.empresaId,
      guardia: widget.guardia,
      existente: modalidad,
    );

    if (guardada == null || !mounted) return;

    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final total = _modalidades?.length ?? 0;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.onVolver case final volver?) ...[
                // EL REGRESO VA ARRIBA Y A LA IZQUIERDA, igual que en los otros dos
                // catálogos: no es una pestaña, así que sin esto no habría forma de salir.
                InkWell(
                  onTap: volver,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back, size: 16, color: colors.accent),
                        const SizedBox(width: AppSpacing.xxs),
                        Text(
                          'Servicios',
                          style: AppTypography.caption.copyWith(color: colors.accent),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Modalidades de turno',
                          style: AppTypography.heading1,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          total == 1 ? '1 modalidad' : '$total modalidades',
                          style: AppTypography.caption.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.capacidades.puedeCrear) ...[
                    RisegButton(
                      key: const Key('modalidades-recomendadas'),
                      label: 'Agregar las recomendadas',
                      variant: RisegButtonVariant.secondary,
                      icon: Icons.auto_awesome_outlined,
                      loading: _agregandoRecomendadas,
                      onPressed: _cargando ? null : _agregarRecomendadas,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    RisegButton(
                      key: const Key('modalidades-nueva'),
                      label: 'Nueva modalidad',
                      icon: Icons.add,
                      onPressed: _cargando ? null : () => _editar(null),
                    ),
                  ],
                ],
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

    if (_fallo case final fallo?) {
      return RisegEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudo leer el catálogo',
        message: MensajesHumanos.deMutacion(fallo),
        primaryAction: RisegButton(label: 'Intentar de nuevo', onPressed: _cargar),
      );
    }

    final lista = _modalidades ?? const <ModalidadDeTurno>[];

    if (lista.isEmpty) {
      return RisegEmptyState(
        icon: Icons.schedule_outlined,
        title: 'Todavía no hay modalidades',
        // 🚫 Y SE DICE QUÉ SE ROMPE SIN ELLAS, que es lo que el dueño vivió: sin una
        // modalidad no se puede capturar una condición comercial.
        message:
            'Sin una modalidad no se puede capturar una condición comercial. Lo más '
            'rápido es agregar las recomendadas y corregir lo que no cuadre.',
        primaryAction: widget.capacidades.puedeCrear
            ? RisegButton(
                label: 'Agregar las recomendadas',
                icon: Icons.auto_awesome_outlined,
                loading: _agregandoRecomendadas,
                onPressed: _agregarRecomendadas,
              )
            : null,
      );
    }

    return ListView.separated(
      itemCount: lista.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, i) => _FilaDeModalidad(
        modalidad: lista[i],
        puedeModificar: widget.capacidades.puedeModificar,
        alEditar: () => _editar(lista[i]),
      ),
    );
  }
}

/// Una modalidad en la lista, con **las tres respuestas a la vista**.
class _FilaDeModalidad extends StatelessWidget {
  const _FilaDeModalidad({
    required this.modalidad,
    required this.puedeModificar,
    required this.alEditar,
  });

  final ModalidadDeTurno modalidad;
  final bool puedeModificar;
  final VoidCallback alEditar;

  @override
  Widget build(BuildContext context) => RisegCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(modalidad.nombre, style: AppTypography.bodyStrong),
                  const SizedBox(width: AppSpacing.sm),
                  RisegStatusBadge(
                    label: modalidad.estaActiva ? 'Activa' : 'Inactiva',
                    tone: modalidad.estaActiva
                        ? RisegStatusTone.success
                        : RisegStatusTone.neutral,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                modalidad.codigo,
                style: AppTypography.caption.copyWith(
                  color: context.colors.textMuted,
                ),
              ),
              if (modalidad.explicacion case final texto?) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(texto, style: AppTypography.body),
              ],
              const SizedBox(height: AppSpacing.xs),
              Text(
                [
                  _comoSeCaptura(modalidad),
                  if (modalidad.pidePeriodo) 'La plaza es diurna o nocturna',
                ].join(' · '),
                style: AppTypography.caption.copyWith(
                  color: context.colors.textMuted,
                ),
              ),
            ],
          ),
        ),
        if (puedeModificar)
          RisegButton(
            key: Key('modalidad-editar-${modalidad.id}'),
            label: 'Editar',
            icon: Icons.edit_outlined,
            variant: RisegButtonVariant.ghost,
            size: RisegButtonSize.compact,
            onPressed: alEditar,
          ),
      ],
    ),
  );

  /// La frase de cómo se captura su horario, **con las horas cuando se conocen**.
  static String _comoSeCaptura(ModalidadDeTurno m) => switch (m.capturaDelHorario) {
    CapturaDelHorario.horaDeCambio =>
      'Se captura la hora de cambio de turno'
          '${m.minutosDelTurno == null ? '' : ' · turnos de ${m.minutosDelTurno! ~/ 60} h'}',
    CapturaDelHorario.semanalPrecargada =>
      'Horario semanal, que nace con lunes a viernes puesto',
    CapturaDelHorario.semanalVacia => 'Horario semanal, día por día',
  };
}

/// El panel de alta y edición de una modalidad.
Future<ModalidadDeTurno?> mostrarPanelDeModalidad(
  BuildContext context, {
  required CondicionesRepositorioHttp repositorio,
  required String empresaId,
  required GuardiaDeSalida guardia,
  ModalidadDeTurno? existente,
}) => showDialog<ModalidadDeTurno>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _PanelDeModalidad(
    repositorio: repositorio,
    empresaId: empresaId,
    guardia: guardia,
    existente: existente,
  ),
);

/// Las llaves del panel. Públicas por lo mismo que las de la condición.
class ClavesDeModalidad {
  const ClavesDeModalidad();

  Key get codigo => const Key('modalidad-codigo');
  Key get nombre => const Key('modalidad-nombre');
  Key get explicacion => const Key('modalidad-explicacion');
  Key get pidePeriodo => const Key('modalidad-pide-periodo');
  Key get captura => const Key('modalidad-captura');
  Key get duracion => const Key('modalidad-duracion');
  Key get estatus => const Key('modalidad-estatus');
  Key get guardar => const Key('modalidad-guardar');
}

const ClavesDeModalidad clavesDeModalidad = ClavesDeModalidad();

class _PanelDeModalidad extends StatefulWidget {
  const _PanelDeModalidad({
    required this.repositorio,
    required this.empresaId,
    required this.guardia,
    required this.existente,
  });

  final CondicionesRepositorioHttp repositorio;
  final String empresaId;
  final GuardiaDeSalida guardia;
  final ModalidadDeTurno? existente;

  @override
  State<_PanelDeModalidad> createState() => _PanelDeModalidadState();
}

class _PanelDeModalidadState extends State<_PanelDeModalidad>
    with DeclaraSuTrabajoSinGuardar<_PanelDeModalidad> {
  @override
  GuardiaDeSalida get guardia => widget.guardia;

  @override
  bool get hayCambiosSinGuardar =>
      _codigo.text.trim() != _codigoInicial ||
      _nombre.text.trim() != _nombreInicial ||
      _explicacion.text.trim() != _explicacionInicial ||
      _pidePeriodo != _pidePeriodoInicial ||
      _captura != _capturaInicial ||
      _duracion.text.trim() != _duracionInicial ||
      _activa != _activaInicial;

  @override
  String get queSePierde => widget.existente == null
      ? 'la modalidad de turno que estás dando de alta'
      : 'los cambios de la modalidad «${widget.existente!.nombre}»';

  late final String _codigoInicial = widget.existente?.codigo ?? '';
  late final String _nombreInicial = widget.existente?.nombre ?? '';
  late final String _explicacionInicial = widget.existente?.explicacion ?? '';
  late final bool _pidePeriodoInicial = widget.existente?.pidePeriodo ?? false;
  late final CapturaDelHorario _capturaInicial =
      widget.existente?.capturaDelHorario ?? CapturaDelHorario.semanalVacia;
  late final String _duracionInicial = widget.existente?.minutosDelTurno == null
      ? ''
      : (widget.existente!.minutosDelTurno! ~/ 60).toString();
  late final bool _activaInicial = widget.existente?.estaActiva ?? true;

  final _codigo = TextEditingController();
  final _nombre = TextEditingController();
  final _explicacion = TextEditingController();
  final _duracion = TextEditingController();

  late bool _pidePeriodo = _pidePeriodoInicial;
  late CapturaDelHorario _captura = _capturaInicial;
  late bool _activa = _activaInicial;

  bool _guardando = false;
  final Map<String, String> _errores = {};

  @override
  void initState() {
    super.initState();

    _codigo.text = _codigoInicial;
    _nombre.text = _nombreInicial;
    _explicacion.text = _explicacionInicial;
    _duracion.text = _duracionInicial;
  }

  @override
  void dispose() {
    _codigo.dispose();
    _nombre.dispose();
    _explicacion.dispose();
    _duracion.dispose();
    super.dispose();
  }

  bool get _esAlta => widget.existente == null;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_esAlta ? 'Nueva modalidad de turno' : 'Editar la modalidad'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // EL CÓDIGO SÓLO EN EL ALTA: es identidad y el servidor no lo acepta en el
            // cambio. Un campo que se puede escribir y que no se guarda es una mentira.
            if (_esAlta) ...[
              RisegTextField(
                key: clavesDeModalidad.codigo,
                label: 'Código',
                controller: _codigo,
                errorText: _errores['codigo'],
                helperText: 'Corto y en mayúsculas: 24X24, 12X12_CORRIDO.',
                onChanged: (_) => setState(() => _errores.remove('codigo')),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            RisegTextField(
              key: clavesDeModalidad.nombre,
              label: 'Nombre',
              controller: _nombre,
              errorText: _errores['nombre'],
              helperText: 'Como se habla de ella: «24 × 24», «12 × 12 corrido».',
              onChanged: (_) => setState(() => _errores.remove('nombre')),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              key: clavesDeModalidad.explicacion,
              label: 'Explicación (opcional)',
              controller: _explicacion,
              maxLines: 3,
              errorText: _errores['explicacion'],
              helperText:
                  'Lo que se lee al elegirla. Conviene decir cuántas personas hacen '
                  'falta para cubrir 24 horas los 7 días.',
              helperMaxLines: 3,
              onChanged: (_) => setState(() => _errores.remove('explicacion')),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<CapturaDelHorario>(
              key: clavesDeModalidad.captura,
              label: 'Cómo se captura su horario',
              value: _captura,
              helperText: switch (_captura) {
                CapturaDelHorario.horaDeCambio =>
                  'Una sola hora: cuándo entra el turno diurno. El horario se deriva de '
                      'ella y de la duración del turno.',
                CapturaDelHorario.semanalPrecargada =>
                  'Rejilla de siete días, que nace con lunes a viernes de 09:00 a 17:00 '
                      'y se puede cambiar.',
                CapturaDelHorario.semanalVacia =>
                  'Rejilla de siete días en blanco: se captura bloque por bloque.',
              },
              helperMaxLines: 3,
              items: const [
                RisegSelectItem(
                  value: CapturaDelHorario.horaDeCambio,
                  label: 'Con la hora de cambio de turno',
                ),
                RisegSelectItem(
                  value: CapturaDelHorario.semanalPrecargada,
                  label: 'Horario semanal, precargado de lunes a viernes',
                ),
                RisegSelectItem(
                  value: CapturaDelHorario.semanalVacia,
                  label: 'Horario semanal, día por día',
                ),
              ],
              onChanged: (v) => setState(() {
                _captura = v ?? CapturaDelHorario.semanalVacia;

                // LA DURACIÓN SÓLO EXISTE CON LA HORA DE CAMBIO: al pasar a una captura
                // semanal se limpia, porque el servidor la rechaza —y porque en una
                // rejilla la duración la dicen sus bloques—.
                if (_captura != CapturaDelHorario.horaDeCambio) _duracion.clear();

                _errores.remove('duracion');
              }),
            ),
            if (_captura == CapturaDelHorario.horaDeCambio) ...[
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                key: clavesDeModalidad.duracion,
                label: 'Horas que dura el turno',
                controller: _duracion,
                keyboardType: TextInputType.number,
                errorText: _errores['duracion'],
                helperText:
                    'Con ella y la hora de cambio se derivan las horas: un turno de 12 h '
                    'que entra a las 08:00 va de 08:00 a 20:00.',
                helperMaxLines: 3,
                onChanged: (_) => setState(() => _errores.remove('duracion')),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            // ⚠️ **LA NOTA DE `RisegCheckbox` VA AL LADO Y ES CORTA A PROPÓSITO** —no se
            // ajusta a dos líneas—, así que la explicación larga va debajo, en su propio
            // texto. Una frase entera dentro de la nota desborda la fila, y lo que no se
            // ve es tan malo como lo que no está.
            RisegCheckbox(
              key: clavesDeModalidad.pidePeriodo,
              label: 'La plaza es fija de día o de noche',
              value: _pidePeriodo,
              onChanged: (v) => setState(() => _pidePeriodo = v),
            ),
            Text(
              'Márcalo cuando el turno NO rota: entonces al capturar una condición hay que '
              'decir si la plaza es diurna o nocturna, porque se cobra distinto.',
              style: AppTypography.caption.copyWith(color: context.colors.textMuted),
            ),
            if (!_esAlta) ...[
              const SizedBox(height: AppSpacing.md),
              RisegCheckbox(
                key: clavesDeModalidad.estatus,
                label: 'Activa',
                value: _activa,
                onChanged: (v) => setState(() => _activa = v),
              ),
              Text(
                'Una modalidad inactiva no se puede elegir para una condición nueva. Las '
                'condiciones que ya la usan la conservan.',
                style: AppTypography.caption.copyWith(color: context.colors.textMuted),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _guardando ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: clavesDeModalidad.guardar,
        onPressed: _guardando ? null : _guardar,
        child: const Text('Guardar'),
      ),
    ],
  );

  Future<void> _guardar() async {
    final errores = <String, String>{};

    if (_esAlta && _codigo.text.trim().isEmpty) {
      errores['codigo'] = 'Escribe el código.';
    }

    if (_nombre.text.trim().isEmpty) errores['nombre'] = 'Ponle nombre.';

    final horas = int.tryParse(_duracion.text.trim());

    if (_captura == CapturaDelHorario.horaDeCambio) {
      if (horas == null || horas < 1 || horas > 24) {
        errores['duracion'] = 'Entre 1 y 24 horas.';
      }
    }

    if (errores.isNotEmpty) {
      setState(() {
        _errores
          ..clear()
          ..addAll(errores);
      });

      return;
    }

    setState(() => _guardando = true);

    final minutos = _captura == CapturaDelHorario.horaDeCambio ? horas! * 60 : 0;

    final resultado = _esAlta
        ? await widget.repositorio.crearModalidad(
            empresaId: widget.empresaId,
            codigo: _codigo.text.trim().toUpperCase(),
            nombre: _nombre.text.trim(),
            explicacion: _explicacion.text.trim(),
            pidePeriodo: _pidePeriodo,
            captura: _captura,
            minutosDelTurno: minutos == 0 ? null : minutos,
          )
        : await widget.repositorio.modificarModalidad(
            empresaId: widget.empresaId,
            modalidadId: widget.existente!.id,
            nombre: _nombre.text.trim(),
            explicacion: _explicacion.text.trim(),
            pidePeriodo: _pidePeriodo,
            // ⚠️ **CERO VACÍA LA DURACIÓN**, y no es un valor: el contrato lo dice así
            // porque un nulo significa «no la toques», y pasar de un turno rotativo a
            // una captura semanal tiene que poder QUITARLA.
            captura: _captura,
            minutosDelTurno: minutos,
            estatus: _activa ? 'activa' : 'inactiva',
          );

    if (!mounted) return;

    resultado.when(
      ok: (modalidad) => Navigator.of(context).pop(modalidad),
      failure: (f) {
        setState(() => _guardando = false);
        RisegFeedback.showError(context, MensajesHumanos.deMutacion(f));
      },
    );
  }
}
