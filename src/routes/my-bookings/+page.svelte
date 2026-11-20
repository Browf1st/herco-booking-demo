<script lang="ts">
 import DemoPage from './DemoPage.svelte';
 import ServerBookingHistory from '#lib/live/ServerBookingHistory.svelte';
</script>

{#if import.meta.env.MODE === 'worker'}
 <ServerBookingHistory />
{:else}
 <DemoPage />
{/if}
