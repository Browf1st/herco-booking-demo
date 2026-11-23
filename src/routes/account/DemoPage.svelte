<script lang="ts">
 import ActionIcon from '#lib/shared/ActionIcon.svelte';
 import { account, saveProfilePhone, signIn, signOut } from '#lib/demo/account.svelte.ts';
 import AuthShell from '#lib/shared/AuthShell.svelte';
 let mode = $state<'Log in' | 'Sign up'>('Log in');
 const socialProviders = ['Facebook', 'Google'] as const;
 let provider = $state<'Email' | typeof socialProviders[number]>('Email');
 let name = $state('');
 let email = $state('');
 let phone = $state(account.current?.phone ?? '');
 let profileStatus = $state('');
 let phoneError = $state('');
 function saveProfile(event: SubmitEvent) {
  event.preventDefault();
  const value = phone.trim();
  if (value && (!/^\+?[\d ()-]+$/.test(value) || value.replace(/\D/g, '').length < 7)) {
   phoneError = 'Enter a valid mobile number.';
   return;
  }
  saveProfilePhone(value);
  phone = value;
  profileStatus = 'Profile saved.';
 }
 function submit(event: SubmitEvent) {
  event.preventDefault();
  signIn(name, email, provider);
  phone = account.current?.phone ?? '';
  profileStatus = phoneError = '';
  provider = 'Email';
  email = name = '';
 }
</script>

<svelte:head><title>Demo account | HERCO</title></svelte:head>
<section class="section wrap stack account">
 {#if account.current}
  <div class="account-heading">
   <button class="btn sm ghost" onclick={signOut}><ActionIcon name="logout" />Sign out</button>
  </div>
  <section class="card stack" aria-labelledby="profile-heading">
   <h1 id="profile-heading">Profile</h1>
   <p>Signed in as <strong>{account.current.name}</strong> via {account.current.provider}</p>
   <form class="stack" onsubmit={saveProfile}>
    <label>Email<input type="email" value={account.current.email} readonly /></label>
    <label>Mobile number
     <input type="tel" bind:value={phone} autocomplete="tel" maxlength="20"
      placeholder="e.g. 0917 000 0000" aria-invalid={!!phoneError} aria-describedby="profile-phone-help"
      oninput={() => { profileStatus = phoneError = ''; }} />
    </label>
    <p id="profile-phone-help" class="muted">Your email and saved mobile number will prefill future bookings.</p>
    {#if phoneError}<p role="alert">{phoneError}</p>{/if}
    <div class="row"><button class="btn ghost" type="submit"><ActionIcon name="save" />Save profile</button></div>
    {#if profileStatus}<p role="status">{profileStatus}</p>{/if}
   </form>
  </section>
 {:else}
  <AuthShell heading={mode === 'Sign up' ? 'Create your account' : 'Welcome back'}
   subtext={mode === 'Sign up' ? 'Sign up to book faster, track your bookings and earn HERCO Points.' : 'Log in to book visits, see your bookings and use HERCO Points.'}
   tab={mode === 'Sign up' ? 'signup' : 'login'} ontab={(next) => { mode = next === 'signup' ? 'Sign up' : 'Log in'; provider = 'Email'; }}>
   {#if provider === 'Email'}
    <div class="providers stack">
     {#each socialProviders as social}
      <button type="button" class="provider" class:facebook={social === 'Facebook'} onclick={() => { provider = social; }}>
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
    </div>
    <p class="auth-divider">or use your email</p>
   {/if}
   <form onsubmit={submit}>
    <p class="muted small demo-note">{provider} demo. Use sample details.</p>
    {#if mode === 'Sign up'}<label>Name<input bind:value={name} autocomplete="name" required /></label>{/if}
    <label>Sample email<input type="email" bind:value={email} placeholder="rider@example.com" required /></label>
    <button class="auth-primary" type="submit"><ActionIcon name={mode === 'Sign up' ? 'add' : 'login'} />{mode} with {provider}</button>
    {#if provider !== 'Email'}<button type="button" class="auth-link back" onclick={() => provider = 'Email'}><ActionIcon name="back" />Back to sign-in options</button>{/if}
   </form>
  </AuthShell>
 {/if}
</section>
<style>
 .account { max-width: 680px; }
 .account-heading { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: .6rem; }
 #profile-heading { font-size: 1.5rem; }
 .demo-note { margin: 0; }
 .back { display: inline-flex; align-items: center; gap: 6px; justify-self: center; min-height: 44px; }
 .provider { position: relative; min-height: 56px; padding: 10px 42px; border: 1px solid transparent; border-radius: 3px; background: #2465ca; color: #fff; font: 650 1rem var(--body); cursor: pointer; }
 .provider.facebook { background: #395793; }
 .provider:hover { filter: brightness(.94); }
 .logo { position: absolute; inset-inline-start: 10px; top: 50%; translate: 0 -50%; display: grid; place-items: center; width: 30px; height: 30px; background: #fff; border-radius: 2px; }
 .logo svg { width: 23px; height: 23px; }
</style>
