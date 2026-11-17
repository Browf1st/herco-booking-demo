<script lang="ts">
 import ActionIcon from '#lib/ActionIcon.svelte';
 import { resolve } from '$app/paths';
 import { account } from '#lib/account.svelte.ts';
 import CustomerBookingHistory from '#lib/CustomerBookingHistory.svelte';
</script>
<svelte:head><title>My bookings | HERCO</title></svelte:head>
<section class="section wrap stack">
 <h1>My bookings</h1>
 <p class="muted">See your service status and request changes. The shop reviews cancellation and rescheduling requests.</p>
 {#if !account.current}<div><a class="btn sm ghost" href={resolve('/account')}><ActionIcon name="user" />Sign in</a></div>{/if}
 <CustomerBookingHistory />
</section>
