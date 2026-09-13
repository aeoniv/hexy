class_name Envelope6
extends RefCounted

## The wire word of the mesh is a hexagram.
##
## Byte 0 IS the figure: the low six bits are the hexagram's `bits` exactly as
## HexyStore holds them (bit i = line i+1 from the bottom, yang = 1), and the
## two high bits are the kind of thing this figure is being said about. Six
## lines and four kinds fit in one octet with nothing left over, which is the
## whole reason the head is a byte and not a JSON field: a peer that can only
## afford to read one byte of a datagram still learns the figure.
##
## Everything after byte 0 is the payload, UTF-8 JSON of a Dictionary. An empty
## payload is written as zero trailing bytes rather than "{}" so a bare figure
## costs exactly one byte on the wire.

const KIND_FIGURE := 0
const KIND_CHIRP := 1
const KIND_WITNESS := 2
const KIND_OTHER := 3
const KIND_NAMES := ["figure", "chirp", "witness", "other"]

const BITS_MASK := 63
const KIND_SHIFT := 6


static func kind_name(kind: int) -> String:
	return KIND_NAMES[kind & 3]


## byte0 = kind<<6 | bits, then UTF-8 JSON of payload (omitted when empty).
static func pack(kind: int, bits: int, payload: Dictionary = {}) -> PackedByteArray:
	var out := PackedByteArray()
	out.append(((kind & 3) << KIND_SHIFT) | (bits & BITS_MASK))
	if not payload.is_empty():
		out.append_array(JSON.stringify(payload).to_utf8_buffer())
	return out


## Always returns the three keys. A truncated or non-JSON tail yields an empty
## payload rather than an error: the figure in byte 0 is still true, and losing
## the sentence is not a reason to lose the word.
static func unpack(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty():
		return {"kind": KIND_OTHER, "bits": 0, "payload": {}}
	var head := int(bytes[0]) & 255
	var payload := {}
	# A tail that is not even shaped like a JSON object is not handed to the
	# parser at all: a half-arrived datagram is an ordinary event on a mesh,
	# and an ordinary event must not print like a fault.
	if bytes.size() > 1 and int(bytes[1]) == 0x7B:
		var parsed = JSON.parse_string(bytes.slice(1).get_string_from_utf8())
		if parsed is Dictionary:
			payload = parsed
	return {
		"kind": (head >> KIND_SHIFT) & 3,
		"bits": head & BITS_MASK,
		"payload": payload,
	}


## The one-byte head alone, for a caller that only wants the word.
static func head_of(bytes: PackedByteArray) -> int:
	return int(bytes[0]) & 255 if not bytes.is_empty() else 0


## Base64, because the existing fabric carries JSON Dictionaries and a
## PackedByteArray cannot ride in one. Composition, not a fork: the six-bit
## head keeps its meaning, it just travels inside an EventEnvelope body until a
## transport exists that can carry raw octets.
static func to_wire(kind: int, bits: int, payload: Dictionary = {}) -> String:
	return Marshalls.raw_to_base64(pack(kind, bits, payload))


static func from_wire(b64: String) -> Dictionary:
	return unpack(Marshalls.base64_to_raw(b64))
