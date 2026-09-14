class_name Clock
extends RefCounted

## THE ONE PLACE A CLOCK IS READ. Ported from ix64-hexy (M1b).
##
## Several files each grew their own `_now()`. That would be harmless if they
## agreed, and they did not: incompatible return contracts were living
## under one name — nanoseconds as an int, seconds as a float, and a
## caller-supplied millisecond stamp with a fallback. A fix to any one of them
## reached only its own file.
##
## THE SIGNATURES ARE KEPT APART ON PURPOSE. There is no single `now()` here,
## because ns, ms and s are not interchangeable and a helper that quietly
## picked one would turn a compile error into a wrong number on a phone. Each
## function says its unit in its name.
##
## PURE AND STATIC. Nothing is cached: a clock that remembered its last answer
## would be the exact bug these guards exist to catch.


## NANOSECONDS FROM A WIRED SOURCE, or zero when nothing is wired.
##
## Zero and not `Time.get_ticks_*`: a seam clock where an unwired source means
## the plugin never handed one over, and a plausible-looking local number
## would be silently wrong against a peer's stamps. Zero reads as "no clock".
static func ns(source: Callable) -> int:
	return int(source.call()) if source.is_valid() else 0


## NANOSECONDS, FALLING BACK TO THE LOCAL MONOTONIC CLOCK.
##
## For callers that only ever compare their own stamps to their own stamps,
## `get_ticks_usec` scaled to ns keeps the unit constant whether wired or not.
static func ns_or_ticks(source: Callable) -> int:
	if source.is_valid():
		return int(source.call())
	return Time.get_ticks_usec() * 1000


## MILLISECONDS FROM A WIRED SOURCE, or zero when nothing is wired.
static func ms(source: Callable) -> int:
	return int(source.call()) if source.is_valid() else 0


## A CALLER-SUPPLIED MILLISECOND STAMP, or the local one when the caller passed
## a negative. Seams that get their stamp injected per call so a suite can
## drive time; -1 is the agreed "you decide".
static func ms_or_ticks(now_ms: int) -> int:
	return now_ms if now_ms >= 0 else Time.get_ticks_msec()


## THE LOCAL MONOTONIC CLOCK, IN MILLISECONDS. The plain, uncached call site
## for anything that just wants "now" off the engine's own ticker.
static func now_ms() -> int:
	return Time.get_ticks_msec()


## THE LOCAL MONOTONIC CLOCK, IN NANOSECONDS. Scaled from the engine's
## microsecond ticker so the unit never changes across a call site that later
## starts comparing stamps with a wired peer clock.
static func now_ns() -> int:
	return Time.get_ticks_usec() * 1000


## SECONDS AS A FLOAT, off the local monotonic clock. For tables that age in
## seconds and never cross a wire with them.
static func seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


## SECONDS SINCE MIDNIGHT, WALL CLOCK, or a wired source when there is one.
##
## Distinct from [method seconds] because it is a different clock, not a
## different unit — this one is for a stamp a PERSON reads.
static func day_seconds(source: Callable) -> int:
	if source.is_valid():
		return int(source.call())
	var t := Time.get_time_dict_from_system()
	return int(t["hour"]) * 3600 + int(t["minute"]) * 60 + int(t["second"])


## WHICH DAY IT IS, as a plain days-since-epoch integer, or a wired source when
## there is one.
##
## The companion to [method day_seconds], and it exists because that one
## wraps. Seconds-since-midnight is the right stamp to SHOW a person and the
## wrong thing to compare two rows with: 18:12 yesterday and 18:12 today are
## the same number. Anything that has to know whether a stamp is stale needs
## the day as well, and only the day — a date is not drawn, it is subtracted.
static func day_index(source: Callable) -> int:
	if source.is_valid():
		return int(source.call())
	return int(Time.get_unix_time_from_system() / 86400.0)
