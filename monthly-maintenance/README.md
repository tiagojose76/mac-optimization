# macOS Monthly Maintenance

Utilitario mensal para analisar uso de disco, localizar pastas grandes e limpar caches comuns com confirmacao manual.

## Uso

```bash
chmod +x mac-monthly-maintenance.sh
./mac-monthly-maintenance.sh scan
```

O modo `scan` nao apaga nada. Ele gera um relatorio em:

```text
~/Desktop/mac-maintenance-reports/
```

Para limpar itens seguros com perguntas antes de cada acao:

```bash
./mac-monthly-maintenance.sh clean
```

## O que ele verifica

- Resumo do disco.
- Pressao atual de memoria e processos usando mais RAM.
- Maiores itens em `~`, `~/Library` e `/Applications`.
- Tamanhos de caches e diretorios comuns: lixeira, logs, Homebrew, npm, Yarn, pip, Go, Xcode e Docker.

## O que ele pode limpar

- Conteudo da lixeira.
- Logs do usuario com mais de 30 dias.
- `~/Library/Caches`.
- Caches de Homebrew, Yarn, pip e Go.
- Limpezas opcionais de Homebrew, npm e Docker, se essas ferramentas existirem.

## Observacoes

- O script foca em liberar armazenamento em disco. Ele mostra uso de RAM, mas apagar caches nao reduz RAM diretamente.
- Ele nao apaga `Downloads`, documentos pessoais, fotos, projetos, `/System` ou `/Library`.
- Revise sempre o relatorio antes de confirmar uma limpeza.
