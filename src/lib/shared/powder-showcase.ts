// Showcase powder coating gallery: the shop's own photos (owner folder, 2026-11-20).
// Kept out of config.ts so only the Showcase page downloads this list.
// Each has photos/powder/<slug>-480.webp and -800.webp, cropped 3:4 with camera data removed.
// `finish` (when set) is passed to the booking form as the requested colour.
export const powderShowcase: readonly { slug: string; title: string; finish?: string; alt: string }[] = [
	{ slug: 'luminous-blue-two-tone', title: 'Luminous Blue (two tone)', finish: 'Luminous Blue (two tone)', alt: 'Motorcycle wheel powder coated in two-tone luminous blue' },
	{ slug: 'fire-blue-cvt-cover', title: 'Fire Blue', finish: 'Fire Blue', alt: 'CVT cover powder coated in glossy fire blue' },
	{ slug: 'high-gloss-black-topcoat', title: 'High gloss black + topcoat', finish: 'High gloss black (+topcoat)', alt: 'Motorcycle wheel in high gloss black with a clear topcoat' },
	{ slug: 'red-black-two-tone-wheels', title: 'Red and black two-tone', finish: 'Red and black two-tone', alt: 'Pair of motorcycle wheels in gloss black with red spoke accents' },
	{ slug: 'gloss-black-wheels', title: 'Custom gloss black', finish: 'Gloss black', alt: 'Custom motorcycle wheel in gloss black' },
	{ slug: 'black-cvt-covers', title: 'Black CVT covers', alt: 'Two gloss black CVT covers, one with a red vent and one with a silver vent' },
	{ slug: 'red-brackets', title: 'Red brackets and covers', alt: 'Motorcycle brackets and covers powder coated in red and black' },
	{ slug: 'purple-spring', title: 'Purple spring', alt: 'Suspension spring powder coated in glossy purple' },
	{ slug: 'red-wheels-scooter', title: 'Red wheel accents', alt: 'Red scooter with red powder coated wheel accents' },
	{ slug: 'blue-violet-scooter', title: 'Blue-violet scooter', alt: 'Scooter finished in blue-violet with grey wheels' }
];

export const powderConcept = {
	photo: 'photos/powder/herco-concept-800.webp',
	small: 'photos/powder/herco-concept-480.webp',
	alt: 'HERCO Concept poster: a red and black two-tone wheel. Revive your ride with a flawless fusion of different colors.'
} as const;
