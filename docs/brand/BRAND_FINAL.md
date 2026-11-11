# Remi: final brand kit

**Remi, a little bird that remembers for you.** Short form for listings: **Remi for Mac**.

Direction: Couture. A Sankofa-inspired bird in ivory, jet and thread gold, embroidered with a gold running stitch. Remi looks back at the egg on its back: going back for what you meant to do. Everything below lives in `docs/brand/final/` as vector SVG. The design canvas is the visual reference for anything this file does not cover.

## Decisions

| Item | Choice |
|---|---|
| Name | **Remi** (`APP_DISPLAY_NAME = Remi`). The app and the bird share the name. |
| Tagline | a little bird that remembers for you |
| App icon / mark | **The Sankofa bird**: a solid ivory silhouette built from circles, with wing and eye cut as negative space, head turned back to the gold egg on its back, on jet |
| Wordmark | Bodoni Moda, lower case: `remi`. Optional flourish: the dot of the i drawn as the gold egg |
| Companion modes | **Perched** (Remi on a gold peg at the side edge) and **On the cord** (Remi on a swing at the end of the knotted cord). **Pebble is retired.** |
| Companion finish | **Stitched** |
| Companion colour | **Plumage** setting with four colourways (below); default **Ivory** |
| Egg | Cradled on the back (perched); carried on the back of the mark (cord) |
| UI type | SF Pro (system) |
| Panel accent | Thread gold `#C9A25A` in place of the system blue, used lightly |

## Palette

| Name | Hex | Use |
|---|---|---|
| Jet | `#121110` | Icon background, eye, text on gold |
| Ivory | `#F2ECE0` | Bird body |
| Thread gold | `#C9A25A` | Egg, beak, legs, wing satin, stitching, peg, cord, accent |
| Oxblood | `#7A2A2E` | Oxblood plumage |
| Gold on ivory | `#B08A3E` | Gold when it sits on ivory |
| Gold shadow | `#7E6436` | Underside of the peg |

## Plumage (the colour setting)

`final/plumage.json` defines four colourways. Each one recolours the perched bird, the cord and Remi on the cord together, so they always match. It replaces the old companion colour list (stone grey, off-white, charcoal, terracotta). Migrate any old choice to Ivory.

| Colourway | When | Body | Egg / beak | Metal (peg, legs, cord fittings) |
|---|---|---|---|---|
| **Ivory** (default) | Dark wallpapers | `#F2ECE0` | `#C9A25A` | `#C9A25A` |
| **Jet** | Light wallpapers | `#24211E` | `#C9A25A` | `#C9A25A` |
| **Oxblood** | Warm and rich | `#7A2A2E` | `#D8B56A` | `#D8B56A` |
| **Brass** | A goldweight bird | `#C9A25A` | egg `#F2ECE0`, beak `#121110` | `#121110` |

Full token sets (feather, stitch, wing satin, crest, eye, egg text, halo, braid strands, knots) are in the JSON.

## Files

```
final/
  mark/       mark.svg (for dark), mark-dark-on-light.svg, mark-mono.svg (currentColor), tile.svg (preview),
              lockup-remi-on-dark.svg, lockup-remi-on-light.svg, lockup-remi-tagline-on-dark.svg
  icon/       background.svg, foreground-bird.svg, foreground-egg-beak.svg (1024 canvas, Icon Composer layers)
  menubar/    menubar-template.svg (black on transparent, 19 x 18 pt, template image)
  companion/  stitched/  body.svg, head.svg, head-doze.svg, bird-rest-reference.svg
              egg.svg, head-shade.svg, legs.svg, feet-tucked.svg, peg.svg
              plumage/bird-rest-<colourway>.svg (the perched bird in each plumage, for reference)
  cord/       braid.svg, knot.svg, mount.svg, swing.svg, remi-on-swing.svg, reference-<colourway>.svg
  plumage.json
  archive/    spiral/ (earlier mark), cord-tassel/ (earlier cord ending), kept for reference only
```

## Perched companion: geometry

Drawn in a 120 x 120 space (y down), shown at about 104 x 108 pt.

**Draw order, back to front:** peg, legs (or feet-tucked), body (tail, body, light, chest, belly stitch, thighs, wing, cradle feather, neck, neck ruff), egg, head, head-shade.

- **Egg:** `egg.svg` placed with `translate(52, 56) rotate(-14°)`. The count is live text in the same group (Bodoni Moda italic 500, size 11), so it tilts and rocks with the egg.
- **Head:** `head.svg`. Its origin is the neck pivot at **(81, 35)**, beak along +x. It is symmetric about the beak line (eye on the line, crest trailing behind), so it turns a full circle and never flips.
- **Head light:** `head-shade.svg` at (81, 35) never rotates. The fixed highlight makes the head read as a lit ball.
- **Crest:** a little fan of three rounded feathers behind the head (centre one along the beak line, two at ±30°), in body colour with stitched edges and a gold quill each (crest token). It replaced the old gold V, which read as a second open beak. The beak stays the only solid gold point on the head.
- **Crest pivot** (for the lag): (-9, 0) in head space.
- **Neck** never rotates. The neck ruff stitches hide the join.
- **Legs** are static. Thigh feathers cover the tops of the legs.
- **Peg** starts at x = 0, the screen edge. It is the perch.

### Stitched finish: two build rules
- **No crawling stitches.** Animate breathing and the head as transforms on finished layers. Never re-stroke scaled paths, so each dash stays locked to its spot.
- **Hold the edge.** Give the bird a faint halo (about 1 pt, 25% opacity, no offset) in the plumage `halo` colour so it keeps its outline on any wallpaper.

## Head follow

The head turns as one solid object all the way round, over the top, and never looks through its own body.

```
pivot = (81, 35)                                    // 120 space, y down
a = atan2(pointer.y - pivot.y, pointer.x - pivot.x) in degrees, 0..360
t = (a - 140 + 360) mod 360                          // position along the free arc
if t > 260:                                           // pointer is "inside" the body (angles 40..140)
    t = (previousT < 130) ? 0 : 260                   // wait at the nearest edge
headAngle = 140 + t                                   // 140..400, never wraps: always swings over the top
```

- **Duration scales with distance.** A small follow takes 0.24 s with an ease-out. A big swing (more than 40° along the arc, such as coming out the other side of the body) takes `min(0.9, 0.3 + jump / 400)` seconds with an ease-in-out, so it travels round smoothly instead of snapping. Returning to rest when the pointer leaves takes 0.6 s.
- **Make it glide, never chase.** Do not restart an animation on every mouse move (that makes it jerky). Drive the head with a per-frame follower: each display frame, move the current angle toward the target with a critically damped spring (for example a stiffness of about 120 and full damping), keeping its velocity between moves. The duration rule above is the feel to match.
- **AppKit:** y points up. Flip y when converting the pointer into this space.
- **Crest lag:** on each move, `crest = clamp(-(t - previousT) * 0.8, -22°, +22°)`, then spring back to 0 over about 0.5 s with a little overshoot.
- **Rest:** t = 6 (looking back at the egg). **Facing forward:** t = 220.

## Moods

| Mood | Trigger | Behaviour |
|---|---|---|
| Rest | Nothing happening | Looks back at the egg. Breathes, blinks, an occasional tail flick. |
| Notices you | Pointer within about 130 pt | Head follows the pointer as above. |
| Working with you | Panel open | Faces the panel (t = 214), small head bob ±6° every 2.2 s, blinks every 2.6 s. |
| New task | Task captured | Hop, egg wobbles twice, count +1. About 1.9 s, then Rest. |
| Link caught | Link pasted with the shortcut | Three quick pecks at the egg, a gold ring pulses out of the egg twice, count +1. |
| Dozing | Idle for a while | Dozing head, breathing slows to 7 s, no flick, no rock. |
| Tucked | Resting at the edge | Slides about 43% into the edge (tail and part of the egg hidden), dozing head. Springs out (0.55 s, slight overshoot) when the pointer comes near. |
| Carried | Being dragged | Peg and legs hidden, tucked feet shown, body tilted -9°, wing lifted +12°. |
| All kept | Everything done today | Puff, crest raised -14°, a check replaces the count. |
| Morning stretch | First panel open of the day | Wing lifts twice and settles, small head shake. About 2.8 s. |

**Ambient, awake:** breathe (scale 1.025 x 1.04 about (60, 104), 4.5 s), blink every 5 s, egg rock ±3° (3.6 s), tail flick every 9 s.
**Reduce Motion:** no loops or springs. The head still points at the cursor but snaps there.

## Remi on the cord

Drawn in a 120 x 230 space, shown about 240 pt tall, hanging from the top screen edge.

**Layers:** `mount.svg` at the top edge, `braid.svg` (two strands, 160 units), up to 14 tied `knot.svg` knots at y = 20 + 10i, each sitting on a braid crossing (one per task due today). The braid has 16 tight crossings (amplitude 4.2, stroke 2.4) so the knots read as tied into it, not beads threaded on top. Each knot is a flattened bead (rx 4.3, ry 3.5) in the knot colour, a diagonal wrap in braidB and a faint highlight; draw them inside the braid group so they stretch with it, `swing.svg` (ring at (60, 160), two strands to a gold bar at y 207.2), `remi-on-swing.svg` (the mark at 0.38 scale, belly on the bar, tiny gold feet gripping it). See `reference-*.svg` for each plumage.

**Interaction:**
- **Idle:** the whole cord sways ±1.2° around the mount (6 s). The swing rocks ±2.5° around the ring (3.2 s). Remi breathes.
- **Pull:** drag Remi or the bar down (hit area at least 44 pt). The braid stretches with `scaleY = (160 + pull) / 160` from the top, and the swing moves down by `pull`. Knots spread with the braid. The swing stops rocking and Remi squats and grips (scale 1.04 x 0.94 about the bar). Maximum pull about 56 units.
- **Release:** spring back with a visible bounce (SwiftUI `.spring(response: 0.45, dampingFraction: 0.55)` or similar). The swing rocks hard and settles (+9°, -7°, +4°, -2°, 0 over 1.6 s). Remi hops once. If the pull passed about 14 units, the panel opens. A click also opens it.
- **Dozing:** sway and rock stop, breathing slows, eyes close.

### Cord states

| State | When | What happens |
|---|---|---|
| **Tucked in** (rest) | Cursor away for about 1.2 s, panel closed | The cord draws up into the top edge on a soft spring (pull -128 units: braid scales to about 0.2, swing rises the same). Only the swing and Remi peek below the edge, dozing. Rocking stops. This is the default rest state. |
| **Notices you** | Cursor within about 120 pt of the cord's x, or hovering the top edge above it | The cord lowers to full length on the release spring, with one small overshoot. Remi opens its eyes and turns its head toward the cursor (same head-follow rule as Perched). Resume idle sway and rock. |
| **Pull and release** | Drag or click | As above. Panel opens past about 14 units. |
| **Working** | Panel open | Cord stays lowered, Remi blinks every 3 to 6 s, small bob. No tucking while the panel is open. |
| **New task** | A task is added (any route, including the shortcut) | If tucked, lower first. A knot ties itself on: it slides down from the mount to its slot (y = 20 + 10i) and cinches with a squash (scale 1.3 x 0.75, then 1). Remi hops, the cord jiggles. 0.8 s. |
| **Link caught** | A link is pasted or saved | If tucked, lower first. Remi pecks toward the egg (head and body rotate -9° and back, 0.5 s), a gold ring pulses out from the egg (scale 1 to 2.6, fade, 1 s), then a knot ties on as in New task. |
| **Task done** | A task is checked off | The lowest knot loosens (scale 1.15, then fades and drops 6 units, 0.5 s). Remi gives a tiny nod. |
| **All kept** | Last task of the day done | The knots loosen and fade one by one from the bottom (80 ms apart), then Remi puffs up (1.08) and settles. |
| **Morning stretch** | First time the Mac wakes each day | The cord unrolls down from tucked once, Remi shakes (±4°, 3 cycles), then tucks again if the cursor is away. |
| **Moving** | Dragged along the top edge to reposition | The mount slides with the cursor; the cord trails behind by a spring (lean up to 8°) and swings back when you stop. |
| **Reduce Motion** | System setting | No sway, rock, hop, peck, ring or squash. Tuck and lower become 0.2 s fades between the two positions; new knots fade in. |

The live canvas board "Final · Remi (live)" demonstrates Tucked in, Notices you, Pull and release, New task, Link caught and Task done.

## App icon

- Icon Composer (macOS 26): `icon/background.svg` (jet), then `icon/foreground-bird.svg`, then `icon/foreground-egg-beak.svg`. The same artwork holds down to 16 pt.

## Menu bar

- `menubar/menubar-template.svg` as a template image (`isTemplate = true`), 18 pt tall.

## Wordmark and lockup

- `remi` in Bodoni Moda, lower case, next to or under the mark. The tagline "a little bird that remembers for you" is set in Bodoni Moda italic, in thread gold.
- For the README and listings: **Remi for Mac**.
