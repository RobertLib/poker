# ASO: the reasoning, the competition, and the alternatives

Numbers in brackets are character counts. The limits are 30 for the name, 30 for
the subtitle and 100 for keywords.

## What we are up against

Every one of these was looked at on the store before the copy in this directory
was written. The pattern is consistent enough to plan around.

| App | Subtitle | Category | Rating | Money |
|---|---|---|---|---|
| All-In Hold'Em - Offline Poker | Omaha Razz Stud Texas Holdem | Card | 18+ | Free + IAP |
| Offline Poker - Texas Holdem | No-Wait No-Limit Poker | Card | 18+ | Free + IAP ($0.99–$49.99 chip packs) |
| Holdem or Foldem: Texas Poker | Texas Holdem Poker Games | Casino | 18+ | Free + IAP |
| Learn Poker Offline - Hold 'Em | Fast poker offline with bots | Casino | 18+ | Free |
| Poker World - Offline Poker | — | Casino | 18+ | Free + IAP |

Three things follow from that table.

**We cannot win the head terms.** "poker" and "texas holdem" are contested by
apps with years of downloads and a marketing budget. A new app with no ratings
does not rank on them, whatever it puts in its name. Chasing them is how you end
up with no traffic at all.

**The long tail is winnable, and it is where the intent is.** Someone typing
*poker no wifi*, *single player poker*, *poker vs computer* or *poker offline no
ads* knows exactly what they want, and it is exactly this app. Those queries are
thin enough to rank on. The keyword sets are built for them rather than for
volume.

**"No ads, no purchases" is the whole differentiator.** Every competitor above
sells chips, and the reviews on all of them say the same thing about it. That is
why the promise is in the subtitle (where it is read in the search results, not
just in the listing), in the caption on the last screenshot, and in the first
paragraph of the description. It is a conversion lever as much as a keyword.

## What is in use

```
en-US   Ace High: Offline Texas Poker   (29)   Holdem vs. smart bots, no ads   (29)
en-GB   Ace High: Offline Texas Poker   (29)   No-Limit Holdem, no ads ever    (28)
cs      Ace High: Poker Texas Holdem    (28)   Offline, bez reklam, proti AI   (29)
```

Between the name and the subtitle, `en-US` indexes *ace, high, offline, texas,
poker, holdem, vs, smart, bots, no, ads* — and because Apple combines terms
within a locale, that assembles *offline texas holdem*, *texas holdem poker*,
*poker bots*, *no ads poker* and so on without spending a single keyword
character on any of them.

The Czech name drops *offline* (the subtitle carries it) to fit *holdem*, because
Czech players type the English name of the game — which is also why the app's own
Czech interface leaves *Check*, *Flop*, *Turn*, *River*, *Pot* and *All-in* in
English.

## App name

| Czech | | English | |
|---|---|---|---|
| Ace High: Poker Texas Holdem | (28) | Ace High: Offline Texas Poker | (29) |
| Ace High: Poker offline | (23) | Ace High: Offline Poker | (23) |
| Ace High: Texas Holdem Poker | (28) | Ace High: Texas Holdem Poker | (28) |
| Ace High: Poker proti AI | (24) | Ace High: Single Player Poker | (29) |
| Ace High — kapesní poker | (24) | Ace High: Pocket Hold'em | (24) |

Recommendation: keep *offline* in the name somewhere. It is the one head-ish term
this app can compete on, because most of the apps that rank for it are lying —
they need a connection for their chip store — and it is the word the target
player actually types. `Ace High: Offline Poker` (23) is the cleaner-reading
fallback if `Offline Texas Poker` ever feels like a list.

## Subtitle

| Czech | | English | |
|---|---|---|---|
| Offline, bez reklam, proti AI | (29) | Holdem vs. smart bots, no ads | (29) |
| Offline poker proti počítači | (28) | No-Limit Holdem, no ads ever | (28) |
| Bez reklam, bez nákupů, offline | (31 ✗) | Holdem tournaments, no ads | (26) |
| Turnaj proti šesti soupeřům | (27) | Beat six bots, one chip stack | (29) |
| Poker bez internetu a reklam | (28) | Single-player Holdem, no ads | (28) |

## Keywords

In use:

```
en-US  free,cards,game,tournament,solo,single,player,ai,computer,wifi,internet,practice,odds,chips  (91)
en-GB  free,cards,game,tournament,solo,single,player,bots,computer,wifi,internet,practice,odds,heads,up (96)
cs     karty,karetní,hry,zdarma,počítači,botům,turnaj,internetu,wifi,nákupů,trénink,pravidla,strategie (95)
```

`en-GB` deliberately overlaps `en-US` rather than filling in its gaps. It is the
second index in the Czech storefront, but it is the *only* index in the UK,
Ireland, Australia and New Zealand — and those are worth far more than Czechia's
second slot, so it gets the strong set rather than the leftovers. The three terms
it swaps (*bots* and *heads up* for *ai* and *chips*) are the Czech bonus.

Alternative sets, if you end up tuning by performance:

```
# EN, learn-to-play angle (pairs with a "Learn Texas Hold'em" subtitle)
learn,teach,beginner,rules,rankings,hands,odds,practice,trainer,study,guide,free,cards,solo   (92)

# EN, tournament / skill angle
tournament,sitngo,mtt,nolimit,nlhe,bankroll,heads,up,skill,bots,ai,solo,single,player,free    (91)

# EN, no-freemium angle (leans hardest on the differentiator)
free,noads,nowifi,nointernet,purchases,premium,paid,cards,game,solo,single,player,ai,bots     (91)

# CZ, klidná hra / relax angle
karty,karetní,hry,zdarma,relax,jednoduchá,klidná,offline,počítači,botům,trénink,nákupů        (91)

# CZ, výzva a pravidla angle
karty,karetní,hry,turnaj,výzva,těžká,pravidla,strategie,kombinace,šance,počítači,trénink      (91)
```

Rules, so that editing does not break it:

- Separate with a comma and **no space after the comma** — a space counts towards
  the limit of 100.
- Do not repeat words from the name or the subtitle, Apple indexes those
  separately.
- Do not put a plural next to its singular ("card" and "cards"), Apple pairs them
  itself. This is the one rule the Czech set bends — Apple's Czech stemming is
  unreliable enough that *hry* and *karetní* are both worth their characters.
- Do not name competing games — grounds for rejection.
- The word "zdarma"/"free" is only worth using if the game really is free (it is,
  and with no purchases either, which is rarer and worth the space).

## Shorter description, if you decide on a terser version

**EN**

```
Real No-Limit Texas Hold'em, offline. Up to five AI opponents, each with their
own tightness, aggression and bluffing, in a tournament that ends when somebody
owns every chip.

Every rule implemented properly: minimum raises, incomplete all-ins, a side pot
for every short stack, split pots, dead button and dead small blind. Optional
win-probability readout, four-color deck, four table felts, three difficulties.

It saves itself between hands, so a hand on the train costs nothing to abandon.

No ads. No in-app purchases. No account. No internet. Play money only.
```

**CZ**

```
Opravdový No-Limit Texas Hold'em, offline. Až pět AI soupeřů, každý s vlastní
mírou těsnosti, agresivity a blafování, v turnaji, který skončí, až bude mít
někdo všechny žetony.

Všechna pravidla naprogramovaná správně: minimální navýšení, neúplné all-iny,
side pot pro každý krátký stack, dělené poty, dead button i dead small blind.
Volitelná šance na výhru, čtyřbarevné karty, čtyři sukna, tři obtížnosti.

Ukládá se mezi rozdáními, takže rozehrané rozdání ve vlaku nic nestojí.

Bez reklam. Bez nákupů. Bez účtu. Bez internetu. Jen o herní žetony.
```
