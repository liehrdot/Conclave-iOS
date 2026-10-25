"""Writes App/Resources/demo.json, the made-up account the app shows in demo mode and in the
screenshots: the PWA's demo read model (Conclave's src/mtgdeck/sync/app/demo.json) with its German
deck texts, notes and Rule 0 put into English, and the English fields a current server sends
(rule0_en, level_en, speed label_en/text_en, options_en). Run it again when the PWA's demo changes:

    python3 scripts/make_demo.py <path to Conclave's demo.json>
"""

import json
import re
import sys
from pathlib import Path

NAMES = {"Aesi – Gezeiten der Ländereien": "Aesi – Tides of the Lands", "Tiamats Goldhort": "Tiamat's Hoard",
         "Tamiyo – Die Krone, die zurückschlägt": "Tamiyo – The Crown Strikes Back"}
TEXTS = {
    "Opfern, zurückholen, Leben abziehen – Meren holt jede Runde etwas aus dem Friedhof.":
        "Sacrifice, recur, drain – Meren brings something back from the graveyard every turn.",
    "Länder legen, Karten ziehen, mit Landfall-Wellen gewinnen.": "Play lands, draw cards, win with waves of landfall.",
    "Drachen aus der Bibliothek holen und mit Schätzen über alle hinweg rampen.":
        "Fetch dragons from the library and ramp past everyone with Treasure.",
    "Spontanzauber, Counter und ein Planeswalker, der zurückschlägt.": "Instants, counters and a planeswalker who strikes back.",
    "Menschen-Token und Angriffe aus allen Richtungen.": "Human tokens and attacks from every side.",
    "Gewinnt gern über Thassa's Oracle – Friedhofs-Hass und Instant-Removal bereithalten.":
        "Likes to win with Thassa's Oracle – keep graveyard hate and instant removal ready.",
    "Krenko sofort entfernen, sonst Zug 5 vorbei.": "Remove Krenko at once, or it's over by turn 5.",
    "Gray Merchant dreimal zurückgeholt": "Brought Gray Merchant back three times",
}  # fmt: skip
LABELS = {"Stufe": "Level", "Commander": "Commander", "Spielweise": "Play style", "Tempo": "Speed",
          "Game Changer": "Game Changers", "2-Karten-Combos": "Two-card combos", "Tutoren": "Tutors",
          "Extra-Züge": "Extra turns", "Land-Zerstörung": "Land destruction", "Proxys": "Proxies"}  # fmt: skip
SPEED = {"very-fast": ("Very fast", "cEDH pace: as cheap as Bracket 5 and strong Bracket 4 decks."),
         "fast": ("Fast", "Strong Bracket 4 pace: almost everything hits the table early."),
         "brisk": ("Brisk", "Well tuned, like a strong Bracket 3 or a relaxed Bracket 4."),
         "steady": ("Steady", "Typical casual pace, about like a precon."),
         "slow": ("Slow", "Lots of expensive cards: the deck takes a while to get going.")}  # fmt: skip
TIERS = {"unteres": "lower", "mittleres": "mid", "oberes": "upper"}
OPTIONS_EN = {
    "results": {"win": "Win", "loss": "Loss", "draw": "Draw"},
    "issues": [["few_lands", "too few lands"], ["flood", "drew too many lands"], ["colors", "wrong colours / colour problems"],
               ["slow", "too slow"], ["no_draw", "empty hand, too little card draw"], ["no_removal", "no answer to threats"],
               ["wiped", "a board wipe set me back"], ["commander_removed", "commander removed again and again"],
               ["no_win", "no way to win"], ["combo", "lost to a combo"], ["fliers", "lost to fliers / evasion"],
               ["too_strong", "deck was too strong for the table"]],
    "tags": [["combo", "Combo"], ["fast", "fast & aggressive"], ["stax", "Stax / lock"], ["wipes", "lots of board wipes"],
             ["counters", "lots of counterspells"], ["removal", "lots of removal"], ["fliers", "Fliers"],
             ["tokens", "Token swarms"], ["graveyard", "Graveyard / reanimation"], ["lifegain", "Lifegain"],
             ["voltron", "Voltron / commander damage"], ["artifacts", "Artifacts"], ["spells", "Spellslinger"],
             ["theft", "Theft / control"], ["lands", "Land destruction"], ["politics", "Politics / group play"]],
    "how": [["combat", "combat damage"], ["commander", "commander damage"], ["combo", "combo"],
            ["alt", "alternative win condition"], ["concede", "concession"], ["other", "other"]],
}  # fmt: skip


def level(text: str) -> str:
    first, *rest = text.split(" ", 1)
    return f"{TIERS[first]} {rest[0]}" if first in TIERS else text


def value(label: str, text: str, deck: dict) -> str:
    if label == "Stufe":
        return re.sub(r"Einschätzung (\d),(\d)", r"estimate \1.\2", level(text))
    if label == "Spielweise":
        return TEXTS.get(text, text)
    if label == "Tempo":
        s = deck["speed"]
        avg = re.search(r"Ø (\d),(\d+)", text)
        end = text.rsplit(": ", 1)[1].replace("Zug", "turn").replace("jederzeit", "any time")
        return f"{SPEED[s['key']][0]} (total mana value {s['total']}, avg {avg[1]}.{avg[2]}) · earliest game end by bracket: {end}"
    if label == "Proxys":
        return "Proxy deck – contains self-printed cards"
    return "none" if text == "keine" else text


def main(source: str) -> None:
    demo = json.loads(Path(source).read_text())
    for d in demo["decks"]:
        d["name"] = NAMES.get(d["name"], d["name"])
        d["description"] = TEXTS.get(d["description"], d["description"])
        d["level_en"] = level(d["level"])
        d["speed"]["label_en"], d["speed"]["text_en"] = SPEED[d["speed"]["key"]]
        rows = [{"label": LABELS[r["label"]], "value": value(r["label"], r["value"], d), "flag": r["flag"]}
                for r in d["rule0"]["rows"]]  # fmt: skip
        title = f"{d['name']} – Rule 0"
        text = "\n".join([title] + [f"{r['label']}: {r['value']}" for r in rows] + ["Does this fit your table?"])
        d["rule0_en"] = {"rows": rows, "text": text}
    for o in demo["opponents"]:
        for n in o["notes"]:
            n["text"] = TEXTS.get(n["text"], n["text"])
        for p in o["record"]["per_deck"]:
            p["name"] = NAMES.get(p["name"], p["name"])
    for g in demo["games"]:
        g["note"] = TEXTS.get(g.get("note") or "", g.get("note") or "")
    demo["options_en"] = OPTIONS_EN
    out = Path(__file__).parent.parent / "App/Resources/demo.json"
    out.write_text(json.dumps(demo, ensure_ascii=False, indent=1) + "\n")
    print(f"wrote {out}")


if __name__ == "__main__":
    main(sys.argv[1])
