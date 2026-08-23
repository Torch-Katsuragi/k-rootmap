allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// flutter_bluetooth_serialのnamespaceエラーを解決するための設定
subprojects {
    plugins.withId("com.android.library") {
        configure<com.android.build.gradle.LibraryExtension> {
            if (namespace == null) {
                namespace = project.group?.toString() ?: "com.example.${project.name}"
            }
        }
    }
    plugins.withId("com.android.application") {
        configure<com.android.build.gradle.AppExtension> {
            if (namespace == null) {
                namespace = project.group?.toString() ?: "com.example.${project.name}"
            }
        }
    }
}

// flutter_bluetooth_serial等の古いプラグインが compileSdk < 31 のままだと
// androidx.core の android:attr/lStar 解決に失敗するため、31未満なら引き上げる
subprojects {
    afterEvaluate {
        extensions.findByType<com.android.build.gradle.LibraryExtension>()?.apply {
            if ((compileSdk ?: 0) < 31) {
                compileSdk = 35
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
