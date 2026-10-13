# Laborator 1: Adrese Ethereum, portofele și furnizori RPC

Ghid pentru lucrul cu **Foundry** (`cast` și `anvil`): creezi un cont Ethereum, pornești o rețea locală, trimiți tranzacții și observi ce se întâmplă cu ele.

> **Scopul laboratorului:** să înțelegi ce sunt o adresă, un sold, un nonce, un chain ID și o adresă RPC, apoi să le vezi în practică pe o rețea locală.

## Cuprins

- [1. Concepte de bază](#1-concepte-de-bază)
- [2. Pregătire: instalează Foundry](#2-pregătire-instalează-foundry)
- [3. Pasul 1: Creează un cont](#3-pasul-1-creează-un-cont)
- [4. Pasul 2: Lucrul cu o rețea locală](#4-pasul-2-lucrul-cu-o-rețea-locală)
- [5. Exercițiul 1: Signer și publisher](#5-exercițiul-1-signer-și-publisher)

## 1. Concepte de bază

### 1.1. Contul și adresa

Un cont Ethereum (numit *externally owned account*) este format dintr-o pereche de chei:

| Element | Ce este | Se păstrează secret? |
|---|---|---|
| **Cheia privată** | Un număr aleator de 256 de biți. Cine o cunoaște controlează contul. | **Da, mereu** |
| **Cheia publică** | Calculată din cheia privată. Din ea nu se poate afla înapoi cheia privată. | Nu |
| **Adresa** | Ultimii 20 de octeți din hash-ul Keccak-256 al cheii publice, scrisă în hexazecimal cu prefixul `0x`. | Nu |

Lanțul este: **cheie privată → cheie publică → adresă**, iar fiecare pas merge într-un singur sens.

Exemplu de adresă: `0x5e97870f263700f46aa00d967821199b9bc5a120`. Uneori literele apar mici și mari (`0x5E97870f...`). Combinația de litere mici și mari este un checksum (EIP-55) care ajută portofelele să detecteze greșelile de tastare.

### 1.2. Soldul

Soldul (balance) este suma de ether a contului. El **nu se află în portofel** și nu se calculează din chei. Face parte din **starea blockchain-ului**, care păstrează pentru fiecare adresă soldul și nonce-ul. O tranzacție este o cerere de modificare a acestei stări: când intră într-un bloc, soldurile expeditorului și ale destinatarului se actualizează.

### 1.3. Unitățile de măsură

Tranzacțiile implică de obicei mai puțin de 1 ETH, de aceea se folosesc unități mai mici:

| Unitate | Relația cu 1 Ether |
|---|---|
| Finney | 1 Ether = 10<sup>3</sup> Finney |
| Gwei | 1 Ether = 10<sup>9</sup> Gwei |
| Wei | 1 Ether = 10<sup>18</sup> Wei |

Poți face conversii cu [Ethereum unit converter](https://info.etherscan.com/ethereum-unit-converter/).

### 1.4. Rețele Ethereum

Aceeași adresă poate fi folosită pe mai multe rețele, dar fiecare rețea are **starea ei independentă**. Un cont poate avea fonduri pe o rețea și zero pe alta.

| Termen | Ce înseamnă |
|---|---|
| **Rețea** | Un blockchain independent, cu noduri, blocuri și stare proprii. Exemple: **mainnet** (ether real), **testnet-uri publice** ca Sepolia (ether de test, fără valoare) și **rețele locale** ca cea pornită de `anvil`. |
| **Chain ID** | Numărul care identifică rețeaua: `1` pentru mainnet, `11155111` pentru Sepolia, `31337` pentru `anvil`. Face parte din fiecare tranzacție semnată, deci o tranzacție semnată pentru o rețea este respinsă de celelalte. Asta previne *replay-ul între rețele* (EIP-155). |
| **Nonce** | Un contor, păstrat pentru fiecare cont, egal cu numărul de tranzacții trimise de el. Fiecare tranzacție poartă nonce-ul curent al expeditorului, iar rețeaua o acceptă doar dacă este următorul nonce așteptat. Astfel, o tranzacție deja executată nu poate fi executată a doua oară, iar ordinea tranzacțiilor unui cont este fixă. |
| **Adresa RPC** | URL-ul unui nod prin care aplicațiile citesc starea și trimit tranzacții (protocolul JSON-RPC). Pentru `anvil` local este `http://127.0.0.1:8545`. Pentru rețele publice, este un nod propriu sau al unui furnizor RPC (de exemplu Infura sau Alchemy). |

Nodul RPC doar transmite cererile. Tranzacțiile sunt **semnate local**, cu cheia privată, înainte să ajungă la el.

## 2. Pregătire: instalează Foundry

**Foundry** este un set de unelte pentru dezvoltarea Ethereum. Conține:

- `forge`, pentru compilarea și testarea contractelor;
- `cast`, pentru interacțiunea cu blockchain-ul din terminal;
- `anvil`, un nod Ethereum local;
- `chisel`, un mediu interactiv pentru Solidity.

Instrucțiunile sunt pentru **Linux**.

> **Utilizatori Windows:** Foundry trebuie instalat și rulat în **WSL** (Windows Subsystem for Linux). Deschide PowerShell ca Administrator și rulează `wsl --install`. Repornește calculatorul, apoi rulează toate comenzile de mai jos în terminalul **WSL (Ubuntu)**.

### 2.1. Instalare

1. Instalează `foundryup`, programul de instalare al Foundry:

   ```bash
   curl -L https://getfoundry.sh/install | bash
   ```

2. Reîncarcă terminalul, ca `foundryup` să fie găsit în `PATH`:

   ```bash
   source ~/.bashrc
   ```

3. Instalează uneltele Foundry:

   ```bash
   foundryup
   ```

### 2.2. Verificare

Afișează versiunea fiecărei unelte:

```bash
forge --version
cast --version
anvil --version
chisel --version
```

Fiecare comandă trebuie să afișeze un număr de versiune. Dacă primești `command not found`, deschide un terminal nou sau rulează `source ~/.bashrc`, apoi încearcă din nou.

## 3. Pasul 1: Creează un cont

> **Avertisment de securitate.** Conturile pre-finanțate oferite de `anvil` sunt generate dintr-o frază mnemonică **publică**, deci cheile lor private sunt cunoscute de oricine. Se folosesc **exclusiv** pe rețele locale de test. Fondurile trimise la aceste adrese pe o rețea publică sunt luate aproape imediat de boți automați.

În laborator vei genera o pereche de chei nouă și o vei salva într-un **keystore criptat**. Cheile private **nu** se păstrează în text simplu, de exemplu într-un fișier `.env`, pentru că astfel de fișiere ajung ușor, din greșeală, într-un repository public.

1. Generează o pereche de chei aleatoare:

   ```bash
   cast wallet new
   ```

   Comanda afișează adresa și cheia privată a noului cont.

2. Importă cheia privată într-un keystore criptat numit `lab1`:

   ```bash
   cast wallet import lab1 --interactive
   ```

   Ți se cere să lipești cheia privată, apoi să alegi o parolă care o criptează. Keystore-ul se salvează în `~/.foundry/keystores/lab1`. După import, rulează `clear`, ca cheia privată să nu mai apară pe ecran.

3. Verifică dacă keystore-ul există și afișează adresa lui:

   ```bash
   cast wallet list
   cast wallet address --account lab1
   ```

În pașii următori, contul se folosește prin `--account lab1`. Foundry cere parola keystore-ului de fiecare dată când are nevoie de cheie ca să semneze o tranzacție.

**Nu uita parola keystore-ului.** Fără ea nu poți folosi contul `lab1`.

### Alte metode de generare a cheilor (doar informativ)

- **Frază mnemonică:** `cast wallet new-mnemonic` generează o frază de 12 sau 24 de cuvinte din care se pot deriva mai multe conturi. Este metoda folosită de majoritatea aplicațiilor de tip portofel, iar dacă pierzi dispozitivul, fraza te ajută să recuperezi accesul la fonduri.
- **Biblioteci de programare:** de exemplu `ethers.Wallet.createRandom()` (JavaScript, ethers.js) sau `Account.create()` (Python, eth-account).
- **Portofele software:** MetaMask generează și păstrează cheile în browser.
- **Portofele hardware:** Ledger sau Trezor păstrează cheia pe dispozitiv, fără ca ea să ajungă vreodată în calculator. Sunt recomandate pentru conturile cu fonduri reale.

## 4. Pasul 2: Lucrul cu o rețea locală

`anvil` simulează un blockchain pe calculatorul tău. Poți trimite tranzacții fără fonduri reale și fără să aștepți o rețea publică.

Acest pas folosește **două terminale**: unul în care rulează `anvil` și unul pentru comenzile `cast`.

### 4.1. Pornește nodul local

În primul terminal:

```bash
anvil
```

În ieșire vei vedea:

- **10 conturi pre-finanțate**, fiecare cu 10.000 ETH, împreună cu cheile lor private (derivate din mnemonica publică `test test test test test test test test test test test junk`);
- **Chain ID `31337`**;
- **Adresa RPC** `http://127.0.0.1:8545`, prin care `cast` comunică cu nodul.

Implicit, `anvil` folosește **mining instant** (*automine*): fiecare tranzacție intră într-un bloc nou imediat ce este primită.

Lasă acest terminal deschis. În al doilea terminal, spune lui `cast` să folosească nodul local și verifică rețeaua:

```bash
export ETH_RPC_URL=http://127.0.0.1:8545
cast chain-id
cast block-number
```

- `export ETH_RPC_URL=...` setează o variabilă de mediu pe care `cast` o citește ca să știe la ce nod să se conecteze.
- `cast chain-id` trebuie să afișeze `31337`.
- `cast block-number` afișează numărul ultimului bloc.

### 4.2. Interoghează starea conturilor

Definește două variabile: `ACC0` (primul cont afișat de `anvil`) și `LAB1` (adresa contului creat la Pasul 1):

```bash
ACC0=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
LAB1=$(cast wallet address --account lab1)
```

Variabilele se folosesc apoi cu semnul `$` (de exemplu `$ACC0`). Interoghează soldul și nonce-ul fiecărui cont:

```bash
cast balance $ACC0 --ether
cast nonce $ACC0
cast balance $LAB1 --ether
cast nonce $LAB1
```

- **Soldul** este suma de ether a contului. Fără `--ether`, se afișează în wei.
- **Nonce-ul** este numărul de tranzacții trimise de cont. Fiecare tranzacție nouă folosește nonce-ul următor.

Contul `lab1` are sold 0 pe rețeaua locală, pentru că este nou.

### 4.3. Trimite o tranzacție

Mai întâi, transferă 1 ETH către `lab1` din primul cont `anvil`. Cheia lui privată este publică și o folosim aici doar pentru că rețeaua este locală:

```bash
cast send $LAB1 --value 1ether \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

Apoi trimite 0,1 ETH din `lab1` către al doilea cont `anvil`. Tranzacția este semnată cu keystore-ul criptat, iar `cast` îți cere parola:

```bash
cast send 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 --value 0.1ether --account lab1
```

`cast send` așteaptă ca tranzacția să fie minată și afișează chitanța (*receipt*). Copiază valoarea `transactionHash` din ieșire și examinează tranzacția:

```bash
TX=<transactionHash>
cast tx $TX
cast receipt $TX
```

Cele două comenzi arată lucruri diferite:

| Comandă | Ce afișează |
|---|---|
| `cast tx` | **Tranzacția** așa cum a fost semnată și trimisă: `from`, `to`, `value`, `nonce`, câmpurile de gas, `input` (gol pentru un transfer simplu) și semnătura (`r`, `s`, `v`). |
| `cast receipt` | **Rezultatul execuției**: `status` (`1` = succes), `blockNumber`, `gasUsed` (21.000 pentru un transfer simplu de ETH) și `effectiveGasPrice`. |

Repetă interogările din 4.2 și observă schimbările:

- nonce-ul lui `lab1` a crescut cu 1;
- soldul lui `lab1` a scăzut cu 0,1 ETH **plus comisionul tranzacției** (`gasUsed × effectiveGasPrice`).

### 4.4. Observă tranzacțiile în așteptare (pending)

Cu mining instant, tranzacția este minată imediat, deci starea ei *pending* nu poate fi observată. Ca să simulezi o rețea reală, oprește `anvil` (`Ctrl+C`) și pornește-l din nou cu un bloc la fiecare 12 secunde, intervalul de blocuri al mainnet-ului:

```bash
anvil --block-time 12
```

> **Atenție.** `anvil` păstrează starea doar în memorie. După repornire, toate tranzacțiile anterioare se pierd, iar contul `lab1` trebuie finanțat din nou (repetă prima comandă din 4.3).

În al doilea terminal, trimite o tranzacție cu `--async`, care afișează hash-ul tranzacției și se oprește fără să aștepte minarea:

```bash
TX=$(cast send 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 --value 0.1ether --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --async)
cast tx $TX
cast tx $TX --raw
cast decode-transaction <transaction>
```

- `cast tx $TX --raw` afișează tranzacția brută semnată (un șir hexazecimal lung).
- La `cast decode-transaction`, înlocuiește `<transaction>` cu acel șir hexazecimal.

Dacă rulezi `cast tx` înainte de următorul bloc, tranzacția este încă **pending**: nodul a primit-o, dar nu face încă parte dintr-un bloc, deci nu are `blockNumber`. Acum rulează:

```bash
cast receipt $TX
```

Comanda așteaptă ca tranzacția să fie inclusă într-un bloc, apoi afișează chitanța. Același principiu se aplică și rețelelor publice: o tranzacție este finală doar după ce a fost inclusă într-un bloc.

## 5. Exercițiul 1: Signer și publisher

*Exercițiu pe echipe de doi sau trei studenți.*

La Pasul 2, o singură comandă (`cast send`) a **semnat** tranzacția și a **trimis-o** nodului. În acest exercițiu, cele două operații sunt separate și făcute de persoane diferite:

- **Signer-ul** are cheia privată și creează tranzacții semnate, dar **nu are acces** la nicio rețea;
- **Publisher-ul** rulează rețeaua, dar **nu are acces** la cheia signer-ului.

Cei doi pot schimba între ei doar **adrese** și **tranzacții brute semnate** (șiruri hexazecimale), de exemplu printr-un mesaj. Observând cum reacționează rețeaua, echipa investighează rolul **chain ID-ului** și al **nonce-ului**.

### 5.1. Roluri și reguli

| Rol | Echipă de doi | Echipă de trei | Comenzi permise |
|---|---|---|---|
| **Signer** | 1 student | 1 student | `cast wallet`, `cast mktx`. **Fără** `--rpc-url`, fără nod pornit. |
| **Publisher** | 1 student | 2 studenți (Publisher 1 și Publisher 2), pe **același calculator**, în terminale separate | `anvil`, `cast publish`, `cast tx`, `cast receipt`, `cast rpc`, `cast nonce`, `cast balance`, `cast decode-transaction` |

Reguli:

1. Cheia privată nu părăsește calculatorul signer-ului. Se schimbă doar adrese și tranzacții brute.
2. Tot ce are nevoie signer-ul să știe despre o rețea (chain ID, nonce, sold) trebuie **cerut** de la publisher.
3. Fiecare tranzacție folosește valorile fixe `--legacy --gas-limit 21000 --gas-price 2gwei`, cu excepția variantei cu tip din Runda 1. Gas-ul și comisioanele se studiază la un alt laborator, deci copiază aceste valori.
4. Înainte de fiecare experiment, fiecare membru scrie în raport o **predicție**. Rezultatul observat se notează după aceea.
5. La jumătatea exercițiului (Runda 3), rolurile se inversează, ca fiecare student să fie și signer, și publisher.

Observațiile se notează în raport, folosind șablonul [`REPORT_TEMPLATE.md`](REPORT_TEMPLATE.md).

### 5.2. Runda 0: Pregătirea rețelelor și finanțarea signer-ului

**Publisher.** Pornește două rețele locale independente, fiecare în terminalul ei. Opțiunea `--no-mining` dezactivează mining-ul automat, deci blocurile se produc doar când le ceri tu:

```bash
# Terminal 1: Rețeaua 1 (chain ID 31337, port 8545)
anvil --no-mining

# Terminal 2: Rețeaua 2 (chain ID 1337, port 8546)
anvil --no-mining --port 8546 --chain-id 1337
```

Într-un al treilea terminal, definește variabilele folosite în rundele următoare:

```bash
export ETH_RPC_URL=http://127.0.0.1:8545     # Rețeaua 1 este folosită implicit
NET2=http://127.0.0.1:8546                    # Rețeaua 2 se folosește cu --rpc-url $NET2
ANVIL_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80   # contul 0 anvil (cheie publică, doar uz local)
```

**Signer.** Asigură-te că nicio rețea nu este configurată, apoi trimite adresa ta publisher-ului:

```bash
unset ETH_RPC_URL
cast wallet address --account lab1
```

**Publisher.** Finanțează adresa signer-ului cu 1 ETH pe **ambele** rețele, minează câte un bloc pe fiecare și verifică soldurile:

```bash
SIGNER=<adresa primită de la signer>

cast send $SIGNER --value 1ether --private-key $ANVIL_KEY --async
cast send $SIGNER --value 1ether --private-key $ANVIL_KEY --async --rpc-url $NET2

cast rpc evm_mine
cast rpc evm_mine --rpc-url $NET2

cast balance $SIGNER --ether
cast balance $SIGNER --ether --rpc-url $NET2
```

**Signer.** Ca să semnezi o tranzacție, ai nevoie de două valori pe care doar publisher-ul le poate da: **chain ID-ul** și **nonce-ul tău curent** pe Rețeaua 1. Publisher-ul îți răspunde cu rezultatul comenzilor:

```bash
cast chain-id
cast nonce $SIGNER
```

> **Raport:** Explică de ce are nevoie signer-ul de fiecare dintre aceste două valori ca să semneze o tranzacție.

### 5.3. Runda 1: Ciclul de viață al unei tranzacții

**Signer.** Semnează un transfer de 0,01 ETH către contul 1 `anvil`, folosind nonce-ul primit în Runda 0. Comanda afișează tranzacția brută semnată (un șir hexazecimal lung care începe cu `0x`). Trimite-l publisher-ului:

```bash
cast mktx 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 --value 0.01ether \
  --nonce <nonce> --chain 31337 \
  --legacy --gas-limit 21000 --gas-price 2gwei \
  --account lab1
```

`cast mktx` doar **creează și semnează** tranzacția, fără să o trimită nicăieri. Înlocuiește `<nonce>` cu valoarea primită.

**Publisher.** Salvează tranzacția brută (o vei folosi din nou în Rundele 2 și 4), public-o și notează hash-ul:

```bash
RAW1=<tranzacția brută primită de la signer>
TX1=$(cast publish $RAW1 --async)
echo $TX1
```

Cum mining-ul este dezactivat, tranzacția nu este încă inclusă într-un bloc. Rulează cele trei verificări, în această ordine, și notează rezultatul fiecăreia:

```bash
cast tx $TX1                  # Nodul cunoaște tranzacția? Are număr de bloc?
cast receipt $TX1 --async     # Există o chitanță?
cast rpc txpool_inspect       # Este tranzacția în pool-ul de tranzacții (mempool)?
```

Apoi minează un bloc și rulează cele trei verificări din nou:

```bash
cast rpc evm_mine
```

> **Raport:** Enumeră stările prin care a trecut tranzacția și, pentru fiecare, comanda care a arătat-o.

#### Varianta cu tip (opțională)

În loc de o tranzacție *legacy*, signer-ul poate semna o tranzacție **EIP-1559**, care are două valori:

- **comisionul maxim per gas** pe care expeditorul acceptă să-l plătească (`--gas-price`);
- **comisionul de prioritate**, numit *tip* (`--priority-gas-price`), plătit celui care produce blocul ca stimulent să includă tranzacția.

```bash
cast mktx 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 --value 0.01ether \
  --nonce <nonce> --chain 31337 \
  --gas-limit 21000 --gas-price 10gwei --priority-gas-price 1gwei \
  --account lab1
```

Ca să observe efectul tip-ului, publisher-ul trimite, **înainte de minare**, o tranzacție concurentă din contul 0 `anvil`, cu un tip diferit (aici, mai mare), pe lângă publicarea tranzacției signer-ului:

```bash
TX0=$(cast send 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC --value 0.01ether \
  --gas-price 10gwei --priority-gas-price 3gwei \
  --private-key $ANVIL_KEY --async)
```

După `cast rpc evm_mine`, compară poziția celor două tranzacții în bloc:

```bash
cast receipt $TX1 transactionIndex
cast receipt $TX0 transactionIndex
```

Repetă experimentul cu tip-urile inversate. Tip-ul ordonează tranzacțiile doar între **expeditori diferiți**: tranzacțiile aceluiași expeditor sunt incluse mereu în ordinea nonce-urilor, indiferent de tip.

### 5.4. Runda 2: Publicarea aceleiași tranzacții de două ori

**Publisher.** Fără să implici signer-ul, publică a doua oară tranzacția din Runda 1:

```bash
cast publish $RAW1 --async
```

> **Raport:** Înainte să rulezi comanda, prezice dacă contul 1 `anvil` va primi 0,01 ETH a doua oară. Apoi notează rezultatul și câmpul tranzacției care îl explică.

### 5.5. Runda 3: Perechea misterioasă

Această rundă se joacă de **cel puțin patru ori**: de două ori cu rolurile inițiale și de două ori după inversarea lor. La fiecare repetare, signer-ul alege **în secret** unul dintre scenariile de mai jos și semnează **două** tranzacții, TX-A și TX-B. Publisher-ul nu știe scenariul ales și trebuie să-l identifice doar din comportamentul rețelelor.

| Scenariu | TX-A | TX-B |
|---|---|---|
| **S1. Nonce-uri consecutive** | nonce *n*, chain 31337 | nonce *n*+1, chain 31337 |
| **S2. Ordine inversată** | nonce *n*+1, chain 31337 | nonce *n*, chain 31337 |
| **S3. Același nonce** | nonce *n*, chain 31337, destinatar contul 1 `anvil` | nonce *n*, chain 31337, destinatar contul 2 `anvil` |
| **S4. Lanțuri diferite** | nonce *n*, chain 31337 | nonce *m*, chain 1337 |

Aici *n* este nonce-ul curent al signer-ului pe Rețeaua 1, iar *m* nonce-ul lui pe Rețeaua 2. Contul 1 `anvil` este `0x70997970C51812dc3A010C7d01b50e0d17dc79C8`, iar contul 2 este `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC`.

**Signer.**

1. Cere publisher-ului nonce-ul tău curent pe **ambele** rețele (fără să dezvălui scenariul).
2. Alege un scenariu și notează-l în raport, ascuns de publisher. Folosește fiecare scenariu cel puțin o dată pe parcursul exercițiului.
3. Semnează TX-A și TX-B cu `cast mktx`, ca în Runda 1, schimbând doar `--nonce`, `--chain` și destinatarul, conform scenariului. Fiecare tranzacție transferă 0,01 ETH.
4. Trimite ambele tranzacții brute publisher-ului, etichetate TX-A și TX-B.

**Publisher.** Investighează cele două tranzacții. În echipa de trei, Publisher 1 primește TX-A, Publisher 2 primește TX-B, iar ei le publică **în același timp** (după o numărătoare inversă), fiecare din terminalul lui (cu variabilele din Runda 0 definite), ambele pe Rețeaua 1.

1. Notează nonce-ul și soldul signer-ului pe ambele rețele:

   ```bash
   cast nonce $SIGNER;  cast nonce $SIGNER --rpc-url $NET2
   cast balance $SIGNER --ether;  cast balance $SIGNER --ether --rpc-url $NET2
   ```

2. Publică TX-A, apoi TX-B, **pe Rețeaua 1**. Notează hash-ul sau mesajul de eroare returnat pentru fiecare:

   ```bash
   TXA=$(cast publish <TX-A> --async)
   TXB=$(cast publish <TX-B> --async)
   ```

3. Inspectează pool-ul de tranzacții. Notează în ce secțiune (`pending` sau `queued`) apare fiecare tranzacție:

   ```bash
   cast rpc txpool_inspect
   ```

4. Minează **un** bloc, apoi verifică din nou chitanțele, pool-ul și nonce-ul signer-ului:

   ```bash
   cast rpc evm_mine
   cast receipt $TXA --async
   cast receipt $TXB --async
   cast rpc txpool_inspect
   cast nonce $SIGNER
   ```

5. Dacă o tranzacție a fost respinsă sau tot nu este inclusă, decide ce încerci mai departe: minezi încă un bloc sau o publici pe Rețeaua 2 (`cast publish <TX> --async --rpc-url $NET2`, urmată de `cast rpc evm_mine --rpc-url $NET2`).

6. Scrie un **diagnostic** (ce scenariu crezi că a fost ales) și **dovezile** care îl susțin. Abia apoi poate signer-ul să dezvăluie scenariul.

7. Verifică diagnosticul decodând cele două tranzacții brute și comparând câmpurile `nonce` și `chainId`:

   ```bash
   cast decode-transaction <TX-A>
   cast decode-transaction <TX-B>
   ```

> **Notă.** În scenariul S3, mesajul de eroare al nodului poate face referire la comisioane sau la prețul gas-ului. Notează mesajul exact, așa cum apare. El va fi explicat la laboratorul despre gas și comisioane.

**Inversarea rolurilor.** După a doua repetare, rolurile se inversează. Noul publisher își pornește propriile rețele și finanțează noul signer (repetă Runda 0), iar noul signer trimite o tranzacție ca în Runda 1, ca noul publisher să aibă un `RAW1` pentru Runda 4. Apoi Runda 3 continuă.

> **Raport:** Pentru fiecare repetare, completează un rând din tabelul Rundei 3. La final, răspunde: de ce poate fi inclusă cel mult una din două tranzacții cu același nonce? Care scenarii nu pot fi deosebite înainte de minarea unui bloc și ce singură comandă le deosebește?

### 5.6. Runda 4: Două rețele cu același chain ID

În Runda 3, tranzacțiile semnate pentru o rețea au fost respinse de cealaltă. Această rundă testează ce protejează împotriva acestui lucru.

**Publisher.**

1. Oprește Rețeaua 2 (`Ctrl+C`) și pornește-o din nou cu **același** chain ID ca Rețeaua 1:

   ```bash
   anvil --no-mining --port 8546 --chain-id 31337
   ```

2. Finanțează signer-ul pe noua Rețea 2 și minează un bloc (ca în Runda 0).

3. Publică pe Rețeaua 2 tranzacția din Runda 1, semnată pentru Rețeaua 1, și minează un bloc:

   ```bash
   cast publish $RAW1 --async --rpc-url $NET2
   cast rpc evm_mine --rpc-url $NET2
   ```

> **Raport:** Prezice rezultatul înainte să rulezi comenzile, apoi notează ce s-a întâmplat. Explică de ce chain ID-ul protejează împotriva replay-ului doar dacă fiecare rețea folosește o valoare diferită. Ca cercetare suplimentară, află cum a afectat această problemă Ethereum și Ethereum Classic după separarea din 2016.

**Securitate:** folosește exclusiv conturi și fonduri de test. Nu publica chei private, fraze de recuperare, fișiere `.env` sau parole de keystore în repository-ul GitHub.
