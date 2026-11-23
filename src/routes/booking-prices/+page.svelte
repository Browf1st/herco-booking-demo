<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import PageHeader from '#lib/shared/PageHeader.svelte';
	const worker = import.meta.env.MODE === 'worker';
	const booking = $derived(page.url.searchParams.get('booking') ?? '');
	const url = resolve('/api/booking-prices');
	const money = new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP' });
	const stamp = new Intl.DateTimeFormat('en-PH', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Manila' });
	type Line = { code: string; label: string; price_centavos: number | null; quote_required?: boolean; max_centavos?: number };
	type Info = { revision: number; status: string; lines: Line[]; corrections: {
		revision: number; service_code: string; reason: string; previous_centavos: number | null;
		corrected_centavos: number; recorded_at: string }[] };
	let info = $state<Info>();
	let service = $state('');
	let amount = $state<number>();
	let reason = $state('');
	let busy = $state(false);
	let message = $state('');
	let notice = $state('');
	let retry: { fingerprint: string; id: string } | undefined;

	async function read(response: Response): Promise<Info> {
		const value = await response.json().catch(() => null);
		if (!response.ok || !value) throw Error(value?.message ?? 'Booking prices are temporarily unavailable.');
		return value;
	}

	async function load() {
		busy = true;
		message = '';
		try { info = await read(await fetch(url + '?booking=' + encodeURIComponent(booking))); }
		catch (error) { message = error instanceof Error ? error.message : 'Could not load booking prices.'; }
		finally { busy = false; }
	}

	async function save(event: SubmitEvent) {
		event.preventDefault();
		if (!info || !service || amount == null || !reason.trim() || busy) return;
		busy = true;
		message = notice = '';
		try {
			const payload = { booking, revision: info.revision, service, centavos: Math.round(amount * 100), reason: reason.trim() };
			const fingerprint = JSON.stringify(payload);
			if (retry?.fingerprint !== fingerprint) retry = { fingerprint, id: crypto.randomUUID() };
			info = await read(await fetch(url, { method: 'POST',
				headers: { 'content-type': 'application/json', accept: 'application/json' },
				body: JSON.stringify({ ...payload, requestId: retry.id }) }));
			retry = undefined;
			amount = undefined;
			service = reason = '';
			notice = 'Price saved and recorded in booking activity.';
		} catch (error) { message = error instanceof Error ? error.message : 'Could not confirm the price change.'; }
		finally { busy = false; }
	}

	function linePrice(line: Line) {
		if (line.quote_required || line.price_centavos == null) return 'Shop quote required';
		const minimum = money.format(line.price_centavos / 100);
		return line.max_centavos == null ? minimum : minimum + '–' + money.format(line.max_centavos / 100);
	}

	onMount(() => { if (worker && booking) void load(); });
</script>

<svelte:head><title>Booking prices | HERCO</title></svelte:head>
<section class="section wrap stack">
	<PageHeader title="Booking prices" subtitle="Correct the price of one booking. Every change is kept in its history.">
		<a class="btn sm ghost" href={resolve('/admin')}>Staff workspace</a>
	</PageHeader>
	{#if message}<p role="alert">{message}</p><div><button class="btn sm ghost" onclick={load} disabled={busy}>Reload</button></div>{/if}
	{#if notice}<p role="status">{notice}</p>{/if}
	{#if info}
		<ul>{#each info.lines as line (line.code)}<li>{line.label} · {linePrice(line)}</li>{/each}</ul>
		<form class="card stack" onsubmit={save}>
			{#if info.status === 'done'}<p>This correction will update Completed service value and record the previous amount in the audit trail.</p>{/if}
			<label for="price-service">Service</label>
			<select id="price-service" bind:value={service} disabled={busy} required>
				<option value="">Choose a service</option>
				{#each info.lines as line (line.code)}<option value={line.code}>{line.label}</option>{/each}
			</select>
			<label>Exact price (₱)<input type="number" min="0" max="999999999.99" step=".01" bind:value={amount} disabled={busy} required /></label>
			<label>Reason<input bind:value={reason} maxlength="300" disabled={busy} required /></label>
			<div><button class="btn sm" disabled={busy}>Save price</button></div>
		</form>
		{#if info.corrections.length}
			<section class="card stack"><h2>Price correction history</h2>
				{#each info.corrections as correction (correction.revision)}
					<p>{info.lines.find(line => line.code === correction.service_code)?.label ?? correction.service_code} ·
						{correction.previous_centavos == null ? 'Unquoted' : money.format(correction.previous_centavos / 100)} →
						{money.format(correction.corrected_centavos / 100)} · {correction.reason} ·
						{stamp.format(new Date(correction.recorded_at))} Philippine time</p>
				{/each}
			</section>
		{/if}
	{:else if busy}<p role="status">Loading prices…</p>
	{:else if !message}<p>Open a booking from the staff workspace to edit its prices.</p>{/if}
</section>
