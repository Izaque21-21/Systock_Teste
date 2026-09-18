# Parte 4 — Estratégia de Validação com o Cliente

**Período em validação:** Fevereiro/2025
**Duração prevista:** 90 minutos
**Participantes:** analista de implantação, gestor de compras, gestor comercial/fiscal, responsável de TI do cliente

---

## Premissa do roteiro

O objetivo da reunião não é apresentar dados. É conseguir que o cliente **assine embaixo** de que a base está correta — e, para isso, ele precisa se convencer sozinho.

Três princípios orientam a condução:

1. **Nenhum número aparece sem contexto de origem.** Todo valor mostrado vem acompanhado de onde saiu e como pode ser conferido.
2. **Problema encontrado é apresentado como pergunta, não como falha.** "Estes 8 produtos existem no seu cadastro?" funciona; "sua base tem 13 vendas órfãs" fecha a conversa.
3. **O cliente decide, o analista recomenda.** Toda divergência termina em uma decisão registrada com responsável e prazo.

---

# 1. Principais pontos a validar

Organizados em cinco blocos, na ordem em que entram na reunião.

## Bloco 1 — Escopo e completude

Antes de conferir número, alinhar o que está sendo contado.

| Ponto | Pergunta ao cliente | Consulta |
|---|---|---|
| Recorte do período | "Validamos fevereiro. A base tem janeiro e março — entram agora?" | `qa.vw_venda_por_competencia` |
| Filiais no escopo | "Aparecem as filiais 1, 2 e 3. Todas devem estar aqui?" | 1.1 |
| Volume esperado | "14 lançamentos em fevereiro. Bate com o movimento do mês?" | 1.1 |
| Dias sem movimento | "Fevereiro tem 20 dias úteis e há venda em 6. É esperado?" | 1.3 |

> O ponto dos dias sem movimento costuma ser o mais produtivo da abertura. O cliente reconhece o próprio calendário na hora e identifica falha de carga que nenhuma validação técnica pegaria.

## Bloco 2 — Faturamento

| Ponto | O que validar | Consulta |
|---|---|---|
| Total do mês | R$ 14.093,17 — confronto com o fechamento contábil do cliente | 1.1 |
| Ranking de produtos | Os 5 mais vendidos correspondem ao que o cliente espera? | Parte 2.1 |
| Preço praticado | 20 vendas com preço diferente do cadastro | `qa.vw_venda_preco_divergente` |
| Qual preço é o oficial | `preco_unitario`, `preco_compra` ou `preco_venda`? | 3.7 |

## Bloco 3 — Compras e recebimento

O bloco mais crítico. Aqui está o problema de maior severidade da base.

| Ponto | O que validar | Consulta |
|---|---|---|
| Conciliação pedido × NF | **18 de 18 ordens divergem** | 2.1 |
| Fonte oficial da quantidade | Vale o pedido ou a nota fiscal? | 3.5 |
| Pedidos sem ordem de compra | 11 pedidos com `ordem_compra = 0` | 3.4 |
| Recebimento a maior | 7 ordens com NF acima do pedido | `qa.vw_recebido_maior_que_pedido` |
| Duplicidade | 9 pares de pedidos repetidos | 3.4 |

## Bloco 4 — Cadastro e integridade

| Ponto | O que validar | Consulta |
|---|---|---|
| Produtos sem cadastro | P21 a P28 vendidos sem existir | 3.1 |
| Margem negativa | 4 produtos vendidos abaixo do custo | 3.6 |
| Unidade de medida | 5 vendas fracionárias em `UN` | 3.3 |
| Vínculo de fornecedor | Código textual × numérico | — |

## Bloco 5 — Coerência de estoque

| Ponto | O que validar | Consulta |
|---|---|---|
| Saldo × movimento | Estoque atual é compatível com entradas e saídas? | 2.2 |
| Saída maior que disponível | P14 vendeu 53 com estoque de 9 | 2.2 |
| Saldo inicial | O estoque informado é de qual data? | — |

---

# 2. Técnicas para garantir exatidão e precisão

Seis técnicas, da mais básica à mais específica. As três primeiras são obrigatórias em qualquer carga; as três últimas são o que separa validação superficial de validação confiável.

## 2.1 Reconciliação de volumetria (origem × destino)

Contagem linha a linha entre a planilha e o banco. Prova que nada se perdeu nem foi inventado.

| Tabela | Origem | Destino | Diferença |
|---|---|---|---|
| `venda` | 33 | 33 | 0 |
| `pedido_compra` | 29 | 29 | 0 |
| `entradas_mercadoria` | 20 | 20 | 0 |
| `produtos_filial` | 20 | 20 | 0 |
| `fornecedor` | 20 | 20 | 0 |

É o argumento de abertura mais forte: o cliente vê a contagem bater antes de qualquer discussão.

## 2.2 Checksum financeiro

Contagem igual não garante valor igual — uma vírgula deslocada na conversão de tipo mantém o número de linhas e altera o faturamento. Somar `quantidade × valor` nos dois lados fecha essa brecha.

| | Valor |
|---|---|
| Origem (staging) | R$ 34.768,22 |
| Destino (produção) | R$ 34.768,22 |
| **Diferença** | **R$ 0,00** |

## 2.3 Rastreabilidade ponta a ponta

A staging permanece no banco depois da carga. Qualquer número questionado é rastreável até a linha original sem reabrir a planilha:

```sql
SELECT * FROM stg.venda        WHERE venda_id = '14';
SELECT * FROM public.venda     WHERE venda_id = 14;
```

Em reunião, esse é o movimento que encerra discussão: o cliente aponta um número, o analista mostra a origem em dois segundos.

## 2.4 Validação cruzada entre módulos

O mesmo fato visto por tabelas diferentes tem que contar a mesma história. Três cruzamentos:

| Cruzamento | Regra esperada | Resultado |
|---|---|---|
| `pedido_compra` × `entradas_mercadoria` | `qtde_entregue` = soma das NFs | **18 divergências** |
| `venda` × `produtos_filial` | Todo produto vendido é cadastrado | **13 órfãos** |
| `produtos_filial` × movimento | Estoque compatível com entradas − saídas | **1 alerta (P14)** |

Uma tabela isolada pode estar internamente consistente e ainda assim errada. Só o cruzamento revela.

## 2.5 Testes de razoabilidade de negócio

Regras que o banco não impõe mas o negócio exige:

| Regra | Violações |
|---|---|
| `data_entrega >= data_pedido` | 20 |
| `preco_venda >= preco_compra` | 4 |
| `qtde_recebida <= qtde_pedida` | 7 |
| Quantidade inteira quando unidade é `UN` | 5 |
| Todo pedido tem ordem de compra | 11 |

Estas regras **não viraram CHECK constraint** de propósito. Criá-las bloquearia a carga e o problema ficaria invisível. A escolha foi carregar, sinalizar em `qa` e trazer para esta reunião.

## 2.6 Verificação de unicidade real

A PK de `venda` tem 6 colunas, incluindo data e hora — o que a torna permissiva. A mesma venda reprocessada com horário diferente entra duas vezes sem violar a chave.

```sql
SELECT filial_id, venda_id, produto_id, item, COUNT(*)
FROM public.venda
GROUP BY filial_id, venda_id, produto_id, item
HAVING COUNT(*) > 1;
```

Resultado atual: nenhuma duplicata. Mas a fragilidade permanece, e vira recomendação de evolução do modelo.

---

# 3. Consultas prontas para a reunião

Todas em `sql/07_parte4_consultas_validacao.sql`, numeradas na ordem de uso.

## Abertura — "os números batem?"

| # | Consulta | Para quê |
|---|---|---|
| 1.1 | Cartão de conferência do período | Número único para o cliente confirmar ou negar |
| 1.2 | Delimitação de escopo | Alinhar o recorte antes de comparar |
| 1.3 | Faturamento diário | Cliente reconhece o próprio movimento |

## Conciliação

| # | Consulta | Para quê |
|---|---|---|
| 2.1 | Pedido × NF, ordem a ordem | **Consulta central da reunião** |
| 2.2 | Movimentação completa por produto | Teste de razoabilidade de estoque |

## Exceções — cada uma termina em uma pergunta

| # | Pergunta ao cliente | Ocorrências |
|---|---|---|
| 3.1 | "Estes 8 produtos existem no seu cadastro?" | 13 |
| 3.2 | "As filiais 2 e 3 devem estar nesta base?" | 2 |
| 3.3 | "Estes itens são vendidos por peso?" | 5 |
| 3.4 | "Estes 9 pedidos são reais ou duplicação?" | 18 |
| 3.5 | "Quando pedido e NF divergem, qual vale?" | 18 |
| 3.6 | "Estes 4 produtos são vendidos abaixo do custo de propósito?" | 4 |
| 3.7 | "Das três colunas de preço, qual é a oficial?" | 20 |
| 3.8 | "Estas entregas antes do pedido são erro de digitação?" | 20 |

## Fechamento — provas de exatidão

| # | Consulta | Para quê |
|---|---|---|
| 4.1 | Rastreabilidade origem → destino | Nada se perdeu |
| 4.2 | Checksum financeiro | Nenhum valor se alterou |
| 4.3 | Teste de unicidade | Nenhuma duplicata na chave |
| 4.4 | Painel de qualidade | Estado consolidado das 11 verificações |

---

# 4. Como conduzir cada tipo de divergência

A forma de apresentar determina se a reunião avança ou trava.

| Situação | ❌ Evitar | ✅ Usar |
|---|---|---|
| Produto sem cadastro | "Há 13 vendas órfãs na base" | "Encontrei 8 códigos com venda mas sem cadastro. São produtos descontinuados ou faltou carregar?" |
| Divergência pedido × NF | "Os dados estão inconsistentes" | "Para a ordem 13, o pedido registra 91 entregues e a NF, 7. Qual desses o senhor usa hoje para conferir o recebimento?" |
| Pedidos duplicados | "A planilha veio com duplicatas" | "Os pedidos 21 a 29 repetem produto, data e preço dos pedidos 12 a 20. Quero confirmar se são compras distintas antes de tratá-los." |
| Margem negativa | "Estes produtos estão com preço errado" | "Quatro produtos estão com venda abaixo do custo. É estratégia comercial ou o cadastro está desatualizado?" |

O padrão: descrever o fato observado, mostrar a evidência, fazer uma pergunta que o cliente consiga responder. Nunca qualificar o dado do cliente como errado — ele pode ter uma razão que o analista não conhece.

---

# 5. Registro de decisões

Toda divergência sai da reunião com decisão, responsável e prazo. Sem isso, a discussão se repete na semana seguinte.

| Cód. | Divergência | Decisão | Responsável | Prazo |
|---|---|---|---|---|
| QA-08 | Divergência qtde_entregue × NF | | | |
| QA-05 | 9 pares de pedidos duplicados | | | |
| QA-01 | 8 produtos sem cadastro | | | |
| QA-04 | 11 pedidos sem ordem de compra | | | |
| QA-07 | 7 ordens com recebimento a maior | | | |
| QA-09 | 4 produtos com margem negativa | | | |
| QA-02 | Filiais 2 e 3 sem cadastro | | | |
| QA-06 | 20 entregas anteriores ao pedido | | | |
| QA-10 | Definir coluna de preço oficial | | | |
| QA-03 | 5 vendas fracionárias em `UN` | | | |
| QA-11 | 3 fornecedores sem produto | | | |

---

# 6. Critério de aceite

A validação é considerada concluída quando:

1. O cliente confirma o faturamento de fevereiro contra o fechamento contábil dele.
2. As 11 divergências têm decisão registrada e assinada.
3. O saneamento aprovado é aplicado e `qa.vw_painel_qualidade` **zera todas as linhas**.
4. A FK prospectiva é validada, comprovando que o passivo foi eliminado:

```sql
ALTER TABLE public.venda VALIDATE CONSTRAINT venda_produto_fk;
```

O item 3 é o que dá segurança ao cliente: a prova de que o combinado foi cumprido é uma consulta que ele mesmo pode rodar, não uma afirmação do fornecedor.

---

# 7. Recomendações pós-validação

Melhorias que não cabem no escopo da carga mas previnem a reincidência dos problemas encontrados.

| # | Recomendação | Problema que previne |
|---|---|---|
| 1 | Revisar a PK de `venda` para chave de documento fiscal | Duplicidade por reprocessamento (M-07) |
| 2 | Tornar `ordem_compra` obrigatória e única por pedido | Pedidos órfãos (QA-04) |
| 3 | Eliminar `qtde_entregue` e derivar da NF | Divergência estrutural (QA-08) |
| 4 | Definir uma única coluna de preço oficial | Ambiguidade de faturamento (M-13) |
| 5 | Cadastrar `unidade_medida` no produto, não na venda | Fracionário em `UN` (QA-03) |
| 6 | Rodar `qa.vw_painel_qualidade` em rotina diária | Detecção precoce de reincidência |

A recomendação 6 é a que mais muda o jogo no médio prazo: transforma a validação de evento pontual em monitoramento contínuo. O painel já está pronto — só precisa de agendamento.
