<script lang="ts">
 import DemoPage from './DemoPage.svelte';
 import ServerBooking from '#lib/live/ServerBooking.svelte';
</script>

{#if import.meta.env.MODE === 'worker'}
 <ServerBooking />
{:else}
 <DemoPage />
{/if}
