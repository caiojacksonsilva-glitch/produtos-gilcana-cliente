-- Produtos Gilçana Cliente V3.6 — pedido + chat robustos
-- Execute no mesmo projeto Supabase. Idempotente.
begin;

-- O gatilho de mensagens de status nunca pode cancelar um pedido.
create or replace function public.chat_status_pedido_cliente()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare v_texto text;
begin
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
  exception when others then
    -- Falha no chat não pode desfazer criação/alteração do pedido.
    null;
  end;
  return new;
end;
$$;

drop trigger if exists trg_chat_status_pedido_cliente on public.pedidos;
create trigger trg_chat_status_pedido_cliente
after insert or update of status on public.pedidos
for each row execute function public.chat_status_pedido_cliente();

-- Wrapper autenticado do pedido. Valida aparelho/data/itens e deixa o erro real chegar ao app.
create or replace function public.criar_meu_pedido(p_data_entrega date,p_itens jsonb)
returns bigint
language plpgsql
security definer
set search_path=''
as $$
declare
  v_d public.dispositivos_cliente%rowtype;
  v_id bigint;
begin
  select * into v_d
  from public.dispositivos_cliente
  where auth_uid=auth.uid() and ativo=true
  limit 1;
  if not found then raise exception 'Aparelho não autorizado.'; end if;
  if p_data_entrega is null then raise exception 'Selecione a data de entrega.'; end if;
  if not exists(select 1 from public.minhas_datas_entrega() x where x.data_entrega=p_data_entrega) then
    raise exception 'Essa data de entrega não está mais disponível. Atualize as datas e tente novamente.';
  end if;
  if p_itens is null or jsonb_typeof(p_itens)<>'array' or jsonb_array_length(p_itens)=0 then
    raise exception 'O pedido está vazio.';
  end if;

  v_id := public.criar_pedido(v_d.cliente_id,v_d.pessoa_autorizada_id,p_data_entrega,p_itens);
  if v_id is null then raise exception 'O pedido não retornou um número válido.'; end if;
  return v_id;
end;
$$;
revoke all on function public.criar_meu_pedido(date,jsonb) from public,anon;
grant execute on function public.criar_meu_pedido(date,jsonb) to authenticated;

-- Envio de chat autenticado e independente da função legada.
create or replace function public.enviar_minha_mensagem(p_pedido_id bigint,p_mensagem text)
returns bigint
language plpgsql
security definer
set search_path=''
as $$
declare v_d public.dispositivos_cliente%rowtype; v_texto text; v_id bigint;
begin
  select * into v_d from public.dispositivos_cliente where auth_uid=auth.uid() and ativo=true limit 1;
  if not found then raise exception 'Aparelho não autorizado.'; end if;
  v_texto:=trim(coalesce(p_mensagem,''));
  if v_texto='' then raise exception 'A mensagem está vazia.'; end if;
  if p_pedido_id is not null and not exists(select 1 from public.pedidos where id=p_pedido_id and cliente_id=v_d.cliente_id) then
    raise exception 'Pedido inválido.';
  end if;
  insert into public.mensagens(cliente_id,pedido_id,remetente,mensagem)
  values(v_d.cliente_id,p_pedido_id,'cliente',v_texto)
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.enviar_minha_mensagem(bigint,text) from public,anon;
grant execute on function public.enviar_minha_mensagem(bigint,text) to authenticated;

-- Histórico de mensagens do próprio cliente.
create or replace function public.listar_minhas_mensagens(p_pedido_id bigint default null)
returns jsonb language sql security definer set search_path='' stable as $$
with d as (
  select cliente_id from public.dispositivos_cliente where auth_uid=auth.uid() and ativo=true limit 1
), m as (
  select msg.id,msg.cliente_id,msg.pedido_id,msg.remetente,msg.mensagem,msg.criado_em
  from public.mensagens msg join d on d.cliente_id=msg.cliente_id
  where p_pedido_id is null or msg.pedido_id=p_pedido_id or msg.pedido_id is null
  order by msg.criado_em asc
)
select coalesce(jsonb_agg(to_jsonb(m)),'[]'::jsonb) from m;
$$;
revoke all on function public.listar_minhas_mensagens(bigint) from public,anon;
grant execute on function public.listar_minhas_mensagens(bigint) to authenticated;

commit;
