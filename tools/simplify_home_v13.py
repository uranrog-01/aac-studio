"""Board v13: an easier Home page and easier-to-find categories.

Home now starts with what a person needs most often, one idea per row
(asking, answers, body needs, how I feel, feelings, people, doing, places,
greetings, questions), and shows 16 categories instead of 23. Fourteen
everyday words are added to Home (water, sleep, break, happy, sad, angry,
scared, hug, mom, dad, come, outside, home, music) and ten words that were
missing from the library (big, small, slow, wrong, start, next to, dizzy,
good morning, good night, excuse me). "All categories" is ordered by topic
instead of by the English alphabet, which meant nothing in other languages.

No picture is new: every added word uses artwork already in the app.
Run once from studio: python tools/simplify_home_v13.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / 'assets/sample_pack.json'
HISTORY = ROOT / 'assets/factory_symbol_history.json'

HOME_ROWS = [
    ['I', 'want', 'more', 'help', 'stop'],
    ['yes', 'no', 'all done', 'wait', 'again'],
    ['eat', 'drink', 'water', 'toilet', 'sleep'],
    ['hurt', 'sick', 'tired', 'hungry', 'break'],
    ['happy', 'sad', 'angry', 'scared', 'hug'],
    ['like', "don't like", 'need', 'my turn', 'not'],
    ['you', 'mom', 'dad', 'he', 'she'],
    ['we', 'my', 'it', 'this', 'that'],
    ['go', 'come', 'look', 'give', 'make'],
    ['open', 'up', 'down', 'outside', 'home'],
    ['hot', 'cold', 'good', 'bad', 'music'],
    ['hi', 'bye', 'please', 'thank you', 'sorry'],
    ['what', 'where', 'who', "don't know"],
]
HOME_FOLDERS = ['People', 'Feelings', 'Calm down', 'Eat & drink', 'Play',
                'Daily routines', 'My body', 'Home things', 'Places', 'School',
                'Animals', 'Actions', 'Colors', 'Numbers', 'Alphabet',
                'All categories']
# label, word class, picture pack, picture key, emoji fallback
HOME_NEW = [
    ('water', 'noun', 'modernflat', 'scene-water', '💧'),
    ('sleep', 'verb', 'modernflat', 'fluent-sleeping-face', '😴'),
    ('break', 'noun', 'modernflat', 'scene-break', '⏸'),
    ('happy', 'adjective', 'modernflat', 'fluent-grinning-face-with-smiling-eyes', '😄'),
    ('sad', 'adjective', 'modernflat', 'fluent-crying-face', '😢'),
    ('angry', 'adjective', 'modernflat', 'fluent-angry-face', '😠'),
    ('scared', 'adjective', 'modernflat', 'fluent-fearful-face', '😨'),
    ('hug', 'verb', 'modernflat', 'scene-hug', '🤗'),
    ('mom', 'noun', 'modernflat', 'fluent-woman', '👩'),
    ('dad', 'noun', 'modernflat', 'fluent-man', '👨'),
    ('come', 'verb', 'mulberry', 'come_,_to', '⬜'),
    ('outside', 'adverb', 'modernflat', 'scene-outside', '🌳'),
    ('home', 'noun', 'modernflat', 'fluent-house', '🏠'),
    ('music', 'noun', 'modernflat', 'fluent-musical-notes', '🎵'),
]
# Mom and dad are the adult faces, so "he" and "she" become a boy and a girl.
HOME_REPICTURE = {'he': ('fluent-boy', '👦'), 'she': ('fluent-girl', '👧')}
# folder, label, word class, pack, key
LIBRARY_NEW = [
    ('describe', 'big', 'adjective', 'mulberry', 'large'),
    ('describe', 'small', 'adjective', 'mulberry', 'little'),
    ('describe', 'slow', 'adjective', 'modernflat', 'fluent-turtle'),
    ('describe', 'wrong', 'adjective', 'mulberry', 'mistake_no_wrong'),
    ('actions', 'start', 'verb', 'mulberry', 'begin_start'),
    ('positions', 'next to', 'preposition', 'mulberry', 'beside_next_to'),
    ('health', 'dizzy', 'adjective', 'modernflat', 'fluent-dizzy'),
    ('chat', 'good morning', 'social', 'mulberry', 'morning'),
    ('chat', 'good night', 'social', 'mulberry', 'night'),
    ('chat', 'excuse me', 'social', 'modernflat', 'fluent-person-raising-hand'),
]
# Categories that left Home stay one tap inside a related category.
MOVED = {'Clothes': ['routines', 'body'], 'Time': ['routines', 'school'],
         'Chat': ['people'], 'Questions': ['people', 'chat'],
         'Describing words': ['actions', 'school']}
ALL_CATEGORIES = [
    'People', 'Jobs', 'Feelings', 'Calm down', 'Chat', 'Questions',
    'Eat & drink', 'Meals', 'Snacks', 'Drinks', 'Fruits', 'Vegetables',
    'Bread & cakes', 'Meat, fish & eggs', 'Milk & cheese', 'Mealtime',
    'Kitchen', 'Cooking',
    'My body', 'Health', 'Daily routines', 'Bathroom things', 'Clothes',
    'Home things', 'Tools', 'TV, phones & computers',
    'Play', 'Toys', 'Sports', 'Music', 'Art & crafts', 'Stories & pretend',
    'Holidays & parties',
    'Places', 'Buildings', 'Shopping & money', 'Vehicles', 'Weather', 'Time',
    'School', 'School things', 'Alphabet', 'Numbers', 'Colors', 'Shapes',
    'Science & space',
    'Animals', 'Wild animals', 'Sea animals', 'Birds', 'Bugs',
    'Reptiles & frogs', 'Animal homes & food', 'Plants',
    'Actions', 'Describing words', 'In, on, under', 'How much',
]


def main():
    pack = json.loads(PACK.read_text(encoding='utf8'))
    history = json.loads(HISTORY.read_text(encoding='utf8'))
    if pack['packVersion'] >= 13:
        raise SystemExit('Board is already v13.')
    buttons = {b['id']: b for b in pack['buttons']}
    views = pack['views']

    def cells(folder):
        return views[folder][0]['cells']

    def labels(folder):
        return {buttons[c['btn']]['label'].lower(): c['btn'] for c in cells(folder)}

    def pictures(folder):
        return {(buttons[c['btn']]['symbolPack'], buttons[c['btn']]['symbolKey'])
                for c in cells(folder)}

    def add(button_id, label, word_class, pack_name, key, emoji='⬜'):
        assert button_id not in buttons, button_id
        suffix = '.webp' if pack_name == 'modernflat' else '.svg'
        base = 'assets/flat_symbols/modernflat' if pack_name == 'modernflat' \
            else 'assets/symbols/mulberry'
        assert (ROOT / base / (key + suffix)).exists(), key
        button = {'id': button_id, 'kind': 'item', 'label': label,
                  'class': word_class, 'symbol': emoji,
                  'actions': [{'kind': 'addText', 'data': label}],
                  'symbolPack': pack_name, 'symbolKey': key}
        buttons[button_id] = button
        pack['buttons'].append(button)
        return button

    # The layouts before this change, so boards whose Home was never
    # rearranged can move to the new one (lib/engine/pack_upgrade.dart).
    layouts = history.setdefault('layouts', {})
    for folder in ('home', 'allcats'):
        layouts.setdefault(folder, []).append([c['btn'] for c in cells(folder)])

    # ---- Home
    home = labels('home')
    for label, word_class, pack_name, key, emoji in HOME_NEW:
        button_id = 'v13_home_' + label.replace(' ', '_')
        add(button_id, label, word_class, pack_name, key, emoji)
        home[label] = button_id
    for label, (key, emoji) in HOME_REPICTURE.items():
        button = buttons[home[label]]
        history['buttons'].setdefault(button['id'], []).append(
            {k: button.get(k) for k in ('label', 'symbol', 'symbolPack', 'symbolKey')})
        button['symbol'], button['symbolKey'] = emoji, key
    words = [w for row in HOME_ROWS for w in row]
    old_words = {buttons[c['btn']]['label'].lower() for c in cells('home')
                 if buttons[c['btn']]['kind'] == 'item'}
    assert old_words <= {w.lower() for w in words}, old_words - {w.lower() for w in words}
    removed_folders = [l for l in home if buttons[home[l]]['kind'] == 'folder'
                       and l not in {f.lower() for f in HOME_FOLDERS}]
    views['home'][0]['cells'] = [{'btn': home[w.lower()]} for w in words + HOME_FOLDERS]
    views['home'][0]['columns'] = 5

    # ---- categories that left Home
    for label, targets in MOVED.items():
        for folder in targets:
            button_id = home[label.lower()]
            button = buttons[button_id]
            if label.lower() in labels(folder) or \
                    (button['symbolPack'], button['symbolKey']) in pictures(folder):
                print(f'  {label} is already in {folder}')
                continue
            cells(folder).append({'btn': button_id})
    print('left Home:', removed_folders)

    # ---- missing words
    for folder, label, word_class, pack_name, key in LIBRARY_NEW:
        assert label not in labels(folder), (folder, label)
        assert (pack_name, key) not in pictures(folder), (folder, key)
        button = add(f'v13_{folder}_' + label.replace(' ', '_'), label,
                     word_class, pack_name, key)
        items = cells(folder)
        # Alphabetical among the words; categories stay at the end.
        at = next((i for i, c in enumerate(items)
                   if buttons[c['btn']]['kind'] == 'folder'), len(items))
        for i in range(at):
            other = buttons[items[i]['btn']]
            if other['id'].startswith(('v11_', 'v13_')) and other['label'].lower() > label:
                at = i
                break
        items.insert(at, {'btn': button['id']})

    # ---- All categories by topic
    allcats = labels('allcats')
    assert sorted(allcats) == sorted(c.lower() for c in ALL_CATEGORIES), \
        set(allcats) ^ {c.lower() for c in ALL_CATEGORIES}
    views['allcats'][0]['cells'] = [{'btn': allcats[c.lower()]} for c in ALL_CATEGORIES]

    # ---- every page: no word and no picture twice
    for folder in views:
        seen_labels, seen_pictures = set(), set()
        for c in cells(folder):
            b = buttons[c['btn']]
            assert b['label'].lower() not in seen_labels, (folder, b['label'])
            assert (b['symbolPack'], b['symbolKey']) not in seen_pictures, (folder, b['label'])
            seen_labels.add(b['label'].lower())
            seen_pictures.add((b['symbolPack'], b['symbolKey']))

    pack['packVersion'] = 13
    PACK.write_text(json.dumps(pack, ensure_ascii=False, indent=1) + '\n', encoding='utf8')
    HISTORY.write_text(json.dumps(history, ensure_ascii=False, indent=1) + '\n', encoding='utf8')
    print(f"Home: {len(words)} words + {len(HOME_FOLDERS)} categories; "
          f"{len(pack['buttons'])} buttons in the board")


if __name__ == '__main__':
    main()
