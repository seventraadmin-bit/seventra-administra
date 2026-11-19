import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/mensajes_humanos.dart';
import '../../../../core/trabajo_sin_guardar/declara_su_trabajo_sin_guardar.dart';
import '../../../../core/trabajo_sin_guardar/guardia_de_salida.dart';
import '../datos/areas_repositorio_http.dart';
import '../datos/puestos_repositorio_http.dart';
import '../modelos/area.dart';
import '../modelos/codigo_sugerido.dart';
import '../modelos/puesto.dart';

/// Crea un **puesto operativo** sin salir de donde se estaba.
///
/// ## Por qué existe
///
/// 🚫 **Porque salir costaba todo lo capturado.** El dueño lo encontró probando el ensayo el
/// 18 de noviembre de 2026: al capturar una condición comercial no había ni un puesto
/// operativo, y el formulario sólo decía *«se dan de alta en Organización › Puestos»*. Seguir
/// ese consejo significaba **salir, crear el área, crear el puesto y volver a capturar la
/// condición desde cero**.
///
/// ## Y crea el ÁREA si hace falta
///
/// Un puesto necesita su área, y aquel día tampoco había ninguna. Así que este diálogo
/// resuelve las dos cosas: si hay áreas activas se elige una, y si no hay **se escribe el
/// nombre de la primera** y se crean las dos en orden.
///
/// ⚠️ **Dos peticiones, y no una transacción**: el área y el puesto son dos rutas distintas
/// del servidor, así que si el puesto fallara el área ya estaría creada. **Se dice en voz
/// alta** en lugar de disimularlo — un área de más es inofensiva y se desactiva, y la
/// alternativa sería una ruta nueva para un atajo de pantalla.
///
/// ## Lo que NO decide
///
/// El tipo es **operativo** y no se pregunta: una condición comercial describe una plaza que
/// se presta, y un puesto administrativo lo rechaza el servidor con su propio código. Para
/// cualquier otra cosa está la pantalla de Puestos, que sigue siendo la completa.
Future<Puesto?> mostrarPuestoRapido(
  BuildContext context, {
  required String empresaId,
  required AreasRepositorioHttp areas,
  required PuestosRepositorioHttp puestos,
  required GuardiaDeSalida guardia,
}) => showDialog<Puesto>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _DialogoDePuestoRapido(
    empresaId: empresaId,
    areas: areas,
    puestos: puestos,
    guardia: guardia,
  ),
);

/// Las llaves de este formulario. Públicas por lo mismo que las de la condición: una prueba
/// no puede inventárselas, y buscar por posición mediría otro campo sin fallar.
class ClavesDePuestoRapido {
  const ClavesDePuestoRapido();

  Key get area => const Key('puesto-rapido-area');
  Key get areaNueva => const Key('puesto-rapido-area-nueva');
  Key get nombre => const Key('puesto-rapido-nombre');
  Key get guardar => const Key('puesto-rapido-guardar');
}

const ClavesDePuestoRapido clavesDePuestoRapido = ClavesDePuestoRapido();

class _DialogoDePuestoRapido extends StatefulWidget {
  const _DialogoDePuestoRapido({
    required this.empresaId,
    required this.areas,
    required this.puestos,
    required this.guardia,
  });

  final String empresaId;
  final AreasRepositorioHttp areas;
  final PuestosRepositorioHttp puestos;
  final GuardiaDeSalida guardia;

  @override
  State<_DialogoDePuestoRapido> createState() => _DialogoDePuestoRapidoState();
}

class _DialogoDePuestoRapidoState extends State<_DialogoDePuestoRapido>
    with DeclaraSuTrabajoSinGuardar<_DialogoDePuestoRapido> {
  @override
  GuardiaDeSalida get guardia => widget.guardia;

  @override
  bool get hayCambiosSinGuardar =>
      _nombre.text.trim().isNotEmpty || _areaNueva.text.trim().isNotEmpty;

  @override
  String get queSePierde => 'el puesto que estás dando de alta';

  final _nombre = TextEditingController();
  final _areaNueva = TextEditingController();

  List<Area> _areas = const [];
  String? _areaId;
  List<String> _codigosDePuesto = const [];

  bool _cargando = true;
  bool _guardando = false;
  final Map<String, String> _errores = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _nombre.dispose();
    _areaNueva.dispose();
    super.dispose();
  }

  /// Las áreas y los códigos de puesto que ya existen, **en una sola tanda**: los segundos
  /// hacen falta para proponer el código siguiente sin pedírselo a nadie.
  Future<void> _cargar() async {
    final (areas, puestos) = await (
      widget.areas.listar(widget.empresaId),
      widget.puestos.listar(widget.empresaId),
    ).wait;

    if (!mounted) return;

    setState(() {
      _areas = areas.when(
        ok: (lista) => [
          for (final a in lista)
            if (a.activa) a,
        ],
        failure: (_) => const [],
      );

      _codigosDePuesto = puestos.when(
        ok: (lista) => [for (final p in lista) p.codigo],
        failure: (_) => const [],
      );

      _areaId = _areas.length == 1 ? _areas.first.id : null;
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nuevo puesto operativo'),
    content: SizedBox(
      width: 460,
      child: _cargando
          ? const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_areas.isEmpty)
                  RisegTextField(
                    key: clavesDePuestoRapido.areaNueva,
                    label: 'Área',
                    controller: _areaNueva,
                    errorText: _errores['area'],
                    helperText:
                        'Todavía no hay áreas, así que se crea la primera: «Operaciones», '
                        '«Administración».',
                    helperMaxLines: 3,
                    onChanged: (_) => setState(() => _errores.remove('area')),
                  )
                else
                  RisegSelect<String>(
                    key: clavesDePuestoRapido.area,
                    label: 'Área',
                    value: _areaId,
                    errorText: _errores['area'],
                    helperText: 'A qué área pertenece el puesto.',
                    items: [
                      for (final a in _areas)
                        RisegSelectItem(value: a.id, label: a.nombre),
                    ],
                    onChanged: (v) => setState(() {
                      _areaId = v;
                      _errores.remove('area');
                    }),
                  ),
                const SizedBox(height: AppSpacing.md),
                RisegTextField(
                  key: clavesDePuestoRapido.nombre,
                  label: 'Nombre del puesto',
                  controller: _nombre,
                  errorText: _errores['nombre'],
                  helperText:
                      'El cargo, no la persona: «Guardia», «Supervisor de turno». Su '
                      'código se asigna solo.',
                  helperMaxLines: 3,
                  onChanged: (_) => setState(() => _errores.remove('nombre')),
                ),
              ],
            ),
    ),
    actions: [
      TextButton(
        onPressed: _guardando ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: clavesDePuestoRapido.guardar,
        onPressed: _guardando || _cargando ? null : _guardar,
        child: const Text('Guardar'),
      ),
    ],
  );

  Future<void> _guardar() async {
    final errores = <String, String>{};

    if (_nombre.text.trim().isEmpty) errores['nombre'] = 'Ponle nombre al puesto.';

    if (_areas.isEmpty && _areaNueva.text.trim().isEmpty) {
      errores['area'] = 'Escribe el nombre de la primera área.';
    }

    if (_areas.isNotEmpty && _areaId == null) {
      errores['area'] = 'Elige el área del puesto.';
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

    var areaId = _areaId;

    // EL ÁREA PRIMERO, si hace falta: sin ella el puesto no se puede crear.
    if (areaId == null) {
      final nombreDelArea = _areaNueva.text.trim();

      final creada = await widget.areas.crear(
        empresaId: widget.empresaId,
        codigo: siguienteCodigo(
          PrefijoDeCodigo.area,
          [for (final a in _areas) a.codigo],
        ),
        nombre: nombreDelArea,
      );

      if (!mounted) return;

      final area = creada.when(ok: (a) => a, failure: (_) => null);

      if (area == null) {
        setState(() => _guardando = false);

        RisegFeedback.showError(
          context,
          MensajesHumanos.deMutacion(
            creada.when(ok: (_) => throw StateError('imposible'), failure: (f) => f),
          ),
        );

        return;
      }

      areaId = area.id;
    }

    final creado = await widget.puestos.crear(
      empresaId: widget.empresaId,
      areaId: areaId,
      codigo: siguienteCodigo(PrefijoDeCodigo.puesto, _codigosDePuesto),
      nombre: _nombre.text.trim(),
      // ⚠️ OPERATIVO Y FIJO: este atajo existe para capturar una condición comercial, y una
      // condición describe una plaza que se presta. Un administrativo lo rechazaría el
      // servidor con `puesto_no_operativo`, así que ofrecerlo sería ofrecer un error.
      tipo: 'operativo',
      nivel: 1,
    );

    if (!mounted) return;

    creado.when(
      ok: (puesto) {
        // SE CIERRA SIN PREGUNTAR, y no hace falta nada más: el mixin libera su registro al
        // destruirse el estado, y lo que había que guardar ya se guardó.
        Navigator.of(context).pop(puesto);
      },
      failure: (f) {
        setState(() => _guardando = false);
        RisegFeedback.showError(context, MensajesHumanos.deMutacion(f));
      },
    );
  }
}
