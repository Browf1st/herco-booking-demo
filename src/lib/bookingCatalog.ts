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

export const wheels = 'Wheels / mags';
export const wheelRates = {
 '10–14 inches': [2199, 2499],
 '17 inches (Raider / Sniper only)': [3199, 3499],
 'Big bike / sports bike': [4499, 5499]
} as const;
export const wheelExtras = ['Aftermarket mags', 'Previously powder-coated mags', 'Protective top coat'];
export const basicColors = ['Snow White', 'Graphite Black', 'Matte Black', 'Crystal Black', 'Pristine White'];
export const powderPhotos = [
 { name: 'Dry Bronze', file: 'booking-colors/dry-bronze.jpg' },
 { name: 'Pearl White', file: 'booking-colors/pearl-white.jpg' },
 { name: 'High Gloss Black', file: 'booking-colors/gloss-black.jpg' },
 { name: 'High Gloss White', file: 'booking-colors/gloss-white.jpg' },
 { name: 'Fire Blue', file: 'booking-colors/fire-blue.jpg' }
] as const;

export type CatalogOptions = {
 ceramicAddons: string[];
 wheelType: string;
 prismatic: boolean;
 wheelExtras: string[];
 bigBike: boolean;
 otherBigBike?: boolean;
 pcx2026?: boolean;
};

type Range = readonly [number, number];
export function ceramicPrice(bike: string, bigBike: boolean) {
 const model = bike.split(' — ')[0];
 if (!model.trim()) return bigBike ? 2499 : undefined;
 const listed = Object.entries(ceramicModels).find(([, models]) => models.includes(model));
 return listed ? Number(listed[0]) : bigBike ? 2499 : undefined;
}

export function catalogItems(
 selection: { ceramic: boolean; powder: boolean; powderParts: string[]; finish: string },
 options: CatalogOptions,
 bike: string,
 year?: number
) {
 const items = new Map<string, Range | undefined>();
 const base = options.otherBigBike ? 2499 : ceramicPrice(bike, options.bigBike);
 if (selection.ceramic) {
  items.set('Ceramic coating', base === undefined ? undefined : [base, base]);
  for (const addon of options.ceramicAddons) {
   if (!Object.hasOwn(ceramicAddons, addon)) continue;
   const pcxGloss = addon === 'Matte to Glossy' && /^Honda PCX/i.test(bike);
   const premium = addon === 'Matte to Glossy' && (base === 2499 || (pcxGloss && (year === 2026 || (year === undefined && options.pcx2026))));
   const fixed499 = (base === 1799 || base === 1999 || base === 2499) && ['Matte to Glossy', 'Inner coating', 'Graphene coating'].includes(addon);
   items.set(addon, premium ? [999, 999] : pcxGloss && year === undefined ? [499, 999] : fixed499 ? [499, 499] : ceramicAddons[addon as keyof typeof ceramicAddons]);
  }
 }
 if (selection.powder) {
  const color = selection.finish.trim();
  const suffix = color ? ' · ' + color : '';
  for (const part of selection.powderParts) {
   if (part === wheels) {
    const type = options.wheelType;
    const rate = Object.hasOwn(wheelRates, type) ? wheelRates[type as keyof typeof wheelRates] : undefined;
    const prismatic = type === '10–14 inches' ? 2999 : type === '17 inches (Raider / Sniper only)' ? 3999 : undefined;
    items.set(wheels + (type ? ' · ' + type : '') + suffix, options.prismatic ? (prismatic ? [prismatic, prismatic] : undefined) : rate);
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
