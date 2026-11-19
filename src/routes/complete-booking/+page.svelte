<script lang="ts">
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { onMount } from 'svelte';
	const worker = import.meta.env.MODE === 'worker';
	const booking = $derived(page.url.searchParams.get('booking') ?? '');
	let files = $state<File[]>([]);
	let price = $state<number>();
	let note = $state('');
	let busy = $state(false);
	let failure = $state('');
	let done = $state(false);
	let uploaded = $state<string[]>([]);
	let photoCount = $state(0);
	let loading = $state(worker);
	let evidenceAccess = $state(false);
	const photoUrl = $derived(resolve('/api/completion') + '?booking=' + encodeURIComponent(booking));

	async function readEvidence() {
		try {
			const response = await fetch(photoUrl);
			if (!response.ok) {
				const detail = await response.json().catch(() => null);
				throw new Error(detail?.message ?? 'Completion evidence is temporarily unavailable.');
			}
			photoCount = (await response.json()).count;
			evidenceAccess = true;
		} catch (error) {
			failure = error instanceof Error ? error.message : 'Completion evidence is temporarily unavailable.';
		} finally { loading = false; }
	}
	onMount(() => { if (worker && booking) void readEvidence(); });

	function choose(event: Event, append = false) {
		const input = event.currentTarget as HTMLInputElement;
		const incoming = Array.from(input.files ?? []);
		if (!incoming.length) return;
		const next = append ? [...files, ...incoming] : incoming;
		if (next.length > 3 || next.some(file => file.size > 4 * 1024 * 1024)) {
			failure = 'Choose up to three photos, no more than 4 MB each.';
			input.value = '';
			return;
		}
		files = next;
		uploaded = [];
		failure = '';
	}

	async function execute(method: 'PUT' | 'POST', body: BodyInit) {
		const endpoint = resolve('/api/completion');
		const response = await fetch(method === 'PUT' ? endpoint + '?booking=' + encodeURIComponent(booking) : endpoint, {
			method,
			headers: { accept: 'application/json', 'content-type': method === 'PUT' ? 'application/octet-stream' : 'application/json' },
			body
		});
		if (!response.ok) {
			const detail = await response.json().catch(() => null);
			throw new Error(detail?.message ?? 'Could not confirm this update. Please try again.');
		}
		return response.json();
	}

	async function complete(event: SubmitEvent) {
		event.preventDefault();
		if (busy || price === undefined || !files.length) return;
		busy = true;
		failure = '';
		try {
			for (let index = uploaded.length; index < files.length; index++) {
				const result = await execute('PUT', files[index]);
				uploaded = [...uploaded, result.path];
			}
			await execute('POST', JSON.stringify({ booking, priceCentavos: Math.round(price * 100), photos: uploaded, note }));
			done = true;
			photoCount = uploaded.length;
		} catch (error) {
			failure = error instanceof Error ? error.message : 'Could not confirm completion. Please try again.';
		} finally {
			busy = false;
		}
	}
</script>

<svelte:head><title>Complete booking | HERCO</title></svelte:head>
<section class="section wrap stack">
	<h1>Complete booking</h1>
	{#if !worker || !booking}
		<p>Open a confirmed booking from the staff workspace to mark it completed.</p>
	{:else if loading}
		<p role="status">Loading completion details…</p>
	{:else if !evidenceAccess}
		<p role="alert">{failure}</p>
		<div><button class="btn sm ghost" onclick={() => { loading = true; failure = ''; void readEvidence(); }}>Try again</button></div>
	{:else if done || photoCount}
		{#if done}<p role="status">Booking completed. The final service price and photos were saved.</p>{/if}
		<div class="row">
			{#each Array.from({ length: photoCount }, (_, index) => index) as index (index)}
				<a class="btn sm ghost" href={photoUrl + '&photo=' + index} target="_blank" rel="noreferrer">View photo {index + 1}</a>
			{/each}
		</div>
	{:else}
		<form class="card stack" onsubmit={complete}>
			<p class="small muted reference">Booking {booking}</p>
			<label>Final service price (₱)<input type="number" min="0" step=".01" bind:value={price} required disabled={busy} /></label>
			<label>Completion note (optional)<textarea bind:value={note} maxlength="500" disabled={busy}></textarea></label>
			<label>Choose photos<input type="file" accept="image/jpeg,image/png,image/webp" multiple onchange={choose} disabled={busy} /></label>
			<label>Take a photo<input type="file" accept="image/*" capture="environment" onchange={(event) => choose(event, true)} disabled={busy} /></label>
			<p class="small muted">Attach one to three private JPEG, PNG, or WebP photos.</p>
			{#if files.length}
				<ul>{#each files as file, index}<li>{file.name}{index < uploaded.length ? ' · Saved' : ''}</li>{/each}</ul>
			{/if}
			{#if failure}<p role="alert">{failure}</p>{/if}
			{#if busy}<p role="status">Saved {uploaded.length} of {files.length} photos…</p>{/if}
			<div><button class="btn sm" disabled={busy || !files.length}>Mark completed</button></div>
		</form>
	{/if}
	<div><a class="btn sm ghost" href={resolve('/admin')}>Staff workspace</a></div>
</section>

<style>
	.reference { overflow-wrap: anywhere; }
</style>
