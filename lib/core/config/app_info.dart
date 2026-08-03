/// Versión de la aplicación, mantenida en sincronía manual con el campo
/// `version` de `pubspec.yaml`.
///
/// Se define como constante (en vez de leerla en tiempo de ejecución con un
/// paquete adicional) porque, en esta etapa, no hay una necesidad real que
/// lo justifique — se reconsiderará si en el futuro hace falta leerla
/// dinámicamente (por ejemplo, para mostrarla en una pantalla "Acerca de").
const String kAppVersion = '1.0.0+1';
