# Octopus

Comando `/octopus` per Claude Code: orchestra task lunghi e complessi su tre modelli, instradando ogni sub-task al livello più economico che può riuscire e salendo solo su evidenza di fallimento.

![Architettura di Octopus](docs/architecture.svg)

## Idea

Un dynamic workflow spende modelli forti ovunque. Octopus inverte il rapporto: il modello più costoso decide, quelli economici lavorano, e i verificatori eseguibili (test, typecheck, lint, build) vengono prima di qualunque giudizio LLM.

| Livello | Modello | Agente | Ruolo |
|---|---|---|---|
| Testa | Opus 5.5 | comando `/octopus` | piano, routing, adiudicazione, riconciliazione finale |
| Dev ops | Sonnet 5.5 | `octopus-devops`, `octopus-reviewer` | verifica e integrazione, revisione a contesto fresco, sub-task di difficoltà media |
| Esecutore | Haiku 5.5 | `executor`, `Explore` | implementazione meccanica, ricognizione, ricerche |

Per far salire un sub-task di livello non serve un agente nuovo: `executor` viene rilanciato con `model: "sonnet"`.

## Fasi

0. **Inquadramento.** Al massimo 2-3 domande, solo su ciò che il codice non chiarisce.
1. **Ricognizione.** Agenti `Explore` su Haiku, sintesi compatte. Si individuano i comandi di verifica e la baseline git.
2. **Piano.** Sub-task autocontenuti con brief scritto, tier di partenza, rischio, gate eseguibile, livello di revisione e budget di spawn. Per task lunghi, ondate con checkpoint di integrazione e file di stato.
3. **Esecuzione.** Un `executor` per sub-task, in parallelo se i file sono disgiunti, in worktree isolati altrimenti. Dopo ogni executor un controllo di integrità in sola lettura.
4. **Revisione a cascata.** Prima il gate deterministico, poi, in base al rischio, `octopus-reviewer`.
5. **Integrazione.** `octopus-devops` esegue la verifica end-to-end; Opus riconcilia il risultato con la richiesta originale.

## Routing

| Livello di partenza | Quando |
|---|---|
| Haiku | modifica locale (≤ 3 file), specifica non ambigua, criterio di accettazione eseguibile, pattern già presente nel codice |
| Sonnet | più file accoppiati, debugging con causa ignota, contratti condivisi, rischio alto, oppure Haiku ha già fallito |
| Opus | decisioni architetturali, conflitti tra sub-task, fallimento anche a Sonnet |

Escalation: Haiku, poi Sonnet, poi Opus, massimo 2 tentativi per livello. Il rilancio riceve l'errore reale del tentativo precedente.

## Modalità di ragionamento

| Modalità | Uso | Costo |
|---|---|---|
| Plan-and-execute a cascata | default per ogni task | basso |
| CoT | ragionamento interno dei modelli; Haiku scrive un piano breve prima di editare | trascurabile |
| ToT | solo ai punti di decisione incerti e difficili da annullare: 2-3 candidati Sonnet, Opus sceglie | alto, da usare di rado |
| Best-of-N | sub-task difficili con test oggettivi: 2-3 executor Haiku in worktree, vince chi supera il gate | medio, senza bias da giudice LLM |
| Debate | solo su finding di revisione in conflitto ad alto rischio | alto |

## Installazione

```sh
./install.sh
```

Copia il comando e gli agenti in `~/.claude`. Rifiuta di sovrascrivere file esistenti; con `--force` li sostituisce. La destinazione si cambia con `CLAUDE_HOME`.

Claude Code carica le definizioni degli agenti all'avvio: dopo l'installazione apri una nuova sessione.

## Uso

```
/octopus <task da realizzare>
```

Con un repo git sono disponibili worktree e best-of-N. Senza git i sub-task con file in comune vengono serializzati e la revisione avviene senza diff.

## Struttura

```
commands/octopus.md          comando e logica di orchestrazione
agents/executor.md           esecutore su Haiku 5.5
agents/octopus-reviewer.md   revisore a contesto fresco su Sonnet 5.5
agents/octopus-devops.md     verifica e integrazione su Sonnet 5.5
docs/architecture.svg        diagramma dell'architettura
install.sh                   installazione in ~/.claude
```
