/* =============================================================================
   Systock - Case Tecnico de Integracao de Dados
   Arquivo 03 - PARTE 2: CONSULTAS SQL BASICAS
   ============================================================================= */


/* -----------------------------------------------------------------------------
   2.1 - CONSUMO POR PRODUTO E MES
   "Total de vendas, em quantidade e em valores (R$), de cada produto,
    no mes de fevereiro de 2025."

   Duas decisoes tecnicas:

   (a) Filtro de periodo por intervalo semiaberto
       [2025-02-01, 2025-03-01) em vez de BETWEEN ou EXTRACT.
       Motivo: EXTRACT(MONTH FROM data_emissao) aplica funcao sobre a coluna e
       inviabiliza o uso do indice ix_venda_data. O intervalo semiaberto e
       sargable e continua correto se a coluna virar timestamp no futuro -
       BETWEEN '2025-02-01' AND '2025-02-28' perderia as vendas do dia 28
       apos as 00:00:00.

   (b) LEFT JOIN com produtos_filial, nao INNER JOIN.
       Motivo: 13 vendas referenciam produtos sem cadastro (P21..P28). Com
       INNER JOIN elas sumiriam do relatorio e o total nao bateria com o
       faturamento do cliente. Com LEFT JOIN elas aparecem sinalizadas.
       Relatorio que esconde problema e pior que relatorio com problema.
   ----------------------------------------------------------------------------- */
SELECT
    v.produto_id                                          AS produto_id,
    COALESCE(pf.descricao, '*** SEM CADASTRO ***')        AS descricao,
    v.filial_id                                           AS filial,
    COUNT(*)                                              AS qtde_notas,
    SUM(v.qtde_vendida)                                   AS qtde_total_vendida,
    ROUND(SUM(v.qtde_vendida * v.valor_unitario), 2)      AS valor_total_reais,
    ROUND(AVG(v.valor_unitario), 2)                       AS preco_medio_unitario
FROM public.venda v
LEFT JOIN public.produtos_filial pf
       ON pf.filial_id = v.filial_id
      AND pf.idproduto = v.produto_id
WHERE v.data_emissao >= DATE '2025-02-01'
  AND v.data_emissao <  DATE '2025-03-01'
GROUP BY v.produto_id, pf.descricao, v.filial_id
ORDER BY valor_total_reais DESC;


/* -----------------------------------------------------------------------------
   2.1.b - MESMO RESULTADO COM TOTAL GERAL
   Versao para levar a reuniao: o cliente confere o total antes de descer ao
   detalhe. GROUPING SETS gera o analitico e o consolidado em uma unica
   varredura da tabela.
   ----------------------------------------------------------------------------- */
SELECT
    COALESCE(v.produto_id, '>>> TOTAL FEVEREIRO/2025')  AS produto_id,
    SUM(v.qtde_vendida)                                 AS qtde_total_vendida,
    ROUND(SUM(v.qtde_vendida * v.valor_unitario), 2)    AS valor_total_reais
FROM public.venda v
WHERE v.data_emissao >= DATE '2025-02-01'
  AND v.data_emissao <  DATE '2025-03-01'
GROUP BY GROUPING SETS ((v.produto_id), ())
ORDER BY GROUPING(v.produto_id), valor_total_reais DESC;


/* -----------------------------------------------------------------------------
   2.2 - PRODUTOS COM REQUISICAO PENDENTE
   "Produtos que foram requisitados, mas nao recebidos."

   A expressao "nao recebidos" tem tres leituras possiveis, e elas dao numeros
   diferentes. Em vez de escolher uma em silencio, a consulta classifica cada
   pendencia em uma categoria - assim o cliente enxerga a diferenca e decide
   qual regra vale. As tres situacoes reais da base:

     SEM ENTRADA VINCULADA  - existe pedido, nao existe NF para a ordem_compra
     ORDEM DE COMPRA ZERADA - ordem_compra = 0, ou seja, nao ha como vincular
     PARCIALMENTE RECEBIDO  - existe NF, mas qtde_recebida < qtde_pedida

   NOT EXISTS foi preferido a NOT IN: se ordem_compra tivesse um unico NULL,
   NOT IN devolveria conjunto vazio silenciosamente. NOT EXISTS e imune a isso.
   ----------------------------------------------------------------------------- */
WITH recebido_por_ordem AS (
    SELECT
        em.ordem_compra,
        SUM(em.qtde_recebida) AS qtde_recebida_total,
        COUNT(*)              AS qtde_notas
    FROM public.entradas_mercadoria em
    GROUP BY em.ordem_compra
)
SELECT
    pc.pedido_id,
    pc.ordem_compra,
    pc.produto_id,
    pc.descricao_produto,
    TO_CHAR(pc.data_pedido, 'DD/MM/YYYY')                  AS data_pedido,
    pc.qtde_pedida,
    COALESCE(r.qtde_recebida_total, 0)                     AS qtde_recebida,
    pc.qtde_pedida - COALESCE(r.qtde_recebida_total, 0)    AS saldo_pendente,
    CASE
        WHEN pc.ordem_compra = 0
            THEN 'ORDEM DE COMPRA ZERADA'
        WHEN r.ordem_compra IS NULL
            THEN 'SEM ENTRADA VINCULADA'
        ELSE 'PARCIALMENTE RECEBIDO'
    END                                                    AS situacao
FROM public.pedido_compra pc
LEFT JOIN recebido_por_ordem r
       ON r.ordem_compra = pc.ordem_compra
      AND pc.ordem_compra <> 0          -- ordem 0 nunca vincula
WHERE pc.ordem_compra = 0
   OR r.ordem_compra IS NULL
   OR COALESCE(r.qtde_recebida_total, 0) < pc.qtde_pedida
ORDER BY situacao, pc.pedido_id;


/* -----------------------------------------------------------------------------
   2.2.b - RESUMO DAS PENDENCIAS
   Uma linha por categoria. E o slide de abertura da reuniao de validacao:
   o cliente ve o tamanho do problema antes de discutir caso a caso.
   ----------------------------------------------------------------------------- */
WITH recebido_por_ordem AS (
    SELECT ordem_compra, SUM(qtde_recebida) AS qtde_recebida_total
    FROM public.entradas_mercadoria
    GROUP BY ordem_compra
),
classificado AS (
    SELECT
        pc.pedido_id,
        pc.qtde_pedida - COALESCE(r.qtde_recebida_total, 0) AS saldo,
        CASE
            WHEN pc.ordem_compra = 0     THEN 'ORDEM DE COMPRA ZERADA'
            WHEN r.ordem_compra IS NULL  THEN 'SEM ENTRADA VINCULADA'
            ELSE 'PARCIALMENTE RECEBIDO'
        END AS situacao
    FROM public.pedido_compra pc
    LEFT JOIN recebido_por_ordem r
           ON r.ordem_compra = pc.ordem_compra
          AND pc.ordem_compra <> 0
    WHERE pc.ordem_compra = 0
       OR r.ordem_compra IS NULL
       OR COALESCE(r.qtde_recebida_total, 0) < pc.qtde_pedida
)
SELECT
    situacao,
    COUNT(*)     AS qtde_pedidos,
    SUM(saldo)   AS saldo_total_pendente
FROM classificado
GROUP BY situacao
ORDER BY qtde_pedidos DESC;
