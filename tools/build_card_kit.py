#!/usr/bin/env python3
"""Emit the hand-card frames and card backs (tools/pixelart/cards.py).

    python3 tools/build_card_kit.py

Regenerating is deterministic: same code, same pixels."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from pixelart import cards

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UI = os.path.join(ROOT, "assets/art/ui")


def main():
    written = []
    for el in ("life", "fire", "neutral"):
        for role in ("creature", "place", "spell", "realm"):
            written.append(cards.hand_card(el, role).save(
                f"{UI}/hand_frame_{el}_{role}.png"))
        written.append(cards.card_back(el).save(f"{UI}/card_back_{el}.png"))
    print(f"card kit: {len(written)} files")


if __name__ == "__main__":
    main()
# appended: chrome components live here too, one regenerating entry point
def chrome():
    from pixelart import ui_kit
    n = 0
    for kind in ("gold", "stone", "talisman"):
        for state in ("normal", "hover", "pressed", "disabled"):
            ui_kit.button(kind, state).save(f"{UI}/btn_{kind}_{state}.png"); n += 1
    ui_kit.tray().save(f"{UI}/tray_wood.png"); n += 1
    ui_kit.parchment().save(f"{UI}/panel_parchment.png"); n += 1
    print(f"chrome: {n} files")


if __name__ == "__main__":
    chrome()
