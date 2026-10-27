# Persistência do employee local ao ler o getter

Com `fbt_employee_enabled` ligado, `FBUserPreferences.isEmployee` agora lê o valor original e, se falso, chama `setEmployee:YES` no mesmo objeto antes de devolver true. O setter já existente encaminha a gravação para a implementação nativa. Isso utiliza o escopo da conta escolhido pelo Facebook, sem abrir um domínio de preferências pelo nome, escrever no Keychain ou mudar tokens.

A decisão de leitura/gravação é serializada por objeto. Um guard por thread impede que uma leitura recursiva disparada durante o setter inicie outra gravação; ele é liberado em `@finally`, inclusive se o setter lançar uma exceção. Leituras posteriores deixam de gravar quando o getter original já retorna true. Uma nova instância/conta não depende de um marcador global de "já gravado".

Com o toggle desligado, o getter usa o comportamento original. A alteração não restaura artificialmente false: um true já persistido segue a política nativa e pode ser atualizado pelo fluxo de sessão. Não é acrescentado `synchronize` no hot path; a persistência/flush segue o setter nativo. O diagnóstico do getter conserva o retorno observado antes da gravação, separado do retorno efetivo forçado.

O teste `python3 -m unittest discover -s tests -p test_employee_preference_persistence.py -v` compila os corpos reais dos métodos do hook, substituindo somente `%orig` por métodos de armazenamento da fixture. Verifica persistência lida por outra instância, concorrência, contas separadas, toggle desligado, reentrada, recuperação após exceção e observação dos valores. Executa com Foundation no macOS; Substrate/Logos e as classes privadas do Facebook ainda exigem validação no aparelho. O build iOS continua sendo verificado pelo workflow existente.

O teste de regressão anterior à correção está no commit `5a799901b832e6ef3bc6a9a43e7fe80f8707de44`: cinco casos falharam por ausência da gravação e dois passaram. A mudança de preferência é local; não é evidência de autorização remota nem uma correção comprovada do OAuth #100.
