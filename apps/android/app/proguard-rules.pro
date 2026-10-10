# ML Kit discovers these registrars from manifest metadata and constructs them
# through reflection. Keep their names and no-argument constructors in R8 builds.
-keep class com.google.mlkit.** implements com.google.firebase.components.ComponentRegistrar {
    public <init>();
}
