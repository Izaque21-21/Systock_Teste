# Parte 1 — Documentação do Processo de Importação

Documento de entrega da Parte 1 do case. Descreve como a planilha `base_teste_systock.xlsx` foi importada para o PostgreSQL, quais tratamentos foram aplicados e quais correções foram necessárias.

---

## 1. Ferramentas utilizadas

| Camada | Ferramenta | Versão | Papel no processo |
|---|---|---|---|
| Banco de dados | PostgreSQL | 16 | Destino da carga |
| Cliente SQL | DBeaver | 24.x | Inspeção, execução e conferência |
| Extração | Python + pandas + openpyxl | 3.11 / 2.x / 3.1 | Conversão XLSX → CSV |
| Carga | `\copy` (psql) | — | CSV → tabelas de staging |
| Transformação | SQL puro (`INSERT ... SELECT`) | — | Staging → tabelas finais |

**Por que não importar o XLSX direto pelo assistente do DBeaver.** O assistente funciona, mas o tratamento fica registrado em cliques, não em código. Um segundo analista não consegue reproduzir a carga nem auditar o que foi alterado. Com script, a importação é reexecutável e versionada — requisito básico em implantação, onde a carga costuma rodar várias vezes até o cliente homologar.

---

## 2. Arquitetura da importação

```
base_teste_systock.xlsx
        │
        │  etl/importar_planilha.py          ← extração fiel, SEM tratamento
        ▼
data/csv/*.csv  (texto puro)
        │
        │  \copy                              ← carga bruta
        ▼
schema stg.*    (todas as colunas TEXT, sem constraint)
        │
        │  INSERT ... SELECT                  ← tipagem e tratamento em SQL
        ▼
schema public.* (tipado, com PK, FK, CHECK e índices)
        │
        │  views                              ← o que não pôde ser corrigido sozinho
        ▼
schema qa.*     (11 verificações de qualidade)
```

### Por que staging em TEXT

Três razões práticas:

1. **A carga não quebra na primeira linha suja.** Se o destino já fosse tipado, um único `'F8'` numa coluna `integer` abortaria o arquivo inteiro e não daria para saber quantos outros problemas existem. Com staging em texto, tudo entra e os problemas são contados de uma vez.

2. **Sobra um retrato do dado original dentro do banco.** Quando o cliente questionar um número na reunião de validação, a resposta sai de uma consulta comparando `stg` com `public` — sem reabrir a planilha.

3. **Cada transformação vira um `INSERT ... SELECT` legível.** O cliente consegue acompanhar a regra aplicada. Código Python de tratamento, não.

---

## 3. Estrutura da planilha

Cinco abas, 122 registros no total.

### 3.1 `venda` — 33 linhas × 9 colunas

| Coluna | Tipo na origem | Tipo no destino | Observação |
|---|---|---|---|
| `venda_id` | Numérico | `bigint` | |
| `data_emissao` | Data | `date` | Jan a Mar/2025 |
| `horariomov` | Texto `HH:MM:SS` | `time` | Convertido |
| `produto_id` | Texto | `varchar(25)` | P1..P28 |
| `qtde_vendida` | Numérico | `numeric(14,3)` | 5 valores fracionários com unidade `UN` |
| `valor_unitario` | Numérico | `numeric(12,4)` | |
| `filial_id` | Numérico | `int` | Valores 1, 2 e 3 |
| `item` | Numérico | `int` | Sempre 1 |
| `unidade_medida` | Texto | `varchar(3)` | Sempre `UN` |

### 3.2 `pedido_compra` — 29 linhas × 12 colunas nomeadas (+ 11 sem cabeçalho)

| Coluna | Tipo na origem | Tipo no destino | Observação |
|---|---|---|---|
| `pedido_id` | Numérico | `bigint` | DDL pedia `float8` |
| `data_pedido` | Data | `date` | |
| `item` | Numérico | `int` | |
| `produto_id` | Texto | `varchar(25)` | |
| `descricao_produto` | Texto | `varchar(255)` | |
| `ordem_compra` | Numérico | `bigint` | **11 registros com valor 0** |
| `qtde_pedida` | Numérico | `numeric(14,3)` | |
| `filial_id` | Numérico | `int` | |
| `data_entrega` | Data | `date` | 20 registros anteriores ao pedido |
| `qtde_entregue` | Numérico | `numeric(14,3)` | |
| `preco_compra` | Numérico | `numeric(12,4)` | |
| `fornecedor_id` | Numérico | `int` | 1..20 — **textual em `fornecedor`** |
| `qtde_pendente` | **AUSENTE** | `numeric(14,3)` | Existe no DDL, não na planilha |

**Anomalia estrutural.** As colunas 13 a 23 da aba não têm cabeçalho e trazem dados nas linhas 22 a 30. O conteúdo é um bloco deslocado com os dados corretos dos pedidos 12 a 20 — incluindo a coluna `qtde_pendente`, ausente do cabeçalho oficial. É erro de montagem da planilha. O bloco foi preservado em `data/csv/_anomalia_pedido_compra_colunas_sem_cabecalho.csv` em vez de descartado.

### 3.3 `entradas_mercadoria` — 20 linhas × 9 colunas

Todas mapeadas sem divergência. A coluna `ordem_compra` **existe na planilha** e estava ausente do DDL do enunciado — ver seção 5.

### 3.4 `produtos_filial` — 20 linhas × 8 colunas

| Coluna na planilha | Coluna no DDL original | Situação |
|---|---|---|
| `idproduto` | `produto_id` | Nome divergente |
| `descricao` | `decricao` | Erro de grafia no DDL |
| `idfornecedor` | `idfonecedor` | Erro de grafia no DDL |
| `idfornecedor` (valores `F8`, `F9`…) | declarado `int4` | **Tipo incompatível** |

### 3.5 `fornecedor` — 20 linhas × 2 colunas

`idfornecedor` (`F1`..`F20`) e `razao_social`. O DDL grafava `idforncedor`.

---

## 4. Tratamentos aplicados

### 4.1 Conversão de tipos

| De | Para | Motivo |
|---|---|---|
| `float8` em `pedido_id`, `item`, `ordem_compra` | `bigint` / `int` | Ponto flutuante binário não garante igualdade exata. Identificador em `float8` é erro conceitual: chave precisa comparar exato. |
| `float8` em quantidades e valores | `numeric` | `float8` não representa decimais exatamente; somas acumulam erro de arredondamento. Em base financeira isso vira divergência de centavos que ninguém explica. |
| `varchar(8)` em `horariomov` | `time` | Texto aceita `'99:99:99'` e ordena errado. |
| `int4` em `produtos_filial.idfornecedor` | `varchar(25)` | A planilha traz `'F8'`. `INSERT` falharia com *invalid input syntax for type integer*. |

### 4.2 Normalizações

- `trim()` em todos os campos textuais.
- `NULLIF(trim(campo), '')` para converter string vazia em `NULL` — string vazia e ausência são coisas diferentes e precisam ser distinguíveis.
- Datas normalizadas para ISO (`YYYY-MM-DD`) na extração, para não depender do `DateStyle` da sessão PostgreSQL.
- `COALESCE(ordem_compra, 0)` preservando o zero de origem em vez de convertê-lo para `NULL` — o zero é o dado real do cliente e precisa aparecer no relatório de pendências.

### 4.3 Derivação de coluna ausente

`qtde_pendente` existe no DDL do enunciado mas não na planilha. Duas opções:

| Opção | Avaliação |
|---|---|
| Remover a coluna do modelo | Descartada — o DDL do cliente a prevê |
| Derivar na carga | **Adotada** |

Regra aplicada:

```sql
GREATEST(COALESCE(qtde_pedida, 0) - COALESCE(qtde_entregue, 0), 0)
```

O `GREATEST` evita pendência negativa quando o recebido supera o pedido — situação que ocorre em 7 ordens da base.

### 4.4 Criação de chave substituta em `fornecedor`

O problema mais estrutural da base: `pedido_compra.fornecedor_id` é numérico (1..20), `fornecedor.idfornecedor` é textual (`F1`..`F20`). Como estava, as duas tabelas não se relacionavam.

Solução adotada: manter a chave natural textual e **adicionar** `fornecedor_num` (`int`, `GENERATED BY DEFAULT AS IDENTITY`), derivada da parte numérica do código:

```sql
NULLIF(regexp_replace(idfornecedor, '\D', '', 'g'), '')::int
```

Assim `'F8'` → `8`, e `pedido_compra.fornecedor_id` passa a ter FK válida. Nenhuma informação do cliente é perdida: `'F8'` para quem opera, `8` para quem integra. Esta coluna é também o alvo da trigger da Parte 3.

Após a carga, a sequence é realinhada com `setval()` — sem isso a trigger geraria um número já em uso no primeiro disparo.

---

## 5. Correções realizadas no DDL

O DDL do enunciado **não é executável**. São 4 erros fatais e 11 de modelagem. Catálogo completo em [`02_catalogo_inconsistencias.md`](02_catalogo_inconsistencias.md); resumo dos fatais:

| Tabela | Erro | Correção |
|---|---|---|
| `entradas_mercadoria` | PK referencia `ordem_compra`, coluna não declarada | Coluna adicionada (`bigint NOT NULL`) — confirmada pela planilha |
| `produtos_filial` | Falta vírgula antes do `CONSTRAINT` | Vírgula adicionada |
| `produtos_filial` | PK referencia `idproduto`, coluna chamada `produto_id` | Coluna renomeada para `idproduto` (grafia da planilha) |
| `fornecedor` | PK referencia `idproduto`, inexistente | PK corrigida para `(idfornecedor)` |

O caso de `entradas_mercadoria` merece nota: a coluna faltante é justamente `ordem_compra`, que a própria observação do enunciado indica como campo de ligação com `pedido_compra`. O DDL torna impossível o relacionamento que o texto descreve.

Além das correções, foram adicionados:

- **3 FKs** (`produtos_filial → fornecedor` por texto e por número, `pedido_compra → fornecedor`)
- **1 FK `NOT VALID`** (`venda → produtos_filial`) — ver seção 6
- **12 CHECKs** de não-negatividade
- **9 índices** sobre as colunas de filtro das análises
- **COMMENTs** nas tabelas e colunas com decisão de projeto

---

## 6. Decisões deliberadas de NÃO corrigir

Três situações em que a correção automática seria mais prejudicial que o problema:

### 6.1 Registros duplicados mantidos

Os pedidos 21 a 29 repetem produto, data e preço dos pedidos 12 a 20. Não violam a PK (o `pedido_id` é diferente), então o banco não os barra.

Foram **carregados, não descartados**. Excluir dado do cliente sem autorização formal é o erro mais caro que se comete em implantação — e o que não tem como desfazer. Ficam visíveis em `qa.vw_pedido_duplicado` e a exclusão só ocorre após o de acordo.

### 6.2 CHECKs de regra de negócio não criados

Não foram criados `CHECK (preco_venda >= preco_compra)` nem `CHECK (data_entrega >= data_pedido)`, embora a base viole ambos (4 e 20 registros). Criar essas constraints impediria a carga e o problema ficaria invisível. A escolha foi carregar, sinalizar em `qa` e levar para validação.

### 6.3 FK de venda criada como `NOT VALID`

13 vendas referenciam produtos inexistentes (P21..P28) e 4 referenciam filiais sem cadastro. A FK foi criada `NOT VALID`: dispensa a verificação do histórico já gravado, mas **passa a valer para todo dado novo**. O passivo fica mensurável e nenhuma venda órfã nova entra.

> Detalhe que costuma passar batido: `NOT VALID` não desliga a checagem de `INSERT` — só pula a varredura das linhas preexistentes. Por isso a constraint precisa ser criada **depois** da carga, não no `CREATE TABLE`. Foi o que causou a falha na primeira execução do script de carga durante o desenvolvimento.

Após o saneamento aprovado:

```sql
ALTER TABLE public.venda VALIDATE CONSTRAINT venda_produto_fk;
```

---

## 7. Conferência da carga

Toda importação termina com contagem origem × destino. Sem isso não há como afirmar que nada se perdeu.

| Tabela | Planilha | Staging | Final | Diferença |
|---|---|---|---|---|
| `fornecedor` | 20 | 20 | 20 | 0 |
| `produtos_filial` | 20 | 20 | 20 | 0 |
| `pedido_compra` | 29 | 29 | 29 | 0 |
| `entradas_mercadoria` | 20 | 20 | 20 | 0 |
| `venda` | 33 | 33 | 33 | 0 |
| **Total** | **122** | **122** | **122** | **0** |

Contagem igual não garante valor igual — uma vírgula deslocada mantém o número de linhas e altera o faturamento. Por isso há também checksum financeiro (`sql/07`, consulta 4.2):

| | Valor |
|---|---|
| Soma `qtde × valor` na origem | R$ 34.768,22 |
| Soma `qtde × valor` no destino | R$ 34.768,22 |
| Diferença | **R$ 0,00** |

---

## 8. Como reproduzir

```bash
createdb -U postgres systock

python etl/importar_planilha.py

psql -U postgres -d systock -f sql/01_ddl_corrigido.sql
psql -U postgres -d systock -f sql/02_staging_e_carga.sql
psql -U postgres -d systock -f sql/05_parte3_trigger_fornecedor.sql
psql -U postgres -d systock -f sql/06_qualidade_dados.sql
```

Alternativa a partir do backup, sem reprocessar a planilha:

```bash
psql -U postgres -d systock -f backup/systock_backup.sql
```
