import {env} from 'cloudflare:workers';
import {identity,json,failure} from '@/lib/server';
export async function GET(req:Request){try{await identity(req);return json({key:env.AMAP_JS_KEY||null,enabled:!!(env.AMAP_JS_KEY&&env.AMAP_SECURITY_CODE)})}catch(e){return failure(e)}}
