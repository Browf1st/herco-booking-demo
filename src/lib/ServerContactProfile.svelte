<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	const endpoint = resolve('/api/auth/contact');
	let name = $state('');
	let mobile = $state('');
	let ready = $state(false);
	let busy = $state(false);
	let message = $state('');
	let notice = $state('');

	async function load() {
		busy = true;
		message = '';
		try {
			const response = await fetch(endpoint);
			if (!response.ok) throw new Error();
			const data = await response.json();
			name = data.name;
			mobile = data.mobile;
			ready = true;
		} catch { message = 'Your profile is temporarily unavailable.'; }
		finally { busy = false; }
	}

	async function save(event: SubmitEvent) {
		event.preventDefault();
		if (busy) return;
		busy = true;
		message = notice = '';
		try {
			const response = await fetch(endpoint, {
				method: 'PUT',
				headers: { 'content-type': 'application/json', accept: 'application/json' },
				body: JSON.stringify({ name, mobile })
			});
			const data = await response.json().catch(() => null);
			if (!response.ok || !data) throw new Error(data?.message ?? 'Could not save your profile.');
			name = data.name;
			mobile = data.mobile;
			notice = 'Contact details saved.';
		} catch (error) { message = error instanceof Error ? error.message : 'Could not save your profile.'; }
		finally { busy = false; }
	}
	onMount(() => { void load(); });
</script>

<section class="card stack">
	<h2>Booking contact details</h2>
	{#if message}<p role="alert">{message}</p>{/if}
	{#if notice}<p role="status">{notice}</p>{/if}
	{#if ready}
		<form class="stack" onsubmit={save}>
			<label>Full name<input bind:value={name} autocomplete="name" maxlength="120" disabled={busy} /></label>
			<label>Mobile number<input type="tel" bind:value={mobile} autocomplete="tel" maxlength="21" disabled={busy} /></label>
			<p class="small muted">We’ll prefill these details when you book a visit.</p>
			<div><button class="btn sm ghost" disabled={busy}>Save contact details</button></div>
		</form>
	{:else if busy}
		<p role="status">Loading contact details…</p>
	{:else}
		<div><button class="btn sm ghost" onclick={load}>Try again</button></div>
	{/if}
</section>
