import {
  LAYOUTS,
  MACBOOK,
  arrangement,
  detail,
  fit,
  glyphFrames,
  glyphParts,
  isHorizontal,
  layout,
  mixGlyph,
  offset,
  percent,
  place,
  room,
  title,
  type Arrangement,
  type GlyphFrames,
  type Placement,
  type Rect,
  type Size,
} from "./geometry";
import {
  CARD_BOX,
  DEFAULT_RESOLUTION,
  DEMO_BOX,
  DEMO_INSET,
  HERO_BOX,
  HERO_INSET,
  POINTER_SPOT,
  RESOLUTIONS,
  layouts,
  resolutionLayouts,
} from "./config";

const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
const $ = <T extends Element = HTMLElement>(selector: string, root: ParentNode = document) =>
  root.querySelector(selector) as T;
const $$ = <T extends Element = HTMLElement>(selector: string, root: ParentNode = document) =>
  Array.from(root.querySelectorAll(selector)) as T[];

// Motion -----------------------------------------------------------------------------------------

/** SwiftUI's `.spring(response:dampingFraction:)` as a CSS easing, so tiles settle the way the
 *  app's do rather than on a generic curve. */
function spring(response: number, damping: number) {
  const w0 = (2 * Math.PI) / response;
  const decay = damping * w0;
  const wd = w0 * Math.sqrt(1 - damping * damping);
  const at = (t: number) => 1 - Math.exp(-decay * t) * (Math.cos(wd * t) + (decay / wd) * Math.sin(wd * t));
  const duration = Math.log((1 + decay / wd) / 0.001) / decay;
  const steps = 48;
  const points = Array.from({ length: steps + 1 }, (_, i) => (i === steps ? 1 : at((i / steps) * duration)).toFixed(4));
  const easing = CSS.supports("transition-timing-function", "linear(0, 1)")
    ? `linear(${points.join(", ")})`
    : "cubic-bezier(0.22, 1, 0.36, 1)";
  return { duration: +duration.toFixed(3), easing };
}

const SPRING = spring(0.36, 0.86);
const FOLLOW = 0.14;

interface Motion {
  x: number;
  y: number;
}

/** The displays first separate along one axis, then close in along the other, so they swing
 *  around each other's corner rather than cutting straight across it. */
const motionTo = (to: Placement): Motion => (isHorizontal(to.edge) ? { x: 0, y: FOLLOW } : { x: FOLLOW, y: 0 });

function setFrame(el: HTMLElement, r: Rect, box: Size, motion: Motion | null) {
  const { duration, easing } = SPRING;
  el.style.transition =
    motion && !reducedMotion.matches
      ? [
          `left ${duration}s ${easing} ${motion.x}s`,
          `width ${duration}s ${easing} ${motion.x}s`,
          `top ${duration}s ${easing} ${motion.y}s`,
          `height ${duration}s ${easing} ${motion.y}s`,
        ].join(", ")
      : "none";
  Object.assign(el.style, percent(r, box));
}

class Diagram {
  readonly anchor: HTMLElement;
  readonly satellite: HTMLElement;
  frames = { anchor: { x: 0, y: 0, w: 0, h: 0 }, satellite: { x: 0, y: 0, w: 0, h: 0 } };

  constructor(
    readonly root: HTMLElement,
    readonly box: Size,
    public scaleWith: Arrangement[],
    readonly inset = 1,
  ) {
    this.anchor = $("[data-tile=anchor]", root);
    this.satellite = $("[data-tile=satellite]", root);
  }

  render(arr: Arrangement, motion: Motion | null = null) {
    const frames = layout(arr, this.box, this.scaleWith, this.inset);
    setFrame(this.anchor, frames.anchor, this.box, motion);
    setFrame(this.satellite, frames.satellite, this.box, motion);
    this.frames = frames;
    return frames;
  }
}

// State --------------------------------------------------------------------------------------------

/** Who asked for the flip, which decides where (and whether) a confirmation shows. */
type Source = "shortcut" | "demo" | "quiet";
type Target = "anchor" | "satellite";

interface Flip {
  from: Placement;
  to: Placement;
  source: Source;
  target?: Target;
}

let slot = 0;
const listeners: ((flip: Flip) => void)[] = [];
const onFlip = (listener: (flip: Flip) => void) => listeners.push(listener);
const announcer = $("#announcer");

function choose(next: number, source: Source, target?: Target) {
  if (next === slot) return;
  const flip = { from: LAYOUTS[slot], to: LAYOUTS[next], source, target };
  slot = next;
  for (const listener of listeners) listener(flip);
  announcer.textContent = `${title(flip.to)}. ${detail(flip.to)}.`;
}

const flip = (source: Source, target?: Target) => choose(1 - slot, source, target);

// HUD ----------------------------------------------------------------------------------------------

class Hud {
  private readonly diagram: Diagram;
  private readonly label: HTMLElement;
  private timers: number[] = [];

  constructor(readonly el: HTMLElement) {
    this.diagram = new Diagram($(".diagram", el), { w: 148, h: 84 }, layouts);
    this.label = $("[data-hud-title]", el);
  }

  /** Shows the change on `host`, a tile (scaled to fit it) or, with nil, the viewport. */
  show(from: Placement, to: Placement, host: HTMLElement | null) {
    for (const timer of this.timers) clearTimeout(timer);
    const { el } = this;
    if (el.parentElement !== (host ?? document.body)) (host ?? document.body).append(el);
    el.dataset.mode = host ? "tile" : "viewport";
    this.label.textContent = title(to);

    if (host) {
      const width = el.offsetWidth;
      const height = el.offsetHeight;
      // Never larger than the app draws it, and with room around it on small screens.
      const scale = Math.min(1, (host.clientWidth * 0.8) / width, (host.clientHeight * 0.8) / height);
      // Lower middle, like the app, when the screen has room for that; centred when it doesn't.
      const h = host.clientHeight;
      const half = (height * scale) / 2;
      const y = h >= height * scale * 2.4 ? Math.min(h * 0.78, h - half - 10) : h / 2;
      el.style.setProperty("--hud-scale", `${scale}`);
      el.style.setProperty("--hud-y", `${y}px`);
    }

    this.diagram.render(arrangement(from));
    // Restart the fade if a flip lands while the last confirmation is still up.
    el.classList.remove("is-visible");
    void el.offsetWidth;
    el.classList.add("is-visible");
    this.timers = [
      window.setTimeout(() => this.diagram.render(arrangement(to), motionTo(to)), 120),
      window.setTimeout(() => el.classList.remove("is-visible"), 1300),
    ];
  }
}

// Hero ---------------------------------------------------------------------------------------------

const heroRoot = $("#hero");
// Centred in each layout, like the legend on the icon and the app's own diagrams.
const hero = new Diagram(heroRoot, HERO_BOX, layouts, HERO_INSET);
const heroHud = new Hud($("#hero-hud"));
const readoutTitle = $("[data-readout-title]");
const readoutDetail = $("[data-readout-detail]");
let pointerTile: Target = "anchor";
let heroInView = true;

heroRoot.addEventListener("pointermove", (event) => {
  const tile = (event.target as Element).closest<HTMLElement>("[data-tile]");
  if (tile) pointerTile = tile.dataset.tile as Target;
});
new IntersectionObserver(([entry]) => (heroInView = entry.intersectionRatio >= 0.55), {
  threshold: [0, 0.55, 1],
}).observe(heroRoot);

onFlip(({ from, to, source }) => {
  hero.render(arrangement(to), motionTo(to));
  readoutTitle.textContent = title(to);
  readoutDetail.textContent = detail(to);
  if (source !== "shortcut") return;
  // On the screen the pointer is on, like the app. When the hero is out of view, the screen
  // being looked at is the viewport.
  heroHud.show(from, to, heroInView ? (pointerTile === "anchor" ? hero.anchor : hero.satellite) : null);
});

// The keys ---------------------------------------------------------------------------------------------

const keys = $$<HTMLButtonElement>("[data-chord]");

/** Presses the keycaps one after another, the way fingers land on a chord, then flips. */
function pressChord() {
  keys.forEach((key, i) => {
    setTimeout(() => key.classList.add("is-down"), i * 45);
    setTimeout(() => key.classList.remove("is-down"), 240 + i * 20);
  });
  setTimeout(() => flip("shortcut"), reducedMotion.matches ? 0 : 150);
}

keys.forEach((key) => key.addEventListener("click", pressChord));
document.addEventListener("keydown", (event) => {
  if (event.ctrlKey && event.altKey && event.metaKey && event.code === "KeyD") {
    event.preventDefault();
    if (!event.repeat) pressChord();
  }
});
$$("[data-flip-quiet]").forEach((button) => button.addEventListener("click", () => flip("quiet")));

// The menu bar icon --------------------------------------------------------------------------------------

/** Morphs a copy of the menu bar icon from one arrangement to the next. */
class Glyph {
  private frames: GlyphFrames;
  private frame = 0;

  constructor(private readonly svg: SVGSVGElement) {
    this.frames = glyphFrames(LAYOUTS[0]);
  }

  to(placement: Placement) {
    const start = this.frames;
    const end = glyphFrames(placement);
    cancelAnimationFrame(this.frame);
    if (reducedMotion.matches) return this.draw((this.frames = end));
    const began = performance.now();
    const step = (now: number) => {
      const t = Math.min(1, (now - began) / 360);
      const eased = t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2;
      this.frames = t < 1 ? mixGlyph(start, end, eased) : end;
      this.draw(this.frames);
      if (t < 1) this.frame = requestAnimationFrame(step);
    };
    this.frame = requestAnimationFrame(step);
  }

  private draw(frames: GlyphFrames) {
    for (const [part, attrs] of Object.entries(glyphParts(frames))) {
      const rect = this.svg.querySelector(`[data-part=${part}]`)!;
      for (const [name, value] of Object.entries(attrs)) rect.setAttribute(name, `${value}`);
    }
  }
}

const glyphs = $$<SVGSVGElement>("[data-glyph]").map((svg) => new Glyph(svg));
onFlip(({ to }) => glyphs.forEach((glyph) => glyph.to(to)));

// The panel ---------------------------------------------------------------------------------------------

const cards = $$<HTMLButtonElement>(".card");
cards.forEach((card, index) => {
  new Diagram($(".diagram", card), CARD_BOX, layouts).render(layouts[index]);
  card.addEventListener("click", () => choose(index, "quiet"));
});
onFlip(() => cards.forEach((card, index) => card.setAttribute("aria-pressed", `${index === slot}`)));

// Demo: everything stays on the screen you're using ---------------------------------------------------

{
  const demo = $("#demo-flip");
  const diagram = new Diagram($(".diagram", demo), DEMO_BOX, layouts, DEMO_INSET);
  const hud = new Hud($(".hud", demo));
  const pointer = $<SVGElement>(".pointer", demo) as unknown as HTMLElement;
  const status = $("[data-pointer-status]", demo);
  const modes = $$<HTMLButtonElement>("[data-mode]", demo);
  const names: Record<Target, string> = { anchor: "monitor", satellite: "MacBook" };
  let keepsSpot = true;
  let pointerOn: Target = "satellite";

  const spotOn = (r: Rect) => ({ x: r.x + r.w * POINTER_SPOT.x, y: r.y + r.h * POINTER_SPOT.y });
  const inside = (p: { x: number; y: number }, r: Rect) => p.x >= r.x && p.x <= r.x + r.w && p.y >= r.y && p.y <= r.y + r.h;
  const movePointer = (p: { x: number; y: number }, motion: Motion | null) => {
    const { duration, easing } = SPRING;
    pointer.style.transition =
      motion && !reducedMotion.matches
        ? `left ${duration}s ${easing} ${motion.x}s, top ${duration}s ${easing} ${motion.y}s, opacity 0.3s ease`
        : "none";
    pointer.style.left = `${(p.x / DEMO_BOX.w) * 100}%`;
    pointer.style.top = `${(p.y / DEMO_BOX.h) * 100}%`;
  };

  diagram.render(arrangement(LAYOUTS[0]));
  /** Puts the pointer back on its screen, as if you'd just moved it there. */
  const reset = () => {
    pointer.classList.remove("is-lost");
    movePointer(spotOn(diagram.frames[pointerOn]), null);
    // Commit the starting spot before the next move, or the browser animates from the old one.
    void pointer.getBoundingClientRect();
    status.textContent = `On the ${names[pointerOn]}.`;
  };

  // Clicking a screen moves the pointer there and flips from it.
  $$("[data-target]", demo).forEach((button) =>
    button.addEventListener("click", () => {
      pointerOn = button.dataset.target as Target;
      flip("demo", pointerOn);
    }),
  );
  $("[data-flip-demo]", demo).addEventListener("click", () => flip("demo", pointerOn));
  modes.forEach((button) =>
    button.addEventListener("click", () => {
      keepsSpot = button.dataset.mode === "flipside";
      modes.forEach((b) => b.setAttribute("aria-checked", `${b === button}`));
      reset();
    }),
  );

  onFlip(({ from, to, source }) => {
    reset();
    const before = diagram.frames;
    const start = spotOn(before[pointerOn]);
    const after = diagram.render(arrangement(to), motionTo(to));
    // The confirmation shows on the screen the pointer was on, like the app's.
    if (source === "demo") hud.show(from, to, pointerOn === "anchor" ? diagram.anchor : diagram.satellite);

    // The monitor is the main display, so its coordinates never move: a pointer there stays put
    // with or without Flipside. Only the MacBook moves out from under it.
    if (keepsSpot || pointerOn === "anchor") {
      movePointer(spotOn(after[pointerOn]), motionTo(to));
      status.textContent = `Same spot on the ${names[pointerOn]}.`;
      return;
    }
    const moved = { x: after.anchor.x + (start.x - before.anchor.x), y: after.anchor.y + (start.y - before.anchor.y) };
    movePointer(moved, motionTo(to));
    if (inside(moved, after.satellite)) status.textContent = "Still on the MacBook, by luck.";
    else if (inside(moved, after.anchor)) status.textContent = "Jumped to the monitor.";
    else {
      pointer.classList.add("is-lost");
      status.textContent = "Lost off-screen.";
    }
  });
}

// Demo: the same shape at any resolution ------------------------------------------------------------

{
  const demo = $("#demo-scale");
  const diagram = new Diagram($(".diagram", demo), DEMO_BOX, resolutionLayouts, DEMO_INSET);
  const ghost = $(".ghost", demo);
  const options = $$<HTMLButtonElement>("[data-resolution]", demo);
  const share = $("[data-share]", demo);
  const fixedPoints = $("[data-fixed-points]", demo);
  let resolution = DEFAULT_RESOLUTION;

  const render = (motion: Motion | null) => {
    const placement = LAYOUTS[slot];
    const monitor = RESOLUTIONS[resolution].size;
    const arr = arrangement(placement, monitor);
    diagram.render(arr, motion);

    // Saved in points: the slide measured at the default resolution, kept as is.
    const reference = RESOLUTIONS[DEFAULT_RESOLUTION].size;
    const fixed = Math.round(room(placement.edge, reference, MACBOOK) * placement.align);
    const ghostPlacement = { edge: placement.edge, align: fixed / room(placement.edge, monitor, MACBOOK) };
    const o = offset(ghostPlacement, monitor, MACBOOK);
    const frame = place({ x: o.x, y: o.y, w: MACBOOK.w, h: MACBOOK.h }, fit(arr, DEMO_BOX, resolutionLayouts), DEMO_INSET);
    setFrame(ghost, frame, DEMO_BOX, motion);
    const drifted = Math.abs(fixed - Math.round(room(placement.edge, monitor, MACBOOK) * placement.align)) > 2;
    ghost.classList.toggle("is-apart", drifted);

    share.textContent = `${Math.round(placement.align * 100)}%`;
    fixedPoints.textContent = `${fixed} pt`;
  };

  options.forEach((button) =>
    button.addEventListener("click", () => {
      resolution = +button.dataset.resolution!;
      options.forEach((b) => b.setAttribute("aria-checked", `${b === button}`));
      render({ x: 0, y: 0 });
    }),
  );
  onFlip(({ to }) => render(motionTo(to)));
  render(null);
}

// Demo: the icon ---------------------------------------------------------------------------------------

{
  const demo = $("#demo-icon");
  const toggle = $<HTMLInputElement>("[data-one-display]", demo);
  toggle.addEventListener("change", () => demo.classList.toggle("is-single", toggle.checked));
}

// Segmented controls move with arrow keys, as radio groups do.
$$(".segmented").forEach((group) =>
  group.addEventListener("keydown", (event) => {
    const keys: Record<string, number> = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 };
    if (!(event.key in keys)) return;
    event.preventDefault();
    const radios = $$<HTMLButtonElement>("[role=radio]", group);
    const current = radios.findIndex((radio) => radio.getAttribute("aria-checked") === "true");
    const next = radios[(current + keys[event.key] + radios.length) % radios.length];
    next.click();
    next.focus();
  }),
);

// Copy buttons -----------------------------------------------------------------------------------------

$$<HTMLButtonElement>("[data-copy]").forEach((button) => {
  let timer = 0;
  button.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(button.dataset.copy!);
      button.textContent = "Copied";
    } catch {
      button.textContent = "Press ⌘C";
      const code = button.parentElement?.querySelector("code");
      if (code) getSelection()?.selectAllChildren(code);
    }
    button.classList.add("is-done");
    clearTimeout(timer);
    timer = window.setTimeout(() => {
      button.textContent = "Copy";
      button.classList.remove("is-done");
    }, 1600);
  });
});

document.documentElement.classList.add("is-ready");
