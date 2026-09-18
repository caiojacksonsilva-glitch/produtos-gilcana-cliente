-- Produtos Gilçana Cliente V3.7 — chat v2 com retorno da mensagem
begin;
create or replace function public.enviar_minha_mensagem_v2(p_pedido_id bigint,p_mensagem text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_d public.dispositivos_cliente%rowtype; v_texto text; v_m public.mensagens%rowtype;
begin
 select * into v_d from public.dispositivos_cliente where auth_uid=auth.uid() and ativo=true limit 1;
 if not found then raise exception 'Aparelho não autorizado.'; end if;
 v_texto:=trim(coalesce(p_mensagem,'')); if v_texto='' then raise exception 'A mensagem está vazia.'; end if;
 if p_pedido_id is not null and not exists(select 1 from public.pedidos where id=p_pedido_id and cliente_id=v_d.cliente_id) then raise exception 'Pedido inválido.'; end if;
 insert into public.mensagens(cliente_id,pedido_id,remetente,mensagem) values(v_d.cliente_id,p_pedido_id,'cliente',v_texto) returning * into v_m;
 return to_jsonb(v_m);
end;$$;
revoke all on function public.enviar_minha_mensagem_v2(bigint,text) from public,anon;
grant execute on function public.enviar_minha_mensagem_v2(bigint,text) to authenticated;

create or replace function public.listar_minhas_mensagens_v2(p_pedido_id bigint default null)
returns jsonb language sql security definer set search_path='' stable as $$
with d as (select cliente_id from public.dispositivos_cliente where auth_uid=auth.uid() and ativo=true limit 1),
m as (select msg.id,msg.pedido_id,msg.remetente,msg.mensagem,msg.criado_em from public.mensagens msg join d on d.cliente_id=msg.cliente_id where p_pedido_id is null or msg.pedido_id=p_pedido_id or msg.pedido_id is null order by msg.criado_em asc,msg.id asc)
select coalesce(jsonb_agg(to_jsonb(m)),'[]'::jsonb) from m;$$;
revoke all on function public.listar_minhas_mensagens_v2(bigint) from public,anon;
grant execute on function public.listar_minhas_mensagens_v2(bigint) to authenticated;
commit;
