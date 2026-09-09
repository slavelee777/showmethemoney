import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = {title:'Show Me The Money — 맥 메뉴바 주식 앱 · Stock Ticker',description:'맥 메뉴바와 윈도우 작업표시줄에서 주가를 확인하는 무료 앱. Free lightweight stock ticker for macOS and Windows. 한국·미국 주식, 보유 평가금액과 수익률.',icons:{icon:'/app-icon.png'}};
export default function Layout({children}:{children:React.ReactNode}) {return <html lang="ko"><body>{children}</body></html>}
