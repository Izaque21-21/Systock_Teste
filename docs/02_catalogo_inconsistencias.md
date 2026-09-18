# Catálogo de Inconsistências

> O enunciado informa: *"O teste contém erros intencionais, inseridos com o objetivo de avaliar a capacidade de análise, atenção aos detalhes."*

Este documento cataloga o que foi encontrado. São **32 inconsistências** em duas categorias: 21 na estrutura (DDL) e 11 nos dados.

Cada item de dados tem uma view correspondente no schema `qa`, o que permite reconferir o estado a qualquer momento — e comprovar o saneamento depois.

---

## Resumo

| Categoria | Qtd. | Severidade máxima |
|---|---|---|
| Erros fatais de DDL (impedem execução) | 4 | Bloqueante |
| Erros de grafia e nomenclatura | 6 | Alta |
| Problemas de modelagem | 11 | Média |
| Inconsistências de dados | 11 | Crítica |

---

# Parte A — Erros de estrutura (DDL)

## A.1 Erros fatais

O `CREATE TABLE` do enunciado **não executa**. Quatro pontos abortam a execução:

### [E-03] `entradas_mercadoria`: coluna `ordem_compra` não declarada

```sql
CONSTRAINT entradas_mercadoria_pkey PRIMARY KEY (ordem_compra, item, produto_id, nro_nfe)
```

```
ERROR: column "ordem_compra" named in key does not exist
```

A PK referencia uma coluna que não existe na tabela. Agravante: é justamente o campo que a observação do enunciado indica como ligação com `pedido_compra` — *"uma entrada de mercadoria é atrelada ao seu pedido de compra pelo campo ORDEM_COMPRA"*. O DDL torna impossível o relacionamento que o texto descreve.

A planilha confirma que a coluna existe (9 colunas, incluindo `ordem_compra`).

**Correção:** declarar `ordem_compra bigint NOT NULL`.

### [E-07] `produtos_filial`: vírgula ausente

```sql
    idfonecedor int4 NULL          -- ← falta a vírgula
    CONSTRAINT produtos_filial_pkey PRIMARY KEY (filial_id, idproduto)
```

```
ERROR: syntax error at or near "CONSTRAINT"
```

### [E-09] `produtos_filial`: PK referencia coluna inexistente

A coluna é declarada como `produto_id`, a PK referencia `idproduto`. A planilha usa `idproduto`.

**Correção:** renomear a coluna para `idproduto`, alinhando com a planilha e com a própria PK.

### [E-11] `fornecedor`: PK referencia `idproduto`

```sql
CONSTRAINT fornecedor_pkey PRIMARY KEY (idforncedor, idproduto)
```

A coluna `idproduto` não existe nesta tabela — e não deveria. Fornecedor não tem relação 1:1 com produto. Colocar `idproduto` na PK quebraria a 2ª Forma Normal: o mesmo fornecedor apareceria repetido para cada produto que fornece.

**Correção:** `PRIMARY KEY (idfornecedor)`.

---

## A.2 Erros de grafia e nomenclatura

| Cód. | Onde | No DDL | Correto | Consequência |
|---|---|---|---|---|
| E-05 | `produtos_filial` | `decricao` | `descricao` | Coluna não encontrada na carga |
| E-06 | `produtos_filial` | `idfonecedor` | `idfornecedor` | Idem |
| E-10 | `fornecedor` | `idforncedor` | `idfornecedor` | Idem |
| E-04 | `produtos_filial` | `produto_id` | `idproduto` | Divergência com a planilha |
| F-05 | Texto do enunciado | "vendas", "produtos" | `venda`, `produtos_filial` | Ambiguidade na comunicação |
| M-06 | `venda` | `pk_consumo` | `venda_pkey` | Constraint com nome de outra entidade |

Três erros de grafia em cinco tabelas indicam DDL escrito à mão sem validação contra a origem. Em implantação real, esse é o sintoma que motiva propor geração de DDL a partir do dicionário de dados.

---

## A.3 Erros de tipo

### [E-02] `fornecedor_id` numérico × `idfornecedor` textual — **o mais estrutural**

| Tabela | Coluna | Tipo declarado | Valores reais |
|---|---|---|---|
| `fornecedor` | `idforncedor` | `varchar(25)` | `'F1'` .. `'F20'` |
| `pedido_compra` | `fornecedor_id` | `int4` | `1` .. `20` |
| `produtos_filial` | `idfonecedor` | `int4` | `'F8'`, `'F9'`, `'F10'` |

Três declarações para a mesma entidade, duas incompatíveis entre si. `produtos_filial` é o pior caso: declarada `int4` recebendo texto.

```
ERROR: invalid input syntax for type integer: "F8"
```

**Correção:** `produtos_filial.idfornecedor` como `varchar(25)` + chave substituta numérica `fornecedor.fornecedor_num`. Detalhamento em `docs/01`, seção 4.4.

### [M-08] Identificadores em `float8`

`pedido_id`, `item` e `ordem_compra` declarados como ponto flutuante. Além de conceitualmente errado, `float8` não garante igualdade exata — o que é justamente o que uma chave precisa fazer. Um `JOIN ... ON ordem_compra = ordem_compra` pode falhar silenciosamente.

### [M-03] Quantidades e valores em `float8`

`float8` não representa decimais exatamente. Somas acumulam erro de arredondamento. Em base financeira isso vira divergência de centavos que ninguém consegue explicar ao cliente.

**Correção:** `numeric(14,3)` para quantidades, `numeric(12,4)` para valores.

### [M-01] Hora como `varchar(8)`

`horariomov varchar(8)` aceita `'99:99:99'` e ordena como texto. **Correção:** `time`.

### [M-05] `filial_id` com larguras diferentes

`int8` em `venda`, `int4` nas demais. Mismatch de tipo em JOIN pode impedir uso de índice.

### [M-02] `produto_id` com domínios diferentes

`varchar(25)` em venda, pedido e entradas; `varchar(255)` em `produtos_filial`.

---

## A.4 Problemas de modelagem

| Cód. | Problema | Impacto |
|---|---|---|
| F-01 | **Nenhuma FK em nenhuma das 5 tabelas** | Nada impede venda de produto inexistente. A base confirma: 13 vendas órfãs |
| F-02 | Nenhum CHECK | Quantidade e preço negativos entram sem resistência |
| F-03 | Nenhum índice além das PKs | Consultas filtram por `data_emissao` e `produto_id` sem suporte |
| F-04 | Nenhum COMMENT | Documentação no catálogo é o que sobrevive à troca de equipe |
| D-01 | `qtde_pendente` no DDL, ausente da planilha | Coluna sem origem definida |
| M-07 | PK de `venda` com 6 colunas incluindo data e hora | Mesma venda reprocessada com horário diferente duplica sem violar PK |
| M-09 | `produto_id DEFAULT '0'` | Mascara carga incompleta: entra com produto fantasma em vez de falhar |
| M-10 | `descricao_produto` duplicada em duas tabelas | Sem FK, as duas divergem livremente |
| M-11 | Valor monetário em `float8` em pedido, `numeric` em venda | Divergência de centavos entre módulos |
| M-12 | `filial_id NULL` sendo coluna de PK | Contraditório; PostgreSQL converte silenciosamente |
| M-13 | Três colunas de preço sem definição de qual é a oficial | Ambiguidade de negócio — pendência de validação |

---

# Parte B — Inconsistências de dados

Ordenadas por severidade. Cada uma tem view em `qa`.

---

## [QA-08] Divergência entre `qtde_entregue` e a nota fiscal — **CRÍTICA**

**18 ocorrências — todas as ordens vinculadas.**

`pedido_compra.qtde_entregue` não bate com a soma de `entradas_mercadoria.qtde_recebida` em **nenhuma** das 18 ordens.

| Ordem | Produto | Pedido | Entregue (sistema) | Recebido (NF) | Divergência |
|---|---|---|---|---|---|
| 1 | P1 | 96 | 10 | 77 | +67 |
| 2 | P2 | 14 | 7 | 64 | +57 |
| 3 | P3 | 12 | 2 | 88 | +86 |
| 13 | P13 | 99 | 91 | 7 | −84 |
| … | | | | | |

Duas fontes para o mesmo número, sempre discordantes. Não é ruído: é 100% de divergência, o que sugere que os dois campos foram populados por processos independentes que nunca se falaram.

**Impacto:** estoque, custo médio e contas a pagar ficam sem número confiável.

**Recomendação técnica:** adotar a NF como fonte oficial, por ser documento fiscal. Decisão precisa vir do cliente.

`qa.vw_divergencia_entregue_vs_nf`

---

## [QA-05] Pedidos duplicados — **ALTA**

**18 registros envolvidos (9 pares).**

Os pedidos 21 a 29 repetem produto, data e preço dos pedidos 12 a 20:

| Original | Duplicata | Produto | Data | Qtde original | Qtde duplicata |
|---|---|---|---|---|---|
| 12 | 21 | P12 | 25/02/2025 | 91 | 12 |
| 13 | 22 | P13 | 23/02/2025 | 99 | 4 |
| 14 | 23 | P14 | 21/01/2025 | 96 | 6 |
| … | | | | | |

Não violam a PK porque o `pedido_id` é diferente — a duplicidade é invisível para o banco.

**Evidência da origem:** na planilha, as linhas 22 a 30 trazem um bloco de 11 colunas **sem cabeçalho** à direita, contendo os dados corretos dos pedidos 12 a 20 — incluindo `qtde_pendente`, coluna ausente do cabeçalho oficial. É erro de montagem da planilha, não pedido real.

Bloco preservado em `data/csv/_anomalia_pedido_compra_colunas_sem_cabecalho.csv`.

**Impacto:** duplicação de compromisso financeiro e inflação artificial da demanda.

`qa.vw_pedido_duplicado`

---

## [QA-01] Vendas de produto sem cadastro — **ALTA**

**13 ocorrências.** Produtos P21 a P28 aparecem em `venda` mas não existem em `produtos_filial`, que só cadastra P1 a P20.

**Impacto:** margem não calculável (sem preço de compra), estoque que nunca baixa, relatório por categoria incompleto.

`qa.vw_venda_produto_sem_cadastro`

---

## [QA-04] Pedidos com ordem de compra zerada — **ALTA**

**11 ocorrências** (pedidos 19 a 29). Como `ordem_compra` é o campo de ligação com `entradas_mercadoria`, esses pedidos nunca poderão ser conciliados com a NF.

Correlação relevante: 9 dos 11 são também as duplicatas do QA-05. Reforça a hipótese de erro na montagem da planilha.

`qa.vw_pedido_sem_ordem_compra`

---

## [QA-07] Recebido maior que pedido — **ALTA**

**7 ordens** com NF trazendo quantidade superior à pedida:

| Ordem | Produto | Pedido | Recebido | Excesso |
|---|---|---|---|---|
| 2 | P2 | 14 | 64 | +50 |
| 3 | P3 | 12 | 88 | +76 |
| 11 | P11 | 24 | 85 | +61 |
| … | | | | |

**Impacto:** pagamento de mercadoria não solicitada e estoque inflado.

`qa.vw_recebido_maior_que_pedido`

---

## [QA-09] Produtos com margem negativa — **ALTA**

**4 produtos** com `preco_venda` abaixo de `preco_compra`:

| Produto | Preço compra | Preço venda | Margem |
|---|---|---|---|
| P1 | 144,13 | 40,79 | −71,7% |
| P8 | 149,50 | 95,28 | −36,3% |
| P15 | 107,60 | 29,24 | −72,8% |
| P18 | 134,12 | 105,61 | −21,3% |

Prejuízo embutido no cadastro. Ou os preços foram invertidos na carga, ou o cadastro está desatualizado.

`qa.vw_produto_margem_negativa`

---

## [QA-02] Vendas em filial sem cadastro — **ALTA**

**2 filiais** (2 e 3) aparecem em `venda`, mas `produtos_filial` só tem a filial 1. Ou faltou carregar o cadastro dessas filiais, ou as vendas estão com filial errada.

`qa.vw_venda_filial_sem_cadastro`

---

## [QA-06] Entrega anterior ao pedido — **MÉDIA**

**20 registros** com `data_entrega < data_pedido`. Impossível no mundo real.

| Pedido | Data pedido | Data entrega | Diferença |
|---|---|---|---|
| 6 | 22/02/2025 | 05/01/2025 | −48 dias |
| 11 | 22/02/2025 | 08/01/2025 | −45 dias |
| 16 | 27/02/2025 | 14/01/2025 | −44 dias |

**Impacto:** *lead time* de compras fica negativo — indicador usado para negociar prazo com fornecedor.

`qa.vw_pedido_data_invertida`

---

## [QA-10] Preço de venda divergente do cadastro — **MÉDIA**

**20 ocorrências.** O `valor_unitario` praticado não corresponde ao `preco_venda` cadastrado. Combina-se com [M-13]: `produtos_filial` tem três colunas de preço sem definição de qual é a oficial.

`qa.vw_venda_preco_divergente`

---

## [QA-03] Quantidade fracionária em unidade inteira — **MÉDIA**

**5 vendas** com quantidade fracionária e unidade `UN`:

| Venda | Produto | Quantidade | Unidade |
|---|---|---|---|
| 4 | P4 | 38,60 | UN |
| 8 | P8 | 20,04 | UN |
| 12 | P12 | 2,86 | UN |
| 16 | P16 | 37,11 | UN |
| 26 | P26 | 3,11 | UN |

Ou a unidade está errada (deveria ser KG/L), ou houve erro de digitação com deslocamento de vírgula. Não se arredonda por conta própria: as duas hipóteses mudam o faturamento.

`qa.vw_venda_qtde_fracionaria`

---

## [QA-11] Fornecedores sem produto vinculado — **BAIXA**

**3 fornecedores** (F14, F15, F16) sem nenhum produto. Não é erro, mas pode indicar produto que faltou carregar.

`qa.vw_fornecedor_sem_produto`

---

## [QA-12] Vendas fora do período de validação — informativo

| Competência | Lançamentos | Valor | Situação |
|---|---|---|---|
| 01/2025 | 12 | R$ 17.947,15 | fora do escopo |
| **02/2025** | **14** | **R$ 14.093,17** | **escopo de validação** |
| 03/2025 | 7 | R$ 2.727,89 | fora do escopo |

Delimitar o recorte antes de comparar qualquer número evita a discussão mais comum de reunião de validação: dois lados certos falando de períodos diferentes.

`qa.vw_venda_por_competencia`

---

# Painel consolidado

```sql
SELECT * FROM qa.vw_painel_qualidade;
```

| Cód. | Verificação | Severidade | Ocorrências |
|---|---|---|---|
| QA-08 | Divergência qtde_entregue × NF | CRÍTICA | 18 |
| QA-01 | Vendas de produto sem cadastro | ALTA | 13 |
| QA-02 | Vendas em filial sem cadastro | ALTA | 2 |
| QA-04 | Pedido com ordem de compra zerada | ALTA | 11 |
| QA-05 | Pedidos duplicados | ALTA | 18 |
| QA-07 | Recebido maior que pedido | ALTA | 7 |
| QA-09 | Produto com margem negativa | ALTA | 4 |
| QA-03 | Qtde fracionária em unidade UN | MÉDIA | 5 |
| QA-06 | Entrega anterior ao pedido | MÉDIA | 20 |
| QA-10 | Preço de venda divergente do cadastro | MÉDIA | 20 |
| QA-11 | Fornecedor sem produto vinculado | BAIXA | 3 |

Após o saneamento aprovado pelo cliente, esta mesma consulta deve zerar. É a evidência objetiva de que o combinado foi cumprido — prova por consulta, não por afirmação.
