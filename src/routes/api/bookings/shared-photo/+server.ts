import {createClient} from '@supabase/supabase-js';
import {HERCO_STORAGE_SECRET_KEY,PUBLIC_SUPABASE_URL} from '$app/env/private';
import {error} from '@sveltejs/kit';
import {requestSupabase} from '#lib/server/supabase.ts';
import type {RequestHandler} from './$types';
export const prerender=false;
export const GET:RequestHandler=async event=>{
 const booking=event.url.searchParams.get('booking')??'',index=event.url.searchParams.get('photo')??'';
 if(!/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(booking)||!/^[0-2]$/.test(index))error(400,'Choose a shared booking photo.');
 const {data:share,error:failure}=await requestSupabase(event).rpc('herco_customer_booking_shared',{booking});
 if(failure||!share)error(404,'Shared photo not found.');
 const path=share.photo_paths?.[Number(index)];
 if(typeof path!=='string'||!path.startsWith(booking+'/')||!/^[-a-f0-9/]+\.(jpg|png|webp)$/i.test(path))error(404,'Shared photo not found.');
 if(!HERCO_STORAGE_SECRET_KEY||!PUBLIC_SUPABASE_URL)error(503,'Shared photos are temporarily unavailable.');
 const client=createClient(PUBLIC_SUPABASE_URL,HERCO_STORAGE_SECRET_KEY,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false},global:{fetch:event.fetch}});
 const {data,error:downloadFailure}=await client.storage.from('herco-completion').download(path);
 if(downloadFailure||!data)error(503,'This shared photo is temporarily unavailable.');
 return new Response(data,{headers:{'content-type':path.endsWith('.jpg')?'image/jpeg':path.endsWith('.png')?'image/png':'image/webp','x-content-type-options':'nosniff','cache-control':'private, no-store'}});
};
