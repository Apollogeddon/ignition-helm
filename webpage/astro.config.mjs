// @ts-check

import mdx from "@astrojs/mdx";
import sitemap from "@astrojs/sitemap";
import { defineConfig } from "astro/config";
import mermaid from "astro-mermaid";

// https://astro.build/config
export default defineConfig({
  site: "https://apollogeddon.github.io",
  base: "/ignition-helm",
  integrations: [
    mdx(),
    sitemap(),
    mermaid({
      // Mermaid sizes each label in this font, so it must be the one the page draws them in
      mermaidConfig: { fontFamily: '"Inter", system-ui, sans-serif' },
    }),
  ],
  markdown: {
    // both themes are written into each block; custom.css shows the one the page's data-theme picks
    shikiConfig: { themes: { light: "github-light", dark: "github-dark" } },
  },
});
