import { ceramicTier, type CatalogOptions } from './bookingCatalog';
import type { Selection } from './coating';
export type UiCatalogConfig = {
 ceramic?: {tiers?:Record<string,number>;models?:Record<string,string>;addons?:Record<string,number[]>;listedAddons?:Record<string,number>;premiumGloss?:number};
 powder?: {parts?:Record<string,number[]>;wheelRates?:Record<string,number[]>;prismatic?:Record<string,number>;extras?:Record<string,number>;largeSwingarm?:number[]};
};
export function catalogRate(config:UiCatalogConfig,value:Selection,bike:string,year:number|undefined,label:string):number[]|undefined {
 const o=value.catalog!; const tier=o.otherBigBike?'2499':config.ceramic?.models?.[bike]??(o.bigBike?'2499':String(ceramicTier(bike,false)??''));
 if(label==='Ceramic coating'){const n=config.ceramic?.tiers?.[tier];return n===undefined?undefined:[n,n];}
 if(config.ceramic?.addons?.[label]){const premium=label==='Matte to Glossy'&&(tier==='2499'||(/^Honda PCX/i.test(bike)&&year===2026));const n=premium?config.ceramic?.premiumGloss:config.ceramic?.listedAddons?.[label];return n===undefined?config.ceramic.addons[label]:[n,n];}
 if(label.startsWith('Wheels / mags')){const type=label.split(' · ')[1]??o.wheelType;const n=o.prismatic?config.powder?.prismatic?.[type]:undefined;return o.prismatic?(n===undefined?undefined:[n,n]):config.powder?.wheelRates?.[type];}
 if(config.powder?.extras?.[label]!==undefined){const n=config.powder.extras[label];return[n,n];}
 return label==='Swingarm'&&(o.bigBike||/Raider|Sniper/i.test(bike))?config.powder?.largeSwingarm:config.powder?.parts?.[label];
}
export function uiCoatingSnapshot(value:Selection,year?:number,notes='') {
 return { ...(value.powder&&value.powderParts.length?{powder_parts:[...value.powderParts].sort(),...(value.powderParts.includes('Wheels / mags')?{wheel_front:'Not sure'}:{})}:{}),
  ui_catalog:{ceramic_addons:value.ceramic?[...(value.catalog?.ceramicAddons??[])].sort():[],wheel_type:value.powder?value.catalog?.wheelType??'':'',prismatic:value.powder&&Boolean(value.catalog?.prismatic),wheel_extras:value.powder?[...(value.catalog?.wheelExtras??[])].sort():[],big_bike:Boolean(value.catalog?.bigBike),other_big_bike:Boolean(value.catalog?.otherBigBike),finish:value.powder?value.finish.trim():'',...(year?{model_year:year}:{}),notes:notes.trim()}};
}
