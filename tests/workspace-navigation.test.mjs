import assert from 'node:assert/strict';
import test from 'node:test';
import { parseWorkspaceAccess, workspaceLanding, workspaceLinks, workspaceGroups } from '../src/lib/shared/workspace-navigation.ts';

test('routes each role to its preferred permitted landing page', () => {
	assert.equal(workspaceLanding(null), '/my-bookings');
	for (const role of ['owner', 'superadmin']) {
		assert.equal(workspaceLanding({ role, pages: ['Bookings', 'Reports'], actions: [] }), '/reports');
	}
	for (const role of ['admin', 'staff', 'restricted_admin']) {
		assert.equal(workspaceLanding({ role, pages: ['Bookings', 'Reports'], actions: [] }), '/admin');
	}
});

test('restricted accounts receive only supported permitted links and landing pages', () => {
	const access = { role: 'staff', pages: ['Inventory'], actions: ['createBooking'] };
	assert.deepEqual(workspaceLinks(access), [{ label: 'Inventory', href: '/inventory' }]);
	assert.equal(workspaceLanding(access), '/inventory');
	assert.equal(workspaceLanding({ role: 'owner', pages: ['Pricing'], actions: [] }), '/pricing');
	assert.equal(workspaceLanding({ role: 'staff', pages: [], actions: [] }), '/account');
	assert.equal(workspaceLinks({ role: 'staff', pages: ['Bookings'], actions: [] }).some(link => link.href === '/manual-booking'), false);
	// Manual booking links moved out of the menu into the "Book" dropdown, so they never appear here now.
	assert.deepEqual(workspaceLinks({ role: 'admin', pages: ['Bookings'], actions: ['createBooking'] }).map(link => link.href), ['/admin']);
	assert.equal(workspaceLinks({ role: 'admin', pages: ['Bookings'], actions: ['createBooking'] }).some(link => link.href.startsWith('/manual-booking')), false);
});

test('rejects malformed or unrecognized account permissions', () => {
	for (const value of [null, {}, { role: 'customer', pages: [], actions: [] },
		{ role: 'owner', pages: [null], actions: [] }, { role: 'owner', pages: [], actions: '*' }]) {
		assert.equal(parseWorkspaceAccess(value), null);
	}
	assert.deepEqual(parseWorkspaceAccess({ role: 'owner', pages: ['Reports'], actions: ['viewIncome'] }),
		{ role: 'owner', pages: ['Reports'], actions: ['viewIncome'] });
});

test('keeps role-specific grouping in the main menu without granting extra sections', () => {
	const owner = { role: 'owner', pages: ['Reports','Staff Access','Bookings','Inventory'], actions: ['manageStaff'] };
	assert.deepEqual(workspaceGroups(owner).map(group => group.label), ['Reports','Accounts','More']);
	assert.deepEqual(workspaceGroups({ ...owner, pages: [...owner.pages, 'Activity log'] }).map(group => group.label),
		['Reports','Accounts','Activity Log','More']);
	assert.deepEqual(workspaceGroups({ role: 'staff', pages: ['Bookings','Booking history'], actions: [] }).map(group => group.label), ['Booking']);
	assert.equal(workspaceLinks({ role: 'staff', pages: ['Staff Access'], actions: ['manageStaff'] }).length, 0);
	assert.equal(workspaceLanding({ role: 'staff', pages: ['Booking history'], actions: [] }), '/booking-history');
});
