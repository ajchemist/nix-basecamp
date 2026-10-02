"""Exercise selection, ownership and persistence without installing into the host."""
import os
from pathlib import Path
import subprocess
import shutil
import pty
import select
import signal
import time
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'lib/emacs-setup.sh'


class EmacsSetup(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='basecamp emacs ')
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.bin = self.home / 'mock-bin'
        self.bin.mkdir()
        self.package = self.home / 'fake-emacs'
        (self.package / 'bin').mkdir(parents=True)
        (self.package / 'Applications/Emacs.app').mkdir(parents=True)
        for name in ('emacs', 'emacsclient'):
            self.executable(self.package / 'bin' / name, 'exit 0')
        self.executable(self.bin / 'nix', '''
if [ "${FAIL_BUILD:-0}" = 1 ]; then exit 1; fi
while [ "$1" != --out-link ]; do shift; done
shift
ln -sfn "$FAKE_PACKAGE" "$1"
echo built >> "$HOME/build-log"
''')
        self.executable(self.bin / 'setup', 'echo "$*" >> "$HOME/setup-log"')
        # Mock brew: emacs-app is an installed cask until uninstalled.
        self.executable(self.bin / 'brew', '''
case "$1 $2" in
  'list --cask') [ "$3" = emacs-app ] && [ ! -e "$HOME/cask-gone" ] ;;
  'uninstall --cask') echo "$3" >> "$HOME/brew-log"; touch "$HOME/cask-gone" ;;
  *) exit 1 ;;
esac
''')
        self.env = dict(os.environ, HOME=str(self.home),
                        PATH=f'{self.bin}:{os.environ["PATH"]}',
                        BASECAMP_STANDALONE='1', BASECAMP_DARWIN='0',
                        BASECAMP_SYSTEM='x86_64-linux', BASECAMP_FLAKE='path:/fixture',
                        BASECAMP_PLAN='', BASECAMP_SETUP='', BASECAMP_WARM='/usr/bin/true',
                        BASECAMP_APP_TAKEOVER=str(SCRIPT.parent / 'emacs-app-takeover.sh'),
                        BASECAMP_APPS_ROOT=str(self.home / 'root'),
                        BASECAMP_BREW=str(self.bin / 'brew'),
                        FAKE_PACKAGE=str(self.package))
        self.choice = self.home / '.config/nix-basecamp/emacs'
        self.profile = self.home / '.local/state/nix-basecamp/emacs/package'
        self.link = self.home / '.local/bin/emacs'
        # Both legacy and XDG user config, plus a different managed profile.
        for name in ('.emacs', '.emacs.d/init.el', '.config/emacs/custom.el',
                     '.config/emacs/elpa/example.el', '.nix-profile/keep'):
            p = self.home / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('user-owned\n')

    @staticmethod
    def executable(path, text):
        path.write_text('#!' + shutil.which('bash') + '\nset -eu\n' + text + '\n')
        path.chmod(0o755)

    def run_setup(self, *args, success=True):
        result = subprocess.run(['bash', '-euo', 'pipefail', str(SCRIPT), *args],
                                env=self.env, capture_output=True, text=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def interactive(self, mode, answer):
        try:
            pid, fd = pty.fork()
        except OSError as error:
            self.skipTest(f'PTY unavailable: {error}')
        if pid == 0:
            os.execvpe('bash', ['bash', '-euo', 'pipefail', str(SCRIPT)], self.env)
        output = b''
        sent_mode = sent_answer = False
        deadline = time.monotonic() + 10
        try:
            while time.monotonic() < deadline:
                ready, _, _ = select.select([fd], [], [], 0.1)
                if not ready:
                    continue
                try:
                    chunk = os.read(fd, 4096)
                except OSError:
                    break
                if not chunk:
                    break
                output += chunk
                if b'[none]: ' in output and not sent_mode:
                    os.write(fd, (mode + '\n').encode())
                    sent_mode = True
                if b'Proceed? [y/N] ' in output and not sent_answer:
                    os.write(fd, (answer + '\n').encode())
                    sent_answer = True
            else:
                os.kill(pid, signal.SIGKILL)
                self.fail(f'interactive timeout: {output!r}')
        finally:
            os.close(fd)
            _, status = os.waitpid(pid, 0)
        self.assertTrue(sent_mode, output)
        self.assertTrue(sent_answer, output)
        return os.waitstatus_to_exitcode(status)

    def test_interactive_selection_installs_and_saves(self):
        self.assertEqual(self.interactive('nox', 'y'), 0)
        self.assertEqual(self.choice.read_text(), 'nox\n')
        self.assertTrue(self.link.is_symlink())

    def test_interactive_decline_does_not_save(self):
        self.assertNotEqual(self.interactive('gui', 'n'), 0)
        self.assertFalse(self.choice.exists())
        self.assertFalse(self.link.exists())

    def test_interactive_default_is_none(self):
        self.assertEqual(self.interactive('', 'y'), 0)
        self.assertEqual(self.choice.read_text(), 'none\n')
        self.assertFalse(self.link.exists())

    def save_choice(self, value):
        self.choice.parent.mkdir(parents=True, exist_ok=True)
        self.choice.write_text(value + '\n')

    def test_yes_is_not_opt_in(self):
        self.env.update(BASECAMP_STANDALONE='0', BASECAMP_SETUP=str(self.bin / 'setup'))
        self.run_setup('--yes')
        self.assertFalse(self.link.exists())
        self.assertFalse(self.choice.exists())
        self.assertEqual((self.home / 'setup-log').read_text(), '--yes\n')

    def test_standalone_yes_requires_choice(self):
        self.run_setup('--yes', success=False)
        self.assertFalse(self.choice.exists())

    def test_dry_run_has_no_effects(self):
        for mode in ('gui', 'nox', 'none'):
            self.run_setup('--dry-run', '--emacs=' + mode)
        self.assertFalse(self.choice.exists())
        self.assertFalse(self.profile.exists())
        self.assertFalse((self.home / 'build-log').exists())

    def test_install_repeat_and_remove_preserve_user_files(self):
        self.run_setup('--yes', '--emacs=nox')
        self.assertTrue(self.link.is_symlink())
        self.assertEqual(self.choice.read_text(), 'nox\n')
        self.run_setup('--yes')
        self.run_setup('--yes', '--emacs=none')
        self.assertFalse(self.link.is_symlink())
        self.assertFalse(self.profile.is_symlink())
        self.assertEqual(self.choice.read_text(), 'none\n')
        for name in ('.emacs', '.emacs.d/init.el', '.config/emacs/custom.el',
                     '.config/emacs/elpa/example.el', '.nix-profile/keep'):
            self.assertEqual((self.home / name).read_text(), 'user-owned\n')

    def test_saved_choice_is_applied_by_default_setup(self):
        self.env.update(BASECAMP_STANDALONE='0', BASECAMP_SETUP=str(self.bin / 'setup'))
        self.save_choice('nox')
        self.run_setup('--yes')
        self.assertTrue(self.link.is_symlink())

    def test_foreign_binary_is_preserved_before_main_setup(self):
        self.env.update(BASECAMP_SETUP=str(self.bin / 'setup'))
        self.link.parent.mkdir(parents=True)
        self.link.write_text('foreign')
        self.run_setup('--yes', '--emacs=nox', success=False)
        self.assertEqual(self.link.read_text(), 'foreign')
        self.assertFalse((self.home / 'setup-log').exists())
        self.assertFalse(self.choice.exists())

    def test_gui_displaces_other_emacs_apps(self):
        self.env['BASECAMP_DARWIN'] = '1'
        user_app = self.home / 'Applications/Emacs.app'
        system_app = self.home / 'root/Applications/Emacs.app'
        for app in (user_app, system_app):
            (app / 'Contents').mkdir(parents=True)
            (app / 'Contents/marker').write_text('foreign')
        self.run_setup('--yes', '--emacs=gui')
        self.assertEqual((self.home / 'brew-log').read_text(), 'emacs-app\n')
        self.assertTrue(user_app.is_symlink())
        self.assertEqual(os.readlink(user_app), str(self.profile / 'Applications/Emacs.app'))
        for app in (user_app, system_app):
            self.assertEqual((app.parent / 'Emacs.app.before-basecamp/Contents/marker').read_text(), 'foreign')
        self.assertFalse(system_app.exists())
        # A repeat run keeps ours and touches nothing else.
        self.run_setup('--yes')
        self.assertTrue(user_app.is_symlink())

    def test_nox_leaves_other_emacs_apps(self):
        self.env['BASECAMP_DARWIN'] = '1'
        system_app = self.home / 'root/Applications/Emacs.app'
        system_app.mkdir(parents=True)
        self.run_setup('--yes', '--emacs=nox')
        self.assertTrue(system_app.is_dir())
        self.assertFalse((self.home / 'brew-log').exists())

    def test_old_app_name_is_retired(self):
        self.env['BASECAMP_DARWIN'] = '1'
        old = self.home / 'Applications/Nix Basecamp Emacs.app'
        old.parent.mkdir(parents=True)
        old.symlink_to(self.profile / 'Applications/Emacs.app')
        self.run_setup('--yes', '--emacs=gui')
        self.assertFalse(old.is_symlink())
        self.assertTrue((self.home / 'Applications/Emacs.app').is_symlink())

    def test_gui_to_nox_removes_only_owned_app(self):
        self.env['BASECAMP_DARWIN'] = '1'
        app = self.home / 'Applications/Emacs.app'
        self.run_setup('--yes', '--emacs=gui')
        self.assertTrue(app.is_symlink())
        self.run_setup('--yes', '--emacs=nox')
        self.assertFalse(app.is_symlink())
        self.assertTrue(self.link.is_symlink())

    def test_failed_build_does_not_record_choice(self):
        self.save_choice('none')
        self.env['FAIL_BUILD'] = '1'
        self.run_setup('--yes', '--emacs=nox', success=False)
        self.assertEqual(self.choice.read_text(), 'none\n')
        self.assertFalse(self.link.is_symlink())

    def test_disable_does_not_remove_foreign_binary(self):
        self.link.parent.mkdir(parents=True)
        self.link.write_text('foreign')
        self.run_setup('--yes', '--emacs=none')
        self.assertEqual(self.link.read_text(), 'foreign')

    @unittest.skipUnless(os.environ.get('BASECAMP_HANDOVER'), 'requires generated module activation')
    def test_home_manager_takes_over_standalone_install(self):
        self.run_setup('--yes', '--emacs=nox')
        subprocess.run([os.environ['BASECAMP_HANDOVER']], env=self.env, check=True)
        self.assertFalse(self.link.is_symlink())
        self.assertFalse(self.profile.is_symlink())
        self.assertEqual((self.home / '.emacs').read_text(), 'user-owned\n')

    @unittest.skipUnless(os.environ.get('BASECAMP_HANDOVER'), 'requires generated module activation')
    def test_home_manager_preserves_foreign_binary(self):
        self.link.parent.mkdir(parents=True)
        self.link.write_text('foreign')
        subprocess.run([os.environ['BASECAMP_HANDOVER']], env=self.env, check=True)
        self.assertEqual(self.link.read_text(), 'foreign')

    @unittest.skipUnless(os.environ.get('BASECAMP_WARM_REAL'), 'requires the built warmer')
    def test_warm_store_runs_once_per_package(self):
        tool = os.environ['BASECAMP_WARM_REAL']
        def status():
            return subprocess.run([tool, 'status', str(self.package)], env=self.env,
                                  capture_output=True, text=True, check=True).stdout.strip()
        self.assertEqual(status(), 'pending')
        subprocess.run([tool, 'start', str(self.package)], env=self.env, check=True)
        deadline = time.monotonic() + 10
        while status() != 'done' and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertEqual(status(), 'done')
        mark = self.home / '.cache/emacs/eln-warmed.fake-emacs'
        before = mark.stat().st_mtime_ns
        subprocess.run([tool, 'start', str(self.package)], env=self.env, check=True)
        time.sleep(0.2)
        self.assertEqual(mark.stat().st_mtime_ns, before)
        self.assertFalse(Path(str(mark) + '.pid').exists())

    def test_invalid_saved_choice_and_argument(self):
        self.save_choice('oops')
        self.run_setup('--yes', success=False)
        self.run_setup('--emacs=oops', success=False)


if __name__ == '__main__':
    unittest.main()
