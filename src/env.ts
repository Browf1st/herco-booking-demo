import { defineEnvVars } from '@sveltejs/kit/env';

const optional = (value: string | undefined) => value?.trim() || undefined;
const enabled = (value: string | undefined) => value === 'true';
// Must match Supabase → Authentication → Email → "Email OTP length" (6-10). Defaults to Supabase's 6.
const otpLength = (value: string | undefined) => {
	const length = Number(value?.trim() || 6);
	return Number.isInteger(length) && length >= 6 && length <= 10 ? length : 6;
};

export const variables = defineEnvVars({
	PUBLIC_SUPABASE_URL: { schema: optional },
	PUBLIC_SUPABASE_PUBLISHABLE_KEY: { schema: optional },
	HERCO_STORAGE_SECRET_KEY: { schema: optional },
	HERCO_REMINDER_TOKEN_SECRET: { schema: optional },
	HERCO_AUTH_EMAIL_ENABLED: { schema: enabled },
	HERCO_AUTH_GOOGLE_ENABLED: { schema: enabled },
	HERCO_AUTH_FACEBOOK_ENABLED: { schema: enabled },
	HERCO_AUTH_OTP_LENGTH: { schema: otpLength },
	HERCO_GA4_MEASUREMENT_ID: { schema: optional },
	HERCO_GA4_API_SECRET: { schema: optional }
});
