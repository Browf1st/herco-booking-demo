import { powderSizeFromValue, wheelRate, type PowderModel } from './powderPricing.ts';

export const ceramicModels = {
 1799: ['Yamaha Mio Gravis', 'Suzuki Skydrive Sports', 'Yamaha Mio Soul', 'Honda Click125', 'Yamaha Sniper 155', 'Yamaha Mio Gear', 'Yamaha NMAX', 'Yamaha Aerox', 'Suzuki Raider R150', 'Suzuki Burgman Street', 'Samurai 155', 'Honda Wave RSX'],
 1999: ['Honda Rebel', 'Honda AirBlade160', 'Honda ADV150', 'Honda ADV160', 'Honda Giorno+', 'Yamaha Mio Fazzio', 'Honda PCX150', 'Honda PCX160', 'Kawasaki Dominar 400', 'Honda Click160', 'Kymco Like 150i', 'Suzuki Gixxer 155', 'Suzuki Gixxer 250'],
 2499: ['Vespa Primavera 150', 'Yamaha XMAX', 'Kymco Xciting', 'Bristol']
};

export const ceramicAddons = {
 'Matte to Glossy': [399, 499],
 'Inner coating': [399, 499],
 'Graphene coating': [399, 499],
 'Mags coating': [299, 299],
 'Helmet coating': [299, 299],
 'K3 bracket / crashguard removal': [199, 199],
 'Decals removal': [99, 499]
} as const;

export const ceramicTierNames = {
 1799: 'Standard / Underbone', 1999: 'Mid-Range / Maxi', 2499: 'Big Bike / Premium'
};
type CeramicTier = keyof typeof ceramicModels;
type CeramicAddon = keyof typeof ceramicAddons;
export const listedCeramicAddons = ['Matte to Glossy', 'Inner coating', 'Graphene coating'] as const;
export type CeramicCatalogPricing = {
 tiers: Record<CeramicTier, number>;
 addons: Record<CeramicAddon, [number, number]>;
 listedAddons: Record<typeof listedCeramicAddons[number], number>;
 premiumGloss: number;
};
export const defaultCeramicCatalogPricing: CeramicCatalogPricing = {
 tiers: { 1799: 1799, 1999: 1999, 2499: 2499 },
 addons: Object.fromEntries(Object.entries(ceramicAddons).map(([name, range]) => [name, [...range]])) as CeramicCatalogPricing['addons'],
 listedAddons: { 'Matte to Glossy': 499, 'Inner coating': 499, 'Graphene coating': 499 },
 premiumGloss: 999
};

export const powderParts = {
 'Swingarm': [799, 999],
 'Handlebar / grab bar': [799, 999],
 'Foot pegs': [399, 399],
 'Brake lever': [299, 399],
 'Radiator cover / housing': [799, 799],
 'Muffler cover': [499, 499],
 'Gear cover': [999, 999],
 'Side stand': [499, 499],
 'Center stand': [999, 999],
 'Caliper': [799, 1499],
 'Shock springs (pair)': [799, 1200],
 'Front shocks (pair)': [799, 799],
 'Crankcase': [999, 1299],
 'Crankcase (custom / two-tone)': [1700, 1700]
} as const;

export const powderCategories = ['basic', 'special', 'luminous-prismatic', 'custom'] as const;
export type PowderCategory = (typeof powderCategories)[number];
export const powderCategoryLabels: Record<PowderCategory, string> = {
 basic: 'Basic', special: 'Special', 'luminous-prismatic': 'Luminous / Prismatic', custom: 'Custom'
};
export const powderSizes = ['10-14', '17', 'big-bike', 'not-sure'] as const;
export type PowderSize = (typeof powderSizes)[number];
export const powderSizeLabels: Record<PowderSize, string> = {
 '10-14': '10–14 in', '17': '15–17 in', 'big-bike': 'Big bike', 'not-sure': 'Not sure'
};
/** Sizes that can carry a price (Not sure is always a quote). */
export const pricedPowderSizes = ['10-14', '17', 'big-bike'] as const;

export const wheels = 'Wheels / mags';
export const customNoteLimit = 300;
export const wheelExtras = ['Aftermarket mags', 'Previously powder-coated mags', 'Protective top coat'];

export type CatalogOptions = {
 ceramicAddons: string[];
 /** A size key ('10-14', '17', 'big-bike', 'not-sure'). Old bookings may hold an older label. */
 wheelType: string;
 powderCategory: PowderCategory | '';
 colorId: string;
 customNote: string;
 /** Old bookings only. The booking screen no longer sets it. */
 prismatic: boolean;
 wheelExtras: string[];
 bigBike: boolean;
 otherBigBike?: boolean;
 pcx2026?: boolean;
};

export function createCatalogOptions(): CatalogOptions {
 return { ceramicAddons: [], wheelType: '', powderCategory: '', colorId: '', customNote: '', prismatic: false, wheelExtras: [], bigBike: false, otherBigBike: false };
}

type Range = readonly [number, number];
export function ceramicTier(bike: string, bigBike: boolean): CeramicTier | undefined {
 const model = bike.split(' — ')[0];
 if (!model.trim()) return bigBike ? 2499 : undefined;
 const listed = Object.entries(ceramicModels).find(([, models]) => models.includes(model));
 return listed ? Number(listed[0]) as CeramicTier : bigBike ? 2499 : undefined;
}

export function catalogItems(
 selection: { ceramic: boolean; powder: boolean; powderParts: string[]; finish: string },
 options: CatalogOptions,
 bike: string,
 year?: number,
 pricing = defaultCeramicCatalogPricing,
 powderModel?: PowderModel
) {
 const items = new Map<string, Range | undefined>();
 const tier = options.otherBigBike ? 2499 : ceramicTier(bike, options.bigBike);
 const base = tier === undefined ? undefined : pricing.tiers[tier];
 if (selection.ceramic) {
  items.set('Ceramic coating', base === undefined ? undefined : [base, base]);
  for (const addon of options.ceramicAddons) {
   if (!Object.hasOwn(ceramicAddons, addon)) continue;
   const pcxGloss = addon === 'Matte to Glossy' && /^Honda PCX/i.test(bike);
   const premium = addon === 'Matte to Glossy' && (tier === 2499 || (pcxGloss && (year === 2026 || (year === undefined && options.pcx2026))));
   const listedRate = pricing.listedAddons[addon as keyof CeramicCatalogPricing['listedAddons']];
   const gloss = pricing.listedAddons['Matte to Glossy'];
   items.set(addon, premium ? [pricing.premiumGloss, pricing.premiumGloss]
    : pcxGloss && year === undefined ? [gloss, pricing.premiumGloss]
    : tier !== undefined && listedRate !== undefined ? [listedRate, listedRate]
    : pricing.addons[addon as CeramicAddon]);
  }
 }
 if (selection.powder) {
  const color = selection.finish.trim();
  const suffix = color ? ' · ' + color : '';
  for (const part of selection.powderParts) {
   if (part === wheels) {
    const size = powderSizeFromValue(options.wheelType);
    const rate = powderModel ? wheelRate(powderModel, { bike, size, finish: selection.finish, prismatic: options.prismatic }) : undefined;
    items.set(wheels + (size ? ' · ' + powderSizeLabels[size] : '') + suffix, rate === undefined ? undefined : [rate, rate]);
    for (const extra of options.wheelExtras) {
     if (wheelExtras.includes(extra)) items.set(extra, [499, 499]);
    }
   } else if (Object.hasOwn(powderParts, part)) {
    const largeSwingarm = part === 'Swingarm' && (options.bigBike || /Raider|Sniper/i.test(bike));
    items.set(part + suffix, largeSwingarm ? [1499, 1999] : powderParts[part as keyof typeof powderParts]);
   }
  }
 }
 return items;
}

export const powderDay = (date: string) => [0, 3, 6].includes(new Date(date + 'T00:00:00Z').getUTCDay());
