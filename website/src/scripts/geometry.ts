// The arrangement geometry from FlipsideCore and the app's diagrams, ported so the page draws
// arrangements exactly the way the app does. Shared by the server render and the browser.

export type Edge = "left" | "right" | "above" | "below";

/** Where the satellite (the MacBook) sits against the anchor (the monitor). `align` is the
 *  satellite's position along the shared edge as a fraction of the room it has to slide. */
export interface Placement {
  edge: Edge;
  align: number;
}

export interface Size {
  w: number;
  h: number;
}

export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface Arrangement {
  placement: Placement;
  anchor: Size;
  satellite: Size;
}

export const MONITOR: Size = { w: 2560, h: 1440 };
export const MACBOOK: Size = { w: 1512, h: 982 };

/** The layouts the app ships with: beside and a little low, and tucked underneath. */
export const LAYOUTS: Placement[] = [
  { edge: "left", align: 48 / 69 },
  { edge: "below", align: 86 / 157 },
];

export const arrangement = (placement: Placement, anchor = MONITOR, satellite = MACBOOK): Arrangement => ({
  placement,
  anchor,
  satellite,
});

export const isHorizontal = (edge: Edge) => edge === "left" || edge === "right";

export const title = (placement: Placement) => (isHorizontal(placement.edge) ? "Side by side" : "Stacked");

export function detail(placement: Placement, label = "MacBook") {
  switch (placement.edge) {
    case "left":
      return `${label} on the left`;
    case "right":
      return `${label} on the right`;
    case "above":
      return `${label} above`;
    case "below":
      return `${label} below`;
  }
}

/** Room the satellite has to slide along the shared edge. */
export const room = (edge: Edge, anchor: Size, satellite: Size) =>
  isHorizontal(edge) ? anchor.h - satellite.h : anchor.w - satellite.w;

/** The satellite's origin relative to the anchor's, in points with y pointing down. */
export function offset({ edge, align }: Placement, anchor: Size, satellite: Size) {
  const slide = Math.round(room(edge, anchor, satellite) * align);
  switch (edge) {
    case "left":
      return { x: -satellite.w, y: slide };
    case "right":
      return { x: anchor.w, y: slide };
    case "above":
      return { x: slide, y: -satellite.h };
    case "below":
      return { x: slide, y: anchor.h };
  }
}

function bounds({ placement, anchor, satellite }: Arrangement) {
  const o = offset(placement, anchor, satellite);
  return {
    anchor: { x: 0, y: 0, w: anchor.w, h: anchor.h },
    satellite: { x: o.x, y: o.y, w: satellite.w, h: satellite.h },
  };
}

function union(a: Rect, b: Rect): Rect {
  const x = Math.min(a.x, b.x);
  const y = Math.min(a.y, b.y);
  return { x, y, w: Math.max(a.x + a.w, b.x + b.w) - x, h: Math.max(a.y + a.h, b.y + b.h) - y };
}

export interface Fit {
  scale: number;
  dx: number;
  dy: number;
}

/** Scales so every arrangement in `scaleWith` would fit `box`, keeping displays one size from
 *  one picture to the next, then centres this arrangement in the box. */
export function fit(arr: Arrangement, box: Size, scaleWith: Arrangement[] = []): Fit {
  const unionOf = (a: Arrangement) => {
    const b = bounds(a);
    return union(b.anchor, b.satellite);
  };
  const scale = Math.min(...[arr, ...scaleWith].map((a) => Math.min(box.w / unionOf(a).w, box.h / unionOf(a).h)));
  const u = unionOf(arr);
  return {
    scale,
    dx: (box.w - u.w * scale) / 2 - u.x * scale,
    dy: (box.h - u.h * scale) / 2 - u.y * scale,
  };
}

/** Maps a rect in points (relative to the anchor's origin) into the box. Displays touch in the
 *  real arrangement; `inset` leaves a sliver of air between them. */
export const place = (r: Rect, f: Fit, inset = 1): Rect => ({
  x: r.x * f.scale + f.dx + inset,
  y: r.y * f.scale + f.dy + inset,
  w: r.w * f.scale - inset * 2,
  h: r.h * f.scale - inset * 2,
});

export function layout(arr: Arrangement, box: Size, scaleWith: Arrangement[] = [], inset = 1) {
  const f = fit(arr, box, scaleWith);
  const b = bounds(arr);
  return { anchor: place(b.anchor, f, inset), satellite: place(b.satellite, f, inset), fit: f };
}

/** The smallest box, in points, that holds every arrangement in `all` at one scale. */
export function extent(all: Arrangement[]): Size {
  const unions = all.map((a) => {
    const b = bounds(a);
    return union(b.anchor, b.satellite);
  });
  return { w: Math.max(...unions.map((u) => u.w)), h: Math.max(...unions.map((u) => u.h)) };
}

const pct = (n: number) => `${+(n * 100).toFixed(4)}%`;

/** A rect as CSS percentages of `box`, so a diagram can resize without being redrawn. */
export const percent = (r: Rect, box: Size) => ({
  left: pct(r.x / box.w),
  top: pct(r.y / box.h),
  width: pct(r.w / box.w),
  height: pct(r.h / box.h),
});

// The menu bar icon (StatusGlyph.swift): a solid monitor and an outlined laptop.

export const GLYPH = { w: 23, h: 16, monitor: { w: 13, h: 8 }, laptop: { w: 7.5, h: 5 }, gap: 1.5 };

export interface GlyphFrames {
  monitor: Rect;
  laptop: Rect;
}

export function glyphFrames(placement: Placement): GlyphFrames {
  const clamped = { edge: placement.edge, align: Math.min(Math.max(placement.align, 0), 1) };
  const o = offset(clamped, GLYPH.monitor, GLYPH.laptop);
  if (placement.edge === "left") o.x -= GLYPH.gap;
  if (placement.edge === "right") o.x += GLYPH.gap;
  if (placement.edge === "above") o.y -= GLYPH.gap;
  if (placement.edge === "below") o.y += GLYPH.gap;

  const monitor = { x: 0, y: 0, ...GLYPH.monitor };
  const laptop = { x: o.x, y: o.y, ...GLYPH.laptop };
  const u = union(monitor, laptop);
  // Half points keep the edges crisp on Retina displays.
  const dx = Math.round(((GLYPH.w - u.w) / 2 - u.x) * 2) / 2;
  const dy = Math.round(((GLYPH.h - u.h) / 2 - u.y) * 2) / 2;
  return {
    monitor: { ...monitor, x: monitor.x + dx, y: monitor.y + dy },
    laptop: { ...laptop, x: laptop.x + dx, y: laptop.y + dy },
  };
}

const mix = (a: Rect, b: Rect, t: number): Rect => ({
  x: a.x + (b.x - a.x) * t,
  y: a.y + (b.y - a.y) * t,
  w: a.w + (b.w - a.w) * t,
  h: a.h + (b.h - a.h) * t,
});

export const mixGlyph = (a: GlyphFrames, b: GlyphFrames, t: number): GlyphFrames => ({
  monitor: mix(a.monitor, b.monitor, t),
  laptop: mix(a.laptop, b.laptop, t),
});

const attrs = (r: Rect, inset: number) => ({
  x: +(r.x + inset).toFixed(3),
  y: +(r.y + inset).toFixed(3),
  width: +(r.w - inset * 2).toFixed(3),
  height: +(r.h - inset * 2).toFixed(3),
});

/** SVG rect attributes for each part of the glyph. Mid-morph the laptop passes behind the
 *  monitor's corner, so a gap is cut around the monitor to keep the shapes from merging. */
export const glyphParts = (f: GlyphFrames) => ({
  laptop: attrs(f.laptop, 0.6),
  cut: attrs(f.monitor, -GLYPH.gap),
  monitor: attrs(f.monitor, 0),
});
