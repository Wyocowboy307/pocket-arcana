from pathlib import Path
import json, sys
ROOT=Path(__file__).parent
D=ROOT/'data'
def load(n): return json.loads((D/n).read_text())
errors=[]
elements={e['id'] for e in load('elements.json')}
cards=load('core_set.json'); by={c['id']:c for c in cards}
if len(cards)!=240: errors.append(f'core_set expected 240 cards, got {len(cards)}')
if len(by)!=len(cards): errors.append('duplicate card id')
cmds=load('commanders.json'); decks=load('starter_decks.json'); recipes=load('combo_recipes.json'); tokens=load('tokens.json'); prompts=load('card_art_prompts.json'); future=load('future_blueprints.json'); opponents=load('opponents.json'); regions=load('campaign_regions.json'); archetypes=load('archetype_blueprints.json'); precons=load('preconstructed_decks.json')
if len(cmds)!=24:errors.append(f'expected 24 commanders, got {len(cmds)}')
if len(decks)!=8:errors.append(f'expected 8 starter decks, got {len(decks)}')
if len(recipes)!=28:errors.append(f'expected 28 recipes, got {len(recipes)}')
if len(tokens)!=12:errors.append(f'expected 12 tokens, got {len(tokens)}')
if len(prompts)!=240:errors.append(f'expected 240 art prompts, got {len(prompts)}')
if len(future)!=80:errors.append(f'expected 80 future hooks, got {len(future)}')
if len(opponents)!=24:errors.append(f'expected 24 opponents, got {len(opponents)}')
if len(regions)!=8:errors.append(f'expected 8 regions, got {len(regions)}')
if len(archetypes)!=24:errors.append(f'expected 24 archetypes, got {len(archetypes)}')
if len(precons)!=16:errors.append(f'expected 16 advanced precons, got {len(precons)}')
cmd_ids={c['id'] for c in cmds}
for c in cards:
    for e in c.get('elements',[]):
        if e not in elements:errors.append(f'{c["id"]}: bad element {e}')
    if c.get('type')=='creature' and ('power' not in c or 'health' not in c):errors.append(f'{c["id"]}: creature missing stats')
for d in decks:
    total=sum(x['count'] for x in d['cards'])
    if total!=40:errors.append(f'{d["id"]}: {total} cards, expected 40')
    if d['commander_id'] not in cmd_ids:errors.append(f'{d["id"]}: bad commander')
    seen={}
    for x in d['cards']:
        cid=x['card_id']; seen[cid]=seen.get(cid,0)+x['count']
        if cid not in by:errors.append(f'{d["id"]}: missing {cid}')
    for cid,n in seen.items():
        limit=1 if by[cid]['rarity']=='mythic' else 3
        if n>limit:errors.append(f'{d["id"]}: {cid} has {n}, limit {limit}')
for r in recipes:
    if len(r.get('states',[]))!=2:errors.append(f'{r["id"]}: needs exactly two states')
for d in precons:
    total=sum(x['count'] for x in d['cards'])
    if total!=40: errors.append(f'{d["id"]}: advanced precon has {total} cards')
    if d['commander_id'] not in cmd_ids: errors.append(f'{d["id"]}: bad commander')
    for x in d['cards']:
        if x['card_id'] not in by: errors.append(f'{d["id"]}: missing {x["card_id"]}')
        elif x['count'] > (1 if by[x['card_id']]['rarity']=='mythic' else 3): errors.append(f'{d["id"]}: copy limit {x["card_id"]}')

supported={'add_state','damage_unit','damage_heart','heal_heart','draw','gain_wonder','gain_aether','buff_unit','transform_terrain','summon_token','resurrect_last','move_unit'}
for c in cards:
    for fx in c.get('effects',[]):
        if fx.get('kind') not in supported: errors.append(f'{c["id"]}: unsupported effect {fx.get("kind")}')
ready=sum(c.get('implementation_status')=='slice_ready' for c in cards)
if ready!=32: errors.append(f'expected 32 slice-ready cards, got {ready}')
print(f'Pocket Arcana content: {len(cards)} cards, {len(cmds)} commanders, {len(decks)} starters, {len(recipes)} recipes, {len(tokens)} tokens, {ready} slice-ready')
if errors:
    print('ERRORS:'); [print(' -',e) for e in errors]; sys.exit(1)
print('Validation: 0 errors')
