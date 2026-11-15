import '../models/domain.dart';

/// Word forms for the board's English words: hold a word to say "eats",
/// "ate", "eating", "dogs", "bigger" or "mine" instead of the base word.
///
/// English only for now: the other languages need their own grammar
/// tables, and a wrong form is worse than none, so they show no forms.
class WordForms {
  /// Forms of [word] (an English board label) for its word class, base
  /// form first. Empty when the word has no other forms.
  static List<String> of(String word, WordClass wordClass) {
    final w = word.trim().toLowerCase();
    if (w.isEmpty) return const [];
    final forms = switch (wordClass) {
      WordClass.verb => _verb(w),
      WordClass.noun => _noun(w),
      WordClass.adjective => _adjective(w),
      WordClass.pronoun => _pronouns[w] ?? const <String>[],
      _ => const <String>[],
    };
    final out = <String>[];
    for (final f in [w, ...forms]) {
      if (f.isNotEmpty && !out.contains(f)) out.add(f);
    }
    return out.length > 1 ? out : const [];
  }

  // ------------------------------------------------------------ verbs

  static List<String> _verb(String w) {
    // Phrasal and multi-word verbs ("get dressed", "wash hands") change
    // their first word only.
    final parts = w.split(' ');
    final head = parts.first;
    final rest = parts.length > 1 ? ' ${parts.skip(1).join(' ')}' : '';
    if (head == "don't" || head == 'not' || head.length < 2) return const [];
    return [
      '${thirdPerson(head)}$rest',
      '${past(head)}$rest',
      '${ing(head)}$rest',
    ];
  }

  /// "he eats", "she goes", "it has".
  static String thirdPerson(String v) {
    const irregular = {'be': 'is', 'have': 'has', 'do': 'does', 'go': 'goes', 'can': 'can'};
    if (irregular.containsKey(v)) return irregular[v]!;
    if (RegExp(r'(s|x|z|ch|sh|o)$').hasMatch(v)) return '${v}es';
    if (RegExp(r'[^aeiou]y$').hasMatch(v)) return '${v.substring(0, v.length - 1)}ies';
    return '${v}s';
  }

  static const _irregularPast = {
    'be': 'was', 'become': 'became', 'begin': 'began', 'bend': 'bent', 'bite': 'bit',
    'blow': 'blew', 'break': 'broke', 'bring': 'brought', 'build': 'built',
    'buy': 'bought', 'can': 'could', 'catch': 'caught', 'choose': 'chose',
    'come': 'came', 'cut': 'cut', 'dig': 'dug', 'do': 'did', 'draw': 'drew',
    'dream': 'dreamt', 'drink': 'drank', 'drive': 'drove', 'eat': 'ate',
    'fall': 'fell', 'feed': 'fed', 'feel': 'felt', 'fight': 'fought', 'find': 'found',
    'fly': 'flew', 'forget': 'forgot', 'freeze': 'froze', 'get': 'got', 'give': 'gave',
    'go': 'went', 'grow': 'grew', 'hang': 'hung', 'have': 'had', 'hear': 'heard',
    'hide': 'hid', 'hit': 'hit', 'hold': 'held', 'hurt': 'hurt', 'keep': 'kept',
    'know': 'knew', 'lay': 'laid', 'lead': 'led', 'leave': 'left', 'lend': 'lent',
    'let': 'let', 'lie': 'lay', 'lose': 'lost', 'make': 'made', 'mean': 'meant',
    'meet': 'met', 'pay': 'paid', 'put': 'put', 'read': 'read', 'ride': 'rode',
    'ring': 'rang', 'rise': 'rose', 'run': 'ran', 'say': 'said', 'see': 'saw',
    'sell': 'sold', 'send': 'sent', 'set': 'set', 'sew': 'sewed', 'shake': 'shook',
    'shine': 'shone', 'shoot': 'shot', 'shut': 'shut', 'sing': 'sang', 'sink': 'sank',
    'sit': 'sat', 'sleep': 'slept', 'slide': 'slid', 'speak': 'spoke',
    'spend': 'spent', 'spill': 'spilt', 'spin': 'spun', 'spread': 'spread',
    'stand': 'stood', 'steal': 'stole', 'stick': 'stuck', 'sting': 'stung',
    'sweep': 'swept', 'swim': 'swam', 'swing': 'swung', 'take': 'took',
    'teach': 'taught', 'tear': 'tore', 'tell': 'told', 'think': 'thought',
    'throw': 'threw', 'understand': 'understood', 'wake': 'woke', 'wear': 'wore',
    'win': 'won', 'write': 'wrote',
  };

  static String past(String v) {
    final irregular = _irregularPast[v];
    if (irregular != null) return irregular;
    if (v.endsWith('e')) return '${v}d';
    if (RegExp(r'[^aeiou]y$').hasMatch(v)) return '${v.substring(0, v.length - 1)}ied';
    if (_doubles(v)) return '$v${v[v.length - 1]}ed';
    return '${v}ed';
  }

  static String ing(String v) {
    if (v == 'be') return 'being';
    if (v.endsWith('ie')) return '${v.substring(0, v.length - 2)}ying';
    if (v.endsWith('e') && !v.endsWith('ee') && !v.endsWith('ye') && v.length > 2) {
      return '${v.substring(0, v.length - 1)}ing';
    }
    if (_doubles(v)) return '$v${v[v.length - 1]}ing';
    return '${v}ing';
  }

  /// Short words ending consonant-vowel-consonant double the last letter:
  /// stop/stopped, hug/hugging, run/running.
  static bool _doubles(String v) {
    if (v.length < 3 || v.length > 4) return false;
    final m = RegExp(r'[^aeiou][aeiou]([bdgklmnprt])$').firstMatch(v);
    if (m == null) return false;
    // Not when two vowels come before ("cook", "rain") or a long word.
    return !RegExp(r'[aeiou]{2}[^aeiou]$').hasMatch(v);
  }

  // ------------------------------------------------------------ nouns

  static const _irregularPlural = {
    'child': 'children', 'man': 'men', 'woman': 'women', 'person': 'people',
    'foot': 'feet', 'tooth': 'teeth', 'mouse': 'mice', 'goose': 'geese',
    'fish': 'fish', 'sheep': 'sheep', 'deer': 'deer', 'knife': 'knives',
    'leaf': 'leaves', 'wolf': 'wolves', 'loaf': 'loaves', 'half': 'halves',
    'shelf': 'shelves', 'scarf': 'scarves', 'life': 'lives', 'wife': 'wives',
    'calf': 'calves', 'potato': 'potatoes', 'tomato': 'tomatoes',
    'baby': 'babies', 'ox': 'oxen', 'cactus': 'cacti', 'dice': 'dice',
  };

  /// Words that are already plural or have no plural.
  static const _uncountable = {
    'water', 'milk', 'juice', 'bread', 'rice', 'pasta', 'music', 'money',
    'sand', 'snow', 'rain', 'hair', 'soap', 'butter', 'cheese', 'meat',
    'sugar', 'salt', 'tea', 'coffee', 'homework', 'furniture', 'clothes',
    'glasses', 'scissors', 'trousers', 'jeans', 'shorts', 'pants',
    'pyjamas', 'teeth', 'feet', 'people', 'news', 'fruit', 'food', 'help',
  };

  static List<String> _noun(String w) {
    final parts = w.split(' ');
    final last = parts.last;
    if (_uncountable.contains(w) || _uncountable.contains(last) || last.endsWith('ss') == false && last.endsWith('s') && parts.length == 1 && last.length > 3) {
      return const [];
    }
    final head = parts.length > 1 ? '${parts.take(parts.length - 1).join(' ')} ' : '';
    return ['$head${plural(last)}'];
  }

  static String plural(String n) {
    final irregular = _irregularPlural[n];
    if (irregular != null) return irregular;
    if (RegExp(r'(s|x|z|ch|sh)$').hasMatch(n)) return '${n}es';
    if (RegExp(r'[^aeiou]y$').hasMatch(n)) return '${n.substring(0, n.length - 1)}ies';
    return '${n}s';
  }

  // ------------------------------------------------------------ adjectives

  static List<String> _adjective(String w) {
    const irregular = {
      'good': ['better', 'best'],
      'bad': ['worse', 'worst'],
      'little': ['less', 'least'],
      'far': ['farther', 'farthest'],
    };
    if (irregular.containsKey(w)) return irregular[w]!;
    // Feelings ("tired", "scared") and long words take more / most.
    if (w.contains(' ') || w.endsWith('ed') || _syllables(w) > 2 ||
        (_syllables(w) == 2 && !w.endsWith('y'))) {
      return ['more $w', 'most $w', 'very $w', 'not $w'];
    }
    String stem = w;
    if (RegExp(r'[^aeiou]y$').hasMatch(w)) {
      stem = '${w.substring(0, w.length - 1)}i';
    } else if (w.endsWith('e')) {
      stem = w.substring(0, w.length - 1);
    } else if (RegExp(r'^[^aeiou]*[aeiou][bdgmnpt]$').hasMatch(w)) {
      stem = '$w${w[w.length - 1]}';
    }
    return ['${stem}er', '${stem}est', 'very $w', 'not $w'];
  }

  static int _syllables(String w) =>
      RegExp(r'[aeiouy]+').allMatches(w.replaceAll(RegExp(r'e$'), '')).length;

  // ------------------------------------------------------------ pronouns

  static const _pronouns = {
    'i': ['me', 'my', 'mine', 'myself'],
    'you': ['your', 'yours', 'yourself'],
    'he': ['him', 'his', 'himself'],
    'she': ['her', 'hers', 'herself'],
    'it': ['its', 'itself'],
    'we': ['us', 'our', 'ours'],
    'they': ['them', 'their', 'theirs'],
  };
}
