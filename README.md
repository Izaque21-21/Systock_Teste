# Case Técnico — Analista de Integração de Dados (Implantação)

Solução do case técnico Systock: restauração da base em PostgreSQL, documentação do processo de importação, consultas SQL de análise, transformações com trigger e estratégia de validação com o cliente.

**Autor:** Izaque
**Banco:** PostgreSQL 16
**Ferramentas:** DBeaver, Python 3.11 (pandas, openpyxl), psql

---

## Sumário da entrega

| Parte do case | Entrega | Onde está |
|---|---|---|
| Setup | Restauração da base | [`sql/01`](sql/01_ddl_corrigido.sql), [`sql/02`](sql/02_staging_e_carga.sql), [`backup/`](backup/) |
| **Parte 1** | Documentação da importação | [`docs/01_documentacao_importacao.md`](docs/01_documentacao_importacao.md) |
| **Parte 2** | Consultas SQL básicas | [`sql/03_parte2_consultas_basicas.sql`](sql/03_parte2_consultas_basicas.sql) |
| **Parte 3** | Transformações (itens 1–3) | [`sql/04_parte3_transformacoes.sql`](sql/04_parte3_transformacoes.sql) |
| **Parte 3** | Trigger de fornecedor (item 4) | [`sql/05_parte3_trigger_fornecedor.sql`](sql/05_parte3_trigger_fornecedor.sql) |
| **Parte 4** | Estratégia de validação | [`docs/03_roteiro_validacao_cliente.md`](docs/03_roteiro_validacao_cliente.md) + [`sql/07`](sql/07_parte4_consultas_validacao.sql) |
| Extra | Catálogo das inconsistências | [`docs/02_catalogo_inconsistencias.md`](docs/02_catalogo_inconsistencias.md) |
| Extra | Camada de qualidade de dados | [`sql/06_qualidade_dados.sql`](sql/06_qualidade_dados.sql) |

---

## Resultado em uma tela

O enunciado avisa que o teste contém erros intencionais. Foram encontrados **32**:

| Categoria | Qtd. |
|---|---|
| Erros fatais de DDL (impedem a execução do `CREATE TABLE`) | 4 |
| Erros de grafia e nomenclatura | 6 |
| Problemas de modelagem | 11 |
| Inconsistências de dados | 11 |

O DDL do enunciado **não é executável**. O caso mais grave: a PK de `entradas_mercadoria` referencia a coluna `ordem_compra`, que não é declarada na tabela — e é justamente o campo que a observação do enunciado aponta como ligação com `pedido_compra`.

Nos dados, a inconsistência crítica é a divergência entre `pedido_compra.qtde_entregue` e a soma das notas fiscais: **as 18 ordens vinculadas divergem, sem exceção**.

Catálogo completo: [`docs/02_catalogo_inconsistencias.md`](docs/02_catalogo_inconsistencias.md).

---

## Estrutura do repositório

```
.
├── README.md
│
├── etl/
│   ├── importar_planilha.py         Extração XLSX → CSV (sem tratamento)
│   └── requirements.txt
│
├── sql/
│   ├── 00_ddl_original_comentado.sql    DDL do enunciado com cada erro anotado (NÃO EXECUTAR)
│   ├── 01_ddl_corrigido.sql             Estrutura corrigida: PK, FK, CHECK, índices
│   ├── 02_staging_e_carga.sql           Staging em TEXT + carga tratada
│   ├── 03_parte2_consultas_basicas.sql  PARTE 2
│   ├── 04_parte3_transformacoes.sql     PARTE 3, itens 1 a 3
│   ├── 05_parte3_trigger_fornecedor.sql PARTE 3, item 4 (trigger + 5 testes)
│   ├── 06_qualidade_dados.sql           11 views de QA + painel consolidado
│   └── 07_parte4_consultas_validacao.sql PARTE 4 — consultas da reunião
│
├── docs/
│   ├── 01_documentacao_importacao.md    PARTE 1
│   ├── 02_catalogo_inconsistencias.md   As 32 inconsistências, com evidência
│   └── 03_roteiro_validacao_cliente.md  PARTE 4
│
├── data/
│   ├── base_teste_systock.xlsx          Planilha original
│   └── csv/                             CSVs gerados pelo ETL
│
└── backup/
    └── systock_backup.sql               Dump completo (pg_dump)
```

---

## Como executar

### Opção A — restaurar do backup (mais rápido)

```bash
createdb -U postgres systock
psql -U postgres -d systock -f backup/systock_backup.sql
```

Pronto. Base com estrutura, dados, trigger e views de QA.

### Opção B — reproduzir o processo completo

```bash
# 1. Dependências Python
pip install -r etl/requirements.txt

# 2. Banco
createdb -U postgres systock

# 3. Extração XLSX → CSV
python etl/importar_planilha.py

# 4. Estrutura e carga (rodar da raiz do repositório — o \copy usa caminho relativo)
psql -U postgres -d systock -f sql/01_ddl_corrigido.sql
psql -U postgres -d systock -f sql/02_staging_e_carga.sql

# 5. Trigger e camada de qualidade
psql -U postgres -d systock -f sql/05_parte3_trigger_fornecedor.sql
psql -U postgres -d systock -f sql/06_qualidade_dados.sql
```

### Conferir se deu certo

```sql
SELECT * FROM qa.vw_painel_qualidade;
```

Deve retornar 11 linhas com as ocorrências descritas no catálogo.

### Usando DBeaver

O `\copy` é um comando do `psql` e não roda no DBeaver. Alternativa:

1. Executar apenas a **Seção 1** de `sql/02_staging_e_carga.sql` (cria as tabelas `stg.*`)
2. Importar cada CSV de `data/csv/` pelo assistente — botão direito na tabela → *Import Data*
3. Executar da **Seção 3** em diante

---

## Modelo de dados

```
  fornecedor
  ├── idfornecedor    varchar(25)  PK    'F1'..'F20'   chave natural
  └── fornecedor_num  int          UK     1..20        chave substituta ◄── criada na solução
        │
        ├──────────────────────────────┐
        │ (texto)                      │ (número)
        ▼                              ▼
  produtos_filial                 pedido_compra
  ├── filial_id      PK           ├── pedido_id     PK
  ├── idproduto      PK           ├── produto_id    PK
  ├── idfornecedor   FK ──────────┤   item          PK
  └── idfornecedor_num FK ◄── trigger
                                  └── ordem_compra ──┐
        ▲                                            │
        │ FK NOT VALID                               │ (sem FK: não é chave candidata)
        │                                            ▼
     venda                              entradas_mercadoria
     └── filial_id + produto_id          └── ordem_compra + item + produto_id + nro_nfe  PK
```

### Duas decisões que sustentam o modelo

**1. Chave substituta em `fornecedor`.** O enunciado declara `produtos_filial.idfonecedor` como `int4`, mas a planilha traz `'F8'`, `'F9'`, `'F10'`. E `pedido_compra.fornecedor_id` é numérico enquanto `fornecedor.idforncedor` é texto — as tabelas não se relacionavam.

A solução mantém a chave natural textual e **adiciona** `fornecedor_num`, derivada da parte numérica do código (`'F8'` → `8`). Nada do cliente é perdido: `'F8'` para quem opera, `8` para quem integra. É também o alvo da trigger da Parte 3.

**2. FK de `venda` criada como `NOT VALID`.** 13 vendas referenciam produtos inexistentes. A FK `NOT VALID` dispensa a verificação do histórico já gravado mas passa a valer para todo dado novo — o passivo fica mensurável e nenhuma venda órfã nova entra.

> Detalhe que costuma passar batido: `NOT VALID` **não** desliga a checagem de `INSERT`, só pula a varredura das linhas preexistentes. Por isso a constraint é criada depois da carga, e não no `CREATE TABLE`.

---

## Decisões de projeto

### Por que staging em TEXT

```
XLSX → CSV → stg.* (TEXT) → public.* (tipado) → qa.* (views)
```

1. A carga não quebra na primeira linha suja — um `'F8'` em coluna `integer` abortaria o arquivo inteiro e esconderia os demais problemas.
2. Sobra um retrato do dado original dentro do banco: número questionado na validação é rastreável sem reabrir a planilha.
3. Cada transformação vira um `INSERT ... SELECT` legível e auditável.

### O que foi deliberadamente NÃO corrigido

Três situações em que a correção automática seria mais prejudicial que o problema:

| Situação | Decisão | Motivo |
|---|---|---|
| 9 pares de pedidos duplicados | Carregados, sinalizados em `qa` | Excluir dado do cliente sem autorização formal é o erro que não tem como desfazer |
| Margem negativa e datas invertidas | Sem CHECK constraint | A constraint bloquearia a carga e o problema ficaria invisível |
| 5 quantidades fracionárias em `UN` | Carregadas como estão | Arredondar altera o faturamento do cliente por conta própria |

O princípio: **sinalizar, nunca silenciar**. Em implantação, dado corrigido sem aprovação vira divergência que aparece meses depois, quando ninguém lembra o que foi alterado.

### Ambiguidade tratada explicitamente

O requisito 3 da Parte 3 pede produtos *"requisitados mais de 10 vezes"*, o que admite duas leituras: soma das quantidades > 10, ou número de ocorrências > 10.

O exemplo do enunciado mostra `Qtde Requisitada = 15` com **uma única** data de solicitação — se fossem 15 ocorrências, a coluna "Data Solicitação" não poderia ter valor único. Isso indica a primeira leitura, adotada na consulta principal.

A segunda leitura ficou entregue como consulta alternativa. Na base atual retorna vazio (o máximo são 2 ocorrências, justamente as duplicatas) — resultado que reforça a escolha.

---

## Trigger da Parte 3 — comportamento

`tg_produtos_filial_vincula_fornecedor` (`BEFORE INSERT OR UPDATE`) preenche `idfornecedor_num` a partir do código textual e **cadastra o fornecedor automaticamente** quando ele não existe.

Cinco cenários testados no próprio script:

| Teste | Cenário | Esperado | Resultado |
|---|---|---|---|
| 1 | Fornecedor existente (`F5`) | Vincula, não cria nada | ✅ `idfornecedor_num = 5` |
| 2 | Fornecedor inexistente (`F99`) | Cria fornecedor e gera novo número | ✅ criado com `num = 21` |
| 3 | `UPDATE` trocando o código textual | Revincula o número | ✅ `F12` → `num = 12` |
| 4 | `UPDATE` trocando o número | Sincroniza o código textual | ✅ `num = 3` → `F3` |
| 5 | `UPDATE` com número inexistente | Recusa a operação | ✅ exceção lançada |

O teste 3 expôs um bug na primeira versão: em `UPDATE` que altera só o código textual, `NEW.idfornecedor_num` ainda carrega o número **antigo** e a função o considerava válido — o produto terminava com texto novo e número velho. A correção compara `NEW` com `OLD` para definir qual campo tem precedência (o textual vence, por ser o que o usuário opera).

---

## Camada de qualidade

Cada inconsistência virou uma view em `qa`, consultável a qualquer momento:

```sql
SELECT * FROM qa.vw_painel_qualidade;
```

| Cód. | Verificação | Severidade | Ocorrências |
|---|---|---|---|
| QA-08 | Divergência qtde_entregue × NF | CRÍTICA | 18 |
| QA-01 | Vendas de produto sem cadastro | ALTA | 13 |
| QA-05 | Pedidos duplicados | ALTA | 18 |
| QA-04 | Pedido com ordem de compra zerada | ALTA | 11 |
| QA-07 | Recebido maior que pedido | ALTA | 7 |
| QA-09 | Produto com margem negativa | ALTA | 4 |
| QA-02 | Vendas em filial sem cadastro | ALTA | 2 |
| QA-06 | Entrega anterior ao pedido | MÉDIA | 20 |
| QA-10 | Preço de venda divergente do cadastro | MÉDIA | 20 |
| QA-03 | Qtde fracionária em unidade UN | MÉDIA | 5 |
| QA-11 | Fornecedor sem produto vinculado | BAIXA | 3 |

Depois do saneamento aprovado pelo cliente, esta mesma consulta deve zerar. É prova por consulta, não por afirmação — e é o que dá segurança ao cliente no aceite.

---

## Conferência da carga

| Tabela | Planilha | Banco | Diferença |
|---|---|---|---|
| `fornecedor` | 20 | 20 | 0 |
| `produtos_filial` | 20 | 20 | 0 |
| `pedido_compra` | 29 | 29 | 0 |
| `entradas_mercadoria` | 20 | 20 | 0 |
| `venda` | 33 | 33 | 0 |
| **Total** | **122** | **122** | **0** |

Contagem igual não garante valor igual — uma vírgula deslocada mantém o número de linhas e altera o faturamento. Por isso há também checksum financeiro:

| | Valor |
|---|---|
| Soma `qtde × valor` na origem | R$ 34.768,22 |
| Soma `qtde × valor` no destino | R$ 34.768,22 |
| **Diferença** | **R$ 0,00** |

---

## Resultado da Parte 2 — Fevereiro/2025

| | |
|---|---|
| Lançamentos | 14 |
| Produtos distintos | 14 |
| Quantidade total | 173,22 |
| **Faturamento** | **R$ 14.093,17** |

Dos 14 produtos vendidos no período, **6 não têm cadastro** (P22 a P27). A consulta usa `LEFT JOIN` de propósito: com `INNER JOIN` essas vendas sumiriam e o total não bateria com o faturamento do cliente. Relatório que esconde problema é pior que relatório com problema.
