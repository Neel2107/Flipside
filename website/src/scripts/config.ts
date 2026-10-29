// Diagram setups shared by the server render and the browser, so both draw the same picture.
import { LAYOUTS, MACBOOK, arrangement, extent, type Size } from "./geometry";

export const layouts = LAYOUTS.map((p) => arrangement(p));

/** The hero is drawn in points: one box that holds both layouts at one scale. */
export const HERO_BOX = extent(layouts);
export const HERO_INSET = 30;

export const CARD_BOX: Size = { w: 120, h: 70 };
export const DEMO_BOX: Size = { w: 480, h: 236 };
export const DEMO_INSET = 2;

/** External display sizes for the resolution demo, in points (the "looks like" size). */
export const RESOLUTIONS: { label: string; size: Size }[] = [
  { label: "1920 × 1080", size: { w: 1920, h: 1080 } },
  { label: "2560 × 1440", size: { w: 2560, h: 1440 } },
  { label: "3008 × 1692", size: { w: 3008, h: 1692 } },
];
export const DEFAULT_RESOLUTION = 1;

export const resolutionLayouts = RESOLUTIONS.flatMap((r) => LAYOUTS.map((p) => arrangement(p, r.size, MACBOOK)));

/** Where the pointer rests on the MacBook in the pointer demo, as a fraction of its screen. */
export const POINTER_SPOT = { x: 0.58, y: 0.4 };
