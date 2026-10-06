import type {Metadata, Viewport} from 'next';
import './globals.css';
export const metadata:Metadata={title:'行迹 · 我的探店本',description:'记录到访时间、评分、感受和照片。你的私人探店本。',manifest:'/manifest.webmanifest',icons:{icon:'/favicon.svg',apple:'/icon.png'},appleWebApp:{capable:true,title:'行迹',statusBarStyle:'default'}};
export const viewport:Viewport={width:'device-width',initialScale:1,themeColor:'#174b3d',viewportFit:'cover'};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="zh-CN"><body>{children}</body></html>}
