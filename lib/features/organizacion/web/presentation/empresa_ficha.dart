import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../../../core/design_system/design_system_web.dart';
import '../../domain/usecases/lineas_de_domicilio_fiscal.dart';
import '../modelos/expediente.dart';

/// La ficha de la empresa, **con la forma en que sus datos se entregan**.
///
/// ## Por qué tiene la forma de la tarjeta fiscal
///
/// Porque es para lo que se usa. Lo que alguien hace a diario con esta pantalla no es
/// editar el RFC: es **leerlo para dárselo a quien va a facturar**. El escritorio ya lo
/// había entendido y tenía una «tarjeta fiscal» con su formato propio; aquí la ficha
/// **es** ese formato, en pantalla, con el logotipo arriba.
///
/// Y el formato no se reinventa: las cinco líneas del domicilio salen de
/// [lineasDeDomicilioFiscal], que el escritorio declara «única fuente de este formato
/// para no tener 3 formatos ligeramente distintos entre pantalla, PDF y portapapeles».
/// Ahora son cuatro salidas y el argumento sólo se hace más fuerte.
///
/// ## De sólo lectura, y sin notas de permiso
///
/// Quien no puede editar **ve la ficha completa**: es la identidad de su empresa, no un
/// dato reservado. Lo que no ve es «Editar».
///
/// **Y aquí no van notas de «te falta tal permiso»**, al contrario que en el
/// formulario: nadie está intentando editar, así que una nota de permiso sería la
/// respuesta a una pregunta que no se hizo.
class EmpresaFicha extends StatelessWidget {
  const EmpresaFicha({
    required this.expediente,
    required this.regimenes,
    required this.logotipo,
    required this.logotipoFallo,
    required this.puedeEditar,
    required this.onEditar,
    required this.onReintentarLogotipo,
    this.onVolverALaLista,
    super.key,
  });

  final ExpedienteDeEmpresa expediente;

  /// El catálogo del SAT, **para decir el régimen con su descripción**.
  ///
  /// ⚠️ **EL EXPEDIENTE SÓLO TRAE EL CÓDIGO**, y un «601» a secas no le dice nada a
  /// nadie: quien recibe la tarjeta fiscal necesita «601 · General de Ley Personas
  /// Morales», que es como lo pide el SAT y como lo enseña el escritorio. Se vio en
  /// pantalla el 21 de octubre de 2026.
  ///
  /// Vacío mientras el catálogo no haya llegado, y entonces se enseña el código solo:
  /// es lo único que se sabe, y esconder el dato por no tener su descripción sería
  /// peor.
  final List<RegimenFiscal> regimenes;

  /// Los bytes del logotipo, o **nulo si la empresa no tiene**.
  final Uint8List? logotipo;

  /// Si el logotipo **no se pudo traer**.
  ///
  /// ⚠️ **NO ES LO MISMO QUE NO TENER LOGOTIPO**, y confundirlos haría pensar que se
  /// perdió. Sin logotipo, la presentación es tipográfica y no se dice nada; con un
  /// fallo, se dice y se ofrece reintentar.
  final bool logotipoFallo;

  final bool puedeEditar;
  final VoidCallback onEditar;
  final VoidCallback onReintentarLogotipo;

  /// Nulo cuando hay una sola empresa: un «‹ Empresas» que lleva a una lista de uno
  /// sería un paso que no decide nada.
  final VoidCallback? onVolverALaLista;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.surface,
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (onVolverALaLista case final volver?) ...[
              _Regreso(onTocar: volver),
              const SizedBox(height: AppSpacing.sm),
            ],

            _Encabezado(
              expediente: expediente,
              logotipo: logotipo,
              logotipoFallo: logotipoFallo,
              puedeEditar: puedeEditar,
              onEditar: onEditar,
              onReintentarLogotipo: onReintentarLogotipo,
            ),
            const SizedBox(height: AppSpacing.lg),

            _DatosFiscales(expediente: expediente, regimenes: regimenes),
            const SizedBox(height: AppSpacing.lg),

            if (expediente.contacto case final contacto?
                when !contacto.estaVacio) ...[
              _Contacto(contacto: contacto),
              const SizedBox(height: AppSpacing.lg),
            ],

            if (expediente.representanteLegal != null ||
                expediente.eslogan != null)
              _RepresentanteYEslogan(expediente: expediente),
          ],
        ),
      ),
    ),
  );
}

class _Regreso extends StatelessWidget {
  const _Regreso({required this.onTocar});

  final VoidCallback onTocar;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTocar,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_back, size: 16, color: context.colors.accent),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            'Empresas',
            style: AppTypography.caption.copyWith(color: context.colors.accent),
          ),
        ],
      ),
    ),
  );
}

/// El logotipo, el nombre y «Editar».
class _Encabezado extends StatelessWidget {
  const _Encabezado({
    required this.expediente,
    required this.logotipo,
    required this.logotipoFallo,
    required this.puedeEditar,
    required this.onEditar,
    required this.onReintentarLogotipo,
  });

  final ExpedienteDeEmpresa expediente;
  final Uint8List? logotipo;
  final bool logotipoFallo;
  final bool puedeEditar;
  final VoidCallback onEditar;
  final VoidCallback onReintentarLogotipo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ⚠️ `Wrap` Y NO `Row`: con un nombre comercial largo y una razón social
        // larga, una fila con el botón al final se sale de la pantalla. Ya pasó en el
        // encabezado de una sucursal, con 95 px de desbordamiento.
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.md,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            _Logotipo(
              bytes: logotipo,
              fallo: logotipoFallo,
              iniciales: _inicialesDe(expediente.nombre),
              onReintentar: onReintentarLogotipo,
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(expediente.nombre, style: AppTypography.heading2),
                  if (expediente.razonSocial case final razon?) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      razon,
                      style: AppTypography.body.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                  if (expediente.rfc case final rfc?) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      rfc,
                      style: AppTypography.body.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                  if (puedeEditar) ...[
                    const SizedBox(height: AppSpacing.md),
                    RisegButton(
                      label: 'Editar',
                      icon: Icons.edit_outlined,
                      variant: RisegButtonVariant.secondary,
                      size: RisegButtonSize.compact,
                      onPressed: onEditar,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),

        // QUÉ FALTA PARA LA TARJETA FISCAL, nombrado. Lo decide el SERVIDOR con
        // `fiscalCardReady`; aquí sólo se nombra lo que está vacío, porque la lista de
        // indispensables es una regla del dominio y dos listas discreparían.
        if (!expediente.tarjetaFiscalLista) ...[
          const SizedBox(height: AppSpacing.md),
          _LoQueFalta(expediente: expediente),
        ],
      ],
    );
  }

  /// Las iniciales para la presentación tipográfica: `RISEG` → `R`, `Seguridad
  /// Privada RISEG` → `SP`.
  static String _inicialesDe(String nombre) {
    final palabras = nombre
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();

    if (palabras.isEmpty) return '—';

    return palabras.length == 1
        ? palabras.first.characters.first.toUpperCase()
        : palabras
              .take(2)
              .map((p) => p.characters.first.toUpperCase())
              .join();
  }
}

/// El logotipo, o lo que se pone en su sitio.
class _Logotipo extends StatelessWidget {
  const _Logotipo({
    required this.bytes,
    required this.fallo,
    required this.iniciales,
    required this.onReintentar,
  });

  final Uint8List? bytes;
  final bool fallo;
  final String iniciales;
  final VoidCallback onReintentar;

  static const double _lado = 96;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (bytes case final imagen? when !fallo) {
      return Container(
        width: _lado,
        height: _lado,
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: colors.borderSubtle),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        // SOBRE BLANCO, porque un PNG con transparencia se diseñó para un documento
        // blanco y sobre el fondo de la pantalla puede desaparecer.
        child: Image.memory(
          imagen,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _Tipografico(iniciales: iniciales),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Tipografico(iniciales: iniciales),

        // UN FALLO SE DICE Y SE PUEDE REINTENTAR. **No tener logotipo no se dice**:
        // es un estado legítimo y la presentación tipográfica ya lo expresa.
        if (fallo) ...[
          const SizedBox(height: AppSpacing.xxs),
          SizedBox(
            width: _lado,
            child: InkWell(
              onTap: onReintentar,
              child: Text(
                'No se pudo cargar el logotipo. Reintentar',
                style: AppTypography.caption.copyWith(color: colors.accent),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Tipografico extends StatelessWidget {
  const _Tipografico({required this.iniciales});

  final String iniciales;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: _Logotipo._lado,
      height: _Logotipo._lado,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.accentSoftBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        iniciales,
        style: AppTypography.heading1.copyWith(color: colors.accent),
      ),
    );
  }
}

/// Qué falta para poder entregar la tarjeta fiscal.
class _LoQueFalta extends StatelessWidget {
  const _LoQueFalta({required this.expediente});

  final ExpedienteDeEmpresa expediente;

  @override
  Widget build(BuildContext context) {
    final falta = [
      if (expediente.razonSocial == null) 'la razón social',
      if (expediente.rfc == null) 'el RFC',
      if (expediente.direccion == null) 'el domicilio fiscal',
    ];

    return RisegCard(
      child: Row(
        children: [
          Icon(Icons.info_outline, color: context.colors.warning),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            // «FALTAN DATOS» OBLIGA A ADIVINAR CUÁL. Se nombran, que es lo que la
            // pantalla del escritorio ya hacía.
            child: Text(
              falta.isEmpty
                  ? 'Para entregar la tarjeta fiscal falta completar el expediente.'
                  : 'Para entregar la tarjeta fiscal '
                        '${falta.length == 1 ? "falta" : "faltan"} '
                        '${_enumerar(falta)}.',
            ),
          ),
        ],
      ),
    );
  }

  static String _enumerar(List<String> partes) => partes.length == 1
      ? partes.single
      : '${partes.take(partes.length - 1).join(", ")} y ${partes.last}';
}

/// El bloque que se entrega, con «Copiar datos» y el ⧉ por dato.
class _DatosFiscales extends StatelessWidget {
  const _DatosFiscales({required this.expediente, required this.regimenes});

  final ExpedienteDeEmpresa expediente;
  final List<RegimenFiscal> regimenes;

  /// `601 · General de Ley Personas Morales`, o el código solo si el catálogo no
  /// llegó o si el régimen ya no está en él.
  ///
  /// **Un régimen retirado por el SAT sigue nombrándose**: la empresa que lo tenía lo
  /// conserva —es la regla del catálogo— así que lo que no se puede hacer es dejar de
  /// decirlo porque ya no se pueda elegir.
  String? get _regimen {
    final codigo = expediente.regimenFiscal;
    if (codigo == null) return null;

    for (final r in regimenes) {
      if (r.codigo == codigo) return r.etiqueta;
    }

    return codigo;
  }

  @override
  Widget build(BuildContext context) {
    final direccion = expediente.direccion;

    final lineas = direccion == null
        ? const <String>[]
        : lineasDeDomicilioFiscal(
            calle: direccion.calle,
            numeroExterior: direccion.numeroExterior,
            colonia: direccion.colonia,
            municipio: direccion.municipio,
            estado: direccion.estado,
            codigoPostal: direccion.codigoPostal,
            numeroInterior: direccion.numeroInterior,
            ciudad: direccion.ciudad,
            pais: direccion.pais,
          );

    return RisegFormSection(
      title: 'Datos fiscales',
      description: 'Lo que necesita quien va a facturarte.',
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: RisegButton(
            label: 'Copiar datos',
            icon: Icons.copy_all_outlined,
            variant: RisegButtonVariant.secondary,
            size: RisegButtonSize.compact,
            onPressed: () => _copiar(
              context,
              _bloqueCompleto(lineas),
              'Datos fiscales copiados.',
            ),
          ),
        ),
        _Dato(
          etiqueta: 'Razón social',
          valor: expediente.razonSocial,
          onCopiar: _copiar,
        ),
        _Dato(etiqueta: 'RFC', valor: expediente.rfc, onCopiar: _copiar),
        // EL CÓDIGO **Y** LA DESCRIPCIÓN, y el ⧉ copia los dos: quien recibe esto va
        // a pegarlo en una factura, y ahí hace falta el código; pero quien lo lee
        // necesita saber cuál es.
        _Dato(etiqueta: 'Régimen fiscal', valor: _regimen, onCopiar: _copiar),
        _Dato(
          etiqueta: 'Domicilio fiscal',
          valor: lineas.isEmpty ? null : lineas.join('\n'),
          onCopiar: _copiar,
        ),
      ],
    );
  }

  /// El bloque entero, **con el mismo orden y el mismo formato que la pantalla**.
  String _bloqueCompleto(List<String> lineasDelDomicilio) => [
    if (expediente.razonSocial case final v?) v,
    if (expediente.rfc case final v?) 'RFC: $v',
    // EL MISMO TEXTO QUE LA PANTALLA, con código y descripción: el bloque que se pega
    // en un correo tiene que decir lo mismo que lo que se estaba mirando.
    if (_regimen case final v?) 'Régimen fiscal: $v',
    ...lineasDelDomicilio,
  ].join('\n');

  static void _copiar(BuildContext context, String texto, String aviso) {
    Clipboard.setData(ClipboardData(text: texto));
    RisegFeedback.showSuccess(context, aviso);
  }
}

/// Un dato con su ⧉.
///
/// **El ⧉ por dato era un requisito ya anotado** —«Ícono por dato en la tarjeta de la
/// empresa → con el expediente de Empresa»—: el escritorio sólo tenía el bloque
/// completo, y pegar un RFC obligaba a pegar los cinco renglones y borrar cuatro.
class _Dato extends StatelessWidget {
  const _Dato({
    required this.etiqueta,
    required this.valor,
    required this.onCopiar,
  });

  final String etiqueta;
  final String? valor;
  final void Function(BuildContext, String, String) onCopiar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texto = valor;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              etiqueta,
              style: AppTypography.caption.copyWith(color: colors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              // VACÍO SE DICE, no se deja en blanco: un hueco se lee como un fallo de
              // carga y no como un dato que nadie capturó.
              texto ?? 'Sin capturar',
              style: AppTypography.body.copyWith(
                color: texto == null ? colors.textDisabled : colors.textPrimary,
              ),
            ),
          ),

          // SIN VALOR NO HAY BOTÓN: copiar «Sin capturar» no le sirve a nadie.
          if (texto != null)
            IconButton(
              tooltip: 'Copiar $etiqueta',
              icon: const Icon(Icons.copy_outlined, size: 16),
              onPressed: () => onCopiar(context, texto, '$etiqueta copiado.'),
            ),
        ],
      ),
    );
  }
}

class _Contacto extends StatelessWidget {
  const _Contacto({required this.contacto});

  final Contacto contacto;

  @override
  Widget build(BuildContext context) => RisegFormSection(
    title: 'Contacto',
    children: [
      _Dato(
        etiqueta: 'Teléfono',
        valor: contacto.telefono,
        onCopiar: _DatosFiscales._copiar,
      ),
      _Dato(
        etiqueta: 'Correo',
        valor: contacto.correo,
        onCopiar: _DatosFiscales._copiar,
      ),
      _Dato(
        etiqueta: 'Sitio web',
        valor: contacto.sitio,
        onCopiar: _DatosFiscales._copiar,
      ),
    ],
  );
}

class _RepresentanteYEslogan extends StatelessWidget {
  const _RepresentanteYEslogan({required this.expediente});

  final ExpedienteDeEmpresa expediente;

  @override
  Widget build(BuildContext context) => RisegFormSection(
    title: 'Representante legal y eslogan',
    children: [
      _Dato(
        etiqueta: 'Representante',
        valor: expediente.representanteLegal,
        onCopiar: _DatosFiscales._copiar,
      ),
      _Dato(
        etiqueta: 'Eslogan',
        valor: expediente.eslogan,
        onCopiar: _DatosFiscales._copiar,
      ),
    ],
  );
}
