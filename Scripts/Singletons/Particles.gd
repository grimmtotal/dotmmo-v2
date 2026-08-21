extends Node

const DEFAULTS = {
	"initialGravity": Vector2(0, 0),
	"colors": ["#754b25ff"],
	# How the renderer paints this material, past its colour. Every field is
	# consumed by Shaders/WorldCells.gdshader, uploaded once at startup as a
	# lookup row per type, so none of it costs the simulation anything.
	"look": {
		# Per-particle brightness variation, so a mass of one material has
		# grain instead of reading as a single flat plane. Rolled once when a
		# particle is created and carried with it as it moves, so a falling
		# grain keeps its own shade rather than twinkling on the way down.
		"grain": 0.08,
		# Brightness that moves over time. High values flicker like flame; low
		# ones read as a glint crawling over a surface.
		"glow": 0.0,
		# Face shading across the cell - lit along the top, dark underneath.
		# This is what makes a solid read as a block you could stand on, so
		# liquids and gases leave it near zero and stay continuous instead.
		"bevel": 0.0,
		# Opacity. Gases sit well below 1 so a plume shows the sky through it.
		"alpha": 1.0
	},
	"solid": false,
	"liquid": false,
	# Whether the collector box can pick this up and carry it.
	#
	# Loose matter can be gathered and moved; terrain and living things cannot,
	# and neither can fire or the gases, which are not things you scoop into a
	# box. Stone is deliberately out: it has to be broken into Rubble with
	# the breaker before any of it can be carried, which is what makes digging
	# a thing you do rather than a thing you skip.
	"capturable": false,
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
		"resetTimers": [],
		# Probability the reaction fires on any tick the two are touching, 0..1.
		# 1.0 means it always does, which is the right answer for a reaction
		# that reads as instant (sand dropped in lava). Anything that reads as
		# a process rather than an event wants a low value here: it is contact
		# time, not contact alone, that decides the outcome, and the rate is
		# what makes a burn spread at a watchable speed instead of flashing
		# through a whole bed in a tick.
		"chance": 1.0
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
		"colors": ["#e8c46a", "#c99a45"], # Pale Sand, Deep Sand
		"look": {"grain": 0.10, "bevel": 0.30},
		"solid": true,
		"capturable": true,
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
		"colors": ["#2f86e0", "#1c5da8"], # Surface Blue, Deep Blue
		"look": {"grain": 0.05, "glow": 0.10, "bevel": 0.05, "alpha": 0.86},
		"liquid": true,
		"capturable": true,
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
			},
			"Ember": {
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
		"colors": ["#6b7480", "#565f6b"], # Slate, Dark Slate
		"look": {"grain": 0.08, "bevel": 0.42},
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
		"colors": ["#ffd34d", "#ff8a1f", "#f2451f"], # Yellow Core, Orange, Red Edge
		"look": {"grain": 0.10, "glow": 0.85, "alpha": 0.95},
		"density": 0.3,
		"interactions": {
			"Plant": {
				"spawn": [],
				"destroy": false,
				"resetTimers": ["Life"]
			},
			"Ember": {
				"spawn": [],
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
		"colors": ["#585a66", "#464855"], # Ash Grey, Dark Grey
		"look": {"grain": 0.16, "alpha": 0.50},
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
		"colors": ["#e6f0f4", "#c3d3dc"], # Off-White, Pale Blue
		"look": {"grain": 0.14, "glow": 0.06, "alpha": 0.42},
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
		"colors": ["#46b055", "#2b7c38"], # Leaf, Deep Leaf
		"look": {"grain": 0.13, "bevel": 0.22},
		"solid": true,
		"density": 0.8,
		"interactions": {
			"Fire": {
				"spawn": ["Ember"],
				"destroy": true,
				"resetTimers": [],
				"chance": 0.25
			},
			"Ember": {
				"spawn": ["Ember"],
				"destroy": true,
				"resetTimers": [],
				# The rate a burn creeps through a bed. An ember lives 1.2-2.2s,
				# so at this rate it very nearly always passes the burn on
				# before it dies - but not quite always, which is what lets a
				# fire fizzle out instead of every fire being total.
				"chance": 0.04
			}
		},
		"idleBehaviors": {
			"changeVelocity": Vector2.ZERO
		},
		"timers": {}
	},
	"Ash": {
		"initialGravity": Vector2(0, 0.3),
		"colors": ["#3a3a40", "#2c2c31"], # Charcoal, Soot
		"look": {"grain": 0.15, "bevel": 0.10, "alpha": 0.92},
		"capturable": true,
		"density": 0.5,
		"interactions": {},
		"idleBehaviors": {
			"changeVelocity": Vector2.ZERO
		},
		# No despawn timer: ash is something you gather and carry now, so a
		# heap of it has to still be there when you come back for it. Dropping
		# the timer also lets a buried heap fall out of the active list, which
		# a despawning material can never do.
		"timers": {}
	},
	"Ember": {
		"initialGravity": Vector2(0, 0),
		"colors": ["#ff7a1a", "#a83208"], # Hot Cinder, Dull Cinder
		"look": {"grain": 0.10, "glow": 0.60, "bevel": 0.24},
		"solid": true,
		"density": 0.8,
		"interactions": {
			"Water": {
				"spawn": [],
				"destroy": true,
				"resetTimers": []
			}
		},
		"idleBehaviors": {
			"changeVelocity": Vector2.ZERO
		},
		"timers": {
			# Two timers at once: it burns down to Ash on the life timer while
			# throwing flame off whatever face is open on the repeating one. An
			# ember buried in a bed has no open face, so it smoulders to Ash
			# without ever showing a flame - which is what you want, and costs
			# nothing to arrange.
			"Life": {
				"despawn": Vector2i(1200, 2200),
				"spawn": ["Ash"]
			},
			"Burn": {
				"every": Vector2i(150, 400),
				"spawn": ["Fire"]
			}
		}
	},
	# Broken stone. The only way to carry rock: Stone itself is not capturable,
	# so terrain has to be chewed into Rubble with the breaker before any of it
	# can be picked up. Warmer and lighter than the slate it comes from, and
	# heavily grained, so a pile of debris reads as debris at a glance.
	"Rubble": {
		"initialGravity": Vector2(0, 1),
		"colors": ["#8a8578", "#6d6a60"], # Grit, Dark Grit
		"look": {"grain": 0.18, "bevel": 0.28},
		"solid": true,
		"capturable": true,
		"density": 1.8,
		"interactions": {
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
	"Lava": {
		"initialGravity": Vector2(0, 1),
		"colors": ["#ff9a2b", "#c22a10"], # Molten, Crust
		"look": {"grain": 0.07, "glow": 0.55, "bevel": 0.06},
		"liquid": true,
		"capturable": true,
		"density": 2.5,
		"interactions": {},
		"idleBehaviors": {
			"changeVelocity": Vector2.ZERO
		},
		"timers": {
			"Bubble": {
				"every": Vector2i(1500, 40000),
				"spawn": ["Fire"]
			}
		}
	}
}
