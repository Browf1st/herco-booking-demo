<script lang="ts">
	import { onMount, tick } from 'svelte';
 import ActionIcon from '#lib/shared/ActionIcon.svelte';
	import { resolve } from '$app/paths';

	type Role = 'staff' | 'admin' | 'restricted_admin';
	type Grant = { page: string; key: string; label: string };
	type Draft = { name: string; email: string; role: Role; enabled: boolean; pages: string[]; actions: string[] };
	type Member = Draft & { userId: string; revision: number };
	type StaffAccess = { pages: string[]; actions: Grant[]; members: Member[] };
	const roleLabels: Record<Role, string> = { staff: 'Staff', admin: 'Admin', restricted_admin: 'Restricted Admin' };
	const enabled = import.meta.env.MODE === 'worker';
	const url = resolve('/api/staff-access');
	const emptyDraft = (): Draft => ({ name: '', email: '', role: 'staff', enabled: true, pages: [], actions: [] });
	let data = $state<StaffAccess>();
	let member = $state<Member>();
	let draft = $state<Draft>(emptyDraft());
	let showForm = $state(false);
 let editor = $state<HTMLDialogElement>();
 let previewDialog: HTMLDialogElement;
 let preview = $state<Member>();
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
			name: selected.name, email: selected.email, role: selected.role, enabled: selected.enabled,
			pages: [...selected.pages], actions: [...selected.actions]
		} : emptyDraft();
		message = success = '';
		showForm = true; void tick().then(() => editor?.showModal());
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
<section class="wrap section stack"><div class="row between"><h1>Staff Access</h1>{#if data}<button class="btn sm" onclick={()=>edit()}><ActionIcon name="add"/>Add account</button>{/if}</div>
{#if loading}<p role="status">Checking staff access…</p>{/if}{#if success}<p role="status">{success}</p>{/if}{#if message}<p role="alert">{message}</p>{/if}
{#if needsReload}<button class="btn sm ghost" onclick={()=>{editor?.close();showForm=false;void load();}}>Reload latest access</button>{/if}
{#if authRequired}<a class="btn" href={resolve('/account')}>Sign in with your account</a>{:else if !loading&&!data}<button class="btn sm ghost" onclick={load}>Try again</button>{:else if data}
<p class="muted">Manage the pages and actions available to verified staff accounts.</p>
{#each data.members as account(account.userId)}<article class="card row between"><div><h3>{account.name}</h3><p>{account.email}</p><p class="small muted">{roleLabels[account.role]} · {account.enabled?'Active':'Disabled'}</p><p class="small">{account.pages.join(' · ')||'No page access'}</p></div><div class="row">{#if account.enabled}<button class="btn sm ghost" onclick={()=>{preview=account;previewDialog.showModal();}} aria-label={'Preview access for '+account.name}>Preview access</button>{/if}<button class="btn sm ghost" onclick={()=>edit(account)} aria-label={'Edit access for '+account.name}><ActionIcon name="edit"/>Edit access</button></div></article>{:else}<p>No staff accounts within your access scope.</p>{/each}
{/if}
</section>
{#if showForm&&data}<dialog bind:this={editor} aria-labelledby="staff-editor-title"><form class="stack" onsubmit={save}><div class="row between"><h3 id="staff-editor-title">{member?'Edit staff access':'Add staff account'}</h3><button class="close-dialog" type="button" aria-label="Close staff access popup" onclick={()=>editor?.close()}><ActionIcon name="close"/></button></div><p class="small muted">The person needs an existing, verified HERCO account.</p><div class="cols"><label>Full name<input bind:value={draft.name} required maxlength="120"/></label><label>Email<input type="email" bind:value={draft.email} readonly={!!member} required maxlength="254"/></label><label>Role<select bind:value={draft.role}><option value="staff">Staff</option><option value="admin">Admin</option><option value="restricted_admin">Restricted Admin</option></select></label><label>Status<select bind:value={draft.enabled}><option value={true}>Active</option><option value={false}>Disabled</option></select></label></div>
<fieldset class="stack" disabled={busy}><legend>Pages</legend><div class="row"><button class="btn sm ghost" type="button" disabled={draft.pages.length===data.pages.length} onclick={()=>draft.pages=[...data!.pages]}>Select all</button><button class="btn sm ghost" type="button" disabled={!draft.pages.length} onclick={()=>{draft.pages=[];draft.actions=[];}}>Clear all</button></div><div class="choices">{#each data.pages as page(page)}<label class="choice"><input type="checkbox" checked={draft.pages.includes(page)} onchange={e=>togglePage(page,e.currentTarget.checked)}/>{page}</label>{/each}</div></fieldset>
<fieldset class="stack" disabled={busy}><legend>Actions</legend><div class="row"><button class="btn sm ghost" type="button" onclick={()=>draft.actions=data!.actions.filter(a=>draft.pages.includes(a.page)).map(a=>a.key)}>Select all</button><button class="btn sm ghost" type="button" disabled={!draft.actions.length} onclick={()=>draft.actions=[]}>Clear all</button></div><div class="choices">{#each data.actions.filter(a=>draft.pages.includes(a.page)) as action(action.key)}<label class="choice"><input type="checkbox" checked={draft.actions.includes(action.key)} onchange={e=>toggleAction(action.key,e.currentTarget.checked)}/>{action.label}</label>{:else}<p class="small muted">Select a page to see its actions.</p>{/each}</div></fieldset>
{#if message}<p role="alert">{message}</p>{/if}<div class="row"><button class="btn sm ghost" type="button" onclick={()=>editor?.close()}>Cancel</button><button class="btn sm" disabled={busy||needsReload}><ActionIcon name="save"/>Save access</button></div></form></dialog>{/if}
<dialog bind:this={previewDialog} aria-labelledby="preview-title"><div class="stack"><div class="row between"><h3 id="preview-title">Access preview</h3><button class="close-dialog" aria-label="Close access preview" onclick={()=>previewDialog.close()}><ActionIcon name="close"/></button></div>{#if preview}<p><strong>{preview.name}</strong> · {roleLabels[preview.role]}</p><p class="small muted">Read-only preview. Your signed-in identity and permissions have not changed.</p><h4>Pages</h4><ul>{#each preview.pages as page}<li>{page}</li>{:else}<li>No page access</li>{/each}</ul><h4>Actions</h4><ul>{#each preview.actions as key}<li>{data?.actions.find(a=>a.key===key)?.label??key}</li>{:else}<li>No actions</li>{/each}</ul>{/if}<button class="btn sm ghost" onclick={()=>previewDialog.close()}>Close preview</button></div></dialog>
<style>.between{justify-content:space-between}.choices{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:.65rem}.choice{display:flex;gap:.5rem;align-items:start}.choice input{width:auto;margin-top:.2rem}fieldset{min-width:0;border:1px solid var(--line);border-radius:.4rem;padding:.8rem}legend{font-weight:700;padding-inline:.35rem}dialog{width:min(760px,calc(100vw - 32px));max-height:calc(100dvh - 48px);padding:24px;overflow:auto;border:1px solid var(--line);border-radius:12px;background:var(--panel);color:var(--text)}dialog::backdrop{background:#000b}.close-dialog{display:grid;place-items:center;width:40px;height:40px;border:1px solid var(--line);border-radius:50%;background:var(--panel-2);color:var(--text)}@media(max-width:560px){.choices{grid-template-columns:1fr}}</style>
