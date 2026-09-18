-- Produtos Gilçana Cliente V3.5 — correção da leitura do chat
begin;

create or replace function public.listar_minhas_mensagens(p_pedido_id bigint default null)
returns jsonb
language sql
security definer
set search_path=''
stable
as $$
with d as (
  select cliente_id
  from public.dispositivos_cliente
  where auth_uid=auth.uid() and ativo=true
  limit 1
), m as (
  select msg.id,msg.cliente_id,msg.pedido_id,msg.remetente,msg.mensagem,msg.criado_em
  from public.mensagens msg
  join d on d.cliente_id=msg.cliente_id
  where p_pedido_id is null
     or msg.pedido_id=p_pedido_id
     or msg.pedido_id is null
  order by msg.criado_em asc
)
select coalesce(jsonb_agg(to_jsonb(m)),'[]'::jsonb) from m;
$$;

revoke all on function public.listar_minhas_mensagens(bigint) from public,anon;
grant execute on function public.listar_minhas_mensagens(bigint) to authenticated;

commit;
