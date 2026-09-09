import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = {title:'Show Me The Money — 주가만, 가볍게.',description:'Mac 메뉴 막대와 Windows에서 확인하는 주가. 현재가, 보유 평가금액, 수익률. 무료 데스크톱 앱.',icons:{icon:'/app-icon.png'}};
export default function Layout({children}:{children:React.ReactNode}) {return <html lang="ko"><body>{children}</body></html>}
