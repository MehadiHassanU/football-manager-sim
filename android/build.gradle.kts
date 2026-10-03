allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// The transitive `jni` plugin (via path_provider_android) pins
// `ndkVersion flutter.ndkVersion`, which resolves to Flutter's default NDK
// (28.2.13676358). That NDK is not installed on this machine and its
// auto-download fails, so force every plugin project onto the NDK that IS
// installed (see android/app/build.gradle.kts). Safe because NDK releases
// are backward compatible for compiling native plugin code.
subprojects {
    val applyNdkOverride: (org.gradle.api.Project) -> Unit = { p ->
        p.extensions.findByName("android")?.let { ext ->
            try {
                ext.javaClass
                    .getMethod("setNdkVersion", String::class.java)
                    .invoke(ext, "30.0.16248370")
            } catch (_: NoSuchMethodException) {
                // Project has no ndkVersion property (pure-Dart plugins).
            } catch (_: Exception) {
                // Never let the override break configuration.
            }
        }
    }
    // :app is force-evaluated by evaluationDependsOn above, so it is already
    // executed here; every other subproject is still pending.
    if (state.executed) {
        applyNdkOverride(this)
    } else {
        afterEvaluate { applyNdkOverride(this) }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
