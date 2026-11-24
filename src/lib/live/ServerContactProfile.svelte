<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import ActionIcon from '../shared/ActionIcon.svelte';
	import type { Component } from 'svelte';
	// Loaded after the profile appears, to keep the Account page's first download small.
	let ReminderSwitch = $state<Component>();
	const endpoint = resolve('/api/auth/contact');
	let name = $state('');
	let mobile = $state('');
	let email = $state('');
	let provider = $state('Email');
	let leaderboardOptIn = $state(false);
	let leaderboardAlias = $state('');
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
			email = data.email;
			provider = data.provider === 'google' ? 'Google' : data.provider === 'facebook' ? 'Facebook' : 'Email';
			leaderboardOptIn = data.leaderboardOptIn;
			leaderboardAlias = data.leaderboardAlias;
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
				body: JSON.stringify({ name, mobile, leaderboardOptIn, leaderboardAlias })
			});
			const data = await response.json().catch(() => null);
			if (!response.ok || !data) throw new Error(data?.message ?? 'Could not save your profile.');
			name = data.name;
			mobile = data.mobile;
			notice = 'Profile saved.';
		} catch (error) { message = error instanceof Error ? error.message : 'Could not save your profile.'; }
		finally { busy = false; }
	}
	onMount(() => {
		void load();
		void import('./ServerReminderSwitch.svelte').then((module) => { ReminderSwitch = module.default; });
	});
</script>

<section class="card stack" aria-labelledby="profile-heading">
	<h2 id="profile-heading">Profile</h2>
	{#if message}<p role="alert">{message}</p>{/if}
	{#if notice}<p role="status">{notice}</p>{/if}
	{#if ready}
		<p>Signed in as <strong>{name || 'HERCO member'}</strong> via {provider}</p>
		<form class="stack" onsubmit={save}>
			<label>Email<input type="email" value={email} readonly /></label>
			<label>Full name<input bind:value={name} autocomplete="name" maxlength="120" disabled={busy} /></label>
			<label>Mobile number<input type="tel" bind:value={mobile} autocomplete="tel" maxlength="21" placeholder="e.g. 0917 000 0000" disabled={busy} /></label>
			<p class="muted">Your email and saved mobile number will prefill future bookings.</p>
			<details><summary>Rewards ranking privacy</summary><div class="stack ranking-options">
				<label class="choice"><input type="checkbox" bind:checked={leaderboardOptIn} disabled={busy} /> Show my chosen name in the rewards ranking</label>
				{#if leaderboardOptIn}<label>Ranking name<input bind:value={leaderboardAlias} maxlength="40" required disabled={busy} /></label>{/if}
				<p class="small muted">Other members only see this name and your points, never your email or phone.</p>
			</div></details>
			<div class="row"><button class="btn ghost" disabled={busy}><ActionIcon name="save" />Save profile</button></div>
		</form>
		{#if ReminderSwitch}<ReminderSwitch />{/if}
	{:else if busy}
		<p role="status">Loading contact details…</p>
	{:else}
		<div><button class="btn sm ghost" onclick={load}>Try again</button></div>
	{/if}
</section>

<style>
	#profile-heading { font: 750 1.25rem/1.2 var(--body); font-style: normal; text-transform: none; }
	.choice { display: flex; align-items: center; gap: .5rem; }
	.choice input { width: auto; }
	.ranking-options { padding-block: .75rem; }
</style>
