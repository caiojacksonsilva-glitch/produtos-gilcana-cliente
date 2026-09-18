-- PRODUTOS GILÇANA — V3.1
-- Atualização para um banco que já possui a V2 funcionando.
-- NÃO recria clientes, login ou ativar_aparelho.

begin;

-- Verificação de segurança: interrompe sem alterar nada se a base V2 não estiver neste projeto.
do $$
begin
  if to_regclass('public.clientes') is null then
    raise exception 'BASE_V2_AUSENTE: a tabela public.clientes não existe neste projeto Supabase.';
  end if;
  if to_regclass('public.pessoas_autorizadas') is null then
    raise exception 'BASE_V2_AUSENTE: a tabela public.pessoas_autorizadas não existe neste projeto Supabase.';
  end if;
  if to_regclass('public.dispositivos_cliente') is null then
    raise exception 'BASE_V2_AUSENTE: a tabela public.dispositivos_cliente não existe. Execute primeiro a ativação V2.';
  end if;
  if to_regclass('public.pedidos') is null or to_regclass('public.itens_pedido') is null then
    raise exception 'BASE_V2_AUSENTE: as tabelas de pedidos não existem neste projeto.';
  end if;
end $$;

-- Datas válidas calculadas no servidor, inclusive corte e alteração excepcional.
create or replace function public.minhas_datas_entrega()
returns table(data_entrega date) language plpgsql security definer set search_path='' stable as $$
declare d date; r record; ex record; corte time; local_now timestamp := timezone('America/Sao_Paulo',now()); candidate date;
begin
 if not exists(select 1 from public.dispositivos_cliente where auth_uid=auth.uid() and ativo=true) then raise exception 'Aparelho não autorizado.'; end if;
 for d in select generate_series(local_now::date+1,local_now::date+35,'1 day'::interval)::date loop
  select * into r from public.dias_entrega where dia_semana=extract(dow from d)::int and ativo=true limit 1;
  if not found then continue; end if;
  select * into ex from public.excecoes_entrega where data_original=d limit 1;
  if found and ex.cancelada then continue; end if;
  candidate:=case when found and ex.nova_data is not null then ex.nova_data else d end;
  select ec.horario_corte into corte from public.excecoes_corte ec where ec.data_entrega=candidate limit 1;
  corte:=coalesce(corte,r.horario_corte,'10:00'::time);
  if local_now > ((candidate-coalesce(r.dias_antes_preparacao,1))::timestamp+corte) then continue; end if;
  data_entrega:=candidate; return next;
 end loop;
end;$$;
revoke all on function public.minhas_datas_entrega() from public,anon;
grant execute on function public.minhas_datas_entrega() to authenticated;

-- Pedido: valida a data novamente no servidor antes de reservar estoque.
create or replace function public.criar_meu_pedido(p_data_entrega date,p_itens jsonb)
returns bigint language plpgsql security definer set search_path='' as $$
declare v_d public.dispositivos_cliente%rowtype; v_id bigint;
begin
 select * into v_d from public.dispositivos_cliente where auth_uid=auth.uid() and ativo=true limit 1;
 if not found then raise exception 'Aparelho não autorizado.'; end if;
 if p_data_entrega is null or not exists(select 1 from public.minhas_datas_entrega() x where x.data_entrega=p_data_entrega) then raise exception 'Essa data de entrega não está mais disponível.'; end if;
 if p_itens is null or jsonb_typeof(p_itens)<>'array' or jsonb_array_length(p_itens)=0 then raise exception 'O pedido está vazio.'; end if;
 v_id:=public.criar_pedido(v_d.cliente_id,v_d.pessoa_autorizada_id,p_data_entrega,p_itens);
 return v_id;
end;$$;
revoke all on function public.criar_meu_pedido(date,jsonb) from public,anon;
grant execute on function public.criar_meu_pedido(date,jsonb) to authenticated;

-- Preferência de notificações do cliente.
create or replace function public.definir_minhas_notificacoes(p_ativas boolean)
returns void language plpgsql security definer set search_path='' as $$
declare cid bigint;
begin
 select cliente_id into cid from public.dispositivos_cliente where auth_uid=auth.uid() and ativo=true limit 1;
 if cid is null then raise exception 'Aparelho não autorizado.'; end if;
 update public.clientes set notificacoes_ativas=coalesce(p_ativas,true) where id=cid;
end;$$;
revoke all on function public.definir_minhas_notificacoes(boolean) from public,anon;
grant execute on function public.definir_minhas_notificacoes(boolean) to authenticated;

-- Uma única pessoa autorizada por cliente.
create or replace function public.minha_pessoa_autorizada()
returns jsonb language sql security definer set search_path='' stable as $$
 select coalesce((select jsonb_build_object('id',pa.id,'nome',pa.nome,'telefone',pa.telefone) from public.dispositivos_cliente d join public.pessoas_autorizadas pa on pa.cliente_id=d.cliente_id where d.auth_uid=auth.uid() and d.ativo=true and d.pessoa_autorizada_id is null and pa.ativo=true order by pa.id desc limit 1),'null'::jsonb);
$$;
revoke all on function public.minha_pessoa_autorizada() from public,anon;
grant execute on function public.minha_pessoa_autorizada() to authenticated;

create or replace function public.salvar_minha_pessoa_autorizada(p_nome text,p_telefone text,p_codigo text)
returns void language plpgsql security definer set search_path='' as $$
declare cid bigint;
begin
 select cliente_id into cid from public.dispositivos_cliente where auth_uid=auth.uid() and ativo=true and pessoa_autorizada_id is null limit 1;
 if cid is null then raise exception 'Somente o cliente principal pode autorizar outra pessoa.'; end if;
 if nullif(trim(p_nome),'') is null or length(regexp_replace(p_telefone,'\\D','','g'))<10 or length(trim(p_codigo))<4 then raise exception 'Dados da pessoa autorizada inválidos.'; end if;
 if exists(select 1 from public.pessoas_autorizadas where cliente_id=cid and ativo=true) then raise exception 'Remova a pessoa autorizada atual antes de cadastrar outra.'; end if;
 if exists(select 1 from public.clientes where telefone=regexp_replace(p_telefone,'\\D','','g') and ativo=true) then raise exception 'Esse WhatsApp já pertence a um cliente.'; end if;
 insert into public.pessoas_autorizadas(cliente_id,nome,telefone,ativo,codigo_acesso_hash) values(cid,trim(p_nome),regexp_replace(p_telefone,'\\D','','g'),true,extensions.crypt(trim(p_codigo),extensions.gen_salt('bf')));
end;$$;
revoke all on function public.salvar_minha_pessoa_autorizada(text,text,text) from public,anon;
grant execute on function public.salvar_minha_pessoa_autorizada(text,text,text) to authenticated;

create or replace function public.remover_minha_pessoa_autorizada()
returns void language plpgsql security definer set search_path='' as $$
declare cid bigint; aid bigint;
begin
 select cliente_id into cid from public.dispositivos_cliente where auth_uid=auth.uid() and ativo=true and pessoa_autorizada_id is null limit 1;
 if cid is null then raise exception 'Somente o cliente principal pode remover a pessoa autorizada.'; end if;
 select id into aid from public.pessoas_autorizadas where cliente_id=cid and ativo=true order by id desc limit 1;
 if aid is null then return; end if;
 update public.pessoas_autorizadas set ativo=false where id=aid;
 update public.dispositivos_cliente set ativo=false where pessoa_autorizada_id=aid;
end;$$;
revoke all on function public.remover_minha_pessoa_autorizada() from public,anon;
grant execute on function public.remover_minha_pessoa_autorizada() to authenticated;

-- Leitura privada necessária para pedidos/chat/notificações.
drop policy if exists cliente_le_proprios_pedidos on public.pedidos;
create policy cliente_le_proprios_pedidos on public.pedidos for select to authenticated using(exists(select 1 from public.dispositivos_cliente d where d.auth_uid=auth.uid() and d.cliente_id=pedidos.cliente_id and d.ativo=true));
drop policy if exists cliente_le_itens_proprios on public.itens_pedido;
create policy cliente_le_itens_proprios on public.itens_pedido for select to authenticated using(exists(select 1 from public.pedidos p join public.dispositivos_cliente d on d.cliente_id=p.cliente_id where p.id=itens_pedido.pedido_id and d.auth_uid=auth.uid() and d.ativo=true));
drop policy if exists cliente_le_mensagens on public.mensagens;
create policy cliente_le_mensagens on public.mensagens for select to authenticated using(exists(select 1 from public.dispositivos_cliente d where d.auth_uid=auth.uid() and d.cliente_id=mensagens.cliente_id and d.ativo=true));
drop policy if exists cliente_le_notificacoes on public.notificacoes;
create policy cliente_le_notificacoes on public.notificacoes for select to authenticated using(exists(select 1 from public.dispositivos_cliente d where d.auth_uid=auth.uid() and d.cliente_id=notificacoes.cliente_id and d.ativo=true));
grant select on public.pedidos,public.itens_pedido,public.mensagens,public.notificacoes to authenticated;

commit;

-- V3.2 PATCH: chat + calendário padrão + fila de confirmação
-- Este bloco é idempotente e pode ser executado novamente.

-- Chat seguro do cliente.
create or replace function public.enviar_minha_mensagem(p_pedido_id bigint,p_mensagem text)
returns bigint language plpgsql security definer set search_path='' as $$
declare v_d public.dispositivos_cliente%rowtype; v_texto text;
begin
  select * into v_d from public.dispositivos_cliente where auth_uid=auth.uid() and ativo=true limit 1;
  if not found then raise exception 'Aparelho não autorizado.'; end if;
  v_texto:=trim(coalesce(p_mensagem,''));
  if v_texto='' then raise exception 'A mensagem está vazia.'; end if;
  if p_pedido_id is not null and not exists(select 1 from public.pedidos where id=p_pedido_id and cliente_id=v_d.cliente_id) then raise exception 'Pedido inválido.'; end if;
  return public.enviar_mensagem(v_d.cliente_id,p_pedido_id,'cliente',v_texto);
end; $$;
revoke all on function public.enviar_minha_mensagem(bigint,text) from public,anon;
grant execute on function public.enviar_minha_mensagem(bigint,text) to authenticated;

-- Calendário padrão: somente segunda(1), quarta(3) e sexta(5).
-- Datas alternativas devem entrar por excecoes_entrega no painel do gerente.
update public.dias_entrega set ativo=false where dia_semana not in (1,3,5);
insert into public.dias_entrega(dia_semana,ativo,horario_corte,dias_antes_preparacao)
values (1,true,'10:00',1),(3,true,'10:00',1),(5,true,'10:00',1)
on conflict (dia_semana) do update set ativo=true;

-- Garante que um pedido recém-criado esteja na fila de confirmação.
-- 'enviado' e 'recebido' são ambos pendentes até a confirmação do gerente.
create or replace view public.pedidos_aguardando_confirmacao as
select p.* from public.pedidos p where p.status in ('enviado','recebido');
revoke all on public.pedidos_aguardando_confirmacao from public,anon,authenticated;

-- Datas válidas: M/Q/S padrão; uma exceção pode mover a entrega para qualquer outra data.
create or replace function public.minhas_datas_entrega()
returns table(data_entrega date) language plpgsql security definer set search_path='' stable as $$
declare d date; r record; ex record; corte time; local_now timestamp := timezone('America/Sao_Paulo',now()); candidate date;
begin
 if not exists(select 1 from public.dispositivos_cliente where auth_uid=auth.uid() and ativo=true) then raise exception 'Aparelho não autorizado.'; end if;
 for d in select generate_series(local_now::date+1,local_now::date+35,'1 day'::interval)::date loop
  select * into r from public.dias_entrega where dia_semana=extract(dow from d)::int and dia_semana in (1,3,5) and ativo=true limit 1;
  if not found then continue; end if;
  select * into ex from public.excecoes_entrega where data_original=d limit 1;
  if found and ex.cancelada then continue; end if;
  candidate:=case when found and ex.nova_data is not null then ex.nova_data else d end;
  select ec.horario_corte into corte from public.excecoes_corte ec where ec.data_entrega=candidate limit 1;
  corte:=coalesce(corte,r.horario_corte,'10:00'::time);
  if local_now > ((candidate-coalesce(r.dias_antes_preparacao,1))::timestamp+corte) then continue; end if;
  data_entrega:=candidate; return next;
 end loop;
end;$$;
revoke all on function public.minhas_datas_entrega() from public,anon;
grant execute on function public.minhas_datas_entrega() to authenticated;
