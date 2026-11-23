// Home page Showcase strip: 4 photos picked from powder-showcase.ts (kept separate so Home
// does not download the full 91-photo list). A test checks these slugs and the total stay in sync.
export const showcaseTotal = 91;

export const showcaseHome: readonly { slug: string; title: string; alt: string }[] = [
	{ slug: 'black-and-red-two-tone-wheel', title: 'Black and red two-tone wheel', alt: 'Gloss black wheel with red powder coated spoke sections' },
	{ slug: 'fire-aqua-teal-on-the-bike', title: 'Fire Aqua Teal on the bike', alt: 'White scooter with fire aqua teal wheels' },
	{ slug: 'fire-pink', title: 'Fire Pink', alt: 'Wheel powder coated in glossy fire pink' },
	{ slug: 'aqua-teal-cvt-covers', title: 'Aqua Teal CVT covers', alt: 'Two CVT covers in aqua teal' }
];
