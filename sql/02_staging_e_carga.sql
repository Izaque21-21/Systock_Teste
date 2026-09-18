/* =============================================================================
   Systock - Case Tecnico de Integracao de Dados
   Arquivo 02 - STAGING E CARGA

   Estrategia: carga em duas fases.

       CSV  ->  stg.* (tudo TEXT, copia fiel)  ->  public.* (tipado e tratado)

   Por que staging em TEXT:
     1. A carga nunca quebra na primeira linha suja. Se o destino ja fosse
        tipado, um unico 'F8' em coluna integer abortaria o arquivo inteiro e
        nao daria para saber quantos outros problemas existem.
     2. Fica um retrato do dado original DENTRO do banco. Na reuniao de
        validacao, qualquer numero questionado pelo cliente pode ser
        confrontado contra a origem sem reabrir a planilha.
     3. Cada transformacao vira um INSERT...SELECT legivel e auditavel,
        em vez de codigo Python que o cliente nao le.

   Execucao (a partir da raiz do repositorio):
       psql -U postgres -d systock -f sql/02_staging_e_carga.sql

   Pre-requisito: python etl/importar_planilha.py (gera os CSV em data/csv/).

   Alternativa sem psql: no DBeaver, criar as tabelas stg.* rodando apenas a
   Secao 1 deste arquivo e importar cada CSV pelo assistente
   (botao direito na tabela > Import Data), depois rodar a Secao 3 em diante.
   ============================================================================= */


-- =============================================================================
-- SECAO 1 - TABELAS DE STAGING (tudo TEXT, sem constraint)
-- =============================================================================
DROP TABLE IF EXISTS stg.venda, stg.pedido_compra, stg.entradas_mercadoria,
                     stg.produtos_filial, stg.fornecedor;

CREATE TABLE stg.venda (
    venda_id text, data_emissao text, horariomov text, produto_id text,
    qtde_vendida text, valor_unitario text, filial_id text, item text,
    unidade_medida text
);

CREATE TABLE stg.pedido_compra (
    pedido_id text, data_pedido text, item text, produto_id text,
    descricao_produto text, ordem_compra text, qtde_pedida text, filial_id text,
    data_entrega text, qtde_entregue text, preco_compra text, fornecedor_id text
    -- Sem qtde_pendente: a coluna existe no DDL do enunciado mas nao na planilha.
);

CREATE TABLE stg.entradas_mercadoria (
    data_entrada text, nro_nfe text, item text, produto_id text,
    descricao_produto text, ordem_compra text, qtde_recebida text,
    filial_id text, custo_unitario text
);

CREATE TABLE stg.produtos_filial (
    filial_id text, idproduto text, descricao text, estoque text,
    preco_unitario text, preco_compra text, preco_venda text, idfornecedor text
);

CREATE TABLE stg.fornecedor (
    idfornecedor text, razao_social text
);


-- =============================================================================
-- SECAO 2 - CARGA DOS CSV
-- \copy roda no cliente (psql), entao os caminhos sao relativos a raiz do repo.
-- =============================================================================
\copy stg.venda               FROM 'data/csv/venda.csv'               WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy stg.pedido_compra       FROM 'data/csv/pedido_compra.csv'       WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy stg.entradas_mercadoria FROM 'data/csv/entradas_mercadoria.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy stg.produtos_filial     FROM 'data/csv/produtos_filial.csv'     WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy stg.fornecedor          FROM 'data/csv/fornecedor.csv'          WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')


-- =============================================================================
-- SECAO 3 - CARGA TRATADA PARA AS TABELAS FINAIS
-- Ordem obrigatoria por dependencia de FK.
-- =============================================================================

TRUNCATE public.venda, public.entradas_mercadoria, public.pedido_compra,
         public.produtos_filial, public.fornecedor RESTART IDENTITY CASCADE;


-- 3.1 FORNECEDOR ---------------------------------------------------------------
-- Transformacao central do projeto: a chave natural e textual ('F1'..'F20'),
-- mas pedido_compra.fornecedor_id e numerico (1..20). A chave substituta
-- fornecedor_num e derivada da parte numerica do codigo, o que reconstroi o
-- relacionamento que o DDL original tornava impossivel.
INSERT INTO public.fornecedor (idfornecedor, fornecedor_num, razao_social)
SELECT
    trim(idfornecedor),
    NULLIF(regexp_replace(idfornecedor, '\D', '', 'g'), '')::int,
    trim(razao_social)
FROM stg.fornecedor
WHERE NULLIF(trim(idfornecedor), '') IS NOT NULL;

-- Realinha a sequence da IDENTITY acima do maior valor inserido manualmente,
-- senao a trigger da Parte 3 geraria um numero ja em uso no primeiro disparo.
SELECT setval(
    pg_get_serial_sequence('public.fornecedor', 'fornecedor_num'),
    COALESCE((SELECT MAX(fornecedor_num) FROM public.fornecedor), 0) + 1,
    false
);


-- 3.2 PRODUTOS_FILIAL ----------------------------------------------------------
INSERT INTO public.produtos_filial (
    filial_id, idproduto, descricao, estoque,
    preco_unitario, preco_compra, preco_venda, idfornecedor
)
SELECT
    filial_id::int,
    trim(idproduto),
    trim(descricao),
    estoque::numeric,
    preco_unitario::numeric,
    preco_compra::numeric,
    preco_venda::numeric,
    NULLIF(trim(idfornecedor), '')
FROM stg.produtos_filial
WHERE NULLIF(trim(idproduto), '') IS NOT NULL;


-- 3.3 PEDIDO_COMPRA ------------------------------------------------------------
-- Duas decisoes de tratamento aqui:
--
-- (a) qtde_pendente nao existe na planilha. Derivada como
--     GREATEST(qtde_pedida - qtde_entregue, 0). O GREATEST evita pendencia
--     negativa quando o recebido supera o pedido - situacao que ocorre em
--     6 ordens da base e que esta no roteiro de validacao.
--
-- (b) Os 9 registros duplicados (pedidos 21..29) sao carregados, NAO
--     descartados. Excluir dado do cliente sem autorizacao e o erro mais caro
--     que se comete em implantacao. Eles ficam visiveis em
--     qa.vw_pedido_duplicado e a exclusao so ocorre apos o de acordo formal.
INSERT INTO public.pedido_compra (
    pedido_id, item, ordem_compra, data_pedido, produto_id, descricao_produto,
    qtde_pedida, filial_id, data_entrega, qtde_entregue, qtde_pendente,
    preco_compra, fornecedor_id
)
SELECT
    pedido_id::numeric::bigint,
    item::numeric::int,
    COALESCE(ordem_compra::numeric::bigint, 0),
    NULLIF(trim(data_pedido), '')::date,
    trim(produto_id),
    NULLIF(trim(descricao_produto), ''),
    qtde_pedida::numeric,
    filial_id::int,
    NULLIF(trim(data_entrega), '')::date,
    COALESCE(qtde_entregue::numeric, 0),
    GREATEST(COALESCE(qtde_pedida::numeric, 0) - COALESCE(qtde_entregue::numeric, 0), 0),
    preco_compra::numeric,
    fornecedor_id::numeric::int
FROM stg.pedido_compra
WHERE NULLIF(trim(pedido_id), '') IS NOT NULL;


-- 3.4 ENTRADAS_MERCADORIA ------------------------------------------------------
INSERT INTO public.entradas_mercadoria (
    ordem_compra, nro_nfe, item, produto_id, descricao_produto,
    data_entrada, qtde_recebida, filial_id, custo_unitario
)
SELECT
    ordem_compra::numeric::bigint,
    trim(nro_nfe),
    item::numeric::int,
    trim(produto_id),
    NULLIF(trim(descricao_produto), ''),
    NULLIF(trim(data_entrada), '')::date,
    qtde_recebida::numeric,
    filial_id::int,
    custo_unitario::numeric
FROM stg.entradas_mercadoria
WHERE NULLIF(trim(nro_nfe), '') IS NOT NULL;


-- 3.5 VENDA --------------------------------------------------------------------
-- horariomov vem como texto 'HH:MM:SS' e e convertido para TIME.
-- As quantidades fracionarias em unidade 'UN' (5 registros) sao carregadas
-- como estao: arredondar aqui alteraria o faturamento do cliente por conta
-- propria. Ficam sinalizadas em qa.vw_venda_qtde_fracionaria.
INSERT INTO public.venda (
    venda_id, data_emissao, horariomov, produto_id, qtde_vendida,
    valor_unitario, filial_id, item, unidade_medida
)
SELECT
    venda_id::numeric::bigint,
    data_emissao::date,
    COALESCE(NULLIF(trim(horariomov), '')::time, '00:00:00'::time),
    trim(produto_id),
    qtde_vendida::numeric,
    valor_unitario::numeric,
    filial_id::numeric::int,
    item::numeric::int,
    NULLIF(trim(unidade_medida), '')
FROM stg.venda
WHERE NULLIF(trim(venda_id), '') IS NOT NULL;


-- =============================================================================
-- SECAO 4 - FK DE INTEGRIDADE PROSPECTIVA
--
-- Criada apenas agora, depois da carga. Motivo: NOT VALID dispensa a
-- verificacao das linhas ja existentes, mas continua validando todo INSERT
-- novo. Se a constraint existisse antes, a carga das 13 vendas orfas
-- (P21..P28) falharia.
--
-- Efeito pratico: o passivo historico fica registrado e mensuravel, e nenhuma
-- venda orfa NOVA consegue entrar. Depois que o cliente aprovar o saneamento,
-- basta rodar:
--     ALTER TABLE public.venda VALIDATE CONSTRAINT venda_produto_fk;
-- =============================================================================
ALTER TABLE public.venda DROP CONSTRAINT IF EXISTS venda_produto_fk;

ALTER TABLE public.venda
    ADD CONSTRAINT venda_produto_fk
    FOREIGN KEY (filial_id, produto_id)
    REFERENCES public.produtos_filial (filial_id, idproduto)
    NOT VALID;

COMMENT ON CONSTRAINT venda_produto_fk ON public.venda IS
    'NOT VALID: o historico tem 13 vendas orfas (P21..P28) e 4 em filiais sem cadastro. Rodar VALIDATE CONSTRAINT apos o saneamento aprovado pelo cliente.';


-- =============================================================================
-- SECAO 5 - CONFERENCIA DE CARGA
-- Toda carga precisa terminar com contagem origem x destino. Sem isso nao ha
-- como afirmar ao cliente que nada se perdeu no caminho.
-- =============================================================================
SELECT 'fornecedor'          AS tabela,
       (SELECT count(*) FROM stg.fornecedor)          AS staging,
       (SELECT count(*) FROM public.fornecedor)       AS final
UNION ALL SELECT 'produtos_filial',
       (SELECT count(*) FROM stg.produtos_filial),
       (SELECT count(*) FROM public.produtos_filial)
UNION ALL SELECT 'pedido_compra',
       (SELECT count(*) FROM stg.pedido_compra),
       (SELECT count(*) FROM public.pedido_compra)
UNION ALL SELECT 'entradas_mercadoria',
       (SELECT count(*) FROM stg.entradas_mercadoria),
       (SELECT count(*) FROM public.entradas_mercadoria)
UNION ALL SELECT 'venda',
       (SELECT count(*) FROM stg.venda),
       (SELECT count(*) FROM public.venda);
