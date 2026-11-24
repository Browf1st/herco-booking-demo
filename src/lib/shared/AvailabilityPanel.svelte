<script lang="ts">
	import { onMount } from 'svelte';
	import DateHoursPanel from './DateHoursPanel.svelte';
	import OpeningHoursCard from './OpeningHoursCard.svelte';
	import type { DateAction, DayInfo, Needs, ScheduleSettings } from './schedule-hours';

	// Loaded on demand from the booking pages. Each build supplies its own load and save functions.
	let { date, day, loadSettings, saveSettings, act }: {
		date: string; day: DayInfo;
		loadSettings: () => Promise<ScheduleSettings & { canManage: boolean }>;
		saveSettings: (values: ScheduleSettings, confirmOutside: boolean, confirmedCount?: number) => Promise<Needs | undefined>;
		act: (action: DateAction, confirmOutside: boolean, confirmedCount?: number) => Promise<Needs | undefined>;
	} = $props();

	let settings = $state<ScheduleSettings & { canManage: boolean }>();
	let failed = $state(false);

	// Used by the hours card to pick up the server's newest settings (and version).
	async function reloadSettings() { return (settings = await loadSettings()); }

	async function load() {
		failed = false;
		try { settings = await loadSettings(); } catch { failed = true; }
	}
	onMount(() => { void load(); });
</script>

<div class="stack">
	<p class="small muted">Changes apply to new bookings. Existing appointments stay scheduled.</p>
	{#if settings}
		<OpeningHoursCard {settings} canManage={settings.canManage} onsave={saveSettings} onreload={reloadSettings} />
		{#key date}<DateHoursPanel {day} canManage={settings.canManage} {act} />{/key}
	{:else if failed}
		<p class="error" role="alert">Couldn't load the opening hours.</p>
		<div><button type="button" class="btn sm ghost" onclick={load}>Try again</button></div>
	{:else}<p role="status">Loading opening hours…</p>{/if}
</div>
