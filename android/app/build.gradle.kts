plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// The release workflow stamps Desktop's manifest before all platform builds.
val appVersion = providers.gradleProperty("releaseVersion").orElse(provider {
    Regex("""(?m)^version = "([^"]+)"$""")
        .find(rootProject.file("../desktop/moon.mod").readText())
        ?.groupValues?.get(1) ?: error("Desktop version is missing")
}).get()
val versionParts = Regex("""(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]?)\.(0|[1-9][0-9]?)""")
    .matchEntire(appVersion)?.groupValues?.drop(1)?.map(String::toInt)
    ?: error("Android version must be major.minor.patch (major <= 9999, minor/patch <= 99)")
// +1 keeps 0.0.0 positive. This ordering agrees with the release version.
val appVersionCode = versionParts[0] * 10_000 + versionParts[1] * 100 + versionParts[2] + 1

android {
    namespace = "com.moonbit.openseek"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.moonbit.openseek.connect"
        minSdk = 26
        targetSdk = 36
        versionCode = appVersionCode
        versionName = appVersion
    }
    signingConfigs {
        create("release") {
            providers.environmentVariable("OPENSEEK_ANDROID_KEYSTORE_PATH").orNull?.let {
                storeFile = file(it)
            }
            storePassword = providers.environmentVariable("OPENSEEK_ANDROID_KEYSTORE_PASSWORD").orNull
            keyAlias = providers.environmentVariable("OPENSEEK_ANDROID_KEY_ALIAS").orNull
            keyPassword = providers.environmentVariable("OPENSEEK_ANDROID_KEY_PASSWORD").orNull
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
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
            .replace("</head>", "<link rel=\"stylesheet\" href=\"/console/android/conversation.css\" /></head>")
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
