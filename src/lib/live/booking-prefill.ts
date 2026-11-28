// Turns a saved booking (stored coating options and bike text) back into the booking form's fields.
// Used by the edit mode of the booking screen. Pure functions, so Node tests can load it.
import { ceramicModels, createCatalogOptions, type CatalogOptions, type PowderCategory } from '../shared/bookingCatalog.ts';
import type { Selection } from '../shared/coating.ts';
import { findColorEntry, powderSizeFromValue } from '../shared/powderPricing.ts';
import type { CoatingOptions } from './booking-coating.ts';
import type { UiCatalogConfig } from './ui-catalog.ts';

type SavedCatalog = NonNullable<CoatingOptions['ui_catalog']>;

/** Opens old bookings (old size labels, the prismatic flag) on the new size and colour group. */
function savedPowderChoice(c: SavedCatalog | undefined, config: UiCatalogConfig) {
	const entry = findColorEntry(config.powderModel, c?.finish ?? '');
	const category = (c?.powder_category as PowderCategory | undefined) || entry?.category || (c?.prismatic ? 'luminous-prismatic' : '');
	return { wheelType: powderSizeFromValue(c?.wheel_type) || (c?.wheel_type ?? ''), powderCategory: category as PowderCategory | '',
		colorId: entry?.id ?? c?.color_id ?? '', customNote: c?.custom_note ?? '', prismatic: c?.prismatic ?? false };
}

/** The service choice, add-ons, powder parts and finish saved on the booking. */
export function prefillSelection(options: CoatingOptions | undefined, serviceCodes: readonly string[], config: UiCatalogConfig): Selection & { catalog: CatalogOptions } {
	const c = options?.ui_catalog;
	return { ceramicFinish: 'Glossy Finish', red: false, front: '', rear: '', ceramic: serviceCodes.includes('ceramic'), powder: serviceCodes.includes('wheel-colour'),
		powderParts: options?.powder_parts ?? [], finish: c?.finish ?? '',
		catalog: { ...createCatalogOptions(), ceramicAddons: c?.ceramic_addons ?? [], ...savedPowderChoice(c, config),
			wheelExtras: c?.wheel_extras ?? [], bigBike: c?.big_bike ?? false, otherBigBike: c?.other_big_bike ?? false } };
}

const listedModels: string[] = Object.values(ceramicModels).flat();

/**
 * Maps the stored bike text to the form's motorcycle fields.
 * A listed model selects its tier radio. Anything else uses the "not listed" path
 * (or "other big bike" when the booking was saved as one) with the text in the model box.
 * Powder-only bookings keep the text in the powder motorcycle box.
 */
export function prefillBike(bike: string, ceramic: boolean, options: CoatingOptions | undefined) {
	const text = (bike ?? '').trim();
	if (!ceramic) return { unit: '', custom: '', powderBike: text };
	const model = text.split(' — ')[0];
	if (listedModels.includes(model)) return { unit: model, custom: '', powderBike: '' };
	return { unit: options?.ui_catalog?.other_big_bike ? 'other-big-bike' : 'other', custom: text, powderBike: '' };
}
