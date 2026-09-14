class_name FlyCircadianClock
extends RefCounted

## DROSOPHILA CIRCADIAN PACEMAKER (s-LNv & l-LNv NEURONS)
##
## Models the biological clock neurons of the fruit fly:
##   - Small Lateral Ventral Neurons (s-LNvs): Morning anticipation pacemaker.
##   - Large Lateral Ventral Neurons (l-LNvs): Arousal / light modulation.
##   - Pigment-Dispersing Factor (PDF): The canonical neuropeptide synchronizer.
##
## Drosophila displays a bimodal circadian rhythm:
##   1. Morning peak (Dawn, ~06:00 - 08:00): PDF surge primes Dopamine & Octopamine.
##   2. Midday siesta (~12:00 - 14:00): Temporary dip in locomotor activity.
##   3. Evening peak (Dusk, ~17:00 - 19:30): Secondary surge before nightfall.
##   4. Night torpor (~23:00 - 05:00): PDF trough unlocks dFB sleep consolidation.

var solar_hour: float = 12.0
var pdf_level: float = 0.5            # 0.0 (night torpor) .. 1.0 (peak arousal)
var morning_drive: float = 0.0        # s-LNv activity
var evening_drive: float = 0.0        # l-LNv activity


## Updates the circadian pacemaker given the solar hour [0.0, 24.0)
func update(hour: float) -> void:
	solar_hour = fposmod(hour, 24.0)
	
	# Morning anticipation peak (centered at 07:00, sigma = 1.8 hours)
	var m_diff: float = absf(solar_hour - 7.0)
	if m_diff > 12.0:
		m_diff = 24.0 - m_diff
	morning_drive = exp(-0.5 * pow(m_diff / 1.8, 2))
	
	# Evening anticipation peak (centered at 18.5, sigma = 1.8 hours)
	var e_diff: float = absf(solar_hour - 18.5)
	if e_diff > 12.0:
		e_diff = 24.0 - e_diff
	evening_drive = exp(-0.5 * pow(e_diff / 1.8, 2))
	
	# Midday baseline (~0.35) vs Night trough (~0.05)
	var is_daytime := solar_hour >= 6.0 and solar_hour < 21.0
	var base_arousal: float = 0.35 if is_daytime else 0.05
	
	# Total PDF neuropeptide concentration
	pdf_level = clampf(base_arousal + morning_drive * 0.45 + evening_drive * 0.40, 0.0, 1.0)


## Returns metabolic modifiers for the 6 creature needs based on circadian phase
## Returns Dictionary: {"da_boost", "oa_boost", "dfb_gate", "phase_name"}
func get_circadian_modifiers() -> Dictionary:
	var phase_name := "Day"
	if morning_drive > 0.5:
		phase_name = "Morning Dawn (晨曦)"
	elif evening_drive > 0.5:
		phase_name = "Evening Twilight (黄昏)"
	elif solar_hour >= 22.0 or solar_hour < 5.0:
		phase_name = "Night Torpor (夜伏)"
	elif solar_hour >= 12.0 and solar_hour < 14.5:
		phase_name = "Midday Siesta (午歇)"
		
	return {
		"phase_name": phase_name,
		"pdf_level": pdf_level,
		"morning_drive": morning_drive,
		"evening_drive": evening_drive,
		# Morning/Evening boosts Dopamine (BODY) and Octopamine (BREATH)
		"da_boost": (morning_drive * 0.25 + evening_drive * 0.20),
		"oa_boost": (morning_drive * 0.30 + evening_drive * 0.25),
		# Night torpor permits deep dFB sleep; daytime PDF suppresses it
		"dfb_permissiveness": clampf(1.0 - (pdf_level * 0.8), 0.1, 1.0)
	}
