#!/usr/bin/env python3
"""Turns the brand kit's SVGs into recolourable layers in App/Resources/Companion.

Each colour becomes a {{token}} from plumage.json, chosen per element because the same gold means
different things in different layers. Run again only when docs/brand/final changes.
"""
import pathlib
import re
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
ART = ROOT / "docs/brand/final"
OUT = ROOT / "App/Resources/Companion"
SVG = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG)
Q = lambda tag: f"{{{SVG}}}{tag}"


def load(path):
    return ET.parse(ART / path).getroot()


def by_id(root, name):
    found = root.find(f".//*[@id='{name}']")
    assert found is not None, name
    return found


def paint(element, **tokens):
    """Sets fill/stroke to tokens on the element and everything inside it. hexes={old: token} maps by colour."""
    hexes = tokens.pop("hexes", {})
    for node in element.iter():
        for attribute in ("fill", "stroke"):
            value = node.get(attribute)
            if value in hexes:
                node.set(attribute, "{{" + hexes[value] + "}}")
            elif attribute in tokens and value not in (None, "none") and not str(value).startswith("url"):
                node.set(attribute, "{{" + tokens[attribute] + "}}")
    return element


def write(name, view_box, *elements, defs=None):
    root = ET.Element(Q("svg"), {"viewBox": view_box})
    if defs is not None:
        root.append(defs)
    root.extend(elements)
    text = ET.tostring(root, encoding="unicode")
    OUT.joinpath(name + ".svg").write_text(text + "\n")


OUT.mkdir(parents=True, exist_ok=True)
for old in OUT.glob("*.svg"):
    old.unlink()

CANVAS = "0 0 120 120"
CENTRED = "-60 -60 120 120"  # the layer's centre is its pivot

# Perched: pieces that move on their own are separate layers.
body = load("companion/stitched/body.svg")
defs = body.find(Q("defs"))
paint(defs.find(f".//{Q('rect')}"), fill="wingSatin")
peg = load("companion/peg.svg")
paths = peg.findall(Q("path"))
paint(paths[0], stroke="metal")
paint(paths[1], stroke="pegShadow")
write("perched-peg", CANVAS, *paths)
write("perched-legs", CANVAS, paint(by_id(load("companion/legs.svg"), "legs"), fill="metal", stroke="metal"))
write("perched-feet", CANVAS, paint(by_id(load("companion/feet-tucked.svg"), "feet-tucked"), stroke="metal"))
write("perched-tail", CANVAS, paint(by_id(body, "tail"), fill="feather", stroke="stitch"))
write("perched-body", CANVAS,
      paint(by_id(body, "body"), fill="body", stroke="stitch"),
      by_id(body, "body-shade"),
      paint(by_id(body, "chest"), stroke="stitch"),
      paint(by_id(body, "belly-stitch"), stroke="stitch"),
      paint(by_id(body, "thighs"), fill="feather", stroke="stitch"),
      defs=defs)
write("perched-wing", CANVAS, by_id(body, "wing"), defs=defs)
write("perched-cradle", CANVAS, paint(by_id(body, "cradle-feather"), fill="stitch"))
write("perched-neck", CANVAS, paint(by_id(body, "neck"), stroke="body"), paint(by_id(body, "neck-ruff"), stroke="stitch"))

egg = load("companion/egg.svg")
write("perched-egg", CENTRED, paint(egg.find(Q("ellipse")), fill="egg"))

head = load("companion/stitched/head.svg")
write("perched-crest", CENTRED, paint(by_id(head, "crest"), fill="crest"))
eye = by_id(head, "eye")
circles = eye.findall(Q("circle"))
paint(circles[0], fill="eye")
paint(circles[1], fill="body")
write("perched-eye", CENTRED, eye)
write("perched-head", CENTRED,
      paint(by_id(head, "skull"), fill="body", stroke="stitch"),
      paint(by_id(head, "beak"), fill="beak"),
      by_id(head, "mouth"))

shade = load("companion/head-shade.svg")
write("perched-head-shade", CANVAS, by_id(shade, "head-shade"), defs=shade.find(Q("defs")))

doze = load("companion/stitched/head-doze.svg")
doze_defs = doze.find(Q("defs"))
pieces = [node for node in doze if node.tag != Q("defs")]
paint(pieces[0], stroke="body")                  # neck
paint(pieces[1], fill="body", stroke="stitch")   # skull
paint(pieces[3], fill="crest")
paint(pieces[4], fill="beak")
paint(pieces[5], stroke="eye")                   # closed eye
write("perched-head-doze", CANVAS, *pieces, defs=doze_defs)

# Cord.
FULL = "0 0 120 230"
write("cord-mount", FULL, paint(by_id(load("cord/mount.svg"), "mount"), fill="metal"))
braid = by_id(load("cord/braid.svg"), "braid")
strands = braid.findall(Q("path"))
paint(strands[0], stroke="braidA")
paint(strands[1], stroke="braidB")
write("cord-braid", "0 0 120 160", braid)
knot = load("cord/knot.svg").find(f".//{Q('g')}")
parts = list(knot)
paint(parts[0], fill="knot")
paint(parts[1], stroke="braidB")
write("cord-knot", "54 15 12 10", knot)
write("cord-swing", FULL, paint(by_id(load("cord/swing.svg"), "swing"), fill="metal", stroke="metal"))

swing_bird = load("cord/remi-on-swing.svg")
remi = by_id(swing_bird, "remi")
shapes = list(remi)
paint(shapes[0], fill="body")
paint(shapes[1], fill="beak")
paint(shapes[2], fill="egg")
feet = by_id(swing_bird, "feet")
write("cord-remi", FULL, remi, paint(feet, stroke="metal"))
# The mark's eye is a hole in the silhouette; this fills it while Remi's eyes are closed.
eyelid = ET.Element(Q("circle"), {"cx": "66.08", "cy": "180.26", "r": "1.15", "fill": "{{body}}"})
write("cord-eyelid", FULL, eyelid)

count = len(list(OUT.glob("*.svg")))
print(f"wrote {count} layers to {OUT.relative_to(ROOT)}")
leftovers = [path.name for path in OUT.glob("*.svg") if re.search(r"#C9A25A", path.read_text()) and "wing" not in path.name]
print("layers still holding raw gold:", leftovers)
