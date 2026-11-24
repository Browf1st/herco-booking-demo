<script lang="ts">
	// The read-only "Access preview" card: who the person is, the pages they can open and the actions they can take.
	// It shows the same data as the Staff Access list and gives nobody new permissions.
	import ActionIcon from '../shared/ActionIcon.svelte';
	import { initials } from '../shared/report-ui';
	import { groupGrantedActions, type StaffGrant } from './staff-access-actions';

	type IconName = 'calendar' | 'ranking' | 'gift' | 'box' | 'edit' | 'history' | 'user' | 'send' | 'view';
	const pageIcons: Record<string, IconName> = {
		Reports: 'ranking', Bookings: 'calendar', 'Change requests': 'send', 'Booking history': 'history', Customers: 'user',
		'HERCO Points': 'gift', Inventory: 'box', Pricing: 'edit', 'Activity log': 'history', 'Staff Access': 'user'
	};
	let { name, role, pages, actions, grants }: { name: string; role: string; pages: string[]; actions: string[]; grants: StaffGrant[] } = $props();
	const groups = $derived(groupGrantedActions(grants, actions));
</script>

<article class="preview">
	<header>
		<span class="avatar" aria-hidden="true">{initials(name)}</span>
		<div><h4>{name}</h4><span class="role">{role}</span></div>
	</header>
	<p class="note" role="note"><ActionIcon name="view" />Read-only preview. Your signed-in identity and permissions have not changed.</p>
	<section aria-labelledby="preview-pages">
		<h5 id="preview-pages">Pages</h5>
		{#if pages.length}
			<ul class="pages">{#each pages as page}<li><ActionIcon name={pageIcons[page] ?? 'view'} />{page}</li>{/each}</ul>
		{:else}<p class="muted small">No page access</p>{/if}
	</section>
	<section aria-labelledby="preview-actions">
		<h5 id="preview-actions">Actions</h5>
		{#each groups as group (group.page)}
			<div class="group">
				<p class="group-name">{group.page}</p>
				<ul>{#each group.labels as label}<li class="tick"><span class="box" aria-hidden="true"><ActionIcon name="check" /></span>{label}</li>{/each}</ul>
			</div>
		{:else}<p class="muted small">No actions</p>{/each}
	</section>
</article>

<style>
	.preview { display: grid; gap: 1rem; min-width: 0; }
	header { display: flex; align-items: center; gap: .85rem; }
	.avatar { display: grid; place-items: center; flex: none; width: 3rem; height: 3rem; border-radius: 50%; background: var(--accent-fill); color: var(--accent-ink); font-weight: 800; }
	h4 { margin: 0; font-size: 1.15rem; overflow-wrap: anywhere; }
	.role { display: inline-block; margin-top: .2rem; padding: .1rem .6rem; border: 1px solid var(--line); border-radius: 99px; background: var(--panel-2); font-size: .75rem; font-weight: 700; }
	.note { display: flex; align-items: flex-start; gap: .5rem; margin: 0; padding: .6rem .75rem; border-radius: 8px; background: var(--info-bg); color: var(--info); font-size: .85rem; }
	section { display: grid; gap: .6rem; }
	h5 { margin: 0; color: var(--muted); font-size: .72rem; letter-spacing: .06em; text-transform: uppercase; }
	ul { display: grid; gap: .4rem; margin: 0; padding: 0; list-style: none; }
	.pages { grid-template-columns: repeat(auto-fill, minmax(10rem, 1fr)); }
	.pages li { display: flex; align-items: center; gap: .5rem; padding: .5rem .7rem; border: 1px solid var(--line); border-radius: 8px; background: var(--panel-2); font-size: .9rem; font-weight: 600; }
	.group { display: grid; gap: .35rem; padding: .7rem .8rem; border: 1px solid var(--line); border-radius: 10px; }
	.group-name { margin: 0; font-size: .85rem; font-weight: 800; }
	.tick { display: flex; align-items: flex-start; gap: .55rem; font-size: .9rem; }
	.box { display: grid; place-items: center; flex: none; width: 1.25rem; height: 1.25rem; margin-top: .05rem; border-radius: 5px; background: var(--ok-bg); color: var(--ok); font-size: .8rem; }
	@media (max-width: 560px) { .pages { grid-template-columns: 1fr; } }
</style>
