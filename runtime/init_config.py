"""Create a locked-down CowAgent config from the upstream JSON template."""

from __future__ import annotations

import json
import os
from pathlib import Path
import tempfile


def initialize_config(template_path: Path, config_path: Path) -> bool:
    if config_path.exists():
        return False

    with template_path.open(encoding="utf-8") as source:
        config = json.load(source)

    config["agent"] = False
    config["self_evolution_enabled"] = False
    config_path.parent.mkdir(parents=True, exist_ok=True)

    descriptor, temporary_name = tempfile.mkstemp(
        dir=config_path.parent,
        prefix=".config-",
        suffix=".json",
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as target:
            json.dump(config, target, ensure_ascii=False, indent=2)
            target.write("\n")
        temporary_path.chmod(0o600)
        temporary_path.replace(config_path)
    except BaseException:
        temporary_path.unlink(missing_ok=True)
        raise
    return True


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("config", type=Path)
    parser.add_argument("template", type=Path)
    arguments = parser.parse_args()
    initialize_config(arguments.template, arguments.config)
