"""Exercise the Emacs.app takeover and the once-per-store-path warm-up
without touching the host (fake HOME, fake /Applications root, mock brew)."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

TAKEOVER = Path(__file__).resolve().parents[1] / 'lib/emacs-app-takeover.sh'


class EmacsTakeover(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='basecamp emacs ')
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.bin = self.home / 'mock-bin'
        self.bin.mkdir()
        # Mock brew: emacs-app is an installed cask until uninstalled.
        brew = self.bin / 'brew'
        brew.write_text('#!' + shutil.which('bash') + '''
case "$1 $2" in
  'list --cask') [ "$3" = emacs-app ] && [ ! -e "$HOME/cask-gone" ] ;;
  'uninstall --cask') echo "$3" >> "$HOME/brew-log"; touch "$HOME/cask-gone" ;;
  *) exit 1 ;;
esac
''')
        brew.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home),
                        BASECAMP_BREW=str(brew), BASECAMP_APPS_ROOT=str(self.home / 'root'))
        self.user_app = self.home / 'Applications/Emacs.app'
        self.system_app = self.home / 'root/Applications/Emacs.app'

    def takeover(self, *args):
        subprocess.run(['bash', str(TAKEOVER), *args], env=self.env, check=True,
                       capture_output=True)

    def foreign(self, app):
        (app / 'Contents').mkdir(parents=True)
        (app / 'Contents/marker').write_text('foreign')

    def test_displaces_casks_and_other_bundles(self):
        self.foreign(self.user_app)
        self.foreign(self.system_app)
        self.takeover()
        self.assertEqual((self.home / 'brew-log').read_text(), 'emacs-app\n')
        for app in (self.user_app, self.system_app):
            self.assertFalse(app.exists())
            self.assertEqual((app.parent / 'Emacs.app.before-basecamp/Contents/marker').read_text(), 'foreign')

    def test_repeat_is_a_no_op(self):
        self.foreign(self.system_app)
        self.takeover()
        self.foreign(self.system_app)  # a new one appears; the old backup stays
        self.takeover()
        self.assertTrue(self.system_app.exists())
        self.assertEqual((self.home / 'brew-log').read_text(), 'emacs-app\n')


@unittest.skipUnless(os.environ.get('BASECAMP_WARM'), 'requires the built warmer')
class WarmStore(unittest.TestCase):
    def test_runs_once_per_package(self):
        tmp = tempfile.TemporaryDirectory(prefix='basecamp warm ')
        self.addCleanup(tmp.cleanup)
        home = Path(tmp.name)
        package = home / 'fake-emacs'
        (package / 'lib/emacs').mkdir(parents=True)
        env = dict(os.environ, HOME=str(home))
        tool = os.environ['BASECAMP_WARM']

        def status():
            return subprocess.run([tool, 'status', str(package)], env=env,
                                  capture_output=True, text=True, check=True).stdout.strip()

        self.assertEqual(status(), 'pending')
        subprocess.run([tool, 'start', str(package)], env=env, check=True)
        deadline = time.monotonic() + 10
        while status() != 'done' and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertEqual(status(), 'done')
        mark = home / '.cache/emacs/eln-warmed.fake-emacs'
        before = mark.stat().st_mtime_ns
        subprocess.run([tool, 'start', str(package)], env=env, check=True)
        time.sleep(0.2)
        self.assertEqual(mark.stat().st_mtime_ns, before)
        self.assertFalse(Path(str(mark) + '.pid').exists())


if __name__ == '__main__':
    unittest.main()
