import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/company/company_remota.dart';
import '../../../core/company/logotipos_de_empresa.dart';
import '../../../core/design_system/design_system_web.dart';

/// La tarjeta de una empresa, **la única que hay**.
///
/// La usan los dos sitios donde se elige empresa: la pantalla «Elige una empresa» al
/// entrar y el menú de la barra inferior. **Se programa una vez a propósito** — dos
/// tarjetas que se parecen divergen en el primer arreglo, y el día que divergen nadie
/// se da cuenta, porque cada una se ve bien por separado.
///
/// Lo que cambia entre los dos sitios es el TAMAÑO, no la forma:
///
/// ```
///  completa (al entrar)                 compacta (el menú)
///  ┌────┐ Nombre comercial  ╭────╮      ┌──┐ Nombre comercial   ✓
///  │ 🏢 │ Razón social      │Últ.│      │RS│ Maestro
///  └────┘ Organización·Rol  ╰vez─╯      └──┘
/// ```
///
/// **La razón social se omite cuando no hay**, y no se sustituye por un «sin
/// registrar»: `company.legal_name` es nullable en la base porque Tenancy crea la
/// Company con un nombre y nada más, así que una empresa recién aprovisionada no la
/// tiene. *Ausencia nunca es cero*, y menos como texto de disculpa en la pantalla de
/// bienvenida. Con razón social la tarjeta tiene tres líneas; sin ella, dos.
///
/// **La organización sólo aparece en la completa.** Al entrar hace falta —una misma
/// persona puede tener acceso a «Administración» en dos clientes distintos, y el
/// nombre de la empresa solo no los distingue—; en el menú ya se está dentro, y se
/// está cambiando entre las propias.
class TarjetaDeEmpresa extends StatelessWidget {
  const TarjetaDeEmpresa({
    required this.empresa,
    required this.logotipos,
    required this.alPulsar,
    this.ultimaVez = false,
    this.esLaActiva = false,
    this.compacta = false,
    this.ocupada = false,
    this.apagada = false,
    super.key,
  });

  final CompanyDisponible empresa;

  /// De dónde salen los logotipos. **Se recibe, no se construye:** esta pieza no sabe
  /// pedir nada por su cuenta, y así el guardia de arquitectura sigue siendo cierto.
  final LogotiposDeEmpresa logotipos;

  /// Qué hacer al pulsarla. **Nulo la vuelve inerte sin apagarla**, y las dos cosas
  /// hacen falta por separado: dentro del menú de la barra, quien recoge el toque es el
  /// propio elemento del menú, así que la tarjeta no debe tener su propio `InkWell`
  /// activo — y no por eso está deshabilitada.
  final VoidCallback? alPulsar;

  /// Pintada al 50 %: sigue ahí, pero ahora no se puede usar.
  ///
  /// **Separado de `alPulsar`** porque «inerte» y «deshabilitada» no son lo mismo. Si el
  /// apagado se dedujera de `alPulsar == null`, las tarjetas del menú saldrían todas
  /// grises.
  final bool apagada;

  /// La última empresa usada. Sólo en la pantalla completa.
  final bool ultimaVez;

  /// La empresa en la que se está trabajando. Sólo en el menú.
  final bool esLaActiva;

  final bool compacta;

  /// Esta tarjeta es la que se está abriendo: lleva el giro en vez de la flecha.
  final bool ocupada;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lado = compacta ? 34.0 : 44.0;

    final textos = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          empresa.companyName,
          style: AppTypography.body.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
            // EN EL MENÚ, UN PUNTO MENOS. No hay un `bodySmall` en el Design System y
            // no se inventa uno aquí: un token nuevo pertenece al sistema, no a una
            // tarjeta.
            fontSize: compacta ? 13.5 : null,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (!compacta && empresa.razonSocial != null)
          Text(
            empresa.razonSocial!,
            style: AppTypography.caption.copyWith(color: colors.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        if (compacta)
          _Rol(role: empresa.role, colors: colors)
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  empresa.organizationName,
                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                ' · ',
                style: AppTypography.caption.copyWith(color: colors.textMuted),
              ),
              _Rol(role: empresa.role, colors: colors),
            ],
          ),
      ],
    );

    final contenido = Row(
      children: [
        RecuadroDeLogotipo(
          companyId: empresa.companyId,
          nombre: empresa.companyName,
          logotipos: logotipos,
          lado: lado,
        ),
        SizedBox(width: compacta ? AppSpacing.sm : AppSpacing.md),
        // `Expanded` Y NO `Flexible`: la insignia y la flecha van pegadas al borde
        // derecho, y con `Flexible` se acercarían al texto en los nombres cortos,
        // dejando las tarjetas desalineadas entre sí.
        Expanded(child: textos),
        if (ultimaVez) ...[
          const SizedBox(width: AppSpacing.sm),
          _InsigniaUltimaVez(colors: colors),
        ],
        SizedBox(width: compacta ? AppSpacing.xs : AppSpacing.sm),
        _Senal(
          ocupada: ocupada,
          esLaActiva: esLaActiva,
          compacta: compacta,
          colors: colors,
        ),
      ],
    );

    return Opacity(
      // SE APAGA, NO DESAPARECE. Mientras una empresa se abre, las demás se
      // deshabilitan —dos selecciones a la vez dejarían a la segunda ganando la
      // carrera—, y verlas apagadas dice que siguen ahí.
      opacity: apagada ? 0.5 : 1,
      child: Material(
        color: esLaActiva ? colors.accentSoftBg : colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: alPulsar,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compacta ? AppSpacing.sm : AppSpacing.md,
              vertical: compacta ? AppSpacing.sm : AppSpacing.md,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: ocupada
                    ? AppColors.verdeMarca
                    : esLaActiva
                    ? colors.accent
                    : colors.borderSubtle,
                width: ocupada || esLaActiva ? 1.6 : 1,
              ),
            ),
            child: contenido,
          ),
        ),
      ),
    );
  }
}

/// El rol, **en palabras y no en vocabulario del modelo de permisos**.
///
/// ⚠️ **ESTO REVIERTE UNA DECISIÓN ESCRITA**, y el motivo cambió de verdad. El selector
/// anterior documentaba que el rol no se mostraba: «es vocabulario del modelo de
/// permisos, no algo que ayude a elegir». Con **una** empresa era cierto. Con dos en las
/// que la misma persona es Maestra en una y usuaria en la otra, el rol es justamente lo
/// que dice qué se va a poder hacer al entrar.
///
/// Lo que sí se conserva de aquella decisión es que `maestro` y `user` **no se
/// enseñan**: son los valores del catálogo cerrado del backend, y la pantalla dice
/// «Maestro» y «Usuario».
///
/// El Maestro va en verde de marca porque es el único de los dos que cambia lo que se
/// puede hacer ahí. Un rol desconocido —si el catálogo creciera— se enseña **tal cual**
/// en vez de traducirse a «Usuario»: inventarle un nombre bonito a algo que no se
/// entiende es peor que repetir lo que dijo el servidor.
class _Rol extends StatelessWidget {
  const _Rol({required this.role, required this.colors});

  final String role;
  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final (texto, esMaestro) = switch (role) {
      'maestro' => ('Maestro', true),
      'user' => ('Usuario', false),
      _ => (role, false),
    };

    return Text(
      texto,
      style: AppTypography.caption.copyWith(
        color: esMaestro ? AppColors.verdeMarca : colors.textMuted,
        fontWeight: esMaestro ? FontWeight.w600 : FontWeight.w400,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _InsigniaUltimaVez extends StatelessWidget {
  const _InsigniaUltimaVez({required this.colors});

  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('tarjeta_ultima_vez'),
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
    decoration: BoxDecoration(
      color: colors.successBg,
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Text(
      'Última vez',
      style: AppTypography.caption.copyWith(
        color: colors.success,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _Senal extends StatelessWidget {
  const _Senal({
    required this.ocupada,
    required this.esLaActiva,
    required this.compacta,
    required this.colors,
  });

  final bool ocupada;
  final bool esLaActiva;
  final bool compacta;
  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) {
    if (ocupada) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          color: AppColors.verdeMarca,
        ),
      );
    }

    if (esLaActiva) {
      return Icon(
        Icons.check,
        key: const Key('tarjeta_es_la_activa'),
        size: 18,
        color: colors.accent,
      );
    }

    return Icon(
      Icons.chevron_right,
      size: compacta ? 18 : 22,
      color: colors.textMuted,
    );
  }
}

/// El logotipo de la empresa, o sus iniciales mientras no haya uno.
///
/// **Nace con las iniciales y cambia cuando el logotipo llega.** Es una petición por
/// empresa y no se espera a ninguna: una pantalla de bienvenida que tarda en aparecer
/// porque está bajando imágenes es peor que una que las va poniendo. Y si el logotipo
/// ya estaba en la caché, nace con él puesto — así abrir el menú dos veces no parpadea.
class RecuadroDeLogotipo extends StatefulWidget {
  const RecuadroDeLogotipo({
    required this.companyId,
    required this.nombre,
    required this.logotipos,
    required this.lado,
    super.key,
  });

  /// ⚠️ **RECIBE EL ID Y EL NOMBRE, NO UNA `CompanyDisponible`.** Al principio recibía
  /// el modelo entero, y E2 lo cambió: su lista de administración usa otro modelo
  /// —`EmpresaAdministrada`, con el estado y el número de accesos—, y lo único que este
  /// recuadro necesita de cualquiera de los dos es **de quién es el logotipo** y **qué
  /// iniciales pintar si no hay**.
  ///
  /// Pedir el modelo habría obligado a E2 a fabricar uno falso para poder pintar.
  final String companyId;
  final String nombre;

  final LogotiposDeEmpresa logotipos;
  final double lado;

  @override
  State<RecuadroDeLogotipo> createState() => _RecuadroDeLogotipoState();
}

class _RecuadroDeLogotipoState extends State<RecuadroDeLogotipo> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();

    final ya = widget.logotipos.yaResuelto(widget.companyId);

    if (ya != null) {
      _bytes = ya.bytes;
      return;
    }

    _pedir();
  }

  Future<void> _pedir() async {
    final bytes = await widget.logotipos.leer(widget.companyId);

    // `mounted` NO ES OPCIONAL: la tarjeta puede desmontarse mientras la imagen
    // viaja —el menú se cierra, o se cambió de empresa— y llamar a `setState` sobre
    // un `State` desmontado lanza.
    if (!mounted || bytes == null) return;

    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;

    return SizedBox(
      width: widget.lado,
      height: widget.lado,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: bytes == null
            ? _Iniciales(
                companyId: widget.companyId,
                nombre: widget.nombre,
                lado: widget.lado,
              )
            : Image.memory(
                bytes,
                // `contain` Y FONDO CLARO: un logotipo recortado para llenar el
                // cuadro perdería parte de la marca, que es lo único que esa imagen
                // tiene que hacer bien.
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => _Iniciales(
                  companyId: widget.companyId,
                  nombre: widget.nombre,
                  lado: widget.lado,
                ),
              ),
      ),
    );
  }
}

/// Dos letras sobre un color.
///
/// **El color sale del `companyId`, no del nombre**, y es lo que hace que renombrar una
/// empresa no le cambie el color que la vuelve reconocible de un vistazo. Sale de la
/// paleta categórica del Design System, que ya está pensada para que dos colores
/// contiguos se distingan.
class _Iniciales extends StatelessWidget {
  const _Iniciales({
    required this.companyId,
    required this.nombre,
    required this.lado,
  });

  final String companyId;
  final String nombre;
  final double lado;

  /// Las dos primeras letras de las dos primeras palabras: «RISEG Servicios» → `RS`.
  /// Con una sola palabra, sus dos primeras letras: «Administración» → `AD`.
  static String inicialesDe(String nombre) {
    final palabras = nombre
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();

    if (palabras.isEmpty) return '?';

    if (palabras.length == 1) {
      final una = palabras.single;
      return (una.length == 1 ? una : una.substring(0, 2)).toUpperCase();
    }

    return (palabras[0].characters.first + palabras[1].characters.first)
        .toUpperCase();
  }

  /// El color, derivado del id. **`hashCode` de la cadena no sirve**: en Dart no está
  /// garantizado estable entre ejecuciones, así que el color de una empresa podría
  /// cambiar al recargar la página. Se suman los códigos de los caracteres, que es
  /// aritmética y no una promesa de la plataforma.
  static Color colorDe(String companyId, List<Color> paleta) {
    var suma = 0;
    for (final unidad in companyId.codeUnits) {
      suma = (suma + unidad) % 1000003;
    }

    return paleta[suma % paleta.length];
  }

  @override
  Widget build(BuildContext context) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    final paleta = oscuro ? AppColors.categoricaDark : AppColors.categoricaLight;
    final fondo = colorDe(companyId, paleta);

    return ColoredBox(
      color: fondo,
      child: Center(
        child: Text(
          inicialesDe(nombre),
          style: AppTypography.caption.copyWith(
            // BLANCO SOBRE LA PALETA CLARA, TINTA SOBRE LA OSCURA: la paleta de tema
            // oscuro es clara por definición —tiene que verse sobre un lienzo
            // oscuro—, así que ahí el texto blanco desaparecería.
            color: oscuro ? AppColors.tinta : Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: lado <= 34 ? 12 : 14,
          ),
        ),
      ),
    );
  }
}
