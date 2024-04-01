package com.rules.android.lint.cli

import com.rules.android.lint.worker.Worker
import java.io.PrintStream
import java.nio.file.Files
import kotlin.system.exitProcess

object AndroidLintAction {

  @JvmStatic
  fun main(args: Array<String>) {
    val worker = Worker.fromArgs(args, AndroidLintExecutor())
    val exitCode = worker.processRequests()
    exitProcess(exitCode)
  }

  private class AndroidLintExecutor : Worker.WorkRequestCallback {
    override fun processWorkRequest(args: List<String>, printStream: PrintStream): Int {
      val workingDirectory = Files.createTempDirectory("rules")

      val prior_out = System.out
      try {
        val runner = AndroidLintRunner()
        val parsedArgs = AndroidLintActionArgs.parseArgs(args)
        System.setOut(printStream)
        return runner.runAndroidLint(parsedArgs, workingDirectory)
      } catch (exception: Exception) {
        exception.printStackTrace()
        exception.printStackTrace(printStream)
        return 1
      } finally {
        System.setOut(prior_out)
        try {
          workingDirectory.toFile().deleteRecursively()
        } catch (e: Exception) {
          e.printStackTrace()
        }
      }
    }
  }
}
