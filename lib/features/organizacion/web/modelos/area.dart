/// Un área, tal como la devuelve la API.
///
/// **Es un modelo PLANO y propio de la web, y eso merece explicación.** La interfaz
/// de dominio del escritorio —`AreaRepository`— habla `AreaData`, una clase
/// **generada por Drift**, y su archivo importa `dart:io`. Implementarla desde la web
/// arrastraría todo eso y la build fallaría.
///
/// El plan de mudanza decía «cambiar el repositorio de Drift por uno de HTTP detrás
/// de la MISMA interfaz de dominio». No se sostiene: **la capa de dominio de este
/// producto no es libre de Drift, habla sus tipos generados.**
///
/// ⏳ **La deuda que esto crea se cierra sola.** Durante la mudanza hay dos modelos
/// de Área, pero el de Drift está **congelado** —el escritorio ya no se desarrolla—
/// así que no hay que mantener nada en paralelo: **se jubila cuando la mudanza
/// termine**. Lo que NO se debe hacer es «unificarlos» a medio camino.
class Area {
  const Area({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.activa,
  });

  /// Lee la respuesta de `GET /companies/{id}/areas`.
  ///
  /// **`activa` se DERIVA del estado**, no se guarda aparte: el motor manda
  /// `'activa'` o `'inactiva'` y aquí se convierte en la pregunta que la pantalla
  /// hace de verdad. Dos campos para un solo hecho acabarían discrepando.
  factory Area.deJson(Map<String, dynamic> json) => Area(
    id: json['id'] as String,
    codigo: json['code'] as String,
    nombre: json['name'] as String,
    activa: json['status'] == 'activa',
  );

  final String id;

  /// El código que **escribe el cliente** —`OPERACIONES`—, no un folio generado.
  ///
  /// Se muestra pequeño y en gris debajo del nombre: es suyo y lo reconoce, pero lo
  /// que identifica el área en una lista es el nombre.
  final String codigo;

  final String nombre;

  /// ¿Se puede usar en el sistema? Una área inactiva no aparece en los selectores.
  final bool activa;
}
