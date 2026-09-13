class_name ReadingWords
extends RefCounted
## THE MEANING LAYER — the reading said out loud, in three languages.
##
## `hexagram.gd` turns six bits into a King Wen NUMBER and stops there, because
## its header says the canon is not in that file. `creature.gd` turns the
## number into a reading — hexagram, one changing line, the hexagram it walks
## toward, a floored vitality — and stops there for the same reason. A number
## under a creature's name is honest and it is also mute: "37" tells the owner
## nothing they can act on, and the whole point of Phase 13 was that the six
## needs ARE the six lines, which means the six needs are the thing worth
## saying.
##
## ── ROAD D, THE OWNER'S RULING, AND THE WHOLE OF WHAT THIS FILE MAY DO ───────
##
## HYBRID. The sentence is COMPOSED FROM THE CREATURE'S OWN DATA — which need
## moved, how long it has been quiet, how full it is. The I-Ching canon
## contributes EXACTLY ONE THING: the sixty-four NAMES, used as a TITLE. That
## is the entire loan.
##
## WHAT IS NOT HERE, and a grep will confirm it: no judgment text, no image
## text, no line text, no commentary, from any edition, in any language. The
## NAMES below are the common public-domain renderings of the Wilhelm/Legge
## lineage for the latin words and the plain traditional character for the
## chinese one — a hexagram's name is a label on a number, the way "Tuesday" is
## a label on a weekday, and labels are all this file takes. The Portuguese
## column is not a translation of anybody's edition: it is a short faithful
## rendering written here, for this app.
##
## NO ix64-core IMPORT, the same standing boundary `creature.gd` and
## `hexagram.gd` both hold. The huohoutu canon port is still a later,
## parity-locked step and this file does not pre-empt it: a NAME is not a text.
##
## ── THE VOICE, WHICH IS THE OTHER HALF OF THE LAW ───────────────────────────
##
## THE COACH NEVER SCOLDS. `character.gd` has four weather words and no
## hospital word; `creature.gd` floors vitality so a rough week cannot end a
## creature. This file is where that law would first be broken, because this
## file is the only one in the chain that writes SENTENCES. So:
##
##   a quiet observation, and at most a soft request. Never an order, never an
##   alarm, never a reproach, in any of the three languages.
##
## "food is the line that moved — it has been quiet since morning" is the
## shape. A reproach about a skipped meal is not, and no branch below can
## produce one.
## `tests/reading_words_smoke.gd` greps this whole file against a list of the
## words that would mean the law had slipped.
##
## ── PURE, STATIC, CLOCKLESS, FILELESS ───────────────────────────────────────
##
## Every function here is static and total. No node, no signal, no clock, no
## file, no `Time` call. THE CALLER READS THE CLOCKS: hours-since arrives as a
## plain float in the facts dictionary, already measured by whoever owns a real
## clock (`creature_organ.gd`), exactly the way `character.gd` takes `now_ms`
## as an argument rather than asking the world what time it is.
##
## TOTAL MEANS TOTAL. An unknown hexagram number, an unknown language, an empty
## facts dictionary, a changing line outside 1..6 — every one of them returns an
## honest short sentence. Nothing here returns "" and nothing here can crash the
## screen it writes to.


## The three languages, and the exact strings `lang()` normalises to. There is
## no fourth: a locale this app has no words for reads as English rather than
## as a blank, which is the same "never nothing" rule the state card holds.
const EN := "en"
const PT := "pt"
const ZH := "zh"
const LANGS := [EN, PT, ZH]

## The six needs, in line order, bottom-to-top. Index-aligned with
## `creature.gd`'s NEEDS and `character.gd`'s NEED_NAMES — asserted equal by
## the suite, so a rename in either file is a red suite rather than a sentence
## about a need that no longer exists.
const NEEDS := ["body", "food", "breath", "rest", "focus", "connection"]

## THE NEED, IN THE OWNER'S LANGUAGE. English is the key itself; the other two
## columns are index-aligned with NEEDS above. The chinese column is one
## character per need on purpose — the sentence it sits in is already short,
## and a hexagram's own name beside it is one or two characters.
const NEED_WORDS := {
	EN: ["body", "food", "breath", "rest", "focus", "connection"],
	PT: ["corpo", "comida", "respiração", "descanso", "atenção", "companhia"],
	ZH: ["身", "食", "息", "休", "專", "伴"],
}

## ── THE SIXTY-FOUR NAMES ────────────────────────────────────────────────────
##
## NAMES ONLY. This table is the ENTIRE canon loan in this repo, and every cell
## in it is a label: `zh` the traditional character(s) the hexagram is written
## with, `pinyin` how that is said, `en` the common public-domain English name,
## `pt` a short faithful Portuguese rendering written for this app.
##
## Deliberately absent from every row: the judgment, the image, the six line
## texts, and any commentary. Grep this file for them and find nothing — the
## canon port is a later, parity-locked step (see the header).
##
## The order is King Wen 1..64, the sequence `hexagram.gd`'s 8x8 grid produces,
## so a reader can check any row against any printed edition's contents page.
const NAMES := {
	1: {"zh": "乾", "pinyin": "qián", "en": "The Creative", "pt": "O Criador"},
	2: {"zh": "坤", "pinyin": "kūn", "en": "The Receptive", "pt": "O Receptivo"},
	3: {"zh": "屯", "pinyin": "zhūn", "en": "Sprouting", "pt": "Brotar"},
	4: {"zh": "蒙", "pinyin": "méng", "en": "Youthful Folly", "pt": "Inexperiência"},
	5: {"zh": "需", "pinyin": "xū", "en": "Waiting", "pt": "Espera"},
	6: {"zh": "訟", "pinyin": "sòng", "en": "Conflict", "pt": "Conflito"},
	7: {"zh": "師", "pinyin": "shī", "en": "The Army", "pt": "O Exército"},
	8: {"zh": "比", "pinyin": "bǐ", "en": "Holding Together", "pt": "União"},
	9: {"zh": "小畜", "pinyin": "xiǎo chù", "en": "Small Taming", "pt": "Pequena Contenção"},
	10: {"zh": "履", "pinyin": "lǚ", "en": "Treading", "pt": "Caminhar"},
	11: {"zh": "泰", "pinyin": "tài", "en": "Peace", "pt": "Paz"},
	12: {"zh": "否", "pinyin": "pǐ", "en": "Standstill", "pt": "Estagnação"},
	13: {"zh": "同人", "pinyin": "tóng rén", "en": "Fellowship", "pt": "Companhia"},
	14: {"zh": "大有", "pinyin": "dà yǒu", "en": "Great Possession", "pt": "Grande Posse"},
	15: {"zh": "謙", "pinyin": "qiān", "en": "Modesty", "pt": "Modéstia"},
	16: {"zh": "豫", "pinyin": "yù", "en": "Enthusiasm", "pt": "Entusiasmo"},
	17: {"zh": "隨", "pinyin": "suí", "en": "Following", "pt": "Seguir"},
	18: {"zh": "蠱", "pinyin": "gǔ", "en": "Repairing", "pt": "Reparo"},
	19: {"zh": "臨", "pinyin": "lín", "en": "Approach", "pt": "Aproximação"},
	20: {"zh": "觀", "pinyin": "guān", "en": "Contemplation", "pt": "Contemplação"},
	21: {"zh": "噬嗑", "pinyin": "shì kè", "en": "Biting Through", "pt": "Atravessar"},
	22: {"zh": "賁", "pinyin": "bì", "en": "Grace", "pt": "Graça"},
	23: {"zh": "剝", "pinyin": "bō", "en": "Splitting Apart", "pt": "Desgaste"},
	24: {"zh": "復", "pinyin": "fù", "en": "Return", "pt": "Retorno"},
	25: {"zh": "無妄", "pinyin": "wú wàng", "en": "Innocence", "pt": "Inocência"},
	26: {"zh": "大畜", "pinyin": "dà chù", "en": "Great Taming", "pt": "Grande Contenção"},
	27: {"zh": "頤", "pinyin": "yí", "en": "Nourishment", "pt": "Nutrição"},
	28: {"zh": "大過", "pinyin": "dà guò", "en": "Great Excess", "pt": "Grande Excesso"},
	29: {"zh": "坎", "pinyin": "kǎn", "en": "The Deep", "pt": "O Profundo"},
	30: {"zh": "離", "pinyin": "lí", "en": "The Clinging Fire", "pt": "O Fogo"},
	31: {"zh": "咸", "pinyin": "xián", "en": "Influence", "pt": "Atração"},
	32: {"zh": "恆", "pinyin": "héng", "en": "Duration", "pt": "Duração"},
	33: {"zh": "遯", "pinyin": "dùn", "en": "Retreat", "pt": "Recuo"},
	34: {"zh": "大壯", "pinyin": "dà zhuàng", "en": "Great Power", "pt": "Grande Vigor"},
	35: {"zh": "晉", "pinyin": "jìn", "en": "Progress", "pt": "Progresso"},
	36: {"zh": "明夷", "pinyin": "míng yí", "en": "Hidden Light", "pt": "Luz Velada"},
	37: {"zh": "家人", "pinyin": "jiā rén", "en": "The Family", "pt": "A Família"},
	38: {"zh": "睽", "pinyin": "kuí", "en": "Opposition", "pt": "Divergência"},
	39: {"zh": "蹇", "pinyin": "jiǎn", "en": "Obstruction", "pt": "Obstáculo"},
	40: {"zh": "解", "pinyin": "xiè", "en": "Deliverance", "pt": "Alívio"},
	41: {"zh": "損", "pinyin": "sǔn", "en": "Decrease", "pt": "Diminuição"},
	42: {"zh": "益", "pinyin": "yì", "en": "Increase", "pt": "Aumento"},
	43: {"zh": "夬", "pinyin": "guài", "en": "Breakthrough", "pt": "Rompimento"},
	44: {"zh": "姤", "pinyin": "gòu", "en": "Coming to Meet", "pt": "Encontro"},
	45: {"zh": "萃", "pinyin": "cuì", "en": "Gathering Together", "pt": "Reunião"},
	46: {"zh": "升", "pinyin": "shēng", "en": "Pushing Upward", "pt": "Ascensão"},
	47: {"zh": "困", "pinyin": "kùn", "en": "Confinement", "pt": "Aperto"},
	48: {"zh": "井", "pinyin": "jǐng", "en": "The Well", "pt": "O Poço"},
	49: {"zh": "革", "pinyin": "gé", "en": "Revolution", "pt": "Mudança"},
	50: {"zh": "鼎", "pinyin": "dǐng", "en": "The Cauldron", "pt": "O Caldeirão"},
	51: {"zh": "震", "pinyin": "zhèn", "en": "The Arousing", "pt": "O Trovão"},
	52: {"zh": "艮", "pinyin": "gèn", "en": "Keeping Still", "pt": "Quietude"},
	53: {"zh": "漸", "pinyin": "jiàn", "en": "Gradual Progress", "pt": "Progresso Gradual"},
	54: {"zh": "歸妹", "pinyin": "guī mèi", "en": "The Marrying Maiden", "pt": "A Noiva"},
	55: {"zh": "豐", "pinyin": "fēng", "en": "Abundance", "pt": "Abundância"},
	56: {"zh": "旅", "pinyin": "lǚ", "en": "The Wanderer", "pt": "O Viajante"},
	57: {"zh": "巽", "pinyin": "xùn", "en": "The Gentle Wind", "pt": "O Vento Suave"},
	58: {"zh": "兌", "pinyin": "duì", "en": "The Joyous", "pt": "A Alegria"},
	59: {"zh": "渙", "pinyin": "huàn", "en": "Dispersion", "pt": "Dispersão"},
	60: {"zh": "節", "pinyin": "jié", "en": "Limitation", "pt": "Limite"},
	61: {"zh": "中孚", "pinyin": "zhōng fú", "en": "Inner Truth", "pt": "Verdade Interior"},
	62: {"zh": "小過", "pinyin": "xiǎo guò", "en": "Small Excess", "pt": "Pequeno Excesso"},
	63: {"zh": "既濟", "pinyin": "jì jì", "en": "After Completion", "pt": "Após a Conclusão"},
	64: {"zh": "未濟", "pinyin": "wèi jì", "en": "Before Completion", "pt": "Antes da Conclusão"},
}

## THE TITLE'S SHAPE, stated once. "24 · 復 fù · Return" — the number first
## because it is what the app has always shown and what a returning owner's eye
## already looks for, then the character and its sound because that pair IS the
## canon's own name for the number, then the latin word last because it is the
## most disposable part: it changes with the locale, the other two never do.
const TITLE_SEP := " · "

## What the title says about a number that is not a hexagram. Never "" and
## never an invented name — an unknown number reads as itself.
const TITLE_UNKNOWN := "%d"


## Normalise anything locale-shaped to one of the three. Accepts "pt", "pt_BR",
## "pt-br", "zh_TW", "cmn", and anything else, which is English — see LANGS.
static func lang(raw: String) -> String:
	var s := raw.to_lower().replace("_", "-")
	if s.begins_with("pt"):
		return PT
	if s.begins_with("zh") or s.begins_with("cmn") or s.begins_with("yue"):
		return ZH
	return EN


## THE NAME OF A HEXAGRAM, AS A TITLE. The chinese character is ALWAYS present,
## because the character is the canon's own name and does not belong to a
## locale; `lang` only chooses which latin word rides beside it, and ZH asks for
## no latin word at all beyond the pinyin.
##
##   title(24, "en") → "24 · 復 fù · Return"
##   title(24, "pt") → "24 · 復 fù · Retorno"
##   title(24, "zh") → "24 · 復 fù"
##
## A number outside 1..64 is the caller holding something that is not a reading
## — `hexagram.gd` answers 0 for a state it cannot read — and the honest title
## for that is the number itself, printed, rather than a name it does not have.
static func title(wen: int, lang_raw: String = EN) -> String:
	var row: Dictionary = NAMES.get(wen, {})
	if row.is_empty():
		return TITLE_UNKNOWN % wen
	var head: String = "%d%s%s" % [wen, TITLE_SEP, pinyin_of(wen)]
	var l := lang(lang_raw)
	if l == ZH:
		return head
	return head + TITLE_SEP + String(row.get(l, row["en"]))


## ── THE FONT AUDIT, AND WHY NO CHARACTER IS ON THE GLASS ────────────────────
##
## This project ships NO font. There is no .ttf or .otf anywhere in it, so
## every string it draws is drawn by `ThemeDB.fallback_font`, and the question
## "can we draw this" has exactly one answer, which `tools/font_coverage.gd`
## reads straight off that font. Measured on Godot 4.7.1:
##
##   U+4DC0..4DFF  the 64 hexagram symbols ......... NOT covered
##   U+268A/U+268B ⚊ ⚋, the single yang/yin lines .. NOT covered
##   U+4E00..U+9FFF  every CJK character in NAMES ... NOT covered (all 76)
##   ǎ ǐ ǒ ǔ ǚ  the five pinyin CARON vowels ........ NOT covered
##   ā á à, ē é è, ī í ì, ō ó ò, ū ú ù, ü, ·, — ..... covered
##
## So the title used to put `row["zh"]` on the glass and the glass answered
## with a tofu box, every time, in every language — "1 · ▯ qián · O Criador"
## (field, 2026-09-07). Three things follow, and this is all three:
##
##   1. THE CHARACTER IS DROPPED FROM THE TITLE. Not from `NAMES`, which is the
##      canon and stays exact — dropped from what is RENDERED. A box is not a
##      character; showing one claims a name we cannot say.
##   2. THE PINYIN STAYS, because it is how the name is SAID, it is the half a
##      reader can actually use, and it survives the font almost intact.
##   3. THE SIX LINES ARE NOT TEXT. Neither the hexagram block nor the yang/yin
##      pair exists in this font, so there is no glyph to fall back to and the
##      lines stay what they already were: rectangles `hexy.gd` DRAWS. A drawn
##      bar has no font to miss. `lines_ascii` below is for logs and tests,
##      where the six lines have to be readable as characters; it uses `---`
##      and `- -`, which are ASCII and therefore always covered.
##
## The day a CJK font is added, put the character back in `title()` and delete
## this note — but a CJK subset is megabytes, and the pinyin already says it.


## The pinyin, with the five caron vowels this font cannot draw folded to the
## plain vowel underneath (ǎ→a, ǐ→i, ǒ→o, ǔ→u, ǚ→ü). Losing a tone mark makes
## the syllable less precise; a tofu box in the middle of it makes the whole
## word unreadable, and eleven of the sixty-four names carry one.
const CARON_FOLD := {"ǎ": "a", "ǐ": "i", "ǒ": "o", "ǔ": "u", "ǚ": "ü"}


static func pinyin_of(wen: int) -> String:
	var row: Dictionary = NAMES.get(wen, {})
	if row.is_empty():
		return ""
	var s := String(row["pinyin"])
	for caron: String in CARON_FOLD:
		s = s.replace(caron, String(CARON_FOLD[caron]))
	return s


## The six lines as characters, bottom-to-top, for a log line or a test. ASCII
## on purpose — see the audit above. `bits` is the same bottom-to-top bitfield
## `hexagram.gd` produces and `hexy.gd` draws: bit i set is line i+1 YANG.
const LINE_YANG := "-----"
const LINE_YIN := "-- --"


static func lines_ascii(bits: int) -> PackedStringArray:
	var out := PackedStringArray()
	for i in 6:
		out.append(LINE_YANG if ((bits >> i) & 1) == 1 else LINE_YIN)
	return out


## Just the name, no number and no pinyin — for a caller with its own frame.
## Always non-empty for 1..64; an unknown number answers with itself.
static func name_of(wen: int, lang_raw: String = EN) -> String:
	var row: Dictionary = NAMES.get(wen, {})
	if row.is_empty():
		return TITLE_UNKNOWN % wen
	var l := lang(lang_raw)
	if l == ZH:
		# The pinyin, not the character — see the font audit above `pinyin_of`.
		return pinyin_of(wen)
	return String(row.get(l, row["en"]))


# ── the composed sentence ────────────────────────────────────────────────────
#
# EVERY WORD BELOW IS ABOUT THE CREATURE, NOT ABOUT THE CANON. The need that
# moved is `creature.gd`'s changing line; how long it has been quiet and how
# full it is are numbers the caller measured. The canon's name is NOT repeated
# here — it is already on the glass in `title()`, and saying it twice would
# make the sentence sound like a fortune instead of an observation.


## THE SHAPE, one per language, filled with [need, when]. A single format
## string per language rather than a concatenation, so a translator (or a
## later reader) can see the whole sentence at once and check its tone.
const SAY := {
	EN: "%s is the line that moved — %s",
	PT: "%s é a linha que se moveu — %s",
	ZH: "%s 是動的那一爻 —— %s",
}

## HOW LONG IT HAS BEEN QUIET, in the plainest words a person uses for the same
## spans. The bands are hours, and they are deliberately coarse: "it has been
## quiet since morning" is something an owner recognises; "6.4 hours since the
## last feed" is a log line about a person.
##
## Each band is [hours_upper_bound, en, pt, zh]. The first band whose bound the
## measurement is under wins; past the last one, LONG_AGO answers.
const WHEN_BANDS := [
	[1.0, "it was tended just now", "acabou de ser cuidada", "剛剛才顧到"],
	[4.0, "it was tended a few hours ago", "foi cuidada há algumas horas", "幾個小時前顧過"],
	[12.0, "it has been quiet since morning", "está quieta desde cedo", "從早上起就靜著"],
	[24.0, "it has been quiet since yesterday", "está quieta desde ontem", "從昨天起就靜著"],
	[72.0, "it has been quiet a couple of days", "está quieta há alguns dias", "靜了幾天了"],
]
const WHEN_LONG_AGO := ["it has been quiet a good while", "está quieta há um bom tempo",
	"靜了好一陣子"]
## Nothing was ever measured for this need — the honest answer, and NOT a
## reproach: a need with no history is a need the app has not seen yet, which
## is a fact about the app.
const WHEN_UNSEEN := ["nothing has been noted for it yet", "nada foi notado sobre ela ainda",
	"還沒有記到什麼"]

## THE SOFT REQUEST, and it is the only thing in this file that ASKS for
## anything. Appended when the need is running low — under `LOW_FULLNESS` —
## and phrased as a welcome rather than an instruction. There is no branch that
## produces a stronger form of this, in any language.
const LOW_FULLNESS := 0.5
const ASK := {
	EN: " · a little would be welcome",
	PT: " · um pouco seria bem-vindo",
	ZH: " · 有一點就很好",
}

## When the reading itself is unreadable — no changing line, no need, nothing
## measured. Still a sentence, still in the voice, still never empty.
const SAY_UNREADABLE := {
	EN: "the reading is quiet right now",
	PT: "a leitura está quieta agora",
	ZH: "此刻的卦象很安靜",
}


## THE ONE COMPOSED SENTENCE. `reading` is `creature.gd`'s `reading()` — only
## `changing_line` is read out of it, because the moving line IS what the
## sentence is about. `facts` carries the plain numbers the caller measured:
##
##   hours_since  float, hours since that need was last fed; negative or
##                missing means never seen (see WHEN_UNSEEN)
##   fullness     float 0..1, that need's current fullness; missing reads as
##                full, so a caller with no number never provokes the request
##
## Returns one sentence, always. An unknown language reads as English, a
## changing line outside 1..6 reads as SAY_UNREADABLE, and an empty `facts`
## still produces the honest "nothing has been noted for it yet" form.
static func sentence(reading: Dictionary, facts: Dictionary = {}, lang_raw: String = EN) -> String:
	var l := lang(lang_raw)
	var line := int(reading.get("changing_line", 0))
	if line < 1 or line > NEEDS.size():
		return String(SAY_UNREADABLE[l])
	var need: String = String(NEED_WORDS[l][line - 1])
	var hours := float(facts.get("hours_since", -1.0))
	var out: String = String(SAY[l]) % [need, _when(hours, l)]
	var fullness := float(facts.get("fullness", 1.0))
	if fullness < LOW_FULLNESS:
		out += String(ASK[l])
	return out


## The time phrase for a measured span, in the given (already normalised)
## language. Its own function because the bands are the part most likely to be
## retuned once a real owner has read a week of these.
static func _when(hours: float, l: String) -> String:
	var col := LANGS.find(l) + 1
	if hours < 0.0:
		return String(WHEN_UNSEEN[col - 1])
	for band in WHEN_BANDS:
		if hours < float(band[0]):
			return String(band[col])
	return String(WHEN_LONG_AGO[col - 1])


# ── THE FRUIT FLY BIOLOGICAL MEANING LAYER ──────────────────────────────────

const BIOLOGICAL_NEED_WORDS := {
	EN: [
		"Dopamine (cuticular body vigor)",
		"Neuropeptide F (metabolic energy)",
		"Octopamine (flight ventilation)",
		"dFB homeostat (synaptic rest)",
		"Central Complex (heading focus)",
		"Fruitless (conspecific resonance)"
	],
	PT: [
		"Dopamina (vigor da carapaça)",
		"Neuropeptídeo F (energia metabólica)",
		"Octopamina (fôlego e prontidão de voo)",
		"Homeostato dFB (repouso sináptico)",
		"Complexo Central (foco de navegação)",
		"Fruitless (ressonância com pares)"
	],
	ZH: [
		"多巴胺（甲殼體能）",
		"神經肽F（代謝充盈）",
		"章魚胺（振翅之息）",
		"dFB神經元（突觸修歇）",
		"中央複合體（羅盤凝神）",
		"Fruitless（同類共鳴）"
	]
}

const BIOLOGICAL_OBSERVATIONS := {
	EN: [
		"the body stands firm in its shell; vitality courses through the frame",
		"nectar reserves are fed; metabolic valence is calm and sweet",
		"air moves swiftly; wings carry the hum of flight readiness",
		"the quiet chamber fills; memories settle into darkness",
		"the internal compass locks true to its heading",
		"wings sense the social fabric; conspecific resonance is open"
	],
	PT: [
		"o corpo firma sua carapaça; a vitalidade corre pela estrutura",
		"a reserva de néctar está nutrida; a doçura metabólica traz calma",
		"o ar move-se veloz; as asas vibram prontas para o voo",
		"a câmara de repouso acolhe; memórias assentam-se na penumbra",
		"o compasso interno sustenta o rumo com firmeza",
		"as asas sentem a rede de pares; a ressonância social está aberta"
	],
	ZH: [
		"形骸自固，生機行於骨架",
		"瓊漿充盈，天時代謝甘美",
		"天風振翮，靈息躍動如飛",
		"淵默內斂，神慮歸於幽寂",
		"心盤定向，八方焦點朗然",
		"同類共鳴，群脈感通無礙"
	]
}

## Produces an authentic biological observation combining the Drosophila
## neuromodulatory cluster with poetic Daoist phrasing.
static func biological_sentence(line: int, fullness: float, lang_raw: String = EN) -> String:
	var l := lang(lang_raw)
	if line < 1 or line > NEEDS.size():
		return String(SAY_UNREADABLE[l])
	var bio_word: String = String(BIOLOGICAL_NEED_WORDS[l][line - 1])
	var obs: String = String(BIOLOGICAL_OBSERVATIONS[l][line - 1])
	if fullness >= 0.5:
		return "%s · %s" % [bio_word, obs]
	else:
		var low_ask: String = String(ASK[l]).strip_edges()
		return "%s · %s" % [bio_word, low_ask]

