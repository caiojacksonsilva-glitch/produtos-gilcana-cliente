-- Produtos Gilçana Cliente V3.8 — recibo/leitura do chat e contador de não lidas
begin;

alter table public.mensagens add column if not exists lida_cliente boolean not null default false;
alter table public.mensagens add column if not exists lida_gerente boolean not null default false;

-- Mensagens antigas não devem aparecer como novas ao instalar a atualização.
update public.mensagens set lida_cliente=true where remetente in ('gerente','sistema') and lida_cliente=false;
update public.mensagens set lida_gerente=true where remetente='cliente' and lida_gerente=false;

create or replace function public.enviar_minha_mensagem_v3(p_pedido_id bigint,p_mensagem text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_d public.dispositivos_cliente%rowtype; v_texto text; v_m public.mensagens%rowtype;
begin
 select * into v_d from public.dispositivos_cliente where auth_uid=auth.uid() and ativo=true limit 1;
 if not found then raise exception 'Aparelho não autorizado.'; end if;
 v_texto:=trim(coalesce(p_mensagem,'')); if v_texto='' then raise exception 'A mensagem está vazia.'; end if;
 if p_pedido_id is not null and not exists(select 1 from public.pedidos where id=p_pedido_id and cliente_id=v_d.cliente_id) then raise exception 'Pedido inválido.'; end if;
 insert into public.mensagens(cliente_id,pedido_id,remetente,mensagem,lida_cliente,lida_gerente)
 values(v_d.cliente_id,p_pedido_id,'cliente',v_texto,true,false) returning * into v_m;
 return to_jsonb(v_m);
end;$$;
revoke all on function public.enviar_minha_mensagem_v3(bigint,text) from public,anon;
grant execute on function public.enviar_minha_mensagem_v3(bigint,text) to authenticated;

create or replace function public.listar_minhas_mensagens_v3(p_pedido_id bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_cliente bigint; j jsonb;
begin
 select cliente_id into v_cliente from public.dispositivos_cliente where auth_uid=auth.uid() and ativo=true limit 1;
 if v_cliente is null then raise exception 'Aparelho não autorizado.'; end if;
 update public.mensagens set lida_cliente=true where cliente_id=v_cliente and remetente in ('gerente','sistema') and lida_cliente=false;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'pedido_id',pedido_id,'remetente',remetente,'mensagem',mensagem,'criado_em',criado_em,'lida_gerente',lida_gerente) order by criado_em,id),'[]'::jsonb)
 into j from public.mensagens where cliente_id=v_cliente and (p_pedido_id is null or pedido_id=p_pedido_id or pedido_id is null);
 return j;
end;$$;
revoke all on function public.listar_minhas_mensagens_v3(bigint) from public,anon;
grant execute on function public.listar_minhas_mensagens_v3(bigint) to authenticated;

create or replace function public.contar_minhas_mensagens_nao_lidas()
returns bigint language plpgsql security definer set search_path='' stable as $$
declare v_cliente bigint; n bigint;
begin
 select cliente_id into v_cliente from public.dispositivos_cliente where auth_uid=auth.uid() and ativo=true limit 1;
 if v_cliente is null then return 0; end if;
 select count(*) into n from public.mensagens where cliente_id=v_cliente and remetente in ('gerente','sistema') and lida_cliente=false;
 return n;
end;$$;
revoke all on function public.contar_minhas_mensagens_nao_lidas() from public,anon;
grant execute on function public.contar_minhas_mensagens_nao_lidas() to authenticated;

-- Quando o gerente abre a conversa, as mensagens enviadas pelo cliente passam a constar como lidas.
create or replace function public.gerente_mensagens(p_cliente_id bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare j jsonb;
begin
 if not public.sou_gerente() then raise exception 'Não autorizado.'; end if;
 update public.mensagens set lida_gerente=true where cliente_id=p_cliente_id and remetente='cliente' and lida_gerente=false;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'pedido_id',pedido_id,'remetente',remetente,'mensagem',mensagem,'criado_em',criado_em,'lida_cliente',lida_cliente) order by criado_em,id),'[]'::jsonb)
 into j from public.mensagens where cliente_id=p_cliente_id;
 return j;
end;$$;
revoke all on function public.gerente_mensagens(bigint) from public,anon;
grant execute on function public.gerente_mensagens(bigint) to authenticated;

commit;
