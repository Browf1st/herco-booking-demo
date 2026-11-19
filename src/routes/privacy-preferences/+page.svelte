<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	const worker = import.meta.env.MODE === 'worker';
	let settings = $state<{ enabled: boolean; status: 'on' | 'off' | 'unset' }>();
	let message = $state('');
	let notice = $state('');
	let busy = $state(false);

	async function load() {
		try {
			const response = await fetch(resolve('/api/analytics'));
			if (!response.ok) throw new Error();
			settings = await response.json();
		} catch { message = 'Analytics preferences are temporarily unavailable.'; }
	}

	async function choose(choice: 'allow' | 'decline') {
		busy = true;
		message = notice = '';
		try {
			const response = await fetch(resolve('/api/analytics'), { method: 'PUT', body: choice });
			if (!response.ok) throw new Error();
			await load();
			notice = 'Preference saved.';
		} catch { message = 'Could not save your preference. Please try again.'; }
		finally { busy = false; }
	}
	onMount(() => { if (worker) void load(); });
</script>

<svelte:head><title>Privacy preferences | HERCO</title></svelte:head>
<section class="section wrap stack">
	<h1>Privacy preferences</h1>
	{#if settings?.enabled}
		<p>Optional analytics help HERCO understand how people use booking. They send basic events and a random browser identifier.</p>
		<p>Analytics are {settings.status === 'on' ? 'on' : 'off'} for this browser.</p>
		<div class="row"><button class="btn sm" disabled={busy} onclick={() => choose('allow')}>Allow analytics</button>
			<button class="btn sm ghost" disabled={busy} onclick={() => choose('decline')}>Turn analytics off</button></div>
	{:else if settings || !worker}
		<p>Analytics are currently off.</p>
	{:else if !message}
		<p role="status">Loading preferences…</p>
	{/if}
	{#if message}<p role="alert">{message}</p>{/if}
	{#if notice}<p role="status">{notice}</p>{/if}
</section>
