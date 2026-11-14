#!/usr/bin/env python3
"""Install only our Lua block, preserving existing Ingress health customizations."""
import json
from pathlib import Path
import subprocess

key = "resource.customizations.health.networking.k8s.io_Ingress"
command = ["kubectl", "--request-timeout=15s", "-n", "argocd"]
config = json.loads(subprocess.check_output(command + ["get", "cm", "argocd-cm", "-o", "json"]))
current = config.get("data", {}).get(key, "")
begin = "-- BEGIN image-webapp tunnel health"
end = "-- END image-webapp tunnel health"
if begin in current:
    start = current.index(begin)
    stop = current.index(end, start) + len(end)
    current = current[:start] + current[stop:].lstrip("\n")
if not current.strip():
    raise SystemExit("No existing Ingress health script; review default fallback before installing.")
block = (Path(__file__).resolve().parents[1] / "argocd/image-webapp-ingress-health.lua").read_text()
patch = [
    {"op": "test", "path": "/metadata/resourceVersion", "value": config["metadata"]["resourceVersion"]},
    {"op": "add", "path": "/data/" + key, "value": block + "\n" + current},
]
subprocess.run(command + ["patch", "cm", "argocd-cm", "--type=json", "-p", json.dumps(patch)], check=True)
