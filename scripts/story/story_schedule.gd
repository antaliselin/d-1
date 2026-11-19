class_name StorySchedule
extends RefCounted

const PORTRAITS := {
	"old-soldier": "veteran",
	"underground-clinic": "doctor",
	"wounded-scavenger": "scout",
	"courier": "courier",
}

var progress: Dictionary = {}
var last_seen: Dictionary = {}


func next_story(day: int, ownership: String, seed_value: int) -> Dictionary:
	var pool: Array[Dictionary] = []
	var weights := PackedFloat32Array()
	for story: Dictionary in ShopCatalog.STORIES.data:
		var stage := int(progress.get(story.id, 0))
		if stage >= story.stages.size() or int(last_seen.get(story.id, 0)) >= day:
			continue
		if story.get("act", "any") == "post" and ownership == "gang":
			continue
		if story.has("requiresOwnership") and ownership not in story.requiresOwnership:
			continue
		pool.append(story)
		weights.append(float(story.weight) * (3.0 if stage > 0 else 1.0))
	if pool.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + day * 102503
	var story := pool[rng.rand_weighted(weights)]
	last_seen[story.id] = day
	var index := int(progress.get(story.id, 0))
	var stage: Dictionary = story.stages[index].duplicate(true)
	stage.id = story.id
	stage.kind = "story"
	stage.stage_index = index
	stage.stage_count = story.stages.size()
	stage.heading = story.title
	if PORTRAITS.has(story.id):
		stage.speaker.portrait = PORTRAITS[story.id]
	return stage


func advance(event: Dictionary, ends: bool) -> void:
	progress[event.id] = int(event.stage_count) if ends else int(event.stage_index) + 1
