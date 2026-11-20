import { error,json } from '@sveltejs/kit';
import { requestSupabase } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';
export const prerender=false;
export const GET:RequestHandler=async event=>{
 const client=requestSupabase(event);
 const {data,error:failure}=await client.rpc('herco_booking_ui_catalog');
 if(failure?.code==='42501')error(403,'Sign in with a verified account.');
 if(failure)error(503,'The service catalog is temporarily unavailable.');
 return json(data);
};
