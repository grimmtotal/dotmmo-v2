extends Node

const DEFAULTS = {
	"initialGravity": Vector2(0, 0),
	"colors": ["#754b25ff"],
	"solid": false,
	"liquid": false,
	"density": 1.0,
	"spread": Vector2i(0, 0),
	"interactions": {},
	"idleBehaviors": {
		"changeVelocity": null # Vector2
	},
	"timers": {},
	"interaction": {
		"spawn": [],
		"destroy": false,
		"resetTimers": []
	},
	"timer": {
		# Durations are milliseconds, given either as a single int or as a
		# Vector2i(min, max) range that every particle rolls within when it is
		# created, so a batch of the same material never fires in lockstep.
		#
		# `despawn` fires once and takes the particle with it (Fire -> Smoke).
		# `every` fires over and over and leaves the particle alone, trying to
		# place its products in a neighbouring cell each time (Lava -> Fire).
		"despawn": null,
		"every": null,
		"spawn": [],
		"changeVelocity": null # Vector2
	}
}

static var _cached_configs: Dictionary = {}

static func get_config(type_name: String) -> Dictionary:
	if _cached_configs.has(type_name):
		return _cached_configs[type_name] as Dictionary

	if not TYPES.has(type_name):
		push_warning("Unknown particle type: ", type_name)
		return DEFAULTS.duplicate(true)

	var merged: Dictionary = DEFAULTS.duplicate(true)
	var default_interaction: Dictionary = (merged["interaction"] as Dictionary).duplicate(true)
	var default_timer: Dictionary = (merged["timer"] as Dictionary).duplicate(true)
	merged.erase("interaction")
	merged.erase("timer")

	_merge_dict(merged, TYPES[type_name] as Dictionary)

	for target: String in merged.get("interactions", {}):
		var inter: Dictionary = (merged["interactions"] as Dictionary)[target] as Dictionary
		inter = inter.duplicate(true)
		inter = _merge_with_defaults(inter, default_interaction)
		merged["interactions"][target] = inter

	for timer_name: String in merged.get("timers", {}):
		var timer: Dictionary = (merged["timers"] as Dictionary)[timer_name] as Dictionary
		timer = _merge_with_defaults(timer.duplicate(true), default_timer)
		merged["timers"][timer_name] = timer

	_cached_configs[type_name] = merged
	return merged


static func _merge_dict(base: Dictionary, override: Dictionary) -> void:
	for key: String in override:
		if base.has(key) and base[key] is Dictionary and override[key] is Dictionary:
			_merge_dict(base[key] as Dictionary, override[key] as Dictionary)
		else:
			base[key] = override[key]


static func _merge_with_defaults(specific: Dictionary, defaults: Dictionary) -> Dictionary:
	var merged: Dictionary = defaults.duplicate(true)
	_merge_dict(merged, specific)
	return merged

const TYPES = {
	"Sand": {
		"initialGravity": Vector2(0, 1),
		"colors": ["#f4c430"], # Saffron
		"solid": true,
		"density": 1.5,
		"interactions": {
			"Water": {
				"spawn": [],
				"destroy": false,
				"resetTimers": []
			},
			"Lava": {
				"spawn": [],
				"destroy": true,
				"resetTimers": []
			}
		},
		"idleBehaviors": {
			"changeVelocity": Vector2.ZERO
		},
		"timers": {}
	},
	"Water": {
		"initialGravity": Vector2(0, 1),
		"colors": ["#2e86de", "#2a7fd6"], # Bright Blue, Near-Identical Blue
		"liquid": true,
		"density": 1.0,
		"interactions": {
			"Fire": {
				"spawn": ["Steam"],
				"destroy": true,
				"resetTimers": []
			},
			"Lava": {
				"spawn": ["Steam"],
				"destroy": true,
				"resetTimers": []
			}
		},
		"idleBehaviors": {
			"changeVelocity": Vector2.ZERO
		},
		"timers": {}
	},
	"Stone": {
		"initialGravity": Vector2(0, 0),
		"colors": ["#7f8c8d"], # Steel Grey
		"solid": true,
		"density": 2.0,
		"interactions": {
			"Lava": {
				"spawn": [],
				"destroy": false,
				"resetTimers": []
			}
		},
		"idleBehaviors": {
			"changeVelocity": Vector2.ZERO
		},
		"timers": {}
	},
	"Fire": {
		"initialGravity": Vector2(0, -1),
		"spread": Vector2(2,2),
		"colors": ["#ff3b30", "#ff9500", "#ffcc00"], # Red-Orange, Orange, Yellow
		"density": 0.3,
		"interactions": {
			"Plant": {
				"spawn": ["Fire"],
				"destroy": false,
				"resetTimers": ["Life"]
			},
			"Water": {
				"spawn": [],
				"destroy": true,
				"resetTimers": []
			}
		},
		"timers": {
			"Life": {
				"despawn": Vector2i(600, 1000),
				"spawn": ["Smoke"],
				"changeVelocity": Vector2.ZERO
			},
		}
	},
	"Smoke": {
		"initialGravity": Vector2(0, -0.5),
		"colors": ["#95a5a6", "#7f8c8d"], # Light Grey, Grey
		"density": 0.1,
		"interactions": {},
		"idleBehaviors": {
			"changeVelocity": Vector2.ZERO
		},
		"timers": {
			"Life": {
				"despawn": Vector2i(1200, 1800),
				"spawn": [],
				"changeVelocity": Vector2.ZERO
			}
		}
	},
	"Steam": {
		"initialGravity": Vector2(0, -1.5),
		"colors": ["#ecf0f1", "#d5dbdb"], # Off-White, Light Grey
		"density": 0.05,
		"interactions": {},
		"idleBehaviors": {
			"changeVelocity": Vector2.ZERO
		},
		"timers": {
			"Life": {
				"despawn": Vector2i(1000, 1400),
				"spawn": [],
				"changeVelocity": Vector2.ZERO
			}
		}
	},
	"Plant": {
		"initialGravity": Vector2(0, 0),
		"colors": ["#27ae60", "#25a25b"], # Emerald, Near-Identical Green
		"solid": true,
		"density": 0.8,
		"interactions": {
			"Fire": {
				"spawn": ["Fire"],
				"destroy": true,
				"resetTimers": []
			}
		},
		"idleBehaviors": {
			"changeVelocity": Vector2.ZERO
		},
		"timers": {}
	},
	"Ash": {
		"initialGravity": Vector2(0, 0.3),
		"colors": ["#424949"], # Charcoal
		"density": 0.5,
		"interactions": {},
		"idleBehaviors": {
			"changeVelocity": Vector2.ZERO
		},
		"timers": {
			"Life": {
				"despawn": Vector2i(2500, 3500),
				"spawn": [],
				"changeVelocity": Vector2.ZERO
			}
		}
	},
	"Lava": {
		"initialGravity": Vector2(0, 1),
		"colors": ["#e63946", "#df323f"], # Red, Near-Identical Red
		"liquid": true,
		"density": 2.5,
		"interactions": {},
		"idleBehaviors": {
			"changeVelocity": Vector2.ZERO
		},
		"timers": {
			"Bubble": {
				"every": Vector2i(1500, 4000),
				"spawn": ["Fire"]
			}
		}
	}
}
