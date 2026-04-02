class_name LuxoddPayloads
extends RefCounted

## Convenience functions that build payload dictionaries matching the server's
## expected JSON structure. Keys match the wire format exactly.


static func amount_payload(amount: int, pin_hash: String) -> Dictionary:
	return {"amount": amount, "pin": pin_hash}


static func level_begin_payload(level: int) -> Dictionary:
	return {"level": level}


static func level_end_payload(
	level: int,
	score: int,
	accuracy: int = 0,
	time_taken: int = 0,
	enemies_killed: int = 0,
	completion_percentage: int = 0,
) -> Dictionary:
	var p := {"level": level, "score": score}
	if accuracy > 0:
		p["accuracy"] = accuracy
	if time_taken > 0:
		p["time_taken"] = time_taken
	if enemies_killed > 0:
		p["enemies_killed"] = enemies_killed
	if completion_percentage > 0:
		p["completion_percentage"] = completion_percentage
	return p


static func user_data_payload(data: Variant) -> Dictionary:
	return {"user_data": data}


static func strategic_betting_result_payload(results: Array) -> Dictionary:
	return {"results": results}
