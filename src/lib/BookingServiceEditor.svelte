<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import { fmtDate } from '#lib/dates.ts';
	import { displayEstimate, displayServicePrice, type PricedService } from './service-estimate';

	type Line = PricedService & { code: string; label: string; promotion?: { label: string } | null };
	type CatalogItem = Line & { appointment_days: number[] };
	type Change = { revision: number; recorded_at: string; before_services: Line[]; after_services: Line[] };
	type Services = { original: Line[]; current: Line[]; totalCentavos: number; revision: number;
		date: string; canEdit: boolean; changes: Change[] };
	let { bookingId, fromStaff }: { bookingId: string; fromStaff: boolean } = $props();
	const stamp = new Intl.DateTimeFormat('en-PH', { timeZone: 'Asia/Manila', dateStyle: 'medium', timeStyle: 'short' });
	let details = $state<Services>();
	let catalog = $state<CatalogItem[]>([]);
	let checked = $state<string[]>([]);
	let loading = $state(true);
	let busy = $state(false);
	let issue = $state('');
	let notice = $state('');
	let retry = $state<{ fingerprint: string; id: string }>();
	const choices = $derived(details ? [...details.current, ...catalog.filter(item => !details?.current.some(line =>
		item.code === line.code) && item.appointment_days.includes(new Date(details?.date + 'T00:00:00Z').getUTCDay()))] : []);

	function show(result: Services) {
		details = result;
		checked = result.current.map(line => line.code);
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
			if (result.canEdit) {
				const available = await fetch(resolve('/api/catalog'));
				if (!available.ok) throw Error('Could not load the service catalog.');
				catalog = await available.json();
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
		if (!details || busy || !checked.length) return;
		busy = true;
		notice = issue = '';
		try {
			const payload = { bookingId, revision: details.revision, services: [...checked].sort() };
			const fingerprint = JSON.stringify(payload);
			if (retry?.fingerprint !== fingerprint) retry = { fingerprint, id: crypto.randomUUID() };
			const response = await fetch(resolve('/api/booking-services'), {
				method: 'POST', headers: { 'content-type': 'application/json', accept: 'application/json' },
				body: JSON.stringify({ ...payload, requestId: retry.id })
			});
			if (!response.ok) throw Error(await errorMessage(response));
			show(await response.json());
			retry = undefined;
			notice = 'Booking services saved.';
		} catch (failure) {
			issue = failure instanceof Error ? failure.message : 'Could not save the selection. Retry with the same details.';
		} finally {
			busy = false;
		}
	}

	onMount(() => { void load(); });
</script>

<svelte:head><title>Booking services | HERCO</title></svelte:head>
<section class="section wrap stack">
	<div><a class="btn sm ghost" href={resolve(fromStaff ? '/admin' : '/my-bookings')}>Back to bookings</a></div>
	<h1>Booking services</h1>
	{#if loading}
		<p role="status">Loading booking services…</p>
	{:else if details}
		<p>Visit · {fmtDate(details.date)}</p>
		<p>Current estimate <strong>{displayEstimate(details.current, details.totalCentavos)}</strong></p>
		{#if details.canEdit}
			<form class="card stack" onsubmit={save}>
				<fieldset class="stack" disabled={busy}>
					<legend>Choose services</legend>
					{#each choices as service (service.code)}
						<label class="option"><input type="checkbox" bind:group={checked} value={service.code} />
							<span>{service.label} · {displayServicePrice(service)}
							{#if service.promotion}<small>{service.promotion.label}</small>{/if}</span>
						</label>
					{/each}
				</fieldset>
				<div><button class="btn sm" disabled={busy || !checked.length}>{busy ? 'Saving…' : 'Save services'}</button></div>
			</form>
		{:else}
			<h2>Current services</h2>
			{@render services(details.current)}
		{/if}
		<details class="card">
			<summary>Original services and change history</summary>
			<h2>Original services</h2>
			{@render services(details.original)}
			{#each details.changes as change (change.revision)}
				<h3>{stamp.format(new Date(change.recorded_at))} Philippine time</h3>
				<p>Services after change</p>
				{@render services(change.after_services)}
			{/each}
		</details>
	{/if}
	{#if issue}
		<p role="alert">{issue}</p>
		<div><button class="btn sm ghost" disabled={busy} onclick={load}>Reload</button></div>
	{/if}
	{#if notice}<p role="status">{notice}</p>{/if}
</section>

{#snippet services(lines: Line[])}
	<ul>{#each lines as line (line.code)}
		<li>{line.label} · {displayServicePrice(line)}{line.promotion ? ' · ' + line.promotion.label : ''}</li>
	{/each}</ul>
{/snippet}

<style>
	.option { display: flex; align-items: center; gap: .5rem; }
	.option input { width: auto; }
</style>
