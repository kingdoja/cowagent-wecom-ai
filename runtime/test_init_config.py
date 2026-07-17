import json
from pathlib import Path
import tempfile
import unittest

from init_config import initialize_config


class InitializeConfigTest(unittest.TestCase):
    def test_creates_locked_down_config_without_touching_other_values(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            template = root / "template.json"
            destination = root / "data" / "config.json"
            template.write_text(
                json.dumps({
                    "agent": True,
                    "self_evolution_enabled": True,
                    "keep_me": True,
                }),
                encoding="utf-8",
            )

            self.assertTrue(initialize_config(template, destination))
            config = json.loads(destination.read_text(encoding="utf-8"))
            self.assertEqual(config, {
                "agent": False,
                "self_evolution_enabled": False,
                "keep_me": True,
            })
            self.assertEqual(destination.stat().st_mode & 0o777, 0o600)

    def test_preserves_an_existing_config(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            template = root / "template.json"
            destination = root / "config.json"
            template.write_text('{"agent": true}', encoding="utf-8")
            destination.write_text('{"existing": true}', encoding="utf-8")

            self.assertFalse(initialize_config(template, destination))
            self.assertEqual(destination.read_text(encoding="utf-8"), '{"existing": true}')


if __name__ == "__main__":
    unittest.main()
