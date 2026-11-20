<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { resolve } from '$app/paths';
	import ActionIcon from './ActionIcon.svelte';
	let { bookingId, initialPrice, onSaved = () => {}, onClose }: { bookingId: string; initialPrice?: number; onSaved?: () => void; onClose?: () => void } = $props();
	let files = $state<File[]>([]);
	let previews = $state<string[]>([]);
	let price = $state<number | undefined>();
	let note = $state('');
	let issue = $state('');
	let busy = $state(false);
	let loading = $state(true);
	let photoCount = $state(0);
	let uploaded = $state<string[]>([]);
	let camera = $state<HTMLInputElement>();
	let album = $state<HTMLInputElement>();
	const photoUrl = $derived(resolve('/api/completion') + '?booking=' + encodeURIComponent(bookingId));
	async function read() {
		loading = true; issue = '';
		try { const response = await fetch(photoUrl); const result = await response.json(); if (!response.ok) throw new Error(result.message); photoCount = result.count; }
		catch (failure) { issue = failure instanceof Error ? failure.message : 'Could not load completion details.'; }
		finally { loading = false; }
	}
	function clearPreviews() { previews.forEach(url => URL.revokeObjectURL(url)); previews = []; }
	function choose(event: Event) {
		const field = event.currentTarget as HTMLInputElement;
		const next = [...files, ...Array.from(field.files ?? [])]; field.value = '';
		if (next.length > 3 || next.some(file => file.size > 4194304 || !['image/jpeg', 'image/png', 'image/webp'].includes(file.type))) {
			issue = 'Choose up to three JPEG, PNG or WebP photos, no more than 4 MB each.'; return;
		}
		clearPreviews(); files = next; previews = files.map(file => URL.createObjectURL(file)); uploaded = []; issue = '';
	}
	function remove(index: number) { clearPreviews(); files = files.filter((_, i) => i !== index); previews = files.map(file => URL.createObjectURL(file)); uploaded = []; }
	async function execute(method: string, body: BodyInit) {
		const response = await fetch(method === 'PUT' ? photoUrl : resolve('/api/completion'), { method,
			headers: { accept: 'application/json', 'content-type': method === 'PUT' ? 'application/octet-stream' : 'application/json' }, body });
		const result = await response.json(); if (!response.ok) throw new Error(result.message ?? 'Could not save completion.'); return result;
	}
	async function submit(event: SubmitEvent) {
		event.preventDefault(); if (busy || price === undefined || !files.length) return; busy = true; issue = '';
		try {
			for (let i = uploaded.length; i < files.length; i++) uploaded = [...uploaded, (await execute('PUT', files[i])).path];
			await execute('POST', JSON.stringify({ booking: bookingId, priceCentavos: Math.round(price * 100), photos: uploaded, note }));
			photoCount = uploaded.length; onSaved();
		} catch (failure) { issue = failure instanceof Error ? failure.message : 'Could not complete booking.'; }
		finally { busy = false; }
	}
	onMount(() => { price = initialPrice; void read(); }); onDestroy(clearPreviews);
</script>
{#if loading}<p role="status">Loading completion details…</p>
{:else if photoCount}
	<h3>Completion photos</h3><div class="photo-grid">{#each Array.from({ length: photoCount }) as _, index}
		<a href={photoUrl + '&photo=' + index} target="_blank" rel="noreferrer"><img src={photoUrl + '&photo=' + index} alt={'Completion photo ' + (index + 1)} /></a>
	{/each}</div>
{:else}
	<form class="stack" onsubmit={submit}>
		<h3>Complete service</h3>
		<label>Final service price (₱)<input type="number" min="0" step=".01" bind:value={price} required disabled={busy} /></label>
		<label>Private completion note (optional)<textarea bind:value={note} maxlength="500" rows="3" disabled={busy}></textarea></label>
		<input class="sr-only" type="file" bind:this={camera} accept="image/jpeg,image/png,image/webp" capture="environment" onchange={choose} disabled={busy} />
		<input class="sr-only" type="file" bind:this={album} accept="image/jpeg,image/png,image/webp" multiple onchange={choose} disabled={busy} />
		<div class="row"><button type="button" class="btn sm ghost" disabled={busy} onclick={() => camera?.click()}><ActionIcon name="add" />Take photo</button><button type="button" class="btn sm ghost" disabled={busy} onclick={() => album?.click()}><ActionIcon name="add" />Choose photos</button></div>
		<p class="small muted">One to three private photos, up to 4 MB each. Share them with the customer separately after completion.</p>
		<div class="photo-grid">{#each previews as url, index}<div><img src={url} alt={'Selected photo ' + (index + 1)} /><button type="button" class="btn sm ghost" disabled={busy} onclick={() => remove(index)}>Remove photo {index + 1}</button></div>{/each}</div>
		{#if busy}<p role="status">Saved {uploaded.length} of {files.length} photos…</p>{/if}
		<div class="row"><button class="btn sm" disabled={busy || !files.length}>{busy ? 'Saving…' : 'Complete service'}</button>{#if onClose}<button type="button" class="btn sm ghost" disabled={busy} onclick={onClose}>Go back</button>{/if}</div>
	</form>
{/if}
{#if issue}<p role="alert">{issue}</p>{#if !files.length && !photoCount}<button class="btn sm ghost" onclick={read}>Try again</button>{/if}{/if}
<style>.photo-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(120px,1fr));gap:.65rem}.photo-grid img{width:100%;max-height:180px;object-fit:contain;background:var(--panel-2);border-radius:6px}</style>
