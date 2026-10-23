import './globals.css';
import type {Metadata} from 'next';
export const metadata: Metadata={title:'Coroinhas • Servir é amar',description:'Escalas de coroinhas e coordenação'};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="pt-BR"><body>{children}</body></html>}
