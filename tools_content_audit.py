from pathlib import Path
import json, collections, statistics
D=Path(__file__).parent/'data'; cards=json.loads((D/'core_set.json').read_text())
mono=collections.Counter(c['elements'][0] for c in cards if len(c.get('elements',[]))==1)
types=collections.Counter(c['type'] for c in cards); rar=collections.Counter(c['rarity'] for c in cards)
ready=[c for c in cards if c.get('implementation_status')=='slice_ready']
wordy=[c for c in cards if len(c.get('rules','').split())>22]
print('Mono-element counts:',dict(sorted(mono.items())))
print('Types:',dict(types)); print('Rarities:',dict(rar)); print('Slice-ready:',len(ready)); print('Rules >22 words:',len(wordy))
assert all(mono[e]==24 for e in mono), mono
assert len(cards)==240
print('Audit: structural checks passed')
