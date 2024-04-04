package com.rules.android.lint.cli

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.io.path.absolutePathString
import kotlin.io.path.exists
import kotlin.io.path.extension
import kotlin.io.path.isRegularFile
import kotlin.io.path.name
import kotlin.io.path.pathString
import kotlin.io.path.readText
import kotlin.io.path.writeText

internal class AndroidLintRunner {

  internal fun runAndroidLint(
    args: AndroidLintActionArgs,
    workingDirectory: Path,
  ): Int {
    // Create the input baseline file. This is either a copy of the existing baseline
    // or a new temp one that can be written to
    val baselineFile = workingDirectory.resolve("${args.label}_lint_baseline")
    if (!args.regenerateBaselineFile && args.baselineFile != null) {
      Files.copy(args.baselineFile!!, baselineFile)
    }

    // Split the aars and jars
    val aars = args.classpath.filter { it.extension == "aar" }
    val jars = args.classpath.filter { it.extension == "jar" }
    require(aars.size + jars.size == args.classpath.size) { "Error: Classpath size mismatch" }

    // Unarchive the AARs to avoid lint having to do this work. This also prevents some
    // concurrency issues inside of Lint when multiplex workers are enabled
    val unpackedAars = unpackAars(aars, workingDirectory.resolve("aars"))

    // Collect the custom lint rules from the unpacked aars
    val aarLintRuleJars = unpackedAars
      .asSequence()
      .map { it.first.resolve("lint.jar") }
      .filter { it.exists() && it.isRegularFile() }

    // Create the project configuration file for lint
    val projectFile = workingDirectory.resolve("${args.label}_project_config.xml")
    Files.createFile(projectFile)
    projectFile.writeText(
      createProjectXMLString(
        moduleName = args.label,
        srcs = args.srcs.sortedDescending(),
        resources = args.resources.sortedDescending(),
        androidManifest = args.androidManifest,
        classpathJars = jars.sortedDescending(),
        classpathAars = emptyList(),
        classpathExtractedAarDirectories = unpackedAars,
        customLintChecks = (args.customChecks + aarLintRuleJars).sortedDescending(),
      ),
    )

    // Run Android Lint
    val androidCacheFolder = workingDirectory.resolve("android-cache")
    Files.createDirectory(androidCacheFolder)
    val invoker = AndroidLintCliInvoker.createUsingJars(jars = arrayOf(args.androidLintCliTool))
    val exitCode = invokeAndroidLintCLI(
      invoker = invoker,
      actionArgs = args,
      projectFilePath = projectFile,
      baselineFilePath = baselineFile,
      cacheDirectoryPath = androidCacheFolder,
    )

    // Pure hacks to strip the relative paths and exec roots out of the file
    // locations. Lint doesn't offer any way to disable this and if we parse-and-transform the
    // baseline using a proper XML parser we can't easily preserve the baseline formatting.
    val sanitizedContent = args.output.readText()
      .run { AndroidLintBaselineSanitizer.sanitize(this) }
    args.output.writeText(sanitizedContent)

    return when (exitCode) {
      AndroidLintCliInvoker.ERRNO_SUCCESS,
      AndroidLintCliInvoker.ERRNO_CREATED_BASELINE,
      -> 0

      else -> exitCode
    }
  }

  private fun invokeAndroidLintCLI(
    invoker: AndroidLintCliInvoker,
    actionArgs: AndroidLintActionArgs,
    projectFilePath: Path,
    baselineFilePath: Path,
    cacheDirectoryPath: Path,
  ): Int {
    val args = mutableListOf(
      "--project",
      projectFilePath.pathString,
      "--xml",
      actionArgs.output.pathString,
      "--html",
      actionArgs.htmlOutput.pathString,
      "--exitcode",
      "--fullpath",
    )
    if (actionArgs.warningsAsErrors) {
      args.add("-Werror")
    } else {
      args.add("--nowarn")
    }
    if (actionArgs.config != null) {
      args.add("--config")
      args.add(actionArgs.config!!.pathString)
    }
    if (actionArgs.enableChecks.isNotEmpty()) {
      args.add("--enable")
      args.add(actionArgs.enableChecks.joinToString(","))
    }
    if (actionArgs.disableChecks.isNotEmpty()) {
      args.add("--disable")
      args.add(actionArgs.disableChecks.joinToString(","))
    }

    if (actionArgs.androidHome?.isNotEmpty() != null) {
      var androidHomePath =
        Paths.get(System.getenv("PWD"), actionArgs.androidHome).absolutePathString()
      args.add("--sdk-home")
      args.add(androidHomePath)
    }

    invoker.setCheckDependencies(actionArgs.enableCheckDependencies)
    return invoker.invoke(args.toTypedArray())
  }

  /**
   * Takes a list of AARs and unarchives them into the provided directory
   * with this structure: ${tmpDirectory}/${aarFileName}--aar-unzipped/
   *
   * This is a necessary workaround for Lint wanting to unpack these aars into a global
   * shared directory, which causes lots of obscure concurrency issues inside of lint
   * when operating in persistent worker mode.
   */
  private fun unpackAars(
    aars: List<Path>,
    dstDirectory: Path,
    executorService: ExecutorService = Executors.newFixedThreadPool(6),
  ): List<Pair<Path, Path>> {
    val aarsToUnpack = aars.map { it to dstDirectory.resolve("${it.name}-aar-contents") }
    aarsToUnpack.forEach { (src, dst) -> unzip(src, dst) }
    executorService.awaitTermination(15, TimeUnit.SECONDS)
    return aarsToUnpack.sortedBy { it.first }
  }
}
