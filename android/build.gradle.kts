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

// The FFmpeg plugin hardcodes the "full-gpl" native package, which carries
// every external codec ever built for it and pushes the APK past 200 MB.
// We only ever transcode into H.264 + AAC, so "min-gpl" (x264 plus FFmpeg's
// own decoders and AAC encoder) covers the job at a fraction of the size.
subprojects {
    configurations.all {
        resolutionStrategy.dependencySubstitution {
            substitute(module("com.antonkarpenko:ffmpeg-kit-full-gpl"))
                .using(module("com.antonkarpenko:ffmpeg-kit-min-gpl:2.2.1"))
                .because("full-gpl ships codecs this app never uses")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
