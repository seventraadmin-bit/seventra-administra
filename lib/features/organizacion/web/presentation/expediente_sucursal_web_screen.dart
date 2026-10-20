import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../datos/expedientes_repositorio_http.dart';
import '../modelos/expediente.dart';
import 'eliminar_estructura.dart';

/// El expediente de una SUCURSAL: domicilio y horario semanal.
///
/// ## El horario puede más que el del escritorio, a propósito
///
/// Allá el horario son **siete filas fijas con un tramo cada una**, así que una
/// oficina que abre 9–14 y 16–20 no caía en el modelo. Aquí cada día admite **los
/// tramos que haga falta**, y el solape **lo impide el motor** —no un `if` de esta
/// pantalla— con una exclusión sobre la semana canónica.
///
/// **Un día cerrado es la AUSENCIA de tramos**, nunca un tramo con ceros. Por eso el
/// interruptor de «Abierto» no guarda nada por sí mismo: apagarlo quita los tramos del
/// día, y eso es exactamente lo que «cerrado» significa.
///
/// ## El 24:00 y por qué no se puede elegir «00:00» como cierre
///
/// `TimeOfDay` no puede valer 24:00, y el servidor **rechaza** un cierre de 0 con un
/// mensaje que nombra el 24:00. Así que cuando alguien elige las 00:00 como hora de
/// cierre, se guarda como 1440 —medianoche— y se muestra «24:00». No es una suposición
/// cómoda: un tramo de 22:00 a 00:00 son dos horas, y «hasta las 00:00 de pasado
/// mañana» no significa nada. La conversión vive en [TramoDeHorario.nuevo], en un solo
/// sitio.
///
/// <b>Importa `design_system_web.dart`, NUNCA el barrel completo</b>, que arrastra
/// `dart:io` y rompe la build web.
class ExpedienteSucursalWebScreen extends StatefulWidget {
  const ExpedienteSucursalWebScreen({
    required this.repositorio,
    required this.empresaId,
    required this.sucursalId,
    required this.puedeEditar,
    required this.onVolver,
    super.key,
  });

  final ExpedientesRepositorioHttp repositorio;
  final String empresaId;
  final String sucursalId;

  /// Cómo volver a la lista. **Lo decide quien abrió esta pantalla**, igual que en el
  /// catálogo de tipos: mientras la web no tenga router, la navegación es del padre.
  final VoidCallback onVolver;

  /// Si quien mira tiene `company.settings.manage`. **Sólo gobierna si los campos se
  /// ofrecen**; quien decide es el servidor.
  final bool puedeEditar;

  @override
  State<ExpedienteSucursalWebScreen> createState() =>
      _ExpedienteSucursalWebScreenState();
}

class _ExpedienteSucursalWebScreenState
    extends State<ExpedienteSucursalWebScreen> {
  ExpedienteDeSucursal? _expediente;
  Failure? _fallo;
  bool _cargando = true;
  bool _guardando = false;
  Map<String, String> _erroresDeCampo = const {};

  /// El horario que se está editando. **Copia propia**, no la del expediente: así
  /// cancelar es cerrar, y nada de lo escrito se cuela al modelo cargado.
  List<TramoDeHorario> _horario = [];

  final _calle = TextEditingController();
  final _exterior = TextEditingController();
  final _interior = TextEditingController();
  final _colonia = TextEditingController();
  final _municipio = TextEditingController();
  final _ciudad = TextEditingController();
  final _estado = TextEditingController();
  final _cp = TextEditingController();
  final _pais = TextEditingController();
  final _referencias = TextEditingController();

  List<TextEditingController> get _todos => [
    _calle, _exterior, _interior, _colonia, _municipio,
    _ciudad, _estado, _cp, _pais, _referencias,
  ];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    // Liberar los controllers no es opcional: en este proyecto ya costó una vez.
    for (final c in _todos) {
      c.dispose();
    }

    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _fallo = null;
    });

    final resultado = await widget.repositorio.leerDeSucursal(
      empresaId: widget.empresaId,
      sucursalId: widget.sucursalId,
    );

    if (!mounted) return;

    resultado.when(
      ok: (e) => setState(() {
        _expediente = e;
        _horario = [...e.horario];
        _volcarDomicilio(e.direccion);
        _cargando = false;
        _erroresDeCampo = const {};
      }),
      failure: (f) => setState(() {
        _fallo = f;
        _cargando = false;
      }),
    );
  }

  void _volcarDomicilio(Direccion? d) {
    _calle.text = d?.calle ?? '';
    _exterior.text = d?.numeroExterior ?? '';
    _interior.text = d?.numeroInterior ?? '';
    _colonia.text = d?.colonia ?? '';
    _municipio.text = d?.municipio ?? '';
    _ciudad.text = d?.ciudad ?? '';
    _estado.text = d?.estado ?? '';
    _cp.text = d?.codigoPostal ?? '';
    _pais.text = d?.pais ?? '';
    _referencias.text = d?.referencias ?? '';
  }

  // =========================================================================
  // El horario
  // =========================================================================

  List<TramoDeHorario> _tramosDe(int dia) =>
      [for (final t in _horario) if (t.dia == dia) t]
        ..sort((a, b) => a.inicio.compareTo(b.inicio));

  /// Enciende un día: le pone **un** tramo de 9 a 18, que es el que casi siempre es.
  ///
  /// Apagarlo **quita todos** sus tramos, porque cerrado es la ausencia de tramos.
  void _cambiarDia(int dia, {required bool abierto}) {
    setState(() {
      _horario = [for (final t in _horario) if (t.dia != dia) t];

      if (abierto) {
        _horario.add(
          TramoDeHorario.nuevo(dia: dia, inicio: 9 * 60, fin: 18 * 60),
        );
      }
    });
  }

  void _agregarTramo(int dia) {
    final existentes = _tramosDe(dia);

    // EL TRAMO NUEVO EMPIEZA DONDE TERMINÓ EL ÚLTIMO, no a las 9 otra vez: así el
    // caso común —abrir, cerrar a comer, reabrir— no nace solapado, que es el único
    // estado que el motor va a rechazar.
    final desde = existentes.isEmpty
        ? 9 * 60
        : existentes.last.fin == 1440
              ? 1440
              : existentes.last.fin;

    setState(() {
      _horario.add(
        TramoDeHorario.nuevo(
          dia: dia,
          inicio: desde >= 1440 ? 0 : desde,
          fin: desde >= 1440 || desde + 120 > 1440 ? 1440 : desde + 120,
        ),
      );
    });
  }

  void _quitarTramo(TramoDeHorario tramo) {
    setState(() => _horario.remove(tramo));
  }

  void _cambiarHora(
    TramoDeHorario tramo, {
    int? inicio,
    int? fin,
  }) {
    final indice = _horario.indexOf(tramo);
    if (indice < 0) return;

    setState(() {
      _horario[indice] = TramoDeHorario.nuevo(
        dia: tramo.dia,
        inicio: inicio ?? tramo.inicio,
        fin: fin ?? tramo.fin,
      );
    });
  }

  // =========================================================================
  // Guardar
  // =========================================================================

  bool get _hayAlgoDeDomicilio => _todos.any((c) => c.text.trim().isNotEmpty);

  Direccion? _direccionDelFormulario() {
    if (!_hayAlgoDeDomicilio) return null;

    String? opcional(TextEditingController c) {
      final t = c.text.trim();

      return t.isEmpty ? null : t;
    }

    return Direccion(
      calle: _calle.text.trim(),
      numeroExterior: _exterior.text.trim(),
      colonia: _colonia.text.trim(),
      municipio: _municipio.text.trim(),
      estado: _estado.text.trim(),
      codigoPostal: _cp.text.trim(),
      numeroInterior: opcional(_interior),
      ciudad: opcional(_ciudad),
      pais: opcional(_pais),
      referencias: opcional(_referencias),
    );
  }

  Future<void> _guardar() async {
    final expediente = _expediente;
    if (expediente == null) return;

    setState(() {
      _guardando = true;
      _erroresDeCampo = const {};
    });

    final resultado = await widget.repositorio.guardarDeSucursal(
      empresaId: widget.empresaId,
      sucursalId: widget.sucursalId,
      // La versión que se leyó al abrir. No se vuelve a pedir antes de guardar:
      // hacerlo leería justo el valor que acaba de cambiar la otra persona.
      version: expediente.version,
      direccion: _direccionDelFormulario(),
      horario: _horario,
    );

    if (!mounted) return;

    resultado.when(
      ok: (e) {
        setState(() {
          _expediente = e;
          _horario = [...e.horario];
          _volcarDomicilio(e.direccion);
          _guardando = false;
        });

        RisegFeedback.showSuccess(context, 'Expediente de la sucursal guardado.');
      },
      failure: (f) {
        setState(() => _guardando = false);

        if (ExpedientesRepositorioHttp.esDesactualizado(f)) {
          _avisarDesactualizado();

          return;
        }

        // EL SOLAPE LO DICE EL MOTOR Y SE MUESTRA TAL CUAL. La pantalla no lo
        // adelanta con una comprobación propia: serían dos reglas para un mismo
        // hecho, y la de aquí se quedaría atrás el día que la del motor cambie.
        if (f case ApiHttpFailure(codigo: 'horario_se_solapa')) {
          mostrarRechazoDelServidor(context, f.message);

          return;
        }

        final campos = ExpedientesRepositorioHttp.camposDe(f);

        if (campos.isNotEmpty) {
          setState(() => _erroresDeCampo = campos);

          return;
        }

        mostrarRechazoDelServidor(context, f.message);
      },
    );
  }

  void _avisarDesactualizado() {
    showDialog<void>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Alguien más guardó este expediente'),
        content: const Text(
          'Mientras tenías el formulario abierto, otra persona guardó cambios en el '
          'expediente de esta sucursal. Para no borrar su trabajo, no se guardó '
          'nada.\n\n'
          'Se van a cargar los datos más recientes. Revisa lo que haya cambiado y '
          'vuelve a escribir lo tuyo.',
        ),
        actions: [
          RisegButton(
            label: 'Cargar lo más reciente',
            onPressed: () {
              Navigator.of(contexto).pop();
              _cargar();
            },
          ),
        ],
      ),
    );
  }

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
              Text(fallo.message, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              RisegButton(label: 'Volver a intentar', onPressed: _cargar),
            ],
          ),
        ),
      );
    }

    final expediente = _expediente!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // EL REGRESO VA ARRIBA Y A LA IZQUIERDA, igual que en el catálogo de tipos:
          // no es una pestaña, así que sin esto no habría forma de salir.
          InkWell(
            onTap: widget.onVolver,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_back,
                    size: 16,
                    color: context.colors.accent,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    'Sucursales',
                    style: AppTypography.caption.copyWith(
                      color: context.colors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          RisegSectionHeader(
            title: '${expediente.codigo} · ${expediente.nombre}',
            description:
                'El domicilio y el horario de esta sucursal. Recuerda: la sucursal es '
                'un destino administrativo, no el lugar donde se cubre un servicio.',
          ),
          const SizedBox(height: AppSpacing.lg),
          _seccionDeDomicilio(),
          const SizedBox(height: AppSpacing.lg),
          _seccionDeHorario(),
          const SizedBox(height: AppSpacing.xl),
          if (widget.puedeEditar)
            Align(
              alignment: Alignment.centerRight,
              child: RisegButton(
                label: 'Guardar expediente',
                icon: Icons.save_outlined,
                loading: _guardando,
                onPressed: _guardando ? null : _guardar,
              ),
            )
          else
            Text(
              'Sólo puedes consultar este expediente. Editarlo necesita el permiso '
              'de configuración de la empresa.',
              style: AppTypography.caption.copyWith(
                color: context.colors.textMuted,
              ),
            ),
        ],
      ),
    );
  }

  Widget _seccionDeHorario() => RisegFormSection(
    title: 'Horario semanal',
    description:
        'Cada día puede tener más de un tramo: abrir de 9 a 14 y de 16 a 20 son dos '
        'tramos del mismo día. Un día sin tramos está cerrado.',
    children: [
      for (var dia = 1; dia <= 7; dia++) _filaDeDia(dia),
      if (_erroresDeCampo.keys.any((k) => k.startsWith('schedule')))
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: Text(
            [
              for (final e in _erroresDeCampo.entries)
                if (e.key.startsWith('schedule')) e.value,
            ].join('\n'),
            style: AppTypography.caption.copyWith(
              color: context.colors.error,
            ),
          ),
        ),
    ],
  );

  Widget _filaDeDia(int dia) {
    final colors = context.colors;
    final tramos = _tramosDe(dia);
    final abierto = tramos.isNotEmpty;
    final habilitado = widget.puedeEditar && !_guardando;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  TramoDeHorario.nombresDeDia[dia],
                  style: AppTypography.body.copyWith(color: colors.textPrimary),
                ),
              ),
              Text(
                abierto ? 'Abierto' : 'Cerrado',
                style: AppTypography.caption.copyWith(color: colors.textMuted),
              ),
              Switch(
                value: abierto,
                onChanged: habilitado
                    ? (v) => _cambiarDia(dia, abierto: v)
                    : null,
              ),
            ],
          ),
          for (final tramo in tramos) _filaDeTramo(tramo, habilitado: habilitado),
          if (abierto && habilitado)
            Align(
              alignment: Alignment.centerLeft,
              child: RisegButton(
                label: 'Agregar tramo',
                icon: Icons.add,
                variant: RisegButtonVariant.secondary,
                size: RisegButtonSize.compact,
                onPressed: () => _agregarTramo(dia),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filaDeTramo(TramoDeHorario tramo, {required bool habilitado}) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      children: [
        Expanded(
          child: RisegTimeField(
            label: 'Desde',
            value: _comoTimeOfDay(tramo.inicio),
            enabled: habilitado,
            onChanged: (v) =>
                _cambiarHora(tramo, inicio: v.hour * 60 + v.minute),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: RisegTimeField(
            label: 'Hasta',
            value: _comoTimeOfDay(tramo.fin),
            enabled: habilitado,
            // «00:00» COMO CIERRE SE GUARDA COMO 24:00, y la ayuda lo dice en vez de
            // dejar que se descubra viendo un número raro.
            helperText: tramo.fin == 1440
                ? 'Cierra a medianoche (24:00).'
                : tramo.cruzaMedianoche
                      ? 'Cruza la medianoche: cierra al día siguiente.'
                      : null,
            onChanged: (v) => _cambiarHora(tramo, fin: v.hour * 60 + v.minute),
          ),
        ),
        if (habilitado)
          IconButton(
            tooltip: 'Quitar este tramo',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _quitarTramo(tramo),
          ),
      ],
    ),
  );

  /// 1440 no cabe en un `TimeOfDay`, así que el selector lo abre en **00:00** — que es
  /// justo el valor que [TramoDeHorario.nuevo] vuelve a convertir en 1440. El reloj
  /// da la vuelta y el dato no se pierde.
  TimeOfDay _comoTimeOfDay(int minutos) {
    final m = minutos >= 1440 ? 0 : minutos;

    return TimeOfDay(hour: m ~/ 60, minute: m % 60);
  }

  Widget _seccionDeDomicilio() => RisegFormSection(
    title: 'Domicilio',
    description:
        'Si escribes cualquier dato, hacen falta calle, número exterior, colonia, '
        'municipio, estado y código postal. Si los dejas todos vacíos, no se guarda '
        'domicilio.',
    grid: true,
    children: [
      RisegTextField(
        label: 'Calle',
        controller: _calle,
        enabled: widget.puedeEditar && !_guardando,
        errorText: _erroresDeCampo['address.street'],
      ),
      RisegTextField(
        label: 'Número exterior',
        controller: _exterior,
        enabled: widget.puedeEditar && !_guardando,
        errorText: _erroresDeCampo['address.exteriorNumber'],
      ),
      RisegTextField(
        label: 'Número interior',
        controller: _interior,
        enabled: widget.puedeEditar && !_guardando,
        errorText: _erroresDeCampo['address.interiorNumber'],
        helperText: 'Opcional.',
      ),
      RisegTextField(
        label: 'Colonia',
        controller: _colonia,
        enabled: widget.puedeEditar && !_guardando,
        errorText: _erroresDeCampo['address.neighborhood'],
      ),
      RisegTextField(
        label: 'Municipio',
        controller: _municipio,
        enabled: widget.puedeEditar && !_guardando,
        errorText: _erroresDeCampo['address.municipality'],
      ),
      RisegTextField(
        label: 'Ciudad',
        controller: _ciudad,
        enabled: widget.puedeEditar && !_guardando,
        errorText: _erroresDeCampo['address.city'],
        helperText: 'Opcional.',
      ),
      RisegTextField(
        label: 'Estado',
        controller: _estado,
        enabled: widget.puedeEditar && !_guardando,
        errorText: _erroresDeCampo['address.state'],
      ),
      RisegTextField(
        label: 'Código postal',
        controller: _cp,
        enabled: widget.puedeEditar && !_guardando,
        errorText: _erroresDeCampo['address.postalCode'],
        helperText: 'Cinco dígitos.',
        keyboardType: TextInputType.number,
      ),
      RisegTextField(
        label: 'País',
        controller: _pais,
        enabled: widget.puedeEditar && !_guardando,
        errorText: _erroresDeCampo['address.country'],
        helperText: 'Opcional.',
      ),
      RisegTextField(
        label: 'Referencias',
        controller: _referencias,
        enabled: widget.puedeEditar && !_guardando,
        errorText: _erroresDeCampo['address.landmarks'],
        helperText: 'Opcional. Entre qué calles, frente a qué.',
      ),
    ],
  );
}
