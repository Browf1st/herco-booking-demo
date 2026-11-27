import type { PowderColorEntry, PowderException, PowderModel } from './ui-catalog';

/** Bike keys and finishes are compared lowercased and trimmed, the same way the database does. */
export const normaliseKey = (text: string) => text.trim().toLowerCase();

export const newColorEntry = (): PowderColorEntry => ({
	id: crypto.randomUUID(), name: '', category: 'special', photoPath: null, quoteOnly: false, enabled: true
});

export const newException = (): PowderException => ({
	id: crypto.randomUUID(), service: 'wheel-colour', bikeKey: '', finish: '', quoteOnly: false, enabled: true, note: ''
});

/** Returns a plain-words problem the server would reject, or an empty string. */
export function powderModelProblem(model: PowderModel): string {
	const names = new Set<string>();
	for (const entry of model.colorEntries) {
		const name = normaliseKey(entry.name);
		if (!name) return 'Every colour needs a name.';
		if (names.has(name)) return `Two colours are named "${entry.name.trim()}". Colour names must be different.`;
		names.add(name);
	}
	const rules = new Set<string>();
	for (const rule of model.exceptions) {
		if (!normaliseKey(rule.bikeKey)) return 'Every exception needs a bike.';
		if (rule.service === 'wheel-colour' && !normaliseKey(rule.finish)) return 'Every wheel colour exception needs a finish.';
		const ceramic = rule.service === 'ceramic';
		const signature = [rule.service, normaliseKey(rule.bikeKey), ceramic ? '' : normaliseKey(rule.finish), ceramic ? '' : normaliseKey(rule.fromFinish ?? '')].join('|');
		if (rules.has(signature)) return `There are two exceptions for "${rule.bikeKey.trim()}" with the same finish.`;
		rules.add(signature);
	}
	return '';
}

/** Cleans a draft just before saving: trims text, lowercases keys and drops empty optional fields. */
export function cleanPowderModel(model: PowderModel): PowderModel {
	const clean: PowderModel = structuredClone(model);
	clean.colorEntries = clean.colorEntries.map((entry) => {
		const next = { ...entry, name: entry.name.trim() };
		const prices = Object.fromEntries(Object.entries(entry.pricesBySize ?? {}).filter(([, price]) => typeof price === 'number'));
		if (entry.category === 'custom') return { ...next, quoteOnly: true, pricesBySize: undefined };
		return { ...next, pricesBySize: Object.keys(prices).length ? prices : undefined };
	});
	clean.exceptions = clean.exceptions.map((rule) => {
		const next: PowderException = {
			...rule, service: rule.service ?? 'wheel-colour', bikeKey: normaliseKey(rule.bikeKey), finish: rule.finish.trim(),
			fromFinish: rule.fromFinish?.trim() || undefined, note: rule.note.trim()
		};
		if (next.service === 'ceramic') { next.finish = ''; delete next.fromFinish; }
		if (rule.quoteOnly) delete next.priceCentavos;
		return next;
	});
	clean.bikeTiers = Object.fromEntries(Object.entries(clean.bikeTiers).map(([bike, size]) => [normaliseKey(bike), size]));
	return clean;
}
