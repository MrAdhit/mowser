# -*- bazel-starlark -*-
"""Siso backend config for BuildBuddy remote execution.

scripts/sync.sh copies this file to build/config/siso/backend_config/backend.star. Actions run
in the container image of Chromium's Google backend config, without its worker pool labels.
"""

load("@builtin//struct.star", "module")
load("./google.star", google = "backend")

def __platform_properties(ctx):
    platforms = {}
    for name, properties in google.platform_properties(ctx).items():
        platforms[name] = {
            key: value
            for key, value in properties.items()
            if not key.startswith("label:")
        }
    return platforms

backend = module(
    "backend",
    platform_properties = __platform_properties,
)
