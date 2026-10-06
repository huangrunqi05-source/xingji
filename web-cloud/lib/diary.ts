import {z} from 'zod';
export const visitSchema=z.object({id:z.string().uuid(),placeKey:z.string().min(1).max(200),name:z.string().trim().min(1,'请填写店名').max(100),address:z.string().trim().max(250),category:z.enum(['餐厅','咖啡','购物','其他']),arrived:z.string().datetime(),departed:z.string().datetime().nullable(),rating:z.number().min(.5).max(5).multipleOf(.5).nullable(),note:z.string().max(5000),location:z.object({lat:z.number().min(-90).max(90),lng:z.number().min(-180).max(180),system:z.enum(['WGS84','GCJ02']),source:z.enum(['browser','amap']),accuracy:z.number().nonnegative().nullable()}).nullable()}).refine(v=>!v.departed||Date.parse(v.departed)>=Date.parse(v.arrived),{message:'离开时间不能早于到达时间'});
export type Visit=z.infer<typeof visitSchema>&{photoIds:string[]};
export type Snapshot={id:string;name:string;address:string;category:string;date:string;rating:number|null;note:string;photoIds:string[]};
export type DiaryList={id:string;title:string;created:string;items:Snapshot[]};
export function average(visits:Pick<Visit,'rating'>[]){const rated=visits.filter(v=>v.rating!==null);return rated.length?rated.reduce((s,v)=>s+v.rating!,0)/rated.length:null}
export function chinaDate(value:string){return new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Shanghai',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(value))}
export function escapeHtml(s:string){return s.replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!))}
// Remove EXIF/GPS, IPTC and comments while preserving JPEG pixels and color profile.
export function stripJpegMetadata(bytes:Uint8Array){
 if(bytes[0]!==255||bytes[1]!==216)throw new Error('照片必须转换成 JPEG');
 const chunks:Uint8Array[]=[bytes.slice(0,2)];let i=2;let ended=false;
 while(i<bytes.length){if(bytes[i]!==255)throw new Error('照片文件损坏');const marker=bytes[i+1];
 if(marker===218){chunks.push(bytes.slice(i));ended=true;break;}
 if(marker===217){chunks.push(bytes.slice(i,i+2));ended=true;break;}
 const length=(bytes[i+2]<<8)+bytes[i+3];if(length<2||i+length+2>bytes.length)throw new Error('照片文件损坏');
 if(marker!==225&&marker!==237&&marker!==254)chunks.push(bytes.slice(i,i+length+2));i+=length+2;}
 if(!ended)throw new Error('照片文件不完整');const output=new Uint8Array(chunks.reduce((s,c)=>s+c.length,0));let off=0;for(const c of chunks){output.set(c,off);off+=c.length}return output;
}
