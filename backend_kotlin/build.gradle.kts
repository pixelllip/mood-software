plugins {
    kotlin("jvm") version "2.1.20"
    kotlin("plugin.serialization") version "2.1.20"
    id("io.ktor.plugin") version "3.1.2"
    application
}

application {
    mainClass.set("com.aegis.backend.ApplicationKt")
}

ktor {
    fatJar {
        archiveFileName.set("ai_agent_backend.jar")
    }
}

dependencies {
    // Ktor Server
    implementation("io.ktor:ktor-server-core:3.1.2")
    implementation("io.ktor:ktor-server-netty:3.1.2")
    implementation("io.ktor:ktor-server-content-negotiation:3.1.2")
    implementation("io.ktor:ktor-serialization-kotlinx-json:3.1.2")
    implementation("io.ktor:ktor-server-cors:3.1.2")
    implementation("io.ktor:ktor-server-status-pages:3.1.2")

    // Kotlinx Serialization
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.1")

    // OkHttp for HTTP calls
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:okhttp-sse:4.12.0")

    // JSON processing
    implementation("org.json:json:20231013")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.1")

    // Logging
    implementation("ch.qos.logback:logback-classic:1.5.18")

    // (kotlinx-io-core 不存在此版本，已移除)

    // Searching in log
    implementation("org.apache.lucene:lucene-core:9.9.1")
    implementation("org.apache.lucene:lucene-queryparser:9.9.1")
    implementation("org.apache.lucene:lucene-analysis-common:9.9.1")
    implementation("com.google.code.gson:gson:2.10.1")
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

tasks.withType<JavaCompile> {
    options.release.set(17)
}

tasks.withType<JavaExec> {
    systemProperty("file.encoding", "UTF-8")
    systemProperty("stdout.encoding", "UTF-8")
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile> {
    kotlinOptions {
        jvmTarget = "17"
        freeCompilerArgs = listOf("-Xjvm-default=all")
    }
}
