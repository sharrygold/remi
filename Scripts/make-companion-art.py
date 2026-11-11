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

# The head is drawn this much larger than the kit's, with a slightly wider neck so the two still read
# as one bird. Its stitches are compensated, so they match the body's size and spacing.
HEAD_SCALE = 1.15
NECK_WIDTH = "13.6"


def enlarge(about, *elements):
    """Wraps elements in the head scale about a point, keeping stitch width and spacing unchanged."""
    x, y = about
    group = ET.Element(Q("g"), {"transform": f"translate({x} {y}) scale({HEAD_SCALE}) translate({-x} {-y})"})
    for element in elements:
        for node in element.iter():
            for attribute in ("stroke-width",):
                if node.get("stroke-dasharray") and node.get(attribute):
                    node.set(attribute, f"{float(node.get(attribute)) / HEAD_SCALE:.3f}")
            if node.get("stroke-dasharray"):
                gaps = [float(v) / HEAD_SCALE for v in node.get("stroke-dasharray").split()]
                node.set("stroke-dasharray", " ".join(f"{v:.3f}" for v in gaps))
        group.append(element)
    return group


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
neck = paint(by_id(body, "neck"), stroke="body")
neck.set("stroke-width", NECK_WIDTH)
write("perched-neck", CANVAS, neck, paint(by_id(body, "neck-ruff"), stroke="stitch"))

egg = load("companion/egg.svg")
write("perched-egg", CENTRED, paint(egg.find(Q("ellipse")), fill="egg"))

head = load("companion/stitched/head.svg")
def paint_crest(crest):
    """The crest is feathers in body colour with stitched edges and a gold quill down each one."""
    paint(crest, fill="body", stroke="stitch")
    for node in crest.iter():
        if node.get("class") == "quill":
            node.set("stroke", "{{crest}}")
    return crest


write("perched-crest", CENTRED, enlarge((0, 0), paint_crest(by_id(head, "crest"))))
eye = by_id(head, "eye")
circles = eye.findall(Q("circle"))
paint(circles[0], fill="eye")
paint(circles[1], fill="body")
write("perched-eye", CENTRED, enlarge((0, 0), eye))
write("perched-head", CENTRED, enlarge((0, 0),
      paint(by_id(head, "skull"), fill="body", stroke="stitch"),
      paint(by_id(head, "beak"), fill="beak"),
      by_id(head, "mouth")))

def soften_head_light(defs):
    """The head's highlight strength depends on the plumage, so it becomes a token."""
    gradient = defs.find(f".//{Q('radialGradient')}[@id='shadeHead']")
    gradient.findall(Q("stop"))[0].set("stop-opacity", "{{headLight}}")
    return defs


shade = load("companion/head-shade.svg")
soften_head_light(shade.find(Q("defs")))
write("perched-head-shade", CANVAS, enlarge((81, 35), by_id(shade, "head-shade")), defs=shade.find(Q("defs")))

doze = load("companion/stitched/head-doze.svg")
doze_defs = soften_head_light(doze.find(Q("defs")))
pieces = [node for node in doze if node.tag != Q("defs")]
paint(pieces[0], stroke="body")                  # neck
paint(by_id(doze, "skull-doze"), fill="body", stroke="stitch")
paint_crest(by_id(doze, "crest"))
paint(by_id(doze, "beak-doze"), fill="beak")
paint(by_id(doze, "eye-doze"), stroke="eye")     # closed eye
pieces[0].set("stroke-width", NECK_WIDTH)
write("perched-head-doze", CANVAS, pieces[0], enlarge((79, 42), *pieces[1:]), defs=doze_defs)

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
