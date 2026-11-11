<script lang="ts">
 import CustomerBookingHistory from '#lib/CustomerBookingHistory.svelte';
 import { account, signIn, signOut } from '#lib/account.svelte.ts';
 let mode = $state<'Log in' | 'Sign up'>('Log in');
 const socialProviders = ['Facebook', 'Google'] as const;
 let provider = $state<'Email' | typeof socialProviders[number]>('Email');
 let showForm = $state(false);
 let name = $state('');
 let email = $state('');
 function submit(event: SubmitEvent) {
  event.preventDefault();
  signIn(name, email, provider);
  showForm = false;
  email = name = '';
 }
</script>

<svelte:head><title>Demo account | HERCO</title></svelte:head>
<section class="section wrap stack account">
 {#if account.current}
  <h1>HERCO account</h1>
  <div class="card stack"><p>Signed in as <strong>{account.current.name}</strong> via {account.current.provider}</p>
   <div class="row"><button class="btn ghost" onclick={signOut}>Sign out</button></div>
  </div>
 {:else}
  <div class="login stack">
   <h1>{mode === 'Log in' ? 'Log In' : 'Sign Up'}</h1>
   <p>{mode === 'Log in' ? 'New to HERCO?' : 'Already have an account?'}
    <button type="button" class="mode" onclick={() => { mode = mode === 'Log in' ? 'Sign up' : 'Log in'; showForm = false; }}>{mode === 'Log in' ? 'Sign Up' : 'Log In'}</button>
   </p>
   {#if !showForm}
    <div class="providers stack">
     {#each socialProviders as social}
      <button type="button" class="provider" class:facebook={social === 'Facebook'} onclick={() => { provider = social; showForm = true; }}>
       <span class="logo" aria-hidden="true">
        {#if social === 'Facebook'}
         <svg viewBox="0 0 24 24"><path fill="#395793" d="M14 24V13h4l.6-4H14V6.5C14 5.3 14.4 5 16 5h3V1.4C18 1.1 16.8 1 15.5 1 12 1 10 3 10 6.7V9H7v4h3v11z"/></svg>
        {:else}
         <svg viewBox="0 0 48 48"><path fill="#4285f4" d="M43.6 24.5c0-1.4-.1-2.8-.4-4.1H24v7.8h11a9.4 9.4 0 0 1-4.1 6.2v5h6.7c3.8-3.5 6-8.7 6-14.9z"/><path fill="#34a853" d="M24 44c5.5 0 10.1-1.8 13.5-4.9l-6.6-5.1a12.3 12.3 0 0 1-18.3-6.5H5.8v5.2A20.4 20.4 0 0 0 24 44z"/><path fill="#fbbc05" d="M12.6 27.5a12 12 0 0 1 0-7V15H5.8a20.2 20.2 0 0 0 0 18z"/><path fill="#ea4335" d="M24 12c3 0 5.7 1 7.8 3l5.8-5.8A19.7 19.7 0 0 0 24 4 20.4 20.4 0 0 0 5.8 15l6.8 5.5A12 12 0 0 1 24 12z"/></svg>
        {/if}
       </span>
       {mode} with {social}
      </button>
     {/each}
     <p class="divider">or</p>
     <button type="button" class="provider email" onclick={() => { provider = 'Email'; showForm = true; }}>{mode} with Email</button>
    </div>
   {:else}
    <form class="stack demo-form" onsubmit={submit}>
     <p class="muted">{provider} demo. Use sample details.</p>
     {#if mode === 'Sign up'}<label>Name<input bind:value={name} autocomplete="name" required /></label>{/if}
     <label>Sample email<input type="email" bind:value={email} placeholder="rider@example.com" required /></label>
     <button class="provider email" type="submit">{mode} with {provider}</button>
     <button type="button" class="mode" onclick={() => showForm = false}>Back to sign-in options</button>
    </form>
   {/if}
  </div>
 {/if}
 <section class="stack" aria-labelledby="booking-history">
  <h2 id="booking-history">Booking history</h2>
  <CustomerBookingHistory />
 </section>
</section>
<style>
 .account { max-width: 680px; }
 .login { background: #fff; text-align: center; padding: clamp(20px, 5vw, 54px) 16px; border-radius: 8px; }
 .login h1 { font: 750 clamp(2.6rem, 7vw, 4.4rem)/1.1 var(--body); text-transform: none; }
 .providers, .demo-form { width: min(100%, 440px); margin: 24px auto 0; }
 .demo-form label { text-align: left; }
 .mode { border: 0; padding: 0; color: var(--accent); background: transparent; font: inherit; font-weight: 650; cursor: pointer; }
 .mode:hover { text-decoration: underline; }
 .provider { position: relative; min-height: 56px; padding: 10px 42px; border: 1px solid transparent; border-radius: 3px; background: #2465ca; color: #fff; font: 650 1rem var(--body); cursor: pointer; }
 .provider.facebook { background: #395793; }
 .provider.email { background: #fff; color: var(--text); border-color: var(--line); }
 .provider:hover { filter: brightness(.94); }
 .logo { position: absolute; inset-inline-start: 10px; top: 50%; translate: 0 -50%; display: grid; place-items: center; width: 30px; height: 30px; background: #fff; border-radius: 2px; }
 .logo svg { width: 23px; height: 23px; }
 .divider { display: flex; align-items: center; gap: 14px; margin-block: 8px; color: var(--muted); }
 .divider::before, .divider::after { content: ''; flex: 1; border-top: 1px solid var(--line); }
</style>
