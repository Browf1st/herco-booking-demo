<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { addDays, fmtDate, fmtSlot, today } from '../shared/dates';
	import { trackShopEvent } from './analytics';
	import { canEnhance } from '../shared/coating';
	import { wheels } from '../shared/bookingCatalog';
	import { coatingSnapshot, type CoatingDraft } from './booking-coating';
	import ActionIcon from '../shared/ActionIcon.svelte';
 import ServerBookingCatalog from './ServerBookingCatalog.svelte';
 import ServerVisitPicker from './ServerVisitPicker.svelte';
 import { ceramicModels, ceramicTierNames, createCatalogOptions } from '../shared/bookingCatalog';
 import { selection, serviceLabel, money } from '../shared/coating';
 import { uiCoatingSnapshot, type UiCatalogConfig } from './ui-catalog';
 import { goto } from '$app/navigation';
	import { displayEstimate, displayServicePrice, type PricedService } from './service-estimate';
	import { contactError, slotFromHour } from './booking-contact';

	type Service = {
		code: string;
		label: string;
		price_centavos: number;
		max_centavos?: number | null;
		quote_required?: boolean;
		appointment_days: number[];
		promotion?: { label: string; base_price_centavos: number } | null;
	};
	type Slot = { visit_date: string; visit_hour: number; status: string };
	type Booking = { id: string; reference?: string; status: string; totalCentavos: number; estimateOpen?: boolean };
	type Intake = { version: string; title: string; body: string; method: 'typed_name'; date: string };
	type EstimateLine = PricedService & { code: string; label: string; promotion?: { label: string } | null };
	type Estimate = { lines: EstimateLine[]; totalCentavos: number; fingerprint: string };
	let { walkIn = false, manualCustomer, manualGuest = false }: { walkIn?: boolean; manualCustomer?: { id: string; email: string }; manualGuest?: boolean } = $props();
	const staffBooking = $derived(Boolean(manualCustomer) || manualGuest);

	let services = $state<Service[]>([]);
	let slots = $state<Slot[]>([]);
	 let catalogSelection=$state({...selection(false,''),ceramic:false,catalog:createCatalogOptions()});
 let additionalCodes=$state<string[]>([]);
 const selected=$derived([...(catalogSelection.ceramic?['ceramic']:[]),...(catalogSelection.powder?['wheel-colour']:[]),...additionalCodes]);
	let visitDate = $state('');
	let visitHour = $state('');
	let name = $state('');
	let phone = $state('');
	// Walk-ins and verified-account staff bookings require a mobile number.
	const phoneRequired = $derived(walkIn || !!manualCustomer);
	let unit=$state(''), custom=$state(''), powderBike=$state(''), modelYear=$state<number>(), notes=$state('');
 const manualModel=$derived(unit==='other'||unit==='other-big-bike');
 const bike=$derived(catalogSelection.ceramic?(manualModel?custom.trim():unit):powderBike.trim());
 const isPcx=$derived(catalogSelection.ceramic&&/^Honda PCX/i.test(bike));
 const pcxYears=[2026,2025,2024,2023,2022,2021,2020,2019,2018];
 const groupedAliases=['Honda ADV150','Honda PCX150','Suzuki Gixxer 250'];
 const tiers=Object.entries(ceramicModels);
 const modelLabels:Record<string,string>={};
 const tierDescriptions:Record<string,string>={1799:'Scooters and underbones',1999:'Maxi scooters and naked bikes',2499:'Vespa, 400 cc and up, and more'};
 let catalogConfig=$state<UiCatalogConfig>({});
 const ceramicPricing=$derived(catalogConfig.ceramic??{});

 let reviewDialog=$state<HTMLDialogElement>();
 function selectMotorcycle(model:string){modelYear=undefined;custom='';catalogSelection.catalog.otherBigBike=model==='other-big-bike';catalogSelection.catalog.bigBike=catalogSelection.catalog.otherBigBike||model==='Kawasaki Dominar 400';}
	let plate = $state('');
	
	let email = $state('');
	let intake = $state<Intake | null>(null);
	let signerName = $state('');
	let acknowledged = $state(false);
	let loading = $state(true);
	let signedOut = $state(false);
	let loadError = $state('');
	let submitting = $state(false);
	let submitError = $state('');
	let booked = $state<Booking>();
	let preview = $state<{ estimate: Estimate; selection: string; revision: number }>();
	let previewIssue = $state('');
	let previewRevision = $state(0);
	let started = false;

	const attempts = new Map<string, string>();
	const prices = new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP' });
	const selectedServices = $derived(services.filter((service) => selected.includes(service.code)));
	const openSlots = $derived(slots.filter((slot) => slot.status === 'open' &&
		selectedServices.every((service) => service.appointment_days.includes(
			new Date(slot.visit_date + 'T00:00:00Z').getUTCDay()
		))
	));
	const availableDates = $derived([...new Set(openSlots.map((slot) => slot.visit_date))]);
	const availableHours = $derived(openSlots.filter((slot) => slot.visit_date === visitDate));
	const intakeWeekday = $derived(intake ? new Date(intake.date + 'T00:00:00Z').getUTCDay() : null);
	const visibleServices = $derived(walkIn && intakeWeekday !== null
		? services.filter(service => service.appointment_days.some(day => day === intakeWeekday))
		: services);
	const openEstimate = $derived(selectedServices.some(service => service.quote_required ||
		(service.max_centavos != null && service.max_centavos > service.price_centavos)));
	const configured = $derived(uiCoatingSnapshot(catalogSelection,isPcx?modelYear:undefined,notes));
 const allowedDays=$derived(selectedServices.reduce((days,service)=>days.filter(d=>service.appointment_days.includes(d)),[0,1,2,3,4,5,6]));

	const configurationIssue=$derived(catalogSelection.powder&&!catalogSelection.powderParts.length?'Choose powder coating parts.':'');
	const previewInput = $derived(bike.trim() && selected.length && !configurationIssue
		? JSON.stringify({ bike: bike.trim(), services: [...selected].sort(), coating: configured })
		: '');
	const currentEstimate = $derived(preview?.selection === previewInput && preview.revision === previewRevision
		? preview.estimate : undefined);
 const cartLines=$derived(currentEstimate?.lines.flatMap(line=>(line as EstimateLine & {details?:EstimateLine[]}).details??[line])??[]);

	$effect(() => {
		const selection = previewInput;
		const revision = previewRevision;
		preview = undefined;
		previewIssue = '';
		if (!selection || signedOut || booked) return;
		const controller = new AbortController();
		const timer = setTimeout(() => { void loadEstimate(selection, revision, controller.signal); }, 250);
		return () => {
			clearTimeout(timer);
			controller.abort();
		};
	});

	async function loadEstimate(selection: string, revision: number, signal: AbortSignal) {
		try {
			const response = await fetch(resolve('/api/coating-estimate'), {
				method: 'POST', signal,
				headers: { 'content-type': 'application/json', accept: 'application/json' },
				body: selection
			});
			const data = await response.json().catch(() => null);
			if (!response.ok || !Array.isArray(data?.lines) || !Number.isSafeInteger(data.totalCentavos) ||
				typeof data.fingerprint !== 'string' || !/^[a-f0-9]{32}$/.test(data.fingerprint)) {
				throw Error(typeof data?.message === 'string' ? data.message : 'Could not load the estimate. Try again.');
			}
			if (!signal.aborted) preview = { estimate: data, selection, revision };
		} catch (error) {
			if (!signal.aborted) previewIssue = error instanceof Error ? error.message : 'Could not load the estimate. Try again.';
		}
	}

	function servicePrice(service: Service) {
		if (service.quote_required) return 'Shop quote';
		const minimum = prices.format(service.price_centavos / 100);
		return service.max_centavos != null && service.max_centavos > service.price_centavos
			? minimum + '–' + prices.format(service.max_centavos / 100)
			: minimum;
	}

	async function fetchIntake(): Promise<Intake | null> {
		const response = await fetch(resolve('/api/walk-in-bookings'), { headers: { accept: 'application/json' } });
		if (!response.ok) {
			const failure = await response.json().catch(() => null);
			throw new Error(typeof failure?.message === 'string' ? failure.message : 'Could not load the walk-in form.');
		}
		return response.json();
	}

	async function availability(): Promise<Slot[]> {
		const from = today();
		const query = new URLSearchParams({ from, to: addDays(from, 20) });
		const response = await fetch(resolve('/api/availability') + '?' + query);
		if (!response.ok) throw new Error('Could not load available visits. Try again.');
		return response.json();
	}

	async function load() {
		loading = true;
		signedOut = false;
		loadError = '';
		try {
			const session = await fetch(resolve('/api/auth/session'));
			if (session.status === 401) {
				signedOut = true;
				return;
			}
			if (!session.ok) throw new Error('Could not check your sign-in. Try again.');

			const [catalog, freshSlots, approvedForm, richCatalog] = await Promise.all([
				fetch(resolve('/api/catalog')),
				walkIn ? Promise.resolve([]) : availability(),
				walkIn ? fetchIntake() : Promise.resolve(null),
 fetch(resolve('/api/booking-catalog'))
			]);
			if (!catalog.ok) throw new Error('Could not load services. Try again.');
			email = manualGuest ? '' : manualCustomer?.email ?? (await session.json()).email ?? '';
			services = await catalog.json();
 if(!richCatalog.ok)throw new Error('Could not load the service catalog. Try again.');
 catalogConfig=(await richCatalog.json()).config;
 const service=page.url.searchParams.get('service');
 if(service==='ceramic')catalogSelection.ceramic=true;
 if(service==='wheel-colour'){catalogSelection.powder=true;catalogSelection.powderParts=['Wheels / mags'];}
 catalogSelection.finish=page.url.searchParams.get('finish')??'';
			slots = freshSlots;
			intake = approvedForm;
			if (!staffBooking) void fetch(resolve('/api/auth/contact')).then(async response => {
				if (!response.ok) return;
				const contact = await response.json();
				if (!name) name = contact.name;
				if (!phone) phone = contact.mobile;
			}).catch(() => {});
			if (!started && visibleServices.length && (!walkIn || intake)) {
				started = true;
				trackShopEvent('booking_started');
			}
			const suggestedDate = page.url.searchParams.get('date');
			if (!visitDate && suggestedDate && availableDates.includes(suggestedDate)) visitDate = suggestedDate;
		} catch (failure) {
			loadError = failure instanceof Error ? failure.message : 'Could not load booking.';
		} finally {
			loading = false;
		}
	}

	function chooseService(code: string, checked: boolean) {
		if(code==='ceramic')catalogSelection.ceramic=checked;else if(code==='wheel-colour')catalogSelection.powder=checked;else additionalCodes=checked?[...additionalCodes,code]:additionalCodes.filter(c=>c!==code);
		if (checked) trackShopEvent('service_selected');
		if (!availableDates.includes(visitDate)) visitDate = '';
		if (!availableHours.some((slot) => String(slot.visit_hour) === visitHour)) visitHour = '';
	}

	function submit(event:SubmitEvent){event.preventDefault();submitError='';if(!currentEstimate)return;submitError=contactError(name,phone,phoneRequired);if(submitError)return;reviewDialog?.showModal();}
 async function confirmBooking() {
		if (submitting || !selected.length || (walkIn ? !intake || (!manualCustomer&&!acknowledged) : !visitDate || !visitHour)) return;
		const estimate = currentEstimate;
		if (!estimate) return;
		submitting = true;
		submitError = '';
		try {
			const payload = {
				...(walkIn && intake ? { date: intake.date, formVersion: intake.version, signerName: signerName.trim(), acknowledged,...(manualCustomer?{hour:null}:{}) }
					: { date: visitDate, hour: Number(visitHour) }),
				services: [...selected].sort(),
				bike: bike.trim(), name: name.trim(), phone: phone.trim(), plate: plate.trim(),
				coating: configured,
				...(manualGuest ? { action: 'book_guest' } : manualCustomer
					? { action: 'book', customerId: manualCustomer.id, email: manualCustomer.email, walkIn }
					: {})
			};
			const fingerprint = JSON.stringify(payload);
			const requestId = attempts.get(fingerprint) ?? crypto.randomUUID();
			attempts.set(fingerprint, requestId);

			const response = await fetch(resolve(staffBooking?'/api/staff/manual-booking':walkIn ? '/api/walk-in-bookings' : '/api/bookings'), {
				method: 'POST',
				headers: { 'content-type': 'application/json', accept: 'application/json' },
				body: JSON.stringify({ ...payload, requestId, priceFingerprint: estimate.fingerprint })
			});
			if (response.ok) {
				const saved: Booking = await response.json();
 reviewDialog?.close();
				trackShopEvent('booking_submitted');
				// Customers land on My Bookings, where the new booking shows its live status.
				if (!staffBooking) {
					await goto(resolve('/my-bookings') + '?submitted=' + encodeURIComponent(saved.id));
					return;
				}
				booked = saved;
				return;
			}
			if (response.status === 401) signedOut = true;
			const errorBody = await response.json().catch(() => null);
			submitError = errorBody?.message ?? 'Could not submit your booking. Try again with the same details.';
			if (response.status === 409 && errorBody?.code === 'price_changed') {
				previewRevision += 1;
				return;
			}
			if (response.status === 409) {
				if (walkIn) {
					intake = await fetchIntake().catch(() => intake);
					signerName = '';
					acknowledged = false;
					additionalCodes = additionalCodes.filter(code => visibleServices.some(service => service.code === code));
				} else {
					slots = await availability().catch(() => slots);
					visitHour = '';
					if (!availableDates.includes(visitDate)) visitDate = '';
				}
			}
		} catch {
			submitError = staffBooking
				? 'Could not confirm the booking. Retry with the same details or check Booking History.'
				: 'Could not confirm your booking. Retry with the same details or check My Bookings.';
		} finally {
			submitting = false;
		}
	}

	onMount(() => { void load(); });
</script>
<svelte:head><title>{staffBooking?'Manual booking':walkIn?'Walk-in intake':'Book a visit'} | HERCO</title></svelte:head>
<section class="section wrap stack booking">
<h1>{booked?'Booking submitted':walkIn?'Walk-in intake':'Book a visit'}</h1>
{#if loading}<p role="status">Loading booking options…</p>{:else if signedOut}<p>Sign in to submit a booking and view it on any device.</p><div><a class="btn" href={resolve('/account')}><ActionIcon name="login" />Sign in</a></div>{:else if loadError}<p role="alert">{loadError}</p><div><button class="btn ghost" onclick={load}><ActionIcon name="reset" />Try again</button></div>{:else if booked}<p class="eyebrow">{manualGuest ? booked.reference ?? booked.id : booked.id}</p><p>The shop will review your request.</p><div class="card stack"><p><strong>{serviceLabel(catalogSelection)}</strong> · {bike}{modelYear?' · Model year '+modelYear:''}</p><p>{walkIn?'Walk-in today':fmtDate(visitDate)+' at '+fmtSlot(visitHour+':00')} · Philippine time</p><p>Estimated service price <strong>{currentEstimate?displayEstimate(currentEstimate.lines,currentEstimate.totalCentavos):prices.format(booked.totalCentavos/100)}</strong></p></div><div>{#if staffBooking}<a class="btn" href={resolve(walkIn?'/walk-in-intake':'/admin')+(walkIn?'?booking='+booked.id:'')}>{walkIn?'Open customer intake':'Back to bookings'}</a>{:else}<a class="btn" href={resolve('/my-bookings')}><ActionIcon name="calendar" />View my bookings</a>{/if}</div>{:else if walkIn&&!intake}<p>Walk-in booking is unavailable while the shop sets up its intake form.</p>{:else if !visibleServices.length}<p>Booking is unavailable while the shop enables its services.</p>{:else}
{#if !manualGuest}<label class="booking-source">Booking source<select value={walkIn?'walk-in':'online'} onchange={event=>{if(manualCustomer){walkIn=event.currentTarget.value==='walk-in';void load();}else void goto(resolve(event.currentTarget.value==='walk-in'?'/walk-in':'/book'));}}><option value="online">Online</option><option value="walk-in">Walk-in</option></select></label>{/if}
  <form class="booking-layout" onsubmit={submit}>
   <div class="stack booking-steps">
   <fieldset class="card stack booking-panel">
    <legend><span>1</span> Choose a service</legend>
    <div class="cols">
     <label class="service-choice"><input type="checkbox" bind:checked={catalogSelection.ceramic} /><strong>Ceramic coating</strong><span class="small muted">Paint protection and detailing</span></label>
     <label class="service-choice"><input type="checkbox" bind:checked={catalogSelection.powder} /><strong>Powder coating</strong><span class="small muted">Color and finish for mags and small parts</span></label>
    </div>
   </fieldset>
   {#if catalogSelection.ceramic || catalogSelection.powder}
   <fieldset class="card stack booking-panel">
    <legend><span>2</span> Motorcycle and service options</legend>
    {#if catalogSelection.ceramic}
    <div class="stack models" role="group" aria-label="Motorcycle models">
     <p class="small muted">Prices shown are for ceramic coating.</p>
     <div class="model-groups">
      {#each tiers as [price, models], index}
       {@const tier = Number(price) as keyof typeof ceramicModels}
       <div class="model-group" class:selected={models.includes(unit) || (price === '2499' && unit === 'other-big-bike')}>
        <div class="tier-heading">
         <div class="tier-label">Tier {index + 1}<span class="tier-indicator" aria-hidden="true"></span></div>
         <strong>{ceramicTierNames[tier]}</strong>
         <p class="small muted">{tierDescriptions[price]}</p>
         <div class="tier-price"><span class="small muted">From</span> <strong>{ceramicPricing.tiers?.[String(tier)]===undefined?'Shop quote':money(ceramicPricing.tiers[String(tier)])}</strong></div>
        </div>
        <div class="model-options">
       {#each models.filter(model => !groupedAliases.includes(model)) as model}
        <label class="model"><input type="radio" name="motorcycle" value={model} bind:group={unit} onchange={() => selectMotorcycle(model)} aria-label={(modelLabels[model] ?? model) + ', ceramic coating ' + (ceramicPricing.tiers?.[String(tier)]===undefined?'Shop quote':money(ceramicPricing.tiers[String(tier)]))} /> {modelLabels[model] ?? model}</label>
       {/each}
        {#if price === '2499'}
         <label class="model"><input type="radio" name="motorcycle" value="other-big-bike" bind:group={unit} onchange={() => selectMotorcycle('other-big-bike')} /> Other big bike (400 cc and up)</label>
        {/if}
        </div>
       </div>
      {/each}
     </div>
     <label class="model"><input type="radio" name="motorcycle" value="other" bind:group={unit} onchange={() => selectMotorcycle('other')} /> Motorcycle not listed</label>
     {#if manualModel}
      <label>Brand and model
       <input bind:value={custom} placeholder={unit === 'other-big-bike' ? 'e.g. Ducati Monster' : 'e.g. Yamaha MT-15'} maxlength="100" required />
      </label>
     {/if}
    </div>
    {/if}
    {#if isPcx}
     <label>PCX model year
      <select bind:value={modelYear} required>
       <option value={undefined} disabled>Select model year</option>
       {#each pcxYears as year}<option value={year}>{year}</option>{/each}
      </select>
     </label>
    {/if}
    {#if bike || !catalogSelection.ceramic}
     <ServerBookingCatalog bind:value={catalogSelection} {bike} year={isPcx ? modelYear : undefined} serviceControls={false} config={catalogConfig}>
      {#snippet powderDetails()}
       {#if !catalogSelection.ceramic}
        <label>Motorcycle brand and model <input bind:value={powderBike} placeholder="e.g. Yamaha Sniper 155" maxlength="100" required /></label>
       {/if}
      {/snippet}
     </ServerBookingCatalog>
    {/if}
    <label>Notes for the shop (optional) <textarea bind:value={notes} maxlength="700" rows="2" placeholder="e.g. Please check the brackets for scratches"></textarea></label>

   </fieldset>
   {#if bike}
   <fieldset class="card stack booking-panel contact-panel">
    <legend><span>3</span> Contact details and vehicle plate</legend>
    <div class="cols">
     <label>Full name <input bind:value={name} autocomplete="name" placeholder="e.g. Jamie Reyes" maxlength="70" required /></label>
     <label>Mobile number{phoneRequired ? '' : ' (optional)'} <input type="tel" bind:value={phone} autocomplete="tel" placeholder="e.g. 0917 000 0000" maxlength="20" required={phoneRequired} /></label>
     {#if !manualGuest}<label>
      <span>Email <span class:required-label={!walkIn}>{walkIn ? '(optional)' : '(required)'}</span></span>
      <input type="email" bind:value={email} readonly autocomplete="email" placeholder="e.g. jamie@example.com" maxlength="254" required={!walkIn} aria-describedby={walkIn ? undefined : 'booking-email-help'} />
      {#if !walkIn}<span id="booking-email-help" class="small muted email-help">Used for booking reminders.</span>{/if}
     </label>{/if}
     <label>Plate number (optional) <input bind:value={plate} placeholder="e.g. ABC 1234" maxlength="20" /></label>
    </div>
   </fieldset>
   <fieldset class="card stack booking-panel">
    <legend><span>4</span> Preferred date and time</legend>
    
    {#if !walkIn || false}<ServerVisitPicker bind:date={visitDate} bind:hour={visitHour} days={allowedDays} disabled={submitting} />{/if}
    {#if walkIn && manualCustomer}<p>The customer must sign in to their own account and sign the intake before the shop can confirm this walk-in.</p>{:else if walkIn && intake}<p class="small muted">{intake.title} · {intake.version}</p><p class="intake-text">{intake.body}</p><label class="check"><input type="checkbox" bind:checked={acknowledged} required/>I read and agree to the form above.</label><label>Customer signature (type full name)<input bind:value={signerName} required/></label>{/if}   </fieldset>
   {/if}
   {/if}
   </div>
   <aside class="card stack booking-cart" aria-label="Booking summary">
    <div class="stack" aria-live="polite">
     <h2 class="cart-title">Booking cart</h2>
     {#if bike}<div class="cart-line"><span>Motorcycle</span><strong>{bike}</strong></div>{/if}
     {#if visitDate && visitHour}<div class="cart-line"><span>Preferred visit</span><strong>{fmtDate(visitDate)} · {fmtSlot(visitHour+':00')}</strong></div>{/if}
     {#each cartLines as line (line.label)}
      <div class="cart-line"><span>{line.label}</span><strong>{displayServicePrice(line)}</strong></div>
     {:else}
      <p>Choose a service to add it to your booking.</p>
     {/each}
     {#if cartLines.length}
      {#if 0}<div class="cart-line"><span>Estimated promo savings</span><strong>{money(0)}</strong></div>{/if}
      <div class="cart-line cart-total"><span>Estimated total</span><strong>{currentEstimate?displayEstimate(currentEstimate.lines,currentEstimate.totalCentavos):'Shop quote'}</strong></div>
      <p class="small muted">Your estimate may change after an in-shop inspection. The shop will confirm any price changes with you before starting the work.</p>
     {/if}
    </div>
    {#if submitError}<p class="submitError" role="alert">{submitError}</p>{/if}
    <button class="btn" disabled={submitting || !currentEstimate || !bike || (walkIn ? !manualCustomer&&(!acknowledged || !signerName.trim()) : !visitHour)}><ActionIcon name={walkIn ? "save" : "send"} />{walkIn ? 'Save walk-in intake' : 'Submit booking'}</button>
   </aside>
  </form>
{/if}</section>
<dialog bind:this={reviewDialog} aria-labelledby="review-title" class="booking-review">
 <div class="stack">
  <h2 id="review-title">Review booking</h2>
  <dl class="review-facts">
   <div><dt>Booking source</dt><dd>{walkIn ? 'Walk-in' : 'Online'}</dd></div>
   <div><dt>Appointment · Philippine time</dt><dd>{visitDate ? fmtDate(visitDate, {month:'long', day:'numeric', year:'numeric'}) : ''} · {visitHour ? fmtSlot(slotFromHour(visitHour)) : ''}</dd></div>
   <div><dt>Customer</dt><dd>{name.trim()}</dd></div>
   <div><dt>Mobile</dt><dd>{phone.trim() || 'Not provided'}</dd></div>
   {#if !manualGuest}<div><dt>Email</dt><dd>{email.trim() || 'Not provided'}</dd></div>{/if}
   <div><dt>Motorcycle</dt><dd>{bike}{isPcx && modelYear ? ' · ' + modelYear : ''}</dd></div>
   <div><dt>Plate number</dt><dd>{plate.trim() || 'Not provided'}</dd></div>
   {#if walkIn}<div><dt>Intake signed by</dt><dd>{signerName.trim()}</dd></div>{/if}
   <div class="review-notes"><dt>Notes for the shop</dt><dd>{notes.trim() || 'None'}</dd></div>
  </dl>
  <section class="stack" aria-label="Services and estimated prices">
   <h3>Services and estimate</h3>
   <p>{serviceLabel(catalogSelection)}{catalogSelection.powder && catalogSelection.finish ? ' · ' + catalogSelection.finish : ''}</p>
   {#each cartLines as line}<div class="cart-line"><span>{line.label}</span><strong>{displayServicePrice(line)}</strong></div>{/each}
   {#if 0}<div class="cart-line"><span>Promo savings</span><strong>{money(0)}</strong></div>{/if}
   <div class="cart-line cart-total"><span>Estimated total</span><strong>{currentEstimate?displayEstimate(currentEstimate.lines,currentEstimate.totalCentavos):'Shop quote'}</strong></div>
  </section>
  {#if submitError}<p class="error" role="alert">{submitError}</p>{/if}
  <div class="row"><button type="button" class="btn sm ghost" onclick={() => reviewDialog?.close()}>Back to edit</button><button type="button" class="btn sm" disabled={submitting} onclick={confirmBooking}><ActionIcon name="check" />Confirm and submit</button></div>
 </div>
</dialog>
<style>
 .booking-review { width: min(680px, calc(100% - 24px)); max-height: 88dvh; padding: clamp(16px, 4vw, 28px); border: 1px solid var(--line); border-radius: 12px; background: var(--panel); color: var(--text); }
 .booking-review::backdrop { background: #0009; }
 .booking-review h2 { font-size: 2rem; }
 .review-facts { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 190px), 1fr)); gap: .7rem; margin: 0; }
 .review-facts dt { color: var(--muted); font-size: .8rem; }
 .review-facts dd { margin: 0; overflow-wrap: anywhere; }
 .review-notes { grid-column: 1 / -1; white-space: pre-wrap; }
 .booking { max-width: 1280px; background: var(--bg); color: var(--text); }

 .booking-source { max-width: 18rem; }
 .booking-layout { display: grid; gap: 20px; align-items: start; }
 .booking-steps { min-width: 0; gap: 24px; }
 .booking-cart { border-top: 4px solid var(--accent); border-radius: 12px; padding: 20px; box-shadow: 0 4px 12px var(--card-shadow); }
 .booking-cart .btn { width: 100%; clip-path: none; border-radius: 8px; }
 @media (min-width: 960px) {
  .booking-layout { grid-template-columns: minmax(0, 2fr) minmax(280px, 1fr); gap: 24px; }
  .booking-cart { position: sticky; top: 80px; max-height: calc(100vh - 100px); overflow: auto; }
 }
 legend span { display: inline-grid; place-items: center; width: 1.65em; aspect-ratio: 1; margin-inline-end: 6px; border-radius: 50%; background: var(--accent-fill); color: var(--accent-ink); font-size: .82em; }
 h1 { font-family: var(--body); font-size: clamp(2rem, 5vw, 3.25rem); font-weight: 900; font-style: italic; letter-spacing: -.03em; }
 fieldset { min-inline-size: 0; margin: 0; }
 legend { padding-inline: 6px; font-weight: 750; font-size: 1.2rem; }
 .booking-panel {
  padding: clamp(16px, 3vw, 28px);
  gap: 18px;
  border-radius: 12px;
  box-shadow: 0 1px 3px var(--card-shadow);
 }
 .booking-panel > .cols {
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 235px), 1fr));
 }
 .booking-panel label { min-width: 0; }
 .models { min-inline-size: 0; }
 .model-groups { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 175px), 1fr)); align-items: start; gap: 10px; }
 .model-group { display: grid; gap: 4px; padding: 12px; background: var(--bg); border: 1px solid var(--line); border-radius: 12px; }
 .model-group.selected { border-color: var(--accent); box-shadow: inset 0 0 0 1px var(--accent); }
 .service-choice { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 4px 12px; padding: 16px; border: 1px solid var(--line); border-radius: 12px; background: var(--bg); color: var(--text); cursor: pointer; }
 .service-choice input { grid-area: 1 / 2; align-self: center; appearance: none; width: 1rem; height: 1rem; margin: 0; border: 1px solid var(--line); border-radius: 50%; background: var(--panel); }
 .service-choice input:checked { border: .3rem solid var(--accent); }
 .service-choice strong { grid-area: 1 / 1; }
 .service-choice span { grid-column: 1 / -1; }
 .service-choice:hover { background: var(--panel-2); }
 .service-choice:has(:checked) { border-color: var(--accent); background: color-mix(in srgb, var(--accent) 6%, var(--panel)); box-shadow: inset 0 0 0 1px var(--accent); }
 .service-choice:has(:focus-visible) { outline: 2px solid var(--accent); outline-offset: 2px; }
 .tier-heading { display: grid; gap: 6px; padding: 4px; }
 .tier-label { display: flex; justify-content: space-between; align-items: center; color: var(--muted); font-size: .75rem; font-weight: 750; letter-spacing: .06em; text-transform: uppercase; }
 .tier-indicator { display: grid; place-items: center; width: 16px; height: 16px; border: 1px solid var(--line); border-radius: 50%; }
 .selected .tier-indicator { border-color: var(--accent); background: var(--accent); }
 .selected .tier-indicator::after { content: ''; width: 6px; height: 6px; border-radius: 50%; background: var(--accent-ink); }
 .tier-price { display: flex; flex-wrap: wrap; align-items: baseline; gap: 6px; border-top: 1px solid var(--line); margin-top: 4px; padding-top: 8px; }
 .tier-price strong { font-size: 1.25rem; }
 .model-group { grid-row: span 5; grid-template-rows: subgrid; align-items: start; }
 .tier-heading { grid-row: span 4; grid-template-rows: subgrid; align-self: stretch; }
 .tier-price { align-self: end; }
 .model-options { display: grid; gap: 2px; border-top: 1px solid var(--line); margin-top: 6px; padding-top: 6px; }
 .model { display: flex; align-items: center; gap: 8px; min-height: 38px; padding: 4px 7px; border-radius: 6px; color: var(--text); font-size: .9rem; cursor: pointer; }
 .model input { flex: none; width: 1rem; height: 1rem; margin: 0; accent-color: var(--accent); }
 .model:hover, .model:has(:checked) { background: var(--panel-2); }
 .model:has(:checked) { box-shadow: inset 0 0 0 1px var(--accent); }
 .model:has(:focus-visible) { outline: 2px solid var(--accent); outline-offset: 2px; }
 .cart-title { padding-bottom: 12px; border-bottom: 1px solid var(--line); font-family: var(--body); font-size: 1.15rem; font-weight: 900; font-style: italic; letter-spacing: -.03em; }
 .cart-line { display: flex; justify-content: space-between; gap: 10px; }
 .cart-line strong { text-align: right; }
 .cart-total { border-top: 1px solid var(--line); padding-top: 10px; }
 .check { display: flex; align-items: center; gap: 8px; }
 .contact-panel > .cols { grid-template-columns: repeat(auto-fit, minmax(min(100%, 190px), 1fr)); }
 .contact-panel label { align-content: start; font-weight: 600; }
 .contact-panel input, .booking-panel textarea { background: var(--panel); border-radius: 10px; font-weight: 400; }
 .required-label { color: var(--accent); font-weight: 400; }
 .email-help { font-weight: 400; }
</style>
