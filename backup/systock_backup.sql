--
-- PostgreSQL database dump
--

\restrict pn4Vec2LRXslUpYg3z0puCnRzTGxkeEDEI4nyvCvMrANe5E5sWFLm7FZIAhocp7

-- Dumped from database version 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)
-- Dumped by pg_dump version 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: qa; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA qa;


--
-- Name: stg; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA stg;


--
-- Name: fn_produtos_filial_vincula_fornecedor(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_produtos_filial_vincula_fornecedor() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_num           int;
    v_codigo_texto  text;
    v_texto_mudou   boolean := false;
    v_num_mudou     boolean := false;
BEGIN
    -- Passo 0: em UPDATE, descobrir QUAL dos dois campos o usuario alterou.
    --
    -- Sem este passo a trigger tem um furo silencioso: em um UPDATE que troca
    -- apenas o codigo textual, NEW.idfornecedor_num ainda carrega o numero
    -- ANTIGO. O Passo 1 o encontraria valido, daria RETURN e o produto
    -- terminaria apontando para o fornecedor errado - texto novo, numero
    -- velho. Comparar NEW com OLD e o que define quem tem a palavra final.
    IF TG_OP = 'UPDATE' THEN
        v_texto_mudou := NEW.idfornecedor     IS DISTINCT FROM OLD.idfornecedor;
        v_num_mudou   := NEW.idfornecedor_num IS DISTINCT FROM OLD.idfornecedor_num;
    END IF;

    -- Regra de precedencia: o codigo textual e a chave que o usuario opera,
    -- entao ele vence. Zerar o numero aqui forca o recalculo mais abaixo.
    IF v_texto_mudou THEN
        NEW.idfornecedor_num := NULL;
    END IF;

    -- Passo 1: vinculo numerico informado e coerente -> respeita.
    -- Em UPDATE, so chega aqui se o texto NAO mudou (o bloco acima ja zerou).
    IF NEW.idfornecedor_num IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM public.fornecedor
                    WHERE fornecedor_num = NEW.idfornecedor_num) THEN

            -- Sincroniza o codigo textual quando o numero e a origem da
            -- alteracao, ou quando o texto esta faltando.
            IF NEW.idfornecedor IS NULL OR v_num_mudou THEN
                SELECT idfornecedor INTO NEW.idfornecedor
                FROM public.fornecedor
                WHERE fornecedor_num = NEW.idfornecedor_num;
            END IF;

            RETURN NEW;
        END IF;

        RAISE EXCEPTION
            'idfornecedor_num % nao existe em fornecedor (produto %, filial %)',
            NEW.idfornecedor_num, NEW.idproduto, NEW.filial_id;
    END IF;

    -- Passo 3: sem codigo textual -> nada a vincular.
    v_codigo_texto := NULLIF(trim(NEW.idfornecedor), '');
    IF v_codigo_texto IS NULL THEN
        NEW.idfornecedor     := NULL;
        NEW.idfornecedor_num := NULL;
        RETURN NEW;
    END IF;

    -- Passo 2.1: fornecedor ja cadastrado -> copia o numero.
    SELECT fornecedor_num INTO v_num
    FROM public.fornecedor
    WHERE idfornecedor = v_codigo_texto;

    -- Passo 2.2: nao cadastrado -> cadastra e gera um novo numero.
    -- ON CONFLICT cobre a corrida entre transacoes concorrentes inserindo o
    -- mesmo fornecedor: uma insere, a outra cai no conflito e le o valor.
    IF v_num IS NULL THEN
        INSERT INTO public.fornecedor (idfornecedor, razao_social)
        VALUES (v_codigo_texto,
                'FORNECEDOR PENDENTE DE CADASTRO - ' || v_codigo_texto)
        ON CONFLICT (idfornecedor) DO NOTHING
        RETURNING fornecedor_num INTO v_num;

        IF v_num IS NULL THEN
            SELECT fornecedor_num INTO v_num
            FROM public.fornecedor
            WHERE idfornecedor = v_codigo_texto;
        END IF;

        RAISE NOTICE
            'Fornecedor % nao existia e foi criado automaticamente com idfornecedor_num = %. Revisar a razao social.',
            v_codigo_texto, v_num;
    END IF;

    NEW.idfornecedor     := v_codigo_texto;
    NEW.idfornecedor_num := v_num;

    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION fn_produtos_filial_vincula_fornecedor(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_produtos_filial_vincula_fornecedor() IS 'Preenche produtos_filial.idfornecedor_num a partir do codigo textual do fornecedor, cadastrando o fornecedor automaticamente quando ele ainda nao existe.';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: entradas_mercadoria; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entradas_mercadoria (
    ordem_compra bigint NOT NULL,
    nro_nfe character varying(255) NOT NULL,
    item integer DEFAULT 1 NOT NULL,
    produto_id character varying(25) NOT NULL,
    descricao_produto character varying(255),
    data_entrada date,
    qtde_recebida numeric(14,3),
    filial_id integer,
    custo_unitario numeric(12,4) DEFAULT 0 NOT NULL,
    CONSTRAINT entradas_custo_ck CHECK ((custo_unitario >= (0)::numeric)),
    CONSTRAINT entradas_qtde_ck CHECK (((qtde_recebida IS NULL) OR (qtde_recebida >= (0)::numeric)))
);


--
-- Name: TABLE entradas_mercadoria; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.entradas_mercadoria IS 'Entradas de NF. Liga-se a pedido_compra por ordem_compra. FK nao declarada: ordem_compra nao e chave candidata em pedido_compra.';


--
-- Name: fornecedor; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fornecedor (
    idfornecedor character varying(25) NOT NULL,
    fornecedor_num integer NOT NULL,
    razao_social character varying(255) NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT fornecedor_razao_ck CHECK ((length(TRIM(BOTH FROM razao_social)) > 0))
);


--
-- Name: TABLE fornecedor; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.fornecedor IS 'Cadastro de fornecedores. Chave natural textual (idfornecedor) + chave substituta numerica (fornecedor_num) para relacionamento com pedido_compra.';


--
-- Name: COLUMN fornecedor.fornecedor_num; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.fornecedor.fornecedor_num IS 'Chave numerica. Criada para viabilizar o relacionamento com pedido_compra.fornecedor_id (int) e alimentada pela trigger da Parte 3.';


--
-- Name: fornecedor_fornecedor_num_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.fornecedor ALTER COLUMN fornecedor_num ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.fornecedor_fornecedor_num_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: pedido_compra; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pedido_compra (
    pedido_id bigint NOT NULL,
    item integer DEFAULT 1 NOT NULL,
    ordem_compra bigint DEFAULT 0 NOT NULL,
    data_pedido date,
    produto_id character varying(25) NOT NULL,
    descricao_produto character varying(255),
    qtde_pedida numeric(14,3),
    filial_id integer,
    data_entrega date,
    qtde_entregue numeric(14,3) DEFAULT 0 NOT NULL,
    qtde_pendente numeric(14,3) DEFAULT 0 NOT NULL,
    preco_compra numeric(12,4) DEFAULT 0,
    fornecedor_id integer,
    CONSTRAINT pedido_compra_entreg_ck CHECK ((qtde_entregue >= (0)::numeric)),
    CONSTRAINT pedido_compra_preco_ck CHECK (((preco_compra IS NULL) OR (preco_compra >= (0)::numeric))),
    CONSTRAINT pedido_compra_qtde_ck CHECK (((qtde_pedida IS NULL) OR (qtde_pedida >= (0)::numeric)))
);


--
-- Name: COLUMN pedido_compra.ordem_compra; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.pedido_compra.ordem_compra IS 'Chave de ligacao com entradas_mercadoria. ATENCAO: 11 registros da base chegam com valor 0 (orfaos) - ver qa.vw_pedido_sem_ordem_compra.';


--
-- Name: COLUMN pedido_compra.qtde_pendente; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.pedido_compra.qtde_pendente IS 'Coluna ausente na planilha de origem. Derivada na carga: GREATEST(qtde_pedida - qtde_entregue, 0).';


--
-- Name: produtos_filial; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.produtos_filial (
    filial_id integer NOT NULL,
    idproduto character varying(25) NOT NULL,
    descricao character varying(255) NOT NULL,
    estoque numeric(14,3) DEFAULT 0 NOT NULL,
    preco_unitario numeric(12,4) DEFAULT 0 NOT NULL,
    preco_compra numeric(12,4) DEFAULT 0 NOT NULL,
    preco_venda numeric(12,4) DEFAULT 0 NOT NULL,
    idfornecedor character varying(25),
    idfornecedor_num integer,
    CONSTRAINT produtos_filial_estoque_ck CHECK ((estoque >= (0)::numeric)),
    CONSTRAINT produtos_filial_pcompra_ck CHECK ((preco_compra >= (0)::numeric)),
    CONSTRAINT produtos_filial_punit_ck CHECK ((preco_unitario >= (0)::numeric)),
    CONSTRAINT produtos_filial_pvenda_ck CHECK ((preco_venda >= (0)::numeric))
);


--
-- Name: TABLE produtos_filial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.produtos_filial IS 'Cadastro de produtos por filial. ATENCAO: possui tres colunas de preco (unitario, compra, venda) sem definicao de qual e a oficial - pendencia de validacao com o cliente.';


--
-- Name: venda; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.venda (
    venda_id bigint NOT NULL,
    data_emissao date NOT NULL,
    horariomov time without time zone DEFAULT '00:00:00'::time without time zone NOT NULL,
    produto_id character varying(25) NOT NULL,
    qtde_vendida numeric(14,3) NOT NULL,
    valor_unitario numeric(12,4) DEFAULT 0 NOT NULL,
    filial_id integer DEFAULT 1 NOT NULL,
    item integer DEFAULT 1 NOT NULL,
    unidade_medida character varying(3),
    CONSTRAINT venda_qtde_ck CHECK ((qtde_vendida >= (0)::numeric)),
    CONSTRAINT venda_valor_ck CHECK ((valor_unitario >= (0)::numeric))
);


--
-- Name: vw_divergencia_entregue_vs_nf; Type: VIEW; Schema: qa; Owner: -
--

CREATE VIEW qa.vw_divergencia_entregue_vs_nf AS
 SELECT pc.ordem_compra,
    pc.pedido_id,
    pc.produto_id,
    pc.qtde_pedida,
    pc.qtde_entregue AS qtde_entregue_pedido,
    sum(em.qtde_recebida) AS qtde_recebida_nf,
    (sum(em.qtde_recebida) - pc.qtde_entregue) AS divergencia
   FROM (public.pedido_compra pc
     JOIN public.entradas_mercadoria em ON ((em.ordem_compra = pc.ordem_compra)))
  WHERE (pc.ordem_compra <> 0)
  GROUP BY pc.ordem_compra, pc.pedido_id, pc.produto_id, pc.qtde_pedida, pc.qtde_entregue
 HAVING (sum(em.qtde_recebida) <> pc.qtde_entregue);


--
-- Name: vw_fornecedor_sem_produto; Type: VIEW; Schema: qa; Owner: -
--

CREATE VIEW qa.vw_fornecedor_sem_produto AS
 SELECT idfornecedor,
    fornecedor_num,
    razao_social
   FROM public.fornecedor f
  WHERE (NOT (EXISTS ( SELECT 1
           FROM public.produtos_filial pf
          WHERE ((pf.idfornecedor)::text = (f.idfornecedor)::text))));


--
-- Name: vw_pedido_data_invertida; Type: VIEW; Schema: qa; Owner: -
--

CREATE VIEW qa.vw_pedido_data_invertida AS
 SELECT pedido_id,
    produto_id,
    to_char((data_pedido)::timestamp with time zone, 'DD/MM/YYYY'::text) AS data_pedido,
    to_char((data_entrega)::timestamp with time zone, 'DD/MM/YYYY'::text) AS data_entrega,
    (data_entrega - data_pedido) AS dias_diferenca
   FROM public.pedido_compra pc
  WHERE ((data_entrega IS NOT NULL) AND (data_pedido IS NOT NULL) AND (data_entrega < data_pedido));


--
-- Name: vw_pedido_duplicado; Type: VIEW; Schema: qa; Owner: -
--

CREATE VIEW qa.vw_pedido_duplicado AS
 SELECT pedido_id,
    produto_id,
    to_char((data_pedido)::timestamp with time zone, 'DD/MM/YYYY'::text) AS data_pedido,
    ordem_compra,
    qtde_pedida,
    qtde_entregue,
    preco_compra,
    count(*) OVER (PARTITION BY produto_id, pc.data_pedido, preco_compra) AS ocorrencias
   FROM public.pedido_compra pc
  WHERE (EXISTS ( SELECT 1
           FROM public.pedido_compra d
          WHERE (((d.produto_id)::text = (pc.produto_id)::text) AND (d.data_pedido = pc.data_pedido) AND (d.preco_compra = pc.preco_compra) AND (d.pedido_id <> pc.pedido_id))));


--
-- Name: vw_pedido_sem_ordem_compra; Type: VIEW; Schema: qa; Owner: -
--

CREATE VIEW qa.vw_pedido_sem_ordem_compra AS
 SELECT pedido_id,
    produto_id,
    item,
    to_char((data_pedido)::timestamp with time zone, 'DD/MM/YYYY'::text) AS data_pedido,
    qtde_pedida,
    fornecedor_id
   FROM public.pedido_compra pc
  WHERE (ordem_compra = 0);


--
-- Name: vw_produto_margem_negativa; Type: VIEW; Schema: qa; Owner: -
--

CREATE VIEW qa.vw_produto_margem_negativa AS
 SELECT filial_id,
    idproduto,
    descricao,
    preco_compra,
    preco_venda,
    preco_unitario,
    round((preco_venda - preco_compra), 2) AS margem_absoluta,
    round(((100.0 * (preco_venda - preco_compra)) / NULLIF(preco_compra, (0)::numeric)), 2) AS margem_percentual
   FROM public.produtos_filial pf
  WHERE (preco_venda < preco_compra);


--
-- Name: vw_recebido_maior_que_pedido; Type: VIEW; Schema: qa; Owner: -
--

CREATE VIEW qa.vw_recebido_maior_que_pedido AS
 SELECT pc.ordem_compra,
    pc.pedido_id,
    pc.produto_id,
    pc.qtde_pedida,
    sum(em.qtde_recebida) AS qtde_recebida,
    (sum(em.qtde_recebida) - pc.qtde_pedida) AS excesso
   FROM (public.pedido_compra pc
     JOIN public.entradas_mercadoria em ON ((em.ordem_compra = pc.ordem_compra)))
  WHERE (pc.ordem_compra <> 0)
  GROUP BY pc.ordem_compra, pc.pedido_id, pc.produto_id, pc.qtde_pedida
 HAVING (sum(em.qtde_recebida) > pc.qtde_pedida);


--
-- Name: vw_venda_filial_sem_cadastro; Type: VIEW; Schema: qa; Owner: -
--

CREATE VIEW qa.vw_venda_filial_sem_cadastro AS
 SELECT filial_id,
    count(*) AS qtde_vendas,
    round(sum((qtde_vendida * valor_unitario)), 2) AS valor_total
   FROM public.venda v
  WHERE (NOT (EXISTS ( SELECT 1
           FROM public.produtos_filial pf
          WHERE (pf.filial_id = v.filial_id))))
  GROUP BY filial_id;


--
-- Name: vw_venda_preco_divergente; Type: VIEW; Schema: qa; Owner: -
--

CREATE VIEW qa.vw_venda_preco_divergente AS
 SELECT v.venda_id,
    v.produto_id,
    to_char((v.data_emissao)::timestamp with time zone, 'DD/MM/YYYY'::text) AS data_emissao,
    v.valor_unitario AS preco_praticado,
    pf.preco_venda AS preco_cadastro,
    pf.preco_unitario AS preco_unitario_cadastro,
    round((v.valor_unitario - pf.preco_venda), 2) AS diferenca
   FROM (public.venda v
     JOIN public.produtos_filial pf ON (((pf.filial_id = v.filial_id) AND ((pf.idproduto)::text = (v.produto_id)::text))))
  WHERE (v.valor_unitario <> pf.preco_venda);


--
-- Name: vw_venda_produto_sem_cadastro; Type: VIEW; Schema: qa; Owner: -
--

CREATE VIEW qa.vw_venda_produto_sem_cadastro AS
 SELECT venda_id,
    filial_id,
    produto_id,
    to_char((data_emissao)::timestamp with time zone, 'DD/MM/YYYY'::text) AS data_emissao,
    qtde_vendida,
    valor_unitario,
    round((qtde_vendida * valor_unitario), 2) AS valor_total
   FROM public.venda v
  WHERE (NOT (EXISTS ( SELECT 1
           FROM public.produtos_filial pf
          WHERE ((pf.filial_id = v.filial_id) AND ((pf.idproduto)::text = (v.produto_id)::text)))));


--
-- Name: vw_venda_qtde_fracionaria; Type: VIEW; Schema: qa; Owner: -
--

CREATE VIEW qa.vw_venda_qtde_fracionaria AS
 SELECT venda_id,
    produto_id,
    to_char((data_emissao)::timestamp with time zone, 'DD/MM/YYYY'::text) AS data_emissao,
    qtde_vendida,
    unidade_medida,
    round((qtde_vendida * valor_unitario), 2) AS valor_total
   FROM public.venda v
  WHERE (((unidade_medida)::text = 'UN'::text) AND (qtde_vendida <> trunc(qtde_vendida)));


--
-- Name: vw_painel_qualidade; Type: VIEW; Schema: qa; Owner: -
--

CREATE VIEW qa.vw_painel_qualidade AS
 SELECT cod,
    verificacao,
    severidade,
    ocorrencias
   FROM ( SELECT 'QA-01'::text AS cod,
            'Vendas de produto sem cadastro'::text AS verificacao,
            'ALTA'::text AS severidade,
            ( SELECT count(*) AS count
                   FROM qa.vw_venda_produto_sem_cadastro) AS ocorrencias
        UNION ALL
         SELECT 'QA-02'::text,
            'Vendas em filial sem cadastro'::text,
            'ALTA'::text,
            ( SELECT count(*) AS count
                   FROM qa.vw_venda_filial_sem_cadastro) AS count
        UNION ALL
         SELECT 'QA-03'::text,
            'Qtde fracionaria em unidade UN'::text,
            'MEDIA'::text,
            ( SELECT count(*) AS count
                   FROM qa.vw_venda_qtde_fracionaria) AS count
        UNION ALL
         SELECT 'QA-04'::text,
            'Pedido com ordem de compra zerada'::text,
            'ALTA'::text,
            ( SELECT count(*) AS count
                   FROM qa.vw_pedido_sem_ordem_compra) AS count
        UNION ALL
         SELECT 'QA-05'::text,
            'Pedidos duplicados'::text,
            'ALTA'::text,
            ( SELECT count(*) AS count
                   FROM qa.vw_pedido_duplicado) AS count
        UNION ALL
         SELECT 'QA-06'::text,
            'Entrega anterior ao pedido'::text,
            'MEDIA'::text,
            ( SELECT count(*) AS count
                   FROM qa.vw_pedido_data_invertida) AS count
        UNION ALL
         SELECT 'QA-07'::text,
            'Recebido maior que pedido'::text,
            'ALTA'::text,
            ( SELECT count(*) AS count
                   FROM qa.vw_recebido_maior_que_pedido) AS count
        UNION ALL
         SELECT 'QA-08'::text,
            'Divergencia qtde_entregue x NF'::text,
            'CRITICA'::text,
            ( SELECT count(*) AS count
                   FROM qa.vw_divergencia_entregue_vs_nf) AS count
        UNION ALL
         SELECT 'QA-09'::text,
            'Produto com margem negativa'::text,
            'ALTA'::text,
            ( SELECT count(*) AS count
                   FROM qa.vw_produto_margem_negativa) AS count
        UNION ALL
         SELECT 'QA-10'::text,
            'Preco de venda divergente do cadastro'::text,
            'MEDIA'::text,
            ( SELECT count(*) AS count
                   FROM qa.vw_venda_preco_divergente) AS count
        UNION ALL
         SELECT 'QA-11'::text,
            'Fornecedor sem produto vinculado'::text,
            'BAIXA'::text,
            ( SELECT count(*) AS count
                   FROM qa.vw_fornecedor_sem_produto) AS count) p
  ORDER BY
        CASE severidade
            WHEN 'CRITICA'::text THEN 1
            WHEN 'ALTA'::text THEN 2
            WHEN 'MEDIA'::text THEN 3
            ELSE 4
        END, cod;


--
-- Name: vw_venda_por_competencia; Type: VIEW; Schema: qa; Owner: -
--

CREATE VIEW qa.vw_venda_por_competencia AS
 SELECT to_char((data_emissao)::timestamp with time zone, 'MM/YYYY'::text) AS competencia,
    count(*) AS qtde_vendas,
    sum(qtde_vendida) AS qtde_total,
    round(sum((qtde_vendida * valor_unitario)), 2) AS valor_total,
        CASE
            WHEN (date_trunc('month'::text, (data_emissao)::timestamp with time zone) = '2025-02-01'::date) THEN 'ESCOPO DE VALIDACAO'::text
            ELSE 'fora do escopo'::text
        END AS situacao
   FROM public.venda v
  GROUP BY (to_char((data_emissao)::timestamp with time zone, 'MM/YYYY'::text)),
        CASE
            WHEN (date_trunc('month'::text, (data_emissao)::timestamp with time zone) = '2025-02-01'::date) THEN 'ESCOPO DE VALIDACAO'::text
            ELSE 'fora do escopo'::text
        END
  ORDER BY (to_char((data_emissao)::timestamp with time zone, 'MM/YYYY'::text));


--
-- Name: entradas_mercadoria; Type: TABLE; Schema: stg; Owner: -
--

CREATE TABLE stg.entradas_mercadoria (
    data_entrada text,
    nro_nfe text,
    item text,
    produto_id text,
    descricao_produto text,
    ordem_compra text,
    qtde_recebida text,
    filial_id text,
    custo_unitario text
);


--
-- Name: fornecedor; Type: TABLE; Schema: stg; Owner: -
--

CREATE TABLE stg.fornecedor (
    idfornecedor text,
    razao_social text
);


--
-- Name: pedido_compra; Type: TABLE; Schema: stg; Owner: -
--

CREATE TABLE stg.pedido_compra (
    pedido_id text,
    data_pedido text,
    item text,
    produto_id text,
    descricao_produto text,
    ordem_compra text,
    qtde_pedida text,
    filial_id text,
    data_entrega text,
    qtde_entregue text,
    preco_compra text,
    fornecedor_id text
);


--
-- Name: produtos_filial; Type: TABLE; Schema: stg; Owner: -
--

CREATE TABLE stg.produtos_filial (
    filial_id text,
    idproduto text,
    descricao text,
    estoque text,
    preco_unitario text,
    preco_compra text,
    preco_venda text,
    idfornecedor text
);


--
-- Name: venda; Type: TABLE; Schema: stg; Owner: -
--

CREATE TABLE stg.venda (
    venda_id text,
    data_emissao text,
    horariomov text,
    produto_id text,
    qtde_vendida text,
    valor_unitario text,
    filial_id text,
    item text,
    unidade_medida text
);


--
-- Data for Name: entradas_mercadoria; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.entradas_mercadoria (ordem_compra, nro_nfe, item, produto_id, descricao_produto, data_entrada, qtde_recebida, filial_id, custo_unitario) FROM stdin;
1	NFE1	1	P1	Produto 1	2025-02-27	77.000	1	84.3500
2	NFE2	1	P2	Produto 2	2025-01-20	64.000	1	16.6600
3	NFE3	1	P3	Produto 3	2025-02-18	88.000	1	90.3600
4	NFE4	1	P4	Produto 4	2025-02-12	4.000	1	84.6800
5	NFE5	1	P5	Produto 5	2025-02-19	95.000	1	98.9900
6	NFE6	1	P6	Produto 6	2025-02-08	41.000	1	90.2900
7	NFE7	1	P7	Produto 7	2025-01-03	75.000	1	27.2200
8	NFE8	1	P8	Produto 8	2025-02-21	25.000	1	71.1000
9	NFE9	1	P9	Produto 9	2025-02-13	57.000	1	19.5500
10	NFE10	1	P10	Produto 10	2025-03-01	7.000	1	54.3900
11	NFE11	1	P11	Produto 11	2025-01-23	85.000	1	91.8900
12	NFE12	1	P12	Produto 12	2025-01-02	12.000	1	38.5300
13	NFE13	1	P13	Produto 13	2025-02-20	7.000	1	60.8600
14	NFE14	1	P14	Produto 14	2025-01-10	92.000	1	38.4800
15	NFE15	1	P15	Produto 15	2025-01-13	68.000	1	95.5800
16	NFE16	1	P16	Produto 16	2025-01-22	89.000	1	39.4600
17	NFE17	1	P17	Produto 17	2025-02-24	10.000	1	10.3200
18	NFE18	1	P18	Produto 18	2025-01-31	48.000	1	62.5600
19	NFE19	1	P19	Produto 19	2025-02-13	64.000	1	84.5400
20	NFE20	1	P20	Produto 20	2025-01-01	6.000	1	65.7000
\.


--
-- Data for Name: fornecedor; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.fornecedor (idfornecedor, fornecedor_num, razao_social, criado_em) FROM stdin;
F1	1	Fornecedor 1 LTDA	2026-09-18 17:15:44.186242+00
F2	2	Fornecedor 2 LTDA	2026-09-18 17:15:44.186242+00
F3	3	Fornecedor 3 LTDA	2026-09-18 17:15:44.186242+00
F4	4	Fornecedor 4 LTDA	2026-09-18 17:15:44.186242+00
F5	5	Fornecedor 5 LTDA	2026-09-18 17:15:44.186242+00
F6	6	Fornecedor 6 LTDA	2026-09-18 17:15:44.186242+00
F7	7	Fornecedor 7 LTDA	2026-09-18 17:15:44.186242+00
F8	8	Fornecedor 8 LTDA	2026-09-18 17:15:44.186242+00
F9	9	Fornecedor 9 LTDA	2026-09-18 17:15:44.186242+00
F10	10	Fornecedor 10 LTDA	2026-09-18 17:15:44.186242+00
F11	11	Fornecedor 11 LTDA	2026-09-18 17:15:44.186242+00
F12	12	Fornecedor 12 LTDA	2026-09-18 17:15:44.186242+00
F13	13	Fornecedor 13 LTDA	2026-09-18 17:15:44.186242+00
F14	14	Fornecedor 14 LTDA	2026-09-18 17:15:44.186242+00
F15	15	Fornecedor 15 LTDA	2026-09-18 17:15:44.186242+00
F16	16	Fornecedor 16 LTDA	2026-09-18 17:15:44.186242+00
F17	17	Fornecedor 17 LTDA	2026-09-18 17:15:44.186242+00
F18	18	Fornecedor 18 LTDA	2026-09-18 17:15:44.186242+00
F19	19	Fornecedor 19 LTDA	2026-09-18 17:15:44.186242+00
F20	20	Fornecedor 20 LTDA	2026-09-18 17:15:44.186242+00
\.


--
-- Data for Name: pedido_compra; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.pedido_compra (pedido_id, item, ordem_compra, data_pedido, produto_id, descricao_produto, qtde_pedida, filial_id, data_entrega, qtde_entregue, qtde_pendente, preco_compra, fornecedor_id) FROM stdin;
1	1	1	2025-01-02	P1	Produto 1	96.000	1	2025-02-27	10.000	86.000	46.6700	1
2	1	2	2025-01-07	P2	Produto 2	14.000	1	2025-01-07	7.000	7.000	77.3200	2
3	1	3	2025-01-05	P3	Produto 3	12.000	1	2025-01-03	2.000	10.000	47.8200	3
4	1	4	2025-01-22	P4	Produto 4	27.000	1	2025-01-28	3.000	24.000	49.5700	4
5	1	5	2025-01-28	P5	Produto 5	35.000	1	2025-02-28	12.000	23.000	57.1800	5
6	1	6	2025-02-22	P6	Produto 6	98.000	1	2025-01-05	55.000	43.000	59.9600	6
7	1	7	2025-03-01	P7	Produto 7	34.000	1	2025-02-01	29.000	5.000	49.2200	7
8	1	8	2025-02-02	P8	Produto 8	29.000	1	2025-02-14	24.000	5.000	35.8800	8
9	1	9	2025-01-15	P9	Produto 9	57.000	1	2025-01-28	34.000	23.000	28.4800	9
10	1	10	2025-01-09	P10	Produto 10	49.000	1	2025-02-09	4.000	45.000	42.8600	10
11	1	11	2025-02-22	P11	Produto 11	24.000	1	2025-01-08	12.000	12.000	14.8200	11
12	1	12	2025-02-25	P12	Produto 12	91.000	1	2025-02-20	48.000	43.000	6.9200	12
13	1	13	2025-02-23	P13	Produto 13	99.000	1	2025-02-02	91.000	8.000	65.4400	13
14	1	14	2025-01-21	P14	Produto 14	96.000	1	2025-01-01	27.000	69.000	21.9100	14
15	1	15	2025-02-04	P15	Produto 15	45.000	1	2025-01-04	1.000	44.000	85.0400	15
16	1	16	2025-02-27	P16	Produto 16	84.000	1	2025-01-14	51.000	33.000	64.1700	16
17	1	17	2025-01-08	P17	Produto 17	22.000	1	2025-01-19	7.000	15.000	74.5500	17
18	1	18	2025-02-17	P18	Produto 18	63.000	1	2025-01-02	17.000	46.000	24.9400	18
19	1	0	2025-02-19	P19	Produto 19	20.000	1	2025-01-08	0.000	20.000	22.2100	19
20	1	0	2025-02-10	P20	Produto 20	25.000	1	2025-01-15	0.000	25.000	38.5100	20
21	1	0	2025-02-25	P12	Produto 12	12.000	1	2025-02-20	0.000	12.000	6.9200	12
22	1	0	2025-02-23	P13	Produto 13	4.000	1	2025-02-02	0.000	4.000	65.4400	13
23	1	0	2025-01-21	P14	Produto 14	6.000	1	2025-01-01	0.000	6.000	21.9100	14
24	1	0	2025-02-04	P15	Produto 15	8.000	1	2025-01-04	0.000	8.000	85.0400	15
25	1	0	2025-02-27	P16	Produto 16	9.000	1	2025-01-14	0.000	9.000	64.1700	16
26	1	0	2025-01-08	P17	Produto 17	4.000	1	2025-01-19	0.000	4.000	74.5500	17
27	1	0	2025-02-17	P18	Produto 18	3.000	1	2025-01-02	0.000	3.000	24.9400	18
28	1	0	2025-02-19	P19	Produto 19	3.000	1	2025-01-08	0.000	3.000	22.2100	19
29	1	0	2025-02-10	P20	Produto 20	2.000	1	2025-01-15	0.000	2.000	38.5100	20
\.


--
-- Data for Name: produtos_filial; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.produtos_filial (filial_id, idproduto, descricao, estoque, preco_unitario, preco_compra, preco_venda, idfornecedor, idfornecedor_num) FROM stdin;
1	P1	Produto 1	88.000	42.6500	144.1300	40.7900	F8	8
1	P2	Produto 2	28.000	79.5200	103.5600	174.1800	F9	9
1	P3	Produto 3	40.000	119.5000	24.1400	60.6900	F10	10
1	P4	Produto 4	73.000	89.6700	7.7500	226.5000	F11	11
1	P5	Produto 5	97.000	135.9900	36.1800	89.9200	F12	12
1	P6	Produto 6	38.000	161.3100	55.3700	95.6000	F13	13
1	P7	Produto 7	131.000	153.8200	14.0400	46.6400	F7	7
1	P8	Produto 8	71.000	140.5700	149.5000	95.2800	F17	17
1	P9	Produto 9	2.000	30.8800	137.0000	164.3200	F18	18
1	P10	Produto 10	38.000	115.7100	27.7700	87.7000	F19	19
1	P11	Produto 11	154.000	147.9900	29.3900	44.9500	F1	1
1	P12	Produto 12	78.000	32.4700	64.6300	276.5800	F2	2
1	P13	Produto 13	79.000	194.0400	58.3000	99.0500	F3	3
1	P14	Produto 14	9.000	199.5600	56.8000	80.7400	F4	4
1	P15	Produto 15	131.000	101.1500	107.6000	29.2400	F5	5
1	P16	Produto 16	177.000	24.6400	75.9400	278.8800	F6	6
1	P17	Produto 17	105.000	195.6300	126.2500	183.9200	F7	7
1	P18	Produto 18	198.000	162.2000	134.1200	105.6100	F18	18
1	P19	Produto 19	148.000	184.3600	121.6900	234.5800	F19	19
1	P20	Produto 20	196.000	52.0400	124.8700	157.9300	F20	20
\.


--
-- Data for Name: venda; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.venda (venda_id, data_emissao, horariomov, produto_id, qtde_vendida, valor_unitario, filial_id, item, unidade_medida) FROM stdin;
1	2025-01-11	08:00:00	P1	5.000	78.9300	1	1	UN
2	2025-03-02	08:00:00	P2	7.000	92.9600	1	1	UN
3	2025-01-28	08:00:00	P3	9.000	197.6100	1	1	UN
4	2025-01-10	08:00:00	P4	38.600	139.7100	1	1	UN
5	2025-01-11	08:00:00	P5	3.000	126.7900	1	1	UN
6	2025-01-24	08:00:00	P6	2.000	36.8300	1	1	UN
7	2025-02-22	08:00:00	P7	5.000	40.7500	1	1	UN
8	2025-01-26	08:00:00	P8	20.040	51.3700	1	1	UN
9	2025-01-17	08:00:00	P9	6.000	172.5500	1	1	UN
10	2025-01-03	08:00:00	P10	90.000	44.2200	1	1	UN
11	2025-01-08	08:00:00	P11	6.000	190.3700	1	1	UN
12	2025-01-21	08:00:00	P12	2.860	136.4000	1	1	UN
13	2025-01-24	08:00:00	P13	13.000	61.8500	1	1	UN
14	2025-02-07	08:00:00	P14	53.000	106.3000	1	1	UN
15	2025-02-20	08:00:00	P15	27.000	43.4000	1	1	UN
16	2025-02-17	08:00:00	P16	37.110	14.4100	1	1	UN
17	2025-02-22	08:00:00	P17	3.000	139.8000	1	1	UN
18	2025-02-18	08:00:00	P18	5.000	185.2300	1	1	UN
19	2025-02-20	08:00:00	P19	10.000	182.5100	1	1	UN
20	2025-02-28	08:00:00	P20	2.000	68.5400	1	1	UN
21	2025-01-24	08:00:00	P21	25.000	61.8500	1	1	UN
22	2025-02-07	08:00:00	P22	6.000	106.3000	1	1	UN
23	2025-02-20	08:00:00	P23	7.000	43.4000	1	1	UN
24	2025-02-17	08:00:00	P24	4.000	14.4100	1	1	UN
25	2025-02-22	08:00:00	P25	8.000	139.8000	1	1	UN
26	2025-02-18	08:00:00	P26	3.110	185.2300	1	1	UN
27	2025-02-20	08:00:00	P27	3.000	182.5100	2	1	UN
28	2025-03-28	08:00:00	P28	6.000	68.5400	3	1	UN
29	2025-03-17	08:00:00	P24	5.000	14.4100	1	1	UN
30	2025-03-22	08:00:00	P25	3.000	139.8000	1	1	UN
31	2025-03-18	08:00:00	P26	4.000	185.2300	1	1	UN
32	2025-03-20	08:00:00	P27	2.000	182.5100	2	1	UN
33	2025-03-28	08:00:00	P28	1.000	68.5400	3	1	UN
\.


--
-- Data for Name: entradas_mercadoria; Type: TABLE DATA; Schema: stg; Owner: -
--

COPY stg.entradas_mercadoria (data_entrada, nro_nfe, item, produto_id, descricao_produto, ordem_compra, qtde_recebida, filial_id, custo_unitario) FROM stdin;
2025-02-27	NFE1	1	P1	Produto 1	1	77	1	84.35
2025-01-20	NFE2	1	P2	Produto 2	2	64	1	16.66
2025-02-18	NFE3	1	P3	Produto 3	3	88	1	90.36
2025-02-12	NFE4	1	P4	Produto 4	4	4	1	84.68
2025-02-19	NFE5	1	P5	Produto 5	5	95	1	98.99
2025-02-08	NFE6	1	P6	Produto 6	6	41	1	90.29
2025-01-03	NFE7	1	P7	Produto 7	7	75	1	27.22
2025-02-21	NFE8	1	P8	Produto 8	8	25	1	71.1
2025-02-13	NFE9	1	P9	Produto 9	9	57	1	19.55
2025-03-01	NFE10	1	P10	Produto 10	10	7	1	54.39
2025-01-23	NFE11	1	P11	Produto 11	11	85	1	91.89
2025-01-02	NFE12	1	P12	Produto 12	12	12	1	38.53
2025-02-20	NFE13	1	P13	Produto 13	13	7	1	60.86
2025-01-10	NFE14	1	P14	Produto 14	14	92	1	38.48
2025-01-13	NFE15	1	P15	Produto 15	15	68	1	95.58
2025-01-22	NFE16	1	P16	Produto 16	16	89	1	39.46
2025-02-24	NFE17	1	P17	Produto 17	17	10	1	10.32
2025-01-31	NFE18	1	P18	Produto 18	18	48	1	62.56
2025-02-13	NFE19	1	P19	Produto 19	19	64	1	84.54
2025-01-01	NFE20	1	P20	Produto 20	20	6	1	65.7
\.


--
-- Data for Name: fornecedor; Type: TABLE DATA; Schema: stg; Owner: -
--

COPY stg.fornecedor (idfornecedor, razao_social) FROM stdin;
F1	Fornecedor 1 LTDA
F2	Fornecedor 2 LTDA
F3	Fornecedor 3 LTDA
F4	Fornecedor 4 LTDA
F5	Fornecedor 5 LTDA
F6	Fornecedor 6 LTDA
F7	Fornecedor 7 LTDA
F8	Fornecedor 8 LTDA
F9	Fornecedor 9 LTDA
F10	Fornecedor 10 LTDA
F11	Fornecedor 11 LTDA
F12	Fornecedor 12 LTDA
F13	Fornecedor 13 LTDA
F14	Fornecedor 14 LTDA
F15	Fornecedor 15 LTDA
F16	Fornecedor 16 LTDA
F17	Fornecedor 17 LTDA
F18	Fornecedor 18 LTDA
F19	Fornecedor 19 LTDA
F20	Fornecedor 20 LTDA
\.


--
-- Data for Name: pedido_compra; Type: TABLE DATA; Schema: stg; Owner: -
--

COPY stg.pedido_compra (pedido_id, data_pedido, item, produto_id, descricao_produto, ordem_compra, qtde_pedida, filial_id, data_entrega, qtde_entregue, preco_compra, fornecedor_id) FROM stdin;
1	2025-01-02	1	P1	Produto 1	1	96	1	2025-02-27	10	46.67	1
2	2025-01-07	1	P2	Produto 2	2	14	1	2025-01-07	7	77.32	2
3	2025-01-05	1	P3	Produto 3	3	12	1	2025-01-03	2	47.82	3
4	2025-01-22	1	P4	Produto 4	4	27	1	2025-01-28	3	49.57	4
5	2025-01-28	1	P5	Produto 5	5	35	1	2025-02-28	12	57.18	5
6	2025-02-22	1	P6	Produto 6	6	98	1	2025-01-05	55	59.96	6
7	2025-03-01	1	P7	Produto 7	7	34	1	2025-02-01	29	49.22	7
8	2025-02-02	1	P8	Produto 8	8	29	1	2025-02-14	24	35.88	8
9	2025-01-15	1	P9	Produto 9	9	57	1	2025-01-28	34	28.48	9
10	2025-01-09	1	P10	Produto 10	10	49	1	2025-02-09	4	42.86	10
11	2025-02-22	1	P11	Produto 11	11	24	1	2025-01-08	12	14.82	11
12	2025-02-25	1	P12	Produto 12	12	91	1	2025-02-20	48	6.92	12
13	2025-02-23	1	P13	Produto 13	13	99	1	2025-02-02	91	65.44	13
14	2025-01-21	1	P14	Produto 14	14	96	1	2025-01-01	27	21.91	14
15	2025-02-04	1	P15	Produto 15	15	45	1	2025-01-04	1	85.04	15
16	2025-02-27	1	P16	Produto 16	16	84	1	2025-01-14	51	64.17	16
17	2025-01-08	1	P17	Produto 17	17	22	1	2025-01-19	7	74.55	17
18	2025-02-17	1	P18	Produto 18	18	63	1	2025-01-02	17	24.94	18
19	2025-02-19	1	P19	Produto 19	0	20	1	2025-01-08	0	22.21	19
20	2025-02-10	1	P20	Produto 20	0	25	1	2025-01-15	0	38.51	20
21	2025-02-25	1	P12	Produto 12	0	12	1	2025-02-20	0	6.92	12
22	2025-02-23	1	P13	Produto 13	0	4	1	2025-02-02	0	65.44	13
23	2025-01-21	1	P14	Produto 14	0	6	1	2025-01-01	0	21.91	14
24	2025-02-04	1	P15	Produto 15	0	8	1	2025-01-04	0	85.04	15
25	2025-02-27	1	P16	Produto 16	0	9	1	2025-01-14	0	64.17	16
26	2025-01-08	1	P17	Produto 17	0	4	1	2025-01-19	0	74.55	17
27	2025-02-17	1	P18	Produto 18	0	3	1	2025-01-02	0	24.94	18
28	2025-02-19	1	P19	Produto 19	0	3	1	2025-01-08	0	22.21	19
29	2025-02-10	1	P20	Produto 20	0	2	1	2025-01-15	0	38.51	20
\.


--
-- Data for Name: produtos_filial; Type: TABLE DATA; Schema: stg; Owner: -
--

COPY stg.produtos_filial (filial_id, idproduto, descricao, estoque, preco_unitario, preco_compra, preco_venda, idfornecedor) FROM stdin;
1	P1	Produto 1	88	42.65	144.13	40.79	F8
1	P2	Produto 2	28	79.52	103.56	174.18	F9
1	P3	Produto 3	40	119.5	24.14	60.69	F10
1	P4	Produto 4	73	89.67	7.75	226.5	F11
1	P5	Produto 5	97	135.99	36.18	89.92	F12
1	P6	Produto 6	38	161.31	55.37	95.6	F13
1	P7	Produto 7	131	153.82	14.04	46.64	F7
1	P8	Produto 8	71	140.57	149.5	95.28	F17
1	P9	Produto 9	2	30.88	137	164.32	F18
1	P10	Produto 10	38	115.71	27.77	87.7	F19
1	P11	Produto 11	154	147.99	29.39	44.95	F1
1	P12	Produto 12	78	32.47	64.63	276.58	F2
1	P13	Produto 13	79	194.04	58.3	99.05	F3
1	P14	Produto 14	9	199.56	56.8	80.74	F4
1	P15	Produto 15	131	101.15	107.6	29.24	F5
1	P16	Produto 16	177	24.64	75.94	278.88	F6
1	P17	Produto 17	105	195.63	126.25	183.92	F7
1	P18	Produto 18	198	162.2	134.12	105.61	F18
1	P19	Produto 19	148	184.36	121.69	234.58	F19
1	P20	Produto 20	196	52.04	124.87	157.93	F20
\.


--
-- Data for Name: venda; Type: TABLE DATA; Schema: stg; Owner: -
--

COPY stg.venda (venda_id, data_emissao, horariomov, produto_id, qtde_vendida, valor_unitario, filial_id, item, unidade_medida) FROM stdin;
1	2025-01-11	08:00:00	P1	5	78.93	1	1	UN
2	2025-03-02	08:00:00	P2	7	92.96	1	1	UN
3	2025-01-28	08:00:00	P3	9	197.61	1	1	UN
4	2025-01-10	08:00:00	P4	38.6	139.71	1	1	UN
5	2025-01-11	08:00:00	P5	3	126.79	1	1	UN
6	2025-01-24	08:00:00	P6	2	36.83	1	1	UN
7	2025-02-22	08:00:00	P7	5	40.75	1	1	UN
8	2025-01-26	08:00:00	P8	20.04	51.37	1	1	UN
9	2025-01-17	08:00:00	P9	6	172.55	1	1	UN
10	2025-01-03	08:00:00	P10	90	44.22	1	1	UN
11	2025-01-08	08:00:00	P11	6	190.37	1	1	UN
12	2025-01-21	08:00:00	P12	2.86	136.4	1	1	UN
13	2025-01-24	08:00:00	P13	13	61.85	1	1	UN
14	2025-02-07	08:00:00	P14	53	106.3	1	1	UN
15	2025-02-20	08:00:00	P15	27	43.4	1	1	UN
16	2025-02-17	08:00:00	P16	37.11	14.41	1	1	UN
17	2025-02-22	08:00:00	P17	3	139.8	1	1	UN
18	2025-02-18	08:00:00	P18	5	185.23	1	1	UN
19	2025-02-20	08:00:00	P19	10	182.51	1	1	UN
20	2025-02-28	08:00:00	P20	2	68.54	1	1	UN
21	2025-01-24	08:00:00	P21	25	61.85	1	1	UN
22	2025-02-07	08:00:00	P22	6	106.3	1	1	UN
23	2025-02-20	08:00:00	P23	7	43.4	1	1	UN
24	2025-02-17	08:00:00	P24	4	14.41	1	1	UN
25	2025-02-22	08:00:00	P25	8	139.8	1	1	UN
26	2025-02-18	08:00:00	P26	3.11	185.23	1	1	UN
27	2025-02-20	08:00:00	P27	3	182.51	2	1	UN
28	2025-03-28	08:00:00	P28	6	68.54	3	1	UN
29	2025-03-17	08:00:00	P24	5	14.41	1	1	UN
30	2025-03-22	08:00:00	P25	3	139.8	1	1	UN
31	2025-03-18	08:00:00	P26	4	185.23	1	1	UN
32	2025-03-20	08:00:00	P27	2	182.51	2	1	UN
33	2025-03-28	08:00:00	P28	1	68.54	3	1	UN
\.


--
-- Name: fornecedor_fornecedor_num_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.fornecedor_fornecedor_num_seq', 21, true);


--
-- Name: entradas_mercadoria entradas_mercadoria_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entradas_mercadoria
    ADD CONSTRAINT entradas_mercadoria_pkey PRIMARY KEY (ordem_compra, item, produto_id, nro_nfe);


--
-- Name: fornecedor fornecedor_num_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fornecedor
    ADD CONSTRAINT fornecedor_num_uk UNIQUE (fornecedor_num);


--
-- Name: fornecedor fornecedor_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fornecedor
    ADD CONSTRAINT fornecedor_pkey PRIMARY KEY (idfornecedor);


--
-- Name: pedido_compra pedido_compra_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pedido_compra
    ADD CONSTRAINT pedido_compra_pkey PRIMARY KEY (pedido_id, produto_id, item);


--
-- Name: produtos_filial produtos_filial_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.produtos_filial
    ADD CONSTRAINT produtos_filial_pkey PRIMARY KEY (filial_id, idproduto);


--
-- Name: venda venda_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venda
    ADD CONSTRAINT venda_pkey PRIMARY KEY (filial_id, venda_id, data_emissao, produto_id, item, horariomov);


--
-- Name: ix_entradas_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_entradas_data ON public.entradas_mercadoria USING btree (data_entrada);


--
-- Name: ix_entradas_ordem; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_entradas_ordem ON public.entradas_mercadoria USING btree (ordem_compra);


--
-- Name: ix_entradas_produto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_entradas_produto ON public.entradas_mercadoria USING btree (produto_id);


--
-- Name: ix_pedido_compra_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_pedido_compra_data ON public.pedido_compra USING btree (data_pedido);


--
-- Name: ix_pedido_compra_ordem; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_pedido_compra_ordem ON public.pedido_compra USING btree (ordem_compra);


--
-- Name: ix_pedido_compra_produto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_pedido_compra_produto ON public.pedido_compra USING btree (produto_id);


--
-- Name: ix_venda_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_venda_data ON public.venda USING btree (data_emissao);


--
-- Name: ix_venda_periodo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_venda_periodo ON public.venda USING btree (data_emissao, produto_id);


--
-- Name: ix_venda_produto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_venda_produto ON public.venda USING btree (produto_id);


--
-- Name: produtos_filial tg_produtos_filial_vincula_fornecedor; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER tg_produtos_filial_vincula_fornecedor BEFORE INSERT OR UPDATE OF idfornecedor, idfornecedor_num ON public.produtos_filial FOR EACH ROW EXECUTE FUNCTION public.fn_produtos_filial_vincula_fornecedor();


--
-- Name: pedido_compra pedido_compra_fornecedor_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pedido_compra
    ADD CONSTRAINT pedido_compra_fornecedor_fk FOREIGN KEY (fornecedor_id) REFERENCES public.fornecedor(fornecedor_num) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: produtos_filial produtos_filial_fornecedor_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.produtos_filial
    ADD CONSTRAINT produtos_filial_fornecedor_fk FOREIGN KEY (idfornecedor) REFERENCES public.fornecedor(idfornecedor) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: produtos_filial produtos_filial_fornecedor_num_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.produtos_filial
    ADD CONSTRAINT produtos_filial_fornecedor_num_fk FOREIGN KEY (idfornecedor_num) REFERENCES public.fornecedor(fornecedor_num) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: venda venda_produto_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venda
    ADD CONSTRAINT venda_produto_fk FOREIGN KEY (filial_id, produto_id) REFERENCES public.produtos_filial(filial_id, idproduto) NOT VALID;


--
-- Name: CONSTRAINT venda_produto_fk ON venda; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT venda_produto_fk ON public.venda IS 'NOT VALID: o historico tem 13 vendas orfas (P21..P28) e 4 em filiais sem cadastro. Rodar VALIDATE CONSTRAINT apos o saneamento aprovado pelo cliente.';


--
-- PostgreSQL database dump complete
--

\unrestrict pn4Vec2LRXslUpYg3z0puCnRzTGxkeEDEI4nyvCvMrANe5E5sWFLm7FZIAhocp7

