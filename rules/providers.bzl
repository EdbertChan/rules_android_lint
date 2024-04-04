"""Providers used by the Android Lint rules
"""

AndroidLintResultsInfo = provider(
    "Info needed to evaluate lint results",
    fields = {
        "output": "The Android Lint baseline output",
        "html_output": "The Android Lint html output",
    },
)
