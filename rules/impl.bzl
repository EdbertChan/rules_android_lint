"""Rule implementation for Android Lint
"""

load(
    ":collect_aar_outputs_aspect.bzl",
    _AndroidLintAARInfo = "AndroidLintAARInfo",
)
load(
    ":providers.bzl",
    _AndroidLintResultsInfo = "AndroidLintResultsInfo",
)
load(
    ":utils.bzl",
    _ANDROID_LINT_TOOLCHAIN_TYPE = "ANDROID_LINT_TOOLCHAIN_TYPE",
    _utils = "utils",
)

def _run_android_lint(
        ctx,
        android_lint,
        module_name,
        output,
        html_output,
        srcs,
        deps,
        resource_files,
        manifest,
        compile_sdk_version,
        java_language_level,
        kotlin_language_level,
        baseline,
        config,
        warnings_as_errors,
        custom_rules,
        disable_checks,
        enable_checks,
        autofix,
        regenerate,
        android_lint_enable_check_dependencies,
        android_lint_skip_bytecode_verifier):
    """Constructs the Android Lint actions

    Args:
        ctx: The target context
        android_lint: The Android Lint binary to use
        module_name: The name of the module
        output: The output file
        srcs: The source files
        deps: Depset of aars and jars to include on the classpath
        resource_files: The Android resource files
        manifest: The Android manifest file
        compile_sdk_version: The Android compile SDK version
        java_language_level: The Java language level
        kotlin_language_level: The Kotlin language level
        baseline: The Android Lint baseline file
        config: The Android Lint config file
        warnings_as_errors: Whether to treat warnings as errors
        custom_rules: List of jars containing the custom rules
        disable_checks: List of additional checks to disable
        enable_checks: List of additional checks to enable
        autofix: Whether to autofix (This is a no-op feature right now)
        regenerate: Whether to regenerate the baseline files
        android_lint_enable_check_dependencies: Enables dependency checking during analysis
        android_lint_skip_bytecode_verifier: Disables bytecode verification
    """
    inputs = []
    outputs = [output, html_output]

    args = ctx.actions.args()
    args.set_param_file_format("multiline")
    args.use_param_file("@%s", use_always = True)

    args.add("--android-lint-cli-tool", android_lint)
    inputs.append(android_lint)
    args.add("--label", "{}".format(module_name))
    for src in _utils.list_or_depset_to_list(srcs):
        args.add("--src", src)
        inputs.append(src)
    for resource_file in _utils.list_or_depset_to_list(resource_files):
        args.add("--resource", resource_file)
        inputs.append(resource_file)
    if manifest:
        args.add("--android-manifest", manifest)
        inputs.append(manifest)
    if baseline:
        args.add("--baseline-file", baseline)
        if not regenerate:
            inputs.append(baseline)
    if regenerate:
        args.add("--regenerate-baseline-files")
    if config:
        args.add("--config-file", config)
        inputs.append(config)
    if warnings_as_errors:
        args.add("--warnings-as-errors")
    for custom_rule in _utils.list_or_depset_to_list(custom_rules):
        args.add("--custom-rule", custom_rule)
        inputs.append(custom_rule)
    if autofix == True:
        args.add("--autofix")
    for check in disable_checks:
        args.add("--disable-check", check)
    for check in enable_checks:
        args.add("--enable-check", check)
    for dep in _utils.list_or_depset_to_list(deps):
        # TODO: Upstream this. There is a bug where Android libraries can be dependencies and therefore their
        # AndroidManifest.xml can be added
        if not dep.path.endswith(".aar") and not dep.path.endswith(".jar"):
            continue
        args.add("--classpath", dep)
        inputs.append(dep)
    if android_lint_enable_check_dependencies:
        args.add("--enable-check-dependencies")

    # Declare the output file
    args.add("--output", output)
    outputs.append(output)

    args.add("--html-output", html_output)
    outputs.append(html_output)

    if regenerate:
        outputs.append(baseline)

    toolchain = _utils.get_android_lint_toolchain(ctx)
    if toolchain.android_home != None:
        args.add("--android-home", toolchain.android_home.label.workspace_root)
    else:
        print("WARNING: No android-home has been specified! Some linters will be omitted!")

    ctx.actions.run(
        mnemonic = "AndroidLint",
        inputs = inputs,
        outputs = outputs,
        executable = ctx.executable._lint_wrapper,
        progress_message = "Running Android Lint {}".format(str(ctx.label)),
        arguments = [args],
        tools = [ctx.executable._lint_wrapper],
        toolchain = _ANDROID_LINT_TOOLCHAIN_TYPE,
        execution_requirements = {
            "supports-workers": "1",
            "supports-multiplex-workers": "1",
            "requires-worker-protocol": "json",
        },
        env = {
            # https://googlesamples.github.io/android-custom-lint-rules/usage/variables.md.html
            "ANDROID_LINT_SKIP_BYTECODE_VERIFIER": ("true" if android_lint_skip_bytecode_verifier else "false"),
            # https://stackoverflow.com/questions/30511439/java-lang-outofmemoryerror-compressed-class-space
            # This is for Uber only. Because of the massive size that we run for classes in compilation, we will
            # breach the limits for compilation space size. We instead decide to use heap space since many of the
            # classes loaded like with the lint jar are commonly shared between actions.
            # If you need to debug what is going on, use -Xlog:gc* -Xlog:class+unload=info -Xlog:class+load=info
            "JVM_FLAGS":"-XX:-UseCompressedClassPointers"
        },
    )

def _get_module_name(ctx):
    """Extracts the module name from the target

    This module name will be embedded in the Android Lint project configuration.

    Args:
        ctx: The target context

    Returns:
        A string representing the module name
    """
    path = ctx.build_file_path.split("BUILD")[0].replace("/", "_").replace("-", "_").replace(".", "_")
    name = ctx.attr.name
    if path:
        return "%s_%s" % (path.replace("/", "_").replace("-", "_"), ctx.attr.name)
    return name

def process_android_lint_issues(ctx, regenerate):
    """Runs Android Lint for the given target

    Args:
        ctx: The target context
        regenerate: Whether to regenerate the baseline files

    Returns:
        A struct containing the output file and the providers
    """

    # Append the Android manifest file. Lint requires that the input manifest files be named
    # exactly `AndroidManifest.xml`.
    manifest = ctx.file.manifest
    if manifest and manifest.basename != "AndroidManifest.xml":
        manifest = ctx.actions.declare_file("AndroidManifest.xml")
        ctx.actions.symlink(output = manifest, target_file = ctx.file.manifest)

    # Collect the transitive classpath jars to run lint against.
    deps = []
    for dep in ctx.attr.deps:
        if JavaInfo in dep:
            deps.append(dep[JavaInfo].compile_jars)
        if AndroidLibraryResourceClassJarProvider in dep:
            deps.append(dep[AndroidLibraryResourceClassJarProvider].jars)
        if AndroidLibraryAarInfo in dep:
            deps.append(dep[AndroidLibraryAarInfo].transitive_aar_artifacts)
        if _AndroidLintAARInfo in dep:
            deps.append(dep[_AndroidLintAARInfo].aars)

    # Append the compiled R files for our self
    if ctx.attr.lib and AndroidLibraryResourceClassJarProvider in ctx.attr.lib:
        deps.append(ctx.attr.lib[AndroidLibraryResourceClassJarProvider].jars)

    config = None
    if ctx.attr.android_lint_config:
        config = _utils.only(_utils.list_or_depset_to_list(ctx.attr.android_lint_config.files))
    elif _utils.get_android_lint_toolchain(ctx).android_lint_config:
        config = _utils.only(
            _utils.list_or_depset_to_list(_utils.get_android_lint_toolchain(ctx).android_lint_config.files),
        )

    output = ctx.actions.declare_file("{}.xml".format(ctx.label.name))
    html_output = ctx.actions.declare_file("{}.html".format(ctx.label.name))
    baseline = ctx.actions.declare_file("{}_baseline.xml".format(ctx.label.name)) if regenerate else getattr(ctx.file, "baseline", None)
    _run_android_lint(
        ctx,
        android_lint = _utils.only(_utils.list_or_depset_to_list(_utils.get_android_lint_toolchain(ctx).android_lint.files)),
        module_name = _get_module_name(ctx),
        output = output,
        html_output = html_output,
        srcs = ctx.files.srcs,
        deps = depset(transitive = deps),
        resource_files = ctx.files.resource_files,
        manifest = manifest,
        compile_sdk_version = _utils.get_android_lint_toolchain(ctx).compile_sdk_version,
        java_language_level = _utils.get_android_lint_toolchain(ctx).java_language_level,
        kotlin_language_level = _utils.get_android_lint_toolchain(ctx).kotlin_language_level,
        baseline = baseline,
        config = config,
        warnings_as_errors = ctx.attr.warnings_as_errors,
        custom_rules = ctx.files.custom_rules,
        disable_checks = ctx.attr.disable_checks,
        enable_checks = ctx.attr.enable_checks,
        autofix = ctx.attr.autofix,
        regenerate = regenerate,
        android_lint_enable_check_dependencies = _utils.get_android_lint_toolchain(ctx).android_lint_enable_check_dependencies,
        android_lint_skip_bytecode_verifier = _utils.get_android_lint_toolchain(ctx).android_lint_skip_bytecode_verifier,
    )

    return struct(
        output = output,
        html_output = html_output,
        providers = [
            _AndroidLintResultsInfo(
                output = output,
                html_output = html_output
            ),
        ],
    )
