extends GSNetMessage

const DdEvents := preload("dd_events.gd")

## Anything the authority tells a client that is not a snapshot. Reliable, to clients.

const NAME := &"delivery.event"
const KIND_BITS := 5
const MAX_BODY := 140000

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
	if kind < 0 or kind >= DdEvents.Kind.size():
		return GSResult.fail(GSError.CODE_INVALID, "Unknown event kind %d." % kind)

	return GSResult.success(true)


## Whether every [enum DdEvents.Kind] fits in [constant KIND_BITS]. What a check reads: the writer
## masks a value to its field, so a kind past it goes out as a smaller one and nothing errors.
static func fits() -> bool:
	return int(DdEvents.Kind.values().max()) < (1 << KIND_BITS)


func reader() -> GSNetReader:
	return GSNetReader.new(body)


func _to_string() -> String:
	return "DdEvent(%s, %d bytes)" % [DdEvents.kind_name(kind), body.size()]
