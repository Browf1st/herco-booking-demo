<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';

	type Role = 'staff' | 'admin' | 'restricted_admin';
	type Grant = { page: string; key: string; label: string };
	type Draft = { email: string; role: Role; enabled: boolean; pages: string[]; actions: string[] };
	type Member = Draft & { userId: string; revision: number };
	type StaffAccess = { pages: string[]; actions: Grant[]; members: Member[] };
	const roleLabels: Record<Role, string> = { staff: 'Staff', admin: 'Admin', restricted_admin: 'Restricted Admin' };
	const enabled = import.meta.env.MODE === 'worker';
	const url = resolve('/api/staff-access');
	const emptyDraft = (): Draft => ({ email: '', role: 'staff', enabled: true, pages: [], actions: [] });
	let data = $state<StaffAccess>();
	let member = $state<Member>();
	let draft = $state<Draft>(emptyDraft());
	let showForm = $state(false);
	let loading = $state(true);
	let busy = $state(false);
	let message = $state('');
	let success = $state('');
	let authRequired = $state(false);
	let needsReload = $state(false);

	async function responseMessage(response: Response) {
		const body = await response.json().catch(() => null);
		return typeof body?.message === 'string' ? body.message : 'Staff access is temporarily unavailable. Try again.';
	}

	async function load() {
		loading = true;
		message = '';
		authRequired = false;
		needsReload = false;
		try {
			const response = await fetch(url, { headers: { accept: 'application/json' } });
			if (!response.ok) {
				authRequired = response.status === 401 || response.status === 403;
				if (authRequired) { data = undefined; showForm = false; member = undefined; draft = emptyDraft(); }
				throw new Error(await responseMessage(response));
			}
			data = await response.json();
		} catch (failure) {
			message = failure instanceof Error && failure.name !== 'TypeError'
				? failure.message : 'Could not reach the staff account service. Try again.';
		} finally {
			loading = false;
		}
	}

	function edit(selected?: Member) {
		member = selected;
		draft = selected ? {
			email: selected.email, role: selected.role, enabled: selected.enabled,
			pages: [...selected.pages], actions: [...selected.actions]
		} : emptyDraft();
		message = success = '';
		showForm = true;
	}

	function togglePage(page: string, checked: boolean) {
		if (checked) draft.pages = [...draft.pages, page];
		else {
			draft.pages = draft.pages.filter(value => value !== page);
			draft.actions = draft.actions.filter(action => data?.actions.some(item => item.key === action && draft.pages.includes(item.page)));
		}
	}

	function toggleAction(action: string, checked: boolean) {
		draft.actions = checked ? [...draft.actions, action] : draft.actions.filter(value => value !== action);
	}

	async function save(event: SubmitEvent) {
		event.preventDefault();
		if (busy) return;
		busy = true;
		message = success = '';
		try {
			const response = await fetch(url, {
				method: 'POST',
				headers: { accept: 'application/json', 'content-type': 'application/json' },
				body: JSON.stringify({ ...draft, targetId: member?.userId, revision: member?.revision })
			});
			if (!response.ok) {
				authRequired = response.status === 401 || response.status === 403;
				needsReload = response.status === 409;
				if (authRequired) { data = undefined; showForm = false; member = undefined; draft = emptyDraft(); }
				throw new Error(await responseMessage(response));
			}
			showForm = false;
			member = undefined;
			draft = emptyDraft();
			success = 'Staff access saved.';
			await load();
		} catch (failure) {
			message = failure instanceof Error && failure.name !== 'TypeError'
				? failure.message : 'Could not reach the staff account service. Try again.';
		} finally {
			busy = false;
		}
	}

	onMount(() => { if (enabled) void load(); });
</script>

<svelte:head><title>Staff access | HERCO</title></svelte:head>
<section class="wrap stack section">
	<h1>Staff access</h1>
	{#if !enabled}
		<p>Staff access management is available in the server-backed app.</p>
	{:else}
		<div><a class="btn ghost" href={resolve('/admin')}>Back to staff workspace</a></div>
		{#if loading}<p role="status">Checking staff access…</p>{/if}
		{#if success}<p role="status">{success}</p>{/if}
		{#if message}<p role="alert">{message}</p>{/if}
		{#if needsReload}
			<div><button type="button" class="btn ghost" onclick={() => { showForm = false; member = undefined; draft = emptyDraft(); void load(); }}>Reload latest access</button></div>
		{/if}
		{#if authRequired}
			<div><a class="btn" href={resolve('/account')}>Sign in or verify your account</a></div>
		{:else if !loading && !data}
			<div><button type="button" class="btn ghost" onclick={load}>Try again</button></div>
		{:else if data}
			{#if showForm}
				<form class="card stack" onsubmit={save}>
					<h2>{member ? 'Edit staff access' : 'Grant staff access'}</h2>
					{#if member}
						<p><strong>{member.email}</strong></p>
					{:else}
						<p>The person needs an existing, verified HERCO account.</p>
						<label>Account email <input type="email" bind:value={draft.email} maxlength="254" autocomplete="off" required disabled={busy} /></label>
					{/if}
					<label>Role
						<select bind:value={draft.role} disabled={busy}>
							{#each Object.entries(roleLabels) as [value, label]}<option {value}>{label}</option>{/each}
						</select>
					</label>
					<label class="option"><input type="checkbox" bind:checked={draft.enabled} disabled={busy} /> Access enabled</label>
					<fieldset class="stack" disabled={busy}>
						<legend>Pages and actions</legend>
						{#each data.pages as page (page)}
							<div class="page-options">
								<label class="option">
									<input type="checkbox" checked={draft.pages.includes(page)} onchange={event => togglePage(page, event.currentTarget.checked)} />
									<strong>{page}</strong>
								</label>
								{#if draft.pages.includes(page)}
									{#each data.actions.filter(action => action.page === page) as action (action.key)}
										<label class="option action">
											<input type="checkbox" checked={draft.actions.includes(action.key)} onchange={event => toggleAction(action.key, event.currentTarget.checked)} />
											{action.label}
										</label>
									{/each}
								{/if}
							</div>
						{:else}<p>Your account has no delegable page grants.</p>{/each}
					</fieldset>
					<div class="row">
						<button class="btn" type="submit" disabled={busy || needsReload}>{busy ? 'Saving…' : 'Save staff access'}</button>
						<button class="btn ghost" type="button" disabled={busy} onclick={() => { showForm = false; message = ''; }}>Cancel</button>
					</div>
				</form>
			{:else}
				<div><button class="btn" type="button" onclick={() => edit()} disabled={busy || loading}>Grant access</button></div>
				{#each data.members as entry (entry.userId)}
					<article class="card stack">
						<div class="row">
							<h2>{entry.email}</h2>
							<span class="badge">{roleLabels[entry.role]} · {entry.enabled ? 'Enabled' : 'Disabled'}</span>
						</div>
						<p>{entry.pages.length ? entry.pages.join(' · ') : 'No page access'}</p>
						<div><button class="btn ghost" type="button" onclick={() => edit(entry)} disabled={busy || loading}>Edit access</button></div>
					</article>
				{:else}<p>No staff accounts within your access scope.</p>{/each}
			{/if}
		{/if}
	{/if}
</section>

<style>
	h2 { font-size: 1.3rem; overflow-wrap: anywhere; }
	fieldset { min-inline-size: 0; }
	.option { display: flex; align-items: start; gap: .5rem; }
	.action { padding-inline-start: 1.5rem; }
	.option input { margin-block-start: .25rem; inline-size: auto; }
</style>
