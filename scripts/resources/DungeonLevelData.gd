extends Resource
class_name DungeonLevelData

enum WinCondition {
	KILL_ALL_ENEMIES,
	KILL_BOSS,
	REACH_PORTAL
}

@export_group("Level Info")
@export var level_name: String = "Dungeon Level"
@export var win_condition: WinCondition = WinCondition.REACH_PORTAL
@export var next_level: DungeonLevelData # Level selanjutnya (Recursive)

@export_group("Spawns")
@export var boss_scene: PackedScene
@export var portal_scene: PackedScene
@export var enemy_scenes: Array[PackedScene] = []

@export_group("Generator Overrides")
# Opsi untuk override setting generator per level (misal Level 5 lebih besar)
@export var override_room_count: int = 0 # 0 = Gunakan default generator
@export var override_floor_atlas: Array[Vector2i] = []
