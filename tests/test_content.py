import json
from pathlib import Path
ROOT=Path(__file__).parents[1]
def load(n):return json.loads((ROOT/'data'/n).read_text())
def test_counts():
    assert len(load('core_set.json'))==240
    assert len(load('commanders.json'))==24
    assert len(load('starter_decks.json'))==8
    assert len(load('combo_recipes.json'))==28
