"""Pack v10: more words on Home and in the categories, easier to find.

- Home gets more core words (he, she, eat, drink, what, where, toilet, ...)
  after the existing ones, so learned positions do not move.
- Alphabet, Numbers, Colors, Daily routines, Weather and Vehicles get a
  button on Home (they were only reachable inside other categories).
- Eat & drink gets meals, more foods and a new Drinks category.
- Feelings, People, My body, Health, Places, Clothes, Home things,
  Actions, Time, Toys, Play and Snacks get more words.

Every picture is an existing modern-flat picture. New buttons use new ids
and existing cells keep their relative order, so installed boards receive
the additions through the normal pack upgrade with user edits kept.
Idempotent. Usage: python tools/expand_vocabulary_v10.py
"""
import json
import re
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / 'assets/sample_pack.json'
HISTORY = ROOT / 'assets/factory_symbol_history.json'
INDEX = ROOT / 'assets/symbol_index.json'
PICTURES = ROOT / 'assets/flat_symbols/modernflat'
VERSION = 10

# New words added after a category's existing words (label, word class,
# picture key). Category buttons stay together after the words.
ADD = {
    'home': [
        ('he', 'pronoun', 'fluent-man'),
        ('she', 'pronoun', 'fluent-woman'),
        ('we', 'pronoun', 'fluent-busts-in-silhouette'),
        ('eat', 'verb', 'scene-eat'),
        ('drink', 'verb', 'scene-drink-water'),
        ('what', 'question', 'fluent-red-question-mark'),
        ('where', 'question', 'fluent-magnifying-glass-tilted-left'),
        ('who', 'question', 'fluent-bust-in-silhouette'),
        ('this', 'other', 'fluent-backhand-index-pointing-down'),
        ('that', 'other', 'fluent-backhand-index-pointing-right'),
        ('toilet', 'noun', 'fluent-toilet'),
        ('hurt', 'adjective', 'fluent-face-with-head-bandage'),
        ('sick', 'adjective', 'fluent-face-with-thermometer'),
        ('tired', 'adjective', 'fluent-yawning-face'),
        ('hungry', 'adjective', 'scene-hungry'),
        ('hot', 'adjective', 'fluent-hot-face'),
        ('cold', 'adjective', 'fluent-cold-face'),
        ('good', 'adjective', 'fluent-ok-hand'),
        ('bad', 'adjective', 'fluent-cross-mark'),
        ('up', 'other', 'fluent-up-arrow'),
        ('down', 'other', 'fluent-down-arrow'),
        ('sorry', 'social', 'fluent-person-bowing'),
        ("don't know", 'phrase', 'fluent-person-shrugging'),
    ],
    'food': [
        ('hungry', 'adjective', 'scene-hungry'),
        ('yummy', 'adjective', 'fluent-face-savoring-food'),
        ('yucky', 'adjective', 'fluent-nauseated-face'),
        ('breakfast', 'noun', 'vocab-breakfast'),
        ('lunch', 'noun', 'fluent-bento-box'),
        ('dinner', 'noun', 'vocab-dinner'),
        ('sandwich', 'noun', 'fluent-sandwich'),
        ('burger', 'noun', 'fluent-hamburger'),
        ('fries', 'noun', 'fluent-french-fries'),
        ('hot dog', 'noun', 'fluent-hot-dog'),
        ('spaghetti', 'noun', 'fluent-spaghetti'),
        ('soup', 'noun', 'fluent-pot-of-food'),
        ('pancakes', 'noun', 'fluent-pancakes'),
        ('bacon', 'noun', 'fluent-bacon'),
        ('meat', 'noun', 'fluent-cut-of-meat'),
        ('fish', 'noun', 'fluent-fish'),
        ('salad', 'noun', 'fluent-green-salad'),
        ('beans', 'noun', 'fluent-beans'),
        ('potato', 'noun', 'fluent-potato'),
        ('taco', 'noun', 'fluent-taco'),
        ('burrito', 'noun', 'fluent-burrito'),
        ('dumpling', 'noun', 'fluent-dumpling'),
        ('croissant', 'noun', 'fluent-croissant'),
        ('bagel', 'noun', 'fluent-bagel'),
        ('butter', 'noun', 'fluent-butter'),
        ('salt', 'noun', 'fluent-salt'),
        ('fork and knife', 'noun', 'fluent-fork-and-knife'),
    ],
    'drinks': [
        ('water', 'noun', 'scene-water'),
        ('juice', 'noun', 'fluent-beverage-box'),
        ('milk', 'noun', 'fluent-glass-of-milk'),
        ('hot chocolate', 'noun', 'fluent-hot-beverage'),
        ('tea', 'noun', 'fluent-teacup-without-handle'),
        ('bubble tea', 'noun', 'fluent-bubble-tea'),
        ('smoothie', 'noun', 'fluent-tropical-drink'),
        ('cup with straw', 'noun', 'fluent-cup-with-straw'),
        ('bottle', 'noun', 'fluent-baby-bottle'),
        ('ice', 'noun', 'fluent-ice'),
        ('thirsty', 'adjective', 'fluent-droplet'),
        ('more', 'other', 'fluent-plus'),
    ],
    'snacks': [
        ('crackers', 'noun', 'fluent-rice-cracker'),
        ('pretzel', 'noun', 'fluent-pretzel'),
        ('peanuts', 'noun', 'fluent-peanuts'),
        ('pie', 'noun', 'fluent-pie'),
        ('pudding', 'noun', 'fluent-custard'),
        ('shaved ice', 'noun', 'fluent-shaved-ice'),
    ],
    'feelings': [
        ('surprised', 'adjective', 'fluent-astonished-face'),
        ('bored', 'adjective', 'fluent-unamused-face'),
        ('frustrated', 'adjective', 'fluent-face-with-steam-from-nose'),
        ('love', 'verb', 'fluent-smiling-face-with-hearts'),
        ('okay', 'adjective', 'fluent-ok-hand'),
        ('sleepy', 'adjective', 'fluent-sleepy-face'),
        ('confused', 'adjective', 'fluent-confused-face'),
        ('nervous', 'adjective', 'fluent-anxious-face-with-sweat'),
        ('embarrassed', 'adjective', 'fluent-flushed-face'),
        ('laughing', 'adjective', 'fluent-face-with-tears-of-joy'),
        ('crying', 'adjective', 'fluent-loudly-crying-face'),
        ('cold', 'adjective', 'fluent-cold-face'),
        ('hot', 'adjective', 'fluent-hot-face'),
    ],
    'people': [
        # mom/dad/sister/brother/doctor already use the man, woman, girl,
        # boy and health-worker pictures.
        ('person', 'noun', 'fluent-person'),
        ('nurse', 'noun', 'fluent-woman-health-worker'),
        ('everyone', 'noun', 'fluent-busts-in-silhouette'),
        ('husband', 'noun', 'vocab-husband'),
        ('wife', 'noun', 'vocab-wife'),
    ],
    'body': [
        ('head', 'noun', 'vocab-head'),
        ('arm', 'noun', 'vocab-arm'),
        ('finger', 'noun', 'vocab-finger'),
        ('foot', 'noun', 'fluent-foot'),
        ('knee', 'noun', 'vocab-knee'),
        ('back', 'noun', 'vocab-back'),
        ('neck', 'noun', 'vocab-neck'),
        ('shoulder', 'noun', 'vocab-shoulder'),
        ('throat', 'noun', 'vocab-throat'),
        ('tongue', 'noun', 'fluent-tongue'),
        ('brain', 'noun', 'fluent-brain'),
        ('tooth', 'noun', 'fluent-tooth'),
    ],
    'health': [
        ('sick', 'adjective', 'fluent-face-with-thermometer'),
        ('sneeze', 'verb', 'fluent-sneezing-face'),
        ('mask', 'noun', 'fluent-face-with-medical-mask'),
        ('nurse', 'noun', 'fluent-health-worker'),
        ('hurt', 'adjective', 'fluent-face-with-head-bandage'),
        ('toothbrush', 'noun', 'fluent-toothbrush'),
    ],
    'places': [
        ('playground', 'noun', 'fluent-playground-slide'),
        ('beach', 'noun', 'vocab-beach'),
        ('garden', 'noun', 'fluent-house-with-garden'),
        ('library', 'noun', 'fluent-books'),
        ('hospital', 'noun', 'fluent-hospital'),
        ('restaurant', 'noun', 'fluent-fork-and-knife-with-plate'),
        ('swimming pool', 'noun', 'fluent-person-swimming'),
        ('shop', 'noun', 'fluent-shopping-cart'),
        ('garage', 'noun', 'vocab-garage'),
    ],
    'clothes': [
        ('shirt', 'noun', 'vocab-shirt'),
        ('shorts', 'noun', 'fluent-shorts'),
        ('underwear', 'noun', 'fluent-briefs'),
        ('swimsuit', 'noun', 'fluent-one-piece-swimsuit'),
        ('sandals', 'noun', 'fluent-thong-sandal'),
        ('apron', 'noun', 'vocab-apron'),
    ],
    'furniture': [
        ('TV', 'noun', 'fluent-television'),
        ('phone', 'noun', 'fluent-mobile-phone'),
        ('computer', 'noun', 'fluent-laptop'),
        ('fridge', 'noun', 'vocab-refrigerator'),
        ('table', 'noun', 'vocab-table'),
        ('pillow', 'noun', 'vocab-pillow'),
        ('towel', 'noun', 'vocab-towel'),
        ('toothbrush', 'noun', 'fluent-toothbrush'),
        ('key', 'noun', 'fluent-key'),
        ('washing machine', 'noun', 'vocab-washing-machine'),
        ('oven', 'noun', 'vocab-oven'),
        ('closet', 'noun', 'vocab-closet'),
    ],
    'actions': [
        ('eat', 'verb', 'scene-eat'),
        ('drink', 'verb', 'scene-drink-water'),
        ('stand', 'verb', 'fluent-person-standing'),
        ('run', 'verb', 'fluent-person-running'),
        ('swim', 'verb', 'fluent-person-swimming'),
        ('kiss', 'verb', 'fluent-kissing-face'),
        ('cry', 'verb', 'fluent-loudly-crying-face'),
        ('laugh', 'verb', 'fluent-face-with-tears-of-joy'),
        ('hurry', 'verb', 'vocab-hurry'),
        ('cut', 'verb', 'vocab-cut'),
        ('paint', 'verb', 'vocab-paint'),
        ('answer', 'verb', 'vocab-answer'),
    ],
    'time': [
        ('now', 'adverb', 'vocab-now'),
        ('today', 'noun', 'vocab-today'),
        ('tomorrow', 'noun', 'vocab-tomorrow'),
        ('yesterday', 'noun', 'vocab-yesterday'),
        ('afternoon', 'noun', 'vocab-afternoon'),
        ('week', 'noun', 'vocab-week'),
        ('spring', 'noun', 'vocab-spring'),
        ('summer', 'noun', 'vocab-summer'),
        ('winter', 'noun', 'vocab-winter'),
    ],
    'toys': [
        ('robot', 'noun', 'fluent-robot'),
        ('toy car', 'noun', 'fluent-racing-car'),
        ('dolls', 'noun', 'fluent-nesting-dolls'),
        ('bubbles', 'noun', 'fluent-bubbles'),
        ('video game', 'noun', 'fluent-joystick'),
        ('crayons', 'noun', 'fluent-crayon'),
    ],
    'play': [
        ('TV', 'noun', 'fluent-television'),
        ('tablet', 'noun', 'fluent-mobile-phone'),
        ('bubbles', 'noun', 'fluent-bubbles'),
        ('slide', 'noun', 'fluent-playground-slide'),
        ('robot', 'noun', 'fluent-robot'),
    ],
}

# Categories that get their own button on Home (after the existing ones).
HOME_FOLDERS = ['alphabet', 'numbers', 'colors', 'routines', 'weather', 'vehicles']
# The new Drinks category, linked from Eat & drink.
DRINKS = {'id': 'drinks', 'label': 'Drinks', 'symbol': '🥤',
          'symbolPack': 'modernflat', 'symbolKey': 'fluent-cup-with-straw'}


def slug(label):
    return re.sub(r'[^a-z0-9]+', '_', label.lower()).strip('_')


def emoji_for(key, names):
    """Plain emoji fallback (shown only if a picture fails to load)."""
    name = names.get(key, '')
    for candidate in (name, name.replace('-', ' ')):
        try:
            return unicodedata.lookup(candidate.upper())
        except KeyError:
            pass
    return '⬜'


def main():
    pack = json.loads(PACK.read_text(encoding='utf8'))
    history = json.loads(HISTORY.read_text(encoding='utf8'))
    names = {e['k']: e['n'] for e in json.loads(INDEX.read_text(encoding='utf8'))
             if e['p'] == 'modernflat'}
    buttons = {b['id']: b for b in pack['buttons']}
    folders = {f['id']: f for f in pack['folders']}
    views = pack['views']

    if 'drinks' not in folders:
        pack['folders'].append(dict(DRINKS))
        folders['drinks'] = pack['folders'][-1]
    views.setdefault('drinks', [{'columns': 4, 'cells': []}])

    added = 0
    for folder, words in ADD.items():
        cells = views[folder][0]['cells']
        present = {buttons[c['btn']]['label'].lower() for c in cells}
        pictures = {buttons[c['btn']]['symbolKey'] for c in cells}
        for label, word_class, key in words:
            assert (PICTURES / f'{key}.webp').exists(), f'{folder}/{label}: no picture {key}'
            bid = f'v10_{folder}_{slug(label)}'
            if any(c['btn'] == bid for c in cells):
                continue
            # Never two buttons with one word or one picture on a page.
            assert label.lower() not in present, f'{folder}: "{label}" already there'
            assert key not in pictures, f'{folder}/{label}: picture {key} already used'
            buttons[bid] = {
                'id': bid, 'kind': 'item', 'label': label, 'class': word_class,
                'symbol': emoji_for(key, names), 'symbolPack': 'modernflat',
                'symbolKey': key, 'actions': [{'kind': 'addText', 'data': label}]}
            cells.append({'btn': bid})
            present.add(label.lower())
            pictures.add(key)
            added += 1

    def link(bid, folder_id, parent):
        f = folders[folder_id]
        buttons[bid] = {
            'id': bid, 'kind': 'folder', 'label': f['label'], 'class': 'other',
            'symbol': f.get('symbol', '📁'), 'symbolPack': f['symbolPack'],
            'symbolKey': f['symbolKey'],
            'actions': [{'kind': 'gotoFolder', 'data': folder_id}]}
        cells = views[parent][0]['cells']
        if not any(c['btn'] == bid for c in cells):
            cells.append({'btn': bid})

    for folder_id in HOME_FOLDERS:
        link(f'home_{folder_id}', folder_id, 'home')
    # Drinks sits with the other Eat & drink sub-categories.
    link('sub_drinks', 'drinks', 'food')

    # Category buttons together at the end of Home and of Eat & drink.
    for page in ('home', 'food'):
        cells = views[page][0]['cells']
        words = [c for c in cells if buttons[c['btn']]['kind'] != 'folder']
        groups = [c for c in cells if buttons[c['btn']]['kind'] == 'folder']
        views[page][0]['cells'] = words + groups
    views['food'][0]['columns'] = 5

    pack['buttons'] = list(buttons.values())
    pack['packVersion'] = VERSION
    for kind in ('buttons', 'folders'):
        for item in pack[kind]:
            ref = {k: item.get(k) for k in ('label', 'symbol', 'symbolPack', 'symbolKey')}
            refs = history[kind].setdefault(item['id'], [])
            if ref not in refs:
                refs.append(ref)
    PACK.write_text(json.dumps(pack, ensure_ascii=False, indent=1) + '\n', encoding='utf8')
    HISTORY.write_text(json.dumps(history, ensure_ascii=False, indent=1) + '\n', encoding='utf8')
    home = len(views['home'][0]['cells'])
    print(f'{added} new words; pack v{VERSION}; Home {home} buttons; '
          f'{len(pack["buttons"])} buttons, {len(pack["folders"])} categories')


if __name__ == '__main__':
    main()
