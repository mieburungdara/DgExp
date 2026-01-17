extends ProgressBar

@export var healthy_color: Color = Color.GREEN
@export var caution_color: Color = Color.YELLOW
@export var danger_color: Color = Color.RED

func _ready():
    z_index = 10 # Pastikan bar selalu berada di atas sprite

func setup(max_hp: int):
    max_value = max_hp
    value = max_hp
    visible = false # Sembunyikan saat penuh
    modulate = healthy_color

func update_hp(new_hp: int):
    # 1. Tampilkan bar jika HP berkurang
    if new_hp < max_value:
        visible = true
    
    # 2. Buat animasi perubahan nilai (Smooth)
    var tween = create_tween()
    tween.tween_property(self, "value", new_hp, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    
    # 3. Tentukan warna berdasarkan persentase HP
    var percent = float(new_hp) / float(max_value)
    var target_color = healthy_color
    
    if percent < 0.3:
        target_color = danger_color
    elif percent < 0.6:
        target_color = caution_color
        
    # Animasikan perubahan warna bersamaan dengan nilai HP
    tween.parallel().tween_property(self, "modulate", target_color, 0.2)
    
    # 4. Sembunyikan jika mati (tunggu animasi selesai)
    if new_hp <= 0:
        await tween.finished
        visible = false
