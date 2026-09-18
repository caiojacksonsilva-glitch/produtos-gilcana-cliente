import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
const cors={'Content-Type':'application/json'}
const b64url=(v:Uint8Array|string)=>{const s=typeof v==='string'?btoa(unescape(encodeURIComponent(v))):btoa(String.fromCharCode(...v));return s.replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_')}
async function accessToken(sa:any){
 const now=Math.floor(Date.now()/1000),head=b64url(JSON.stringify({alg:'RS256',typ:'JWT'})),body=b64url(JSON.stringify({iss:sa.client_email,scope:'https://www.googleapis.com/auth/firebase.messaging',aud:'https://oauth2.googleapis.com/token',iat:now,exp:now+3600}));
 const pem=sa.private_key.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\n/g,'');const raw=Uint8Array.from(atob(pem),c=>c.charCodeAt(0));
 const key=await crypto.subtle.importKey('pkcs8',raw,{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']);
 const sig=new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,new TextEncoder().encode(head+'.'+body)));const jwt=head+'.'+body+'.'+b64url(sig);
 const r=await fetch('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion:jwt})});const j=await r.json();if(!r.ok)throw new Error(j.error_description||'OAuth Firebase falhou');return j.access_token;
}
Deno.serve(async req=>{
 try{
  const secret=req.headers.get('x-gilcana-webhook-secret');if(!secret||secret!==Deno.env.get('GILCANA_WEBHOOK_SECRET'))return new Response('unauthorized',{status:401});
  const payload=await req.json(),table=payload.table||payload.type?.split(':')?.[0],row=payload.record||payload.new||{};
  let clienteId=row.cliente_id,title='',body='',link='https://caiojacksonsilva-glitch.github.io/produtos-gilcana-cliente/';
  if(table==='notificacoes'){title=row.titulo||'Produtos Gilçana';body=row.mensagem||'Você tem uma nova atualização.'}
  else if(table==='mensagens'&&row.remetente==='gerente'){title='Nova mensagem — Produtos Gilçana';body=String(row.mensagem||'Você recebeu uma nova mensagem.').slice(0,180)}
  else return new Response(JSON.stringify({ignored:true}),{headers:cors});
  if(!clienteId)return new Response(JSON.stringify({ignored:true,reason:'sem cliente'}),{headers:cors});
  const sb=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const {data:cli}=await sb.from('clientes').select('notificacoes_ativas').eq('id',clienteId).maybeSingle();if(cli?.notificacoes_ativas===false)return new Response(JSON.stringify({ignored:true,reason:'desativado'}),{headers:cors});
  const {data:devs,error}=await sb.from('push_dispositivos').select('id,token').eq('cliente_id',clienteId).eq('ativo',true);if(error)throw error;if(!devs?.length)return new Response(JSON.stringify({sent:0}),{headers:cors});
  const sa=JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON')!);const token=await accessToken(sa);let sent=0;
  for(const d of devs){const r=await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({message:{token:d.token,notification:{title,body},webpush:{fcm_options:{link}}}})});if(r.ok)sent++;else{const t=await r.text();if(t.includes('UNREGISTERED')||t.includes('registration-token-not-registered'))await sb.from('push_dispositivos').update({ativo:false}).eq('id',d.id);console.error(t)}}
  return new Response(JSON.stringify({sent}),{headers:cors});
 }catch(e){console.error(e);return new Response(JSON.stringify({error:String(e?.message||e)}),{status:500,headers:cors})}
})
