from pathlib import Path
import json, collections, statistics
D=Path(__file__).parent/'data'
cards={c['id']:c for c in json.loads((D/'core_set.json').read_text())}

def profile(deck):
    expanded=[]
    for entry in deck['cards']:
        expanded += [cards[entry['card_id']]]*entry['count']
    return {
      'avg_cost':round(statistics.mean(c['cost'] for c in expanded),2),
      'curve':dict(sorted(collections.Counter(c['cost'] for c in expanded).items())),
      'types':dict(collections.Counter(c['type'] for c in expanded)),
      'effects':dict(collections.Counter(f['kind'] for c in expanded for f in c.get('effects',[])))
    }

for filename in ['starter_decks.json','preconstructed_decks.json']:
    print('\n==',filename,'==')
    for deck in json.loads((D/filename).read_text()):
        p=profile(deck)
        print(f"{deck['name']:<20} avg={p['avg_cost']:<4} types={p['types']} effects={p['effects']}")
