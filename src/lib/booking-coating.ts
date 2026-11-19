import { parts, type finishes } from './coating';
import { powderParts, wheels } from './bookingCatalog';

export const appointmentPowderParts = [...new Set([...parts, ...Object.keys(powderParts)])];
export const appointmentWheelSizes = ['Not sure', ...Array.from({ length: 13 }, (_, index) => String(index + 10))];

export type CoatingDraft = {
	ceramic: '' | (typeof finishes)[number];
	red: boolean;
	powder: string[];
	front: string;
	rear: string;
};

export type CoatingOptions = {
	ceramic_finish?: Exclude<CoatingDraft['ceramic'], ''>;
	red_body?: boolean;
	powder_parts?: string[];
	wheel_front?: string;
	wheel_rear?: string;
};

export function coatingSnapshot(draft: CoatingDraft, services: readonly string[]): CoatingOptions {
	const snapshot: CoatingOptions = {};
	if (services.includes('ceramic') && draft.ceramic) {
		snapshot.ceramic_finish = draft.ceramic;
		if (draft.ceramic === 'Enhance') snapshot.red_body = draft.red;
	}
	if (services.includes('wheel-colour') && draft.powder.length) {
		snapshot.powder_parts = [...draft.powder].sort();
		if (draft.powder.includes(wheels)) {
			if (draft.front) snapshot.wheel_front = draft.front;
			if (draft.rear) snapshot.wheel_rear = draft.rear;
		}
	}
	return snapshot;
}
