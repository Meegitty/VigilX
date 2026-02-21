import org.gradle.api.tasks.Delete
import org.gradle.api.file.Directory

// Repositories for all modules/subprojects
subprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Put build outputs in ../../build (common Flutter pattern)
val newBuildDir: Directory = rootProject.layout.buildDirectory
    .dir("../../build")
    .get()

rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    // Each subproject gets its own folder under the newBuildDir
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // Ensure :app evaluated before others if required by your setup
    project.evaluationDependsOn(":app")
}

// Clean task
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}