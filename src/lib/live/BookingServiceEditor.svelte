<script lang="ts">
	import { onMount } from 'svelte';
 import ServerBookingCatalog from './ServerBookingCatalog.svelte';
 import { selection,type Selection } from '../shared/coating';
 import { createCatalogOptions, type PowderCategory } from '../shared/bookingCatalog';
 import { findColorEntry, powderSizeFromValue } from '../shared/powderPricing';
 import { uiCoatingSnapshot,type UiCatalogConfig } from './ui-catalog';
 import type {CoatingOptions} from './booking-coating';
	import { resolve } from '$app/paths';
	import { fmtDate } from '#lib/shared/dates.ts';
	import { displayEstimate, displayServicePrice, type PricedService } from './service-estimate';

	type Line = PricedService & { code: string; label: string; promotion?: { label: string } | null };
	type Services = { original: Line[]; current: Line[]; totalCentavos: number; revision: number;
		date: string; canEdit: boolean; bike:string; options:CoatingOptions };
	let { bookingId, fromStaff, embedded = false, shopPriced = false, readOnly = false, onsaved }: {
		bookingId: string; fromStaff: boolean; embedded?: boolean; shopPriced?: boolean; /** Customers view services here; they edit on /book?edit=. */ readOnly?: boolean; onsaved?: () => void } = $props();
	// Once staff changed a price, the customer can no longer edit services (the server enforces it too).
	const shopMessage = 'The shop updated this booking after inspection. Contact the shop to change services.';
	let shopLocked = $state(false);
	const customerLocked = $derived(!fromStaff && (shopPriced || shopLocked));
	let details = $state<Services>();
 let rich=$state<Selection>({...selection(),catalog:createCatalogOptions()});
 let config=$state<UiCatalogConfig>({});
 let formYear=$state<number>(), formNotes=$state('');
	let loading = $state(true);
	let busy = $state(false);
	let issue = $state('');
	let notice = $state('');
	let retry = $state<{ fingerprint: string; id: string }>();
	// The services still on the booking that the rich catalog doesn't manage (kept as-is on save).
	const keepCodes = $derived(details ? details.current.map(line => line.code).filter(code => code !== 'ceramic' && code !== 'wheel-colour') : []);
	const chosen = $derived([...(rich.ceramic ? ['ceramic'] : []), ...(rich.powder ? ['wheel-colour'] : []), ...keepCodes]);

	/** Opens old bookings (old size labels, the prismatic flag, raider_sniper_confirmed) on the new size and colour group. */
	function savedPowderChoice(c: CoatingOptions['ui_catalog']) {
		const entry = findColorEntry(config.powderModel, c?.finish ?? '');
		const category = (c?.powder_category as PowderCategory | undefined) || entry?.category || (c?.prismatic ? 'luminous-prismatic' : '');
		return { wheelType: powderSizeFromValue(c?.wheel_type) || (c?.wheel_type ?? ''), powderCategory: category as PowderCategory | '',
			colorId: entry?.id ?? c?.color_id ?? '', customNote: c?.custom_note ?? '', prismatic: c?.prismatic ?? false };
	}

	function show(result: Services) {
		details = result;
 const c=result.options?.ui_catalog;
 rich={...selection(),ceramic:result.current.some(line=>line.code==='ceramic'),powder:result.current.some(line=>line.code==='wheel-colour'),powderParts:result.options?.powder_parts??[],finish:c?.finish??'',catalog:{...createCatalogOptions(),ceramicAddons:c?.ceramic_addons??[],...savedPowderChoice(c),wheelExtras:c?.wheel_extras??[],bigBike:c?.big_bike??false,otherBigBike:c?.other_big_bike??false}};
 formYear=c?.model_year;formNotes=c?.notes??'';
	}

	async function errorMessage(response: Response) {
		const failure = await response.json().catch(() => null);
		return typeof failure?.message === 'string' ? failure.message : 'Could not load booking services.';
	}

	async function load() {
		loading = true;
		issue = '';
		try {
			const response = await fetch(resolve('/api/booking-services') + '?' + new URLSearchParams({ booking: bookingId }));
			if (!response.ok) throw Error(await errorMessage(response));
			const result = await response.json();
			if (result.canEdit && !readOnly) {
 const richCatalog=await fetch(resolve('/api/booking-catalog'));if(!richCatalog.ok)throw Error('Could not load catalog options.');config=(await richCatalog.json()).config;
			}
			show(result);
		} catch (failure) {
			issue = failure instanceof Error ? failure.message : 'Could not load booking services.';
		} finally {
			loading = false;
		}
	}

	async function save(event: SubmitEvent) {
		event.preventDefault();
		if (!details || busy || !chosen.length) return;
		busy = true;
		notice = issue = '';
		try {
			const coating=uiCoatingSnapshot(rich,formYear,formNotes);
 const payload = { bookingId, revision: details.revision, services: [...chosen].sort(),coating };
			const fingerprint = JSON.stringify(payload);
			if (retry?.fingerprint !== fingerprint) retry = { fingerprint, id: crypto.randomUUID() };
			const response = await fetch(resolve('/api/booking-services'), {
				method: 'POST', headers: { 'content-type': 'application/json', accept: 'application/json' },
				body: JSON.stringify({ ...payload, requestId: retry.id })
			});
			if (!response.ok) {
				const failure = await response.json().catch(() => null);
				if (response.status === 409 && failure?.code === 'shop_priced') { shopLocked = true; return; }
				throw Error(typeof failure?.message === 'string' ? failure.message : 'Could not load booking services.');
			}
			show(await response.json());
			retry = undefined;
			notice = 'Booking services saved.';
			onsaved?.();
		} catch (failure) {
			issue = failure instanceof Error ? failure.message : 'Could not save the selection. Retry with the same details.';
		} finally {
			busy = false;
		}
	}

	onMount(() => { void load(); });
</script>

<svelte:head><title>Booking services | HERCO</title></svelte:head>
<section class:section={!embedded} class:wrap={!embedded} class="stack">
	{#if !embedded}<div><a class="btn sm ghost" href={resolve(fromStaff ? '/admin' : '/my-bookings')}>Back to bookings</a></div><h1>Booking services</h1>{/if}
	{#if loading}
		<p role="status">Loading booking services…</p>
	{:else if details}
		<p class="visit-line">Visit · {fmtDate(details.date)}{details.bike ? ' · ' + details.bike : ''}</p>
		{#if customerLocked && !readOnly}<p role="status">{shopMessage}</p>{/if}
		{#if details.canEdit && !customerLocked && !readOnly}
			<form class="editor stack" onsubmit={save}>
				<fieldset class="stack" disabled={busy}>
					<legend>Choose services and options</legend>
					<ServerBookingCatalog bind:value={rich} bike={details.bike} year={formYear} {config} serviceControls={true} />
					<label class="notes">Notes for the shop<textarea bind:value={formNotes} maxlength="700" rows="2"></textarea></label>
				</fieldset>
				<div class="editor-foot">
					<p class="estimate">Estimated total <strong>{displayEstimate(details.current, details.totalCentavos)}</strong></p>
					<button class="btn save" disabled={busy || !chosen.length}>{busy ? 'Saving…' : 'Save changes'}</button>
				</div>
			</form>
		{:else}
			<h2>Services on this booking</h2>
			<p class="estimate">Total <strong>{displayEstimate(details.current, details.totalCentavos)}</strong></p>
			{@render serviceList(details.current)}
		{/if}
	{/if}
	{#if issue}
		<p role="alert">{issue}</p>
		<div><button class="btn sm ghost" disabled={busy} onclick={load}>Reload</button></div>
	{/if}
	{#if notice}<p role="status" class="notice">{notice}</p>{/if}
</section>

{#snippet serviceList(lines: Line[])}
	<ul class="services">{#each lines as line (line.code)}
		<li><span>{line.label}{line.promotion ? ' · ' + line.promotion.label : ''}</span><strong>{displayServicePrice(line)}</strong></li>
	{/each}</ul>
{/snippet}

<style>
	.editor { gap: 1rem; }
	fieldset { min-inline-size: 0; margin: 0; padding: 0; border: 0; }
	legend { padding: 0 0 .4rem; font-weight: 750; }
	.notes { display: grid; gap: .3rem; margin-top: .75rem; font-weight: 600; }
	.notes textarea { background: var(--panel); border-radius: 10px; font-weight: 400; }
	.visit-line { color: var(--muted); font-weight: 650; }
	.editor-foot { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: .75rem; padding-top: .75rem; border-top: 1px solid var(--line); }
	.estimate { margin: 0; }
	.estimate strong { font-size: 1.15rem; color: var(--accent); }
	.save { min-width: 11rem; }
	.services { display: grid; gap: .4rem; margin: 0; padding: 0; list-style: none; }
	.services li { display: flex; justify-content: space-between; gap: .75rem; padding: .5rem .7rem; border: 1px solid var(--line); border-radius: 8px; background: var(--panel-2); }
	.services strong { text-align: right; }
	.notice { color: var(--ok); font-weight: 650; }
	@media (max-width: 480px) { .save { width: 100%; } }
</style>
