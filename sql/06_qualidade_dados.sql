/* =============================================================================
   Systock - Case Tecnico de Integracao de Dados
   Arquivo 06 - CAMADA DE QUALIDADE DE DADOS (schema qa)

   Cada view isola UMA inconsistencia encontrada na base. O objetivo e que o
   problema deixe de ser uma anotacao em documento e vire um objeto do banco,
   consultavel a qualquer momento por qualquer pessoa da equipe.

   Vantagem pratica na implantacao: depois do saneamento, basta rodar
   qa.vw_painel_qualidade de novo. Se todas as contagens zerarem, a correcao
   esta comprovada por consulta, nao por afirmacao.

   Execucao:
       psql -U postgres -d systock -f sql/06_qualidade_dados.sql
   ============================================================================= */

CREATE SCHEMA IF NOT EXISTS qa;


/* -----------------------------------------------------------------------------
   QA-01 - VENDAS DE PRODUTO SEM CADASTRO
   13 vendas referenciam P21..P28, que nao existem em produtos_filial.
   Impacto: relatorio de margem impossivel (sem preco de compra) e estoque
   que nunca baixa.
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW qa.vw_venda_produto_sem_cadastro AS
SELECT
    v.venda_id,
    v.filial_id,
    v.produto_id,
    TO_CHAR(v.data_emissao, 'DD/MM/YYYY')              AS data_emissao,
    v.qtde_vendida,
    v.valor_unitario,
    ROUND(v.qtde_vendida * v.valor_unitario, 2)        AS valor_total
FROM public.venda v
WHERE NOT EXISTS (
    SELECT 1 FROM public.produtos_filial pf
     WHERE pf.filial_id = v.filial_id
       AND pf.idproduto = v.produto_id
);


/* -----------------------------------------------------------------------------
   QA-02 - VENDAS EM FILIAL SEM CADASTRO DE PRODUTOS
   As filiais 2 e 3 aparecem em venda, mas produtos_filial so tem a filial 1.
   Impacto: ou faltou carregar o cadastro dessas filiais, ou as vendas estao
   com filial errada. So o cliente sabe qual das duas.
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW qa.vw_venda_filial_sem_cadastro AS
SELECT
    v.filial_id,
    COUNT(*)                                            AS qtde_vendas,
    ROUND(SUM(v.qtde_vendida * v.valor_unitario), 2)    AS valor_total
FROM public.venda v
WHERE NOT EXISTS (
    SELECT 1 FROM public.produtos_filial pf WHERE pf.filial_id = v.filial_id
)
GROUP BY v.filial_id;


/* -----------------------------------------------------------------------------
   QA-03 - QUANTIDADE FRACIONARIA EM UNIDADE INTEIRA
   5 vendas com quantidade fracionaria (38.60, 20.04, 2.86, 37.11, 3.11) em
   unidade de medida 'UN'.
   Impacto: ou a unidade esta errada (deveria ser KG/L), ou houve erro de
   digitacao com deslocamento de virgula. Nao se arredonda por conta propria:
   qualquer das duas hipoteses muda o faturamento.
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW qa.vw_venda_qtde_fracionaria AS
SELECT
    v.venda_id,
    v.produto_id,
    TO_CHAR(v.data_emissao, 'DD/MM/YYYY')  AS data_emissao,
    v.qtde_vendida,
    v.unidade_medida,
    ROUND(v.qtde_vendida * v.valor_unitario, 2) AS valor_total
FROM public.venda v
WHERE v.unidade_medida = 'UN'
  AND v.qtde_vendida <> trunc(v.qtde_vendida);


/* -----------------------------------------------------------------------------
   QA-04 - PEDIDOS COM ORDEM DE COMPRA ZERADA
   11 pedidos com ordem_compra = 0. Como e o campo de ligacao com
   entradas_mercadoria, esses pedidos nunca poderao ser conciliados com a NF.
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW qa.vw_pedido_sem_ordem_compra AS
SELECT
    pc.pedido_id,
    pc.produto_id,
    pc.item,
    TO_CHAR(pc.data_pedido, 'DD/MM/YYYY')  AS data_pedido,
    pc.qtde_pedida,
    pc.fornecedor_id
FROM public.pedido_compra pc
WHERE pc.ordem_compra = 0;


/* -----------------------------------------------------------------------------
   QA-05 - PEDIDOS DUPLICADOS
   Os pedidos 21 a 29 repetem produto, data e preco dos pedidos 12 a 20.
   Nao violam a PK porque o pedido_id e diferente, o que torna a duplicidade
   invisivel para o banco - por isso precisa de uma view.

   Evidencia adicional: na planilha original, as linhas 22 a 30 trazem um
   bloco de 11 colunas SEM CABECALHO a direita, com os dados corretos dos
   pedidos 12 a 20 (incluindo a coluna qtde_pendente, ausente do cabecalho
   oficial). Ou seja, e um erro de montagem da planilha, nao um pedido real.
   Ver data/csv/_anomalia_pedido_compra_colunas_sem_cabecalho.csv
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW qa.vw_pedido_duplicado AS
SELECT
    pc.pedido_id,
    pc.produto_id,
    TO_CHAR(pc.data_pedido, 'DD/MM/YYYY')  AS data_pedido,
    pc.ordem_compra,
    pc.qtde_pedida,
    pc.qtde_entregue,
    pc.preco_compra,
    COUNT(*) OVER (
        PARTITION BY pc.produto_id, pc.data_pedido, pc.preco_compra
    ) AS ocorrencias
FROM public.pedido_compra pc
WHERE EXISTS (
    SELECT 1
    FROM public.pedido_compra d
    WHERE d.produto_id   = pc.produto_id
      AND d.data_pedido  = pc.data_pedido
      AND d.preco_compra = pc.preco_compra
      AND d.pedido_id   <> pc.pedido_id
);


/* -----------------------------------------------------------------------------
   QA-06 - ENTREGA ANTERIOR AO PEDIDO
   20 registros com data_entrega < data_pedido. Impossivel no mundo real:
   entregar antes de pedir.
   Impacto direto no lead time de compras, indicador que costuma ser usado
   para negociar prazo com fornecedor.
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW qa.vw_pedido_data_invertida AS
SELECT
    pc.pedido_id,
    pc.produto_id,
    TO_CHAR(pc.data_pedido,  'DD/MM/YYYY')      AS data_pedido,
    TO_CHAR(pc.data_entrega, 'DD/MM/YYYY')      AS data_entrega,
    (pc.data_entrega - pc.data_pedido)          AS dias_diferenca
FROM public.pedido_compra pc
WHERE pc.data_entrega IS NOT NULL
  AND pc.data_pedido  IS NOT NULL
  AND pc.data_entrega < pc.data_pedido;


/* -----------------------------------------------------------------------------
   QA-07 - RECEBIDO MAIOR QUE PEDIDO
   6 ordens em que a NF traz quantidade superior a pedida.
   Impacto: pagamento de mercadoria nao solicitada e estoque inflado.
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW qa.vw_recebido_maior_que_pedido AS
SELECT
    pc.ordem_compra,
    pc.pedido_id,
    pc.produto_id,
    pc.qtde_pedida,
    SUM(em.qtde_recebida)                        AS qtde_recebida,
    SUM(em.qtde_recebida) - pc.qtde_pedida       AS excesso
FROM public.pedido_compra pc
JOIN public.entradas_mercadoria em
  ON em.ordem_compra = pc.ordem_compra
WHERE pc.ordem_compra <> 0
GROUP BY pc.ordem_compra, pc.pedido_id, pc.produto_id, pc.qtde_pedida
HAVING SUM(em.qtde_recebida) > pc.qtde_pedida;


/* -----------------------------------------------------------------------------
   QA-08 - DIVERGENCIA ENTRE QTDE_ENTREGUE E A NOTA FISCAL
   O campo pedido_compra.qtde_entregue nao bate com a soma das entradas em
   NENHUMA das 18 ordens vinculadas.
   Impacto: e a inconsistencia mais grave da base. Duas fontes para o mesmo
   numero, sempre discordantes. Precisa de definicao do cliente sobre qual e
   a oficial - a recomendacao tecnica e a NF, por ser documento fiscal.
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW qa.vw_divergencia_entregue_vs_nf AS
SELECT
    pc.ordem_compra,
    pc.pedido_id,
    pc.produto_id,
    pc.qtde_pedida,
    pc.qtde_entregue                                   AS qtde_entregue_pedido,
    SUM(em.qtde_recebida)                              AS qtde_recebida_nf,
    SUM(em.qtde_recebida) - pc.qtde_entregue           AS divergencia
FROM public.pedido_compra pc
JOIN public.entradas_mercadoria em
  ON em.ordem_compra = pc.ordem_compra
WHERE pc.ordem_compra <> 0
GROUP BY pc.ordem_compra, pc.pedido_id, pc.produto_id, pc.qtde_pedida, pc.qtde_entregue
HAVING SUM(em.qtde_recebida) <> pc.qtde_entregue;


/* -----------------------------------------------------------------------------
   QA-09 - MARGEM NEGATIVA NO CADASTRO
   4 produtos com preco_venda menor que preco_compra (P1, P8, P15, P18).
   Impacto: prejuizo embutido no cadastro. Ou os precos foram invertidos na
   carga, ou o cadastro esta desatualizado.
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW qa.vw_produto_margem_negativa AS
SELECT
    pf.filial_id,
    pf.idproduto,
    pf.descricao,
    pf.preco_compra,
    pf.preco_venda,
    pf.preco_unitario,
    ROUND(pf.preco_venda - pf.preco_compra, 2)  AS margem_absoluta,
    ROUND(100.0 * (pf.preco_venda - pf.preco_compra)
                / NULLIF(pf.preco_compra, 0), 2) AS margem_percentual
FROM public.produtos_filial pf
WHERE pf.preco_venda < pf.preco_compra;


/* -----------------------------------------------------------------------------
   QA-10 - PRECO DE VENDA DIVERGENTE DO CADASTRO
   O valor_unitario praticado em venda nao corresponde ao preco_venda do
   cadastro. Some-se a isso a ambiguidade das tres colunas de preco em
   produtos_filial (unitario, compra, venda), sem definicao de qual e a
   oficial para faturamento.
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW qa.vw_venda_preco_divergente AS
SELECT
    v.venda_id,
    v.produto_id,
    TO_CHAR(v.data_emissao, 'DD/MM/YYYY')            AS data_emissao,
    v.valor_unitario                                 AS preco_praticado,
    pf.preco_venda                                   AS preco_cadastro,
    pf.preco_unitario                                AS preco_unitario_cadastro,
    ROUND(v.valor_unitario - pf.preco_venda, 2)      AS diferenca
FROM public.venda v
JOIN public.produtos_filial pf
  ON pf.filial_id = v.filial_id
 AND pf.idproduto = v.produto_id
WHERE v.valor_unitario <> pf.preco_venda;


/* -----------------------------------------------------------------------------
   QA-11 - FORNECEDORES SEM NENHUM PRODUTO
   Cadastro ocioso. Nao e erro, mas merece confirmacao: pode indicar produto
   que faltou carregar.
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW qa.vw_fornecedor_sem_produto AS
SELECT f.idfornecedor, f.fornecedor_num, f.razao_social
FROM public.fornecedor f
WHERE NOT EXISTS (
    SELECT 1 FROM public.produtos_filial pf WHERE pf.idfornecedor = f.idfornecedor
);


/* -----------------------------------------------------------------------------
   QA-12 - VENDAS FORA DO PERIODO DE FEVEREIRO/2025
   O escopo de validacao e fevereiro, mas a base tem janeiro e marco.
   Serve para delimitar com o cliente o que entra na conferencia.
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW qa.vw_venda_por_competencia AS
SELECT
    TO_CHAR(v.data_emissao, 'MM/YYYY')                AS competencia,
    COUNT(*)                                          AS qtde_vendas,
    SUM(v.qtde_vendida)                               AS qtde_total,
    ROUND(SUM(v.qtde_vendida * v.valor_unitario), 2)  AS valor_total,
    CASE WHEN date_trunc('month', v.data_emissao) = DATE '2025-02-01'
         THEN 'ESCOPO DE VALIDACAO' ELSE 'fora do escopo' END AS situacao
FROM public.venda v
GROUP BY
    TO_CHAR(v.data_emissao, 'MM/YYYY'),
    CASE WHEN date_trunc('month', v.data_emissao) = DATE '2025-02-01'
         THEN 'ESCOPO DE VALIDACAO' ELSE 'fora do escopo' END
ORDER BY 1;


/* =============================================================================
   PAINEL CONSOLIDADO
   Uma linha por verificacao. E o primeiro slide da reuniao de validacao e,
   depois do saneamento, a prova de que tudo foi resolvido.
   ============================================================================= */
CREATE OR REPLACE VIEW qa.vw_painel_qualidade AS
SELECT *
FROM (
    SELECT 'QA-01' AS cod, 'Vendas de produto sem cadastro' AS verificacao, 'ALTA' AS severidade, (SELECT COUNT(*) FROM qa.vw_venda_produto_sem_cadastro) AS ocorrencias
    UNION ALL SELECT 'QA-02', 'Vendas em filial sem cadastro',         'ALTA',   (SELECT COUNT(*) FROM qa.vw_venda_filial_sem_cadastro)
    UNION ALL SELECT 'QA-03', 'Qtde fracionaria em unidade UN',        'MEDIA',  (SELECT COUNT(*) FROM qa.vw_venda_qtde_fracionaria)
    UNION ALL SELECT 'QA-04', 'Pedido com ordem de compra zerada',     'ALTA',   (SELECT COUNT(*) FROM qa.vw_pedido_sem_ordem_compra)
    UNION ALL SELECT 'QA-05', 'Pedidos duplicados',                    'ALTA',   (SELECT COUNT(*) FROM qa.vw_pedido_duplicado)
    UNION ALL SELECT 'QA-06', 'Entrega anterior ao pedido',            'MEDIA',  (SELECT COUNT(*) FROM qa.vw_pedido_data_invertida)
    UNION ALL SELECT 'QA-07', 'Recebido maior que pedido',             'ALTA',   (SELECT COUNT(*) FROM qa.vw_recebido_maior_que_pedido)
    UNION ALL SELECT 'QA-08', 'Divergencia qtde_entregue x NF',        'CRITICA',(SELECT COUNT(*) FROM qa.vw_divergencia_entregue_vs_nf)
    UNION ALL SELECT 'QA-09', 'Produto com margem negativa',           'ALTA',   (SELECT COUNT(*) FROM qa.vw_produto_margem_negativa)
    UNION ALL SELECT 'QA-10', 'Preco de venda divergente do cadastro', 'MEDIA',  (SELECT COUNT(*) FROM qa.vw_venda_preco_divergente)
    UNION ALL SELECT 'QA-11', 'Fornecedor sem produto vinculado',      'BAIXA',  (SELECT COUNT(*) FROM qa.vw_fornecedor_sem_produto)
) p
ORDER BY CASE p.severidade WHEN 'CRITICA' THEN 1 WHEN 'ALTA' THEN 2
                           WHEN 'MEDIA'   THEN 3 ELSE 4 END, p.cod;


-- Execute para ver o panorama:
SELECT * FROM qa.vw_painel_qualidade;
