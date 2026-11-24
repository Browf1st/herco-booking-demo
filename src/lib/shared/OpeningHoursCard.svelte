<script lang="ts">
	import OutsideHoursWarning from './OutsideHoursWarning.svelte';
	import { closeOptions, closeText, hoursIssue, hourText, openOptions, slotPreview, weekdayChoices, type Needs, type ScheduleSettings } from './schedule-hours';
	import { ScheduleChanged } from './schedule-changed';

	let { settings, canManage, onsave, onreload }: {
		settings: ScheduleSettings; canManage: boolean;
		onsave: (values: ScheduleSettings, confirmOutside: boolean, confirmedCount?: number) => Promise<Needs | undefined>;
		onreload: () => Promise<ScheduleSettings>;
	} = $props();

	// The fields start from the loaded settings and then belong to the admin until saved.
	// svelte-ignore state_referenced_locally
	let saved = $state({ ...settings });
	// svelte-ignore state_referenced_locally
	let openHour = $state(settings.openHour);
	// svelte-ignore state_referenced_locally
	let closeHour = $state(settings.closeHour);
	// svelte-ignore state_referenced_locally
	let weekdays = $state([...settings.openWeekdays]);
	// svelte-ignore state_referenced_locally
	let version = $state(settings.version);
	let busy = $state(false);
	let outside = $state<Needs>();
	let moreOutside = $state(false);
	let notice = $state('');
	let failure = $state('');
	let changed = $state(false);

	const issue = $derived(hoursIssue(openHour, closeHour, weekdays));
	const unchanged = $derived(openHour === saved.openHour && closeHour === saved.closeHour &&
		weekdays.length === saved.openWeekdays.length && weekdays.every(day => saved.openWeekdays.includes(day)));

	function edited() { notice = failure = ''; outside = undefined; moreOutside = false; }

	async function save(confirmOutside: boolean) {
		if (busy || issue) return;
		busy = true;
		notice = failure = '';
		changed = false;
		try {
			const values = { openHour, closeHour, openWeekdays: [...weekdays].sort((a, b) => a - b), ...(version && { version }) };
			const confirmedCount = confirmOutside ? outside?.count : undefined;
			outside = await onsave(values, confirmOutside, confirmedCount);
			moreOutside = confirmOutside && Boolean(outside);
			if (!outside) {
				saved = values; notice = 'Opening hours saved';
				// The server gives the saved hours a new version; keep it so the next save is not refused.
				version = (await onreload().catch(() => undefined))?.version ?? version;
			}
		} catch (error) {
			if (error instanceof ScheduleChanged) changed = true;
			failure = error instanceof Error && error.message ? error.message : "Couldn't save. Try again.";
		} finally {
			busy = false;
		}
	}

	// Another admin changed the hours: load them again and clear the form.
	async function reload() {
		busy = true;
		try {
			const fresh = await onreload();
			saved = { ...fresh }; version = fresh.version;
			openHour = fresh.openHour; closeHour = fresh.closeHour; weekdays = [...fresh.openWeekdays];
			edited(); changed = false;
		} catch {
			failure = "Couldn't reload the hours. Try again.";
		} finally {
			busy = false;
		}
	}
</script>

<section class="stack hours-card" aria-labelledby="opening-hours-title">
	<h4 id="opening-hours-title">Opening hours</h4>
	{#if !canManage}<p class="small muted">You can see the opening hours but not change them.</p>{/if}
	<div class="hour-pair">
		<label>Opens at<select bind:value={openHour} onchange={edited} disabled={!canManage || busy}>{#each openOptions as hour (hour)}<option value={hour}>{hourText(hour)}</option>{/each}</select></label>
		<label>Closes at<select bind:value={closeHour} onchange={edited} disabled={!canManage || busy}>{#each closeOptions as hour (hour)}<option value={hour}>{closeText(hour)}</option>{/each}</select></label>
	</div>
	<fieldset class="days" disabled={!canManage || busy}>
		<legend class="small">Open days</legend>
		{#each weekdayChoices as { day, label } (day)}
			<label class="tick"><input type="checkbox" value={day} bind:group={weekdays} onchange={edited} />{label}</label>
		{/each}
	</fieldset>
	<p class="small muted" aria-live="polite">{issue ? '' : slotPreview(openHour, closeHour)}</p>
	{#if issue}<p class="small error" role="alert">{issue}</p>{/if}
	{#if outside}
		<OutsideHoursWarning bookings={outside.bookings} count={outside.count} more={moreOutside} {busy} onconfirm={() => save(true)} onback={edited} />
	{:else if canManage}
		<div><button type="button" class="btn sm" disabled={busy || unchanged || Boolean(issue)} onclick={() => save(false)}>{busy ? 'Saving…' : 'Save'}</button></div>
	{/if}
	{#if failure}<p class="small error" role="alert">{failure}{#if changed} <button type="button" class="btn sm ghost" disabled={busy} onclick={reload}>Reload</button>{/if}</p>{/if}
	{#if notice}<p class="small" role="status">{notice}</p>{/if}
</section>

<style>
	.hours-card { gap: .6rem; padding: .7rem; border: 1px solid var(--line); border-radius: 8px; background: var(--panel-2); }
	h4 { margin: 0; font-size: .95rem; }
	.hour-pair { display: grid; grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr)); gap: .6rem; }
	.days { display: grid; grid-template-columns: repeat(auto-fill, minmax(5rem, 1fr)); gap: .35rem; margin: 0; padding: 0; border: 0; min-width: 0; }
	legend { padding: 0 0 .25rem; }
	.tick { display: flex; align-items: center; gap: .5rem; min-height: 44px; padding-inline: .6rem; border: 1px solid var(--line); border-radius: 6px; background: var(--panel); cursor: pointer; }
	.tick input { width: 1.25rem; height: 1.25rem; margin: 0; accent-color: var(--accent); }
</style>
