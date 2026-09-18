/* =============================================================================
   Systock - Case Tecnico de Integracao de Dados
   Arquivo 05 - PARTE 3, ITEM 4: TRIGGER DE IDFORNECEDOR NUMERICO

   Requisito:
     "Criar uma trigger que gere automaticamente um novo idfornecedor numerico
      na tabela de produtos que se relacione com a tabela de fornecedor."

   ---------------------------------------------------------------------------
   O PROBLEMA QUE A TRIGGER RESOLVE

   O enunciado declara produtos_filial.idfonecedor como int4. A planilha traz
   valores TEXTUAIS: 'F8', 'F9', 'F10'. E fornecedor.idforncedor e varchar(25).
   Ou seja: o modelo pede um vinculo numerico, a chave real e textual, e um
   INSERT direto falharia com

       invalid input syntax for type integer: "F8"

   Havia tres saidas possiveis:

     (1) Converter idfornecedor para int em produtos_filial.
         Descartada: perde a chave natural do cliente ('F8' vira 8 e o
         codigo original desaparece do sistema).

     (2) Converter a PK de fornecedor para int.
         Descartada: mesma perda, agravada por alterar a tabela mestre.

     (3) Manter a chave natural textual e ADICIONAR uma chave substituta
         numerica em fornecedor, preenchendo automaticamente o vinculo
         numerico em produtos_filial.  <-- ADOTADA

   A opcao (3) atende ao requisito literal (o produto passa a ter um
   idfornecedor numerico que se relaciona com fornecedor) sem destruir
   informacao do cliente. As duas chaves convivem: 'F8' para quem opera,
   8 para quem integra.

   ---------------------------------------------------------------------------
   O QUE A TRIGGER FAZ, EM ORDEM

     1. Se idfornecedor_num ja veio preenchido e e valido, respeita e sai.
     2. Se idfornecedor (texto) esta preenchido:
        2.1 procura o fornecedor correspondente e copia o fornecedor_num;
        2.2 se NAO existir, CADASTRA o fornecedor na hora, gerando um novo
            numero pela IDENTITY, e usa esse numero.
     3. Se idfornecedor estiver nulo, deixa o vinculo nulo (nao inventa).

   O passo 2.2 e o coracao do requisito "gere automaticamente um novo".
   ============================================================================= */


-- =============================================================================
-- 1. FUNCAO DA TRIGGER
-- =============================================================================
CREATE OR REPLACE FUNCTION public.fn_produtos_filial_vincula_fornecedor()
RETURNS trigger
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

COMMENT ON FUNCTION public.fn_produtos_filial_vincula_fornecedor() IS
    'Preenche produtos_filial.idfornecedor_num a partir do codigo textual do fornecedor, cadastrando o fornecedor automaticamente quando ele ainda nao existe.';


-- =============================================================================
-- 2. A TRIGGER
--
-- BEFORE (e nao AFTER): so em BEFORE e possivel alterar NEW e gravar o valor
-- na propria linha. Em AFTER seria preciso um UPDATE adicional na mesma
-- tabela, que redispararia a trigger.
--
-- FOR EACH ROW: a decisao depende do valor de cada linha.
--
-- WHEN: em UPDATE, so dispara se algum dos dois campos de fornecedor mudou.
-- Sem essa clausula, qualquer alteracao de preco ou estoque pagaria o custo
-- de uma consulta a fornecedor sem necessidade.
-- =============================================================================
DROP TRIGGER IF EXISTS tg_produtos_filial_vincula_fornecedor ON public.produtos_filial;

CREATE TRIGGER tg_produtos_filial_vincula_fornecedor
    BEFORE INSERT OR UPDATE OF idfornecedor, idfornecedor_num
    ON public.produtos_filial
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_produtos_filial_vincula_fornecedor();


-- =============================================================================
-- 3. BACKFILL DO HISTORICO
-- A trigger so atua em dado novo. As 20 linhas ja carregadas precisam de um
-- UPDATE para receber o vinculo. O UPDATE dispara a propria trigger, que faz
-- o preenchimento - o que ja e um teste do caminho feliz.
-- =============================================================================
UPDATE public.produtos_filial
   SET idfornecedor = idfornecedor
 WHERE idfornecedor_num IS NULL;


-- =============================================================================
-- 4. FK DO VINCULO NUMERICO
-- Criada so depois do backfill, senao as linhas com idfornecedor_num NULL
-- ja existentes nao teriam problema, mas a ordem correta e garantir o dado
-- antes de impor a regra.
-- =============================================================================
ALTER TABLE public.produtos_filial
    DROP CONSTRAINT IF EXISTS produtos_filial_fornecedor_num_fk;

ALTER TABLE public.produtos_filial
    ADD CONSTRAINT produtos_filial_fornecedor_num_fk
    FOREIGN KEY (idfornecedor_num)
    REFERENCES public.fornecedor (fornecedor_num)
    ON UPDATE CASCADE ON DELETE SET NULL;


/* =============================================================================
   5. TESTES DA TRIGGER
   Os tres cenarios abaixo comprovam o comportamento. Rodar e conferir a saida.
   ============================================================================= */

-- TESTE 1 - Fornecedor EXISTENTE: deve vincular sem criar nada.
-- Esperado: idfornecedor_num = 5 (F5 ja existe), fornecedor continua com 20.
INSERT INTO public.produtos_filial
    (filial_id, idproduto, descricao, estoque, preco_unitario, preco_compra, preco_venda, idfornecedor)
VALUES
    (1, 'TESTE-A', 'Produto de teste A', 10, 25.00, 20.00, 30.00, 'F5');

SELECT 'TESTE 1 - fornecedor existente' AS teste,
       idproduto, idfornecedor, idfornecedor_num
FROM public.produtos_filial WHERE idproduto = 'TESTE-A';


-- TESTE 2 - Fornecedor INEXISTENTE: deve criar o fornecedor e gerar novo numero.
-- Esperado: F99 criado, idfornecedor_num recebe o proximo valor da sequence.
INSERT INTO public.produtos_filial
    (filial_id, idproduto, descricao, estoque, preco_unitario, preco_compra, preco_venda, idfornecedor)
VALUES
    (1, 'TESTE-B', 'Produto de teste B', 5, 15.00, 10.00, 20.00, 'F99');

SELECT 'TESTE 2 - fornecedor novo' AS teste,
       pf.idproduto, pf.idfornecedor, pf.idfornecedor_num, f.razao_social
FROM public.produtos_filial pf
JOIN public.fornecedor f ON f.fornecedor_num = pf.idfornecedor_num
WHERE pf.idproduto = 'TESTE-B';


-- TESTE 3 - UPDATE trocando o fornecedor: deve revincular.
-- Esperado: TESTE-A passa de F5 (num 5) para F12 (num 12).
UPDATE public.produtos_filial
   SET idfornecedor = 'F12'
 WHERE idproduto = 'TESTE-A';

SELECT 'TESTE 3 - troca de fornecedor' AS teste,
       idproduto, idfornecedor, idfornecedor_num
FROM public.produtos_filial WHERE idproduto = 'TESTE-A';


-- TESTE 4 - UPDATE pelo lado NUMERICO: deve sincronizar o codigo textual.
-- Caminho inverso do TESTE 3, para provar que a precedencia funciona nos
-- dois sentidos.
-- Esperado: idfornecedor_num = 3 leva idfornecedor para 'F3'.
UPDATE public.produtos_filial
   SET idfornecedor_num = 3
 WHERE idproduto = 'TESTE-A';

SELECT 'TESTE 4 - troca pelo numero' AS teste,
       idproduto, idfornecedor, idfornecedor_num
FROM public.produtos_filial WHERE idproduto = 'TESTE-A';


-- TESTE 5 - Numero INEXISTENTE: deve recusar a operacao.
-- Esperado: EXCEPTION. O bloco captura para o script nao abortar.
DO $$
BEGIN
    UPDATE public.produtos_filial
       SET idfornecedor_num = 9999
     WHERE idproduto = 'TESTE-A';
    RAISE NOTICE 'TESTE 5 - FALHOU: o UPDATE deveria ter sido recusado';
EXCEPTION WHEN others THEN
    RAISE NOTICE 'TESTE 5 - OK: recusado como esperado (%)', SQLERRM;
END;
$$;


-- Limpeza dos dados de teste.
DELETE FROM public.produtos_filial WHERE idproduto IN ('TESTE-A', 'TESTE-B');
DELETE FROM public.fornecedor      WHERE idfornecedor = 'F99';


-- Conferencia final: nenhum produto pode ficar sem vinculo numerico.
SELECT
    COUNT(*)                                          AS total_produtos,
    COUNT(idfornecedor_num)                           AS com_vinculo_numerico,
    COUNT(*) - COUNT(idfornecedor_num)                AS sem_vinculo
FROM public.produtos_filial;
