# FBTweak Native Live Trace — fase 1

O Live Trace é um inspector **integrado à própria FBTweak**, destinado a um aplicativo iOS sideloaded **sem jailbreak e sem Frida Gadget**. Reutiliza os backends da FBTweak; não injeta código ARM64 arbitrário nem executa scripts remotos.

## Ativação

1. Instale uma build de `flags` com CI concluído.
2. Abra **FBTweak → Browsers → Native Live Trace** e ative **Capturar**. **Iniciar nova captura** no diagnóstico de nomes também arma o buffer nesta sessão. Ativar um probe nativo arma o buffer somente depois de instalar e validar o hook.
3. Para acompanhar um getter BOOL específico: **FBTweak → Browsers → ObjC BOOL Live**, procure a classe/selector, toque em **Observar (sem forçar)**.
4. Execute a interação do aplicativo; retorne à tela Native Live Trace e toque **Atualizar**.
5. **Exportar** compartilha um JSON local (`fbt_native_live_trace.json`); **Limpar** esvazia o buffer atual.

Para eventos de QE/Tigon, mantenha os diagnósticos nativos correspondentes ativados; Live Trace **não instala automaticamente** interceptações de rede ou de funções C++.

O armamento feito por essas ações é efêmero; não altera `fbt_native_trace_enabled` nem instala hooks adicionais. **Capturar OFF** interrompe também esse armamento. Pausar o diagnóstico de nomes interrompe o buffer da sessão; a preferência manual continua independente. **Iniciar nova captura** limpa o buffer anterior; ativar outro probe não apaga os eventos. O buffer registra os próximos eventos e não reconstrói tentativas anteriores a partir do log em disco.

## Estado do JSON exportado

O schema 2 separa o coletor das fontes de eventos:

- `enabled` e `collector_state`: estado real do buffer; não afirmam que um hook foi instalado.
- `manual_capture_enabled` e `session_capture_enabled`: origem do armamento. A sessão depende de Log QE-info ativo.
- `network_source_state`: `diagnostics_off`, `not_armed`, `hook_unavailable`, `unknown` ou `armed`. `armed` exige um probe habilitado **e** seu hook instalado. Resolução desconhecida não conta como falha. `native_session_probes` fornece os estados e a resolução de cada hook.
- `observation_state`: `capture_off` quando vazio e desligado; `not_observed` quando ativo, mas sem evento; `dropped_on_contention` quando houve descartes e nenhum evento retido; `observed` quando há eventos no buffer, mesmo se a captura já foi pausada.

Um JSON antigo com `enabled:false` e `events:[]` mostra um coletor desligado. Isso não demonstra falha do hook nem ausência de requisições no outro diagnóstico. O início da captura não adiciona eventos artificiais ao buffer.

## Tipos observados

- **BOOL**: chave `[+|-]Classe#selector`, amostras das primeiras 8 execuções e a cada 128 chamadas; valor original **somente se realmente executado** e valor efetivo do hook do Runtime BOOL Browser. Um getter forçado mostra `original=null`.
- **QE/Tigon**: eventos já gerados pela instrumentação MobileConfig existente, com request_id/status HTTP/códigos/path quando esses campos estiverem disponíveis e permitidos no diagnóstico. Não captura nem decodifica o fluxo inteiro por conta própria.
- Sequência monotônica, uptime em milissegundos, capacidade 256, contador de eventos descartados por contenção.

## Comportamento / performance

- `fbt_native_trace_enabled` tem default OFF. Não há thread de polling nem hook novo no launch.
- O ring buffer C++ usa `try_lock`; se houver contenção, descarta o evento em vez de bloquear a aplicação. As gravações não alocam memória dinâmica nem fazem I/O.
- A leitura de preferências só acontece no startup ou quando uma preferência muda.
- `Observar` persiste apenas o target Objective-C exato (`source=observe`), não uma força de valor. Classes ainda ausentes ficam pendentes para retry direcionado.
- Seletores suportados pelo browser são Objective-C sem argumentos além de `self/_cmd` e retorno BOOL (`B` ou `c`). Outros ABIs não devem ser tratados como BOOL.
- O registro em memória é perdido ao encerrar o processo; exporte o JSON antes de reiniciar o aplicativo.

## Limitações

Isso **não equivale a todo o Frida**: sem motor JavaScript, trampolines ARM64 inline arbitrários, substituição de função C/C++ desconhecida ou injeção de bibliotecas no processo. `original` é o retorno do IMP anterior na cadeia para o hook *específico* da FBTweak; pode conter alterações feitas por outros hooks. O backend Substrate/Logos continua necessário para hooks ObjC no ambiente sideloaded configurado.

O objetivo é observar o comportamento do aplicativo sem repetir o crash de inicialização `brk #1337` do Gadget. Não alegar que isso conserta QE-info HTTP 400 ou autoriza uma conta employee.

## Validação

```sh
clang++ -std=c++11 -pthread -Wall -Wextra -Werror tests/NativeTraceCoreTests.cpp -o /tmp/native-trace-test
/tmp/native-trace-test
python3 -m unittest discover -s tests -p 'test_native_trace_contract.py' -v
```

A compilação Theos e os testes reais no iPhone devem passar antes de considerar o componente validado.
