"""Pocket Arcana — the locked palette.

Every hand-authored asset and every conformed generation is quantised to this
list. That is what makes Life and Fire read as one game rather than a pile of
separate generations: docs/ART_BIBLE.md asks for a limited palette, and until
now nothing enforced it (the shipped Life creatures used 5839 distinct colours).

Ramps run dark -> light. Index into them rather than inventing a new colour;
a shade that is not in this file is a bug, not a decision.
"""

def _hex(s):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))


# --- ink -------------------------------------------------------------------
# One outline colour, per the style guide. INK_SOFT is only for interior
# separation lines, never for a silhouette edge.
INK      = _hex("17110f")
INK_SOFT = _hex("2f2422")

# --- Grove / Life ----------------------------------------------------------
GROVE = [_hex(c) for c in ("22381b", "324e26", "456831", "587f3c", "6f9a4d", "89b566", "a8cf8a")]
LEAF  = [_hex(c) for c in ("1f3a1c", "2f5a26", "437f33", "5da344", "7cc12a", "9fd95c")]
WOOD  = [_hex(c) for c in ("2a1c14", "402a1c", "5b3d27", "7a5435", "9c7048", "bd8f63")]
BLOOM = [_hex(c) for c in ("8c3350", "c04f6e", "e88fa6", "f7c2d0")]
BERRY = [_hex(c) for c in ("7a1f2c", "b8323f", "d1495b", "e8737f")]
CREAM = [_hex(c) for c in ("9c8a5e", "c4b183", "e6d6a8", "f6ecd0")]
SPORE = [_hex(c) for c in ("5a7a2a", "8cbc3c", "b8f27a", "dcffb4")]   # glowing plants

# --- Cinder / Fire ---------------------------------------------------------
CINDER = [_hex(c) for c in ("17120f", "251d18", "342922", "44362c", "56463a", "6b594a", "857260")]
CHAR   = [_hex(c) for c in ("100c0a", "1d1712", "2c231c", "3b3026")]
EMBER  = [_hex(c) for c in ("5c1a08", "8f2c0d", "c23c14", "f65600", "ff8c1a", "ffb64a")]
HOT    = [_hex(c) for c in ("d97b12", "f2a733", "fcd47a", "fce5a2", "fff6dc")]
IRON   = [_hex(c) for c in ("1a1719", "2c282c", "463f44", "615762", "7d7280", "9c92a0")]

# --- neutral ground / clash zone ------------------------------------------
STONE = [_hex(c) for c in ("1d1a17", "2e2a24", "433d34", "5a5247", "746a5c", "8f8474", "aa9e8c")]
DUST  = [_hex(c) for c in ("3a342c", "544c40", "6f6555", "8a7f6b")]

# --- UI --------------------------------------------------------------------
UI_DARK  = [_hex(c) for c in ("120f14", "1c1820", "2a242f", "3a3341", "4d4455")]
UI_EDGE  = [_hex(c) for c in ("6a5f74", "8a7c96", "b0a2bc")]
AETHER   = [_hex(c) for c in ("2a3a7a", "3f57b0", "5f7fe0", "9db4f5", "d6e2ff")]
HEART    = [_hex(c) for c in ("6e1030", "a81a48", "d92a63", "f26a92", "ffb3c8")]
GOLD     = [_hex(c) for c in ("6b4a12", "a3761f", "d6a338", "f0cc6e", "ffe9ad")]

# Element identity, used for tints and crest fills.
ELEMENT = {"life": LEAF[4], "fire": EMBER[3]}


def ramps():
    """Every named ramp, for the quantiser and for palette documentation."""
    g = globals()
    out = {}
    for name, value in g.items():
        if name.isupper() and isinstance(value, list) and value and isinstance(value[0], tuple):
            out[name] = value
    return out


def all_colours():
    seen = []
    for ramp in ramps().values():
        for c in ramp:
            if c not in seen:
                seen.append(c)
    for c in (INK, INK_SOFT):
        if c not in seen:
            seen.append(c)
    return seen


def nearest(rgb, allowed=None):
    """Closest palette entry, weighted toward luminance so ramps stay ordered."""
    pool = allowed if allowed else all_colours()
    r, g, b = rgb[0], rgb[1], rgb[2]
    best, best_d = pool[0], None
    for c in pool:
        dr, dg, db = r - c[0], g - c[1], b - c[2]
        d = 2 * dr * dr + 4 * dg * dg + 3 * db * db
        if best_d is None or d < best_d:
            best, best_d = c, d
    return best
