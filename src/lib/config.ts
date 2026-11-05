// Visit details come from the supplied HERCO site. Booking settings and prices are demo data.

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
	email: 'bookings@example.com',
	// Day numbers follow Date.getDay(), so 0 is Sunday and 3 is Wednesday.
	openDays: [3, 4, 5, 6, 0],
	openHour: 9,
	closeHour: 17,
	dailyLimit: 8,
	bookingWindowDays: 21,
	downpayment: 500,
	gcash: { name: 'SAMPLE ACCOUNT NAME', number: '0900 000 0000' }
};

export const proFeatures = { payment: true, email: true, preview: true } as const;

export const sizes: Record<Size, string> = {
	small: 'Scooter or underbone',
	medium: 'Sport or naked, up to 400cc',
	large: 'Big bike, above 400cc'
};

export const services = [
	{
		id: 'wash',
		name: 'Premium Wash',
		blurb: 'Foam wash, wheel and chain clean, hand dry.',
		prices: { small: 250, medium: 350, large: 450 }
	},
	{
		id: 'detail',
		name: 'Full Detail',
		blurb: 'Deep clean, decontamination and machine polish.',
		prices: { small: 600, medium: 800, large: 1000 }
	},
	{
		id: 'ceramic-glossy',
		name: 'Glossy Ceramic Coating',
		blurb: 'Ceramic coating for suitable glossy painted panels.',
		prices: { small: 1499, medium: 2499, large: 3499 }
	},
	{
		id: 'ceramic-matte',
		name: 'Matte Ceramic Coating',
		blurb: 'Ceramic coating for suitable matte painted panels.',
		prices: { small: 1799, medium: 2799, large: 3799 }
	},
	{
		id: 'wheel-colour',
		name: 'Powder Coating',
		blurb: 'Choose a colour or finish for wheels or other suitable metal parts.',
		prices: { small: 2500, medium: 3000, large: 3500 }
	}
];

export const bookableServices = services.filter(({ id }) => id !== 'wash' && id !== 'detail');

// Shop photos live in static/photos, with relative paths so they work under any base path since all routes are top-level.
export const photos = {
	logo: 'photos/logo.png',
	hero: 'photos/herco-cruiser.png',
	ceramic: 'photos/ceramic-application.jpg',
	powder: 'photos/herco-red-wheels.jpg',
	before: 'photos/bike-before.jpg',
	after: 'photos/bike-after.jpg',
	wheelSet: 'photos/wheel-set.jpg'
} as const;

// The wheel photos are square crops of the wheel set photo, one per colour.
export const wheelColours = [
	{ id: 'purple', name: 'Purple', hex: '#5a1fb5', photo: 'photos/wheel-purple.jpg' },
	{ id: 'pink', name: 'Pink', hex: '#f2357f', photo: 'photos/wheel-pink.jpg' },
	{ id: 'blue', name: 'Blue', hex: '#1a2fd0', photo: 'photos/wheel-blue.jpg' },
	{ id: 'red', name: 'Red', hex: '#d81e1e', photo: 'photos/wheel-red.jpg' }
];

export const serviceOf = (id: string) => services.find((s) => s.id === id) ?? services[0];

export const priceOf = (b: { serviceId: string; size: Size }) => serviceOf(b.serviceId).prices[b.size];

export const peso = (n: number) => `PHP ${n.toLocaleString('en-PH')}`;

// Reward tiers transcribed from the HERCO Rewards Program poster supplied by the user.
export const rewardProgram = [
	{ points: 1000, name: 'Free T-shirt' },
	{ points: 1500, name: 'Free Graphene Seal' },
	{ points: 2000, name: 'Free powder coating', scope: 'Small parts' },
	{ points: 3000, name: 'Free buffing', scope: 'Full unit' },
	{ points: 4000, name: 'Free ceramic coating' },
	{ points: 5000, name: 'Free powder coating', scope: 'Mags' }
];

export const demoFans = [
	{ name: 'Marco Santos', points: 1280 },
	{ name: 'Andrea Reyes', points: 960 },
	{ name: 'Jolo Cruz', points: 740 },
	{ name: 'Nicole Garcia', points: 520 },
	{ name: 'Paolo Mendoza', points: 310 },
	{ name: 'Trisha Ramos', points: 150 }
];
