import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://flipside.itsneel.com",
  compressHTML: false,
  // Keeps the dev server's toolbar out of screenshots and the share card render.
  devToolbar: { enabled: false },
});
