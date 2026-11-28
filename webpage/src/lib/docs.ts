import { type CollectionEntry, getCollection } from "astro:content";

export type Doc = CollectionEntry<"docs">;

// the sidebar's sections, in reading order; a page belongs to the one that matches its id
const SECTIONS: { label: string; match: (id: string) => boolean }[] = [
  { label: "Guides", match: (id) => id.startsWith("guides/") },
  { label: "Charts", match: (id) => id.startsWith("charts/") },
];

/** How a page is named in the sidebar and in the previous and next links */
export const navLabel = (title: string): string => title;

/** A docs page's URL under the site's base */
export const docHref = (id: string): string => `${import.meta.env.BASE_URL}/docs/${id}/`.replace(/\/+/g, "/");

const byOrder = (a: Doc, b: Doc) =>
  (a.data.order ?? 99) - (b.data.order ?? 99) || a.data.title.localeCompare(b.data.title);

/** The sidebar's sections with their pages */
export async function docSections() {
  const docs = await getCollection("docs");
  return SECTIONS.map((section) => ({
    label: section.label,
    items: docs.filter((d) => section.match(d.id)).sort(byOrder),
  })).filter((section) => section.items.length > 0);
}

/** The pages either side of one, in the sidebar's order */
export async function neighbours(id: string): Promise<{ prev?: Doc; next?: Doc }> {
  const pages = (await docSections()).flatMap((section) => section.items);
  const i = pages.findIndex((d) => d.id === id);
  return i < 0 ? {} : { prev: pages[i - 1], next: pages[i + 1] };
}
