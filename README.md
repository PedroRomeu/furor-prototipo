# Furor (protótipo)

FPS com baralho de melhorias, de 2 a 4 jogadores (cada um por si, ou 2x2 com 4), inspirado no Furor do Roblox.
Godot 4.7.2, GDScript.

## Como abrir

1. Abra o Godot, clique em **Importar**, escolha a pasta `furor_game` e confirme.
2. Com o projeto aberto, aperte **F5**. O jogo abre no menu.

## Controles

Teclas padrão; todas (menos o mouse para mirar e o Esc) podem ser trocadas em
Configurações, com até duas teclas por ação.

| Tecla | Ação |
|---|---|
| WASD / mouse | andar / mirar |
| Clique esquerdo | atirar (um clique por tiro; com a carta Metralhadora, segure) |
| E ou clique direito | escudo (reflete balas) |
| Espaço | pular (toque curto = pulo baixo) |
| Ctrl | dash: no chão, andando, um tiro curto de velocidade (segurando, vira deslize); no ar, uma corridinha reta, uma vez por pulo |
| Shift | dash (sem agachar) |
| C | agachar |
| R | recarregar |
| Q | habilidade da carta mestra (Corrente, Bazuca, Bastião, Perfurante) |
| Tab (segurar) | placar: rodadas, abates, assistências e mortes de cada um, e as cartas de todos (passe o mouse num ícone para ver o efeito) |
| Enter | chat (online): Enter manda, Esc cancela |
| Morto, com a rodada rolando | clique: assistir o próximo vivo; E (ou botão direito): câmera livre (WASD, Espaço sobe, Ctrl desce) |
| Esc | menu de pausa (continuar, configurações, sair); contra bots o jogo para |

**Personalizar** (no menu ou na sala): escolha o personagem (12) e a arma (5 pistolas e armas
pequenas). O modelo aparece no centro; arraste para girar. Só aparência, não muda nada no
jogo; na sala os outros veem na hora.

Levou dano: um arco vermelho em volta da mira aponta de onde veio o tiro e as bordas da
tela avermelham por um instante. Com pouca vida, as bordas pulsam de leve.

Na mira: o arco à direita mostra as balas do pente (as gastas apagam; a última fica
laranja). Recarregando, a mira vira um anel que se fecha quando a recarga termina.

Dicas de movimento: o pulo sobe uns 2,3 m. Encostado num muro, dá para pular nele 2 vezes
antes de tocar o chão: segurando contra o muro, sobe rente a ele (escala uns 7 m);
segurando para o outro lado, salta longe. Pular logo depois de deslizar mantém a
velocidade, e no ar dá para virar sem perder embalo. Dash no ar segurando Ctrl pousa já
deslizando. Pulando contra um muro e segurando W, o personagem escala a beirada (até 2,2 m
acima dos pés): caixotes servem de degrau para os andares de cima.

Configurações (no menu e no Esc da partida), separadas em Perfil, Vídeo, Áudio, Controles e
Créditos: seu nome (o que os amigos veem online; também dá para mudar
dentro da sala), volume (Geral, Efeitos, Interface e Música; ao soltar a barra toca um
exemplo), sensibilidade do mouse, qualidade gráfica (Baixa, Média, Alta), contador
de FPS e troca de teclas (clique na tecla e aperte a nova; botão direito apaga). Num Intel HD a Alta roda a ~14 FPS; Média e Baixa, a 45-60.

## Versão para mandar aos amigos (sem instalar nada)

O arquivo `build/Furor.zip` tem a pasta `Furor` com um único `Furor.exe` (o jogo inteiro
vai dentro dele). Quem receber só extrai o zip em qualquer lugar e abre o `Furor.exe`.
O Windows pode avisar "O Windows protegeu o computador" porque o .exe não é assinado:
clicar em **Mais informações > Executar assim mesmo**. O zip passa do limite do Discord
grátis; mande por Google Drive, WeTransfer ou parecido.

Para gerar de novo depois de mudar o jogo:

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Windows Desktop" build/Furor/Furor.exe
```

e zipar a pasta `build/Furor`. Pelo editor: Projeto > Exportar > Windows Desktop > Exportar Projeto.
Todos precisam da **mesma versão**: mudou o código, gere e mande o zip de novo.

## Jogar com amigos

1. Um abre **Jogar > Online > Criar sala**. A sala mostra o IP dele e quem já entrou.
2. Os outros abrem **Jogar > Online**, digitam esse IP e clicam em **Entrar**.
3. Quem criou a sala clica em **Começar** quando quiser: a partida é com quem estiver na
   sala (2 a 4 jogadores, cada um por si).
   Com 4, dá para escolher **2x2** em Formato: a sala vira Time Azul e Time Vermelho, quem
   criou a sala troca as pessoas de time (ou clica em **Sortear times**) e só começa com 2
   em cada lado.
   Na sala cada um troca o próprio nome (vale na hora para todos), troca o baralho equipado
   ou clica em **Editar** para mexer nele sem sair da sala; se a partida começar enquanto
   você edita, ela abre sozinha. Embaixo da lista de jogadores fica o chat, que continua
   na partida (Enter abre). Cada nome aparece na cor do jogador.
4. Na primeira vez que criar uma sala, o Windows pergunta se libera o Godot no firewall: libere
   (marque também "redes públicas" se for usar VPN).

**Na mesma casa (mesmo Wi-Fi ou roteador):** funciona direto com o IP que aparece no menu
(algo como `192.168.0.10`).

**Em casas diferentes:** a internet não deixa um PC entrar direto no outro. O jeito mais fácil
é uma VPN de jogos, gratuita, que coloca os dois PCs na mesma "rede de mentira":
- **Radmin VPN** (Windows): um cria uma rede, o outro entra com nome e senha. Use o IP
  que o Radmin mostra (começa com `26.`).
- **Tailscale** ou **ZeroTier** funcionam do mesmo jeito.
- Sem VPN: liberar a porta **UDP 7777** no roteador de quem hospeda (redirecionamento de
  porta) e o amigo usar o IP público. Dá mais trabalho e depende do roteador.

**Passar o jogo para o amigo:** o mais simples é ele instalar o Godot 4.7.2, receber a pasta
do projeto (zip ou GitHub) e abrir igual a você. Para mandar um .exe: no Godot, menu
Projeto > Exportar > Adicionar > Windows Desktop. Na primeira vez ele pede para baixar os
"export templates" (botão "Gerenciar modelos de exportação" > Baixar).

Como funciona por dentro: cada PC simula o próprio jogador; quem leva o tiro decide se
refletiu ou tomou dano (é a tela dele que mostra a bala chegando, então o escudo vale
exatamente quando ele aperta E); o host decide mapa, cartas, placar e fim. "Mais 5
rodadas" só continua se todos votarem para continuar. Se a conexão de alguém cair, todos
voltam ao menu.

## Regras da partida

- Baralho de 30 a 50 cartas, até 3 cópias de cada. Mais cópias = mais chance de a carta
  aparecer. Como há 88 cartas, sempre fica alguma de fora.
- Tela **Baralhos** (no menu): crie quantos baralhos quiser, com nome, começando de um
  modelo (Equilibrado, Atirador, Muralha, Acrobata, Caos, Aleatório ou Vazio). Clique numa
  carta para pôr, botão direito para tirar; filtros por grupo, por **arquétipo** (Ricochete, Explosão, Nuke, Espelho, Tanque...: as
cartas que combinam entre si; uma carta pode estar em vários) e busca. O baralho
  **equipado** é o usado nas partidas; dá para trocar também direto no menu.
- **Carta mestra**: cada baralho tem uma, escolhida no topo do editor, fora da contagem de
  cartas. Você começa toda partida com ela. Uma de cada grupo: **Bazuca** (Arma, Q: 6 s de
  bazuca, 3 foguetes), **Perfurante** (Balas, Q: 3 tiros retos e rápidos que atravessam paredes), **Bastião** (Escudo,
  Q: parede que devolve balas por 4 s), **Último Suspiro** (Corpo: o golpe fatal te deixa
  3 s com 1 de vida; abata alguém nesse tempo e volte com metade) e **Corrente**
  (Movimento, Q: impulso de 8 m para cima, também no ar).
- Tiro: 4 balas por pente, 34 de dano (3 acertos matam), bala visível que cai com a
  distância. De longe, mire um pouco acima. Bala refletida volta reta. O tamanho da bala
  cresce com o dano dela, também durante o voo (Bola de Neve, Tabelinha): dá para fazer
  balas enormes. Bala que já quicou numa parede pode acertar quem atirou.
- O personagem fica um pouco maior com mais vida máxima e menor com menos.
- No começo, todos veem 3 cartas diferentes do próprio baralho e ficam com 1.
- Rodada: ganha o último vivo. Só **quem perdeu** escolhe mais uma carta (1 de 3); com
  mais de 2 jogadores, todos os que morreram.
- **2x2** (online com 4, ou no Treino com 3 bots: você e um bot aliado): ganha o time com
  alguém de pé, e os dois do time que perdeu escolhem carta. Bala e explosão atravessam o
  parceiro. O parceiro tem contorno na cor do time e uma seta sobre o nome, visíveis através
  das paredes, com a vida embaixo do nome; no topo da tela fica o placar dos times. Morto, você assiste o parceiro até a rodada acabar.
- As cartas nunca saem do baralho: dá para pegar a mesma várias vezes e o efeito soma.
  Algumas (Adrenalina, Radar, Fênix...) só podem ser pegas uma vez.
- A cada 5 rodadas o jogo pergunta: mais 5 rodadas ou terminar. Ganha quem tiver mais rodadas.
- Cada rodada sorteia uma arena nova, em um de 4 estilos: Pátio, Ruínas, Torres e Fábrica.
  Cada peça se repete girada em volta do centro, uma vez por jogador (2 a 4 lados iguais).
  As arenas têm altura: plataformas com segundo andar, lajes suspensas, plataformas de salto.
- Itens no mapa (nem todo mapa tem, um de cada por jogador): **orbe roxo** no alto
  (devolve o dash no ar, zera a recarga do dash e dá um pulo no ar; volta em 6 s), **cruz
  verde** (30 de vida; volta em 25 s) e, mais raro, **colete amarelo** (25 de colete, até
  50, absorve dano antes da vida e zera a cada rodada; volta em 30 s).
- **Vazio**: alguns mapas não têm muros nas bordas e alguns têm buracos no chão. Lá
  embaixo (1 m abaixo do chão) fica o vazio roxo: quem cai quica e perde 20 de vida. O
  quique é baixo e curto, então longe da borda são vários (e cada um fere). Com o
  **escudo (E) de pé na hora de bater**, não perde vida e quica bem alto. Quem empurrou
  você nos 4 s antes leva o crédito do dano.
- Treino: Jogar > Treino, contra 1, 2 ou 3 bots.

Todos os números são provisórios, para ajustar jogando.

## As cartas

88 cartas em 5 grupos: **Arma** (cadência, pente, escopeta, rajada...), **Balas** (ricochete,
teleguiada, explosiva, veneno, congelante...), **Escudo** (o que acontece ao levantar ou ao
refletir; Pancada, Escudo Duplo, Couraça e Fortaleza montam um escudo de curta distância),
**Corpo** (vida, tamanho, Fênix, Radar...) e **Movimento** (pulo duplo, dash extra no ar,
dash mais longo, Esquiva, Atropelar, Planador...), para quem prefere mobilidade a dano.
O Furor não tem página pública com as cartas; as ideias vêm de dois jogos parecidos:
OVERKILL (Roblox) e ROUNDS (Landfall), de onde veio o "quem perde escolhe a carta".

Uma carta é uma lista de modificadores sobre `BASE_STATS` (em `player.gd`):
`"add"` soma, `"mul"` multiplica. Exemplo: `{"stat": "damage", "mul": 1.35}` é +35% de dano.
Carta nova que só mexe em número: basta uma entrada em `CARDS` (`card_db.gd`).
Carta com efeito novo: precisa de um atributo novo em `BASE_STATS` e do código que o usa.

## Onde mexer

| Arquivo | O que tem |
|---|---|
| `scripts/autoload/card_db.gd` | Todas as cartas, tamanho do baralho, limites dos atributos. |
| `scripts/autoload/game_state.gd` | Rodadas por bloco, teclas, baralho salvo. |
| `scripts/player.gd` | Atributos base, movimento (constantes no topo), tiro, escudo, efeitos. |
| `scripts/bullet.gd` | Projétil: reflexo, ricochete, explosão, veneno etc. |
| `scripts/bot_brain.gd` | IA do oponente. Constantes no topo ajustam a dificuldade. |
| `scripts/match.gd` | Fluxo da partida: compra, contagem, rodada, blocos de 5, fim. |
| `scripts/arena/arena.gd` | Gerador de arenas: estilos, tamanho, peças. |
| `scripts/arena/moving_body.gd` | Peças que se movem (muros deslizantes, barras giratórias, elevadores). |
| `scripts/arena/jump_pad.gd` | Plataforma de salto. |
| `scripts/arena/pickup.gd` | Itens do mapa (orbe de movimento, vida, colete). |
| `scripts/ui/` | HUD, tela de escolha, menu, tela de baralhos (`deck_list.gd`), editor de baralho e o visual comum (`ui_style.gd`). |
| `scripts/autoload/net.gd` | Conexão em rede: hospedar, entrar, quem está pronto. |
| `scripts/sfx.gd` | Sons. |
| `scripts/aim_arm.gd` | Levanta o braço do personagem na direção da mira. |
| `assets/` | Modelos e sons da Kenney (CC0, uso livre; licenças em cada pasta). Ícones das cartas em `assets/card_icons`, de game-icons.net (CC BY 3.0: exige crédito aos autores, listados no `LICENSE.txt` da pasta e na tela de Configurações). |

## Teste sem janela

Roda uma partida de 10 rodadas bot contra bot (passa pela pergunta da rodada 5) e imprime
as escolhas, os mapas, os reflexos e o placar:

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://scenes/match.tscn -- --autotest
```

Com mais bots: acrescente `--bots=2` ou `--bots=3`. Teste em rede na mesma máquina (um
terminal por jogador, um bot em cada; `--host` começa com 1 convidado, `--host3` espera 2 e
`--host4` espera 3, cada um com seu `--join`):

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . -- --autotest --host
Godot_v4.7.2-stable_win64_console.exe --headless --path . -- --autotest --join
```

## Próximos passos

1. Jogar de novo direto em rede (hoje volta ao menu e reconecta).
2. Sons de passos, pouso e deslize.
3. Usar a raridade das cartas (comum, rara, épica, lendária; mítica = mestras): hoje é só etiqueta.
4. Forma de ganhar cartas (hoje todos têm todas).
5. Escolher o personagem (há 12 modelos em `assets/characters`).
