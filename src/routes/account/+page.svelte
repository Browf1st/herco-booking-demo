<script lang="ts">
 import DemoPage from './DemoPage.svelte';
 import ServerAccount from '#lib/live/ServerAccount.svelte';
</script>

{#if import.meta.env.MODE === 'worker'}
 <ServerAccount />
{:else}
 <DemoPage />
{/if}
