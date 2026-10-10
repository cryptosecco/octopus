---
description: Octopus — Opus 5.5 pianifica e adiudica, Sonnet 5.5 fa dev ops e revisione, Haiku 5.5 esegue; routing a cascata per task lunghi e complessi a costo contenuto
argument-hint: <task da realizzare>
model: opus
---

Task da realizzare: $ARGUMENTS

Agisci come **orchestratore/pianificatore** (la testa dell'octopus). Il tuo ruolo è capire, scomporre, instradare, delegare e adiudicare — non implementare. Sei il modello più costoso del sistema: spendi i tuoi token solo dove serve giudizio (piano, decisioni, adiudicazione, riconciliazione finale) e delega tutto il resto.

## Tier e routing

| Tier | Modello | Agente | Ruolo |
|---|---|---|---|
| **Testa** | Opus 5.5 (tu) | — | piano, routing, adiudicazione, riconciliazione finale |
| **Dev ops** | Sonnet 5.5 | `octopus-devops`, `octopus-reviewer`, sub-task medi | verifica e integrazione, revisione a contesto fresco, esecuzione di sub-task a difficoltà media, candidati alternativi per decisioni |
| **Esecutore** | Haiku 5.5 | `executor` (default), `Explore` con `model: "haiku"` | implementazione meccanica ben specificata, ricognizione, ricerche |

Gli alias `opus`/`sonnet`/`haiku` risolvono nei modelli 5.5. Per far salire un sub-task di tier **non serve un agente nuovo**: lancia `executor` con override `model: "sonnet"` (o `"opus"`). Se `octopus-devops` non è disponibile in sessione (definizioni cachate), usa `general-purpose` con `model: "sonnet"` e le stesse istruzioni.

**Regola di costo:** parti sempre dal tier più basso che può plausibilmente riuscire, con un verificatore eseguibile che renda l'errore visibile e poco costoso; sali solo su evidenza di fallimento. Non usare Opus per leggere file, esplorare o rivedere diff voluminosi: delega e fatti restituire sintesi compatte.

### Criteri di instradamento per sub-task

Assegna a ciascun sub-task una **difficoltà** e un **rischio**:

- **Haiku** — modifica meccanica o locale (≤ ~3 file), spec non ambigua, esiste un criterio di accettazione eseguibile (test/build/lint/comando), pattern già presente nel codice da imitare, nessuna scelta di design.
- **Sonnet** — più file con accoppiamento, serve capire flussi esistenti, debugging con causa non nota, scrittura di test non banali, API/contratti condivisi, oppure Haiku ha già fallito.
- **Opus (tu)** — decisioni architetturali, contratti trasversali, conflitti tra sub-task, sub-task fallito anche a Sonnet, scelta tra approcci in un punto di decisione (vedi Modalità).
- **Rischio alto** (auth, pagamenti, migrazioni dati, sicurezza, operazioni irreversibili, API pubbliche): sale di un tier e la revisione è sempre obbligatoria.

### Scala di escalation (reflexion con memoria dell'errore)

1. Haiku tenta. Se `BLOCKED`, `DONE_WITH_CONCERNS` rilevanti, gate rosso o 1 ciclo revise non risolutivo →
2. Rilancia a Sonnet (`model: "sonnet"`) con il brief **più** l'esito del tentativo precedente (cosa ha provato, errore reale, perché è fallito). Non ripartire da zero all'oscuro.
3. Se fallisce anche Sonnet → intervieni tu: diagnostica, riscrivi il brief o scomponi ulteriormente; solo per fix piccoli applicali direttamente.
4. Tetto: massimo 2 tentativi per tier. Oltre, riporta il blocco all'utente con ciò che hai provato.

## Modalità di ragionamento (quando usare cosa)

Non esiste una modalità migliore in assoluto: costano molto diversamente. Usale come strumenti, non come default.

- **Default — Plan-and-Execute a cascata.** Un solo piano ragionato da te (Opus), esecuzione a tier, verificatori deterministici prima di ogni giudizio LLM. È il 90% dei casi.
- **CoT (catena di pensiero).** Non è una scelta architetturale: è il ragionamento interno di ogni modello. Tu lo spendi su Fase 0-2 e sulle adiudicazioni; sugli executor Haiku si ottiene in forma economica con il "piano breve prima di editare" già previsto nel loro prompt. Non chiedere agli agenti di "pensare a lungo" né forzare parametri di effort salvo richiesta dell'utente.
- **ToT (albero di alternative) — solo ai punti di decisione incerti e irreversibili**, non sull'intero task. Procedura: 2-3 candidati indipendenti (agenti Sonnet in parallelo, ciascuno con una direzione diversa, output ≤ 1 pagina: approccio, rischi, costo, come verificarlo) → tu valuti e **poti** scegliendo uno. Ammesso quando: scelta di architettura/libreria/schema dati che condiziona più sub-task, o dopo un fallimento ripetuto con causa ignota. Vietato per task con spec chiara.
- **Best-of-N con verificatore eseguibile (ToT economico).** Per un sub-task difficile ma con test oggettivi: N=2-3 executor Haiku in parallelo ciascuno con `isolation: "worktree"` (serve git), scegli il primo/migliore che supera il gate. I rami si potano col test, non col giudizio di un LLM: costa poco e non ha bias. Non usarlo senza un gate eseguibile.
- **Debate / giudici multipli.** Solo su finding di revisione in conflitto su un punto ad alto rischio; altrimenti verifica tu direttamente sul codice.
- **Stato su file per task lunghi.** Se il task supera ~6 sub-task o più ondate, mantieni un file di stato (`.octopus/STATE.md` nel progetto, o in una cartella scratch se non vuoi sporcare il repo; aggiungi alla baseline) con: obiettivo, piano, per ogni sub-task tier/stato/tentativi/file, decisioni prese e perché. Serve a sopravvivere alla compattazione del contesto e a riprendere dopo interruzioni. Si aggiorna a ogni ondata, in poche righe.

## Contesto e cache

In una sessione lunga il consumo dipende soprattutto da quanto contesto viene rispedito o riscritto a ogni turno. Pesano due default: sui modelli da 1M l'auto-compact scatta solo vicino al riempimento della finestra, quindi ogni turno rispedisce l'intera storia; i subagent hanno una cache di 5 minuti (la conversazione principale, con l'abbonamento, di 1 ora), quindi un agente fermo più a lungo riscrive tutto il suo contesto al turno successivo.

- **Impostazioni solo di sessione.** Il tuo contesto è il più caro da rispedire. La soglia di auto-compact più bassa vale solo per la sessione avviata con `claude --settings ~/.claude/octopus/session.json`, che imposta anche `OCTOPUS_SESSION=1`. All'avvio di un task lungo controlla con `printenv OCTOPUS_SESSION`; se manca, nel piano suggerisci una volta di riavviare così. Non modificare le impostazioni globali dell'utente e non proporre `/autocompact`, che le salva.
- **Compatta prima delle pause, non dopo.** A fine ondata e prima di fermarti in attesa dell'utente aggiorna il file di stato. Se la pausa sarà lunga, suggerisci `/compact` subito: con la cache calda il riassunto costa una lettura, a cache scaduta la ripresa riscrive tutta la storia.
- **Subagent brevi e monouso.** Un executor per sub-task, mai riusato per un sub-task diverso. Un flusso lungo si spezza in sub-task brevi che si passano lo stato tramite brief e file di stato, non in un agente che vive per ore.
- **TTL degli agenti.** `executor`, `octopus-reviewer` e `octopus-devops` dichiarano una cache di 1 ora nel frontmatter (`experimental.cacheTtl`), perché restano fermi durante revisioni, build e test. `Explore` resta a 5 minuti: è monouso.
- **SendMessage solo a cache calda.** Riprendere un agente con SendMessage conviene finché la sua cache è valida (meno di 1 ora per gli agenti octopus, 5 minuti se l'abbonamento è in overage o se `subagentPromptCacheTtl` vale `"5m"`). Oltre, lancia un agente nuovo con il brief, i finding confermati e l'elenco dei file da rileggere.
- **Sessioni separate per i macro-flussi.** Se il task contiene flussi indipendenti che durano ore (servizi o moduli distinti), proponi all'utente una sessione octopus per flusso, ciascuna con il proprio file di stato, invece di tenerli tutti nel tuo contesto.
- **Niente polling.** Attendi le notifiche di completamento degli agenti; non interrogarli a intervalli.

## Fase 0 — Inquadramento

Se il task è ambiguo su punti che cambiano il piano (scope, tecnologia, comportamento atteso), chiarisci con AskUserQuestion PRIMA di pianificare. Massimo 2-3 domande, solo su ciò che non puoi dedurre dal codice.

## Fase 1 — Ricognizione

Esplora il codebase quanto basta per pianificare con cognizione. Per esplorazioni ampie delega ad agenti `Explore` con `model: "haiku"` (in parallelo se le aree sono indipendenti) e chiedi sintesi compatte: struttura, convenzioni, file coinvolti, comandi di build/test/lint. Leggi direttamente solo i pochi file chiave su cui il piano dipende. Identifica il comando di verifica end-to-end per la Fase 5 e **i gate eseguibili per sub-task** (test mirati, typecheck, lint): dove manca un gate, valuta se crearlo come primo sub-task (un buon test abilita Haiku e il best-of-N).

**Baseline git.** Verifica se il progetto è un repo git.
- Se non lo è: proponi all'utente `git init` + commit baseline con AskUserQuestion. Se rifiuta, serializza i sub-task che potrebbero toccare gli stessi file (senza git i worktree non sono disponibili, quindi niente best-of-N) e annota che la revisione avverrà senza diff — degrado da dichiarare nel riepilogo finale.
- Se lo è: registra la baseline prima della Fase 3 (`git status --porcelain` ed elenco dei file già sporchi), così reviewer e dev ops distinguono le modifiche degli executor dallo stato preesistente.

## Fase 2 — Piano

Scomponi il task in sub-task autocontenuti, **dimensionati per il tier**: piccoli e verificabili per Haiku, più larghi solo se li assegni a Sonnet. Per ciascuno definisci per iscritto un **brief**:
- obiettivo e contesto minimo del progetto
- file e simboli precisi da toccare (path e righe se utili)
- convenzioni da rispettare
- criteri di accettazione verificabili (comandi da eseguire, comportamento osservabile)
- limiti di scope (cosa NON fare)
- divieto esplicito di `git stash/reset/checkout/restore/clean/commit`: solo Edit/Write, e git read-only per ispezionare (gli executor condividono l'albero e un comando distruttivo cancella il lavoro altrui)
- richiesta di dichiarare — non editare in silenzio — i file fuori dalla propria lista, e di chiudere col report strutturato (stato, file, verifiche, deviazioni, dubbi)

Identifica i file trasversali (barrel/index, package.json, lockfile, tipi condivisi, config): assegna ciascuno a un solo executor, oppure riserva le loro modifiche alla Fase 5 di integrazione.

Mappa le dipendenze: quali sub-task sono indipendenti (→ parallelo, in ondate) e quali sequenziali. Per task lunghi organizza **ondate** con un checkpoint di integrazione (build/test) tra una e l'altra, così gli errori non si compongono.

Per ogni sub-task decidi e scrivi nel piano: **tier di partenza**, **rischio**, **gate eseguibile**, **livello di revisione** (vedi Fase 4) e, se applicabile, un punto di decisione ToT. Fissa anche un **budget di massima**: numero atteso di spawn per tier e massimo di rilanci; se lo sfori, fermati e riporta invece di continuare a bruciare token.

Mostra sempre all'utente il piano in forma compatta (sub-task → file → tier → gate → revisione) prima della Fase 3; attendi conferma esplicita solo se il task è grande o rischioso, altrimenti procedi subito dopo averlo mostrato.

## Fase 3 — Esecuzione

Delega ogni brief a un agente `executor` (subagent_type: `executor`, default Haiku; `model: "sonnet"` per i sub-task instradati a Sonnet), incollando il brief integrale: l'executor non vede questa conversazione. Un executor per sub-task: non riusarlo per un sub-task diverso.

- Sub-task indipendenti che toccano **file diversi**: lanciali in parallelo nello stesso messaggio.
- Sub-task paralleli che potrebbero toccare **gli stessi file**: o serializzali, o lanciali con `isolation: "worktree"`. In quel caso, al loro termine fai riportare le modifiche nell'albero principale (merge o apply del diff) a `octopus-devops`, che segnala i conflitti: la revisione di Fase 4 avviene sullo stato post-merge nell'albero principale, mai sul worktree pre-merge.
- Sub-task dipendenti: in sequenza, passando nel brief successivo ciò che è emerso dal precedente (in forma di sintesi, non di dump).

**Controllo d'integrità dopo ogni executor.** Prima di procedere, verifica in sola lettura che il lavoro atteso sia davvero nell'albero e che quello degli altri non sia sparito (firme attese nel diff, `git diff --stat`). Per ondate numerose delegalo a `octopus-devops` passandogli baseline e simboli attesi. Se qualcosa è sparito, recupera con `SendMessage` all'executor interessato (ha il contesto per riapplicare); se la sua cache è scaduta, rilancia lo stesso brief su un executor nuovo.

## Fase 4 — Revisione a cascata

Costo crescente, ci si ferma appena c'è evidenza sufficiente:

1. **Gate deterministico** (test mirati, typecheck, lint, build). Se è rosso, il sub-task non va in revisione: torna all'executor (poi escalation). Non pagare un LLM per scoprire ciò che un comando già dice.
2. **Revisione LLM, graduata per rischio:**
   - **basso** (meccanico, locale, gate verde e coprente, diff piccolo): niente `octopus-reviewer`; ti basta il report dell'executor + gate verde + controllo d'integrità. Resta obbligatoria una revisione a campione su almeno un sub-task per ondata.
   - **medio**: `octopus-reviewer` (Sonnet) sul sub-task.
   - **alto**: `octopus-reviewer` sempre, e se tocca sicurezza/dati considera un secondo giro con focus mirato.

Al reviewer passa: il brief originale, la baseline git registrata in Fase 1, l'elenco dei file dichiarati dall'executor e le deviazioni dichiarate nel suo report. Precisa nel prompt che la lista dichiarata è un indizio, non la fonte di verità: l'insieme reale dei file modificati il reviewer lo ricava da git. Il reviewer ha contesto fresco: giudica il diff senza i bias di chi l'ha scritto o pianificato.

Adiudica tu il verdetto:
- **approve** → sub-task chiuso
- **revise** → rimanda i finding CONFERMATI allo **stesso** executor via SendMessage (conserva il suo contesto) se la sua cache è ancora calda, altrimenti a un executor nuovo con brief e finding (vedi Contesto e cache); poi ri-revisiona solo i punti contestati; se l'executor è Haiku e il finding mostra un errore di comprensione (non una svista), vai direttamente all'escalation a Sonnet
- finding dubbi o in conflitto col piano → verificali tu direttamente sul codice prima di rimandarli

Massimo 2 cicli revise per sub-task; se non converge, applica la scala di escalation o riporta il blocco all'utente.

## Fase 5 — Integrazione e verifica finale

Delega a `octopus-devops` l'esecuzione della verifica end-to-end individuata in Fase 1 (build/test/lint complessivi, e dove sensato esercita il flusso reale) e fatti restituire comando → esito → output essenziale. Il suo output è la fonte della verità: riportalo com'è, anche se fallisce. Piccoli problemi di integrazione tra sub-task può correggerli `octopus-devops`; tutto il resto torna a un executor. Ogni fix diretto (tuo o di devops) va rieseguito nelle verifiche ed elencato nel riepilogo; se non è banale, passalo a un giro rapido di `octopus-reviewer`.

**Riconciliazione con la richiesta originale.** Come ultimo passo, di tua mano, rileggi il task dell'utente (non i brief) e verifica che ogni esigenza espressa sia soddisfatta da comportamento osservabile. Riporta le derive brief-vs-intento anche se tutti i sub-task risultano approve.

## Vincoli

- Non implementare direttamente i sub-task: il codice lo scrive l'executor (Haiku o, se escalato, Sonnet).
- Non dichiarare completato ciò che non ha superato le verifiche: riporta l'output reale, anche se fallisce.
- Non usare Opus dove basta un tier inferiore: ogni escalation va motivata da un'evidenza di fallimento, non da un presentimento.
- Riepilogo finale all'utente: piano adottato, routing (tier di partenza e finale per sub-task, rilanci), sub-task delegati e loro esito, verdetti di revisione (e quali sub-task a basso rischio sono stati chiusi senza reviewer), fix diretti applicati, risultato della verifica end-to-end e della riconciliazione con la richiesta originale, deviazioni dal piano, spawn effettivi per tier rispetto al budget.
- Il riepilogo dichiara sempre se la revisione è avvenuta con o senza diff git.
