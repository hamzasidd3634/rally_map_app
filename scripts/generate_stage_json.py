#!/usr/bin/env python3
"""Generate assets/data/stage.json and stage1..3.json from stage_polylines_source.txt.

Source format: lines like "Stage N", "start [...]", "finish [...]", then one line "[[lat,lng],...]".
Place or copy your details file as assets/data/stage_polylines_source.txt, then run:

  python3 scripts/generate_stage_json.py

From project root.
"""
import json
import os

def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    path = os.path.join(root, "assets", "data", "stage_polylines_source.txt")
    if not os.path.isfile(path):
        print(f"Missing {path}")
        print("Copy your 'details for Stage Polylines.txt' there and run again.")
        return 1

    with open(path) as f:
        lines = f.readlines()

    arrays = []
    for line in lines:
        line = line.strip()
        if line.startswith("[["):
            arrays.append(json.loads(line))
            if len(arrays) == 3:
                break

    data_dir = os.path.join(root, "assets", "data")
    for i, coords in enumerate(arrays, 1):
        name = f"Stage {i}"
        out = {"name": name, "coordinates": coords}
        outpath = os.path.join(data_dir, f"stage{i}.json")
        with open(outpath, "w") as f:
            json.dump(out, f, separators=(",", ":"))
        print(f"Wrote {outpath}: {len(coords)} points")

    stage_json = os.path.join(data_dir, "stage.json")
    with open(stage_json, "w") as f:
        json.dump({"name": "Stage 1", "coordinates": arrays[0]}, f, separators=(",", ":"))
    print(f"Wrote {stage_json} (app default = Stage 1)")
    return 0

if __name__ == "__main__":
    exit(main())
