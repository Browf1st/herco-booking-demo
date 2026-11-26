<script lang="ts">

 import ServerStaffBookings from '#lib/live/ServerStaffBookings.svelte';
 import ServerStaffRequests from '#lib/live/ServerStaffRequests.svelte';
 import { resolve } from '$app/paths';
 import { page } from '$app/state';
 import { onMount } from 'svelte';
 const changes = $derived(page.url.searchParams.get('view') === 'requests');
 let access = $state<{ pages: string[]; actions: string[] }>();
 async function loadAccess() {
  try {
   const response = await fetch(resolve('/api/staff/workspace'));
   access = response.ok ? await response.json() : undefined;
  } catch { access = undefined; }
 }
 onMount(() => { void loadAccess(); });
</script>

 {#if changes}
  <ServerStaffRequests />
 {:else}
  <ServerStaffBookings canComplete={access?.actions.includes('completeBooking') ?? false}
   canAdjustPrices={access?.actions.includes('adjustPrices') ?? false} actions={access?.actions} pages={access?.pages}
   canRequestIntake={access?.pages.includes('Bookings') === true && access.actions.includes('createBooking')} />
 {/if}
