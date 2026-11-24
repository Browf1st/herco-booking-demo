<script lang="ts">
	// The "Changes" list for one booking in a staff popup (GET /api/staff/booking-history).
	// `version` goes up after a save, which loads the list again.
	import { resolve } from '$app/paths';
	import BookingChangesList from '../shared/BookingChangesList.svelte';
	import { historyLine, type HistoryEntry } from '../shared/booking-changes';

	let { bookingId, version = 0 }: { bookingId: string; version?: number } = $props();
	let status = $state<'loading' | 'ready' | 'error'>('loading');
	let lines = $state<string[]>([]);
	let message = $state('');
	let latest = 0;

	async function load() {
		const mine = ++latest;
		status = 'loading';
		try {
			const response = await fetch(resolve('/api/staff/booking-history') + '?' + new URLSearchParams({ booking: bookingId }), { headers: { accept: 'application/json' } });
			const body = await response.json().catch(() => null);
			if (mine !== latest) return;
			if (!response.ok) throw Error(response.status === 403 ? 'You do not have access to this booking’s changes.' : typeof body?.message === 'string' ? body.message : 'Could not load the changes.');
			lines = (Array.isArray(body?.entries) ? (body.entries as HistoryEntry[]) : []).map(historyLine);
			status = 'ready';
		} catch (problem) {
			if (mine !== latest) return;
			message = problem instanceof Error ? problem.message : 'Could not load the changes.';
			status = 'error';
		}
	}

	$effect(() => { void version; void bookingId; void load(); });
</script>

<BookingChangesList {status} {lines} {message} onretry={load} />
