"""Generate Pocket Arcana production art from data/art_prompts_vertical_slice.json.

    python3 tools_generate_art.py --phase A
    python3 tools_generate_art.py --id life_sproutling --variations 3
    python3 tools_generate_art.py --phase A --style-lock       # reuse approved masters

Auth reads ~/.spritecook_key (or $SPRITECOOK_API_KEY) at call time. The key is
never printed, logged or written to any file this tool produces.

Generated images are conformed to the exact canvas in the manifest: SpriteCook
treats width/height as hints and smart-crops to squares, so post-processing is
what actually guarantees the sizes docs/ART_BIBLE.md requires. Scaling is always
nearest-neighbour — the bible forbids smoothing.
"""
from pathlib import Path
import argparse, io, json, os, sys, time, urllib.request, urllib.error

from PIL import Image

ROOT = Path(__file__).parent
API = "https://api.spritecook.ai"
PROMPTS = ROOT / "data/art_prompts_vertical_slice.json"
LEDGER = ROOT / "data/art_generation_log.json"
CANDIDATES = ROOT / ".art_candidates"          # gitignored working set
# Sprites are objects on a transparent field; terrain fills its tile.
OPAQUE_KINDS = {"terrain"}


def key():
    env = os.environ.get("SPRITECOOK_API_KEY")
    if env:
        return env.strip()
    path = Path.home() / ".spritecook_key"
    if not path.is_file():
        sys.exit("No SpriteCook key. Set SPRITECOOK_API_KEY or create ~/.spritecook_key")
    return path.read_text().strip()


def call(method, path, payload=None, timeout=240):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(API + path, data=data, method=method, headers={
        "Authorization": "Bearer " + key(),
        "Accept": "application/json",
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")[:400]
        raise SystemExit(f"HTTP {e.code} on {method} {path}: {body}")


def credits():
    return call("GET", "/v1/api/credits").get("total")


def download(url, timeout=120):
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + key()})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def conform(raw, target, opaque):
    """Force the generated image onto the exact authored canvas, nearest-neighbour."""
    tw, th = target
    im = Image.open(io.BytesIO(raw)).convert("RGBA")
    source = im.size

    if opaque:
        # Cover the tile, then centre-crop: terrain must fill edge to edge.
        scale = max(tw / im.width, th / im.height)
        im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.NEAREST)
        left, top = (im.width - tw) // 2, (im.height - th) // 2
        im = im.crop((left, top, left + tw, top + th))
        canvas = Image.new("RGBA", (tw, th), (0, 0, 0, 255))
        canvas.alpha_composite(im)
        return canvas, source

    # Sprite: trim the transparent margin, then fit the canvas.
    bbox = im.getbbox()
    if bbox:
        im = im.crop(bbox)
    # Never upscale — enlarging pixel art by a fractional factor doubles some
    # pixel rows and not others, which visibly wrecks the grid. Pad instead.
    if im.width > tw or im.height > th:
        scale = min(tw / im.width, th / im.height)
        im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.NEAREST)
    canvas = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    canvas.paste(im, ((tw - im.width) // 2, (th - im.height) // 2))
    return canvas, source


def generate(entry, variations, style_ids):
    opaque = entry["kind"] in OPAQUE_KINDS
    w, h = entry["size"]
    payload = {
        "prompt": entry["prompt"],
        "width": w, "height": h,
        "variations": variations,
        "pixel": True,
        "bg_mode": "include" if opaque else "transparent",
        "smart_crop": not opaque,
        "smart_crop_mode": "tightest",
        "mode": "texture" if entry["kind"] == "terrain" else "assets",
    }
    if style_ids:
        payload["style_asset_ids"] = style_ids[:10]
    started = time.time()
    result = call("POST", "/v1/api/generate-sync", payload)
    assets = result.get("assets") or []
    if not assets:
        # A parse or transport failure still charges, so recover rather than re-spend.
        recent = call("GET", f"/v1/api/assets/recent?limit={variations}")
        assets = recent.get("assets") or []
    return assets, result.get("credits_used"), time.time() - started


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase")
    ap.add_argument("--id", action="append", dest="ids")
    ap.add_argument("--variations", type=int, default=1)
    ap.add_argument("--style-lock", action="store_true",
                    help="pass the approved masters recorded in the ledger as style guides")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--pick", type=int,
                    help="promote an already-generated candidate (0-based) without re-spending credits")
    args = ap.parse_args()

    prompts = json.loads(PROMPTS.read_text())
    rows = [p for p in prompts
            if (args.phase is None or p["phase"] == args.phase.upper())
            and (args.ids is None or p["id"] in args.ids)]
    if not rows:
        sys.exit("nothing matched")

    ledger = json.loads(LEDGER.read_text()) if LEDGER.is_file() else {"assets": {}, "masters": {}}

    if args.pick is not None:
        for entry in rows:
            src = CANDIDATES / entry["id"] / f"{args.pick}.png"
            if not src.is_file():
                print(f"  ✗ {entry['id']}: no candidate {args.pick}")
                continue
            image, source = conform(src.read_bytes(), entry["size"], entry["kind"] in OPAQUE_KINDS)
            out = ROOT / entry["path"]
            out.parent.mkdir(parents=True, exist_ok=True)
            image.save(out)
            record = ledger["assets"].setdefault(entry["id"], {})
            record.update({"path": entry["path"], "picked": args.pick,
                           "asset_id": record.get("candidate_ids", [None] * (args.pick + 1))[args.pick]
                           if record.get("candidate_ids") else record.get("asset_id")})
            print(f"  ✓ {entry['id']:<26} promoted candidate {args.pick} -> {entry['path']}")
        LEDGER.write_text(json.dumps(ledger, indent=2) + "\n")
        return
    style_ids = []
    if args.style_lock:
        style_ids = [v for v in ledger.get("masters", {}).values() if v]

    print(f"{len(rows)} asset(s); credits before: {credits()}")
    if args.dry_run:
        for r in rows:
            print(f"  would generate {r['id']:<26} {r['kind']:<17} {r['size']}")
        return

    for entry in rows:
        assets, used, secs = generate(entry, args.variations, style_ids)
        if not assets:
            print(f"  ✗ {entry['id']}: no asset returned")
            continue
        # Keep every candidate on disk so choosing another costs nothing.
        cand_dir = CANDIDATES / entry["id"]
        cand_dir.mkdir(parents=True, exist_ok=True)
        candidate_ids = []
        for i, asset in enumerate(assets):
            (cand_dir / f"{i}.png").write_bytes(download(asset["url"]))
            candidate_ids.append(asset.get("id"))
        chosen = assets[0]
        image, source = conform((cand_dir / "0.png").read_bytes(), entry["size"],
                                entry["kind"] in OPAQUE_KINDS)
        out = ROOT / entry["path"]
        out.parent.mkdir(parents=True, exist_ok=True)
        image.save(out)
        ledger["assets"][entry["id"]] = {
            "asset_id": chosen.get("id"), "candidate_ids": candidate_ids,
            "path": entry["path"], "picked": 0,
            "size": list(entry["size"]), "source_size": list(source),
            "kind": entry["kind"], "element": entry.get("element"),
            "credits_used": used,
        }
        print(f"  ✓ {entry['id']:<26} {source[0]}x{source[1]} -> {entry['size'][0]}x{entry['size'][1]}"
              f"  {used}cr  {secs:.0f}s  {entry['path']}")

    LEDGER.write_text(json.dumps(ledger, indent=2) + "\n")
    print(f"credits after: {credits()}")


if __name__ == "__main__":
    main()
