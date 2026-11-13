'use client';
import {useEffect,useState} from 'react';
import './preview.css';
export default function Homologacao(){
 const [title,setTitle]=useState('Novidade no Escala São Bento');
 const [body,setBody]=useState('Confira os avisos da coordenação.');
 const [image,setImage]=useState('');
 const [open,setOpen]=useState(false);
 const [dismiss,setDismiss]=useState(false);
 useEffect(()=>()=>{if(image.startsWith('blob:'))URL.revokeObjectURL(image)},[image]);
 return <main className="preview-root"><div className="preview-top">ESCALA SÃO BENTO <span>AMBIENTE DE TESTES</span></div><section className="preview-panel"><h1>Prévia dos avisos pop-up</h1><p>Teste a aparência do aviso no celular. Este formulário usa apenas dados locais, sem publicar mensagens para ninguém.</p><label>Título<input value={title} onChange={e=>setTitle(e.target.value)} maxLength={160}/></label><label>Mensagem (opcional)<textarea value={body} onChange={e=>setBody(e.target.value)} rows={3}/></label><label>Imagem (opcional)<input type="file" accept="image/png,image/jpeg,image/webp" onChange={e=>{const f=e.target.files?.[0];if(f&&f.type.startsWith('image/'))setImage(URL.createObjectURL(f))}}/></label>{image&&<button className="preview-secondary" onClick={()=>setImage('')}>Remover imagem</button>}<button className="preview-primary" onClick={()=>{setDismiss(false);setOpen(true)}} disabled={!title.trim()||(!body.trim()&&!image)}>Visualizar pop-up</button></section>{open&&<div className="screen-popup-overlay"><section className="screen-popup-card" role="dialog" aria-modal="true" aria-label={title}><div className="screen-popup-heading"><h2>{title}</h2><button className="preview-close" aria-label="Fechar" onClick={()=>setOpen(false)}>×</button></div>{image&&<img src={image} className="screen-popup-image" alt="Imagem do aviso"/>}{body&&<p>{body}</p>}<label className="screen-popup-check"><input type="checkbox" checked={dismiss} onChange={e=>setDismiss(e.target.checked)}/> Não mostrar novamente</label><button className="preview-primary" onClick={()=>setOpen(false)}>OK, entendi</button></section></div>}</main>
}
