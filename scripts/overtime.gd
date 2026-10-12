class_name Overtime
extends RefCounted
## Prorrogação (2026-10-12, pedido do usuário, como a zona que fecha no Furor; tempos dele):
## rodada que passa de CARDS_AT dá a cada jogador vivo uma carta comum do próprio baralho a
## cada CARD_EVERY (até MAX_CARDS, valem até o fim da rodada); em ZONE_AT um círculo de vidro
## em volta do centro começa a fechar, de start_radius até ZONE_MIN em ZONE_TIME, e fora dele
## leva dano (Player.ZONE_*). Contado pelo tempo de luta de cada máquina (começa no fim da
## contagem, para com a pausa contra bots); a diferença entre máquinas é a do atraso da rede.
## Na sala de teste não acontece.

const CARDS_AT := 480.0     # 8:00
const CARD_EVERY := 10.0
const MAX_CARDS := 20
const ZONE_AT := 600.0      # 10:00
const ZONE_TIME := 120.0    # fechado aos 12:00
const ZONE_MIN := 8.0
const WARN := 30.0          # aviso antes das cartas e do fechamento
const COUNTDOWN := 10       # últimos segundos em contagem grande, com bipe


## Cartas que já deviam ter saído com t segundos de luta.
static func cards_due(t: float) -> int:
	if t < CARDS_AT:
		return 0
	return mini(MAX_CARDS, int((t - CARDS_AT) / CARD_EVERY) + 1)


## Segundos até a próxima carta (-1 sem mais nenhuma).
static func next_card_in(t: float) -> float:
	var n := cards_due(t)
	if n >= MAX_CARDS:
		return -1.0
	return CARDS_AT + n * CARD_EVERY - t


## Raio do círculo no começo: cobre as quinas da arena quadrada (lado 2 x half).
static func start_radius(half: float) -> float:
	return half * sqrt(2.0) + 1.0


## Raio com t segundos de luta (INF antes de começar a fechar).
static func zone_radius(t: float, half: float) -> float:
	if t < ZONE_AT:
		return INF
	var k := clampf((t - ZONE_AT) / ZONE_TIME, 0.0, 1.0)
	return lerpf(start_radius(half), ZONE_MIN, k)
