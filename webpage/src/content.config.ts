import { defineCollection, z } from "astro:content";
import { glob } from "astro/loaders";

const docs = defineCollection({
	loader: glob({ pattern: "**/*.{md,mdx}", base: "./src/content/docs" }),
	schema: z.object({
		title: z.string(),
		description: z.string().optional(),
		template: z.string().optional(),
		hero: z
			.object({
				tagline: z.string().optional(),
				image: z
					.object({
						file: z.string().optional(),
					})
					.optional(),
				actions: z
					.array(
						z.object({
							text: z.string(),
							link: z.string(),
							icon: z.string().optional(),
							variant: z.string().optional(),
						}),
					)
					.optional(),
			})
			.optional(),
	}),
});

export const collections = { docs };
