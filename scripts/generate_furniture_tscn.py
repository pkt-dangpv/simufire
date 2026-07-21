"""
Genera .tscn wrappers para assets GLB en assets/fp/furniture/gltfs/
Uso: python scripts/generate_furniture_tscn.py
"""

import os

GLTF_DIR = "assets/fp/furniture/gltfs"
TSCN_DIR = "assets/fp/furniture"

# Muebles existentes: nombre_tscn -> glb_stem
EXISTING_MAP = {
    "sofa":         "loungeSofa",
    "armchair":     "loungeChair",
    "bed":          "bedDouble",
    "bookcase":     "bookcaseOpen",
    "table":        "table",
    "coffee_table": "tableCoffee",
    "wardrobe":     "bookcaseClosedDoors",
    "dresser":      "cabinetBedDrawer",
    "tv_stand":     "cabinetTelevision",
    "rug":          "rugRectangle",
    "kitchen_unit": "kitchenCabinet",
    "plastic_bin":  "trashcan",
}

# Muebles nuevos: nombre_tscn -> glb_stem
NEW_MAP = {
    "bathtub":          "bathtub",
    "toilet":           "toilet",
    "bathroom_sink":    "bathroomSink",
    "shower":           "shower",
    "bathroom_cabinet": "bathroomCabinet",
    "desk":             "desk",
    "chair":            "chair",
    "chair_desk":       "chairDesk",
    "bed_single":       "bedSingle",
    "bed_bunk":         "bedBunk",
    "lounge_sofa_long": "loungeSofaLong",
    "kitchen_fridge":   "kitchenFridge",
    "kitchen_stove":    "kitchenStove",
    "kitchen_sink":     "kitchenSink",
    "washer":           "washer",
    "dryer":            "dryer",
    "lamp_floor":       "lampSquareFloor",
    "lamp_table":       "lampSquareTable",
    "plant":            "pottedPlant",
    "side_table":       "sideTable",
    "bench":            "bench",
}

TSCN_TEMPLATE = """\
[gd_scene format=3 load_steps=2]

[ext_resource type="PackedScene" path="res://assets/fp/furniture/gltfs/{glb}.glb" id="1"]

[node name="{root_name}" type="Node3D"]

[node name="Model" parent="." instance=ExtResource("1")]
"""

def make_root_name(tscn_stem: str) -> str:
    return "".join(w.capitalize() for w in tscn_stem.replace("-", "_").split("_"))

def write_tscn(tscn_stem: str, glb_stem: str, overwrite: bool = False):
    glb_path = os.path.join(GLTF_DIR, glb_stem + ".glb")
    if not os.path.exists(glb_path):
        print(f"  SKIP {tscn_stem}: GLB no encontrado ({glb_path})")
        return
    out_path = os.path.join(TSCN_DIR, tscn_stem + ".tscn")
    if os.path.exists(out_path) and not overwrite:
        print(f"  SKIP {tscn_stem}: ya existe (usa overwrite=True para sobreescribir)")
        return
    content = TSCN_TEMPLATE.format(
        glb=glb_stem,
        root_name=make_root_name(tscn_stem),
    )
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"  OK   {out_path}")

if __name__ == "__main__":
    print("=== Muebles existentes (reemplazando BoxMesh) ===")
    for tscn, glb in EXISTING_MAP.items():
        write_tscn(tscn, glb, overwrite=True)

    print("\n=== Muebles nuevos ===")
    for tscn, glb in NEW_MAP.items():
        write_tscn(tscn, glb, overwrite=True)

    print("\nHecho. Abre Godot para que reimporte los .tscn.")
