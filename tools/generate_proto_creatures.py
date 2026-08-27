#!/usr/bin/env python3
"""Concept art for the 2.5D visual prototype — a deliberate break from pixel art.

Thomas reset the creature direction: no more plain animals, no Pokemon energy.
These are the two prototype concepts, both from the "animated objects / weird
little magical people" space, chosen for silhouette first:

  Sprigget, the Pot-Sprout   — a living cracked flowerpot with a bloom for a head
  Cinderbelly, the Stove Imp — a pot-bellied iron stove with a furnace-door grin

Candidates land in .art_candidates/proto_* so re-picking costs nothing. These
are CONCEPTS: nothing is production direction until Thomas approves one.
"""
import json, os, sys, time, urllib.request, urllib.error
from pathlib import Path

ROOT = Path(__file__).parent.parent
API = "https://api.spritecook.ai"
CANDIDATES = ROOT / ".art_candidates"

STYLE = ("Stylized fantasy card game illustration, chunky rounded shapes, bold clean dark "
         "outlines, flat cel shading with two-tone shadows and warm rim light, saturated "
         "colors, strong readable silhouette, whimsical and characterful, full body, "
         "three-quarter view, feet on the ground, transparent background, "
         "no text, no watermark, no frame, no border, not pixel art.")

JOBS = {
    "proto_sprigget": {
        "size": (512, 512), "variations": 4,
        "prompt": "A small grumpy-but-kind living flowerpot creature: a round cracked "
                  "terracotta pot for a body, stubby root legs, thin twig arms, moss "
                  "spilling over the pot rim like a beard, and one oversized blooming "
                  "pink-and-cream flower as its head with a simple sleepy face at the "
                  "flower's centre. Tiny glowing green spores drift around it. A magical "
                  "garden spirit, original design. " + STYLE,
    },
    "proto_cinderbelly": {
        "size": (512, 512), "variations": 4,
        "prompt": "A pot-bellied antique cast-iron stove come alive as a mischievous imp: "
                  "round black iron belly with a grinning furnace-door mouth glowing hot "
                  "orange from inside, stubby riveted legs, mitten-like iron hands, a "
                  "crooked stovepipe chimney hat puffing one small smoke cloud, embers "
                  "leaking from its seams. A whimsical fire spirit, original design. " + STYLE,
    },
    "proto_spell_bloom": {
        "size": (512, 384), "variations": 2,
        "prompt": "A magical burst of oversized flowers, curling vines and glowing green "
                  "spores erupting upward from the ground, spell card illustration. " + STYLE,
    },
    "proto_spell_embers": {
        "size": (512, 384), "variations": 2,
        "prompt": "A sweeping sideways wave of glowing embers, flame ribbons and curling "
                  "dark smoke, spell card illustration. " + STYLE,
    },
}


def key():
    env = os.environ.get("SPRITECOOK_API_KEY")
    if env: return env.strip()
    return (Path.home() / ".spritecook_key").read_text().strip()


def call(method, path, payload=None, timeout=300):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(API + path, data=data, method=method, headers={
        "Authorization": "Bearer " + key(), "Accept": "application/json",
        "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        raise SystemExit(f"HTTP {e.code} on {path}: {e.read().decode('utf-8','replace')[:300]}")


def download(url):
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + key()})
    with urllib.request.urlopen(req, timeout=180) as r:
        return r.read()


def main():
    names = sys.argv[1:] or list(JOBS)
    print(f"credits before: {call('GET', '/v1/api/credits').get('total')}")
    for name in names:
        job = JOBS[name]
        w, h = job["size"]
        payload = {"prompt": job["prompt"], "width": w, "height": h,
                   "variations": job["variations"], "pixel": False,
                   "bg_mode": "transparent", "smart_crop": True,
                   "smart_crop_mode": "tightest", "mode": "assets"}
        started = time.time()
        result = call("POST", "/v1/api/generate-sync", payload)
        assets = result.get("assets") or []
        if not assets:
            recent = call("GET", f"/v1/api/assets/recent?limit={job['variations']}")
            assets = recent.get("assets") or []
        d = CANDIDATES / name
        d.mkdir(parents=True, exist_ok=True)
        for i, a in enumerate(assets):
            (d / f"{i}.png").write_bytes(download(a["url"]))
        print(f"  {name:22} {len(assets)} candidates  {result.get('credits_used')}cr  "
              f"{time.time()-started:.0f}s")
    print(f"credits after: {call('GET', '/v1/api/credits').get('total')}")


if __name__ == "__main__":
    main()
