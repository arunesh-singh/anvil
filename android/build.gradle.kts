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
    // Some third-party plugins (e.g. receive_sharing_intent 1.8.1) leave their
    // Java compile target at 11 while Kotlin infers 21 from the JDK, which AGP
    // rejects as "Inconsistent JVM-target". Pin both sides to 17 (matching the
    // app module) across every subproject so plugin builds stay consistent.
    // Registered before the evaluationDependsOn block below so the callback is
    // attached prior to forced evaluation.
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            val android = ext as com.android.build.gradle.BaseExtension
            // AGP 9 hard-errors when a plugin's compileSdk is below what its
            // transitive androidx deps require (e.g. onnxruntime@33 vs
            // exifinterface needing 34). Force every subproject to 36.
            android.compileSdkVersion(36)
            android.compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
        plugins.withId("org.jetbrains.kotlin.android") {
            extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension> {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                }
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
