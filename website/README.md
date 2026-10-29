# Flipside website

Astro site for the Flipside landing page, flipside.itsneel.com.

## Development

Run commands from this directory. Astro needs Node 22.12 or later; with an older Node, add
`--bun` to run it on Bun's runtime instead.

```sh
bun install
bun --bun run dev
bun --bun run check
bun --bun run build
```

## How it fits together

- `src/scripts/geometry.ts` is a port of the app's arrangement maths (FlipsideCore and the
  panel's diagrams), so the page draws layouts exactly as the app does. The server render uses it
  to place every diagram before any script runs; `src/scripts/site.ts` uses it to animate flips
  with the app's spring.
- The `/install` route serves the repository's current `scripts/install.sh`, and the version in
  the install section is read from `Resources/Info.plist`, so neither can drift from the app.

## Deployment

The Vercel project `flipside` is connected to the GitHub repository, so every push to `main`
deploys to flipside.itsneel.com. It builds from the repository root with `vercel.json`, and
`.vercelignore` limits the upload to this folder plus the two files it reads. To deploy by hand
from a checkout, run `bunx vercel@latest deploy --prod` in the repository root.
