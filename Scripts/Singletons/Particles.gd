extends Node

const DEFAULTS = {
	"initialGravity": Vector2(0, 0),
	"colors": ["#754b25ff"],
	"solid": false,
	"liquid": false,
	"density": 1.0,
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
		"despawn": null,
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
		timer = timer.duplicate(true)
		if not timer.has("despawn"):
			timer["despawn"] = default_timer["despawn"]
		if not timer.has("spawn"):
			timer["spawn"] = default_timer["spawn"].duplicate()
		if not timer.has("changeVelocity"):
			timer["changeVelocity"] = default_timer["changeVelocity"]
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
		"colors": ["#E2C08D", "#D4AF37", "#C2B280"],
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
		"colors": ["#4FA4F4", "#2E86C1", "#5DADE2"],
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
		"colors": ["#808080", "#6E6E6E", "#595959"],
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
		"colors": ["#FF4500DD", "#FFA500DD", "#FFD700DD"],
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
		"idleBehaviors": {
			"changeVelocity": Vector2(-0.2, 0)
		},
		"timers": {
			"Life": {
				"despawn": 800,
				"spawn": ["Smoke"],
				"changeVelocity": Vector2.ZERO
			},
			"Flicker": {
				"despawn": null,
				"spawn": [],
				"changeVelocity": Vector2(0.2, 0)
			}
		}
	},
	"Smoke": {
		"initialGravity": Vector2(0, -0.5),
		"colors": ["#55555588", "#66666688", "#77777788"],
		"density": 0.1,
		"interactions": {},
		"idleBehaviors": {
			"changeVelocity": Vector2.ZERO
		},
		"timers": {
			"Life": {
				"despawn": 1500,
				"spawn": [],
				"changeVelocity": Vector2.ZERO
			}
		}
	},
	"Steam": {
		"initialGravity": Vector2(0, -1.5),
		"colors": ["#DDDDDD66", "#CCCCCC66", "#EEEEEE66"],
		"density": 0.05,
		"interactions": {},
		"idleBehaviors": {
			"changeVelocity": Vector2.ZERO
		},
		"timers": {
			"Life": {
				"despawn": 1200,
				"spawn": [],
				"changeVelocity": Vector2.ZERO
			}
		}
	},
	"Plant": {
		"initialGravity": Vector2(0, 0),
		"colors": ["#228B22", "#2ECC71", "#27AE60"],
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
		"colors": ["#2F2F2F", "#3E3E3E", "#1C1C1C"],
		"density": 0.5,
		"interactions": {},
		"idleBehaviors": {
			"changeVelocity": Vector2.ZERO
		},
		"timers": {
			"Life": {
				"despawn": 3000,
				"spawn": [],
				"changeVelocity": Vector2.ZERO
			}
		}
	},
	"Lava": {
		"initialGravity": Vector2(0, 1),
		"colors": ["#FF4500DD", "#FF2200DD", "#CC1100DD"],
		"liquid": true,
		"density": 2.5,
		"interactions": {},
		"idleBehaviors": {
			"changeVelocity": Vector2.ZERO
		},
		"timers": {}
	}
}
