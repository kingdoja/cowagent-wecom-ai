"""Install local runtime adaptations, then run the upstream CowAgent app."""

import os
import runpy
import sys


sys.path.insert(0, "/app")

if os.environ.get("COW_STREAMING_PATCH_ENABLED", "True").lower() == "true":
    from cowagent_streaming_patch import install

    install()

runpy.run_path("/app/app.py", run_name="__main__")
