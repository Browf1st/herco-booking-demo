// Demo adapter. In production resolve the actor, membership and grants from a
// verified server session. Authorize every staff read and mutation on the
// server and in the database; browser storage is for this mock flow only.
export const bookingPages = ['Bookings', 'Change requests', 'Booking history'] as const;
export const staffPages = [...bookingPages, 'Customers', 'HERCO Points', 'Inventory', 'Reports', 'Pricing'] as const;

export const staffActions = {
 createBooking: { page: 'Bookings', label: 'Create manual bookings' },
 manageSchedule: { page: 'Bookings', label: 'Open dates and block time slots' },
 confirmBooking: { page: 'Booking', label: 'Confirm bookings' },
 cancelBooking: { page: 'Booking', label: 'Cancel bookings directly' },
 rescheduleBooking: { page: 'Booking', label: 'Reschedule bookings directly' },
 reviewCancellation: { page: 'Booking', label: 'Approve or decline cancellation requests' },
 reviewReschedule: { page: 'Booking', label: 'Approve or decline reschedule requests' },
 editServices: { page: 'Booking', label: 'Edit booked services' },
 adjustPrices: { page: 'Booking', label: 'Adjust individual booking prices' },
 completeBooking: { page: 'Booking', label: 'Complete bookings and attach photos' },
 managePoints: { page: 'HERCO Points', label: 'Grant or correct points' },
 manageRewards: { page: 'HERCO Points', label: 'Edit rewards' },
 approveRewards: { page: 'HERCO Points', label: 'Review reward redemptions' },
 claimRewards: { page: 'HERCO Points', label: 'Mark rewards as claimed' },
 manageInventory: { page: 'Inventory', label: 'Manage inventory and stock' },
 changePricing: { page: 'Pricing', label: 'Change service catalog prices' },
 changePromotions: { page: 'Pricing', label: 'Change promotions' },
 viewIncome: { page: 'Reports', label: 'View income and final prices' }
} as const;

export type Action = keyof typeof staffActions;
export type StaffAccount = {
 id: string;
 name: string;
 email: string;
 role: 'Admin' | 'Staff';
 enabled: boolean;
 pages: string[];
 actions: Action[];
};

const accountsKey = 'herco-demo-staff-access';
const sessionKey = 'herco-demo-staff-session';
const signedOut = 'signed-out';

function hasPage(pages: readonly string[], page: string) {
 return page === 'Booking' ? bookingPages.some(section => pages.includes(section)) : pages.includes(page);
}

export function availableStaffActions(pages: readonly string[]) {
 return (Object.keys(staffActions) as Action[]).filter(action => hasPage(pages, staffActions[action].page));
}

function normalize(account: StaffAccount): StaffAccount {
 const pages = Array.isArray(account.pages) ? account.pages : [];
 const normalizedPages = staffPages.filter(page => pages.includes(page) || (bookingPages.some(section => section === page) && pages.includes('Booking')));
 const actions = Array.isArray(account.actions) ? account.actions : [];
 return {
  ...account,
  email: account.email.trim().toLowerCase(),
  pages: normalizedPages,
  actions: availableStaffActions(normalizedPages).filter(action => actions.includes(action))
 };
}

function loadAccounts(raw?: string | null): StaffAccount[] {
 let accounts: StaffAccount[] = [];
 try {
  const saved = JSON.parse(raw === undefined ? localStorage.getItem(accountsKey) ?? '[]' : raw ?? '[]');
  if (Array.isArray(saved)) accounts = saved.filter(account =>
   typeof account?.id === 'string' && account.id && !['owner', 'admin', signedOut].includes(account.id) &&
   typeof account.name === 'string' && typeof account.email === 'string' &&
   (account.role === 'Admin' || account.role === 'Staff') && typeof account.enabled === 'boolean'
  ).map(normalize);
 } catch {}

 const sampleId = 'demo-full-access-admin';
 const sampleEmail = 'herco-demo-admin@example.com';
 if (!accounts.some(account => account.id === sampleId || account.email === sampleEmail)) {
  accounts.push({
   id: sampleId,
   name: 'Sample Admin · Full Access',
   email: sampleEmail,
   role: 'Admin',
   enabled: true,
   pages: [...staffPages],
   actions: availableStaffActions(staffPages)
  });
 }
 return accounts;
}

function loadSession(accounts: StaffAccount[]): string | null {
 try {
  const id = sessionStorage.getItem(sessionKey);
  if (id === null) return 'admin';
  return id === 'owner' || id === 'admin' || accounts.some(account => account.id === id && account.enabled) ? id : null;
 }
 catch { return null; }
}

const demo = import.meta.env.MODE !== 'worker';
const initialAccounts = demo ? loadAccounts() : [];
const state = $state({ accounts: initialAccounts, sessionId: demo ? loadSession(initialAccounts) : null });
export const staffAccess = {
 get accounts() { return state.accounts; },
 get sessionId() { return state.sessionId; },
 get owner() { return state.sessionId === 'owner'; },
 get admin() { return state.sessionId === 'admin'; },
 get current() { return state.accounts.find(account => account.id === state.sessionId && account.enabled); }
};

export function saveStaffAccount(input: StaffAccount) {
 if (!staffAccess.owner) throw Error('Only the Owner can manage staff accounts.');
 const account = normalize({ ...input, id: input.id || crypto.randomUUID(), name: input.name.trim() });
 if (!account.name || !/^[^\s@]+@[^\s@]+$/u.test(account.email)) throw Error('Enter a name and valid email address.');
 const current = loadAccounts();
 if (input.id && !current.some(item => item.id === input.id)) throw Error('This staff account is no longer available.');
 if (current.some(item => item.id !== account.id && item.email === account.email)) throw Error('This email already has a staff account.');
 const accounts = input.id ? current.map(item => item.id === account.id ? account : item) : [...current, account];
 localStorage.setItem(accountsKey, JSON.stringify(accounts));
 state.accounts = accounts;
 return account;
}

export function switchStaffSession(id: string | null) {
 if (id !== null && id !== 'owner' && id !== 'admin' && !loadAccounts().some(account => account.id === id && account.enabled)) {
  throw Error('This staff account is inactive.');
 }
 sessionStorage.setItem(sessionKey, id ?? signedOut);
 state.sessionId = id;
}

export function syncStaffAccess() {
 const sync = (event: StorageEvent) => {
  if (event.key !== accountsKey && event.key !== null) return;
  state.accounts = loadAccounts(event.key === null ? undefined : event.newValue);
  if (state.sessionId && !staffAccess.owner && !staffAccess.admin && !staffAccess.current) {
   state.sessionId = null;
   try { sessionStorage.setItem(sessionKey, signedOut); } catch {}
  }
 };
 window.addEventListener('storage', sync);
 return () => window.removeEventListener('storage', sync);
}

export function canAccessPage(page: string): boolean {
 if (staffAccess.owner) return true;
 if (staffAccess.admin) return hasPage(staffPages, page);
 const account = staffAccess.current;
 if (!account) return false;
 return hasPage(account.pages, page);
}

export function canPerform(action: Action) {
 if (staffAccess.owner) return true;
 if (staffAccess.admin) return action !== 'viewIncome';
 return Boolean(staffAccess.current?.actions.includes(action) && canAccessPage(staffActions[action].page));
}

export function requireStaffAction(action: Action) {
 // Read the latest grant on each write, including forms opened before an Owner
 // changed access in another tab. Production must check inside the transaction.
 if (staffAccess.owner || (staffAccess.admin && action !== 'viewIncome')) return;
 const account = loadAccounts().find(account => account.id === state.sessionId && account.enabled);
 if (account?.actions.includes(action) && hasPage(account.pages, staffActions[action].page)) return;
 throw Error('Your account does not have permission to ' + staffActions[action].label.toLowerCase() + '.');
}

export function staffActor() {
 return staffAccess.owner ? 'Demo owner' : staffAccess.admin ? 'Demo admin' : staffAccess.current?.name ?? 'Demo staff';
}
