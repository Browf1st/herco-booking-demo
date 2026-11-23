<script lang="ts">
	// Status pill with an icon, so the status is not shown by colour alone.
	import ActionIcon from './ActionIcon.svelte';
	import { badgeStatus, statusIcons, statusLabels, type RecordStatus } from './records-ui';

	let { status }: { status: RecordStatus } = $props();
</script>

<span class="badge" data-status={badgeStatus(status)}><ActionIcon name={statusIcons[status]} />{statusLabels[status]}</span>

<style>
	.badge { display: inline-flex; align-items: center; gap: .3em; white-space: nowrap; }
</style>
