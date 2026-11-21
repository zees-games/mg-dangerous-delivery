extends GSNetMessage

const DdEvents := preload("dd_events.gd")

## Anything a client asks the authority for. Reliable, rare, to the server only.
## None is a per-tick intent: firing is a BUTTON because it must be ordered against movement; these happen once and must not be lost.

const NAME := &"delivery.request"
const KIND_BITS := 4
const MAX_BODY := 2048

var kind: int = 0
var body: PackedByteArray = PackedByteArray()


## Built with `new(kind, body)`, and this file does not preload itself: a `GSNetMessage` script preloading itself leaks the script graph at exit
## when loaded from a module a running [GSServer] loads. The registry decodes with a bare `new()`, so both arguments default.
func _init(p_kind: int = 0, p_body: PackedByteArray = PackedByteArray()) -> void:
	kind = p_kind
	body = p_body


func _type_name() -> StringName:
	return NAME


func _write(writer: GSNetWriter) -> void:
	writer.write_uint(kind, KIND_BITS)
	writer.write_bytes(body)


func _read(reader: GSNetReader) -> void:
	kind = reader.read_uint(KIND_BITS)
	body = reader.read_bytes(MAX_BODY)


func _validate() -> GSResult:
	if kind < 0 or kind >= DdEvents.Ask.size():
		return GSResult.fail(GSError.CODE_INVALID, "Unknown request kind %d." % kind)

	return GSResult.success(true)


## Whether every [enum DdEvents.Ask] fits in [constant KIND_BITS]. What a check reads: the writer
## masks a value to its field, so a kind past it goes out as a smaller one and nothing errors.
static func fits() -> bool:
	return int(DdEvents.Ask.values().max()) < (1 << KIND_BITS)


func reader() -> GSNetReader:
	return GSNetReader.new(body)


func _to_string() -> String:
	return "DdRequest(%s, %d bytes)" % [DdEvents.ask_name(kind), body.size()]
