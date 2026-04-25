// @ts-check
import { defineConfig } from "astro/config";

import starlight from "@astrojs/starlight";
import sitemap from "@astrojs/sitemap";

// https://astro.build/config
export default defineConfig({
  site: "https://www.inferbridge.dev",
  integrations: [
    sitemap(),
    starlight({
      title: "InferBridge Docs",
      description:
        "Drop-in OpenAI-compatible gateway for OpenAI, Anthropic, Together, Sarvam, and self-hosted models.",
      // Landing page at / is served by src/pages/index.astro; Starlight
      // owns only /docs/* routes via content nested under src/content/docs/docs/.
      logo: {
        src: "./public/favicon.svg",
        alt: "InferBridge",
        replacesTitle: false,
      },
      customCss: ["./src/styles/starlight-theme.css"],
      favicon: "/favicon.svg",
      head: [
        {
          tag: "link",
          attrs: {
            rel: "apple-touch-icon",
            href: "/apple-touch-icon.png",
          },
        },
      ],
      social: [
        {
          icon: "github",
          label: "GitHub",
          href: "https://github.com/Yogeshshirsath01/InferBridge",
        },
      ],
      sidebar: [
        {
          label: "Overview",
          link: "/docs/",
        },
        {
          label: "Getting started",
          link: "/docs/getting-started/",
        },
        {
          label: "Migrating from OpenAI",
          link: "/docs/migration/",
        },
        {
          label: "API reference",
          collapsed: true,
          items: [
            { label: "Authentication", link: "/docs/api/authentication/" },
            { label: "Chat completions", link: "/docs/api/chat-completions/" },
            { label: "Users & provider keys", link: "/docs/api/keys/" },
            { label: "Stats", link: "/docs/api/stats/" },
            { label: "Logs", link: "/docs/api/logs/" },
            { label: "Audit export", link: "/docs/api/audit/" },
            { label: "Errors", link: "/docs/api/errors/" },
          ],
        },
        {
          label: "Changelog",
          link: "/docs/changelog/",
        },
      ],
    }),
  ],
});
