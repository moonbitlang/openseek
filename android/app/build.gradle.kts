plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.moonbit.openseek"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.moonbit.openseek.connect"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
    }
    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
    }
    buildFeatures { buildConfig = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("generated/consoleAssets"))
}

val bundleConsole by tasks.registering(Sync::class) {
    val bundle = rootProject.layout.projectDirectory.dir("../desktop/dist/browser")
    from(bundle)
    from(rootProject.layout.projectDirectory.file("conversation.css"))
    into(layout.buildDirectory.dir("generated/consoleAssets"))
    doLast {
        val entry = destinationDir.resolve("index.html")
        entry.writeText(entry.readText()
            .replace("</head>", "<link rel=\"stylesheet\" href=\"conversation.css\" /></head>")
            .replace("<body>", "<body class=\"android-connect\">"))
    }
    doFirst {
        check(bundle.file("frontend.js").asFile.isFile && bundle.file("index.html").asFile.isFile) {
            "Build the shared frontend first: node desktop/package/build.mjs browser --release"
        }
    }
}
tasks.named("preBuild") { dependsOn(bundleConsole) }

dependencies {
    implementation("androidx.activity:activity-ktx:1.9.3")
    implementation("androidx.webkit:webkit:1.15.0")
    implementation("androidx.browser:browser:1.10.0")
    testImplementation("junit:junit:4.13.2")
}
