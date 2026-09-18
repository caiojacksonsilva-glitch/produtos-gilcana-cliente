const SUPABASE_URL='https://kpzcvreqjkgevzmlipjs.supabase.co';
const SUPABASE_KEY='sb_publishable_PgFcb8Fu86xyZ1Fiu1ftEQ_664m7EdB';
const sb=window.supabase.createClient(SUPABASE_URL,SUPABASE_KEY,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
let account=null, products=[], recommendedProductIds=[], recommendationQty={}, recommendationCursor=0, selected={}, detailProductId=null, detailQuantity=1, cart=JSON.parse(localStorage.getItem('gilcana-cart-v2')||'{}'), activeChatOrder=null;
const $=s=>document.querySelector(s); const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function toast(t){const e=$('#toast');e.textContent=t;e.classList.add('show');clearTimeout(window.tt);window.tt=setTimeout(()=>e.classList.remove('show'),2400)}
function save(){localStorage.setItem('gilcana-cart-v2',JSON.stringify(cart))}
function normalizePhone(v){return String(v||'').replace(/\D/g,'')}
function artType(n){n=(n||'').toLowerCase();if(n.includes('cenoura'))return'carrot';if(n.includes('beterraba'))return'beet';if(n.includes('pepino'))return'cucumber';if(n.includes('berinjela'))return'eggplant';if(n.includes('tomat'))return'tomato';if(n.includes('cebol')||n.includes('sals')||n.includes('coentro'))return'herbs';if(n.includes('americana'))return'lettuce';return'leafy'}
function productImage(type,name){const sh={leafy:'<path d="M57 18c-22 2-36 18-34 40 2 18 18 30 36 28 20-2 33-19 31-40-2-18-14-30-33-28Z"/><path d="M52 83c3-25 10-42 26-56M54 60c-10-8-18-12-27-13M61 48c8-7 14-11 24-13"/>',lettuce:'<path d="M50 20c8-10 19-5 21 5 13-6 22 3 18 15 12 2 15 15 7 23 5 13-7 23-19 20-7 12-22 9-27 0-12 7-24-3-19-15-12-2-14-17-4-23-6-12 5-23 16-19 0-8 2-13 7-16Z"/>',herbs:'<path d="M51 86V35M50 49C34 48 27 38 28 25c15 0 23 8 22 24ZM52 60c15-1 23-10 22-23-15 0-23 8-22 23Z"/>',carrot:'<path d="M45 38c12-4 24 0 29 8L53 88c-4 7-11 6-13-2L29 47c3-4 8-7 16-9Z"/>',beet:'<path d="M31 48c5-15 30-19 43-8 13 12 8 34-7 43-10 6-24 5-33-4-9-9-9-21-3-31Z"/>',cucumber:'<path d="M20 58c4-18 20-31 39-34 16-3 30 2 32 14 2 12-10 22-26 28-18 7-39 9-45-8Z"/>',eggplant:'<path d="M58 31c20 4 29 19 24 36-6 19-26 25-47 17-13-5-18-17-11-28 7-12 17-20 34-25Z"/>',tomato:'<circle cx="52" cy="57" r="30"/><path d="M52 29c-3-10 1-16 8-20M51 31l-13-8M52 31l12-9"/>'};return `<div class="product-art"><svg viewBox="0 0 104 104">${sh[type]||sh.leafy}</svg></div>`}
function pic(p){return p.imagem_url?`<img class="real-product-image" src="${esc(p.imagem_url)}" alt="${esc(p.nome)}">`:productImage(artType(p.nome),p.nome)}
async function ensureAuth(){let {data:{session}}=await sb.auth.getSession();if(!session){const {error}=await sb.auth.signInAnonymously();if(error)throw new Error('Ative Anonymous Sign-Ins no Supabase Auth.');}}
async function getAccount(){const {data,error}=await sb.rpc('minha_conta');if(error)throw error;return data}
async function boot(){try{await ensureAuth();account=await getAccount();if(account){openApp();await Promise.all([loadCatalog(),loadDeliveryDates(),loadOrders(),loadMessages(),loadNotifications()]);subscribeRealtime()}else showLogin()}catch(e){showLogin(e.message)}}
function showLogin(msg=''){ $('#loginScreen').style.display='grid';$('#appShell').hidden=true;$('#loginError').textContent=msg}
function openApp(){ $('#loginScreen').style.display='none';$('#appShell').hidden=false;$('#hello').textContent='OLÁ, '+String(account.nome_acesso||account.nome_empresa||'CLIENTE').toUpperCase()}
async function activateDevice(){const btn=$('#loginBtn');btn.disabled=true;$('#loginError').textContent='';try{await ensureAuth();const nome=$('#loginName').value.trim(),telefone=normalizePhone($('#loginPhone').value),codigo=$('#loginCode').value.trim();if(!nome||telefone.length<10||codigo.length<4)throw new Error('Preencha nome, WhatsApp e código de acesso.');const {data,error}=await sb.rpc('ativar_aparelho',{p_nome:nome,p_telefone:telefone,p_codigo:codigo});if(error)throw error;account=await getAccount();openApp();await Promise.all([loadCatalog(),loadDeliveryDates(),loadOrders(),loadMessages(),loadNotifications()]);subscribeRealtime();toast('Acesso autorizado.')}catch(e){$('#loginError').textContent=e.message||'Não foi possível entrar.'}finally{btn.disabled=false}}
async function loadCatalog(){const {data,error}=await sb.from('produtos').select('id,nome,descricao,unidade,quantidade_disponivel,imagem_url').eq('ativo',true).order('nome');if(error)throw error;products=data||[];const {data:recs}=await sb.from('produtos_recomendados').select('produto_id,ordem').eq('ativo',true).order('ordem');recommendedProductIds=(recs||[]).map(r=>r.produto_id).filter(id=>products.some(p=>p.id===id)).slice(0,3);if(!recommendedProductIds.length)recommendedProductIds=products.slice(0,3).map(p=>p.id);renderProducts();renderCart()}
function renderProducts(){const q=($('#search')?.value||'').toLowerCase();$('#products').innerHTML=products.filter(p=>p.nome.toLowerCase().includes(q)).map(p=>`<article class="product"><div class="pic" onclick="openProductDetail(${p.id})" title="Ver detalhes">${pic(p)}</div><div class="body"><h3 class="product-title-link" onclick="openProductDetail(${p.id})">${esc(p.nome)}</h3><small>${esc(p.unidade)} • ${Number(p.quantidade_disponivel)} disponíveis</small><div class="selector"><button onclick="qty(${p.id},-1)">−</button><b id="q${p.id}">${selected[p.id]||0}</b><button onclick="qty(${p.id},1)">+</button></div><button class="add" onclick="add(${p.id})">Adicionar</button></div></article>`).join('')||'<div class="card">Nenhum produto disponível.</div>'}
async function openProductDetail(id){const p=getP(id);if(!p)return;detailProductId=p.id;detailQuantity=1;$('#detailQty').textContent='1';$('#productDetailName').textContent=p.nome;let imgs=[];try{const r=await sb.from('produto_imagens').select('imagem_url,ordem').eq('produto_id',p.id).order('ordem');if(!r.error)imgs=(r.data||[]).map(x=>x.imagem_url).filter(Boolean)}catch(e){}if(p.imagem_url&&!imgs.includes(p.imagem_url))imgs.unshift(p.imagem_url);$('#productDetailGallery').innerHTML=imgs.length?imgs.map(u=>`<div><img src="${esc(u)}" alt="${esc(p.nome)}"></div>`).join(''):`<div>${productImage(artType(p.nome),p.nome)}</div>`;$('#productDetailText').innerHTML=`<h3>${esc(p.nome)}</h3><p>${esc(p.descricao||'Sem descrição cadastrada.')}</p><p><b>Unidade:</b> ${esc(p.unidade)}<br><b>Disponível:</b> ${Number(p.quantidade_disponivel)}</p>`;showPage('productDetail')}
function detailQty(delta){const p=getP(detailProductId);if(!p)return;detailQuantity=Math.max(1,Math.min(Number(p.quantidade_disponivel)||1,detailQuantity+delta));$('#detailQty').textContent=detailQuantity}
function addFromDetail(){const p=getP(detailProductId);if(!p)return;cart[p.id]=(Number(cart[p.id])||0)+detailQuantity;save();renderCart();toast(detailQuantity+' '+p.unidade+' de '+p.nome+' adicionado ao carrinho.');detailQuantity=1;$('#detailQty').textContent='1'}
function getP(id){return products.find(p=>p.id===Number(id))}
function qty(id,d){const p=getP(id);selected[id]=Math.max(0,Math.min(Number(p.quantidade_disponivel),(selected[id]||0)+d));$('#q'+id).textContent=selected[id]}
function add(id){const n=selected[id]||0,p=getP(id);if(!n)return toast('Selecione a quantidade primeiro.');cart[id]=Math.min(Number(p.quantidade_disponivel),(cart[id]||0)+n);selected[id]=0;save();renderProducts();renderCart();toast('✓ '+p.nome+' adicionado ao carrinho.')}
function change(id,d){cart[id]=Math.max(0,(cart[id]||0)+d);if(!cart[id])delete cart[id];save();renderCart()}
function recommendationChange(id,d){const p=getP(id);recommendationQty[id]=Math.max(0,Math.min(Number(p.quantidade_disponivel),(recommendationQty[id]||0)+d));const e=$('#rq'+id);if(e)e.textContent=recommendationQty[id]}
function nextRecommendation(exclude){const visible=new Set(recommendedProductIds);for(const p of products){if(p.id!==exclude&&!visible.has(p.id)&&!cart[p.id])return p.id}return exclude}
function addRecommendation(id){const n=recommendationQty[id]||0,p=getP(id);if(!n)return toast('Selecione a quantidade primeiro.');cart[id]=Math.min(Number(p.quantidade_disponivel),(cart[id]||0)+n);recommendationQty[id]=0;const pos=recommendedProductIds.indexOf(id);if(pos>=0)recommendedProductIds[pos]=nextRecommendation(id);save();renderCart();toast('✓ '+p.nome+' adicionado ao carrinho.')}
function renderCart(){const ids=Object.keys(cart).map(Number).filter(id=>getP(id));$('#cartCount').textContent=ids.reduce((a,id)=>a+Number(cart[id]),0);$('#cartItems').innerHTML=ids.length?ids.map(id=>{const p=getP(id);return `<div class="cartitem"><div><b>${esc(p.nome)}</b><small>${esc(p.unidade)}</small></div><div class="cartqty"><button onclick="change(${id},-1)">−</button><b>${cart[id]}</b><button onclick="change(${id},1)">+</button></div></div>`}).join(''):'<div class="card"><b>Seu carrinho está vazio.</b><p>Volte aos produtos para começar o pedido.</p></div>';$('#recommend').innerHTML=recommendedProductIds.map(id=>{const p=getP(id);if(!p)return'';return `<article class="recommend-card"><div class="recommend-pic">${pic(p)}</div><b>${esc(p.nome)}</b><small>${esc(p.unidade)} • ${Number(p.quantidade_disponivel)} disponíveis</small><div class="recommend-selector"><button onclick="recommendationChange(${id},-1)">−</button><b id="rq${id}">${recommendationQty[id]||0}</b><button onclick="recommendationChange(${id},1)">+</button></div><button class="recommend-add" onclick="addRecommendation(${id})">Adicionar</button></article>`}).join('')}
function fmtDate(d){return new Intl.DateTimeFormat('pt-BR',{weekday:'long',day:'2-digit',month:'2-digit',year:'numeric',timeZone:'America/Sao_Paulo'}).format(new Date(d+'T12:00:00-03:00'))}
async function loadDeliveryDates(){
  const {data,error}=await sb.rpc('minhas_datas_entrega');
  const select=$('#delivery'), choices=$('#deliveryChoices');
  if(error){console.error(error);select.innerHTML='<option value="">Erro</option>';choices.innerHTML='<div class="delivery-empty">Não foi possível carregar as datas.</div>';return}
  const rows=data||[];
  select.innerHTML=rows.map(x=>`<option value="${x.data_entrega}">${fmtDate(x.data_entrega)}</option>`).join('')||'<option value="">Nenhuma data disponível</option>';
  choices.innerHTML=rows.map((x,i)=>{const d=new Date(x.data_entrega+'T12:00:00-03:00');const wd=new Intl.DateTimeFormat('pt-BR',{weekday:'short',timeZone:'America/Sao_Paulo'}).format(d).replace('.','');const day=String(d.getDate()).padStart(2,'0');const mon=new Intl.DateTimeFormat('pt-BR',{month:'short',timeZone:'America/Sao_Paulo'}).format(d).replace('.','');return `<button type="button" class="delivery-choice ${i===0?'selected':''}" onclick="selectDelivery('${x.data_entrega}',this)"><span>${wd}</span><b>${day}</b><small>${mon}</small><i>✓</i></button>`}).join('')||'<div class="delivery-empty">Nenhuma data disponível.</div>';
  if(rows.length)select.value=rows[0].data_entrega;
}
function selectDelivery(value,el){$('#delivery').value=value;document.querySelectorAll('.delivery-choice').forEach(x=>x.classList.remove('selected'));el.classList.add('selected')}
function requestFinish(){if(!Object.keys(cart).length)return toast('Adicione pelo menos um produto.');if(!$('#delivery').value)return toast('Nenhuma data de entrega disponível.');$('#confirmDeliveryDate').textContent=fmtDate($('#delivery').value);const er=$('#orderSubmitError');if(er)er.textContent='';$('#modal').classList.add('open')}
function closeModal(){$('#modal').classList.remove('open')}
async function finishOrder(){const btn=$('#confirmOrderBtn'),errBox=$('#orderSubmitError');if(btn.disabled)return;btn.disabled=true;btn.textContent='Enviando…';if(errBox)errBox.textContent='';try{const itens=Object.entries(cart).filter(([,q])=>Number(q)>0).map(([id,q])=>({produto_id:Number(id),quantidade:Number(q)}));if(!itens.length)throw new Error('O pedido está vazio.');const delivery=$('#delivery').value;const {data,error}=await sb.rpc('criar_meu_pedido',{p_data_entrega:delivery,p_itens:itens});if(error)throw error;if(!data)throw new Error('O servidor não devolveu o número do pedido.');cart={};save();closeModal();await loadCatalog();await loadOrders();await loadMessages();await loadNotifications();$('#successOrderText').textContent='Pedido #'+data+' enviado com sucesso. Acompanhe o status em Meus pedidos.';$('#successModal').classList.add('open')}catch(e){const msg=e?.message||'Não foi possível enviar o pedido.';console.error('Erro ao criar pedido',e);if(errBox)errBox.textContent=msg;toast('Pedido não enviado. Veja o erro na confirmação.')}finally{btn.disabled=false;btn.textContent='Sim, confirmar'}}
function closeSuccessModal(){$('#successModal').classList.remove('open');showPage('orders')}
function statusLabel(s){return {enviado:'Enviado',recebido:'Recebido',confirmado:'Em preparação',pronto_envio:'Pronto para envio',cancelado:'Cancelado'}[s]||s}
async function loadOrders(){if(!account)return;const {data,error}=await sb.rpc('listar_meus_pedidos');if(error){console.error(error);$('#ordersList').innerHTML='<div class="card"><b>Não foi possível carregar seus pedidos.</b><p>'+esc(error.message||'Erro desconhecido')+'</p></div>';return;}const rows=Array.isArray(data)?data:[];$('#ordersList').innerHTML=rows.map(o=>{const itens=o.itens||[];const resumo=itens.slice(0,2).map(i=>`${Number(i.quantidade)} ${esc(i.unidade||'')} — ${esc(i.nome||'Produto')}`).join(' · ')+(itens.length>2?' · +'+(itens.length-2)+' item(ns)':'');const cls=o.status==='confirmado'||o.status==='pronto_envio'?'confirmed':o.status==='recebido'?'received':o.status==='cancelado'?'cancelled':'sent';const details=itens.map(i=>`<div class="order-detail-item"><span><b>${esc(i.nome||'Produto')}</b><br><small>${esc(i.unidade||'')}</small></span><b>${Number(i.quantidade)}</b></div>`).join('');return `<article class="order"><div class="order-top"><b>Pedido #${o.numero||o.id}</b><span class="status ${cls}">${statusLabel(o.status)}</span></div><p><b>Entrega:</b> ${fmtDate(o.data_entrega)}</p><p class="order-meta">Feito em ${new Date(o.criado_em).toLocaleString('pt-BR')}</p><p>${resumo}</p><div class="order-actions"><button onclick="toggleOrderStatus('dt${o.id}')">Ver detalhes</button><button onclick="openOrderChat(${o.id})">Falar no chat</button></div><div id="dt${o.id}" class="order-details"><h4>Produtos encomendados</h4>${details}<p><b>Data de entrega:</b> ${fmtDate(o.data_entrega)}</p><p><b>Status:</b> ${statusLabel(o.status)}</p></div></article>`}).join('')||'<div class="card">Você ainda não possui pedidos.</div>'}
function toggleOrderStatus(id){$('#'+id)?.classList.toggle('open')}
function statusSteps(s){if(s==='cancelado')return '<div class="status-step done"><i></i><span>Pedido enviado</span></div><div class="status-step cancelled-step"><i></i><span>Pedido cancelado</span></div>';const n={enviado:1,recebido:2,confirmado:3,pronto_envio:4}[s]||1;return ['Pedido enviado','Pedido recebido','Pedido em preparação','Pronto para envio'].map((x,i)=>`<div class="status-step ${i<n?'done':''}"><i></i><span>${i<n?x:(i===1?'Aguardando recebimento':'Aguardando confirmação')}</span></div>`).join('')}
async function openOrderChat(id){activeChatOrder=id;showPage('chat');await loadMessages()}
async function loadMessages(){
 if(!account)return;
 const box=$('#messages'),err=$('#chatError'); if(err)err.textContent='';
 const {data,error}=await sb.rpc('listar_minhas_mensagens_v2',{p_pedido_id:activeChatOrder||null});
 if(error){console.error('Erro ao carregar chat',error);if(err)err.textContent='Erro ao carregar conversa: '+(error.message||'erro desconhecido');return;}
 const rows=Array.isArray(data)?data:[];
 box.innerHTML=rows.map(m=>`<div class="bubble ${m.remetente==='cliente'?'me':m.remetente==='sistema'?'system':'them'}" data-message-id="${m.id}">${esc(m.mensagem)}</div>`).join('')||'<div class="bubble system">Envie uma mensagem para a Produtos Gilçana.</div>';
 requestAnimationFrame(()=>box.scrollTop=box.scrollHeight)
}
let chatSending=false;
async function sendChatMessage(){
 const input=$('#chatInput'),err=$('#chatError'),text=input.value.trim(); if(!text||chatSending)return;
 chatSending=true; if(err)err.textContent='';
 const temp=document.createElement('div');temp.className='bubble me sending';temp.textContent=text;$('#messages').appendChild(temp);$('#messages').scrollTop=$('#messages').scrollHeight;
 input.value=''; input.disabled=true;
 try{
   const {data,error}=await sb.rpc('enviar_minha_mensagem_v2',{p_pedido_id:activeChatOrder||null,p_mensagem:text});
   if(error)throw error;
   temp.classList.remove('sending'); if(data?.id)temp.dataset.messageId=data.id;
   await loadMessages();
 }catch(e){
   console.error('Erro ao enviar chat',e); temp.classList.add('failed'); temp.textContent=text+' — não enviada'; input.value=text;
   if(err)err.textContent='Não foi possível enviar: '+(e?.message||'erro desconhecido');
 }finally{input.disabled=false;chatSending=false;input.focus()}
}
async function loadNotifications(){if(!account)return;const {data}=await sb.from('notificacoes').select('*').eq('cliente_id',account.cliente_id).order('criado_em',{ascending:false}).limit(50);const rows=data||[];$('#noticeCount').textContent=rows.filter(n=>!n.lida).length;$('#noticeCount').style.display=rows.some(n=>!n.lida)?'block':'none';$('#notificationsList').innerHTML=rows.map(n=>`<div class="notice"><i class="notice-dot ${n.tipo?.includes('confirm')?'green':'yellow'}"></i><span><b>${esc(n.titulo)}</b><br>${esc(n.mensagem)}</span></div>`).join('')||'<div class="card">Nenhuma notificação.</div>'}
async function markNotificationsRead(){await sb.rpc('marcar_minhas_notificacoes_lidas');setTimeout(loadNotifications,300)}
async function loadAccountPage(){
  if(!account)return;
  $('#accountName').textContent=account.nome_empresa||account.nome_cliente||'Cliente';
  $('#accountPhone').textContent='WhatsApp: '+(account.telefone||'');
  $('#notificationsToggle').checked=account.notificacoes_ativas!==false;
  const {data,error}=await sb.rpc('minha_pessoa_autorizada');
  if(error){$('#authorizedPerson').innerHTML='<p class="muted">Não foi possível carregar.</p>';return}
  const box=$('#authorizedPerson'), form=$('#authorizedForm');
  if(data&&data.id){box.innerHTML=`<div class="authorized-current"><div><b>${esc(data.nome)}</b><small>${esc(data.telefone)}</small></div><button class="danger-outline" onclick="removeAuthorizedPerson()">Remover</button></div>`;form.style.display='none'}
  else{box.innerHTML='';form.style.display='grid'}
}
async function setNotifications(enabled){
  const {error}=await sb.rpc('definir_minhas_notificacoes',{p_ativas:enabled});
  if(error){$('#notificationsToggle').checked=!enabled;return toast('Não foi possível alterar as notificações.')}
  account.notificacoes_ativas=enabled;toast(enabled?'Notificações ativadas.':'Notificações desativadas.')
}
async function saveAuthorizedPerson(){
  const nome=$('#authorizedName').value.trim(), telefone=normalizePhone($('#authorizedPhone').value), codigo=$('#authorizedCode').value.trim();
  if(!nome||telefone.length<10||codigo.length<4)return toast('Preencha nome, WhatsApp e código.');
  const {error}=await sb.rpc('salvar_minha_pessoa_autorizada',{p_nome:nome,p_telefone:telefone,p_codigo:codigo});
  if(error)return toast('Erro: '+error.message);
  $('#authorizedName').value='';$('#authorizedPhone').value='';$('#authorizedCode').value='';await loadAccountPage();toast('Pessoa autorizada cadastrada.')
}
async function removeAuthorizedPerson(){
  if(!confirm('Deseja remover a pessoa autorizada?'))return;
  const {error}=await sb.rpc('remover_minha_pessoa_autorizada');if(error)return toast('Erro: '+error.message);await loadAccountPage();toast('Pessoa autorizada removida.')
}
function showPage(id){document.querySelectorAll('.page').forEach(x=>x.classList.remove('active'));$('#'+id).classList.add('active');document.querySelectorAll('nav button').forEach(x=>x.classList.toggle('active',x.dataset.page===id));$('#cartBar').style.display=id==='shop'?'flex':'none';if(id==='cart')renderCart();if(id==='orders')loadOrders();if(id==='chat')loadMessages();if(id==='accountPage')loadAccountPage();window.scrollTo(0,0)}
function subscribeRealtime(){sb.channel('gilcana-cliente').on('postgres_changes',{event:'*',schema:'public',table:'pedidos'},()=>loadOrders()).on('postgres_changes',{event:'*',schema:'public',table:'mensagens'},()=>loadMessages()).on('postgres_changes',{event:'*',schema:'public',table:'notificacoes'},()=>loadNotifications()).on('postgres_changes',{event:'*',schema:'public',table:'produtos'},()=>loadCatalog()).subscribe()}
boot();if('serviceWorker'in navigator)window.addEventListener('load',()=>navigator.serviceWorker.register('./sw.js'));


// Bloqueia gestos de zoom no app (pinch/double tap), mantendo rolagem e toques normais.
let lastTouchEnd = 0;
document.addEventListener('gesturestart', (e) => e.preventDefault(), { passive: false });
document.addEventListener('gesturechange', (e) => e.preventDefault(), { passive: false });
document.addEventListener('gestureend', (e) => e.preventDefault(), { passive: false });
document.addEventListener('touchend', (e) => {
  const now = Date.now();
  if (now - lastTouchEnd <= 300) e.preventDefault();
  lastTouchEnd = now;
}, { passive: false });
