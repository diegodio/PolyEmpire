# PolyEmpire

RTS inspirado em Age of Empires II, feito em **Flutter + Flame**, com mapa
isométrico quadriculado (tabuleiro estilo xadrez/campo minado) e visual **low poly**
(todos os modelos são polígonos com sombreamento plano desenhados no Canvas — sem
assets externos).

## Funcionalidades

- **Mapa** 64×64 gerado proceduralmente: grama, terra, areia, lagos, florestas,
  minas de ouro/pedra e arbustos de frutas. Seed aleatória a cada partida.
- **Exploração / névoa de guerra**: tiles inexplorados aparecem como casas
  "fechadas" de campo minado; áreas exploradas fora da visão ficam escurecidas.
- **Recursos (iguais ao AoE2)**: Comida, Madeira, Ouro e Pedra. Aldeões coletam e
  levam ao Centro da Cidade ou aos campos de depósito (Moinho, Campo de Lenhador,
  Campo de Mineração). Fazendas são replantadas automaticamente.
- **Prédios**: Centro da Cidade, Casa, Moinho, Campo de Lenhador, Campo de
  Mineração, Fazenda, Quartel, Campo de Arqueiros, Estábulo, Ferraria, Mercado
  (compra/venda), Torre de Vigia e Castelo.
- **Unidades**: Aldeão, Milícia, Lanceiro, Arqueiro, Escaramuçador, Batedor e
  Cavaleiro, com linhas de melhoria (Homem de Armas → Espadachim Longo, Piqueiro,
  Besteiro, Cavalaria Leve, Cavaleiro Nobre...).
- **4 Idades** (Trevas → Feudal → Castelos → Imperial) e ~30 tecnologias
  (Tear, Carrinho de Mão, Machado de Duas Lâminas, Coleira de Cavalo, Forja,
  Emplumação, Cota de Escamas, Linhagem, Anel de Polegar...).
- **Combate**: ataque corpo a corpo e à distância (flechas), armadura
  corpo-a-corpo/perfurante, bônus (lanceiro × cavalaria, escaramuçador ×
  arqueiro), torres/CC/castelos atiram flechas.
- **IA inimiga** com 3 dificuldades: desenvolve economia, constrói, pesquisa,
  avança de idade, defende a base e manda ondas de ataque.
- HUD com recursos, população, minimapa isométrico, fila de produção,
  alertas de ataque, velocidade 1×/2×/3× e pausa.

## Controles

| Ação | Mouse/teclado | Toque |
| --- | --- | --- |
| Selecionar | clique esquerdo / arrastar caixa | toque / botão "seleção em área" + arrastar |
| Ordem (mover, coletar, construir, atacar) | clique direito | toque no alvo com unidades selecionadas |
| Câmera | WASD/setas, arrastar com botão direito/meio | arrastar |
| Zoom | roda do mouse | pinça |
| Atalhos | H = Centro da Cidade, `.` = aldeão ocioso, ESC, Del, Espaço = pausa | botões laterais |

Shift + clique adiciona à seleção / mantém o modo de construção.

## Rodando

```bash
flutter pub get
flutter run -d chrome     # ou: -d linux / -d windows / -d macos / android / ios
flutter test              # testes de simulação (IA, pathfinding)
```

Parâmetros de URL (web) para depuração: `?seed=42` fixa o mapa, `?reveal=1`
remove a névoa e `?skip=600` simula 600 s antes de mostrar o jogo.

## Estrutura

```
lib/
  main.dart                 app, menu, entrada (toque/mouse/teclado)
  game/
    config.dart             dados: recursos, idades, unidades, prédios, techs
    entities.dart           Unit, Building, ResourceNode, Projectile, Effect
    player.dart             estado do jogador, custos e stats com tecnologias
    game_map.dart           grid, geração procedural, A* (8 direções)
    world.dart              simulação: economia, construção, combate, névoa
    ai.dart                 IA inimiga
    iso.dart                projeção isométrica e primitivas low poly
    renderer.dart           desenho do terreno, entidades e efeitos
    poly_empire_game.dart   FlameGame: câmera, seleção, comandos
  ui/
    hud.dart, minimap.dart  interface
```
