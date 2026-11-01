"""Curate a consistent soft-3D starter set, with exact concept assignments.

Microsoft Fluent Emoji is MIT licensed. Custom action/rare-object illustrations
are generated individually, reviewed, and copied unchanged from their originals.
Run --prepare first, then --apply after generation_manifest.json is populated.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import shutil
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT.parent / 'work/modern_symbol_sources'
DEST = ROOT / 'assets/symbols/modern3d'
REVISION = '1ffb34c752ecf5d402f04cfb4b392c77f57c54bc'
BASE = f'https://raw.githubusercontent.com/microsoft/fluentui-emoji/{REVISION}/'

def read(path):
    return json.loads(path.read_text(encoding='utf8'))

def write(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=1) + '\n', encoding='utf8')

def normalize(s):
    return re.sub('[^a-z0-9]', '', s.lower())

def slug(s):
    return re.sub('[^a-z0-9]+', '-', s.lower()).strip('-')

# Deliberate aliases, never substring/fuzzy image selection.
ALIASES = {
    'apple': 'Red apple', 'car': 'Automobile', 'boat': 'Sailboat',
    'boots': 'Hiking boot', 'bowl': 'Bowl with spoon', 'cake': 'Shortcake',
    'caterpillar': 'Bug', 'cheese': 'Cheese wedge', 'chocolate': 'Chocolate bar',
    'clock': 'Three oclock', 'clover': 'Four leaf clover', 'dad': 'Man',
    'mom': 'Woman', 'sister': 'Girl', 'brother': 'Boy', 'grandma': 'Old woman',
    'grandpa': 'Old man', 'day': 'Sun', 'dont like': 'Thumbs down',
    "don't like": 'Thumbs down', 'excited': 'Star struck', 'flower': 'Blossom',
    'friend': 'People holding hands', 'headphones': 'Headphone',
    'hi': 'Waving hand', 'honey': 'Honey pot', 'hot': 'Hot face',
    'hug': 'People hugging', 'leaf': 'Leaf fluttering in wind', 'like': 'Thumbs up',
    'medal': 'Sports medal', 'medicine': 'Pill', 'milk': 'Glass of milk',
    'morning': 'Sunrise', 'music': 'Musical notes', 'night': 'Crescent moon',
    'noodles': 'Steaming bowl', 'paper': 'Page facing up', 'plant': 'Potted plant',
    'plate': 'Fork and knife with plate', 'pot': 'Pot of food',
    'rain': 'Cloud with rain', 'rest': 'Person in bed', 'rice': 'Cooked rice',
    'sleep': 'Sleeping face', 'snow': 'Cloud with snow', 'tired': 'Yawning face',
    'tree': 'Deciduous tree', 'work': 'Office worker', 'ball': 'Soccer ball',
    'all done': 'Check mark button', 'go': 'Right arrow', 'again': 'Repeat button',
    'more': 'Plus', 'look': 'Eyes', 'calm': 'Relieved face',
    'speak': 'Speaker high volume', 'clear': 'Wastebasket', 'sensory': 'Video game',
    'teeth': 'Tooth', 'green apple': 'Green apple', 'cherry': 'Cherries',
    'orange': 'Tangerine', 'football': 'American football',
}

# Each generated image has exactly one intended concept and its own prompt.
SCENES = {
    'i': 'SELF / I: one friendly person in a blue shirt facing the viewer, pointing their own index finger clearly at their own chest. No other person and no prop.',
    'you': 'YOU: one friendly person facing the viewer, clearly pointing an index finger outward toward the viewer. Show face, torso, arm and natural pointing hand.',
    'my': 'MY / MINE: one friendly person hugging their own closed blue book securely to their own chest with both arms, a warm proud expression showing personal possession.',
    'it': 'IT / THAT OBJECT: a natural pointing hand pointing clearly at a separate simple red ball. The ball is the focus of the pointing gesture. No face or person is needed.',
    'want': 'WANT: one friendly person looking toward a desirable red toy ball, extending both open hands toward it to request it. The ball is a short distance away, not held. Clear reaching/requesting pose.',
    'need': 'NEED: one friendly person with a serious but calm requesting expression, one open hand held on their chest and the other open hand extended toward the viewer to ask for something essential. No tears, no cup or unrelated prop.',
    'my-turn': 'MY TURN: two friendly people at a tiny tabletop board game with a single large die; one person points to their own chest and reaches toward the die while the other waits with resting hands. The self-indicating turn-taking gesture is the focus.',
    'please': 'PLEASE: one friendly person in a blue shirt, smiling gently, one open hand placed flat over their chest and the other hand open in a polite request. Clear single polite requesting pose. No praying hands.',
    'thank-you': 'THANK YOU: one friendly person facing the viewer with a warm grateful smile and a hand extending gently forward from just below their chin in an appreciative gesture. No kissing lips, no heart or unrelated object.',
    'help': 'HELP: two friendly people, one standing person supporting the other by the forearm to rise from a small simple chair. The supportive helping gesture is the unmistakable focus. No medical emergency.',
    'eat': 'EAT: one friendly person bringing a spoonful of food to their open mouth while holding a small bowl in the other hand. Focus on spoon entering the mouth, with natural hands. Waist-up view.',
    'drink-water': 'DRINK WATER: one friendly person holding a clear glass half-full of light-blue water against their lips, gently tilting it to drink. No straw, no bottle and no milk. Waist-up view.',
    'play': 'PLAY: one friendly child actively pushing a colorful toy car along a small play surface beside two toy blocks. Clearly show the hand moving the car. The child and action fill the composition.',
    'read': 'READ: one friendly person holding an open book in both hands, eyes directed down toward the pages, clearly reading it. Simple visible page lines but no readable words. Waist-up view.',
    'brush-teeth': 'BRUSH TEETH: one friendly person brushing their visible front teeth with a blue toothbrush held in one natural hand. A very small amount of white toothpaste foam. Clear mouth and brush contact. Waist-up portrait.',
    'breathe': 'BREATHE: one calm friendly person with gently closed eyes, one hand on the upper chest and one on the belly, taking a slow deliberate breath. Two subtle pale-blue curved airflow strokes near the mouth communicate exhaling. No lungs floating outside the body, no leaf.',
    'draw': 'DRAW: one friendly person using a colored pencil to draw a simple flower on a sheet of paper on a small tabletop. The hand, pencil contact and colored drawing are clearly visible. Compact three-quarter waist-up view.',
    'make': 'MAKE: one friendly person actively fitting two colorful toy building blocks together with both hands. The assembly action is the unmistakable focus. Waist-up view.',
    'sing': 'SING: one friendly person with open singing mouth, relaxed expressive posture and two simple colorful musical notes next to the face. No microphone covering the mouth. Waist-up view.',
    'write': 'WRITE: close-up of one natural hand holding a blue pencil, actively writing three short neat lines on a white sheet of paper. Show clear pencil-paper contact. The lines are not readable letters or words.',
    'quiet': 'QUIET: one friendly calm person facing the viewer with one index finger held gently vertically in front of their closed lips, the familiar shushing gesture. No angry expression, no other prop.',
    'listen': 'LISTEN: one friendly person cupping a hand behind one ear and inclining their head toward that side attentively. Add two small subtle sound curves beside that ear. The listening gesture is clear.',
    'open': 'OPEN: two natural hands clearly opening the hinged lid of a small simple box, with the lid lifted and the empty interior visible. Focus on the open lid and opening action. No lock or key.',
    'line-up': 'LINE UP: three friendly people standing one behind another in a clearly spaced single-file queue, facing the same direction. Full bodies visible, compact three-quarter perspective. No crowd, no overlapping bodies.',
    'cook': 'COOK: one friendly person actively stirring a cooking pot on a small simple cooktop with a spoon, one hand on the spoon and one steadying the pot. Compact waist-up scene. No flames or dangerous action.',
    'high-five': 'HIGH FIVE: two friendly people facing each other and touching their raised open palms together at head height. Both people, their raised arms and the exact palm-to-palm contact are clearly visible.',
    'park': 'PARK: a small inviting green park with one leafy tree, one simple park bench, a short curved footpath and a patch of grass. No people, no text and no buildings.',
    'outside': 'OUTSIDE: a friendly person standing visibly outside a small house beside its front door, with a little grass and a small sun above. Clearly outside the house, not inside a room.',
    'bedroom': 'BEDROOM: a compact room vignette with one neatly made bed with a blue blanket and pillow, one small bedside table and one window. No person. The whole bedroom arrangement is clear and uncluttered.',
    'piano': 'PIANO: a beautiful small upright acoustic piano with a clearly visible black-and-white keyboard and simple matching stool. No person and no electronic keyboard substitute.',
    'building-blocks': 'BUILDING BLOCKS: three colorful toy construction bricks with visible round connecting studs, one red, one blue, one yellow, arranged in a compact stack. No masonry brick, no text or branding.',
    'swing': 'SWING: one playground swing with a sturdy simple A-frame, two hanging ropes or chains and a single empty blue seat. Entire structure visible, no child and no background.',
    'blanket': 'BLANKET: a soft folded blue fabric blanket, with a small turned-over corner and subtle fabric thickness. No bed, no pillow, no person. A blanket is the only object.',
    'yogurt': 'YOGURT: a small open yogurt cup showing smooth white yogurt, with a partially peeled plain foil lid and a simple spoon beside it. No fruit, no branding and no letters.',
    'glue': 'GLUE: one small white school-glue squeeze bottle with a bright orange nozzle cap and a tiny visible white glue droplet beside it. Blank blue label without text, no branding.',
    'lamp': 'LAMP: one modern bedside table lamp with a warm cream fabric lampshade, a blue rounded base and a small visible switch. No table or couch. Single isolated object.',
    'water': 'WATER: one clear drinking glass containing clean light-blue water, with a visible water surface and tiny highlight. No milk, no straw, no ice and no other drink.',
    'bottle': 'BOTTLE: one clear reusable water bottle filled with light-blue water and fitted with a simple blue screw cap. No baby nipple, no alcohol, no branding.',
    'fruit': 'FRUIT: a small compact bowl containing a red apple, a yellow banana, a bunch of purple grapes and one orange. Each fruit is recognizable, no vegetables or text.',
    'apricot': 'APRICOT: one ripe small golden-orange apricot with a green leaf beside one cut apricot half showing the single brown stone. Smooth lightly blushed skin. No peach fuzz or peach leaf.',
    'blackberry': 'BLACKBERRY: two ripe dark purple-black blackberries, clearly made of plump small connected drupelets, with a small green leaf. Not grapes or blueberries.',
    'date': 'DATE FRUIT: two brown ripe dried date fruits with natural elongated wrinkled surfaces, one cut open lengthwise to show a single long narrow stone. No calendar, no numbers, no leaves or other fruit.',
    'fig': 'FIG: one ripe purple fig with its small green stem and one cut fig half showing a pink-red interior densely dotted with tiny seeds. Both the whole fruit and interior are unmistakable.',
    'gooseberry': 'GOOSEBERRY: three ripe pale-green round gooseberries with subtle vertical translucent stripes and small dried flower tips, beside one small lobed green leaf. Not grapes.',
    'grapefruit': 'GRAPEFRUIT: one large round pale-yellow grapefruit beside a cut half showing pink-red citrus segments, a white pith rim and a few tiny seeds. Not an orange or lemon.',
    'passion-fruit': 'PASSION FRUIT: one round dark-purple passion fruit beside a cut half exposing yellow-gold jelly pulp filled with many black seeds and a thick pale inner rind.',
    'plum': 'PLUM: two ripe deep-purple plums with smooth skin, subtle natural center seams, short brown stems and a small green leaf. Not grapes or cherries.',
    'lighthouse': 'LIGHTHOUSE: one compact red-and-white striped coastal lighthouse with a small dark lantern room on top and a warm yellow light beam, standing on a tiny rocky base. No scenery or text.',
    'teeth': 'TEETH: a clean friendly gently curved row of white upper and lower human teeth, with a small amount of healthy pink gum visible. Focus on multiple teeth, no lips and no face. Educational and non-frightening.',
    'ninja-star': 'NINJA STAR: one small silver four-pointed throwing-star object with a round central hole, balanced symmetrical polished-metal shape. Isolated object only, no person, no hand, no motion and no violent scene.',
    'friend': 'FRIEND: two friendly people standing happily side by side with one arm gently around the other person\'s shoulder, smiling at each other. Clear friendly companionship, no romance or heart. Waist-up view.',
    'hungry': 'HUNGRY: one friendly person resting a hand on their tummy with a mild hungry expression, looking toward a small thought bubble containing a sandwich. Clear hunger, not illness or stomach pain. Waist-up view.',
    'count': 'COUNT: one friendly person counting three clearly separated colorful balls on a small tabletop, pointing at one ball while holding up three fingers on the other hand. The counting action is the focus, no written numerals.',
    'calculator': 'CALCULATOR: one modern compact blue handheld calculator with a pale display showing a simple zero and a neat grid of rounded number and math keys. Clearly a calculator, not a phone. Single isolated object.',
    'hug': 'HUG: two friendly people giving each other a warm gentle chest-to-chest hug, with both people\'s arms naturally wrapped around the other person\'s upper back and shoulders. The embrace is unmistakable. Calm warm smiles. Waist-up view, no hearts or unrelated objects.',
}

GENERATED = {
    **{k: k for k in ['I','you','my','it','want','need','my turn','please','thank you',
                     'help','eat','play','read','brush teeth','breathe','draw','make',
                     'sing','write','quiet','listen','open','line up','cook','high five',
                     'park','outside','bedroom','piano','swing','blanket','yogurt','glue',
                     'lamp','water','bottle','fruit','apricot','blackberry','date','fig',
                     'gooseberry','grapefruit','passion fruit','plum','lighthouse','teeth','ninja star']},
    'drink water': 'drink-water', 'drink': 'drink-water', 'give': 'give',
    'blocks': 'building-blocks', 'building blocks': 'building-blocks', 'music play': 'piano',
    'friend': 'friend', 'hungry': 'hungry', 'count': 'count', 'calculator': 'calculator',
    'hug': 'hug',
}
GENERATED = {k.lower(): slug(v) for k,v in GENERATED.items()}

FOLDERS = {
    'home':'House', 'people':'@friend', 'feelings':'Grinning face',
    'calm':'Person in lotus position', 'food':'Fork and knife with plate',
    'play':'@play', 'places':'World map', 'school':'School', 'animals':'Dog',
    'body':'Person standing', 'vehicles':'Automobile', 'clothes':'T shirt',
    'weather':'Sun behind rain cloud', 'colors':'Artist palette',
    'instruments':'@piano', 'sports':'Soccer ball', 'toys':'Teddy bear',
    'kitchen':'Cooking', 'furniture':'Couch and lamp', 'plants':'Potted plant',
    'insects':'Butterfly', 'sea':'Tropical fish', 'wild':'Lion', 'birds':'Bird',
    'jobs':'Construction worker', 'actions':'Clapping hands', 'snacks':'Cookie',
    'fruitveg':'@fruit', 'health':'Stethoscope', 'school2':'Books',
    'places2':'Office building', 'time':'Three oclock', 'fruits':'@fruit',
    'vegetables':'Carrot', 'alphabet':'#ABC', 'numbers':'#123',
}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--prepare', action='store_true')
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    DEST.mkdir(parents=True, exist_ok=True)
    tree_path = CACHE / 'fluent-emoji-tree.json'
    if not tree_path.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        request = urllib.request.Request(f'https://api.github.com/repos/microsoft/fluentui-emoji/git/trees/{REVISION}?recursive=1',headers={'User-Agent':'AAC-Studio'})
        write(tree_path, json.load(urllib.request.urlopen(request)))
    tree = read(tree_path)
    catalog = {}
    for entry in tree['tree']:
        p = entry['path']
        if entry['type'] != 'blob' or '/3D/' not in p or not p.endswith('.png'):
            continue
        if '/Default/' in p or len(p.split('/')) == 4:
            catalog[normalize(p.split('/')[1])] = p
    existing_fluent_names = {'fluent-'+slug(p.split('/')[1]):p.split('/')[1] for p in catalog.values()}
    pack_path = ROOT / 'assets/sample_pack.json'
    pack = read(pack_path)
    index = read(ROOT / 'assets/symbol_index.json')
    old_names = {(x['p'],x['k']):x['n'] for x in index}
    color_ids = {cell['btn'] for view in pack['views']['colors'] for cell in view['cells']}
    downloads, jobs, assignments, problems = {}, {}, [], []

    def fluent(name):
        path = catalog.get(normalize(name))
        if not path:
            problems.append(f'No Fluent 3D artwork: {name}')
            return None
        key = 'fluent-' + slug(path.split('/')[1])
        downloads[key] = path
        return key

    def generated(name):
        key = slug(name)
        if key != 'give':
            jobs[key] = SCENES[key]
        return 'scene-' + key

    colors = {'red':'#F04452','blue':'#247DEC','green':'#42AB64','yellow':'#F9CE35',
              'purple':'#9659CC','orange':'#F79A2E','pink':'#ED8AB8','brown':'#966748',
              'black':'#303840','white':'#F4F6F8','gray':'#9BA8B6'}
    folders = {}
    for fid,name in FOLDERS.items():
        folders[fid] = generated(name[1:]) if name.startswith('@') else 'type-'+name[1:].lower() if name.startswith('#') else fluent(name)
    fluent('Cross mark')  # The keyboard's "no" shortcut is not a starter-grid tile.
    for kind in ['buttons','folders']:
        for b in pack[kind]:
            label = b['label'].lower()
            if kind == 'folders':
                key = folders[b['id']]
            elif b['kind'] == 'folder':
                target = next(a['data'] for a in b['actions'] if a['kind']=='gotoFolder')
                key = folders[target]
            elif b['id'].startswith(('alphabet_','numbers_')):
                key = 'type-'+label
            elif label in colors and b['id'] in color_ids:
                key = 'color-'+label
            elif label in GENERATED:
                key = generated(GENERATED[label])
            else:
                name = 'Poultry leg' if b['id']=='b77' else ALIASES.get(label)
                if name is None:
                    if normalize(b['label']) in catalog:
                        name = b['label']
                    else:
                        name = existing_fluent_names.get(b['symbolKey']) if b['symbolPack']=='modern3d' else old_names.get((b['symbolPack'],b['symbolKey']), '')
                key = fluent(name)
                if key is None:
                    problems.append(f'{b["id"]}: {b["label"]}')
            assignments.append({'kind':kind,'id':b['id'],'label':b['label'],'key':key})
    if problems:
        print('\n'.join(sorted(set(problems))))
        raise SystemExit(1)
    write(CACHE/'generation_jobs.json', jobs)
    write(CACHE/'modern_assignments.json', assignments)

    if args.prepare:
        def fetch(pair):
            key,path = pair
            out = DEST / f'{key}.png'
            if not out.exists():
                url = BASE+urllib.parse.quote(path, safe='/')
                for attempt in range(3):
                    try:
                        out.write_bytes(urllib.request.urlopen(url, timeout=60).read())
                        break
                    except Exception:
                        if attempt == 2: raise
            return key
        with ThreadPoolExecutor(max_workers=10) as pool:
            list(pool.map(fetch, downloads.items()))
        (DEST/'LICENSE-Microsoft.txt').write_bytes(urllib.request.urlopen(BASE+'LICENSE').read())
        print(f'{len(downloads)} Fluent 3D files; {len(jobs)} custom scenes to generate; {len(assignments)} tile/category assignments')
        # Typography and color indicators are repo-native vector UI graphics.
        import resvg_py
        for text in [*'ABCDEFGHIJKLMNOPQRSTUVWXYZ',*[str(n) for n in range(21)],'ABC','123']:
            size = 82 if len(text)==1 else 65 if len(text)==2 else 53
            svg=f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128"><defs><linearGradient id="g" x2="0" y2="1"><stop stop-color="#4D9FE8"/><stop offset="1" stop-color="#1556AC"/></linearGradient></defs><text x="64" y="{85 if len(text)<3 else 83}" text-anchor="middle" font-family="Segoe UI" font-weight="700" font-size="{size}" fill="#0B3576" transform="translate(1 4)">{text}</text><text x="64" y="{85 if len(text)<3 else 83}" text-anchor="middle" font-family="Segoe UI" font-weight="700" font-size="{size}" fill="url(#g)">{text}</text></svg>'''
            (DEST/f'type-{text.lower()}.png').write_bytes(resvg_py.svg_to_bytes(svg_string=svg,width=512,height=512))
        for name,color in colors.items():
            dark='#'+''.join(f'{int(int(color[i:i+2],16)*.63):02x}' for i in [1,3,5])
            svg=f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128"><defs><radialGradient id="g" cx=".32" cy=".25" r=".85"><stop stop-color="white" stop-opacity=".55"/><stop offset=".42" stop-color="{color}"/><stop offset="1" stop-color="{dark}"/></radialGradient></defs><circle cx="64" cy="64" r="49" fill="{color}"/><circle cx="64" cy="64" r="49" fill="url(#g)"/></svg>'''
            (DEST/f'color-{name}.png').write_bytes(resvg_py.svg_to_bytes(svg_string=svg,width=512,height=512))
    if args.apply:
        generated_files = read(CACHE/'generation_manifest.json')
        for key in set(jobs)|{'give'}:
            shutil.copy2(generated_files[key], DEST/f'scene-{key}.png')
        for item in assignments:
            assert (DEST/f'{item["key"]}.png').exists(), item
        history_path=ROOT/'assets/factory_symbol_history.json'
        history=read(history_path)
        for kind in ['buttons','folders']:
            for b in pack[kind]:
                ref={k:b.get(k) for k in ['label','symbol','symbolPack','symbolKey']}
                refs=history[kind].setdefault(b['id'],[])
                if ref not in refs: refs.append(ref)
        write(history_path, history)
        lookup={(a['kind'],a['id']):a for a in assignments}
        for kind in ['buttons','folders']:
            for b in pack[kind]:
                a=lookup[kind,b['id']]
                b['symbolPack']='modern3d'
                b['symbolKey']=a['key']
        pack['packVersion']=6
        write(pack_path, pack)
        index=[e for e in index if e['p']!='modern3d']
        for item in assignments:
            if not any(e['p']=='modern3d' and e['k']==item['key'] and e['n']==item['label'] for e in index):
                index.append({'p':'modern3d','k':item['key'],'n':item['label']})
        index.extend([{'p':'modern3d','k':'fluent-check-mark-button','n':'yes'},
                      {'p':'modern3d','k':'fluent-cross-mark','n':'no'}])
        for key,path in downloads.items():
            name=path.split('/')[1]
            if not any(e['p']=='modern3d' and e['k']==key and e['n'].casefold()==name.casefold() for e in index):
                index.append({'p':'modern3d','k':key,'n':name})
        used={a['key'] for a in assignments}|{'fluent-cross-mark','fluent-check-mark-button'}
        for file in DEST.glob('*.png'):
            if file.stem not in used:
                assert file.resolve().is_relative_to(DEST.resolve())
                file.unlink()  # Only stale files created by this importer.
        (ROOT/'assets/symbol_index.json').write_text(json.dumps(index,ensure_ascii=False,separators=(',',':')),encoding='utf8')
        manifest={'style':'Soft 3D','fluentRevision':REVISION,'upstream':BASE,'assignments':assignments,
                  'files':{p.stem:hashlib.sha256(p.read_bytes()).hexdigest() for p in DEST.glob('*.png')},
                  'fluentSources':downloads,'generatedScenes':{k:jobs.get(k,'GIVE: an apple handoff between two people.') for k in generated_files}}
        write(ROOT/'docs/modern-symbol-manifest.json',manifest)
        print('Applied modern 3D starter artwork, pack version 6.')

if __name__=='__main__': main()
