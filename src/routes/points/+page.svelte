<script lang="ts">
 import DemoPage from './DemoPage.svelte';
 import ServerPoints from '#lib/ServerPoints.svelte';
</script>

{#if import.meta.env.MODE === 'worker'}
 <ServerPoints />
{:else}
 <DemoPage />
{/if}
