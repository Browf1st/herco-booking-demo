<script lang="ts">
	// The service lines in a staff booking popup, with Edit price / Add service / Remove for staff who may use them.
	// Talks to /api/staff/line-price (price) and /api/booking-services (add, remove). The server checks every grant and the booking state.
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import ServiceLinesEditor, { type AddOption, type EditableLine, type SaveResult } from '../shared/ServiceLinesEditor.svelte';
	import { editRights, expectedCentavos, formatCentavos } from '../shared/booking-changes';
	import { displayServicePrice } from './service-estimate';
	import type { StaffLine } from './server-booking-types';

	let { bookingId, status, lines, actions, pages, showMoney, servicesEditable = $bindable(false), onupdated, onreload }: {
		bookingId: string; status: string; lines: StaffLine[]; actions: string[]; pages: string[]; showMoney: boolean;
		// True once the server says services can be edited here AND the add-options have loaded (the popup then shows its Edit service button,
		// so the dialog never opens with a wrong "No other services" message).
		servicesEditable?: boolean;
		// Called with the booking's new lines and total (in centavos) after every successful save.
		onupdated: (lines: StaffLine[], totalCentavos: number) => void;
		// Asks the screen to load this booking again (used by "Reload" after a 409).
		onreload: () => Promise<void>;
	} = $props();
	type CatalogItem = StaffLine & { appointment_days: number[] };
	const rights = $derived(editRights(status, actions, pages));
	let revision = $state(0);
	let codes = $state<string[]>([]);
	let visitDate = $state('');
	let canEditServices = $state(false);
	let catalog = $state<CatalogItem[]>([]);
	let catalogLoaded = $state(false);
	$effect(() => { servicesEditable = rights.services && canEditServices && catalogLoaded; });
	let loadIssue = $state('');
	let retry: { fingerprint: string; id: string } | undefined;

	const editable = $derived<EditableLine[]>(lines.map((line) => ({
		code: line.code, label: line.label,
		price: showMoney ? displayServicePrice(line) : undefined,
		centavos: showMoney && !line.quote_required && (line.max_centavos == null || line.max_centavos === line.price_centavos) ? line.price_centavos : undefined,
		currentPesos: typeof line.price_centavos === 'number' && line.price_centavos % 100 === 0 ? line.price_centavos / 100 : undefined,
		canEditPrice: rights.price && showMoney && expectedCentavos(line) !== undefined,
		parts: showMoney ? line.details?.map((part) => ({ label: part.label, price: formatCentavos(part.price_centavos) })) : undefined
	})));
	const addOptions = $derived<AddOption[]>(catalog
		.filter((item) => !codes.includes(item.code) && item.appointment_days.includes(new Date(visitDate + 'T00:00:00Z').getUTCDay()))
		.map((item) => ({ code: item.code, label: item.label, price: showMoney ? displayServicePrice(item) : undefined, centavos: showMoney && !item.quote_required && item.max_centavos == null ? item.price_centavos : undefined })));

	function requestId(body: object) {
		const fingerprint = JSON.stringify(body);
		if (retry?.fingerprint !== fingerprint) retry = { fingerprint, id: crypto.randomUUID() };
		return retry.id;
	}
	async function failure(response: Response): Promise<SaveResult> {
		const body = await response.json().catch(() => null);
		const text = typeof body?.message === 'string' ? body.message : '';
		if (response.status === 409 && body?.code === 'booking_locked') return { ok: false, message: 'This booking can no longer be changed.' };
		if (response.status === 409) return { ok: false, message: text || 'Someone else changed this booking. Reload and try again.', reload: true };
		if (response.status === 403) return { ok: false, message: 'You do not have permission to make this change.' };
		if (response.status === 401) return { ok: false, message: 'Please sign in again.' };
		if ((response.status === 400 || response.status === 404) && text) return { ok: false, message: text };
		return { ok: false, message: 'Could not save. Check your connection and try again.' };
	}
	function remember(result: { revision?: number; current?: StaffLine[]; canEdit?: boolean }) {
		if (typeof result.revision === 'number') revision = result.revision;
		if (result.current) codes = result.current.map((line) => line.code);
		if (typeof result.canEdit === 'boolean') canEditServices = result.canEdit;
	}

	async function loadServices() {
		loadIssue = '';
		try {
			const response = await fetch(resolve('/api/booking-services') + '?' + new URLSearchParams({ booking: bookingId }));
			if (!response.ok) throw Error('Could not load the services for editing.');
			const result = await response.json();
			remember(result);
			visitDate = result.date;
			if (result.canEdit && !catalog.length) {
				const available = await fetch(resolve('/api/catalog'));
				if (!available.ok) throw Error('Could not load the service catalog.');
				catalog = await available.json();
			}
			catalogLoaded = true;
		} catch (problem) { loadIssue = problem instanceof Error ? problem.message : 'Could not load the services for editing.'; }
	}

	async function savePrice(code: string, pesos: number, reason: string): Promise<SaveResult> {
		const expected = expectedCentavos(lines.find((line) => line.code === code) ?? {});
		if (expected === undefined) return { ok: false, message: 'The current price is not available, so it cannot be changed.' };
		const body = { booking: bookingId, service: code, expectedCentavos: expected, pesos, reason };
		try {
			const response = await fetch(resolve('/api/staff/line-price'), { method: 'POST', headers: { 'content-type': 'application/json', accept: 'application/json' }, body: JSON.stringify({ ...body, requestId: requestId(body) }) });
			if (!response.ok) return await failure(response);
			const result = await response.json();
			retry = undefined;
			remember({ revision: result.revision, current: result.lines });
			onupdated(result.lines, result.totalCentavos);
			return { ok: true };
		} catch { return { ok: false, message: 'Could not save. Check your connection and try again.' }; }
	}

	async function saveServices(wanted: string[]): Promise<SaveResult> {
		const body = { bookingId, revision, services: [...wanted].sort() };
		try {
			const response = await fetch(resolve('/api/booking-services'), { method: 'POST', headers: { 'content-type': 'application/json', accept: 'application/json' }, body: JSON.stringify({ ...body, requestId: requestId(body) }) });
			if (!response.ok) return await failure(response);
			const result = await response.json();
			retry = undefined;
			remember(result);
			onupdated(result.current, result.totalCentavos);
			return { ok: true };
		} catch { return { ok: false, message: 'Could not save. Check your connection and try again.' }; }
	}

	let editor = $state<ServiceLinesEditor>();
	/** The top-right Edit price / Edit service buttons in the popup call this. */
	export function reveal(mode: 'price' | 'service') { void editor?.reveal(mode); }

	async function reload() {
		await onreload();
		if (rights.services) await loadServices();
	}

	onMount(() => { if (rights.services) void loadServices(); });
</script>

<ServiceLinesEditor bind:this={editor} lines={editable} canAdd={rights.services && canEditServices} canRemove={rights.services && canEditServices} {addOptions}
	onsaveprice={savePrice} onapply={saveServices} onreload={reload} />
{#if loadIssue}<p class="error small" role="alert">{loadIssue} <button type="button" class="btn sm ghost" onclick={loadServices}>Try again</button></p>{/if}
