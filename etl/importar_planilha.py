#!/usr/bin/env python3
"""
Systock - Case Tecnico de Integracao de Dados
Etapa 1 do ETL: extracao da planilha base_teste_systock.xlsx para CSV.

PRINCIPIO ADOTADO: extracao fiel, sem tratamento.
Este script NAO corrige nada. Ele apenas converte cada aba da planilha em um
CSV de texto puro, preservando os valores exatamente como estao na origem
(inclusive os erros). Todo tratamento acontece no banco, em SQL, na carga da
staging para as tabelas finais (sql/02_staging_e_carga.sql).

Motivo: manter a origem auditavel. Se o tratamento estiver no Python, o cliente
nao consegue rastrear o que foi alterado. Com a staging em texto dentro do
banco, qualquer divergencia apontada na validacao pode ser confrontada
linha a linha contra o dado original.

Uso:
    python etl/importar_planilha.py
    python etl/importar_planilha.py --xlsx caminho/base.xlsx --saida data/csv
"""

import argparse
import sys
from pathlib import Path

import pandas as pd

# Abas esperadas e quantidade de colunas validas de cada uma.
# pedido_compra tem 12 colunas nomeadas; as colunas 13 a 23 da planilha estao
# sem cabecalho e contem um bloco de dados deslocado (ver docs/02).
ABAS = {
    "venda": 9,
    "pedido_compra": 12,
    "entradas_mercadoria": 9,
    "produtos_filial": 8,
    "fornecedor": 2,
}


def extrair(xlsx: Path, saida: Path) -> None:
    saida.mkdir(parents=True, exist_ok=True)
    relatorio = []

    for aba, n_colunas in ABAS.items():
        # dtype=str preserva o valor textual; sem inferencia de tipo do pandas.
        df = pd.read_excel(xlsx, sheet_name=aba, dtype=str)

        total_colunas = df.shape[1]
        colunas_extras = [c for c in df.columns if str(c).startswith("Unnamed")]

        # Isola o bloco fora do cabecalho em CSV separado, para nao perder o dado
        # e poder documentar a anomalia. Nada e descartado silenciosamente.
        if colunas_extras:
            bloco = df[colunas_extras].dropna(how="all")
            destino = saida / f"_anomalia_{aba}_colunas_sem_cabecalho.csv"
            bloco.to_csv(destino, index=False, encoding="utf-8")
            relatorio.append(
                f"  [!] {aba}: {len(colunas_extras)} colunas sem cabecalho com "
                f"{len(bloco)} linhas preenchidas -> {destino.name}"
            )

        df = df.iloc[:, :n_colunas]

        # Datas chegam como '2025-01-11 00:00:00'. Normaliza para ISO (YYYY-MM-DD),
        # que e o formato que o PostgreSQL le sem depender de DateStyle da sessao.
        # Esta e a UNICA normalizacao feita aqui, e e de formato, nao de conteudo.
        for coluna in df.columns:
            amostra = df[coluna].dropna().astype(str)
            if len(amostra) and amostra.str.match(r"^\d{4}-\d{2}-\d{2} 00:00:00$").all():
                df[coluna] = df[coluna].str.slice(0, 10)

        destino = saida / f"{aba}.csv"
        df.to_csv(destino, index=False, encoding="utf-8")
        relatorio.append(
            f"  {aba:<22} {len(df):>3} linhas x {n_colunas} colunas "
            f"(planilha tinha {total_colunas}) -> {destino.name}"
        )

    print(f"Origem : {xlsx}")
    print(f"Destino: {saida}\n")
    print("\n".join(relatorio))
    print("\nExtracao concluida. Proximo passo: sql/02_staging_e_carga.sql")


def main() -> int:
    raiz = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xlsx", default=raiz / "data" / "base_teste_systock.xlsx")
    parser.add_argument("--saida", default=raiz / "data" / "csv")
    args = parser.parse_args()

    xlsx = Path(args.xlsx)
    if not xlsx.exists():
        print(f"ERRO: planilha nao encontrada em {xlsx}", file=sys.stderr)
        return 1

    extrair(xlsx, Path(args.saida))
    return 0


if __name__ == "__main__":
    sys.exit(main())
