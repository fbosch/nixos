import hashlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(sys.argv.pop(1)).resolve()
SIZE = 64 * 1024 * 1024


class CacheImageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.image = self.directory / "cache.img"

    def initialize(self, size=SIZE):
        return subprocess.run(
            ["bash", str(SCRIPT), str(self.image), str(size)],
            capture_output=True,
            text=True,
            check=False,
        )

    def digest(self):
        return hashlib.sha256(self.image.read_bytes()).hexdigest()

    def test_creates_private_bounded_ext4_image(self):
        result = self.initialize()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.image.stat().st_size, SIZE)
        self.assertEqual(self.image.stat().st_mode & 0o777, 0o600)
        filesystem = subprocess.check_output(
            ["blkid", "-p", "-s", "TYPE", "-o", "value", str(self.image)],
            text=True,
        ).strip()
        self.assertEqual(filesystem, "ext4")
        self.assertEqual(list(self.directory.iterdir()), [self.image])

    def test_reuses_existing_image_without_modifying_it(self):
        self.assertEqual(self.initialize().returncode, 0)
        before = self.digest()
        result = self.initialize()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.digest(), before)

    def test_rejects_size_change_without_modifying_image(self):
        self.assertEqual(self.initialize().returncode, 0)
        before = self.digest()
        result = self.initialize(SIZE * 2)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("size changed", result.stderr)
        self.assertEqual(self.digest(), before)

    def test_rejects_existing_non_filesystem_without_formatting_it(self):
        with self.image.open("wb") as image:
            image.truncate(SIZE)
        before = self.digest()
        result = self.initialize()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.digest(), before)

    def test_rejects_symlink_without_modifying_target(self):
        target = self.directory / "existing-data"
        target.write_bytes(b"unrelated data")
        self.image.symlink_to(target)
        result = self.initialize()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(target.read_bytes(), b"unrelated data")

    def test_rejects_directory_without_modifying_it(self):
        self.image.mkdir()
        result = self.initialize()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.image.is_dir())
        self.assertEqual(list(self.image.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
