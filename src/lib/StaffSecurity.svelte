<script lang="ts">
	import { resolve } from '$app/paths';
	import { onMount } from 'svelte';

	let { busy = $bindable(false) }: { busy?: boolean } = $props();
	let access = $state<{ role?: string; pages: string[]; actions: string[] }>();
	let message = $state('');

	async function loadAccess() {
		busy = true;
		message = '';
		try {
			const response = await fetch(resolve('/api/staff/workspace'), { headers: { accept: 'application/json' } });
			if (response.status === 401 || response.status === 403) {
				access = undefined;
				return;
			}
			if (!response.ok) throw new Error('Could not check staff access. Try again.');
			access = await response.json();
		} catch {
			message = 'Could not check staff access. Try again.';
		} finally {
			busy = false;
		}
	}

	onMount(() => { void loadAccess(); });
</script>

{#if access || message}
	<section class="card stack" aria-labelledby="staff-access-heading">
		<h2 id="staff-access-heading">{access?.role === 'owner' ? 'Owner access' : access?.role === 'superadmin' ? 'Superadmin access' : 'Staff access'}</h2>
		{#if message}
			<p role="alert">{message}</p>
			<div><button class="btn ghost" type="button" disabled={busy} onclick={loadAccess}>Try again</button></div>
		{:else if access}
			<p>Your account has access to the sections shown in the main navigation.</p>
		{/if}
	</section>
{/if}
