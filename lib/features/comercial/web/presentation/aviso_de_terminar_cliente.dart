/// **EL AVISO DE TERMINAR UN CLIENTE QUE TODAVÍA TIENE SERVICIOS COBRANDO** (D-88).
///
/// ## Qué problema resuelve
///
/// Terminar un cliente **no termina sus servicios y no los toca**: no hay cascada, y eso es
/// paridad exacta con RISEG ONE —su propio código lo dice, y el inventario funcional §2.5.2
/// lo confirma—. Lo que faltaba no era el candado: era **decirlo con números antes de
/// confirmar**.
///
/// El dueño lo encontró el **26-nov-2026**, en la prueba en pantalla de C4: terminó el cliente
/// PRUEBA B teniendo **SRV-000003 Activo/Vigente con $54,000** y la pantalla no dijo nada.
///
/// 🚫 **Y NO SE ARREGLA CON UNA CASCADA, que es la decisión de fondo (aprobada el 26-nov-2026):**
/// cerrar las condiciones de un servicio **es renovar**, así que una cascada haría que **un clic
/// de estatus moviera dinero**. Tampoco con un bloqueo, que atascaría el caso legítimo de
/// limpiar un cliente que ya no se opera. Lo que falta es el aviso.
///
/// ## Por qué es una función pura y no un trozo de pantalla
///
/// El texto es lo único que hay que poder afirmar, y aquí se puede afirmar **sin montar un
/// widget ni un servidor**: las pruebas le dan los datos y leen la frase. El cargador que pide
/// los datos vive en la pantalla, y lo que no se puede equivocar —qué se dice y qué NO se dice
/// cuando falta un dato— se decide aquí.
library;

import '../modelos/cliente.dart';
import '../modelos/servicio.dart';

/// Un servicio tal como el aviso lo necesita.
///
/// **No es `ServicioEnLista`** porque le añade el dinero, que el listado no trae: el importe
/// de un servicio sale de su propio indicador. [montos] nulo significa **«no se pudo
/// consultar»** y vacío significa **«sin condiciones vigentes»**, que son dos cosas distintas
/// y el aviso las dice distinto.
class ServicioDelAviso {
  const ServicioDelAviso({
    required this.codigo,
    required this.nombre,
    required this.estatus,
    this.montos,
    this.porCerrar = const [],
  });

  final String codigo;
  final String nombre;

  /// El estatus del servicio, **ya interpretado**. Nulo si el servidor mandó uno que esta
  /// versión no conoce: entonces la fila sale sin insignia en vez de desaparecer.
  final EstatusDeServicio? estatus;

  /// El importe mensual, **una línea por moneda**.
  ///
  /// 🚫 **NO SE SUMAN LAS MONEDAS**, igual que en el encabezado: el día que un cliente tenga
  /// condiciones en dos, el aviso dirá las dos y no un total inventado.
  final List<Monto>? montos;

  /// Lo que las líneas **dadas de baja** todavía cobran, y hasta cuándo.
  final List<MontoPorCerrar> porCerrar;
}

/// **El aviso, o `null` si no hay nada que avisar.**
///
/// Tres entradas y tres silencios distintos, que es el fondo de esta función:
///
///  · [indicadores] **nulo** = no se pudieron consultar. ⚠️ **ENTONCES EL AVISO SALE Y DICE
///    QUE NO SE PUDO COMPROBAR**, nunca «no tiene servicios». *Ausencia nunca es cero*, y
///    aquí un cero sería la mentira exacta que dejaría terminar tranquilo a alguien con un
///    servicio cobrando.
///  · [indicadores] con **cero activos y cero suspendidos** = no hay nada que decir, y
///    devuelve `null`. Un aviso que sale siempre deja de leerse.
///  · [servicios] **nulo** = el listado falló. Sale la frase **con sus números** y se dice que
///    la lista no cargó: media verdad dicha es mejor que una lista vacía que parece completa.
///
/// 🔑 **LOS SUSPENDIDOS CUENTAN** —decisión del dueño del 26-nov-2026—: un suspendido
/// **puede volver a cobrar**, así que esconder el aviso cuando sólo hay suspendidos
/// escondería justo el caso que se pidió incluir.
String? avisoDeTerminarCliente({
  required IndicadoresDeCliente? indicadores,
  required List<ServicioDelAviso>? servicios,
}) {
  if (indicadores == null) {
    return 'No se pudo comprobar si este cliente tiene servicios cobrando. '
        'Terminarlo no los termina ni les quita lo que cobran.';
  }

  final activos = indicadores.serviciosActivos;
  final suspendidos = indicadores.serviciosSuspendidos;
  final total = activos + suspendidos;

  // NADA QUE AVISAR. No es lo mismo que no haber podido comprobar, y por eso este `return`
  // está DESPUÉS del de arriba y no antes.
  if (total == 0) return null;

  final renglones = <String>[_laFrase(activos, suspendidos, indicadores)];

  if (servicios == null) {
    renglones.add('No se pudo cargar la lista de esos servicios.');
    return renglones.join('\n\n');
  }

  for (final s in servicios) {
    renglones.add('  · ${_elRenglonDe(s)}');
  }

  // ⚠️ «Y N MÁS», PORQUE LA LISTA ESTÁ ACOTADA. El listado pagina y el aviso pide unos
  // pocos: sin esta línea, una lista de diez en un cliente con treinta servicios se leería
  // como la lista completa, y el aviso diría MENOS de lo que hay mientras parece exacto.
  final faltan = total - servicios.length;
  if (faltan > 0) {
    renglones.add('  y $faltan más');
  }

  return renglones.join('\n');
}

/// «Este cliente tiene 2 servicios activos y 1 suspendido por $54,000.00 MXN al mes;
/// terminarlo no los termina.»
String _laFrase(int activos, int suspendidos, IndicadoresDeCliente indicadores) {
  final cuenta = <String>[
    if (activos > 0) '$activos ${_plural(activos, 'servicio activo', 'servicios activos')}',
    if (suspendidos > 0)
      '$suspendidos ${_plural(suspendidos, 'suspendido', 'suspendidos')}',
  ].join(' y ');

  // 🚫 VACÍO NO ES $0.00: una lista de importes vacía significa que no hay condiciones
  // vigentes, y decir «$0.00» afirmaría que el servicio no cobra nada, que es otra cosa.
  //
  // ⚠️ Y LA FRASE CAMBIA DE FORMA, no sólo de palabras: «por sin condiciones vigentes» no
  // es español. Con importe se dice «por $X al mes» y sin él se dice en aposición, «, sin
  // condiciones vigentes». Lo corrigió el dueño el 26-nov-2026, leyéndolo.
  final conImporte = indicadores.importeMensual.isNotEmpty;

  final cola = conImporte
      ? ' por ${indicadores.importeMensual.map((m) => m.enPantalla).join(' y ')} al mes'
      : ', sin condiciones vigentes';

  return 'Este cliente tiene $cuenta$cola; terminarlo no los termina '
      'ni les quita lo que cobran.';
}

/// `SRV-000003 · Vigilancia nocturna — activo — $54,000.00 MXN`
String _elRenglonDe(ServicioDelAviso s) {
  final partes = <String>['${s.codigo} · ${s.nombre}'];

  // SE MARCA CUÁL ES CUÁL, que es lo que pidió el dueño: en una lista mezclada, «activo» y
  // «suspendido» cambian lo que significa la fila.
  if (s.estatus case final e?) partes.add(e.nombre.toLowerCase());

  partes.add(switch (s.montos) {
    // Nulo y vacío NO se dicen igual, ni aquí ni arriba.
    null => 'importe no consultado',
    [] => 'sin condiciones vigentes',
    final montos => montos.map((m) => m.enPantalla).join(' y '),
  });

  // EL DINERO «POR CERRAR» VA CON SU FECHA —decisión del dueño del 26-nov-2026—: es dinero
  // cierto y es dinero que SE ACABA un día, así que sumarlo al importe diría una cifra que
  // el mes que viene ya no es. `MontoPorCerrar.enPantalla` ya trae «(hasta el …)».
  // Se usa `MontoPorCerrar.enPantalla`, que YA trae «(hasta el 14/dic/2026)»: componer la
  // fecha aquí sería un segundo sitio formateando lo mismo, y el día que uno cambie el otro
  // diría la misma cifra de otra forma en la misma pantalla.
  for (final p in s.porCerrar) {
    partes.add('deja de cobrar ${p.enPantalla}');
  }

  return partes.join(' — ');
}

String _plural(int n, String uno, String varios) => n == 1 ? uno : varios;
