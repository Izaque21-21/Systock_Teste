/* =============================================================================
   Systock - Case Tecnico de Integracao de Dados
   Arquivo 04 - PARTE 3: TRANSFORMACOES DE DADOS (itens 1 a 3)

   Requisitos combinados em uma unica consulta:
     1. Concatenar produto_id e descricao_produto (onde houver)
     2. Data no formato DD/MM/YYYY
     3. Somente produtos requisitados mais de 10 vezes no periodo

   Formato-alvo do enunciado:
     | Produto              | Qtde Requisitada | Data Solicitacao |
     | 12345 - Detergente   | 15               | 01/01/2025       |

   O item 4 (trigger) esta em 05_parte3_trigger_fornecedor.sql.
   ============================================================================= */


/* -----------------------------------------------------------------------------
   NOTA SOBRE A AMBIGUIDADE DO REQUISITO 3

   "produtos requisitados mais de 10 vezes" admite duas leituras:

     (A) SOMA das quantidades pedidas > 10
     (B) NUMERO DE OCORRENCIAS de pedido > 10

   O exemplo do enunciado mostra "Qtde Requisitada = 15" para um unico produto
   com uma unica data de solicitacao. Se fossem 15 ocorrencias, a coluna
   "Data Solicitacao" nao poderia trazer um valor unico. Isso indica a
   leitura (A), que e a adotada na consulta principal.

   A leitura (B) fica entregue logo abaixo como 3.b. Na base atual ela retorna
   VAZIO - nenhum produto foi pedido mais de 10 vezes (o maximo e 2
   ocorrencias, justamente as duplicatas). Esse resultado vazio e por si so um
   argumento a favor da leitura (A), e o tipo de ponto que se leva para a
   reuniao em vez de decidir sozinho.
   ----------------------------------------------------------------------------- */


/* -----------------------------------------------------------------------------
   3.1 - PEDIDOS DE COMPRA (consulta principal)

   Sobre a concatenacao: o enunciado pede "onde houver" descricao. O operador
   || em PostgreSQL retorna NULL se qualquer operando for NULL - ou seja,
   'P12' || ' - ' || NULL resulta em NULL e o produto sumiria do relatorio.
   Por isso a montagem usa CONCAT_WS, que ignora NULL, dentro de um CASE que
   devolve so o codigo quando nao ha descricao.
   ----------------------------------------------------------------------------- */
SELECT
    CASE
        WHEN NULLIF(trim(pc.descricao_produto), '') IS NULL
            THEN pc.produto_id
        ELSE CONCAT_WS(' - ', pc.produto_id, trim(pc.descricao_produto))
    END                                          AS "Produto",
    SUM(pc.qtde_pedida)                          AS "Qtde Requisitada",
    TO_CHAR(MIN(pc.data_pedido), 'DD/MM/YYYY')   AS "Data Solicitacao",
    COUNT(*)                                     AS "Qtde Solicitacoes",
    TO_CHAR(MAX(pc.data_pedido), 'DD/MM/YYYY')   AS "Ultima Solicitacao"
FROM public.pedido_compra pc
WHERE pc.data_pedido >= DATE '2025-01-01'
  AND pc.data_pedido <  DATE '2025-03-01'
GROUP BY
    CASE
        WHEN NULLIF(trim(pc.descricao_produto), '') IS NULL
            THEN pc.produto_id
        ELSE CONCAT_WS(' - ', pc.produto_id, trim(pc.descricao_produto))
    END
HAVING SUM(pc.qtde_pedida) > 10
ORDER BY "Qtde Requisitada" DESC;


/* -----------------------------------------------------------------------------
   3.1.b - MESMA CONSULTA SOB A LEITURA (B): mais de 10 OCORRENCIAS
   Retorna vazio na base atual. Mantida no entregavel como evidencia de que a
   alternativa foi testada, e nao ignorada.
   ----------------------------------------------------------------------------- */
SELECT
    CONCAT_WS(' - ', pc.produto_id, NULLIF(trim(pc.descricao_produto), '')) AS "Produto",
    SUM(pc.qtde_pedida)                        AS "Qtde Requisitada",
    COUNT(*)                                   AS "Qtde Solicitacoes",
    TO_CHAR(MIN(pc.data_pedido), 'DD/MM/YYYY') AS "Data Solicitacao"
FROM public.pedido_compra pc
WHERE pc.data_pedido >= DATE '2025-01-01'
  AND pc.data_pedido <  DATE '2025-03-01'
GROUP BY 1
HAVING COUNT(*) > 10
ORDER BY 2 DESC;


/* -----------------------------------------------------------------------------
   3.2 - VENDAS COM AS MESMAS TRANSFORMACOES
   Aqui a descricao nao esta na tabela de venda: vem de produtos_filial via
   LEFT JOIN. O "onde houver" do enunciado ganha peso real, porque 8 produtos
   vendidos (P21..P28) nao tem cadastro e portanto nao tem descricao.
   ----------------------------------------------------------------------------- */
SELECT
    CASE
        WHEN NULLIF(trim(pf.descricao), '') IS NULL
            THEN v.produto_id
        ELSE CONCAT_WS(' - ', v.produto_id, trim(pf.descricao))
    END                                            AS "Produto",
    SUM(v.qtde_vendida)                            AS "Qtde Requisitada",
    TO_CHAR(MIN(v.data_emissao), 'DD/MM/YYYY')     AS "Data Solicitacao",
    ROUND(SUM(v.qtde_vendida * v.valor_unitario), 2) AS "Valor Total (R$)",
    CASE WHEN pf.idproduto IS NULL
         THEN 'PRODUTO SEM CADASTRO' END           AS "Alerta"
FROM public.venda v
LEFT JOIN public.produtos_filial pf
       ON pf.filial_id = v.filial_id
      AND pf.idproduto = v.produto_id
WHERE v.data_emissao >= DATE '2025-01-01'
  AND v.data_emissao <  DATE '2025-03-01'
GROUP BY 1, pf.idproduto
HAVING SUM(v.qtde_vendida) > 10
ORDER BY 2 DESC;


/* -----------------------------------------------------------------------------
   3.3 - PRODUTOS: CADASTRO CONSOLIDADO COM O FORNECEDOR
   Fecha o ciclo das transformacoes ligando produto -> fornecedor pelas duas
   chaves (textual e numerica) e trazendo a movimentacao do periodo.
   ----------------------------------------------------------------------------- */
SELECT
    CONCAT_WS(' - ', pf.idproduto, NULLIF(trim(pf.descricao), ''))  AS "Produto",
    pf.filial_id                                                    AS "Filial",
    CONCAT_WS(' - ', f.idfornecedor, f.razao_social)                AS "Fornecedor",
    f.fornecedor_num                                                AS "Cod. Fornecedor (num)",
    pf.estoque                                                      AS "Estoque",
    TO_CHAR(pf.preco_compra, 'FM999G999G990D00')                    AS "Preco Compra",
    TO_CHAR(pf.preco_venda,  'FM999G999G990D00')                    AS "Preco Venda",
    COALESCE(ped.qtde_requisitada, 0)                               AS "Qtde Requisitada",
    TO_CHAR(ped.primeira_solicitacao, 'DD/MM/YYYY')                 AS "Data Solicitacao"
FROM public.produtos_filial pf
LEFT JOIN public.fornecedor f
       ON f.idfornecedor = pf.idfornecedor
LEFT JOIN LATERAL (
    SELECT SUM(pc.qtde_pedida) AS qtde_requisitada,
           MIN(pc.data_pedido) AS primeira_solicitacao
    FROM public.pedido_compra pc
    WHERE pc.produto_id = pf.idproduto
      AND pc.data_pedido >= DATE '2025-01-01'
      AND pc.data_pedido <  DATE '2025-03-01'
) ped ON TRUE
WHERE COALESCE(ped.qtde_requisitada, 0) > 10
ORDER BY ped.qtde_requisitada DESC;
