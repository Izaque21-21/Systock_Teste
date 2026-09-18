/* =============================================================================
   Systock - Case Tecnico de Integracao de Dados
   Arquivo 00 - DDL ORIGINAL DO ENUNCIADO, COMENTADO

   ATENCAO: ESTE ARQUIVO NAO DEVE SER EXECUTADO.
   Ele esta aqui apenas como registro de auditoria: e o DDL exatamente como
   veio no enunciado, com cada problema anotado no ponto em que ocorre.

   O script que realmente cria o banco e o 01_ddl_corrigido.sql.

   Resumo: o DDL do enunciado NAO e executavel. Sao 4 erros de sintaxe/
   referencia que abortam a execucao, alem de 11 problemas de modelagem que
   nao quebram a criacao mas comprometem a integridade dos dados.
   ============================================================================= */


-- -----------------------------------------------------------------------------
-- TABELA 1: venda
-- Status: EXECUTA, mas com ressalvas de modelagem.
-- -----------------------------------------------------------------------------
CREATE TABLE public.venda(
    venda_id int8 NOT NULL,
    data_emissao date NOT NULL,
    horariomov varchar(8) DEFAULT '00:00:00'::character varying NOT NULL,
        -- [M-01] Hora armazenada como texto. Impede ordenacao e aritmetica
        --        temporal corretas e aceita '99:99:99'. Deveria ser TIME.
    produto_id varchar(25) DEFAULT ''::character varying NOT NULL,
        -- [M-02] varchar(25) aqui, mas varchar(255) em produtos_filial.
        --        Divergencia de dominio para a mesma entidade.
    qtde_vendida float8 NULL,
        -- [M-03] float8 para quantidade. Ponto flutuante binario nao representa
        --        decimais exatos; somas acumulam erro. Deveria ser NUMERIC.
        -- [M-04] NULL permitido em quantidade vendida. Venda sem quantidade
        --        nao existe no negocio.
    valor_unitario numeric(12, 4) DEFAULT 0 NOT NULL,
    filial_id int8 DEFAULT 1 NOT NULL,
        -- [M-05] int8 aqui, int4 nas demais tabelas. Mismatch de tipo em JOIN.
    item int4 DEFAULT 0 NOT NULL,
    unidade_medida varchar(3) NULL,
    CONSTRAINT pk_consumo PRIMARY KEY (filial_id, venda_id, data_emissao, produto_id, item, horariomov)
        -- [M-06] Nome da constraint ("pk_consumo") nao corresponde a tabela.
        -- [M-07] PK de 6 colunas incluindo data e hora. Se a mesma venda for
        --        reprocessada com horario diferente, duplica sem violar a PK.
);


-- -----------------------------------------------------------------------------
-- TABELA 2: pedido_compra
-- Status: EXECUTA, mas diverge da planilha.
-- -----------------------------------------------------------------------------
CREATE TABLE public.pedido_compra(
    pedido_id float8 DEFAULT 0 NOT NULL,
        -- [E-01 / M-08] Identificador em ponto flutuante. Alem de conceitualmente
        --        errado, float8 nao garante igualdade exata em JOIN/PK.
        --        Vale para pedido_id, item e ordem_compra.
    data_pedido date NULL,
    item float8 DEFAULT 0 NOT NULL,          -- idem [M-08]
    produto_id varchar(25) DEFAULT '0' NOT NULL,
        -- [M-09] DEFAULT '0' para uma chave de produto. Mascara carga incompleta:
        --        a linha entra com produto inexistente em vez de falhar.
    descricao_produto varchar(255) NULL,
        -- [M-10] Descricao duplicada aqui e em produtos_filial. Sem FK, as duas
        --        podem divergir livremente.
    ordem_compra float8 DEFAULT 0 NOT NULL,  -- idem [M-08]
    qtde_pedida float8 NULL,
    filial_id int4 NULL,                     -- idem [M-05]
    data_entrega date NULL,
    qtde_entregue float8 DEFAULT 0 NOT NULL,
    qtde_pendente float8 DEFAULT 0 NOT NULL,
        -- [D-01] ESTA COLUNA NAO EXISTE NA PLANILHA. O cabecalho de
        --        pedido_compra tem 12 colunas e qtde_pendente nao esta entre elas.
        --        Ver docs/02 - decisao: derivar de qtde_pedida - qtde_entregue.
    preco_compra float8 DEFAULT 0 NULL,
        -- [M-11] Valor monetario em float8. Em venda o mesmo conceito e
        --        numeric(12,4). Inconsistencia que gera divergencia de centavos.
    fornecedor_id int4 DEFAULT 0 NULL,
        -- [E-02] TIPO INCOMPATIVEL COM A TABELA FORNECEDOR.
        --        Aqui e int4 (valores 1..20); em fornecedor a chave e
        --        varchar ('F1'..'F20'). Relacionamento impossivel sem conversao.
    CONSTRAINT pedido_compra_pkey PRIMARY KEY (pedido_id , produto_id, item)
);


-- -----------------------------------------------------------------------------
-- TABELA 3: entradas_mercadoria
-- Status: *** NAO EXECUTA *** - ERRO DE SINTAXE
-- -----------------------------------------------------------------------------
CREATE TABLE public.entradas_mercadoria (
    data_entrada date NULL,
    nro_nfe varchar(255) NOT NULL,
    item float8 DEFAULT 0 NOT NULL,
    produto_id varchar(25) DEFAULT '0' NOT NULL,
    descricao_produto varchar(255) NULL,
    qtde_recebida float8 NULL,
    filial_id int4 NULL,
    custo_unitario numeric(12, 4) DEFAULT 0 NOT NULL,
    CONSTRAINT entradas_mercadoria_pkey PRIMARY KEY (ordem_compra, item, produto_id, nro_nfe)
        -- [E-03] *** ERRO FATAL ***
        --        A PK referencia a coluna ORDEM_COMPRA, que nao foi declarada
        --        nesta tabela. PostgreSQL aborta com:
        --        ERROR: column "ordem_compra" named in key does not exist
        --
        --        Agrava o problema: a propria observacao do enunciado diz que
        --        "uma entrada de mercadoria e atrelada ao seu pedido de compra
        --        pelo campo ORDEM_COMPRA". Ou seja, a coluna faltante e
        --        justamente a chave de ligacao entre as duas tabelas.
        --
        --        A planilha CONFIRMA que a coluna existe (9 colunas, incluindo
        --        ordem_compra). Correcao: declarar ordem_compra int8 NOT NULL.
);


-- -----------------------------------------------------------------------------
-- TABELA 4: produtos_filial
-- Status: *** NAO EXECUTA *** - 3 ERROS
-- -----------------------------------------------------------------------------
CREATE TABLE public.produtos_filial(
    filial_id int4 NULL,
        -- [M-12] Coluna de PK declarada NULL. Contraditorio: PostgreSQL
        --        converte para NOT NULL silenciosamente.
    produto_id varchar(255) NOT NULL,
        -- [E-04] Nome diverge da planilha, que traz a coluna como IDPRODUTO.
        --        E a PK abaixo tambem referencia "idproduto".
    decricao varchar(255) NOT NULL,
        -- [E-05] ERRO DE GRAFIA: "decricao". Na planilha a coluna e "descricao".
    estoque float8 DEFAULT 0 NOT NULL,
    preco_unitario float8 DEFAULT '0' NOT NULL,
        -- [M-13] Tres colunas de preco (unitario, compra, venda) sem definicao
        --        de qual e a oficial para faturamento. Ambiguidade de negocio
        --        que precisa ser resolvida com o cliente (ver docs/03).
    preco_compra float8 DEFAULT '0' NOT NULL,
    preco_venda float8 DEFAULT '0' NOT NULL,
    idfonecedor int4 NULL
        -- [E-06] ERRO DE GRAFIA: "idfonecedor" (falta o R). Planilha: idfornecedor.
        -- [E-07] *** ERRO FATAL DE SINTAXE ***
        --        FALTA A VIRGULA no fim desta linha, antes do CONSTRAINT.
        --        PostgreSQL aborta com: ERROR: syntax error at or near "CONSTRAINT"
        -- [E-08] TIPO ERRADO: declarado int4, mas a planilha traz valores
        --        TEXTUAIS ('F8', 'F9', 'F10'). Um INSERT falharia com
        --        invalid input syntax for type integer: "F8".
    CONSTRAINT produtos_filial_pkey PRIMARY KEY (filial_id, idproduto)
        -- [E-09] *** ERRO FATAL ***
        --        A PK referencia "idproduto", coluna que nao existe: a coluna
        --        declarada acima se chama "produto_id".
);


-- -----------------------------------------------------------------------------
-- TABELA 5: fornecedor
-- Status: *** NAO EXECUTA *** - ERRO DE REFERENCIA
-- -----------------------------------------------------------------------------
CREATE TABLE public.fornecedor(
    idforncedor  varchar(25) NOT NULL,
        -- [E-10] ERRO DE GRAFIA: "idforncedor" (letras trocadas).
        --        Planilha: idfornecedor.
    razao_social varchar(255) NOT NULL,
    CONSTRAINT fornecedor_pkey PRIMARY KEY (idforncedor, idproduto)
        -- [E-11] *** ERRO FATAL ***
        --        A PK referencia "idproduto", que nao existe nesta tabela e nem
        --        deveria: fornecedor nao tem relacao 1:1 com produto.
        --        Colocar idproduto na PK de fornecedor quebraria a 2FN -
        --        o mesmo fornecedor apareceria repetido para cada produto.
        --        Correcao: PRIMARY KEY (idfornecedor).
);


/* =============================================================================
   O QUE FALTA POR COMPLETO NO DDL ORIGINAL

   [F-01] Nenhuma FOREIGN KEY em nenhuma das 5 tabelas. Nada impede venda de
          produto inexistente, pedido de fornecedor inexistente ou entrada sem
          pedido. A base confirma: ha vendas de P21..P28, produtos que nao
          existem em produtos_filial.

   [F-02] Nenhum CHECK constraint. Quantidades e precos negativos entram sem
          resistencia.

   [F-03] Nenhum indice alem das PKs. As consultas de analise filtram por
          data_emissao e produto_id, que ficam sem suporte de indice.

   [F-04] Nenhum COMMENT. Em projeto de implantacao a documentacao no proprio
          catalogo do banco e o que sobrevive a troca de equipe.

   [F-05] Divergencia de nomenclatura entre o enunciado e o DDL: o texto fala
          em tabelas "vendas" e "produtos"; o DDL cria "venda" e
          "produtos_filial".
   ============================================================================= */
