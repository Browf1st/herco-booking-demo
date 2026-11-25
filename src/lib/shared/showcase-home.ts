// Keep Home previews separate so the page does not load either full gallery list.
export const showcaseHome = [
	{
		title: 'Powder Coating',
		folder: 'showcase',
		href: '/preview?tab=powder',
		photos: [
			{ slug: 'black-and-red-two-tone-wheel', title: 'Black and red two-tone wheel', alt: 'Gloss black wheel with red powder coated spoke sections' },
			{ slug: 'fire-aqua-teal-on-the-bike', title: 'Fire Aqua Teal on the bike', alt: 'White scooter with fire aqua teal wheels' }
		]
	},
	{
		title: 'Ceramic Coating & Polish',
		folder: 'ceramic',
		href: '/preview?tab=ceramic',
		photos: [
			{ slug: 'blue-side', alt: 'Blue scooter from the side after ceramic coating' },
			{ slug: 'red-front', alt: 'Red scooter front after ceramic coating' }
		]
	}
] as const;
