export type RewardReceipt = {
	id: string;
	reference: string;
	memberId: string;
	memberName: string;
	reward: string;
	cost: number;
	balanceBefore: number;
	balanceAfter: number;
	at: string;
	status: 'pending' | 'approved' | 'issued' | 'claimed';
	claimedAt?: string;
	claimedBy?: string;
};

export function rewardStatus(receipt: RewardReceipt) {
	if (receipt.status === 'pending') return 'Pending for approval';
	return receipt.status === 'claimed' ? 'Claimed' : 'Approved';
}
