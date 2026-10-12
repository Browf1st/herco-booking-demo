// PLACEHOLDER DATA: every value in this file is sample content to replace with the shop's real details.

export type Size = 'small' | 'medium' | 'large';
export type Tier = 'basic' | 'standard' | 'pro';

export const shop = {
	name: 'Herco Detailing Garage',
	area: 'Valenzuela City, Philippines',
	facebook: 'https://www.facebook.com/',
	email: 'bookings@example.com',
	// Day numbers follow Date.getDay(), so 0 is Sunday and 3 is Wednesday.
	openDays: [3, 4, 5, 6, 0],
	openHour: 9,
	closeHour: 17,
	dailyLimit: 8,
	bookingWindowDays: 21,
	downpayment: 500,
	gcash: { name: 'SAMPLE ACCOUNT NAME', number: '0900 000 0000' },
	stats: [
		{ value: '370K', label: 'Facebook followers' },
		{ value: '1,275', label: 'Reviews' },
		{ value: '100%', label: 'Recommend' }
	]
};

// Each package switches whole features on or off, so a cheaper package needs no code removed.
export const tiers: Record<Tier, { label: string; payment: boolean; email: boolean; preview: boolean }> = {
	basic: { label: 'Basic', payment: false, email: false, preview: false },
	standard: { label: 'Standard', payment: true, email: true, preview: false },
	pro: { label: 'Pro', payment: true, email: true, preview: true }
};

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
		blurb: 'Full detail plus a deep wet-look ceramic layer.',
		prices: { small: 1499, medium: 2499, large: 3499 }
	},
	{
		id: 'ceramic-matte',
		name: 'Matte Ceramic Coating',
		blurb: 'Full detail plus a ceramic layer made for matte paint.',
		prices: { small: 1799, medium: 2799, large: 3799 }
	},
	{
		id: 'wheel-colour',
		name: 'Wheel Colour Coating',
		blurb: 'Both wheels stripped, coated in your colour and sealed.',
		prices: { small: 2500, medium: 3000, large: 3500 }
	}
];

// Shop photos live in static/photos, with relative paths so they work under any base path since all routes are top-level.
export const photos = {
	before: 'photos/bike-before.jpg',
	after: 'photos/bike-after.jpg',
	wheelSet: 'photos/wheel-set.jpg'
};

// The wheel photos are square crops of the wheel set photo, one per colour.
export const wheelColours = [
	{ id: 'purple', name: 'Purple', hex: '#5a1fb5', photo: 'photos/wheel-purple.jpg' },
	{ id: 'pink', name: 'Pink', hex: '#f2357f', photo: 'photos/wheel-pink.jpg' },
	{ id: 'blue', name: 'Blue', hex: '#1a2fd0', photo: 'photos/wheel-blue.jpg' },
	{ id: 'red', name: 'Red', hex: '#d81e1e', photo: 'photos/wheel-red.jpg' }
];

export const reviews = [
	{ name: 'Sample Rider A', text: 'Sample review. Replace with a real review from the Facebook page.' },
	{ name: 'Sample Rider B', text: 'Sample review. The bike looked better than the day it left the casa.' },
	{ name: 'Sample Rider C', text: 'Sample review. Booked a slot, dropped off on time, no waiting.' }
];

export const serviceOf = (id: string) => services.find((s) => s.id === id) ?? services[0];

export const priceOf = (b: { serviceId: string; size: Size }) => serviceOf(b.serviceId).prices[b.size];

export const peso = (n: number) => `PHP ${n.toLocaleString('en-PH')}`;
