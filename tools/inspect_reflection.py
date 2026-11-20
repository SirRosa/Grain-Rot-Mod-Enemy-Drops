#!/usr/bin/env python3
"""Read-only, targeted API audit from the user's actual Helden USMAP/ObjectDump."""
import gzip
import json
import re
from pathlib import Path

root=Path("knowledge/data")
with gzip.open(root/"current-schema.json.gz","rt",encoding="utf-8") as f: db=json.load(f)
structs=db["structs"]
terms=re.compile(r"cosmet|pattern|unlock|profile|enemy|lottery|reward|catalog|characterstats|statcomponent|save|soul|playerstate|playerprofile",re.I)

def show_type(name, full=False):
    data=structs[name]
    fields=[p["name"]+":"+p["type"]+(("/"+p.get("struct","")) if p.get("struct") else "") for p in data.get("properties",[])]
    if full or terms.search(name):
        print(name,"parent="+str(data.get("parent")),"fields="+", ".join(fields))
    else:
        print(name,"fields="+", ".join(x for x in fields if terms.search(x)))

print("=== RELEVANT STRUCT NAMES ===")
names=[n for n in structs if n.startswith("Helden") and terms.search(n)]
for n in sorted(names): show_type(n)
print("=== RELEVANT PROPERTIES IN ALL HELDEN TYPES ===")
for name,data in sorted(structs.items()):
    if not name.startswith("Helden") or name in names: continue
    matches=[p["name"]+":"+p["type"]+(("/"+p.get("struct","")) if p.get("struct") else "") for p in data.get("properties",[]) if terms.search(p["name"])]
    if matches: print(name,"=>",", ".join(matches))
print("=== COSMETIC ENUMS ===")
for name,payload in db["enums"].items():
    if name.startswith("EHelden") and terms.search(name): print(name, json.dumps(payload,ensure_ascii=False))

parts=sorted(root.glob("UE4SS-ObjectDump.txt.gz.part*"))
lines=gzip.decompress(b"".join(p.read_bytes() for p in parts)).decode("utf-8",errors="replace").splitlines()
print("=== TARGETED HELDEN REFLECTED FUNCTIONS ===")
select=re.compile(r"Cosmetic|Pattern|Unlock|Profile|Lottery|Catalog|Enemy|Die_|OnDeath|Death_|OnKill|Killed|OnHealth|Destroy",re.I)
for i,line in enumerate(lines):
    if "Function /Script/Helden." not in line or not select.search(line): continue
    print(line.split("] ",1)[-1].split(" [n:",1)[0])
    for arg in lines[i+1:i+9]:
        if " /Script/Helden." not in arg: break
        if "Function /" in arg or "Class /" in arg or "ScriptStruct /" in arg: break
        print("  "+arg.split("] ",1)[-1].split(" [o:",1)[0])
print("=== CLASSES MATCHED IN OBJECT DUMP ===")
for line in lines:
    if "Class /Script/Helden." in line and select.search(line):
        print(line.split("] ",1)[-1].split(" [n:",1)[0])


print("=== REFLECTED METHODS: PROFILE/COSMETIC LOOT/DEATH ===")
wanted={"HeldenGameInstance","HeldenProfileSaveGame","HeldenSaveGameSystem","HeldenPlayerState","HeldenCosmeticLoot","HeldenDataSingleton","HeldenDungeonEnemyManager","HeldenCharacter","HeldenCharacterStats","HeldenCharacterSoul","HeldenCosmeticMenuWidget","HeldenCheatManager","HeldenPlayerController"}
for i,line in enumerate(lines):
    if "Function /Script/Helden." not in line: continue
    head=line.split("Function /Script/Helden.",1)[-1].split(" ",1)[0]
    cls=head.split(":",1)[0]
    if cls not in wanted: continue
    print(cls+":"+head.split(":",1)[-1])
    for arg in lines[i+1:i+7]:
        if "/Script/Helden."+cls+":"+head.split(":",1)[-1]+":" in arg:
            print("  "+arg.split("] ",1)[-1].split(" [o:",1)[0])
        else: break
print("=== CLASS/OBJECTS COSMETIC PROFILE ASSET PATHS ===")
c=0
for line in lines:
    if re.search(r"(?:Class|BlueprintGeneratedClass|DataTable) (?!/Script/)(?:[^ ]*(Cosmetic|Pattern|Profile|Enemy)[^ ]*)",line,re.I):
        print(line[:300]);c+=1
        if c>120:break


print("=== INTERACTABLE OBJECT METHODS ===")
for i,line in enumerate(lines):
    if "Function /Script/Helden.HeldenInteractableObject:" in line or "Function /Script/Helden.HeldenCosmeticLoot:" in line:
        print(line.split("] ",1)[-1].split(" [n:",1)[0])
        for arg in lines[i+1:i+6]:
            if "/Script/Helden.HeldenInteractableObject:" in arg or "/Script/Helden.HeldenCosmeticLoot:" in arg:
                if "Function /" in arg: break
                print("  "+arg.split("] ",1)[-1].split(" [o:",1)[0])
            else: break
