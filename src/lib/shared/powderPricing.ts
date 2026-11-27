import type { PowderCategory, PowderSize } from './bookingCatalog';

export type PowderColorEntry = {id:string;name:string;category:PowderCategory;photoPath:string|null;quoteOnly:boolean;enabled?:boolean;pricesBySize?:Partial<Record<PowderSize,number>>};
export type PowderException = {id:string;service:'wheel-colour'|'ceramic';bikeKey:string;finish:string;fromFinish?:string;priceCentavos?:number;quoteOnly:boolean;enabled:boolean;note:string};
export type PowderModel = {
 categories: PowderCategory[];
 baseTable: Record<PowderCategory,Record<PowderSize,number|null>>;
 colorEntries: PowderColorEntry[];
 exceptions: PowderException[];
 bikeTiers: Record<string,PowderSize>;
};

const key = (text: string) => text.trim().toLowerCase();

/** Turns a saved wheel size (new size key or an old label such as "17 inches (Raider / Sniper only)") into a size key. */
export function powderSizeFromValue(text: string | undefined): PowderSize | '' {
 const value = (text ?? '').trim();
 if (value === '10-14' || value.startsWith('10')) return '10-14';
 if (value === '17' || value.startsWith('17')) return '17';
 if (value === 'big-bike' || /^big bike/i.test(value)) return 'big-bike';
 if (value === 'not-sure' || /^not sure$/i.test(value)) return 'not-sure';
 return '';
}

/** The colour the server would match for this text: by id or by name, ignoring case. */
export function findColorEntry(model: PowderModel | undefined, finish: string): PowderColorEntry | undefined {
 const wanted = key(finish);
 if (!model || !wanted) return undefined;
 return model.colorEntries.find(entry => key(entry.id) === wanted || key(entry.name) === wanted);
}

/** The size the shop prices this bike at: its tier when the shop set one, else the size the customer picked. */
export function effectivePowderSize(model: PowderModel, bike: string, picked: PowderSize | ''): PowderSize | '' {
 return model.bikeTiers[key(bike)] ?? picked;
}

/**
 * Mirrors the server's wheel price: exception, then the colour's own price for the size,
 * then the category base price. Returns pesos, or undefined when the shop must quote.
 * This is only an estimate. The server always prices the booking again.
 */
export function wheelRate(model: PowderModel, input: { bike: string; size: PowderSize | ''; finish: string; prismatic?: boolean }): number | undefined {
 const wanted = key(input.finish);
 if (!wanted) return undefined;
 const bike = key(input.bike);
 const size: PowderSize = effectivePowderSize(model, input.bike, input.size) || 'not-sure';
 const entry = findColorEntry(model, input.finish);
 const names = [wanted, key(entry?.id ?? ''), key(entry?.name ?? '')];
 const exception = model.exceptions
  .filter(rule => rule.enabled && (rule.service ?? 'wheel-colour') === 'wheel-colour' && rule.bikeKey === bike && names.includes(key(rule.finish)) && !rule.fromFinish)
  .at(0);
 if (exception) return exception.quoteOnly || exception.priceCentavos === undefined ? undefined : Math.round(exception.priceCentavos) / 100;
 if (!entry || entry.category === 'custom' || entry.quoteOnly || size === 'not-sure') return undefined;
 const category: PowderCategory = input.prismatic ? 'luminous-prismatic' : entry.category;
 return entry.pricesBySize?.[size] ?? model.baseTable[category]?.[size] ?? undefined;
}
