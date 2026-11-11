# Motion spec

This is the motion system Remi uses, written so it can be rebuilt exactly in another product.
The numbers here are the source of truth. Do not round them, swap the curves for a default "ease" or "spring", or invent new timings.

Part 1 describes each motion in plain terms. Part 2 is the original web code (use it as-is in a web, Electron or Tauri app). Part 3 maps every motion to SwiftUI for a native macOS app. Part 4 lists where to apply it across the app, settings included.

---

## The feel in one paragraph

Calm and physical. Things arrive quickly and then settle slowly, like a drawer that glides shut on a soft stop. Nothing bounces except a small "pop" when something gets checked off. Nothing slides more than a few pixels. When you press something it gives a little under your finger straight away. When you switch tabs, one highlight travels from the old tab to the new one instead of the old one switching off and the new one switching on.

## Tokens

Three curves, three speeds. Every animation in the app uses one of these.

| Name | Curve (cubic-bezier) | Use |
|---|---|---|
| `ease` | `0.2, 0.7, 0.2, 1` | Colour, border, opacity, hover changes |
| `ease-out` | `0.16, 1, 0.3, 1` | Anything that moves into place (entrances, the sliding highlight, cards lifting). Quick start, long soft landing. |
| `ease-in-out` | `0.65, 0, 0.35, 1` | Things that open and close (accordions, collapsible panels, chevrons) |

| Speed | Duration | Use |
|---|---|---|
| Press | 80 ms | The squish when a control is pressed |
| Quick | 200 to 250 ms | Hover colours, fades out, backdrop fades |
| Settle | 420 to 520 ms | Panels entering, the sliding highlight, accordions, modals |
| Slow | 600 to 1100 ms | First-load and scroll-in reveals only |

Distances: entrances move 8 to 12 px. Nothing travels further.

---

## Part 1: each motion, described

### 1. The sliding highlight ("glider"): tabs, segmented controls, side menus, steppers
This is the one that glides between Overview, Therapists and so on.

- There is ONE highlight shape per group. It sits behind the items (lower z-index), absolutely positioned inside the group.
- When the selection changes, it moves from its current position and size to the new item's position and size. It does not fade out and back in.
- Animated properties: x, y, width, height together. Duration 500 ms, curve `ease-out` (0.16, 1, 0.3, 1). Opacity only animates (250 ms) the first time it appears.
- It matches the active item's exact frame, including when items have different widths, so the width morphs while it slides.
- The text of the active item changes colour (muted to full ink, weight 500 to 600) over 200 ms. The highlight carries the "selected" look; the item itself has no background when active.
- First appearance: place it instantly with no animation (on page load you should never see it slide in from the corner).
- Window resize or wrapping: re-place it instantly, no animation.
- Only an actual selection change animates.
- Variants:
  - Segmented control (pill): grey track, padding 4 px, gap 4 px, track radius 10. The highlight is a white pill with radius 7, a 1 px soft shadow plus a soft drop shadow: `0 1px 2px rgba(0,0,0,.08), 0 4px 12px -6px rgba(0,0,0,.22)`.
  - Side menu and stepper: the highlight is a white rounded rectangle (radius 8) with a 1 px inset hairline border.
  - Top navigation: the highlight is a 1.5 px underline under the active link, sliding the same way.

### 2. Pane and page transitions
- When you move to another page, or switch the content pane inside a dashboard (sidebar stays put), the new content fades in and rises into place.
- Page: from opacity 0 and 10 px down to opacity 1 and 0, over 520 ms, `ease-out`.
- Inner pane (inside a dashboard or settings window): 8 px, 440 ms, `ease-out`.
- Do NOT animate the first render of the app. Only changes.
- Only the part that changed animates. Switching settings sections animates the content pane, never the whole window or the sidebar.
- No exit animation. The old content is swapped out instantly and the new one eases in. This keeps it quick.
- Scroll jumps to the top instantly (no smooth scroll) on page change.

### 3. Accordion / disclosure (FAQ, history, "More filters", any expandable row)
- The height eases open and closed: 450 ms, `ease-in-out`. Never a jump.
- The content inside fades in and drops 4 px into place a moment after the height starts: delay 100 ms, opacity 400 ms `ease`, movement 500 ms `ease-out`.
- Closing: content fades out in 250 ms while the height closes.
- The chevron rotates 180 degrees (pointing down to pointing up) over 450 ms `ease-in-out`, and its opacity goes 0.55 to 0.8.
- Hidden content is not focusable when closed.

### 4. Press feedback (every pressable control)
- On press: scale to 0.96 for small controls (chips, segmented buttons, toggles, day and time pickers, icon buttons), 0.98 for wide ones (primary buttons, menu rows), 0.995 for big cards. Transition 80 ms.
- On release: back to 1 over 180 to 220 ms `ease`.
- Hover: background, border and text colour change over 200 to 220 ms `ease`.
- Primary buttons with an arrow: the arrow nudges right a few px on hover, 300 ms `ease`.

### 5. Things that appear after loading or after a choice
- Default entrance ("soft rise"): opacity 0 to 1 and 8 px up to 0.
- Notices and banners: 450 ms `ease-out`.
- Lists of cards: 600 ms `ease-out`, staggered 60 ms per item, capped at 300 ms (items 6 and later all use 300 ms).
- Stat tiles: 550 ms, stagger 50 ms, cap 150 ms.
- Hoverable cards lift 2 px and gain a soft shadow on hover, 450 ms `ease-out`.
- Chat bubbles: soft rise, 350 ms `ease-out`.
- Plain fade ("soft in") for things that should not move, such as a time grid swapping: 350 ms `ease`.
- Images and avatars fade in when they finish loading, 600 ms `ease`, so they never pop in half drawn.

### 6. Completion "pop"
- When a step or item is completed, its check mark pops: scale 0.6 to 1.08 at 70% of the way, then to 1, opacity 0 to 1, over 450 ms `ease-out`.
- This is the only overshoot in the whole system. Keep it for completion moments.

### 7. Spinners
- A spinner waits 250 ms before fading in (300 ms `ease`). Fast loads never flash a spinner.
- Spin: one turn every 800 ms, linear.

### 8. Modals, sheets, toasts, menus
- Backdrop fades in over 250 ms `ease`.
- Modal: from opacity 0, 12 px down and scale 0.98, to its resting place, 420 ms `ease-out`.
- Toast in: from 14 px down and scale 0.98, 450 ms `ease-out`. Toast out: fade and drop 8 px, 250 ms `ease`.
- Dropdown or mobile menu sheet: fades and drops in from 6 px above, 280 ms. Its items then soft-rise in one after another, 30 ms apart, capped at 120 ms.
- Icon swap (menu to close, play to pause): new icon turns in from -45 degrees and scale 0.8, 350 ms `ease-out`.

### 9. Scroll reveals (marketing or onboarding pages only, not inside the working app)
- Elements fade in and rise 18 px the first time they scroll into view: 900 ms `ease`, optional stagger.
- They animate once and stay. Trigger when 12% is visible, slightly before the bottom edge.

### 10. Reduced motion (required)
- If the user has "Reduce motion" turned on, every movement becomes an instant change or a short plain fade (about 160 ms). No sliding, rising, scaling or rotating. Spinners still spin, more slowly (1.6 s per turn).

---

## Part 2: the original web code

Use this verbatim in a web, Electron or Tauri app. It is React, but the CSS and the logic port to any framework.

### Tokens (CSS)
```css
:root {
  --ease: cubic-bezier(.2, .7, .2, 1);
  --ease-out: cubic-bezier(.16, 1, .3, 1);     /* entrances: quick start, long soft landing */
  --ease-in-out: cubic-bezier(.65, 0, .35, 1); /* things that open and close */
}
@keyframes soft-in { from { opacity: 0; } to { opacity: 1; } }
@keyframes soft-rise { from { opacity: 0; transform: translateY(8px); } to { opacity: 1; transform: none; } }
@keyframes pop-in { 0% { opacity: 0; transform: scale(.6); } 70% { transform: scale(1.08); } 100% { opacity: 1; transform: scale(1); } }
@keyframes modal-in { from { opacity: 0; transform: translateY(12px) scale(.98); } to { opacity: 1; transform: none; } }
@keyframes icon-swap { from { opacity: 0; transform: rotate(-45deg) scale(.8); } to { opacity: 1; transform: none; } }
@keyframes spin { to { transform: rotate(360deg); } }
```

### Sliding highlight (CSS)
```css
.glider {
  position: absolute; left: 0; top: 0; z-index: 0; pointer-events: none; opacity: 0; will-change: transform;
  transition: transform .5s var(--ease-out), width .5s var(--ease-out), height .5s var(--ease-out), opacity .25s var(--ease);
}
.glider.no-anim { transition: none; }

/* Segmented control */
.seg { position: relative; display: inline-flex; background: #ede4d7; border-radius: 10px; padding: 4px; gap: 4px; }
.seg button { position: relative; z-index: 1; border: 0; background: none; padding: 8px 14px; border-radius: 7px; font-weight: 600; color: var(--muted); cursor: pointer;
  transition: color .22s var(--ease), transform .18s var(--ease); }
.seg button[aria-pressed="true"] { color: var(--ink); }
.seg button:active { transform: scale(.96); transition-duration: .08s; }
.seg > .glider { background: #fff; border-radius: 7px; box-shadow: 0 1px 2px rgba(43,30,24,.08), 0 4px 12px -6px rgba(43,30,24,.22); }

/* Side menu */
.side-nav { position: relative; display: grid; gap: 2px; }
.side-nav > .glider { background: #fff; border-radius: 8px; box-shadow: inset 0 0 0 1px var(--line); }
.side-nav a { position: relative; z-index: 1; padding: 9px 12px; border-radius: 8px; color: var(--muted); font-weight: 500; }
.side-nav a.active { color: var(--ink); font-weight: 600; }
.side-nav a:active { transform: scale(.98); transition-duration: .08s; }
```

### Sliding highlight (logic)
The important parts: measure the active item's offsetLeft/Top/Width/Height, place instantly the first time, animate only when the selection changes, and re-place instantly only on a real size change.
```jsx
export function useGlider(ref, selector, dep) {
  useLayoutEffect(() => {
    const box = ref.current;
    const g = box?.querySelector(":scope > .glider");
    if (!box || !g) return;
    const place = (animate) => {
      const a = box.querySelector(selector);
      if (!a) { g.style.opacity = "0"; return; }
      if (!animate) g.classList.add("no-anim");
      g.style.opacity = "1";
      g.style.width = `${a.offsetWidth}px`;
      g.style.height = `${a.offsetHeight}px`;
      g.style.transform = `translate(${a.offsetLeft}px, ${a.offsetTop}px)`;
      if (!animate) { void g.offsetWidth; g.classList.remove("no-anim"); }
    };
    const firstTime = box.dataset.glided !== "1";
    place(!firstTime);
    box.dataset.glided = "1";
    if (firstTime && document.fonts?.ready) document.fonts.ready.then(() => place(false)); // webfonts change widths
    let last = `${box.offsetWidth}x${box.offsetHeight}`;
    const ro = typeof ResizeObserver !== "undefined" ? new ResizeObserver(() => {
      const now = `${box.offsetWidth}x${box.offsetHeight}`;
      if (now !== last) { last = now; place(false); }
    }) : null;
    ro?.observe(box);
    return () => ro?.disconnect();
  }, [dep]);
}

export function Segmented({ options, value, onChange, label }) {
  const ref = useRef(null);
  useGlider(ref, 'button[aria-pressed="true"]', value);
  return (
    <div className="seg" role="group" aria-label={label} ref={ref}>
      <span className="glider" aria-hidden="true" />
      {options.map(([k, l]) => <button type="button" key={k} aria-pressed={value === k} onClick={() => onChange(k)}>{l}</button>)}
    </div>
  );
}
```

### Pane / page enter
```jsx
const EASE_OUT = "cubic-bezier(.16, 1, .3, 1)";
export const prefersReducedMotion = () => window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;

// Eases an element in whenever `dep` changes (not on first render).
export function useEnter(ref, dep, { y = 10, duration = 520 } = {}) {
  const first = useRef(true);
  useLayoutEffect(() => {
    if (first.current) { first.current = false; return; }
    const el = ref.current;
    if (!el?.animate) return;
    const reduce = prefersReducedMotion();
    const a = el.animate(
      reduce ? [{ opacity: 0 }, { opacity: 1 }] : [{ opacity: 0, transform: `translateY(${y}px)` }, { opacity: 1, transform: "translateY(0)" }],
      { duration: reduce ? 160 : duration, easing: EASE_OUT }
    );
    return () => a.cancel();
  }, [dep]);
}
// Inner pane: useEnter(ref, sectionId, { y: 8, duration: 440 })
```

### Accordion
```jsx
export function Disclosure({ summary, children, defaultOpen = false }) {
  const [open, setOpen] = useState(defaultOpen);
  return (
    <div className={`disclosure ${open ? "open" : ""}`}>
      <button type="button" className="disclosure-btn" aria-expanded={open} onClick={() => setOpen(!open)}>
        <span>{summary}</span><span className="chev" aria-hidden="true" />
      </button>
      <div className="disclosure-panel" role="region" {...(open ? {} : { inert: "" })}>
        <div className="disclosure-inner">{children}</div>
      </div>
    </div>
  );
}
```
```css
.disclosure .chev { width: 10px; height: 10px; border-right: 2px solid currentColor; border-bottom: 2px solid currentColor; opacity: .55;
  transform: translateY(-25%) rotate(45deg); transition: transform .45s var(--ease-in-out), opacity .2s; }
.disclosure.open .chev { transform: translateY(25%) rotate(-135deg); opacity: .8; }
.disclosure-panel { display: grid; grid-template-rows: 0fr; transition: grid-template-rows .45s var(--ease-in-out); }
.disclosure.open .disclosure-panel { grid-template-rows: 1fr; }
.disclosure-inner { overflow: hidden; min-height: 0; }
.disclosure-inner > * { opacity: 0; transform: translateY(-4px); transition: opacity .25s var(--ease), transform .45s var(--ease-out); }
.disclosure.open .disclosure-inner > * { opacity: 1; transform: none; transition-delay: .1s; transition-duration: .4s, .5s; }
```

### Press feedback, entrances, overlays
```css
.btn, .chip, .seg button, .side-nav a, .icon-btn {
  transition: background-color .22s var(--ease), border-color .22s var(--ease), color .22s var(--ease), box-shadow .22s var(--ease), transform .18s var(--ease);
}
.chip:active, .seg button:active, .icon-btn:active { transform: scale(.96); transition-duration: .08s; }
.btn:active:not([disabled]) { transform: scale(.98); transition-duration: .08s; }
.card:active { transform: scale(.995); transition-duration: .1s; }

.notice { animation: soft-rise .45s var(--ease-out) both; }
.card { animation: soft-rise .6s var(--ease-out) both; }
.card:nth-child(2) { animation-delay: 60ms; } .card:nth-child(3) { animation-delay: 120ms; }
.card:nth-child(4) { animation-delay: 180ms; } .card:nth-child(5) { animation-delay: 240ms; }
.card:nth-child(n+6) { animation-delay: 300ms; }
a.card:hover { transform: translateY(-2px); box-shadow: 0 12px 28px -18px rgba(43,30,24,.3);
  transition: transform .45s var(--ease-out), box-shadow .45s var(--ease-out); }
.check-icon { animation: pop-in .45s var(--ease-out) both; }
img.avatar { opacity: 0; transition: opacity .6s var(--ease); } img.avatar.loaded { opacity: 1; }
.spinner { opacity: 0; animation: spin .8s linear infinite, soft-in .3s var(--ease) .25s forwards; }

.modal-backdrop { animation: soft-in .25s var(--ease) both; }
.modal { animation: modal-in .42s var(--ease-out) both; }
.toast { animation: toast-in .45s var(--ease-out) both; }
.toast.leaving { animation: toast-out .25s var(--ease) forwards; }
@keyframes toast-in { from { opacity: 0; transform: translate(-50%, 14px) scale(.98); } to { opacity: 1; transform: translate(-50%, 0); } }
@keyframes toast-out { to { opacity: 0; transform: translate(-50%, 8px); } }

@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after { animation-duration: .01ms !important; animation-delay: 0ms !important; animation-iteration-count: 1 !important;
    transition-duration: .01ms !important; transition-delay: 0ms !important; }
  .spinner { opacity: 1; animation: spin 1.6s linear infinite !important; }
}
```

---

## Part 3: SwiftUI equivalents (native macOS)

```swift
import SwiftUI

enum Motion {
    // The three curves, exact.
    static func ease(_ d: Double = 0.22)      -> Animation { .timingCurve(0.2, 0.7, 0.2, 1, duration: d) }
    static func easeOut(_ d: Double = 0.5)    -> Animation { .timingCurve(0.16, 1, 0.3, 1, duration: d) }
    static func easeInOut(_ d: Double = 0.45) -> Animation { .timingCurve(0.65, 0, 0.35, 1, duration: d) }

    static let glide   = easeOut(0.5)    // sliding highlight
    static let pane    = easeOut(0.44)   // settings / dashboard pane enter
    static let page    = easeOut(0.52)
    static let open    = easeInOut(0.45) // accordions, chevrons
    static let press   = Animation.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.08)
    static let release = ease(0.18)
}
```

**Sliding highlight.** Use ONE `matchedGeometryEffect` shape that only the selected item draws. Do not give each item its own background that fades.
```swift
struct GlidingTabs<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.0) { value, title in
                Button {
                    withAnimation(reduceMotion ? nil : Motion.glide) { selection = value }
                } label: {
                    Text(title)
                        .fontWeight(selection == value ? .semibold : .medium)
                        .foregroundStyle(selection == value ? .primary : .secondary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background {
                            if selection == value {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(.background)
                                    .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                                    .shadow(color: .black.opacity(0.12), radius: 6, y: 4)
                                    .matchedGeometryEffect(id: "glider", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScale(scale: 0.96))
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary))
    }
}
```
Same pattern for a sidebar (`VStack`, highlight radius 8 with a 1 px hairline stroke) and for an underline (a 1.5 px `Capsule` under the text).

**Press feedback.**
```swift
struct PressScale: ButtonStyle {
    var scale: CGFloat = 0.96   // 0.98 for wide buttons and rows, 0.995 for big cards
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(configuration.isPressed ? Motion.press : Motion.release, value: configuration.isPressed)
    }
}
```

**Pane enter** (settings sections, dashboard panes). Swap instantly, ease the new one in. No exit animation. (Two-argument `onChange` needs macOS 14; on older targets use the one-argument form.)
```swift
struct PaneEnter: ViewModifier {
    let key: AnyHashable
    var y: CGFloat = 8
    var duration: Double = 0.44
    @State private var shown = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : y)
            .onChange(of: key) { _, _ in
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { shown = false }
                withAnimation(reduceMotion ? .linear(duration: 0.16) : Motion.easeOut(duration)) { shown = true }
            }
    }
}
extension View { func paneEnter(_ key: AnyHashable, y: CGFloat = 8, duration: Double = 0.44) -> some View { modifier(PaneEnter(key: key, y: y, duration: duration)) } }
// usage: detailView(for: section).paneEnter(section)
```

**Accordion.**
```swift
@State private var open = false
VStack(alignment: .leading, spacing: 0) {
    Button { withAnimation(Motion.open) { open.toggle() } } label: {
        HStack {
            Text(title).fontWeight(.semibold)
            Spacer()
            Image(systemName: "chevron.down")
                .rotationEffect(.degrees(open ? 180 : 0))
                .opacity(open ? 0.8 : 0.55)
        }
    }.buttonStyle(PressScale(scale: 0.98))
    if open {
        content
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: -4)).animation(Motion.easeOut(0.5).delay(0.1)),
                removal: .opacity.animation(Motion.ease(0.25))))
    }
}
.clipped()
```

**Entrances and lists.** For inserted rows use `.transition(.opacity.combined(with: .offset(y: 8)))` with `Motion.easeOut(0.6)`. Stagger first-load lists by `min(index, 5) * 0.06` s.

**Completion pop.**
```swift
Image(systemName: "checkmark.circle.fill")
    .scaleEffect(done ? 1 : 0.6).opacity(done ? 1 : 0)
    .animation(.spring(response: 0.35, dampingFraction: 0.55), value: done) // close to the web version: 0.6, slight overshoot, settles at 1
```

**Popovers, sheets, toasts.** Toast in: `.transition(.opacity.combined(with: .offset(y: 14)).combined(with: .scale(scale: 0.98)))` with `Motion.easeOut(0.45)`. Toast out: opacity plus 8 px, `Motion.ease(0.25)`. Keep the system's own sheet and window animations; do not fight them.

**Reduce motion.** Read `@Environment(\.accessibilityReduceMotion)` everywhere you animate. When true, pass `nil` or `.linear(duration: 0.16)` and drop offsets, scales and rotations.

---

## Part 4: where to apply it (audit the whole app, settings included)

Go through every screen and apply the matching motion. Anything that changes state should move with one of the patterns above, and nothing should snap.

- **Any group of tabs, filters or modes** (segmented controls, view switchers like List / Board, Today / Upcoming, settings tabs at the top of a window) → sliding highlight.
- **Sidebars and settings section lists** → sliding highlight behind the active row, plus pane enter on the content on the right. The sidebar itself never animates on a section change.
- **Settings toggles and checkboxes** → native toggle animation, plus press feedback on the row. If turning a toggle on reveals extra options below it, those options open like an accordion (height eases, content fades in 100 ms later).
- **Settings rows that expand** (advanced options, "Show more", shortcuts lists) → accordion.
- **Pickers and steppers inside settings** → press feedback; changed values crossfade (200 ms `ease`) rather than jump.
- **Lists** (tasks, notes, links) → new items soft-rise in; removed items fade and collapse their height (`ease-in-out`, 450 ms) so the rows below slide up instead of jumping.
- **Checking off a task** → completion pop on the check, then the row eases out.
- **Empty states and notices** → soft rise on appear.
- **Popovers, panels and floating windows opening** → soft rise or modal-in (12 px, scale 0.98, 420 ms `ease-out`).
- **Toasts and confirmations** ("Saved", "Copied", "Undo") → toast in and out.
- **Loading** → spinner only after 250 ms.
- **Images, favicons and link previews** → fade in when loaded.
- **Hover on rows and cards** (macOS pointer) → colour change 200 ms; cards lift 2 px.
- **Icon swaps** (pin and unpin, play and pause, expand and collapse) → icon-swap.

## Pitfalls we already hit (avoid them)

1. **Highlight jumping instead of sliding.** It happened because a resize observer's first callback (and the web-font load) re-placed the highlight without animation in the same frame as the selection change, which cancelled the slide. Only re-place instantly when the container's size actually changed, and only wait on fonts the first time.
2. **Highlight sliding in from the corner on first load.** Place it instantly the first time.
3. **Every tab fading its own background.** That reads as a blink, not a glide. There must be one shared shape that moves.
4. **Animating the whole page when only a pane changed.** Animate only what changed.
5. **Defaults sneaking in.** `ease-in-out` 0.3 s or a default spring feels generic. Use the exact curves above.
6. **Forgetting reduce motion.**
