<script lang="ts">
	import OutsideHoursWarning from './OutsideHoursWarning.svelte';
	import { closeOptions, closeText, hoursIssue, hourText, openOptions, type DateAction, type DayInfo, type Needs } from './schedule-hours';

	let { day, canManage, act }: {
		day: DayInfo; canManage: boolean; act: (action: DateAction, confirmOutside: boolean, confirmedCount?: number) => Promise<Needs | undefined>;
	} = $props();

	type Choice = 'default' | 'closed' | 'own';
	const current = $derived<Choice>(day.closed ? 'closed' : day.ownOpen !== null ? 'own' : 'default');
	let picked = $state<Choice>();
	// The own-hours lists start from the date's current hours; the window is reloaded for each date.
	// svelte-ignore state_referenced_locally
	let ownOpen = $state(day.ownOpen ?? day.openHour ?? 9);
	// svelte-ignore state_referenced_locally
	let ownClose = $state(day.ownClose ?? day.closeHour ?? 17);
	let busy = $state(false);
	let outside = $state<Needs>();
	let moreOutside = $state(false);
	let failure = $state('');
	let retry = $state<() => void>();

	const choice = $derived(picked ?? current);
	const readonly = $derived(!canManage || day.past || busy);
	const ownIssue = $derived(hoursIssue(ownOpen, ownClose));
	const hasChoice = $derived(day.override !== null || day.ownOpen !== null);
	const choices: { id: Choice; label: string }[] = [
		{ id: 'default', label: 'Use default hours' }, { id: 'closed', label: 'Closed' }, { id: 'own', label: 'Own hours for this date' }
	];

	async function run(action: DateAction, confirmOutside = false) {
		if (busy) return;
		busy = true;
		failure = '';
		retry = () => void run(action, confirmOutside);
		try {
			const confirmedCount = confirmOutside ? outside?.count : undefined;
			outside = await act(action, confirmOutside, confirmedCount);
			moreOutside = confirmOutside && Boolean(outside);
			if (!outside) picked = undefined;
		} catch (error) {
			failure = error instanceof Error && error.message ? error.message : "Couldn't save. Try again.";
		} finally {
			busy = false;
		}
	}

	function choose(next: Choice) {
		outside = undefined;
		picked = next;
		if (next === 'closed' && current !== 'closed') void run({ action: 'close_date' });
		if (next === 'default' && current !== 'default') void run({ action: 'open_date' });
	}
</script>

<section class="stack date-panel" aria-labelledby="date-hours-title">
	<h4 id="date-hours-title">This date</h4>
	{#if day.past}<p class="small muted">Past dates can't be changed.</p>
	{:else if !canManage}<p class="small muted">You can see this date but not change it.</p>{/if}
	<div class="choices" role="radiogroup" aria-label="Hours for this date">
		{#each choices as item (item.id)}
			<label class="tick"><input type="radio" name="date-hours" checked={choice === item.id} disabled={readonly} onchange={() => choose(item.id)} />{item.label}</label>
		{/each}
	</div>
	{#if choice === 'own'}
		<div class="hour-pair">
			<label>Opens at<select bind:value={ownOpen} disabled={readonly}>{#each openOptions as hour (hour)}<option value={hour}>{hourText(hour)}</option>{/each}</select></label>
			<label>Closes at<select bind:value={ownClose} disabled={readonly}>{#each closeOptions as hour (hour)}<option value={hour}>{closeText(hour)}</option>{/each}</select></label>
		</div>
		{#if ownIssue}<p class="small error" role="alert">{ownIssue}</p>{/if}
		{#if outside}
			<OutsideHoursWarning bookings={outside.bookings} count={outside.count} more={moreOutside} {busy} onconfirm={() => run({ action: 'set_date_hours', openHour: ownOpen, closeHour: ownClose }, true)} onback={() => { outside = undefined; moreOutside = false; }} />
		{:else if !readonly}
			<div><button type="button" class="btn sm" disabled={Boolean(ownIssue)} onclick={() => run({ action: 'set_date_hours', openHour: ownOpen, closeHour: ownClose })}>Save hours</button></div>
		{/if}
	{/if}
	<div class="hours">
		<h5>Hours on this date</h5>
		{#if day.hours.length}
			<ul>
				{#each day.hours as row (row.hour)}
					<li><label class="tick"><input type="checkbox" checked={!row.blocked} disabled={readonly || row.status === 'past'}
						onclick={(event) => { event.preventDefault(); void run({ action: row.blocked ? 'unblock_slot' : 'block_slot', hour: row.hour }); }} />
						<span>{hourText(row.hour)}</span>
						{#if row.status === 'past'}<span class="small muted">Past slot</span>{/if}
						{#if row.booked}<span class="small booked">{row.booked} booked</span>{/if}</label></li>
				{/each}
			</ul>
			<p class="small muted">Tick = customers can book it.</p>
		{:else}<p class="small muted">{day.closed ? 'Closed on this date. There are no hours to show.' : 'No hours left on this date.'}</p>{/if}
	</div>
	{#if hasChoice && !readonly}
		<div><button type="button" class="btn sm ghost" onclick={() => run({ action: 'restore_date' })}>Restore default</button></div>
	{/if}
	{#if busy}<p class="small muted" role="status">Saving…</p>{/if}
	{#if failure}<p class="small error" role="alert">{failure} <button type="button" class="btn sm ghost" onclick={() => retry?.()}>Try again</button></p>{/if}
</section>

<style>
	.date-panel { gap: .6rem; padding: .7rem; border: 1px solid var(--line); border-radius: 8px; background: var(--panel-2); }
	h4, h5 { margin: 0; font-size: .95rem; }
	h5 { font-size: .85rem; }
	.choices { display: grid; gap: .35rem; }
	.hour-pair { display: grid; grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr)); gap: .6rem; }
	.tick { display: flex; align-items: center; gap: .5rem; min-height: 44px; padding-inline: .6rem; border: 1px solid var(--line); border-radius: 6px; background: var(--panel); cursor: pointer; }
	.tick input { width: 1.25rem; height: 1.25rem; margin: 0; accent-color: var(--accent); }
	ul { display: grid; gap: .35rem; margin: .4rem 0; padding: 0; list-style: none; }
	.booked { margin-inline-start: auto; color: var(--accent); font-weight: 700; }
</style>
