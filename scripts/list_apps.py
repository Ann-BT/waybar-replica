#!/usr/bin/env python3
import os
import glob
import json
import sys

def get_apps():
    apps = {}
    paths = [
        "/usr/share/applications/*.desktop",
        os.path.expanduser("~/.local/share/applications/*.desktop")
    ]
    for path_glob in paths:
        for filepath in glob.glob(path_glob):
            if not os.path.exists(filepath):
                continue
            name, exec_cmd, icon, nodisplay = "", "", "", False
            try:
                with open(filepath, "r", errors="ignore") as f:
                    in_entry = False
                    for line in f:
                        line = line.strip()
                        if line == "[Desktop Entry]":
                            in_entry = True
                            continue
                        elif line.startswith("[") and line.endswith("]"):
                            in_entry = False
                        if in_entry:
                            if line.startswith("Name="):
                                name = line.split("=", 1)[1]
                            elif line.startswith("Exec="):
                                exec_cmd = line.split("=", 1)[1]
                                exec_cmd = exec_cmd.split(" %")[0].replace('"', '').replace("'", "")
                            elif line.startswith("Icon="):
                                icon = line.split("=", 1)[1]
                            elif line.startswith("NoDisplay="):
                                nodisplay = line.split("=", 1)[1].lower() == "true"
            except Exception:
                continue
            
            if name and exec_cmd and not nodisplay:
                apps[name] = {
                    "name": name,
                    "exec": exec_cmd,
                    "icon": icon
                }
    
    sorted_apps = sorted(apps.values(), key=lambda x: x["name"].lower())
    return sorted_apps

if __name__ == "__main__":
    print(json.dumps(get_apps()))
