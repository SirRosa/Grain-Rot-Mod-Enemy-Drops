#!/usr/bin/env python3
"""Inspect user's existing Grain Rot reflection dump (read-only)."""
import gzip
import json
import re
from pathlib import Path

root = Path("knowledge")
src = root / "data" / "current-schema.json.gz"
with gzip.open(src, "rt", encoding="utf-8") as f:
    db = json.load(f)
print("=== DATABASE KEYS ===", sorted(db.keys()))
tokens = re.compile(r"pattern|cosmetic|skin|unlock|customiz|decorat|enemy|monster|mob|creature|kill|death|loot|reward|outfit|material|tint|color|palette|appearance", re.I)
priority = re.compile(r"pattern|cosmetic|skin|unlock|customiz|appearance|enemy|monster", re.I)
for group in ("structs", "enums"):
    items = db.get(group, {})
    names = [n for n in items if tokens.search(n)]
    print("\n=== MATCHES", group, "total", len(names), "===")
    for n in names[:220]:
        body = json.dumps(items[n], ensure_ascii=False, separators=(",", ":"))
        if priority.search(n):
            print(n, "=", body[:3000])
        else:
            print(n, "=", body[:400])
    print("=== OTHER SELECTED TYPES ===")
    for n in ["HeldenGameInstance","HeldenPlayerController","HeldenCharacter","HeldenSaveGame","HeldenPlayerState","HeldenDataSingleton","HeldenGameMode","HeldenGameState"]:
        if n in items:
            print(n,"=",json.dumps(items[n],ensure_ascii=False,separators=(",",":"))[:7500])
parts = sorted((root / "data").glob("UE4SS-ObjectDump.txt.gz.part*"))
dump = gzip.decompress(b"".join(p.read_bytes() for p in parts)).decode("utf-8", errors="replace")
lines = dump.splitlines()
print("\n=== REFLECTION LINE MATCHES (priority) ===")
selected = [x.strip() for x in lines if priority.search(x)]
print("total matches",len(selected))
for row in selected[:350]:
    print(row[:350])
print("\n=== REFLECTION LINES DAMAGE/KILL/DEATH (first 180) ===")
selected = [x.strip() for x in lines if re.search(r"(Helden|BP_).*(Die|Death|Kill|Died|OnHealth|Enemy|Damage|Reward)",x,re.I)]
print("total",len(selected))
for row in selected[:180]:
    print(row[:330])
