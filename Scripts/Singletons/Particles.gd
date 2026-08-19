extends Node

const DEFAULTS = {
	"initialGravity": Vector2(0, 0),
	"colors": ["#754b25ff"],
	"solid": false,
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

const TYPES = {
	"Sand": {
		"initialGravity": Vector2(0, 1),
		"colors": ["#E2C08D", "#D4AF37", "#C2B280"],
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
	}
}
