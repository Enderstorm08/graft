"""Exercise the shipped launchd scripts against an isolated fake power system."""

import json
import os
from pathlib import Path
import plistlib
import shlex
import signal
import subprocess
import tempfile
import time
import unittest
import uuid


class ClosedLidPowerScriptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = Path(__file__).resolve().parents[1] / "Sources/GraftMac/Services/ClosedLidPowerScripts.swift"
        build = Path(cls.enterClassContext(tempfile.TemporaryDirectory()))
        main = build / "main.swift"
        main.write_text(
            """import Foundation
let arguments = try ClosedLidPowerScripts.installArguments(
    token: UUID(uuidString: CommandLine.arguments[1])!,
    owner: Int32(CommandLine.arguments[2])!,
    deadline: Int64(CommandLine.arguments[3])!
)
let data = try JSONEncoder().encode([ClosedLidPowerScripts.authorization] + arguments)
FileHandle.standardOutput.write(data)
"""
        )
        cls.export_scripts = build / "export-scripts"
        subprocess.run(
            ["/usr/bin/swiftc", "-swift-version", "6", "-default-isolation", "MainActor",
             source, main, "-o", cls.export_scripts], check=True
        )

    def setUp(self):
        self.fixture = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.token = str(uuid.uuid4()).upper()
        deadline = str(int(time.time()) + 45)
        authorization, installer, *payload = json.loads(
            subprocess.check_output([self.export_scripts, self.token, str(os.getpid()), deadline])
        )
        self.authorization = authorization
        plist = plistlib.loads(payload[-1].encode())
        self.assertEqual(plist["KeepAlive"], {"SuccessfulExit": False})
        self.assertTrue(plist["RunAtLoad"])
        self.label = plist["Label"]

        for name in ("db", "launch", "tmp"):
            (self.fixture / name).mkdir()
        self.state = self.fixture / "db" / self.label
        self.marker = self.fixture / "tmp" / f"{self.label}-{self.token}"
        self.marker.mkdir(mode=0o700)
        self.sleep_disabled = self.fixture / "sleep-disabled"
        self.sleep_disabled.write_text("false")
        self.fail_restore = self.fixture / "fail-restore"
        self.set_power("AC", 80)

        registry = self.faux_command(
            "registry",
            """printf '<plist version="1.0"><array><dict><key>SleepDisabled</key><%s/></dict></array></plist>' "$(cat sleep-disabled)" """,
        )
        power = self.faux_command(
            "power",
            f"""case "$*" in
    '-g batt') cat battery-status ;;
    '-a disablesleep 1')
        test -f {shlex.quote(str(self.state / "restore"))} || exit 2
        printf true > sleep-disabled
        ;;
    '-a disablesleep 0')
        test ! -f fail-restore || exit 3
        printf false > sleep-disabled
        ;;
    *) exit 3 ;;
esac""",
        )
        launcher = self.faux_command("launcher", '[ "$1" = bootstrap ] && test -f "$3"')

        def isolate(script):
            substitutions = {
                "/private/var/db/": str(self.fixture / "db") + "/",
                "/private/tmp/": str(self.fixture / "tmp") + "/",
                "/Library/LaunchDaemons/": str(self.fixture / "launch") + "/",
                "/usr/bin/pmset": str(power),
                "/usr/sbin/ioreg": str(registry),
                "/bin/launchctl": str(launcher),
                "/usr/bin/id -u": "printf 0",
                "Directory:0:755": f"Directory:{os.getuid()}:755",
            }
            for original, fixture_value in substitutions.items():
                script = script.replace(original, fixture_value)
                self.assertNotIn(original, script)
            commands = "\n".join(line for line in script.splitlines() if not line.lstrip().startswith("#"))
            self.assertNotRegex(commands, r"\b(?:pmset|ioreg|launchctl)\b")
            subprocess.run(["/bin/sh", "-n"], input=script, text=True, check=True)
            return script

        self.plist_path = self.fixture / "launch" / f"{self.label}.plist"
        program = plist["ProgramArguments"]
        program[4] = isolate(program[4])
        self.installer = ["/bin/sh", "-c", isolate(installer), self.label, *payload[:-1],
                          plistlib.dumps(plist).decode()]
        self.watcher = program

    def faux_command(self, name, body):
        command = self.fixture / ("mock-" + name)
        command.write_text("#!/bin/sh\n" + body + "\n")
        command.chmod(0o700)
        return command

    def install(self):
        return subprocess.run(self.installer, cwd=self.fixture, capture_output=True, text=True, timeout=5)

    def set_power(self, source, charge):
        status = self.fixture / "battery-status.new"
        status.write_text(f"Now drawing from '{source} Power'\n -InternalBattery-0 (test) {charge}%; present: true\n")
        status.replace(self.fixture / "battery-status")

    def start_watcher(self):
        process = subprocess.Popen(self.watcher, cwd=self.fixture, start_new_session=True)

        def cleanup():
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=5)

        self.addCleanup(cleanup)
        return process

    def wait_phase(self, expected):
        limit = time.monotonic() + 8
        while time.monotonic() < limit:
            if (self.state / "status").read_text().splitlines() == [self.token, expected]:
                return
            time.sleep(0.05)
        self.fail(f"Expected {expected}, got {(self.state / 'status').read_text()!r}")

    def arm(self):
        install = self.install()
        self.assertEqual(install.returncode, 0, install.stderr)
        worker = self.start_watcher()
        self.wait_phase("active")
        self.assertEqual(self.sleep_disabled.read_text(), "true")
        self.assertTrue((self.state / "restore").is_file())
        return worker

    def assert_restored(self, worker, phase="stopped"):
        self.assertEqual(worker.wait(timeout=8), 0)
        self.wait_phase(phase)
        self.assertEqual(self.sleep_disabled.read_text(), "false")
        self.assertFalse((self.state / "restore").exists())
        self.assertFalse(self.plist_path.exists())

    def test_authorization_script_compiles_and_quotes_arguments(self):
        subprocess.run(["/usr/bin/osacompile", "-o", self.fixture / "authorization.scpt", "-e", self.authorization],
                       check=True)
        # Exercise the argument quoting without ever asking for privileges.
        script = self.authorization.split("do shell script commandLine with prompt", 1)[0]
        script += "do shell script commandLine\nend run"
        value = "argument with 'quotes', spaces, and ; characters"
        result = subprocess.check_output(
            ["/usr/bin/osascript", "-e", script, "--", 'printf "%s" "$1"', value], text=True
        )
        self.assertEqual(result.rstrip("\n"), value)

    def test_stop_requires_no_privileges_and_other_session_cannot_take_lease(self):
        worker = self.arm()
        self.assertIn("GRAFT_busy", self.install().stderr)
        self.marker.rmdir()
        self.assert_restored(worker)

    def test_battery_support_restores_sleep_when_charge_reaches_ten_percent(self):
        self.set_power("Battery", 15)
        worker = self.arm()
        self.set_power("Battery", 10)
        self.assert_restored(worker, "battery")
        self.assertIn("GRAFT_battery", self.install().stderr)

    def test_worker_kill_recovers_without_waiting_for_app_or_timer(self):
        worker = self.arm()
        os.killpg(worker.pid, signal.SIGKILL)
        worker.wait(timeout=5)
        self.assertEqual(self.sleep_disabled.read_text(), "true")
        self.assert_restored(self.start_watcher())

    def test_failed_restore_keeps_recovery_record_for_retry(self):
        worker = self.arm()
        self.fail_restore.touch()
        self.marker.rmdir()
        self.assertEqual(worker.wait(timeout=8), 1)
        self.wait_phase("restore-failed")
        self.assertTrue((self.state / "restore").exists())
        self.assertTrue(self.plist_path.exists())
        self.fail_restore.unlink()
        self.assert_restored(self.start_watcher())


if __name__ == "__main__":
    unittest.main()
