// One service line as the staff endpoints return it. Money fields are missing when the viewer may not see income.
export type StaffLine = { code: string; label: string; price_centavos: number; max_centavos?: number | null; quote_required?: boolean; details?: { label: string; price_centavos: number }[] };
export type StaffBooking = {
	id: string; reference?: string; visit_date: string; visit_hour: number | null; bike: string;
	customer_name: string; customer_phone: string; customer_email?: string; plate?: string;
	status: 'pending' | 'confirmed' | 'done' | 'cancelled'; source?: string; created_at?: string;
	approved_at?: string | null; completed_at?: string | null; services: string[];
	original_services?: StaffLine[];
	current_services?: StaffLine[];
	total_centavos?: number; original_total_centavos?: number | null; final_price_centavos?: number | null; coating_options?: Record<string, unknown>;
	approval_note?: string | null; private_completion_note?: string | null; shared_note?: string;
	shared_photos?: number; photo_count?: number; request_pending: boolean; outside_hours?: boolean;
};
export type StaffBookingPermissions = { can_confirm?: boolean; can_cancel?: boolean; can_reschedule?: boolean;
	can_edit_services?: boolean; canComplete?: boolean; canRequestIntake?: boolean; canAdjustPrices?: boolean; past_date?: boolean };
