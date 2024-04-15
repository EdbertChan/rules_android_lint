"""Declare runtime dependencies
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", _http_archive = "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@rules_jvm_external//:defs.bzl", "maven_install")

def _maybe_http_archive(name, **kwargs):
    maybe(_http_archive, name = name, **kwargs)

def rules_android_lint_dependencies():
    # The minimal version of bazel_skylib we require
    _maybe_http_archive(
        name = "bazel_skylib",
        sha256 = "74d544d96f4a5bb630d465ca8bbcfe231e3594e5aae57e1edbf17a6eb3ca2506",
        urls = [
            "https://github.com/bazelbuild/bazel-skylib/releases/download/1.3.0/bazel-skylib-1.3.0.tar.gz",
            "https://mirror.bazel.build/github.com/bazelbuild/bazel-skylib/releases/download/1.3.0/bazel-skylib-1.3.0.tar.gz",
        ],
    )

# buildifier: disable=unnamed-macro
def android_lint_register_toolchains(register = True):
    """Convenience macro for users which does typical setup.

    Args:
        register: Whether to register the toolchain. If False, the user must
            register it themselves.
    """
    native.register_toolchains("//toolchains:android_lint_default_toolchain")

def android_lint_register_java_repositories():
    rules_java_version = "7.0.6"
    rules_java_sha = "e81e9deaae0d9d99ef3dd5f6c1b32338447fe16d5564155531ea4eb7ef38854b"
    _http_archive(
        name = "rules_java",
        urls = [
            "https://github.com/bazelbuild/rules_java/releases/download/%s/rules_java-%s.tar.gz" % (rules_java_version, rules_java_version),
        ],
        sha256 = rules_java_sha,
    )

def android_lint_register_repositories(lint_version = "27.2.2"):
    rules_kotlin_version = "1.9.0"
    rules_kotlin_sha = "5766f1e599acf551aa56f49dab9ab9108269b03c557496c54acaf41f98e2b8d6"
    _http_archive(
        name = "rules_kotlin",
        urls = ["https://github.com/bazelbuild/rules_kotlin/releases/download/v%s/rules_kotlin-v%s.tar.gz" % (rules_kotlin_version, rules_kotlin_version)],
        sha256 = rules_kotlin_sha,
    )

    LINT_VERSION = lint_version

    maven_install(
        name = "rules_android_lint_deps",
        artifacts = [
            # Testing
            "org.assertj:assertj-core:3.24.2",
            "junit:junit:4.13.2",
            # Worker Dependencies
            # TODO(bencodes) Remove these and use the worker impl. that Bazel defines internally
            "com.squareup.moshi:moshi:1.15.0",
            "com.squareup.moshi:moshi-kotlin:1.15.0",
            "com.squareup.okio:okio-jvm:3.6.0",
            "io.reactivex.rxjava3:rxjava:3.1.8",
            "com.xenomachina:kotlin-argparser:2.0.7",
            # Lint Dependencies
            "com.android.tools.lint:lint:%s" % LINT_VERSION,
            "com.android.tools.lint:lint-api:%s" % LINT_VERSION,
            "com.android.tools.lint:lint-checks:%s" % LINT_VERSION,
            "com.android.tools.lint:lint-model:%s" % LINT_VERSION,
        ],
        repositories = [
            "https://maven.google.com",
            "https://repo1.maven.org/maven2",
        ],
    )
