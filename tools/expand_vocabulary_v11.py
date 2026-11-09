"""Pack v11: a large word library (thousands of words) in clear categories.

Sources, both already bundled with the app:
- Mulberry AAC symbols (assets/symbols/mulberry, CC BY-SA). Categories
  come from tools/data/mulberry_categories.json (from the Cboard project's
  Mulberry index).
- Unused modern flat pictures, grouped with Unicode's emoji groups
  (tools/data/fluent_emoji_groups.json, from unicode.org emoji-test.txt).

When a word has a modern flat picture of the same name, that picture is
used so the style stays consistent. New words go after a page's existing
words, A to Z, and before its category buttons, so learned positions do
not move and installed boards receive them through the normal upgrade.
Home gets Questions, Chat, Describing words and "All categories" (every
category A to Z). Idempotent. Usage: python tools/expand_vocabulary_v11.py
"""
import json
import re
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / 'assets/sample_pack.json'
HISTORY = ROOT / 'assets/factory_symbol_history.json'
INDEX = ROOT / 'assets/symbol_index.json'
FLAT = ROOT / 'assets/flat_symbols/modernflat'
MULBERRY = ROOT / 'assets/symbols/mulberry'
DATA = ROOT / 'tools/data'
VERSION = 11

# New categories: id -> (label, picture key, parent pages).
NEW_FOLDERS = {
    'questions': ('Questions', 'fluent-white-question-mark', ['home']),
    'chat': ('Chat', 'fluent-speech-balloon', ['home']),
    'describe': ('Describing words', 'fluent-sparkles', ['home']),
    'allcats': ('All categories', 'fluent-card-index-dividers', ['home']),
    'shapes': ('Shapes', 'fluent-red-triangle', ['describe']),
    'positions': ('In, on, under', 'fluent-backhand-index-pointing-up', ['describe']),
    'amounts': ('How much', 'fluent-abacus', ['describe']),
    'meals': ('Meals', 'fluent-shallow-pan-of-food', ['food']),
    'bakery': ('Bread & cakes', 'fluent-baguette-bread', ['food']),
    'meatfish': ('Meat, fish & eggs', 'fluent-meat-on-bone', ['food']),
    'dairy': ('Milk & cheese', 'fluent-cow-face', ['food']),
    'cooking': ('Cooking', 'fluent-cook', ['food', 'kitchen']),
    'mealtime': ('Mealtime', 'fluent-spoon', ['food']),
    'bathroom': ('Bathroom things', 'fluent-lotion-bottle', ['body', 'routines']),
    'animalhome': ('Animal homes & food', 'fluent-nest-with-eggs', ['animals']),
    'reptiles': ('Reptiles & frogs', 'fluent-lizard', ['animals']),
    'holidays': ('Holidays & parties', 'fluent-party-popper', ['time', 'play']),
    'tools': ('Tools', 'fluent-hammer-and-wrench', ['furniture']),
    'science': ('Science & space', 'fluent-microscope', ['school']),
    'tech': ('TV, phones & computers', 'fluent-desktop-computer', ['furniture', 'play']),
    'shopping': ('Shopping & money', 'fluent-money-bag', ['places']),
    'art': ('Art & crafts', 'fluent-paintbrush', ['school', 'play']),
    'fantasy': ('Stories & pretend', 'fluent-person-fairy', ['play']),
}

# Mulberry category -> (page, word class). Missing = left out
# (flags, country maps, duplicate letters, computer icons).
MULBERRY_PAGES = {
    'number': ('numbers', 'number'), 'numberActivity': ('numbers', 'verb'),
    'peopleActions': ('actions', 'verb'), 'peopleProfession': ('jobs', 'noun'),
    'peopleRelationship': ('people', 'noun'), 'peopleDescriptive': ('describe', 'adjective'),
    'peopleFeelings': ('feelings', 'adjective'),
    'healthcareBodyParts': ('body', 'noun'), 'healthcareMedicalItems': ('health', 'noun'),
    'healthcareMedicalConditions': ('health', 'noun'),
    'healthcareGroomingItems': ('bathroom', 'noun'),
    'healthcareGroomingActivities': ('routines', 'verb'),
    'buildingHouseholdTasks': ('routines', 'verb'),
    'foodMealsAndSnacks': ('meals', 'noun'), 'foodPastasAndRice': ('meals', 'noun'),
    'foodDiet': ('meals', 'noun'), 'foodFestival': ('holidays', 'noun'),
    'foodKitchenItems': ('kitchen', 'noun'), 'foodKitchenActions': ('cooking', 'verb'),
    'foodIngredients': ('cooking', 'noun'), 'foodFeedingAndEating': ('mealtime', 'noun'),
    'foodVegetablesAndSalads': ('vegetables', 'noun'), 'foodFruit': ('fruits', 'noun'),
    'foodBreadsAndBaking': ('bakery', 'noun'), 'foodSweetsAndDesserts': ('snacks', 'noun'),
    'foodNuts': ('snacks', 'noun'), 'foodDairy': ('dairy', 'noun'),
    'foodEggs': ('meatfish', 'noun'), 'foodMeat': ('meatfish', 'noun'),
    'foodPoultry': ('meatfish', 'noun'), 'foodFishAndSeafood': ('meatfish', 'noun'),
    'drinkType': ('drinks', 'noun'), 'drinkContainersAndMeasures': ('drinks', 'noun'),
    'drinkDescription': ('drinks', 'adjective'), 'drinkActions': ('drinks', 'verb'),
    'clothesGeneral': ('clothes', 'noun'), 'clothesAccessories': ('clothes', 'noun'),
    'clothesJewellery': ('clothes', 'noun'), 'clothesSport': ('clothes', 'noun'),
    'animalMammal': ('animals', 'noun'), 'animalBirds': ('birds', 'noun'),
    'animalSpidersAndInsects': ('insects', 'noun'), 'animalOtherInvertebrates': ('insects', 'noun'),
    'animalFishAndMarineMammals': ('sea', 'noun'), 'animalCrustaceanAndMolluscs': ('sea', 'noun'),
    'animalReptilesAndAmphibians': ('reptiles', 'noun'),
    'animalHabitat': ('animalhome', 'noun'), 'animalFeatures': ('animalhome', 'noun'),
    'animalActivityFeeding': ('animalhome', 'noun'),
    'animalActivityGrooming': ('animalhome', 'noun'), 'animalActivityMisc': ('animalhome', 'noun'),
    'sport': ('sports', 'noun'), 'sportAccessories': ('sports', 'noun'),
    'transportRoad': ('vehicles', 'noun'), 'transportAir': ('vehicles', 'noun'),
    'transportWater': ('vehicles', 'noun'), 'transportRail': ('vehicles', 'noun'),
    'transportSpace': ('vehicles', 'noun'),
    'buildingContents': ('furniture', 'noun'), 'buildingFurniture': ('furniture', 'noun'),
    'buildingEquipmentAndDevices': ('furniture', 'noun'),
    'buildingStructure': ('places2', 'noun'), 'buildingPublic': ('places2', 'noun'),
    'buildingResidential': ('places2', 'noun'), 'buildingGardenAndFarm': ('places2', 'noun'),
    'buildingOfficeAndFactory': ('places2', 'noun'), 'buildingSchool': ('school', 'noun'),
    'buildingShop': ('shopping', 'noun'), 'money': ('shopping', 'noun'),
    'descriptiveQuantity': ('amounts', 'adjective'), 'descriptiveShape': ('shapes', 'noun'),
    'descriptiveState': ('describe', 'adjective'),
    'descriptivePosition': ('positions', 'preposition'),
    'descriptiveDirection': ('positions', 'preposition'), 'descriptiveTime': ('time', 'noun'),
    'leisureToys': ('toys', 'noun'), 'leisureGames': ('toys', 'noun'),
    'leisurePlayground': ('play', 'noun'), 'leisureGeneral': ('play', 'noun'),
    'celebrationItem': ('holidays', 'noun'), 'celebrationEvent': ('holidays', 'noun'),
    'religionFestival': ('holidays', 'noun'), 'religionGeneral': ('holidays', 'noun'),
    'holidayAndTravel': ('holidays', 'noun'),
    'plantsAndTrees': ('plants', 'noun'), 'environmentWeather': ('weather', 'noun'),
    'toolsWorkshop': ('tools', 'noun'), 'toolsActions': ('tools', 'verb'),
    'toolsGarden': ('tools', 'noun'),
    'science': ('science', 'noun'), 'scienceAstronomy': ('science', 'noun'),
    'scienceEco': ('science', 'noun'),
    'electricalGeneral': ('tech', 'noun'), 'electricalComputer': ('tech', 'noun'),
    'electricalMedia': ('tech', 'noun'), 'electricalPhone': ('tech', 'noun'),
    'electricalTV': ('tech', 'noun'),
    # communicationAid is left out: device brand names, not words.
    'communicationConversation': ('chat', 'social'), 'communicationSigns': ('chat', 'noun'),
    'workAndSchoolStationery': ('school2', 'noun'), 'workAndSchoolTimetable': ('school', 'noun'),
    'workAndSchoolSubjects': ('school', 'noun'), 'workAndSchoolEducation': ('school', 'noun'),
    'artColour': ('colors', 'adjective'), 'artMaking': ('art', 'noun'),
    'musicInstrument': ('instruments', 'noun'), 'question': ('questions', 'question'),
}

# Unicode emoji subgroup -> (page, word class) for unused modern flat pictures.
EMOJI_PAGES = {
    'Activities/arts & crafts': ('art', 'noun'), 'Activities/award-medal': ('sports', 'noun'),
    'Activities/event': ('holidays', 'noun'), 'Activities/game': ('toys', 'noun'),
    'Activities/sport': ('sports', 'noun'),
    'Animals & Nature/animal-mammal': ('animals', 'noun'),
    'Animals & Nature/animal-bird': ('birds', 'noun'),
    'Animals & Nature/animal-bug': ('insects', 'noun'),
    'Animals & Nature/animal-marine': ('sea', 'noun'),
    'Animals & Nature/animal-reptile': ('reptiles', 'noun'),
    'Animals & Nature/animal-amphibian': ('reptiles', 'noun'),
    'Animals & Nature/plant-flower': ('plants', 'noun'),
    'Animals & Nature/plant-other': ('plants', 'noun'),
    'Food & Drink/dishware': ('kitchen', 'noun'), 'Food & Drink/drink': ('drinks', 'noun'),
    'Food & Drink/food-asian': ('meals', 'noun'), 'Food & Drink/food-marine': ('meatfish', 'noun'),
    'Food & Drink/food-prepared': ('meals', 'noun'), 'Food & Drink/food-sweet': ('snacks', 'noun'),
    'Food & Drink/food-vegetable': ('vegetables', 'noun'),
    'Food & Drink/food-fruit': ('fruits', 'noun'),
    'Objects/book-paper': ('school2', 'noun'), 'Objects/clothing': ('clothes', 'noun'),
    'Objects/computer': ('tech', 'noun'), 'Objects/household': ('furniture', 'noun'),
    'Objects/light & video': ('tech', 'noun'), 'Objects/lock': ('furniture', 'noun'),
    'Objects/mail': ('school2', 'noun'), 'Objects/medical': ('health', 'noun'),
    'Objects/money': ('shopping', 'noun'), 'Objects/music': ('instruments', 'noun'),
    'Objects/musical-instrument': ('instruments', 'noun'), 'Objects/office': ('school2', 'noun'),
    'Objects/phone': ('tech', 'noun'), 'Objects/science': ('science', 'noun'),
    'Objects/tool': ('tools', 'noun'), 'Objects/writing': ('school2', 'noun'),
    'People & Body/body-parts': ('body', 'noun'),
    'People & Body/person-activity': ('actions', 'verb'),
    'People & Body/person-resting': ('actions', 'verb'),
    'People & Body/person-fantasy': ('fantasy', 'noun'),
    'People & Body/person-role': ('jobs', 'noun'),
    'People & Body/person-sport': ('sports', 'verb'),
    'Travel & Places/hotel': ('places2', 'noun'),
    'Travel & Places/place-building': ('places2', 'noun'),
    'Travel & Places/place-religious': ('places2', 'noun'),
    'Travel & Places/place-geographic': ('places', 'noun'),
    'Travel & Places/place-map': ('places', 'noun'),
    'Travel & Places/place-other': ('places', 'noun'),
    'Travel & Places/sky & weather': ('weather', 'noun'),
    'Travel & Places/time': ('time', 'noun'),
    'Travel & Places/transport-air': ('vehicles', 'noun'),
    'Travel & Places/transport-ground': ('vehicles', 'noun'),
    'Travel & Places/transport-water': ('vehicles', 'noun'),
}

TONES = ('-light', '-medium-light', '-medium', '-medium-dark', '-dark')
SKIP_WORDS = re.compile(r'\b(button|sign|symbol|face|mark|arrow|o.clock|thirty|keycap|'
                        r'flag|dots?|lower case|upper case|japan|japanese|globe showing|'
                        r'mount fuji|female side|wearing)\b', re.I)


def mulberry_label(name, category):
    label = re.sub(r'\s*,\s*to$', '', name)           # "come , to" -> "come"
    verb = label != name
    # "breakfast 2" -> "breakfast", "baker 2a" -> "baker"
    label = re.sub(r'\s+\d+[a-z]?(?=\s|$)', '', label)
    if ' , ' in label:                                   # "cheese on toast , melted"
        head, tail = label.split(' , ', 1)
        label = f'{tail} {head}'
    if category == 'peopleFeelings':
        label = re.sub(r'\s+(lady|man)$', '', label)
    label = re.sub(r'\s+', ' ', label).strip()
    if '   ' in name or SKIP_WORDS.search(label) or not label:
        return None, verb
    return label, verb


def emoji_label(name):
    if re.match(r'^(man|woman|men|women|boy|girl|family|couple|kiss)\b', name, re.I):
        return None                                      # gendered copies
    label = re.sub(r'^person\s+', '', name, flags=re.I)
    if re.match(r'^(in|with|on|getting|taking|in)\b', label, re.I) and \
            not label.lower().startswith('taking bath'):
        return None
    if SKIP_WORDS.search(label) or ':' in label or len(label.split()) > 3:
        return None
    return label if label.isupper() else label[0].lower() + label[1:]


def emoji_for(name):
    for candidate in (name, name.replace('-', ' ')):
        try:
            return unicodedata.lookup(candidate.upper())
        except KeyError:
            pass
    return '⬜'


def slug(label):
    return re.sub(r'[^a-z0-9]+', '_', label.lower()).strip('_')


def main():
    pack = json.loads(PACK.read_text(encoding='utf8'))
    history = json.loads(HISTORY.read_text(encoding='utf8'))
    index = json.loads(INDEX.read_text(encoding='utf8'))
    categories = json.loads((DATA / 'mulberry_categories.json').read_text(encoding='utf8'))
    emoji_groups = json.loads((DATA / 'fluent_emoji_groups.json').read_text(encoding='utf8'))

    flat_by_name = {}
    flat_name = {}
    for e in index:
        if e['p'] == 'modernflat' and not e['k'].endswith(TONES):
            flat_by_name.setdefault(e['n'].lower(), e['k'])
            flat_name.setdefault(e['k'], e['n'])
    mulberry = {}
    for e in index:
        if e['p'] == 'mulberry' and (MULBERRY / f"{e['k']}.svg").exists():
            mulberry.setdefault(e['k'], e['n'])

    buttons = {b['id']: b for b in pack['buttons']}
    folders = {f['id']: f for f in pack['folders']}
    views = pack['views']
    used_flat = {b['symbolKey'] for b in buttons.values() if b.get('symbolPack') == 'modernflat'}
    used_flat |= {f['symbolKey'] for f in folders.values()}

    # Categories first, so their pages exist.
    for fid, (label, key, _) in NEW_FOLDERS.items():
        assert (FLAT / f'{key}.webp').exists(), f'{fid}: no picture {key}'
        if fid not in folders:
            folder = {'id': fid, 'label': label, 'symbol': emoji_for(flat_name.get(key, '')),
                      'symbolPack': 'modernflat', 'symbolKey': key}
            pack['folders'].append(folder)
            folders[fid] = folder
        views.setdefault(fid, [{'columns': 5, 'cells': []}])

    # Collect candidate words per page.
    wanted = {}
    for key, name in sorted(mulberry.items(), key=lambda kv: kv[1].lower()):
        category = categories.get(key.lower())
        if category not in MULBERRY_PAGES:
            continue
        page, word_class = MULBERRY_PAGES[category]
        label, verb = mulberry_label(name, category)
        if not label:
            continue
        flat = flat_by_name.get(label.lower())
        ref = ('modernflat', flat) if flat else ('mulberry', key)
        wanted.setdefault(page, []).append((label, 'verb' if verb else word_class, ref))
    for key, group in sorted(emoji_groups.items()):
        # Skin-tone copies are drawn automatically from the chosen tone.
        if (key in used_flat or key.endswith(TONES) or group not in EMOJI_PAGES
                or not (FLAT / f'{key}.webp').exists()):
            continue
        label = emoji_label(flat_name.get(key, key[7:].replace('-', ' ')))
        if label:
            page, word_class = EMOJI_PAGES[group]
            wanted.setdefault(page, []).append((label, word_class, ('modernflat', key)))

    added = 0
    for page, words in wanted.items():
        cells = views[page][0]['cells']
        labels = {buttons[c['btn']]['label'].lower() for c in cells}
        pictures = {(buttons[c['btn']].get('symbolPack'), buttons[c['btn']]['symbolKey'])
                    for c in cells}
        new = []
        for label, word_class, (pack_name, key) in sorted(words, key=lambda w: w[0].lower()):
            bid = f'v11_{page}_{slug(label)}'
            if bid in buttons and any(c['btn'] == bid for c in cells):
                continue
            if label.lower() in labels or (pack_name, key) in pictures:
                continue                                 # one word, one picture per page
            buttons[bid] = {
                'id': bid, 'kind': 'item', 'label': label, 'class': word_class,
                'symbol': emoji_for(flat_name.get(key, '')) if pack_name == 'modernflat' else '⬜',
                'symbolPack': pack_name, 'symbolKey': key,
                'actions': [{'kind': 'addText', 'data': label}]}
            labels.add(label.lower())
            pictures.add((pack_name, key))
            new.append({'btn': bid})
            added += 1
        # New words after the existing words, before the category buttons.
        split = next((i for i, c in enumerate(cells) if buttons[c['btn']]['kind'] == 'folder'),
                     len(cells))
        views[page][0]['cells'] = cells[:split] + new + cells[split:]

    def link(parent, fid, bid):
        f = folders[fid]
        buttons[bid] = {
            'id': bid, 'kind': 'folder', 'label': f['label'], 'class': 'other',
            'symbol': f.get('symbol', '📁'), 'symbolPack': f.get('symbolPack'),
            'symbolKey': f.get('symbolKey'), 'actions': [{'kind': 'gotoFolder', 'data': fid}]}
        cells = views[parent][0]['cells']
        if not any(c['btn'] == bid for c in cells):
            cells.append({'btn': bid})

    for fid, (_, _, parents) in NEW_FOLDERS.items():
        for parent in parents:
            link(parent, fid, f'link_{parent}_{fid}')
    # Every category, A to Z, one tap from Home.
    for fid in sorted(folders, key=lambda f: folders[f]['label'].lower()):
        if fid not in ('home', 'allcats') and views.get(fid):
            link('allcats', fid, f'all_{fid}')
    views['allcats'][0]['cells'].sort(key=lambda c: buttons[c['btn']]['label'].lower())

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
    words = sum(1 for b in pack['buttons'] if b['kind'] == 'item')
    print(f'{added} new words; pack v{VERSION}; {words} words, {len(pack["buttons"])} buttons, '
          f'{len(pack["folders"])} categories; Home {len(views["home"][0]["cells"])}')
    for page in sorted(views, key=lambda p: -len(views[p][0]['cells']))[:8]:
        print(f'  {page}: {len(views[page][0]["cells"])}')


if __name__ == '__main__':
    main()
