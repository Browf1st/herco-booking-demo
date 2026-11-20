import {error,json} from '@sveltejs/kit';
import {requestSupabase} from '#lib/server/supabase.ts';
import type {RequestHandler} from './$types';
export const prerender=false;
export const GET:RequestHandler=async event=>{
 const booking=event.url.searchParams.get('booking')??'';
 if(!/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(booking))error(400,'Choose a booking.');
 const {data,error:failure}=await requestSupabase(event).rpc('herco_customer_booking_shared',{booking});
 if(failure?.code==='42501')error(404,'Booking not found.');
 if(failure)error(503,'Shared booking details are temporarily unavailable.');
 return json({note:data?.note??'',photoCount:data?.photo_paths?.length??0,sharedAt:data?.shared_at??null});
};
