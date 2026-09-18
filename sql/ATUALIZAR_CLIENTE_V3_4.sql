-- Produtos Gilçana Cliente V3.4 — correção de pedidos, chat e histórico
-- Execute no MESMO projeto Supabase. Idempotente.
begin;

-- Chat do cliente: grava diretamente em mensagens, sem depender da função antiga enviar_mensagem.
create or replace function public.enviar_minha_mensagem(p_pedido_id bigint,p_mensagem text)
returns bigint language plpgsql security definer set search_path='' as $$
declare v_d public.dispositivos_cliente%rowtype; v_texto text; v_id bigint;
begin
  select * into v_d from public.dispositivos_cliente where auth_uid=auth.uid() and ativo=true limit 1;
  if not found then raise exception 'Aparelho não autorizado.'; end if;
  v_texto:=trim(coalesce(p_mensagem,''));
  if v_texto='' then raise exception 'A mensagem está vazia.'; end if;
  if p_pedido_id is not null and not exists(select 1 from public.pedidos where id=p_pedido_id and cliente_id=v_d.cliente_id) then raise exception 'Pedido inválido.'; end if;
  insert into public.mensagens(cliente_id,pedido_id,remetente,mensagem)
  values(v_d.cliente_id,p_pedido_id,'cliente',v_texto) returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.enviar_minha_mensagem(bigint,text) from public,anon;
grant execute on function public.enviar_minha_mensagem(bigint,text) to authenticated;

-- Mensagens automáticas de status também gravam diretamente, para nunca cancelar uma criação de pedido.
create or replace function public.chat_status_pedido_cliente()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_texto text;
begin
  if tg_op='INSERT' then
    v_texto:='Pedido recebido. Recebemos o seu pedido #'||coalesce(new.numero::text,new.id::text)||'.';
  elsif new.status is distinct from old.status then
    case new.status
      when 'recebido' then v_texto:='Pedido recebido. O seu pedido #'||coalesce(new.numero::text,new.id::text)||' foi recebido.';
      when 'confirmado' then v_texto:='Pedido em preparação. O seu pedido #'||coalesce(new.numero::text,new.id::text)||' foi confirmado e entrou em preparação.';
      when 'pronto_envio' then v_texto:='Pedido pronto para envio. O seu pedido #'||coalesce(new.numero::text,new.id::text)||' está pronto para envio.';
      when 'cancelado' then v_texto:='Pedido cancelado. O pedido #'||coalesce(new.numero::text,new.id::text)||' foi cancelado.';
      else v_texto:=null;
    end case;
  end if;
  if v_texto is not null then
    insert into public.mensagens(cliente_id,pedido_id,remetente,mensagem)
    values(new.cliente_id,new.id,'sistema',v_texto);
  end if;
  return new;
end; $$;
drop trigger if exists trg_chat_status_pedido_cliente on public.pedidos;
create trigger trg_chat_status_pedido_cliente after insert or update of status on public.pedidos
for each row execute function public.chat_status_pedido_cliente();

-- Histórico via RPC: evita que relacionamento/RLS do navegador esconda os pedidos ou itens.
create or replace function public.listar_meus_pedidos()
returns jsonb language sql security definer set search_path='' stable as $$
with d as (
  select cliente_id from public.dispositivos_cliente where auth_uid=auth.uid() and ativo=true limit 1
), rows as (
  select p.id,p.numero,p.data_entrega,p.status,p.criado_em,
    coalesce((select jsonb_agg(jsonb_build_object('quantidade',i.quantidade,'nome',pr.nome,'unidade',pr.unidade,'descricao',pr.descricao) order by i.id)
      from public.itens_pedido i join public.produtos pr on pr.id=i.produto_id where i.pedido_id=p.id),'[]'::jsonb) itens
  from public.pedidos p join d on d.cliente_id=p.cliente_id
  order by p.criado_em desc
)
select coalesce(jsonb_agg(to_jsonb(rows)),'[]'::jsonb) from rows;
$$;
revoke all on function public.listar_meus_pedidos() from public,anon;
grant execute on function public.listar_meus_pedidos() to authenticated;

commit;
