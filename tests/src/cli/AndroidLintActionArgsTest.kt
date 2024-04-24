package com.rules.android.lint.cli

import org.assertj.core.api.Assertions.assertThat
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.JUnit4
import java.nio.file.Paths

@RunWith(JUnit4::class)
class AndroidLintActionArgsTest {

  @Test
  fun `does parse all arguments`() {
    val parseArgs = AndroidLintActionArgs.parseArgs(
      args = listOf(
        "--label",
        "test",
        "--android-lint-cli-tool",
        "path/to/cli.jar",
        "--src",
        "path/to/Foo.kt",
        "--xml-output",
        "xml_output.xml",
        "--html-output",
        "html_output.html",
        "--resource",
        "path/to/resource/strings.xml",
        "--android-manifest",
        "AndroidManifest.xml",
        "--baseline-file",
        "lib_lint_baseline.xml",
        "--config-file",
        "lint_config.xml",
        "--custom-rule",
        "custom_rule.jar",
        "--classpath",
        "classpath.jar",
        "--classpath",
        "classpath.aar",
        "--autofix",
        "--regenerate-baseline-files",
        "--warnings-as-errors",
        "--enable-check",
        "custom-check",
        "--disable-check",
        "custom-disabled-check",
        "--compile-sdk-version",
        "1.6",
        "--java-language-level",
        "1.7",
        "--kotlin-language-level",
        "1.8",
        "--enable-check-dependencies",
      ),
    )

    assertThat(parseArgs.label).isEqualTo("test")
    assertThat(parseArgs.srcs).containsExactly(Paths.get("path/to/Foo.kt"))
    assertThat(parseArgs.xmlOutput).isEqualTo(Paths.get("xml_output.xml"))
    assertThat(parseArgs.htmlOutput).isEqualTo(Paths.get("html_output.html"))
    assertThat(parseArgs.resources).containsExactly(Paths.get("path/to/resource/strings.xml"))
    assertThat(parseArgs.baselineFile).isEqualTo(Paths.get("lib_lint_baseline.xml"))
    assertThat(parseArgs.config).isEqualTo(Paths.get("lint_config.xml"))
    assertThat(parseArgs.customChecks).containsExactly(Paths.get("custom_rule.jar"))
    assertThat(parseArgs.classpath)
      .containsExactly(Paths.get("classpath.jar"), Paths.get("classpath.aar"))
    assertThat(parseArgs.autofix).isTrue
    assertThat(parseArgs.regenerateBaselineFile).isTrue
    assertThat(parseArgs.warningsAsErrors).isTrue
    assertThat(parseArgs.enableChecks).containsExactly("custom-check")
    assertThat(parseArgs.disableChecks).containsExactly("custom-disabled-check")
    assertThat(parseArgs.compileSdkVersion).isEqualTo("1.6")
    assertThat(parseArgs.javaLanguageLevel).isEqualTo("1.7")
    assertThat(parseArgs.kotlinLanguageLevel).isEqualTo("1.8")
    assertThat(parseArgs.enableCheckDependencies).isTrue()
  }
}
