import type { Size } from './config';
import { catalogItems, powderParts, wheels, type CatalogOptions } from './bookingCatalog';

export const finishes = ['Stay Matte', 'Matte to Glossy', 'Enhance', 'Glossy Finish'] as const;
export const parts = ['Wheels / mags', 'Frame', 'Subframe', 'Swingarm', 'Brackets', 'Foot pegs', 'Grab rails', 'Metal covers', 'Other metal parts'];
export const bikes: Record<Size, string[]> = {
 small: ['Honda ADV150','Honda ADV160','Honda PCX150','Honda PCX160','Honda Click125','Honda Click160','Honda BeAT','Honda Giorno+','Honda AirBlade160','Honda Wave RSX','Honda XRM125','Honda Winner X','Yamaha NMAX','Yamaha Aerox','Yamaha Mio Gear','Yamaha Mio Fazzio','Yamaha Mio Gravis','Yamaha Mio i125','Suzuki Burgman Street','Suzuki Access','Suzuki Avenis','Suzuki Raider R150','Suzuki Smash','Kymco Like 150i','Kymco Dink R 150','Vespa Primavera 150','SYM Jet X 150'],
 medium: ['Honda ADV350','Honda CRF150L','Honda CB150X','Yamaha MT-15','Yamaha XSR155','Yamaha WR155R','Yamaha YZF-R3','Yamaha XMAX','Suzuki Gixxer 155','Suzuki Gixxer 250','Suzuki V-Strom 250 SX','Kawasaki Rouser NS160','Kawasaki Dominar 400','Kawasaki Ninja 400','Kawasaki KLX150','CFMOTO 300NK','CFMOTO 400NK','KTM 390 Duke','Royal Enfield Hunter 350'],
 large: ['Honda CB650R','Honda CBR650R','Honda X-ADV','Honda Africa Twin','Yamaha MT-07','Yamaha MT-09','Yamaha TMAX','Suzuki SV650','Suzuki GSX-8S','Kawasaki Ninja 650','Kawasaki Z650','Kawasaki Z900','Kawasaki Versys 650','CFMOTO 450MT','CFMOTO 450SR','CFMOTO 700CL-X','Royal Enfield Interceptor 650','Triumph Trident 660','BMW R 1300 GS','Ducati Monster']
};

export type Selection = { ceramic: boolean; powder: boolean; ceramicFinish: string; red: boolean; powderParts: string[]; front: string; rear: string; finish: string; catalog?: CatalogOptions };
const versions: Record<string, readonly string[]> = {
 'Honda ADV160': ['ABS', 'RoadSync'],
 'Honda PCX160': ['CBS (earlier model)', 'ABS (earlier model)', 'Standard', 'RoadSync'],
 'Honda Click125': ['Standard', 'Smart Edition', 'Street'],
 'Honda Click160': ['2027 model'],
 'Honda BeAT': ['Playful', 'Premium'],
 'Yamaha NMAX': ['Standard', 'Tech MAX'],
 'Yamaha Aerox': ['Standard', 'SP'],
 'Suzuki Burgman Street': ['125 EX'],
 'Suzuki Raider R150': ['Carb', 'Fi'],
 'Suzuki Smash': ['Carb', 'Fi'],
 'Kawasaki KLX150': ['BF (earlier model)', 'S'],
 'CFMOTO 450SR': ['S']
};

export const motorcycleVersions = (model: string) => versions[model] ?? [];

export function motorcycleOptions(size: Size) {
 return bikes[size].flatMap(model => [model, ...motorcycleVersions(model).map(version => model + ' — ' + version)]);
}

export function modelAdjustment(models: Record<string, number>, bike: string) {
 const base = bike.split(' — ')[0];
 if (Object.hasOwn(models, bike)) return models[bike];
 return Object.hasOwn(models, base) ? models[base] : 0;
}
export const selection = (powder = false, finish = ''): Selection => ({ ceramic: !powder, powder, ceramicFinish: 'Glossy Finish', red: false, powderParts: [], front: '', rear: '', finish });
export type Pricing = { ceramic: Record<string, number>; powder: Record<string, number>; size: Record<Size, number>; models: Record<string, number>; promo: number };
export const defaultPricing: Pricing = {
 ceramic: { 'Stay Matte': 1800, 'Matte to Glossy': 2200, Enhance: 2100, 'Glossy Finish': 1500 },
 powder: Object.fromEntries(parts.map((part, i) => [part, [2500,3000,1300,1600,400,500,700,700,700][i]])),
 size: { small: 0, medium: 400, large: 900 }, models: { 'Honda ADV160': 300, 'Honda PCX160': 250 }, promo: 0
};
export const money = (value: number) => new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP', maximumFractionDigits: 2 }).format(value);
export const canEnhance = (bike: string) => /^honda\s+(adv|pcx)\s*(150|160)\b/i.test(bike.trim());
export const serviceLabel = (s: Selection) => [s.ceramic && 'Ceramic Coating', s.powder && 'Powder Coating'].filter(Boolean).join(' + ');
export type ServiceLine = { label: string; subtotal: number; discount: number; maximum?: number; pending?: boolean };
export type Estimate = { subtotal: number; discount: number; total: number; lines?: ServiceLine[] };
const round = (amount: number) => Math.round(amount * 100) / 100;

export function linePrice(line: ServiceLine) {
 return line.pending ? 'Shop quote required' : line.maximum !== undefined ? money(line.subtotal) + '–' + money(line.maximum) : money(line.subtotal);
}

export function estimatePrice(estimate: Estimate) {
 const maximum = round(estimate.total + (estimate.lines ?? []).reduce((sum, line) => sum + (line.maximum ?? line.subtotal) - line.subtotal, 0));
 const priced = maximum === estimate.total ? money(estimate.total) : money(estimate.total) + '–' + money(maximum);
 if (estimate.lines?.some(line => line.pending)) return estimate.total ? priced + ' plus shop quote' : 'Shop quote required';
 return priced;
}

export function quote(s: Selection, size: Size, bike: string, pricing: Pricing, saved: ServiceLine[] = [], year?: number): Estimate {
 if (s.catalog) {
  const lines = [...catalogItems(s, s.catalog, bike, year)].map(([label, range]): ServiceLine =>
   saved.find(line => line.label === label) ?? {
    label, subtotal: range?.[0] ?? 0, discount: round((range?.[0] ?? 0) * pricing.promo / 100),
    maximum: range && range[0] !== range[1] ? range[1] : undefined, pending: !range
   });
  const subtotal = lines.reduce((sum, line) => sum + line.subtotal, 0);
  const discount = round(lines.reduce((sum, line) => sum + line.discount, 0));
  return { subtotal, discount, total: round(subtotal - discount), lines };
 }
 const items = new Map<string, number>();
 if (s.ceramic) {
  items.set('Ceramic coating · ' + s.ceramicFinish, (pricing.ceramic[s.ceramicFinish] ?? 0) + pricing.size[size] + modelAdjustment(pricing.models, bike));
 }
 if (s.powder) {
  for (const part of s.powderParts) {
   const details = [s.finish.trim(), part === parts[0] && ('Front: ' + (s.front || '—') + ', rear: ' + (s.rear || '—'))].filter(Boolean);
   items.set('Powder coating · ' + part + (details.length ? ' · ' + details.join(' · ') : ''), pricing.powder[part] ?? 0);
  }
 }
 const lines = [...items].map(([label, subtotal]) => saved.find(line => line.label === label) ??
  { label, subtotal: round(subtotal), discount: round(subtotal * pricing.promo / 100) });
 const subtotal = round(lines.reduce((sum, line) => sum + line.subtotal, 0));
 const discount = round(lines.reduce((sum, line) => sum + line.discount, 0));
 return { subtotal, discount, total: round(subtotal - discount), lines };
}
export function validateSelection(s: Selection, bike: string) {
 if (!s.ceramic && !s.powder) throw Error('Choose at least one service.');
 if (s.catalog) {
  if (s.powder && (!s.powderParts.length || s.powderParts.some(part => part !== wheels && !Object.hasOwn(powderParts, part)))) throw Error('Choose wheels or small parts for powder coating.');
  if (s.powder && s.powderParts.includes(wheels) && !s.catalog.wheelType) throw Error('Choose a wheel category.');
  if (s.powder && s.powderParts.includes(wheels) && s.catalog.wheelType.startsWith('17') && !/Raider|Sniper/i.test(bike)) throw Error('The 17-inch mags price is for Raider and Sniper only. Check your motorcycle or choose another wheel category.');
  return;
 }
 if (s.ceramic && (!finishes.some(f => f === s.ceramicFinish) || (s.ceramicFinish === 'Enhance' && (!canEnhance(bike) || !s.red)))) throw Error('Enhance is for red Honda ADV or PCX 150/160 units.');
 if (s.powder && (!s.powderParts.length || s.powderParts.some(p => !parts.includes(p)))) throw Error('Choose the parts you want powder coated.');
 if (s.powder && s.powderParts.includes(parts[0]) && ![s.front, s.rear].some(Boolean)) throw Error('Enter a wheel size or select Not sure.');
}
