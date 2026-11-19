import { defineEnvVars } from '@sveltejs/kit/env';

const optional = (value: string | undefined) => value?.trim() || undefined;
const enabled = (value: string | undefined) => value === 'true';

export const variables = defineEnvVars({
	PUBLIC_SUPABASE_URL: { schema: optional },
	PUBLIC_SUPABASE_PUBLISHABLE_KEY: { schema: optional },
	HERCO_STORAGE_SECRET_KEY: { schema: optional },
	HERCO_AUTH_EMAIL_ENABLED: { schema: enabled },
	HERCO_AUTH_GOOGLE_ENABLED: { schema: enabled },
	HERCO_AUTH_FACEBOOK_ENABLED: { schema: enabled },
	HERCO_GA4_MEASUREMENT_ID: { schema: optional },
	HERCO_GA4_API_SECRET: { schema: optional }
});
