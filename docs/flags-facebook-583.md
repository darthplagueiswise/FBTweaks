# Revisão de `flags` para Facebook 583

Base: `d5ef86c66277d49ee09879ceba153153ea452cf4`, na própria branch `flags`.
A análise anterior de flags não demonstrou uma causa única para o fetch remoto.
Este ajuste corrige a instrumentação e os acessos locais; a resposta do servidor
continua sendo a evidência necessária para Page ID, nomes e informações de parâmetros.

## Acesso à FBTweak

- Removido o recognizer de long press instalado pela tweak na tabbar.
- Ícone de ajustes, com rótulo acessível **FBTweak**, no canto direito da tela nativa de Configurações.
- Fallback: **dois toques com três dedos**, em uma janela normal do aplicativo. Pode ser desligado no painel e funciona com o master desligado.
- O painel evita apresentações duplicadas e acompanha atualizações da sessão do host.

A factory `viewControllerForMenuItem:viewportSizeEstimate:tabSwitchingType:` do
handler Swift de Configurações retorna `nil` neste payload. A abertura efetiva
usa `FBSettingsControllerOpenBloksAction`, que constrói a tela Bloks e chama
`FBNavigationInfo`. O ícone é associado somente à tela identificada nesse fluxo;
não depende de localizar textos traduzidos ou de abrir o painel pela tabbar.

## MobileConfig e diagnóstico

Os seis símbolos C++ de tabela de overrides e cinco getters Tigon agora usam os
nomes ABI esperados por `dlsym`, sem o sublinhado adicional do Mach-O. Lookups
que falham antes do carregamento dos frameworks podem ser tentados novamente.
O helper `getMobileConfigManager` não é exportado neste payload: a ponte usa os
getters Objective-C `getCurrentManager`/`configManager`, com assinatura conferida
e um `shared_ptr` que mantém o manager vivo durante a chamada.
A API opcional `FBMobileConfigSetSkipOverrideCheckEnabled` não existe na IPA
fornecida; sua ausência não bloqueia os outros símbolos nem aparece como sucesso.

O controle Runtime pausa registros e fallback dos readers quando desligado.
Abrir Live ou usar Aquecer também ativa a sessão. Os hooks permanecem instalados
até encerrar o app; desativar o controle não desfaz valores que já tenham sido
gravados na tabela nativa ou no arquivo. O master desativa o comportamento local.
Capturar leituras registra acessos observados, sem solicitar um fetch ao servidor.

Ligar somente o log de fetch não ativa o aquecimento, não suprime o alerta nativo
e não agenda um retry. Com Aquecer ativo, uma seleção pode ser repetida uma única
vez. Seleções substituídas são descartadas antes de executar um retry pendente.

A captura inclui os retornos QE-info, download de nomes, metadados de erro,
callbacks NSURLSession e Tigon disponíveis. Cada classe NSURLSession guarda seu
próprio IMP original, evitando recursão ao chamar a superclasse. O relatório
exportado inclui cobertura atual do runtime e dos transports, além dos eventos.
Registro solicitado, hook disponível, leitura observada e resposta capturada são
estados distintos.

No executável fornecido, `onResponse` e `onBody` têm bindings em
`__DATA_CONST,__const`, fora das seções suportadas pelo fishhook. Foram adicionados
rebinding desses dois slots, estritamente limitado ao UUID
`4c4c44aa-5555-3144-a18e-014741ed190b`, aos endereços `0x101010370` e `0x101010378`
e aos ponteiros originais resolvidos por símbolo. A página deve ser de dados e
não executável; a proteção é restaurada após a troca atômica. UUID, ponteiro ou
permissão incompatíveis impedem a instalação e ficam registrados no diagnóstico.
Nenhuma instrução de `__TEXT` é alterada. O status HTTP do callback Tigon ainda
não é interpretado: `0` significa indisponível, não HTTP 200 nem sucesso.

Os corpos de resposta são limitados a 2 MiB, somente para requisições pertinentes
na janela de captura. Payloads com campos de credenciais são descartados. O
log e os payloads ficam no diretório do MobileConfig resolvido para a sessão.
O arquivo existente é procurado em todos os grupos candidatos antes de escolher
um caminho de criação. O relatório Preferences audit compara o arquivo com as
preferências persistidas; não trata uma diferença como prova de consumo pelo runtime.

## Internal Settings, employee e dogfood

Mantido o construtor exportado `FBInternalSettingsViewControllerFromSession`.
Falhas de sessão, símbolo ou construção agora recebem uma mensagem visível.
Removidos cinco setters que não existem em `FBBugReportConfiguration` no payload.
Corrigido `peopleSampling` de objeto para `long long`, conforme a ABI do
inicializador de `RCDMobileConfigParams`. A assinatura de FBLoom também foi
reconferida. Os gates employee/test-user/dogfood continuam locais e não fornecem
autorização interna no servidor.

Incluído **Abrir Whitehat nativo**. Seu handler nativo cria
`FBWhitehatSettingsViewController` com `+new`; o atalho segue esse caminho e não
altera certificados nem as opções de rede automaticamente.

## Validação e uso

`scripts/verify-facebook-payload.py` usa LIEF e Capstone para conferir UUID,
bindings, exports usados por dlsym, assinaturas Objective-C, setters removidos e
a factory de Configurações. Execute com o diretório `Payload/Facebook.app`:

```sh
python -m pip install lief capstone
python scripts/verify-facebook-payload.py /caminho/Payload/Facebook.app
```

O build rootless ARM64 continua no workflow de push para `flags` com SDK 26.2.
No aparelho, abrir Configurações verifica o ícone; dois toques com três dedos
verificam o fallback. Para investigar o fetch, ligar o log e reproduzir o download
de nomes e a seleção de parâmetros; exportar **Fetch log** e **Plist audit** em
MobileConfig Live. A cobertura informa se os callbacks foram instalados e se
houve corpo de resposta. A falta de resposta observada não é classificada como
sucesso remoto.
