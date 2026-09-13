class_name Judgements
extends RefCounted

## One ASCII line per figure, in King Wen order.
##
## Short paraphrases of the judgement text, twelve words or fewer. They are the
## offline voice: MockLlm speaks them when no model is on the device, and Qwen
## falls back to them when a generation returns nothing.

const LINES: Array[String] = [
	"Creative. Sublime success. Perseverance furthers.",
	"Receptive. Yielding brings fortune. Follow, do not lead.",
	"Difficulty at the beginning. Do not act alone. Find helpers.",
	"Youthful folly. The teacher waits to be asked.",
	"Waiting. Nourish yourself in patience. Crossing the water succeeds.",
	"Conflict. Meet halfway. Do not push the quarrel through.",
	"The army. Discipline holds. An experienced leader brings fortune.",
	"Holding together. Come early. Union asks for sincerity.",
	"Small taming. Dense clouds, no rain yet. Gather strength.",
	"Treading. Step on the tiger's tail gently. Courtesy protects.",
	"Peace. Small departs, great arrives. Heaven and earth meet.",
	"Standstill. The wrong people advance. Withdraw quietly.",
	"Fellowship. Join others in the open. Shared aim succeeds.",
	"Great possession. Supreme success. Hold wealth with modesty.",
	"Modesty. The high bows low. Completion follows.",
	"Enthusiasm. Set helpers moving. Music and order carry all.",
	"Following. Adapt to the hour. Sincere following brings no blame.",
	"Work on the decayed. Repair what was spoiled. Begin again.",
	"Approach. Great progress now. Beware the eighth month.",
	"Contemplation. Wash the hands, do not yet offer. Watch.",
	"Biting through. Bite the obstacle away. Justice clears the path.",
	"Grace. Beauty in small things. Form serves substance.",
	"Splitting apart. Do not move now. Let the old fall.",
	"Return. The turning point. Old friends come back without error.",
	"Innocence. Act without motive. Unexpected trouble passes.",
	"Great taming. Hold firm, feed others. Crossing the water furthers.",
	"Nourishment. Watch what you feed. Words and food both count.",
	"Great excess. The ridgepole bends. Move with purpose.",
	"The abyss. Repeated danger. Sincerity carries the heart through.",
	"Clinging fire. Depend on what is right. Care for the cow.",
	"Influence. Wooing. The lake on the mountain draws together.",
	"Duration. Endure in a steady course. Have somewhere to go.",
	"Retreat. Withdraw in good order. Smallness perseveres.",
	"Great power. Power only in what is right.",
	"Progress. The sun rises over the earth. Advance openly.",
	"Darkening light. Hide your brightness. Persevere inwardly.",
	"The family. Order at home spreads outward. The woman perseveres.",
	"Opposition. In small things fortune. Differences still work together.",
	"Obstruction. Go back and seek counsel. The southwest furthers.",
	"Deliverance. The knot loosens. Return quickly, act early.",
	"Decrease. Less below, more above. Simple offerings suffice.",
	"Increase. It furthers to undertake something. Cross the great water.",
	"Breakthrough. Announce it truly. Do not rely on arms.",
	"Coming to meet. The weak rises. Do not marry this maiden.",
	"Gathering together. The king approaches his temple. Bring a great offering.",
	"Pushing upward. Small things rise. Go south without fear.",
	"Oppression. Exhaustion. The great endure; words are not believed.",
	"The well. The town changes, the well does not.",
	"Revolution. On its own day, belief comes. Remorse vanishes.",
	"The cauldron. Supreme fortune. Nourish the worthy.",
	"The arousing. Thunder repeats. Shock brings laughter afterward.",
	"Keeping still. Still the back. Stand without restlessness.",
	"Development. Gradual progress. The tree grows on the mountain.",
	"The marrying maiden. Undertakings bring misfortune. Know your place.",
	"Abundance. The sun at noon. Be like the sun, unworried.",
	"The wanderer. Small success. Stay modest on the road.",
	"The gentle. Penetrating wind. Small repeated influence works.",
	"The joyous. Lake upon lake. Gladness shared perseveres.",
	"Dispersion. The wind scatters rigidity. Bring people to the temple.",
	"Limitation. Bitter limits cannot last. Measure what you spend.",
	"Inner truth. Sincerity reaches the pigs and fishes.",
	"Small excess. The bird should fly down, not up.",
	"After completion. Order at the start, disorder at the end.",
	"Before completion. The fox wets its tail near the crossing.",
]


static func count() -> int:
	return LINES.size()


## The judgement line for a figure given by its six bits.
static func for_bits(bits: int) -> String:
	return for_number(KingWen.number(bits & 63))


## The judgement line for a King Wen number, 1..64.
static func for_number(num: int) -> String:
	return LINES[clampi(num, 1, 64) - 1]
