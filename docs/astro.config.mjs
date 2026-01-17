// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import mermaid from 'astro-mermaid';

// https://astro.build/config
export default defineConfig({
	site: 'https://apollogeddon.github.io',
	base: '/ignition-helm',
	integrations: [
		starlight({
			title: 'Ignition Helm Charts',
			// customCss: ['./src/styles/custom.css'],
			social: [
				{ icon: 'github', label: 'GitHub', href: 'https://github.com/apollogeddon/ignition-helm' },
			],
			sidebar: [
				{
					label: 'Guides',
					items: [
						{ label: 'Installation', slug: 'guides/installation' },
						{ label: 'Architecture', slug: 'guides/architecture' },
						{ label: 'Capabilities', slug: 'guides/capabilities' },
						{ label: 'Licencing', slug: 'guides/licensing' },
					],
				},
				{
					label: 'Reference',
					autogenerate: { directory: 'reference' },
				},
			],
		}),
		mermaid(),
	],
});