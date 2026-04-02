class_name LuxoddPinCodeHasher
extends RefCounted

## XOR-based pin code hash, matching the Unity plugin's PinCodeHasher.cs.
## The pin string is XOR'd byte-by-byte with the session token key, then
## Base64-encoded.


static func hash_with_key(value: String, key: String) -> String:
	var value_bytes := value.to_utf8_buffer()
	var key_bytes := key.to_utf8_buffer()
	var result := PackedByteArray()
	result.resize(value_bytes.size())
	for i in range(value_bytes.size()):
		result[i] = value_bytes[i] ^ key_bytes[i % key_bytes.size()]
	return Marshalls.raw_to_base64(result)
