/* =============================================================================
   Systock - Case Tecnico de Integracao de Dados
   Arquivo 07 - PARTE 4: CONSULTAS DE APOIO A REUNIAO DE VALIDACAO

   Periodo em validacao: FEVEREIRO/2025

   Estas sao as consultas que ficam abertas na tela durante a reuniao, na
   ordem em que sao usadas. O roteiro narrado esta em
   docs/03_roteiro_validacao_cliente.md.

   Criterio de montagem: o cliente nao le SQL. Toda consulta aqui tem numeros
   arredondados, datas em DD/MM/YYYY e rotulos em linguagem de negocio.
   ============================================================================= */


/* =============================================================================
   BLOCO 1 - ABERTURA: "OS NUMEROS BATEM?"
   Comeca pelo total. Se o cliente concordar com o numero de cima, o resto da
   reuniao e detalhamento. Se discordar, o problema esta na origem e nao
   adianta descer ao detalhe.
   ============================================================================= */

-- 1.1 Cartao de conferencia do periodo
SELECT
    'Fevereiro/2025'                                       AS periodo,
    COUNT(*)                                               AS qtde_lancamentos,
    COUNT(DISTINCT v.produto_id)                           AS produtos_distintos,
    COUNT(DISTINCT v.filial_id)                            AS filiais,
    SUM(v.qtde_vendida)                                    AS qtde_total,
    TO_CHAR(SUM(v.qtde_vendida * v.valor_unitario),
            'FML999G999G990D00')                           AS faturamento_total,
    TO_CHAR(MIN(v.data_emissao), 'DD/MM/YYYY')             AS primeira_venda,
    TO_CHAR(MAX(v.data_emissao), 'DD/MM/YYYY')             AS ultima_venda
FROM public.venda v
WHERE v.data_emissao >= DATE '2025-02-01'
  AND v.data_emissao <  DATE '2025-03-01';


-- 1.2 Delimitacao de escopo
-- Mostra que a base tem janeiro e marco alem de fevereiro. Alinhar o recorte
-- antes de comparar qualquer numero evita a discussao mais comum de reuniao
-- de validacao: dois lados certos falando de periodos diferentes.
SELECT * FROM qa.vw_venda_por_competencia;


-- 1.3 Faturamento diario
-- Serve para o cliente reconhecer o proprio movimento. Dia sem venda no meio
-- da semana costuma ser falha de carga; o cliente identifica na hora.
SELECT
    TO_CHAR(v.data_emissao, 'DD/MM/YYYY')                       AS dia,
    TO_CHAR(v.data_emissao, 'TMDy')                             AS dia_semana,
    COUNT(*)                                                    AS lancamentos,
    TO_CHAR(SUM(v.qtde_vendida * v.valor_unitario),
            'FML999G999G990D00')                                AS faturamento
FROM public.venda v
WHERE v.data_emissao >= DATE '2025-02-01'
  AND v.data_emissao <  DATE '2025-03-01'
GROUP BY v.data_emissao
ORDER BY v.data_emissao;


/* =============================================================================
   BLOCO 2 - CONCILIACAO ENTRE MODULOS
   Compras, recebimento e estoque precisam contar a mesma historia.
   ============================================================================= */

-- 2.1 Conciliacao pedido x nota fiscal, ordem a ordem
-- Esta e a consulta central da reuniao. Cada linha e um pedido e mostra as
-- tres visoes do mesmo fato: o que foi pedido, o que o pedido diz ter sido
-- entregue, e o que a NF registra.
SELECT
    pc.ordem_compra                                     AS "Ordem",
    CONCAT_WS(' - ', pc.produto_id, pc.descricao_produto) AS "Produto",
    TO_CHAR(pc.data_pedido, 'DD/MM/YYYY')               AS "Data Pedido",
    pc.qtde_pedida                                      AS "Pedido",
    pc.qtde_entregue                                    AS "Entregue (sistema)",
    COALESCE(SUM(em.qtde_recebida), 0)                  AS "Recebido (NF)",
    COALESCE(SUM(em.qtde_recebida), 0) - pc.qtde_entregue AS "Divergencia",
    CASE
        WHEN pc.ordem_compra = 0                              THEN 'SEM VINCULO'
        WHEN COALESCE(SUM(em.qtde_recebida), 0) = 0           THEN 'NAO RECEBIDO'
        WHEN COALESCE(SUM(em.qtde_recebida), 0) > pc.qtde_pedida THEN 'RECEBIDO A MAIOR'
        WHEN COALESCE(SUM(em.qtde_recebida), 0) < pc.qtde_pedida THEN 'PARCIAL'
        ELSE 'COMPLETO'
    END                                                 AS "Situacao"
FROM public.pedido_compra pc
LEFT JOIN public.entradas_mercadoria em
       ON em.ordem_compra = pc.ordem_compra
      AND pc.ordem_compra <> 0
WHERE pc.data_pedido >= DATE '2025-02-01'
  AND pc.data_pedido <  DATE '2025-03-01'
GROUP BY pc.ordem_compra, pc.produto_id, pc.descricao_produto,
         pc.data_pedido, pc.qtde_pedida, pc.qtde_entregue
ORDER BY ABS(COALESCE(SUM(em.qtde_recebida), 0) - pc.qtde_entregue) DESC;


-- 2.2 Movimentacao completa por produto
-- Entrou, saiu, e o estoque atual e compativel com isso?
-- Este e o teste de razoabilidade mais forte: estoque negativo ou muito acima
-- do movimento indica erro de carga ou saldo inicial nao informado.
SELECT
    CONCAT_WS(' - ', pf.idproduto, pf.descricao)   AS "Produto",
    pf.estoque                                     AS "Estoque Atual",
    COALESCE(ent.recebido, 0)                      AS "Entradas Fev",
    COALESCE(sai.vendido, 0)                       AS "Saidas Fev",
    COALESCE(ent.recebido, 0) - COALESCE(sai.vendido, 0) AS "Saldo do Mes",
    CASE
        WHEN pf.estoque < 0                                     THEN 'ESTOQUE NEGATIVO'
        WHEN COALESCE(sai.vendido, 0) > pf.estoque
                                 + COALESCE(ent.recebido, 0)    THEN 'SAIDA MAIOR QUE DISPONIVEL'
        ELSE 'ok'
    END                                            AS "Alerta"
FROM public.produtos_filial pf
LEFT JOIN LATERAL (
    SELECT SUM(em.qtde_recebida) AS recebido
    FROM public.entradas_mercadoria em
    WHERE em.produto_id = pf.idproduto
      AND em.filial_id  = pf.filial_id
      AND em.data_entrada >= DATE '2025-02-01'
      AND em.data_entrada <  DATE '2025-03-01'
) ent ON TRUE
LEFT JOIN LATERAL (
    SELECT SUM(v.qtde_vendida) AS vendido
    FROM public.venda v
    WHERE v.produto_id = pf.idproduto
      AND v.filial_id  = pf.filial_id
      AND v.data_emissao >= DATE '2025-02-01'
      AND v.data_emissao <  DATE '2025-03-01'
) sai ON TRUE
ORDER BY COALESCE(sai.vendido, 0) DESC;


/* =============================================================================
   BLOCO 3 - EXCECOES PARA DECISAO DO CLIENTE
   Cada consulta aqui termina em uma pergunta objetiva. O cliente nao precisa
   entender o problema tecnico: precisa responder sim ou nao.
   ============================================================================= */

-- 3.1 PERGUNTA: "Estes 8 produtos existem no seu cadastro?"
SELECT * FROM qa.vw_venda_produto_sem_cadastro ORDER BY produto_id;

-- 3.2 PERGUNTA: "As filiais 2 e 3 devem estar nesta base?"
SELECT * FROM qa.vw_venda_filial_sem_cadastro;

-- 3.3 PERGUNTA: "Estes itens sao vendidos por peso? A unidade esta correta?"
SELECT * FROM qa.vw_venda_qtde_fracionaria;

-- 3.4 PERGUNTA: "Estes 9 pedidos sao reais ou duplicacao de lancamento?"
SELECT * FROM qa.vw_pedido_duplicado ORDER BY produto_id, pedido_id;

-- 3.5 PERGUNTA: "Quando pedido e NF divergem, qual numero vale?"
--               (recomendacao tecnica: a NF, por ser documento fiscal)
SELECT * FROM qa.vw_divergencia_entregue_vs_nf ORDER BY ABS(divergencia) DESC;

-- 3.6 PERGUNTA: "Estes 4 produtos sao vendidos abaixo do custo de proposito?"
SELECT * FROM qa.vw_produto_margem_negativa;

-- 3.7 PERGUNTA: "Das tres colunas de preco, qual e a oficial para faturamento?"
SELECT * FROM qa.vw_venda_preco_divergente ORDER BY ABS(diferenca) DESC LIMIT 10;

-- 3.8 PERGUNTA: "Estas entregas anteriores ao pedido sao erro de digitacao?"
SELECT * FROM qa.vw_pedido_data_invertida ORDER BY dias_diferenca;


/* =============================================================================
   BLOCO 4 - PROVAS DE EXATIDAO
   Tecnicas para sustentar que o numero apresentado esta correto.
   ============================================================================= */

-- 4.1 Rastreabilidade origem -> destino
-- Prova que nada se perdeu nem foi inventado entre a planilha e o banco.
-- E o argumento mais forte de confiabilidade: o cliente ve a contagem bater.
SELECT 'venda'               AS tabela,
       (SELECT COUNT(*) FROM stg.venda)               AS origem_planilha,
       (SELECT COUNT(*) FROM public.venda)            AS carregado_banco,
       (SELECT COUNT(*) FROM stg.venda)
     - (SELECT COUNT(*) FROM public.venda)            AS diferenca
UNION ALL SELECT 'pedido_compra',
       (SELECT COUNT(*) FROM stg.pedido_compra),
       (SELECT COUNT(*) FROM public.pedido_compra),
       (SELECT COUNT(*) FROM stg.pedido_compra) - (SELECT COUNT(*) FROM public.pedido_compra)
UNION ALL SELECT 'entradas_mercadoria',
       (SELECT COUNT(*) FROM stg.entradas_mercadoria),
       (SELECT COUNT(*) FROM public.entradas_mercadoria),
       (SELECT COUNT(*) FROM stg.entradas_mercadoria) - (SELECT COUNT(*) FROM public.entradas_mercadoria)
UNION ALL SELECT 'produtos_filial',
       (SELECT COUNT(*) FROM stg.produtos_filial),
       (SELECT COUNT(*) FROM public.produtos_filial),
       (SELECT COUNT(*) FROM stg.produtos_filial) - (SELECT COUNT(*) FROM public.produtos_filial)
UNION ALL SELECT 'fornecedor',
       (SELECT COUNT(*) FROM stg.fornecedor),
       (SELECT COUNT(*) FROM public.fornecedor),
       (SELECT COUNT(*) FROM stg.fornecedor) - (SELECT COUNT(*) FROM public.fornecedor);


-- 4.2 Checksum financeiro origem x destino
-- Contagem igual nao garante valor igual: uma virgula deslocada na conversao
-- mantem a quantidade de linhas e altera o faturamento. Somar o valor nos
-- dois lados fecha essa brecha.
SELECT
    ROUND((SELECT SUM(qtde_vendida::numeric * valor_unitario::numeric)
           FROM stg.venda), 2)                       AS total_origem,
    ROUND((SELECT SUM(qtde_vendida * valor_unitario)
           FROM public.venda), 2)                    AS total_destino,
    ROUND((SELECT SUM(qtde_vendida::numeric * valor_unitario::numeric) FROM stg.venda)
        - (SELECT SUM(qtde_vendida * valor_unitario) FROM public.venda), 2) AS diferenca;


-- 4.3 Teste de unicidade da chave de venda
-- A PK tem 6 colunas, o que a torna permissiva. Esta consulta verifica se o
-- mesmo documento fiscal entrou mais de uma vez com horarios diferentes -
-- duplicidade que a PK atual nao impede.
SELECT
    v.filial_id, v.venda_id, v.produto_id, v.item,
    COUNT(*)                          AS ocorrencias,
    COUNT(DISTINCT v.horariomov)      AS horarios_distintos
FROM public.venda v
GROUP BY v.filial_id, v.venda_id, v.produto_id, v.item
HAVING COUNT(*) > 1;


-- 4.4 Painel final de qualidade
-- Fecha a reuniao. Depois do saneamento aprovado, roda de novo: toda linha
-- deve zerar. E a evidencia objetiva de que o combinado foi cumprido.
SELECT * FROM qa.vw_painel_qualidade;
