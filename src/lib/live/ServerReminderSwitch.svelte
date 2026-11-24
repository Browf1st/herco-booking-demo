<script lang="ts">
	// "Maintenance reminders" on/off switch for the Profile card (F-017). Saves as soon as it is toggled.
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	const endpoint = resolve('/api/account/reminders');
	let enabled = $state(true);
	let ready = $state(false);
	let busy = $state(false);
	let message = $state('');

	async function request(init?: RequestInit) {
		const response = await fetch(endpoint, { ...init, headers: { accept: 'application/json', 'content-type': 'application/json' } });
		const data = await response.json().catch(() => null);
		if (!response.ok || typeof data?.maintenance !== 'boolean') throw new Error();
		return data.maintenance as boolean;
	}

	async function load() {
		busy = true;
		message = '';
		try {
			enabled = await request();
			ready = true;
		} catch { message = 'Reminder settings are temporarily unavailable.'; }
		finally { busy = false; }
	}

	async function toggle(next: boolean) {
		if (busy) return;
		busy = true;
		message = '';
		try {
			enabled = await request({ method: 'PUT', body: JSON.stringify({ maintenance: next }) });
		} catch { message = 'Could not save your choice. Try again.'; }
		finally { busy = false; }
	}
	onMount(() => { void load(); });
</script>

<div class="reminders stack">
	{#if ready}
		<label class="choice">
			<input type="checkbox" role="switch" checked={enabled} disabled={busy} onchange={(event) => { const box = event.currentTarget; void toggle(box.checked).then(() => { box.checked = enabled; }); }} />
			Maintenance reminders
		</label>
		<p class="small muted" role="status">{busy ? 'Saving…' : enabled ? 'On: we email you 6 months after a finished job. Booking emails are not affected.' : 'Off: no reminder emails. Booking emails keep coming.'}</p>
	{:else if busy}
		<p class="small muted" role="status">Loading reminder settings…</p>
	{/if}
	{#if message}<p role="alert">{message}</p>{/if}
	{#if !ready && !busy}<div><button class="btn sm ghost" type="button" onclick={load}>Try again</button></div>{/if}
</div>

<style>
	.reminders { border-top: 1px solid var(--line); padding-top: 1rem; }
	.choice { display: flex; align-items: center; gap: .6rem; min-height: 44px; font-weight: 650; }
	.choice input { width: auto; margin: 0; }
</style>
