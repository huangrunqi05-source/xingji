import {env} from 'cloudflare:workers';
import {getChatGPTUser} from '@/app/chatgpt-auth';
export class HttpError extends Error{constructor(public status:number,message:string){super(message)}}
export function db(){if(!env.DB)throw new HttpError(503,'记录服务暂时不可用，请稍后重试');return env.DB}
export function bucket(){if(!env.BUCKET)throw new HttpError(503,'照片服务暂时不可用，请稍后重试');return env.BUCKET}
export async function identity(request:Request){const user=await getChatGPTUser();if(!user)throw new HttpError(401,'请先登录，再保存你的私人记录');if(request.method!=='GET'){const origin=request.headers.get('origin');if(origin&&origin!==new URL(request.url).origin)throw new HttpError(403,'请求来源不正确')}return user.userId}
export function json(data:unknown,status=200){return Response.json(data,{status,headers:{'Cache-Control':'private, no-store'}})}
export function failure(error:unknown){if(error instanceof HttpError)return json({error:error.message},error.status);if(error&&typeof error==='object'&&'issues'in error)return json({error:'请检查记录内容、评分和时间'},400);console.error('Diary request failed',error);return json({error:'暂时无法完成，请保留当前内容并重试'},503)}
export async function ownedVisit(owner:string,id:string){const row=await db().prepare('SELECT payload FROM visits WHERE id=? AND owner=?').bind(id,owner).first<{payload:string}>();if(!row)throw new HttpError(404,'没有找到这条到访');return JSON.parse(row.payload)}
export async function ownedList(owner:string,id:string){const row=await db().prepare('SELECT * FROM lists WHERE id=? AND owner=?').bind(id,owner).first();if(!row)throw new HttpError(404,'没有找到这个清单');return row}
