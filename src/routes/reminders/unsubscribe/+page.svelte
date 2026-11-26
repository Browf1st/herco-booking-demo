<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	// The link in the reminder email is /reminders/unsubscribe?token=... Opening it only shows a button, so link
	// scanners in email apps cannot unsubscribe anyone by accident. Only the button sends the token.
	type Step = 'loading' | 'missing' | 'confirm' | 'busy' | 'done' | 'invalid' | 'error';
	let step = $state<Step>('loading');
	let token = '';

	async function unsubscribe() {
		if (step === 'busy') return;
		step = 'busy';
		try {
			const response = await fetch(resolve('/api/reminders/unsubscribe'), {
				method: 'POST',
				headers: { accept: 'application/json', 'content-type': 'application/json' },
				body: JSON.stringify({ token })
			});
			step = response.ok ? 'done' : response.status === 400 ? 'invalid' : 'error';
		} catch {
			step = 'error';
		}
	}

	onMount(() => {

		token = page.url.searchParams.get('token') ?? '';
		step = token ? 'confirm' : 'missing';
	});
</script>

<svelte:head><title>Maintenance reminders | HERCO</title></svelte:head>
<section class="wrap section stack">
	<h1>Maintenance reminders</h1>
	{#if step === 'loading'}
		<p role="status">Loading…</p>
	{:else if step === 'missing'}
		<p role="alert">This link is incomplete. Open the unsubscribe link from your reminder email again, or sign in to change reminder settings in your Account.</p>
		<div><a class="btn ghost" href={resolve('/account')}>Go to Account</a></div>
	{:else if step === 'done'}
		<p role="status">You won't get maintenance reminders any more.</p>
		<p class="muted small">Booking emails keep coming. You can <a href={resolve('/account')}>turn them back on in your Account</a>.</p>
	{:else if step === 'invalid'}
		<p role="alert">This link doesn't work any more. Sign in to change reminder settings in your Account.</p>
		<div><a class="btn ghost" href={resolve('/account')}>Go to Account</a></div>
	{:else}
		<p>Stop maintenance reminder emails from HERCO? Booking emails will keep coming.</p>
		{#if step === 'error'}<p role="alert">We couldn't save that. Check your connection and try again.</p>{/if}
		<div><button class="btn" type="button" disabled={step === 'busy'} onclick={unsubscribe}>{step === 'busy' ? 'Unsubscribing…' : step === 'error' ? 'Try again' : 'Confirm unsubscribe'}</button></div>
	{/if}
</section>
