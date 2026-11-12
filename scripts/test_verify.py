"""Black-box checks for verifier failures using an inert Lake substitute."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


VERIFIER = Path(__file__).resolve().with_name("verify.sh")


class VerifyFailurePropagationTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory(prefix="verify-controls-")
        self.addCleanup(self.temporary_directory.cleanup)
        self.project = Path(self.temporary_directory.name)
        self.lakefile = self.project / "lakefile.toml"
        self.lakefile.write_text('name = "verifier-control"\n', encoding="utf-8")
        self.source = self.project / "Check.lean"
        self.source.write_text(
            "/-\n"
            "Copyright (c) 2026 Test Authors. All rights reserved.\n"
            "-/\n"
            "/-! Minimal verifier control. -/\n",
            encoding="utf-8",
        )
        self.calls = self.project / "lake-calls"
        binary_directory = self.project / "bin"
        binary_directory.mkdir()
        fake_lake = binary_directory / "lake"
        fake_lake.write_text(
            "#!/bin/sh\n"
            'printf "%s\\n" "$*" >> "$VERIFY_CONTROL_CALLS"\n'
            'printf "%s\\n" "$VERIFY_CONTROL_OUTPUT"\n'
            'exit "$VERIFY_CONTROL_STATUS"\n',
            encoding="utf-8",
        )
        fake_lake.chmod(0o755)
        self.environment = {
            **os.environ,
            "PATH": str(binary_directory) + os.pathsep + os.environ.get("PATH", ""),
            "VERIFY_CONTROL_CALLS": str(self.calls),
        }

    def run_verifier(self, *, compiler_status=0, diagnostic=""):
        return subprocess.run(
            ["bash", str(VERIFIER), "--lean", str(self.source)],
            cwd=self.project,
            env={
                **self.environment,
                "VERIFY_CONTROL_STATUS": str(compiler_status),
                "VERIFY_CONTROL_OUTPUT": diagnostic,
            },
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )

    def assert_lake_was_called(self):
        self.assertTrue(self.calls.exists(), "the verifier did not invoke the Lake substitute")
        self.assertTrue(self.calls.read_text(encoding="utf-8").startswith("env lean "))

    def test_clean_output_passes(self):
        result = self.run_verifier()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_lake_was_called()

    def test_nonzero_exit_fails_without_error_diagnostic(self):
        result = self.run_verifier(compiler_status=37)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("Lean exited with status 37", result.stderr)
        self.assert_lake_was_called()

    def test_file_prefixed_error_fails_even_with_zero_exit(self):
        diagnostic = f"{self.source}:5:0: error: verifier control failure"
        result = self.run_verifier(diagnostic=diagnostic)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(diagnostic, result.stderr)
        self.assert_lake_was_called()

    def test_sorry_diagnostic_fails(self):
        result = self.run_verifier(
            diagnostic=f"{self.source}:5:0: warning: declaration uses 'sorry'"
        )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("contains sorry", result.stderr)
        self.assert_lake_was_called()

    def test_missing_project_fails_before_invoking_lake(self):
        self.lakefile.unlink()
        result = self.run_verifier()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("no lakefile found", result.stderr)
        self.assertFalse(self.calls.exists(), "Lake must not run without a project")


if __name__ == "__main__":
    unittest.main()
