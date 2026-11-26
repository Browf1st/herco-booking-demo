// Visit details come from the supplied HERCO site. Booking settings are starting defaults; live availability comes from the API.

export type Size = 'small' | 'medium' | 'large';

export const shop = {
	name: 'Herco Detailing Garage',
	area: 'Valenzuela City, Philippines',
	address: '4494 G Bamboo Street, Valenzuela 1442',
	phone: '+639936935697',
	phoneLabel: '0993 693 5697',
	facebook: 'https://www.facebook.com/profile.php?id=100085045826929',
	messenger: 'https://m.me/100085045826929',
	contactEmail: 'hercoprojects@gmail.com',
	// Day numbers follow Date.getDay(), so 0 is Sunday and 3 is Wednesday.
	openDays: [3, 4, 5, 6, 0],
	openHour: 9,
	closeHour: 17,
	dateStripDays: 21,
};

export const proFeatures = { preview: true } as const;

export const sizes: Record<Size, string> = {
	small: 'Scooter or underbone',
	medium: 'Sport or naked, up to 400cc',
	large: 'Big bike, above 400cc'
};

export const services = [
	{ id: 'ceramic', name: 'Ceramic Coating', blurb: 'For suitable painted surfaces and finishes.' },
	{
		id: 'wash',
		name: 'Premium Wash',
		blurb: 'Foam wash, wheel and chain clean, hand dry.',
	},
	{
		id: 'detail',
		name: 'Full Detail',
		blurb: 'Deep clean, decontamination and machine polish.',
	},
	{
		id: 'ceramic-glossy',
		name: 'Glossy Ceramic Coating',
		blurb: 'Ceramic coating for suitable glossy painted panels.',
	},
	{
		id: 'ceramic-matte',
		name: 'Matte Ceramic Coating',
		blurb: 'Ceramic coating for suitable matte painted panels.',
	},
	{
		id: 'wheel-colour',
		name: 'Powder Coating',
		blurb: 'Choose a colour or finish for wheels or other suitable metal parts.',
	}
];

export const bookableServices = services.filter(({ id }) => id === 'ceramic' || id === 'wheel-colour');

// Shop photos live in static/photos, with relative paths so they work under any base path since all routes are top-level.
export const photos = {
	logo: 'photos/logo.webp',
	hero: 'photos/herco-cruiser.webp',
	ceramic: 'photos/ceramic-application.webp',
	powder: 'photos/powder/fire-red-scooter-wheels-960.webp',
	powderSmall: 'photos/powder/fire-red-scooter-wheels-480.webp',
	before: 'photos/bike-before.webp',
	after: 'photos/bike-after.webp',
	wheelSet: 'photos/wheel-set.webp'
} as const;

// Real shop wheel finishes from the owner's "MAGS POWDER COAT" photos (2026-11-23).
// Each colour has square 480px and 720px crops in static/photos/colours.
export const wheelColours = [
	{ id: 'fire-red', name: 'Fire Red', hex: '#c8101e', photo: 'photos/colours/fire-red-720.webp', photoSmall: 'photos/colours/fire-red-480.webp' },
	{ id: 'fire-pink', name: 'Fire Pink', hex: '#e4196f', photo: 'photos/colours/fire-pink-720.webp', photoSmall: 'photos/colours/fire-pink-480.webp' },
	{ id: 'fire-violet', name: 'Fire Violet', hex: '#5a22d8', photo: 'photos/colours/fire-violet-720.webp', photoSmall: 'photos/colours/fire-violet-480.webp' },
	{ id: 'fire-aqua-teal', name: 'Fire Aqua Teal', hex: '#1aa6c4', photo: 'photos/colours/fire-aqua-teal-720.webp', photoSmall: 'photos/colours/fire-aqua-teal-480.webp' },
	{ id: 'fire-gold', name: 'Fire Gold', hex: '#c9a419', photo: 'photos/colours/fire-gold-720.webp', photoSmall: 'photos/colours/fire-gold-480.webp' },
	{ id: 'chrome-black', name: 'Chrome Black', hex: '#1d1d1f', photo: 'photos/colours/chrome-black-720.webp', photoSmall: 'photos/colours/chrome-black-480.webp' },
	{ id: 'high-gloss-white', name: 'High Gloss White', hex: '#f4f4f6', photo: 'photos/colours/high-gloss-white-720.webp', photoSmall: 'photos/colours/high-gloss-white-480.webp' },
	{ id: 'miko-silver', name: 'Miko Silver', hex: '#b9bcc2', photo: 'photos/colours/miko-silver-720.webp', photoSmall: 'photos/colours/miko-silver-480.webp' }
];

export const serviceOf = (id: string) => services.find((s) => s.id === id) ?? services[0];

// Reward tiers transcribed from the HERCO Rewards Program poster supplied by the user.
export const rewardProgram = [
	{ points: 1000, name: 'Free T-shirt' },
	{ points: 1500, name: 'Free Graphene Seal' },
	{ points: 2000, name: 'Free powder coating', scope: 'Small parts' },
	{ points: 3000, name: 'Free buffing', scope: 'Full unit' },
	{ points: 4000, name: 'Free ceramic coating' },
	{ points: 5000, name: 'Free powder coating', scope: 'Mags' }
];
