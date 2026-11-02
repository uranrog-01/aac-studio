"""Resume the 10,000-symbol modern-flat expansion without counting queued jobs.

Catalog definitions are planning data. Only visually approved, exported WebPs
enter the app's modernflat pack. Generation receipts persist after every image.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import shutil
import sqlite3
from datetime import datetime, timezone

from PIL import Image, ImageDraw, ImageFont

from flatten_symbols import render, optimize

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT.parent/'work/modern_flat_expansion'
DEST = ROOT/'assets/flat_symbols/modernflat'
CATALOG = ROOT/'docs/modern-flat-expansion-jobs.json'
APPROVED = ROOT/'docs/modern-flat-expansion-assets.json'
BASE_COUNT = 3264
TARGET = 10000


def read(path, fallback=None):
    return json.loads(path.read_text(encoding='utf8')) if path.exists() else fallback


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=1)+'\n', encoding='utf8')


def normal(value):
    value = re.sub('[^a-z0-9]+',' ',value.lower()).strip()
    return {'mother':'mom','father':'dad','grandmother':'grandma',
            'grandfather':'grandpa','automobile':'car','aeroplane':'airplane',
            'grey':'gray','neighbour':'neighbor'}.get(value,value)


# Search words a child would never type, or that point at a different picture.
MISLEADING_ALIASES = {
    'cervix', 'pharynx', 'caput', 'dorsum', 'genu', 'articulatio genus', 'fe',
    'hebdomad', 'macrocosm', 'existence', 'creation', 'pall', 'mantle', 'blow',
    'drive', 'register', 'supply', 'append', 'min', 'cullender', 'terra firma',
    'be adrift', 'travel rapidly', 'move quickly', 'pool', 'iron metal',
    'geometric plane', 'flat plane', 'dishwashing staff'}
# Rarer synonyms that are still everyday words for children and caregivers.
HELPFUL_ALIASES = {
    'chalkboard', 'skillet', 'frypan', 'cupboard', 'drape', 'drapery', 'icebox',
    'drinking fountain', 'chopping board', 'springtime', 'summertime',
    'wintertime', 'flooring', 'paving', 'beanbag toy', 'washer'}
# Never planned for a children's AAC app.
UNSUITABLE = re.compile(
    r'\b(weapon|firearm|gun(?!wale)|rifle|pistol|revolver|shotgun|explosive|bomb|grenade|'
    r'ammunition|bullets?\b|missile|artillery|bayonet|dagger|alcoholic|(?<!chocolate )liquor|'
    r'whisk(e)?y|vodka|tobacco|cigar|cigarette|narcotic|gambl|casino|(?<!non-)sexual|erotic|'
    r'lingerie|condom|brothel|execution|corpse)\w*', re.I)
# Matched only through an unrelated word in the definition.
SUITABLE = {'gay man', 'gay', 'gay woman', 'significant other', 'straight person',
            'white chocolate', 'dark chocolate', 'news reader', 'bulletin board system',
            'spore', 'patent log', 'gun rest', 'firework', 'space probe', 'card table'}


def child_alias(alias, label, taken, common):
    """Keep a synonym only if it is an everyday word for this picture alone."""
    a = normal(alias)
    if a == normal(label) or a in MISLEADING_ALIASES or a in taken:
        return False
    return a in HELPFUL_ALIASES or all(word in common for word in a.split())


def catalog():
    """One planned picture per meaning/label; synonyms stay aliases."""
    existing = read(CATALOG, [])
    index = read(ROOT/'assets/symbol_index.json')
    baseline = {normal(e['n']) for e in index if e['p']=='modernflat'}
    names = baseline | {normal(e['label']) for e in existing}
    used_synsets = {e.get('meaningId') for e in existing if e.get('meaningId')}
    candidates = read(WORK/'wordnet_candidates.json')
    lexicon = {}
    # Exclude an existing modern meaning if *any* synonym is already indexed.
    for filename in ('data.noun','data.verb'):
        for line in (WORK/'wordnet'/filename).read_text(encoding='ascii').splitlines():
            if not line or not line[0].isdigit():
                continue
            fields = line.split('|',1)[0].split()
            offset, pos = fields[0], fields[2]
            words = [fields[4+i*2].replace('_',' ') for i in range(int(fields[3],16))]
            lexicon[(offset,pos)] = words
    # First priority is already used AAC vocabulary, then corpus frequency.
    old_aac = {normal(e['n']) for e in index if e['p']=='mulberry'}
    candidates.sort(key=lambda c: (normal(c[1]) in old_aac,c[0]),reverse=True)
    for score, label, category, definition, offset, pos, frequency, sense in candidates:
        if len(existing) >= TARGET-BASE_COUNT:
            break
        meaning = f'wordnet-3.0:{pos}:{offset}'
        synonyms = lexicon[(offset,pos)]
        canonical = normal(label)
        if meaning in used_synsets or canonical in names:
            continue
        if any(normal(s) in baseline for s in synonyms):
            continue
        # Concrete objects/actions are suitable for unlabelled AAC pictures.
        if category in {'noun.time','noun.feeling','verb.perception','verb.communication'} and frequency < 3:
            continue
        if sense > 2 and frequency < 3:
            continue
        if any(term in canonical.split() for term in ('slang','abbreviation','genus','family','order')):
            continue
        if any(s in definition.lower() for s in ('offensive term','offensive name','derogatory','insulting','prostitut','a genus of','a family of','an order of')):
            continue
        if canonical in {'mistress','pussy','whore','breed','nymphomaniac','nude','consummate','jack off','sleep around'}:
            continue
        if re.search(r'\b(kill|murder|rape|torture|suicide|coitus|copulat|masturbat|pornograph|ejaculat|orgasm)\w*',definition,re.I):
            continue
        if canonical not in SUITABLE and (UNSUITABLE.search(label) or UNSUITABLE.search(definition)):
            continue
        # Use the primary sense for polysemous bare words; definitions are
        # recorded so the picture depicts its selected meaning consistently.
        key = 'vocab-' + re.sub('[^a-z0-9]+','-',label.lower()).strip('-')
        if any(e['key']==key for e in existing):
            continue
        kind = 'action' if pos=='v' else 'object or subject'
        scene = (f'Illustrate the {kind} "{label}" with this exact meaning: {definition}. '
                 'Use a concrete, instantly recognizable depiction; no written labels. ')
        if pos=='v':
            scene += 'Show a friendly person clearly performing the action, with only its necessary props.'
        elif category=='noun.person':
            scene += 'Show a friendly person with the clothing, pose or everyday props that clearly identify this role. No stereotypes or real-person likeness.'
        elif category=='noun.body':
            scene += 'Use a simple non-graphic educational body-part illustration. No wounds or blood.'
        else:
            scene += 'Show the actual recognizable subject, isolated and uncluttered; include only details that identify it.'
        aliases = sorted({s.lower() for s in synonyms if re.fullmatch(r"[a-zA-Z][a-zA-Z '-]*",s) and len(s)<=40})
        existing.append({'key':key,'label':label,'category':category,
                         'scene':scene,'meaningId':meaning,'definition':definition,
                         'aliases':aliases,'source':'WordNet 3.0; vocabulary definition only',
                         'priorityFrequency':frequency})
        names.add(canonical)
        used_synsets.add(meaning)
    assert len(existing) == TARGET-BASE_COUNT, f'Only {len(existing)} suitable concepts'
    assert len({e['key'] for e in existing})==len(existing)
    assert len({normal(e['label']) for e in existing})==len(existing)
    write(CATALOG, existing)
    license_path = ROOT/'assets/flat_symbols/LICENSE-WordNet.txt'
    shutil.copy2(WORK/'wordnet/LICENSE',license_path)
    report = {'target':TARGET,'baselineArtworks':BASE_COUNT,'additionalPlanned':len(existing),
              'planningIsNotCompletedArtwork':True,'categories':dict(Counter(e['category'] for e in existing)),
              'definitionSource':'https://www.nltk.org/howto/wordnet.html',
              'definitionDataSha256':hashlib.sha256((WORK/'wordnet.zip').read_bytes()).hexdigest()}
    write(ROOT/'docs/modern-flat-expansion-plan.json', report)
    print(json.dumps(report),flush=True)


def stage():
    count = 0
    approved = read(APPROVED,{})
    for path in sorted((WORK/'receipts').glob('*.json')):
        receipt = read(path)
        if receipt['key'] in approved:
            continue
        render((receipt['original'],WORK/'staged'/f'{receipt["key"]}.webp'))
        optimize(WORK/'staged'/f'{receipt["key"]}.webp')
        count += 1
    print(f'Staged {count} generated pictures; not yet counted in the app.',flush=True)


def sheet():
    approved = read(APPROVED,{})
    jobs = [read(p) for p in sorted((WORK/'receipts').glob('*.json'))
            if p.stem not in approved and (WORK/'staged'/f'{p.stem}.webp').exists()]
    font = ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',18)
    for page in range((len(jobs)+23)//24):
        chunk = jobs[page*24:(page+1)*24]
        image = Image.new('RGB',(1200,((len(chunk)+5)//6)*205),'#F2F5F9')
        draw = ImageDraw.Draw(image)
        for n,job in enumerate(chunk):
            icon = Image.open(WORK/'staged'/f'{job["key"]}.webp').convert('RGBA')
            icon.thumbnail((170,165),Image.Resampling.LANCZOS)
            x,y=n%6*200,n//6*205
            image.paste(icon,(x+(200-icon.width)//2,y),icon)
            draw.text((x+5,y+170),job['label'],font=font,fill='#18324D')
        output = ROOT/f'docs/modern-flat-new-review-{page+1}.png'
        image.save(output)
        write(output.with_suffix('.json'),[job['key'] for job in chunk])
        print(output,flush=True)


def approve(keys):
    approved = read(APPROVED,{})
    for key in keys:
        receipt = read(WORK/'receipts'/f'{key}.json')
        assert receipt, key
        source = WORK/'staged'/f'{key}.webp'
        with Image.open(source) as image:
            image.load()
            assert image.format=='WEBP' and max(image.size)<=340
            assert image.convert('RGBA').getchannel('A').getbbox(),key
        shutil.copy2(source,DEST/f'{key}.webp')
        approved[key] = {**receipt,'status':'visually reviewed and approved',
                         'sha256':hashlib.sha256(source.read_bytes()).hexdigest()}
    write(APPROVED, approved)
    apply()


def prioritize():
    """AAC priority words first (docs/aac-priority-words.json); drop unsuitable jobs.

    Words already drawn in modern flat are skipped. Existing catalog jobs for a
    priority word get its precise scene; missing ones are added. The queue then
    leases jobs by priority, then by catalog order.
    """
    words = read(ROOT/'docs/aac-priority-words.json')['words']
    jobs = read(CATALOG,[])
    approved = read(APPROVED,{})
    index = read(ROOT/'assets/symbol_index.json')
    drawn = {normal(e['n']) for e in index if e['p']=='modernflat'}
    by_label = {normal(j['label']):j for j in jobs}
    pruned = {j['key'] for j in jobs if j['key'] not in approved and normal(j['label']) not in SUITABLE and
              (UNSUITABLE.search(j['label']) or UNSUITABLE.search(j.get('definition','')))}
    jobs = [j for j in jobs if j['key'] not in pruned]
    for j in jobs:
        j.pop('priority',None)
    queued = skipped = 0
    for rank,(word,kind,scene) in enumerate(words):
        if normal(word) in drawn:
            skipped += 1
            continue
        job = by_label.get(normal(word))
        if job is None or job['key'] in pruned:
            key = 'vocab-'+re.sub('[^a-z0-9]+','-',word.lower()).strip('-')
            job = {'key':key,'label':word,'category':'aac.'+kind,'source':'AAC priority list'}
            jobs.append(job)
            by_label[normal(word)] = job
        job['scene'] = scene + ' Exactly this meaning of "'+word+'"; no written words.'
        job['priority'] = rank
        queued += 1
    write(CATALOG,jobs)
    connection=sqlite3.connect(WORK/'jobs.sqlite3',timeout=30)
    for key in pruned:
        connection.execute("UPDATE jobs SET status='removed' WHERE key=? AND status='queued'",(key,))
    for key in {k for (k,) in connection.execute("SELECT key FROM jobs WHERE status='approved'")}-set(approved):
        connection.execute("UPDATE jobs SET status='removed' WHERE key=?",(key,))
    for job in jobs:
        connection.execute('INSERT OR IGNORE INTO jobs (key,body,status) VALUES (?,?,?)',(job['key'],json.dumps(job),'queued'))
        connection.execute("UPDATE jobs SET body=? WHERE key=? AND status='queued'",(json.dumps(job),job['key']))
    connection.commit()
    first = [r[0] for r in connection.execute(
        "SELECT json_extract(body,'$.label') FROM jobs WHERE status='queued' "+QUEUE_ORDER+" LIMIT 12")]
    counts = dict(connection.execute('SELECT status,count(*) FROM jobs GROUP BY status'))
    connection.close()
    plan = read(ROOT/'docs/modern-flat-expansion-plan.json',{})
    plan.update({'additionalPlanned':len(jobs),'priorityWords':queued,
                 'priorityWordsAlreadyDrawn':skipped,
                 'removedUnsuitable':sorted(set(plan.get('removedUnsuitable',[]))|pruned),
                 'categories':dict(Counter(j['category'] for j in jobs)),
                 'order':'AAC priority list first (docs/aac-priority-words.json), then catalog order'})
    write(ROOT/'docs/modern-flat-expansion-plan.json',plan)
    print(json.dumps({'priorityQueued':queued,'alreadyDrawn':skipped,'removedUnsuitable':len(pruned),
                      'queue':counts,'next':first}),flush=True)


# Priority words first; everything else keeps catalog order.
QUEUE_ORDER = "ORDER BY COALESCE(json_extract(body,'$.priority'),1000000), rowid"


def apply():
    approved = read(APPROVED,{})
    index = read(ROOT/'assets/symbol_index.json')
    manifest = read(ROOT/'docs/flat-symbol-manifest.json')
    seen = {(e['p'],e['k'],e['n'].casefold()) for e in index}
    common = set((ROOT/'assets/prediction_en_top10k.txt').read_text(encoding='utf8').lower().split())
    owners = {}
    for e in index:
        if e['p'] in ('modernflat','mulberry'):
            owners.setdefault(normal(e['n']),set()).add(e['k'])
    for key,item in approved.items():
        path = DEST/f'{key}.webp'
        assert path.exists(),key
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        assert digest==item['sha256'],key
        manifest['files']['modernflat/'+key+'.webp']=digest
        manifest['generatedScenes'][key]=item['scene']
        taken = {n for n,keys in owners.items() if keys-{key}}
        words = [a for a in item.get('aliases',[]) if child_alias(a,item['label'],taken,common)]
        for name in [item['label'],*words]:
            identity=('modernflat',key,name.casefold())
            if identity not in seen:
                index.append({'p':'modernflat','k':key,'n':name})
                seen.add(identity)
    manifest['fileCount']=len(manifest['files'])
    manifest['counts']['modernflat']=len(list(DEST.glob('*.webp')))
    assert manifest['counts']['modernflat']==BASE_COUNT+len(approved), 'Unreviewed or untracked modern artwork'
    manifest['indexNames']=len(index)
    manifest['uniqueIndexedPictures']=len({(e['p'],e['k']) for e in index})
    manifest['bytes']=sum(p.stat().st_size for p in (ROOT/'assets/flat_symbols').glob('*/*.webp'))
    manifest['expansionTarget']=TARGET
    manifest['additionalReviewedArtworks']=len(approved)
    (ROOT/'assets/symbol_index.json').write_text(json.dumps(index,ensure_ascii=False,separators=(',',':')),encoding='utf8')
    write(ROOT/'docs/flat-symbol-manifest.json',manifest)
    progress()


def progress():
    approved = read(APPROVED,{})
    actual = len(list(DEST.glob('*.webp')))
    status = {'target':TARGET,'baseline':BASE_COUNT,'modernFlatArtworks':actual,
              'reviewedNewArtworks':len(approved),'remaining':max(0,TARGET-actual),
              'generatedReceipts':len(list((WORK/'receipts').glob('*.json'))),
              'countIsActualWebPFiles':True}
    write(ROOT/'docs/modern-flat-expansion-progress.json',status)
    print(json.dumps(status),flush=True)


def initqueue():
    WORK.mkdir(exist_ok=True)
    jobs=read(CATALOG,[])
    approved=read(APPROVED,{})
    batch2={j['key'] for j in read(WORK/'batch2.json',[])}
    connection=sqlite3.connect(WORK/'jobs.sqlite3',timeout=30)
    connection.execute('CREATE TABLE IF NOT EXISTS jobs (key TEXT PRIMARY KEY, body TEXT NOT NULL, status TEXT NOT NULL, lease TEXT)')
    for job in jobs:
        key=job['key']
        status='approved' if key in approved else 'generated' if (WORK/'receipts'/f'{key}.json').exists() else 'generating' if key in batch2 else 'queued'
        connection.execute('INSERT OR IGNORE INTO jobs (key,body,status) VALUES (?,?,?)',(key,json.dumps(job),status))
        if status in ('approved','generated'):
            connection.execute('UPDATE jobs SET body=?,status=? WHERE key=?',(json.dumps(job),status,key))
    connection.commit()
    print(json.dumps(dict(connection.execute('SELECT status,count(*) FROM jobs GROUP BY status'))),flush=True)
    connection.close()


def claim():
    generation_available()
    connection=sqlite3.connect(WORK/'jobs.sqlite3',timeout=30)
    connection.execute('BEGIN IMMEDIATE')
    row=connection.execute("SELECT key,body FROM jobs WHERE status='queued' "+QUEUE_ORDER+" LIMIT 1").fetchone()
    if row:
        connection.execute("UPDATE jobs SET status='generating',lease=? WHERE key=?",(datetime.now(timezone.utc).isoformat(),row[0]))
    connection.commit()
    connection.close()
    print(row[1] if row else 'null',flush=True)


def claimbatch(keys):
    generation_available()
    limit=int(keys[0]) if keys else 48
    assert 1<=limit<=128
    connection=sqlite3.connect(WORK/'jobs.sqlite3',timeout=30)
    connection.execute('BEGIN IMMEDIATE')
    rows=connection.execute("SELECT key,body FROM jobs WHERE status='queued' "+QUEUE_ORDER+" LIMIT ?",(limit,)).fetchall()
    stamp=datetime.now(timezone.utc).isoformat()
    connection.executemany("UPDATE jobs SET status='generating',lease=? WHERE key=?",[(stamp,r[0]) for r in rows])
    connection.commit()
    connection.close()
    print('['+','.join(r[1] for r in rows)+']',flush=True)


def mark(keys):
    key,status=keys
    assert status in ('generated','failed','queued','approved')
    connection=sqlite3.connect(WORK/'jobs.sqlite3',timeout=30)
    connection.execute('UPDATE jobs SET status=? WHERE key=?',(status,key))
    connection.commit()
    connection.close()
    print(status,flush=True)


def generation_available():
    limit=read(WORK/'tool-limit.json',{})
    if limit.get('resetEpoch',0)>datetime.now(timezone.utc).timestamp():
        raise RuntimeError('Built-in image generation is limited until '+limit['resetNewYork']+'. Saved jobs remain queued; no API fallback has been started.')


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('command',choices=['catalog','prioritize','stage','sheet','approve','apply','progress','initqueue','claim','claimbatch','mark'])
    parser.add_argument('keys',nargs='*')
    args=parser.parse_args()
    if args.command=='approve':approve(args.keys)
    elif args.command=='mark':mark(args.keys)
    elif args.command=='claimbatch':claimbatch(args.keys)
    else:globals()[args.command]()
