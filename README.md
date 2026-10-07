# Furor (prototype)

First-person shooter with an upgrade card deck, for 2 to 4 players (free-for-all, 2v2 with 4, or Duels),
inspired by Furor on Roblox. Made with Godot 4.7.2 and GDScript.

The game itself is in Brazilian Portuguese; button and card names below are written as they
appear in the game, with a translation where it helps.

## Download and play

Get `Furor.zip` from the [latest release](https://github.com/PedroRomeu/furor-prototipo/releases/latest),
extract it anywhere and run `Furor.exe`. Nothing to install. Windows may show "Windows
protected your PC" because the .exe is not signed: click **More info > Run anyway**.
Everyone playing together needs the **same version**.

## Open the project

1. Open Godot, click **Import**, pick the `furor_game` folder and confirm.
2. With the project open, press **F5**. The game starts at the main menu.

## Controls

Default keys; all of them (except mouse aim and Esc) can be changed in Settings, with up to
two keys per action.

| Key | Action |
|---|---|
| WASD / mouse | move / aim |
| Left click | shoot (one click per shot; hold only with the Metralhadora card) |
| E or right click | shield (reflects bullets) |
| Space | jump (short tap = low jump) |
| Ctrl | dash: on the ground while moving, a short burst of speed (hold to slide); in the air, a straight dash, once per jump |
| Shift | dash (without crouching) |
| C | crouch |
| R | reload |
| Q | master card ability (see the master cards below) |
| Tab (hold) | scoreboard: rounds, kills, assists and deaths, and everyone's cards (hover an icon to see its effect) |
| Enter | chat (online): Enter sends, Esc cancels |
| Dead, round still going | click: watch the next living player; E (or right click): free camera (WASD, Space up, Ctrl down) |
| Esc | pause menu (resume, settings, quit); against bots the game pauses |

**Personalizar** (customize, from the menu or the lobby): pick your character (12) and gun
(5 pistols and small guns). The model is shown in the middle; drag to rotate. Cosmetic only;
in the lobby the others see it right away.

Taking damage: a red arc around the crosshair points to where the shot came from and the
screen edges flash red. At low health the edges pulse softly.

Crosshair: the arc on the right shows the bullets left in the magazine (spent ones fade,
the last one turns orange). While reloading, the crosshair becomes a ring that closes when
the reload ends.

HUD: bottom left, your master card in a frame (it darkens while recharging and shows its
key), your health with armor below it, and the shield and dash icons, which fill up while
they recharge. Bottom right, the ammo. Status effects (slowed, frozen, speed boost...)
show as small tags above your health.

Movement tips: a jump goes up about 2.3 m. Against a wall you can jump off it twice before
landing: holding toward the wall climbs it (about 7 m); holding away jumps far. Jumping
right after a slide keeps the speed, and you can turn in the air without losing momentum.
An air dash while holding Ctrl lands already sliding. Jumping at a wall while holding W
climbs the ledge (up to 2.2 m above your feet): crates work as steps to the upper floors.

Settings (main menu and Esc in a match), split into Perfil (profile), Vídeo, Áudio,
Controles and Créditos: display mode (window, borderless fullscreen, fullscreen), window
size (the game always renders at the real window size, so maximizing stays sharp;
fullscreen uses the monitor resolution), interface size (100%, 125%, 150%), graphics
quality (Low, Medium, High), graphics API (Compatibility/OpenGL, Vulkan, DirectX 12), FPS
counter, VSync, your name (what friends see online; can also be changed
in the lobby), volume (Master, Effects, Interface, Music; releasing a slider plays a
sample), mouse sensitivity and key rebinding (click a key and press the new one; right
click clears it). On an Intel HD GPU, High runs at ~14 FPS; Medium and Low at 45-60.

For weak PCs: in fullscreen the resolution can be lowered (the game renders smaller and
stretches to the monitor; about 25% faster at 1280 x 720 on an Intel HD at 1080p), VSync
can be turned off (with it on, a frame that misses 60 FPS drops straight to 30), and Low
quality draws a flat sky.

The graphics API is applied on restart through an `override.cfg` file next to the game.
If the PC lacks the chosen API, Godot falls back to OpenGL by itself. If the game ever
fails to start after switching, delete `override.cfg` next to `Furor.exe`.

## Building the release

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Windows Desktop" build/Furor/Furor.exe
```

This makes a single `Furor.exe` (the whole game is embedded). Zip the `build/Furor` folder
(with its `LEIA-ME.txt`, the in-game readme) and attach it to a GitHub release. From the
editor: Project > Export > Windows Desktop > Export Project.

## Playing with friends

1. One player opens **Jogar > Online > Criar sala** (Play > Online > Create room). The
   lobby shows their IP and who has joined.
2. The others open **Jogar > Online**, type that IP and click **Entrar** (Join).
3. The host clicks **Começar** (Start) whenever they want: the match is played with whoever
   is in the lobby (2 to 4 players, free-for-all). With 4, **2x2** can be picked under
   Formato: the lobby becomes Blue Team and Red Team, the host moves people between teams
   (or clicks **Sortear times** to shuffle) and it only starts with 2 on each side.
   In the lobby everyone can change their name and look (applied right away for everyone),
   switch the equipped deck or click **Editar** to edit it without leaving; if the match
   starts while you edit, it opens by itself. The chat sits below the player list and
   carries on into the match (Enter opens it). Each name shows in that player's color.
4. The first time a lobby is created, Windows asks whether to allow the game through the
   firewall: allow it (also tick "public networks" when using a VPN).

**Same house (same Wi-Fi or router):** works directly with the IP shown in the lobby
(something like `192.168.0.10`).

**Different houses:** the internet doesn't let one PC connect straight to another. The
easiest way is a free gaming VPN that puts both PCs on the same virtual network:
- **Radmin VPN** (Windows): one creates a network, the other joins with name and password.
  Use the IP Radmin shows (starts with `26.`).
- **Tailscale** or **ZeroTier** work the same way.
- Without a VPN: forward **UDP port 7777** on the host's router and have friends use the
  public IP. More work, and it depends on the router.

How it works inside: each PC simulates its own player; whoever gets shot decides whether
they reflected it or took damage (their screen shows the bullet arriving, so the shield
counts exactly when they press E); the host decides map, cards, score and end. "5 more
rounds" only continues if everyone votes to continue. If someone's connection drops,
everyone goes back to the menu.

## Game modes

Picked on mode cards in Treino (practice) and, by the host, in the lobby. The current mode
shows in a corner during the match.

- **Cada um por si** (free-for-all), 2 to 4 players: last one standing wins the round.
- **2x2**, exactly 4 players (practice: you and an allied bot against two bots): the team
  with someone standing wins.
- **Duelos** (duels), 2 to 4 players: 1v1 in rotation with lives (3, 5 or 7). The first two
  in the queue fight; the winner stays and the loser loses a life and goes to the back of the
  queue. The loser picks 1 of 3 cards, or 1 of 4 on their last life. Out of lives, you're
  out; the last one with lives wins. Whoever is waiting watches (follow a duelist or free
  camera).

## Match rules

- Decks of 30 to 50 cards, up to 3 copies each. More copies = more chance of the card
  showing up. With 105 cards there are always some left out.
- **Baralhos** (decks) screen: create as many named decks as you want, starting from a
  template (Equilibrado, Atirador, Muralha, Acrobata, Caos, Aleatório or Vazio). The editor
  has the card collection on the left and your deck on the right. Click a card to add it,
  right click to remove (or click it in the deck list); search, pick a group, or open
  **Filtros** for archetype (Ricochete, Explosão, Nuke, Espelho, Tanque...: cards that combine
  well; a card can be in several), rarity and "only cards in the deck". The master card sits
  in its own slot; click it to choose another. The **equipped** deck is the one used in
  matches.
- **Master card**: each deck has one, picked in its own slot in the editor, outside the
  card count. You start every match with it. New in 0.5.0: **Caos** (Bullets: draws a
  random master; an active one is used once and 8 s after its effect ends another comes, a
  passive one lasts 15 s), **Prisão de Gelo** (Shield, Q: an ice shard that traps the target
  in a sliding ice block for 3 s; they take no damage, but shots, explosions and bodies push
  the block), **Mega Tapa** (Body, Q: a short slap that launches far; hitting a wall deals 20
  more and dazes), **Canhão Arcano** (Weapon, Q: charge 1 s, then a 2.5 s beam through walls
  that you aim slowly; each touch deals 22 and throws the target out of the beam),
  **Plataformas Suspensas** (Movement, Q in the air: platforms under your feet as you jump,
  up to 4, 5 s each, anyone can stand on them), **Chuva de Meteoros** (Bullets, Q: the next
  3 shots mark the ground; 1.5 s later a meteor falls on each mark), **Foguete** (Weapon, Q:
  ride a slow, hard-to-steer rocket that explodes on impact; Q again to jump off and send it
  flying fast) and **Gancho** (Body, Q: a hook that pulls the enemy to you and holds them as
  a human shield; click to throw them: a wall hurts them, another enemy hurts and dazes both). Also: **Espada** (Weapon, Q: a big
  sword for 8 s with a 3-hit combo: slash right, slash left and a lunging thrust; a raised
  shield blocks it), **Sniper** (Weapon, Q: a sniper with ONE laser shot
  that goes through every wall and deals 4x damage; right click to aim with the scope),
  **Bazuca** (Weapon, Q: 6 s of
  bazooka, 3 rockets), **Perfurante** (Bullets, Q: 3 straight fast shots that go through
  walls), **Bastião** (Shield, Q: a wall that returns bullets for 4 s), **Último Suspiro**
  (Body: a fatal hit leaves you at 1 health for 3 s; get a kill in that time and come back
  with half), **Camuflagem** (Body: stand still 0.6 s to vanish, crouch-walk while hidden;
  showing up after 1 s hidden gives Ambush, 3 s of +40% shot damage and +20% speed),
  **Corrente** (Movement, Q: an 8 m upward boost, also in the air), **Bota Foguete**
  (Movement: +10% shot damage per second in the air, up to +40%; with no air jumps left,
  hold jump for a short rocket burst, refilled on landing) and **Formiga** (Movement, Q:
  6 s at 40% size and +60% speed; Q again to grow back early; growing back knocks away
  and hurts whoever is within 4 m).
- Shooting: 4 bullets per magazine, 25 damage (4 hits kill), visible bullets that drop
  with distance. Aim a bit higher from afar. Reflected bullets fly straight. A bullet's size
  grows with its damage, also mid-flight (Bola de Neve, Tabelinha): huge bullets are
  possible, and every bounce gives the bullet 2 more seconds of life (up to 12 bounces), so
  a "nuke" shot at the sky can keep growing. A bullet that already bounced off a wall can
  hit its shooter. Explosions start at the bullet's edge: bigger bullets explode bigger.
- Shield (E): every card that improves it adds to its cooldown (+1 s for strong effects,
  +0.5 s for weak ones); Reflexos, Defensor, Passo Ligeiro and Escudo de Papel lower it.
- Your character gets a bit bigger with more max health and smaller with less, and the
  camera height follows.
- At the start, everyone sees 3 different cards from their own deck and keeps 1.
- Round: last one standing wins. Only **the losers** pick another card (1 of 3); with more
  than 2 players, everyone who died.
- **2x2** (online with 4, or in Treino with 3 bots: you and an allied bot): the team with
  someone standing wins, and both losers pick a card. Bullets and explosions pass through
  your teammate, except when an enemy Gancho holds them: then they lose the outline and your
  shots hit them. Your teammate has a team-colored outline and an arrow over their name,
  visible through walls, with their health under the name; the team score is at the top.
  **Downed:** if you take a fatal hit while your teammate is still standing, you go down
  instead of dying. You crawl slowly and can't shoot, and nobody can finish you off. Your
  teammate revives you by staying inside the circle around you for 3 s (they can shoot
  meanwhile); you get up with 30% health. You have 10 s to be revived, then 6 s on the
  second fall in the same round and 3 s after that. Downed counts as out for the round.
  When dead you watch your teammate (or use the free camera) until the round ends.
- Cards never leave the deck: you can pick the same one several times and the effects
  stack. A few (Adrenalina, Radar, Fênix...) can only be picked once.
- Every 5 rounds the game asks: 5 more rounds or finish (online, everyone's vote shows
  live). Most rounds wins. The match ends on a final scoreboard with everyone's cards;
  online, **Voltar à sala** takes you back to the lobby to play again.
- Each round rolls a new arena from one of 12 maps: 4 styles (Pátio, Ruínas, Torres and
  Fábrica) in 3 sizes (small, medium, large), plus one of 6 color ambiences. Medium and
  large maps have proportionally more pieces; large maps add tall dividing walls with
  passages so fights in different corners don't see each other. Each piece repeats rotated
  around the center, once per player (2 to 4 identical sides). Arenas have height:
  platforms with a second floor, floating slabs, jump pads.
- Online, the host turns maps on and off in the lobby ("Mapas"). Untouched maps follow an
  automatic rule: large maps are off with 2 players in the arena (1v1 and Duels), on with
  3 or 4. In Treino the bot count decides: 1 bot small only, 2 bots small and medium,
  3 bots all sizes.
- Map items (not every map, one of each per player; a ring on the ground marks where each
  comes back): **pink ">>" orb** (+30% speed for 4 s; 15 s), **green up-arrow orb** floating
  low in open spots (launches you about 6 m up and gives back dash, air jumps and boots;
  8 s), **green cross** (30 health; 25 s) and, rarer, **blue shield** (25 armor, up to 50,
  absorbs damage before health and resets every round; 30 s).
- **Void**: some maps have no edge walls and some have holes. Below (1 m under the floor)
  is the purple void: falling in bounces you and costs 15 health. The bounce is low and
  short, so far from the edge it takes several (each one hurts). With the **shield (E) up
  as you hit it**, you lose no health and bounce high. Whoever pushed you in the last 4 s
  gets credit for the damage.
- Practice: Jogar > Treino, against 1, 2 or 3 bots, on **Fácil**, **Médio** or **Difícil**
  (easy bots aim and react slower and only block bullets they see coming).

All numbers are provisional, to be tuned by playing.

## Cards

105 cards in 5 groups: **Arma** (weapon: fire rate, magazine, shotgun, burst...), **Balas**
(bullets: ricochet, homing, explosive, poison, freezing, a toxic cloud or a short black hole
where the bullet lands...), **Escudo** (shield: what happens when raising it or reflecting;
Pancada, Escudo Duplo, Couraça and Fortaleza make a close-range shield build, and Serra,
Chamas, Geada and Mina add a spinning saw, a ring of fire, a frost wave or a mine), **Corpo**
(body: health, size, Fênix, Radar, Blindado against explosions, Peso Pesado against
knockback, Segunda Pele and Casca Dura...) and **Movimento** (movement: double jump, extra air
dash, longer dash, Dash Duplo, Esquiva, Atropelar, Planador, Parkour, Pisão to bounce on
heads...), for those who prefer mobility over damage. Furor has no public card list; the ideas come from
two similar games: OVERKILL (Roblox) and ROUNDS (Landfall), where "the loser picks a card"
comes from.

A card is a list of modifiers on `BASE_STATS` (in `player.gd`): `"add"` adds, `"mul"`
multiplies. Example: `{"stat": "damage", "mul": 1.35}` is +35% damage. A card that only
changes numbers just needs an entry in `CARDS` (`card_db.gd`). A card with a new effect
needs a new attribute in `BASE_STATS` and the code that uses it.

## Where things are

| File | Contents |
|---|---|
| `scripts/autoload/card_db.gd` | All cards, deck size, attribute limits. |
| `scripts/autoload/game_state.gd` | Settings (keys, volume, video, look), saved decks. |
| `scripts/autoload/net.gd` | Networking: hosting, joining, lobby, chat, who is ready. |
| `scripts/player.gd` | Base attributes, movement (constants at the top), shooting, shield, effects, skins. |
| `scripts/bullet.gd` | Projectile: reflection, ricochet, explosion, poison etc. |
| `scripts/bot_brain.gd` | Bot AI. `LEVELS` at the top holds the Easy, Medium and Hard numbers. |
| `scripts/match.gd` | Match flow: picks, countdown, round, 5-round blocks, end. |
| `scripts/spectator.gd` | Camera when dead: follow a living player or fly freely. |
| `scripts/arena/` | Arena generator, color themes, moving pieces, jump pads, map items. |
| `scripts/meteor_strike.gd`, `sky_platform.gd` | Chuva de Meteoros meteor, Plataformas Suspensas platform. |
| `scripts/ui/` | HUD (`vitals.gd` for the health, master card and ability corner), kill feed, chat, damage feedback, scoreboard, pick screen, menu, settings, customization preview, deck screens and the shared look (`ui_style.gd`). |
| `scripts/sfx.gd`, `effects.gd`, `aim_arm.gd` | Sounds, visual effects, arm pointing at the aim. |
| `assets/` | Kenney models and sounds (CC0; licenses in each folder). Card icons in `assets/card_icons`, from game-icons.net (CC BY 3.0: credit required, authors listed in that folder's `LICENSE.txt` and in Settings). Character and gun thumbnails in `assets/skins` and `assets/gun_skins`. |

## Headless test

Runs a 10-round bot-vs-bot match (including the round-5 vote) and prints picks, maps,
reflections, score and a CPU timing summary:

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://scenes/match.tscn -- --autotest
```

Options: `--bots=2` or `--bots=3`, `--2x2` (with 3 bots), `--dificuldade=facil|medio|dificil`
(Hard by default), `--cartas=a,b,c` (gives those cards
to everyone), `--mestra=<id>`, `--tema=<n>`, `--nome=<name>`, `--visual=<skin>,<gun>`.
Network test on one machine (one terminal per player, a bot in each; `--host` starts with 1
guest, `--host3` waits for 2 and `--host4` for 3, each with its own `--join`):

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . -- --autotest --host
Godot_v4.7.2-stable_win64_console.exe --headless --path . -- --autotest --join
```

## Next steps

1. A release focused on performance: frame spikes in busy fights and at round start, one
   suspect at a time, and the cost of huge bullets on weak GPUs.
2. Card balancing and new cards.
3. Footstep, landing and slide sounds.
4. Progression: start with some cards and earn the rest from purchases or chests, with
   rarity tokens (common to mythic) from recycling duplicates. Today everyone has every card
   and rarity is only a label.
