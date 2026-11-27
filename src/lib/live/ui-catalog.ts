import { ceramicTier, customNoteLimit } from '../shared/bookingCatalog.ts';
import { powderSizeFromValue, wheelRate, type PowderModel } from '../shared/powderPricing.ts';
import type { Selection } from '../shared/coating.ts';
export type { PowderColorEntry, PowderException, PowderModel } from '../shared/powderPricing.ts';
export type UiCatalogConfig = {
 powderModel?: PowderModel;
 ceramic?: {tiers?:Record<string,number>;models?:Record<string,string>;addons?:Record<string,number[]>;listedAddons?:Record<string,number>;premiumGloss?:number};
 powder?: {parts?:Record<string,number[]>;extras?:Record<string,number>;largeSwingarm?:number[]};
};
export function catalogRate(config:UiCatalogConfig,value:Selection,bike:string,year:number|undefined,label:string):number[]|undefined {
 const o=value.catalog!; const tier=o.otherBigBike?'2499':config.ceramic?.models?.[bike]??(o.bigBike?'2499':String(ceramicTier(bike,false)??''));
 if(label==='Ceramic coating'){
  const special=config.powderModel?.exceptions.find(rule=>rule.enabled&&rule.service==='ceramic'&&rule.bikeKey===bike.trim().toLowerCase());
  if(special)return special.quoteOnly||special.priceCentavos===undefined?undefined:[Math.round(special.priceCentavos)/100,Math.round(special.priceCentavos)/100];
  const n=config.ceramic?.tiers?.[tier];return n===undefined?undefined:[n,n];}
 if(config.ceramic?.addons?.[label]){const premium=label==='Matte to Glossy'&&(tier==='2499'||(/^Honda PCX/i.test(bike)&&year===2026));const n=premium?config.ceramic?.premiumGloss:config.ceramic?.listedAddons?.[label];return n===undefined?config.ceramic.addons[label]:[n,n];}
 if(label.startsWith('Wheels / mags')){const n=config.powderModel?wheelRate(config.powderModel,{bike,size:powderSizeFromValue(o.wheelType),finish:value.finish,prismatic:o.prismatic}):undefined;return n===undefined?undefined:[n,n];}
 if(config.powder?.extras?.[label]!==undefined){const n=config.powder.extras[label];return[n,n];}
 return label==='Swingarm'&&(o.bigBike||/Raider|Sniper/i.test(bike))?config.powder?.largeSwingarm:config.powder?.parts?.[label];
}
export function uiCoatingSnapshot(value:Selection,year?:number,notes='') {
 const o=value.catalog; const powder=value.powder; const mags=powder&&value.powderParts.includes('Wheels / mags'); const custom=mags&&o?.powderCategory==='custom'; const note=custom?(o?.customNote??'').trim().slice(0,customNoteLimit):'';
 return { ...(powder&&value.powderParts.length?{powder_parts:[...value.powderParts].sort(),...(mags?{wheel_front:'Not sure'}:{})}:{}),
  ui_catalog:{ceramic_addons:value.ceramic?[...(o?.ceramicAddons??[])].sort():[],wheel_type:mags?o?.wheelType??'':'',prismatic:mags&&Boolean(o?.prismatic),wheel_extras:mags?[...(o?.wheelExtras??[])].sort():[],big_bike:Boolean(o?.bigBike),other_big_bike:Boolean(o?.otherBigBike),finish:mags?value.finish.trim():'',...(mags&&o?.powderCategory?{powder_category:o.powderCategory}:{}),...(mags&&o?.colorId?{color_id:o.colorId}:{}),...(note?{custom_note:note}:{}),...(year?{model_year:year}:{}),notes:notes.trim()}};
}
