<script lang="ts">
 import { goto } from '$app/navigation';
 import { resolve } from '$app/paths';
 import { availableStaffActions, saveStaffAccount, staffAccess, staffActions, staffPages, switchStaffSession, type StaffAccount } from './staffAccess.svelte.ts';

 const blank = (): StaffAccount => ({ id: '', name: '', email: '', role: 'Staff', enabled: true, pages: [], actions: [] });
 let draft = $state(blank());
 let editor: HTMLDialogElement;
 let error = $state('');
 let notice = $state('');
 let previewError = $state('');
 const visibleActions = $derived(availableStaffActions(draft.pages));

 function setPages(pages: string[]) {
  const allowedActions = availableStaffActions(pages);
  draft.pages = pages;
  draft.actions = draft.actions.filter(action => allowedActions.includes(action));
 }

 async function preview(account: StaffAccount) {
  previewError = '';
  try {
   switchStaffSession(account.id);
   await goto(resolve('/admin'));
  } catch (cause) {
   previewError = cause instanceof Error ? cause.message : 'Could not preview this account.';
  }
 }

 function open(account?: StaffAccount) {
  draft = account ? { ...account, pages: [...account.pages], actions: [...account.actions] } : blank();
  error = '';
  editor.showModal();
 }

 function save(event: SubmitEvent) {
  event.preventDefault();
  error = '';
  const saved = $state.snapshot(draft);
  saved.actions = saved.actions.filter(action => visibleActions.includes(action));
  try {
   saveStaffAccount(saved);
   notice = 'Saved access settings for ' + saved.name.trim() + '.';
   editor.close();
  } catch (cause) {
   error = cause instanceof Error ? cause.message : 'Could not save these settings in this browser.';
  }
 }
</script>

<section class="stack">
 <div class="row heading">
  <h2>Staff Access</h2>
  <button type="button" class="btn sm" onclick={() => open()}>Add account</button>
 </div>
 <p class="muted">Choose which pages each account can open and which actions it can take. Preview an active account to try its permissions. Select Owner view to return.</p>
 {#if notice}<p role="status">{notice}</p>{/if}
 {#if previewError}<p class="error" role="alert">{previewError}</p>{/if}
 {#each staffAccess.accounts as account (account.id)}
  <article class="card stack">
   <div class="row heading">
    <div><strong>{account.name}</strong><p class="small muted">{account.email}</p></div>
    <div class="row">
     {#if account.enabled}<button type="button" class="btn sm ghost" onclick={() => preview(account)} aria-label={'Preview access for ' + account.name}>Preview access</button>{/if}
     <button type="button" class="btn sm ghost" onclick={() => open(account)} aria-label={'Edit access for ' + account.name}>Edit access</button>
    </div>
   </div>
   <p><span class="badge">{account.role}</span> <span class="badge" data-status={account.enabled ? 'done' : 'cancelled'}>{account.enabled ? 'Active' : 'Disabled'}</span></p>
   <dl class="access-summary">
    <div><dt>Pages</dt><dd>{account.pages.length ? account.pages.join(' · ') : 'No pages assigned'}</dd></div>
    <div><dt>Actions</dt><dd>{account.actions.length ? account.actions.map(action => staffActions[action].label).join(' · ') : 'No actions assigned'}</dd></div>
   </dl>
  </article>
 {:else}
  <p class="card muted">No admin or staff accounts yet. Select Add account to set up access.</p>
 {/each}
</section>

<dialog bind:this={editor} aria-labelledby="staff-editor-title">
 <form class="stack" onsubmit={save}>
  <h3 id="staff-editor-title">{draft.id ? 'Edit staff access' : 'Add staff account'}</h3>
  <div class="cols">
   <label>Full name<input bind:value={draft.name} required maxlength="80" /></label>
   <label>Email<input type="email" bind:value={draft.email} required maxlength="254" /></label>
   <label>Role<select bind:value={draft.role}><option>Staff</option><option>Admin</option></select></label>
   <label>Status<select bind:value={draft.enabled}><option value={true}>Active</option><option value={false}>Disabled</option></select></label>
  </div>
  <fieldset>
   <legend>Page access</legend>
   <div class="row bulk-controls">
    <button type="button" class="btn sm ghost" disabled={draft.pages.length === staffPages.length} onclick={() => setPages([...staffPages])}>Select all</button>
    <button type="button" class="btn sm ghost" disabled={!draft.pages.length} onclick={() => setPages([])}>Clear all</button>
   </div>
   <div class="cols">
    {#each staffPages as page (page)}
     <label class="choice"><input type="checkbox" checked={draft.pages.includes(page)} onchange={(event) => setPages(event.currentTarget.checked ? [...draft.pages, page] : draft.pages.filter(item => item !== page))} />{page}</label>
    {/each}
   </div>
  </fieldset>
  <fieldset>
   <legend>Allowed actions</legend>
   <div class="row bulk-controls">
    <button type="button" class="btn sm ghost" disabled={draft.actions.length === visibleActions.length} onclick={() => draft.actions = [...visibleActions]}>Select all</button>
    <button type="button" class="btn sm ghost" disabled={!draft.actions.length} onclick={() => draft.actions = []}>Clear all</button>
   </div>
   {#if visibleActions.length}
    <div class="cols">
     {#each visibleActions as action (action)}
      <label class="choice"><input type="checkbox" value={action} bind:group={draft.actions} />{staffActions[action].label}</label>
     {/each}
    </div>
   {:else}
    <p class="small muted">Select a page with editable actions to choose what this account can do.</p>
   {/if}
  </fieldset>
  {#if error}<p class="error" role="alert">{error}</p>{/if}
  <div class="row"><button type="button" class="btn sm ghost" onclick={() => editor.close()}>Cancel</button><button class="btn sm">Save access</button></div>
 </form>
</dialog>

<style>
 .heading { justify-content: space-between; }
 dialog { width: min(650px, calc(100% - 24px)); max-height: 90dvh; padding: 1rem; border: 1px solid var(--line); border-radius: 12px; background: var(--panel); color: var(--text); }
 dialog::backdrop { background: #0009; }
 fieldset { min-width: 0; margin: 0; border: 1px solid var(--line); border-radius: 6px; }
 .bulk-controls { margin-block: .15rem .45rem; }
 .choice { display: flex; align-items: center; gap: .5rem; min-height: 40px; }
 .choice input { flex: none; }
 .access-summary { display: grid; gap: .45rem; margin: 0; font-size: .85rem; }
 .access-summary dt { color: var(--muted); }
 .access-summary dd { margin: 0; }
</style>
