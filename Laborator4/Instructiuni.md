# Contracte inteligente în Solidity: interacțiunea dintre contracte, erori, evenimente și costuri de gaz

Acest laborator continuă platforma de puncte de fidelitate din Laboratorul 3. Punctul de pornire este perechea de contracte care rezolvă exercițiile Laboratorului 3, `FidelityPointsFinal.sol` și `CatalogFinal.sol`, redenumite în Pasul 1 în `FidelityPoints` și `Catalog`. Cele două contracte sunt mai întâi conectate, astfel încât un client să poată **folosi punctele pentru a cumpăra produse din catalog**, apoi sunt extinse cu evenimente, tratarea mai fină a erorilor și optimizări de gaz.

## Noțiuni de bază în Solidity

### Function modifiers

Un **modifier** schimbă comportamentul unei funcții, de obicei verificând o condiție înainte de corpul ei:

```solidity
modifier onlyAdmin() {
    if (msg.sender != admin) revert NotAdmin(msg.sender);
    _;
}
```

- **`_;`** este locul în care se inserează corpul funcției. Codul de dinaintea lui rulează *înaintea* funcției, cel de după rulează *după* ea.
- Un modifier poate primi **argumente**: `function spendPoints(uint _points) external validAmount(_points)`.
- Mai multe modifiere se scriu separate prin spațiu și se evaluează **în ordinea listării**. Prima condiție care eșuează decide ce eroare primește apelantul.
- Codul modifierului este **copiat** în fiecare funcție care îl folosește, deci un modifier lung pe multe funcții mărește bytecode-ul și costul de deploy. Soluția: mută corpul într-o funcție `internal` (ex. `_checkAdmin()`) și apeleaz-o din modifier.

### Erori și revert-uri

La o eroare, EVM face **revert**: toate modificările de stare ale apelului sunt anulate, iar apelantul primește datele erorii.

| Construcție | Când se folosește |
|---|---|
| `require(cond, "mesaj")` | validarea intrărilor, a stării contractului, a rezultatelor apelurilor externe. Din 0.8.26 acceptă și o eroare personalizată. |
| `revert CustomError(args)` / `revert("mesaj")` | revert necondiționat, de obicei în interiorul unui `if` |
| `assert(cond)` | **invarianți**: condiții care trebuie să fie mereu adevărate dacă codul e corect. Un `assert` eșuat înseamnă un **bug**, nu o intrare greșită. |
| `error Nume(parametri);` | erori personalizate: mai **ieftine** decât string-urile, pentru că datele erorii conțin doar un *selector* de 4 octeți + argumentele codificate ABI |

**Selectorul** este primii 4 octeți din hash-ul Keccak-256 al semnăturii, de exemplu `NotAdmin(address)`.

Compilatorul generează automat erori `Panic` cu coduri fixe:

| Cod | Cauză |
|---|---|
| `0x01` | `assert` eșuat |
| `0x11` | overflow / underflow aritmetic |
| `0x12` | împărțire la zero |
| `0x32` | index în afara array-ului |

Dacă un contract apelează altul și acela dă revert, eroarea **urcă (*bubbles up*)**: funcția apelantă dă și ea revert, cu aceleași date de eroare, cu excepția cazului în care eroarea e prinsă cu `try`/`catch`.

### `try` / `catch`

```solidity
try catalog.decreaseStock(code, quantity) {
    // apelul a reușit
} catch Error(string memory reason) {
    // revert("...") sau require(false, "...") în contractul apelat
} catch Panic(uint errorCode) {
    // assert, overflow, împărțire la zero, index în afara array-ului
} catch (bytes memory lowLevelData) {
    // orice altceva, inclusiv erorile personalizate
}
```

Reguli de reținut:
- Dacă funcția întoarce valori: `try catalog.getPrice(code) returns (uint price) { ... }`.
- **Erorile personalizate nu au clauză proprie**: ajung în `catch (bytes memory)`. Se recunosc comparând primii 4 octeți cu selectorul: `bytes4(lowLevelData) == Catalog.ProductNotFound.selector`.
- `try` merge **doar** cu apeluri **externe** și cu `new`. Erorile din contractul apelant (ex. la calculul argumentelor) nu sunt prinse.
- Dacă apelantul dă totuși revert *după* `catch`, **toate** modificările lui, inclusiv cele din `catch`, se anulează.

### Evenimente (*events*)

```solidity
event PointsAdded(address indexed client, uint amount);

emit PointsAdded(client, _points);
```

Fiecare intrare din log conține adresa contractului, **maximum 4 topic-uri** și un câmp **data**:

- primul topic = `keccak256` al semnăturii evenimentului (calculabil cu `cast sig-event`);
- fiecare parametru `indexed` devine un topic (maximum 3). Pentru tipuri de referință, ex. `string`, topic-ul este *hash-ul* valorii, nu valoarea;
- restul parametrilor sunt codificați ABI în `data`.

Aplicațiile filtrează logurile după adresă și topic-uri. Logurile sunt **mult mai ieftine decât storage-ul**, dar **nu pot fi citite de contracte**: sunt pentru aplicații off-chain. Ce trebuie folosit mai târziu de un contract rămâne în storage.

### Interacțiunea dintre contracte

Un contract poate apela altul dacă îi știe **adresa** și **interfața**:

```solidity
interface ICatalog {
    function getPrice(bytes32 code) external view returns (uint);
    function decreaseStock(bytes32 code, uint amount) external;
}

ICatalog catalog = ICatalog(catalogAddress);
uint price = catalog.getPrice(code);
```

Codul sursă al `Catalog` nu e necesar; contează doar ca interfața să corespundă ABI-ului lui.

**Proprietăți importante ale apelurilor externe:**

-  În contractul apelat, **`msg.sender` este adresa contractului apelant**, nu a clientului. Adresa clientului e în `tx.origin`, dar **nu trebuie folosită pentru autorizare**: orice contract apelat de client ar putea acționa în numele lui.
-  Contractul apelat poate fi rău intenționat și te poate apela înapoi înainte să se termine primul apel (**reentrancy**). Ordinea recomandată este **checks–effects–interactions**: (1) verifici condițiile, (2) actualizezi starea, (3) abia la sfârșit apelezi alte contracte.
-  Un apel extern costă mult mai mult decât unul intern: 2.600 gas pentru prima accesare a unei adrese, plus codificarea și decodificarea datelor. `this.f()` este tot un apel extern.
-  O funcție `view` e gratuită cu `eth_call` (`cast call`), dar **costă gaz** când e apelată dintr-o tranzacție (ex. `redeem` apelând `getPrice`).

### Layout-ul storage-ului

Storage-ul unui contract are 2²⁵⁶ **sloturi** de 32 de octeți, inițial zero. Compilatorul le atribuie variabilelor **în ordinea declarării**:

- Tipurile simple ocupă doar cât au nevoie, iar variabilele consecutive se **împachetează** în același slot dacă încap. Exemplu: `address admin` (20 B) + `bool paused` (1 B) + `uint64 lastUpdate` (8 B) = un singur slot. Un `uint256` ocupă mereu un slot întreg.
- **Struct-urile și array-urile** încep mereu într-un slot nou, iar variabila următoare începe tot într-un slot nou. În `Catalog`, un `Product` ocupă 5 sloturi și un `Promo` 4.
- `constant` și `immutable` **nu** sunt în storage: valoarea lor e în bytecode.

Cum arată tipurile de referință (unde `p` este slotul variabilei):

| Tip | Unde se află datele |
|---|---|
| **Array dinamic** | slotul `p` = lungimea; elementele de la `keccak256(p)`; elementul `i` (struct de `n` sloturi) începe la `keccak256(p) + i * n` |
| **Mapping** | slotul `p` rămâne gol; valoarea pentru cheia `k` e la `keccak256(h(k) . p)`. De aceea un mapping **nu poate fi parcurs** și nici șters integral. |
| **`string` / `bytes`** | ≤ 31 B: în slotul `p` însuși (date în octeții de ordin înalt, `2 * lungime` în ultimul octet). Mai lung: `2 * lungime + 1` în `p`, datele de la `keccak256(p)`. |

Layout-ul real îl afișează `forge inspect <Contract> storageLayout`.

#### Storage-ul celor două contracte integrate

| Slot `FidelityPoints` | Variabilă | Conținut |
|---|---|---|
| 0 | `admin` | adresa administratorului |
| 1 | `pointValue` | `uint256` |
| 2 | `points` | gol; `points[client]` e la `keccak256(client . 2)` |
| 3 | `totalPoints` | `uint256` |
| 4 | `catalog` | adresa contractului `Catalog` |

| Slot `Catalog` | Variabilă | Conținut |
|---|---|---|
| 0 | `products` | lungimea array-ului; elementele de la `keccak256(0)`, 5 sloturi/produs |
| 1–4 | `generalPromo` | `state`, `start`, `end`, `percent` |
| 5 | `admin` | adresa administratorului |
| 6 | `productPromos` | gol; `Promo` pentru `code` începe la `keccak256(code . 6)` |
| 7 | `fidelityProgram` | adresa contractului `FidelityPoints` |

**Ce trebuie înțeles de aici:**

- **Fiecare contract își are storage-ul propriu, separat.** Slotul 0 din `FidelityPoints` și slotul 0 din `Catalog` sunt sloturi diferite. Un contract nu poate citi sau scrie direct storage-ul altuia, ci doar prin apeluri.
- **O interfață nu ocupă storage.** O variabilă de tip `ICatalog` se stochează exact ca un `address` (20 B). Tipul ajută doar compilatorul să verifice și să codifice apelurile.
- **Legătura dintre contracte = două adrese**: slotul 4 din `FidelityPoints` și slotul 7 din `Catalog`. Se verifică cu `cast storage $FP 4` și `cast storage $CAT 7`.
- **Împachetarea depinde de ordine.** `catalog` vine după `totalPoints` (slot întreg), deci începe un slot nou. Un `bool paused` declarat imediat după `admin` ar împărți slotul 0 cu el și ar muta toate variabilele următoare cu un slot.
- **O răscumpărare atinge storage-ul ambelor contracte.** Costul ei e dat în mare parte de numărul de sloturi *distincte* atinse (fiecare e „rece" la prima accesare).

### Costuri de gaz

Taxa unei tranzacții = `gasUsed × effectiveGasPrice`. Dacă depășești limita de gaz setată, tranzacția dă revert, dar gazul consumat până atunci **se plătește**.

Un slot sau o adresă e **cold** la prima accesare în tranzacție și **warm** după aceea.

| Operație | Gaz | Observații |
|---|---|---|
| Cost de bază al tranzacției | 21.000 | Plătit de orice tranzacție. De aceea gruparea mai multor operații într-una singură e mai ieftină. |
| Calldata | 4 / octet zero, 16 / octet nenul | Argumentele apelului. De aceea un `bytes32` cu zerouri la coadă costă mai puțin decât pare. |
| `SLOAD` (citire storage) | 2.100 cold, 100 warm | |
| `SSTORE` zero → nenul | 20.000 (+2.100 dacă e cold) | Cea mai scumpă operație obișnuită: creează o intrare permanentă în stare. |
| `SSTORE` nenul → alt nenul | 2.900 (+2.100 dacă e cold) | Actualizarea unei intrări existente. |
| `SSTORE` nenul → zero | 2.900 (+2.100 dacă e cold), **4.800 rambursate** | Rambursarea e limitată la 1/5 din gazul consumat. |
| `SSTORE` pe slot deja scris în tranzacție | 100 | De aceea câmpurile împachetate scrise împreună sunt ieftine. |
| Citire `constant` / `immutable` | 3 | Valoarea e în bytecode. |
| Apel extern (`CALL`, `STATICCALL`, `DELEGATECALL`) | 2.600 cold / 100 warm + codul executat | Trimiterea de ether cu `CALL` costă încă 9.000. |
| `LOG` (eveniment) | 375 + 375 / topic + 8 / octet de date | Mult mai ieftin decât storage-ul. |
| Memorie | 3 / cuvânt de 32 B + termen pătratic | Zonele foarte mari devin prohibitive (`cuvinte² / 512`). |
| Crearea unui contract | 32.000 + 200 / octet de cod | Dimensiune maximă: 24.576 octeți (EIP-170). |

#### `constant` vs `immutable`

Amândouă se citesc cu 3 gaz și nu pot fi modificate după deploy. Diferă **momentul** în care se cunoaște valoarea:

- **`constant`**: atribuită chiar la declarare, cu o expresie evaluabilă la compilare (`uint constant SECONDS_PER_DAY = 24 * 60 * 60;`). Aceeași valoare pentru orice deploy. Pot fi tipuri simple sau `string`.
- **`immutable`**: atribuită **o singură dată, în constructor** (`admin = msg.sender;`), deci poate depinde de argumentele constructorului. Fiecare deploy poate avea altă valoare. Doar tipuri simple.

În `FidelityPoints`, `admin` poate fi `immutable` (se setează în constructor și nu se schimbă), dar nu `constant`. `pointValue` trebuie să rămână în storage, pentru că `setPointValue` o schimbă.

#### `DELEGATECALL`

Costă ca un `CALL`, dar codul contractului apelat rulează **în contextul apelantului**: citește și scrie storage-ul *apelantului*, iar `msg.sender` și `msg.value` rămân cele originale. Dacă `FidelityPoints` ar apela `decreaseStock` prin `DELEGATECALL`, codul din `Catalog` ar interpreta storage-ul din `FidelityPoints` după layout-ul din `Catalog` (slotul 0, adică `admin`, ar fi citit ca lungimea lui `products`) și orice scriere ar strica `FidelityPoints`. Se folosește deliberat la **proxy-uri** și **biblioteci**, unde cele două contracte trebuie să aibă layout-uri de storage compatibile.

#### Concluzii practice

- **Scrierea în storage domină totul.** Adăugarea unui produs scrie cel puțin 5 sloturi noi (> 100.000 gaz), iar adunarea a două numere costă 3.
- **Aducerea la zero e răsplătită** prin rambursare, deci ștergerea datelor inutile (`delete`) e mai ieftină decât lăsarea lor.
- **Buclele peste array-uri din storage sunt scumpe și nemărginite.** `findProduct` citește un slot rece (2.100 gaz) pentru fiecare produs examinat, deci costul crește liniar. De la upgrade-ul Fusaka (decembrie 2025), o tranzacție poate consuma cel mult 2²⁴ = 16.777.216 gaz (EIP-7825): o funcție al cărei cost crește cu dimensiunea unui array poate deveni imposibil de executat.
- **Copierea nu e gratuită.** `Product memory p = products[i]` citește toate sloturile struct-ului, pe când `Product storage p = products[i]` urmat de `p.stock` citește un singur slot.
- **Evenimentele costă mult mai puțin decât storage-ul.** Un eveniment cu 3 topic-uri și 64 B de date ≈ 2.000 gaz, față de > 80.000 pentru un struct nou într-un array.

### Tehnici de optimizare a gazului

> Fiecare tehnică trebuie **măsurată** (Pasul 5) și cântărită față de lizibilitatea și siguranța codului.

- **Citește fiecare variabilă din storage cel mult o dată**: copiaz-o într-o variabilă locală și scrie înapoi o singură dată. În bucle, memorează `products.length` înainte de buclă.
- **Împachetează variabilele înrudite** (`uint128`, `uint64`, `uint40`, `uint8`) și declară-le consecutiv.  O conversie explicită la un tip mai mic (`uint128(price)`) **trunchiază în tăcere**, deci verifică intervalul.
- **Folosește `constant` și `immutable`**: 3 gaz în loc de 2.100.
- **Nu stoca ce se poate calcula sau loga**: `inStock` se deduce din `stock > 0`; un istoric de operații poate fi doar în evenimente.
- **Preferă mapping-urile pentru căutări**: O(1) față de O(n) într-un array. Dacă ai nevoie și de enumerare, ține împreună un array și un mapping cheie → index.
- **Grupează operațiile într-o tranzacție** (ex. `addPointsBatch`): plătești 21.000 o singură dată și actualizezi `totalPoints` o singură dată, după buclă.
- **`calldata`** pentru parametrii array/string read-only ai funcțiilor `external`; **erori personalizate** în loc de mesaje string; **`unchecked { ... }`** pentru aritmetică ce nu poate depăși limitele. De la Solidity 0.8.22, verificarea overflow a contorului din buclele `for` simple se omite automat.
- **Activează optimizatorul** în `foundry.toml`: `optimizer = true`, `optimizer_runs = <n>`. Un `runs` mic favorizează bytecode mic (deploy ieftin), unul mare favorizează execuție ieftină.

## Lucrul practic

### Pasul 1: Configurarea proiectului

Se creează un proiect Foundry nou și se copiază în el soluțiile Laboratorului 3, redenumind fișierele și contractele:

```bash
forge init fidelity-shop
cd fidelity-shop
rm src/Counter.sol test/Counter.t.sol script/Counter.s.sol
cp <cale lab4>/src/FidelityPointsFinal.sol src/FidelityPoints.sol
cp <cale lab4>/src/CatalogFinal.sol src/Catalog.sol
sed -i 's/contract FidelityPointsFinal/contract FidelityPoints/' src/FidelityPoints.sol
sed -i 's/contract CatalogFinal/contract Catalog/' src/Catalog.sol
forge build
```

Citește ambele contracte și identifică elementele care rezolvă fiecare exercițiu din Laboratorul 3: modifierul `onlyAdmin` și eroarea `NotAdmin`, `totalPoints` și funcția internă care îl actualizează, câmpul `stock` și funcțiile care îl modifică, mapping-ul `productPromos`, funcția `getProducts` și funcția `pure` `discountedPrice`. Funcția `getPrice` întoarce prețul unui produs după cea mai bună promoție activă în acel moment și este folosită în Exercițiul 1.

În primul terminal pornește `anvil`; în al doilea, setează aceleași variabile ca în Laboratorul 3:

```bash
export ETH_RPC_URL=http://127.0.0.1:8545
ANVIL_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80   # contul 0 anvil
CLIENT=0x70997970C51812dc3A010C7d01b50e0d17dc79C8                              # contul 1 anvil
CLIENT_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
```

### Pasul 2: Inspectarea layout-ului de storage

```bash
forge inspect Catalog storageLayout
```

| Nume | Tip | Slot |
|---|---|---|
| `products` | `struct Catalog.Product[]` | 0 |
| `generalPromo` | `struct Catalog.Promo` | 1 |
| `admin` | `address` | 5 |
| `productPromos` | `mapping(bytes32 => struct Catalog.Promo)` | 6 |

`generalPromo` ocupă sloturile 1–4 (patru membri, fiecare cu un slot întreg), de aceea `admin` începe la slotul 5.

După ce implementezi `Catalog` și adaugi produse, citești storage-ul „de mână":

```bash
cast storage $CAT 0                                   # lungimea lui products
BASE=$(cast keccak $(cast to-uint256 0))              # primul slot al lui products[0]
slot() { python3 -c "print(hex(int('$1', 16) + $2))"; }
cast storage $CAT $BASE                               # products[0].code
cast storage $CAT $(slot $BASE 1)                     # products[0].description
cast --to-dec $(cast storage $CAT $(slot $BASE 7))    # products[1].price = BASE + 5*1 + 2
```

(Numerele de slot sunt pe 256 de biți, de aceea adunarea se face în Python.)

Descrierea `"Coffee mug"` are 10 octeți, deci stă chiar în slotul câmpului, iar ultimul octet este `0x14` = 2 × 10. Pentru o promoție din mapping, struct-ul începe la slotul dat de `cast index`, iar `percent` e al patrulea membru:

```bash
PROMO=$(cast index bytes32 $(cast format-bytes32-string "P001") 6)
cast --to-dec $(cast storage $CAT $(slot $PROMO 3))   # percent: 20
```

### Pasul 3: Măsurarea gazului consumat

Se acordă puncte de trei ori: de două ori aceluiași client și o dată altuia, afișând `gasUsed` după fiecare tranzacție. Rezultate aproximative:

| Tranzacție | Gaz | `points[client]` | `totalPoints` |
|---|---|---|---|
| primul `addPoints` către `CLIENT` | 69.201 | 0 → 100 | 0 → 100 |
| al doilea `addPoints` către `CLIENT` | 35.001 | 100 → 200 | 100 → 200 |
| primul `addPoints` către `CLIENT2` | 52.089 | 0 → 100 | 200 → 300 |

**Același cod, consum foarte diferit.** Diferența dintre primele două, 34.200 gaz, este `2 × (20.000 − 2.900)`: în prima tranzacție **ambele** sloturi trec din zero în nenul, în a doua doar se actualizează. În a treia se schimbă din zero doar slotul noului client.

De gândit: de ce cheltuirea **tuturor** punctelor unui client costă cu ~4.800 gaz mai puțin decât cheltuirea unei părți? (Indiciu: rambursarea de la `SSTORE` nenul → zero.) Gazul se poate estima și înainte de trimitere: `cast estimate`.

### Pasul 4: Tranzacții eșuate și datele erorii

Un client apelează `addPoints` (permis doar adminului). `cast` estimează gazul, estimarea dă revert, deci tranzacția **nu se trimite** și se afișează datele erorii:

```bash
cast sig "NotAdmin(address)"                                   # selectorul: 0x17a84242
cast decode-error <date eroare> --sig "NotAdmin(address)"
```

Dacă forțezi trimiterea cu `--gas-limit 100000`, tranzacția intră într-un bloc cu `status 0 (failed)`: **starea nu se schimbă, dar clientul plătește gazul consumat** (~24.700).

### Pasul 5: Măsurarea gazului în teste

```bash
forge test --gas-report     # gaz per funcție: min, medie, mediană, max
forge snapshot              # scrie gazul fiecărui test în .gas-snapshot
forge snapshot --diff       # compară gazul curent cu snapshot-ul
forge build --sizes         # dimensiunea bytecode-ului fiecărui contract
```

Flux de optimizare: `forge snapshot` → modifici codul → `forge snapshot --diff`.

Într-un test, toate apelurile rulează într-o singură tranzacție, deci sloturile atinse în `setUp` sunt deja „calde" și gazul raportat e mai mic decât pe o rețea reală. Opțiunea `--isolate` rulează fiecare apel de nivel superior ca tranzacție separată (valori mai apropiate de Pasul 3). Un apel anume se măsoară cu `vm.startSnapshotGas` / `vm.stopSnapshotGas`.

### Pasul 6: Interacțiunea dintre contracte și propagarea erorilor

Fișierul `ContractInteraction.sol` conține două contracte mici:

- **`A`** are `int public a` și `setA(int value)`. Funcția modifică `a` **înainte** de verificări, ca să se vadă dacă modificarea supraviețuiește unui revert. Poate eșua în 3 feluri: eroarea personalizată `NegativeValue` (valoare negativă), `Error(string)` pentru 13 și `Panic(0x12)` pentru 10 (împărțire la zero).
- **`B`** are `int public b`, referința la `A` și contoare pentru fiecare tip de eroare. `setDirect` apelează `A` direct; `setWithTry` îl apelează în `try`/`catch`.

**Scenariul 1: `B` apelează `A` direct și `A` dă revert.**
Eroarea afișată e cea din `A` (`NegativeValue(-7)` sau `Error("Unlucky value")`), deși tranzacția a fost trimisă lui `B`: eroarea a **urcat** prin `B`. Atât `a`, cât și `b` rămân neschimbate, pentru că revert-ul anulează **toate** modificările tranzacției, în ambele contracte.

**Scenariul 2: `B` apelează `A` în `try`/`catch`.**
Tranzacțiile **reușesc**. Când `A` dă revert, se anulează doar modificările făcute *în interiorul apelului către A*, deci `a` își păstrează valoarea. `B` prinde eroarea și continuă, deci `b` ia valoarea nouă, iar contorul clauzei `catch` corespunzătoare crește. `NegativeValue` ajunge în `catch (bytes memory)`, fiindcă nu există clauză pentru o eroare personalizată anume.

| `A` dă revert și… | `a` | `b` | Tranzacția | Eroarea primită de expeditor |
|---|---|---|---|---|
| `B` apelează `A` direct | neschimbat | neschimbat | eșuată | eroarea din `A` |
| `B` apelează `A` în `try`/`catch` | neschimbat | actualizat | reușită | niciuna; `B` o tratează |

Gazul consumat de `A` înainte de revert se plătește oricum. Traseul execuției se vede cu `cast run <hash>`. Același mecanism e folosit în Exercițiul 1.6.

> Un număr negativ ar fi luat de `cast` drept opțiune, de aceea opțiunile se dau primele, iar argumentele după `--`: `cast send --private-key $ANVIL_KEY $B "setDirect(int256)" -- -7`.

## Exerciții

| # | Tema | Ce se cere, pe scurt |
|---|---|---|
| **1** | **Răscumpărarea punctelor** | Interfața `ICatalog`, `setCatalog`, funcția `redeem` (preț din catalog, puncte rotunjite în sus, eroarea `InsufficientPoints`, ordinea *checks–effects–interactions*); în `Catalog`, `fidelityProgram` și un modifier pentru `decreaseStock` (doar admin sau programul de fidelitate); răspunde ce `msg.sender` vede `Catalog` și de ce nu se folosește `tx.origin`; ce eroare primește clientul pentru un produs inexistent; `redeem` cu `try`/`catch`, care restituie punctele, întoarce `false` și numără eșecurile pe 3 contoare (`Error`, `Panic`, `bytes`). |
| **2** | **Evenimente** | `PointsAdded`, `PointsSpent`, `PointValueChanged`, `PointsRedeemed`, `RedemptionFailed` în `FidelityPoints`; `ProductAdded`, `StockChanged`, `PromoStarted` în `Catalog`; citirea lor cu `cast logs`; compararea unui istoric în storage (`Redemption[]`) cu un eveniment: când e necesar storage-ul? |
| **3** | **Modifiers și erori** | `paused` cu `pause()`/`unpause()`, `whenNotPaused`/`whenPaused`; modifierul `validAmount`; efectul **ordinii** modifierelor asupra erorii primite; `assert` pentru invariantul `totalPoints` și diferența față de `require`; mutarea corpului lui `onlyAdmin` în `_checkAdmin()` și comparația dimensiunii bytecode-ului. |
| **4** | **Teste** | `test/Redeem.t.sol` cu `setUp` care instalează ambele contracte: redemption reușit + `vm.expectEmit`, rotunjire în sus și promoții, `InsufficientPoints`, acces interzis la `decreaseStock`, cantitate > stoc (returnează `false`, restituie punctele, crește contorul `Panic`), blocarea în starea `paused`. Apoi `forge test --gas-report --isolate`. |
| **5** | **Layout și packing** | Citirea directă din storage a stocului și a datei de final a promoției; împachetarea `Promo` (`uint40`, `uint40`, `uint8`) și `Product` (`uint128`, `uint64`, `bool`); `forge snapshot --diff`; trunchierea la `uint128(price)` și verificările necesare; de ce `uint40` ajunge pentru un timestamp; eliminarea câmpului redundant `inStock`. |
| **6** | **Array-uri și mapping-uri** | Costul `decreaseStock` pentru primul vs. ultimul din 100 de produse; `productIndex` (poziție **+ 1**, de ce?) pentru a elimina bucla din `findProduct`; `removeProduct` cu *swap and pop*; `getProducts(offset, limit)` cu paginare, față de limita de 16.777.216 gaz. |
| **7** | **Optimizarea `FidelityPoints`** | `admin` ca `immutable`; o singură citire din storage + scădere `unchecked`; `addPointsBatch` cu `calldata` vs. `memory`; erori personalizate vs. `require` cu mesaj; `optimizer_runs = 1` vs. `1000000`. Rezultatele se notează într-un tabel *Funcție / Gaz înainte / Gaz după / Tehnică*. |
| **8** | **Deploy pe Sepolia** | Deploy, legarea contractelor, adăugarea unui produs, acordarea de puncte unui coleg care face `redeem`; analiza tab-ului *Logs* din Etherscan; compararea `gasUsed` cu cel de pe `anvil` și calculul costului în ether; adresele contractelor și hash-urile tranzacțiilor intră în raport. |

## Referințe

1. Solidity, [*Function modifiers*](https://docs.soliditylang.org/en/latest/contracts.html#function-modifiers)
2. Solidity, [*Error handling*](https://docs.soliditylang.org/en/latest/control-structures.html#error-handling-assert-require-revert-and-exceptions)
3. Solidity, [*try/catch*](https://docs.soliditylang.org/en/latest/control-structures.html#try-catch)
4. Solidity, [*Events*](https://docs.soliditylang.org/en/latest/contracts.html#events)
5. Solidity, [*Contract ABI specification: events*](https://docs.soliditylang.org/en/latest/abi-spec.html#events)
6. Solidity, [*Interfaces*](https://docs.soliditylang.org/en/latest/contracts.html#interfaces)
7. Solidity, [*External function calls*](https://docs.soliditylang.org/en/latest/control-structures.html#external-function-calls)
8. Solidity, [*Checks-effects-interactions*](https://docs.soliditylang.org/en/latest/security-considerations.html#use-the-checks-effects-interactions-pattern)
9. Solidity, [*Layout of state variables in storage*](https://docs.soliditylang.org/en/latest/internals/layout_in_storage.html)
10. ethereum.org, [*Gas and fees*](https://ethereum.org/en/developers/docs/gas/)
11. [EIP-2929](https://eips.ethereum.org/EIPS/eip-2929): costuri de gaz pentru accesul la stare
12. [EIP-3529](https://eips.ethereum.org/EIPS/eip-3529): reducerea rambursărilor
13. [EVM Codes](https://www.evm.codes/): referință interactivă pentru opcode-uri și gaz
14. [EIP-7825](https://eips.ethereum.org/EIPS/eip-7825): limita de gaz pe tranzacție
15. Solidity, [*Constant and immutable*](https://docs.soliditylang.org/en/latest/contracts.html#constant-and-immutable-state-variables)
16. Solidity, [*The optimizer*](https://docs.soliditylang.org/en/latest/internals/optimizer.html)
17. Foundry, [*forge inspect*](https://getfoundry.sh/forge/reference/forge-inspect)
18. Foundry, [*Gas tracking*](https://getfoundry.sh/forge/gas-tracking) și [*Gas reports*](https://getfoundry.sh/forge/gas-reports)
19. Foundry, [*Gas function snapshots*](https://getfoundry.sh/forge/gas-function-snapshots) și [*Gas section snapshots*](https://getfoundry.sh/forge/gas-section-snapshots)
20. Foundry, [*expectEmit*](https://getfoundry.sh/reference/cheatcodes/expect-emit)
21. Foundry, [*cast logs*](https://getfoundry.sh/cast/reference/logs)
22. Solidity, [*Conversions between elementary types*](https://docs.soliditylang.org/en/latest/types.html#conversions-between-elementary-types)
23. [Etherscan Sepolia](https://sepolia.etherscan.io/)

**Resurse suplimentare:** [documentația Solidity](https://docs.soliditylang.org/en/latest/) · [Remix IDE](https://remix.ethereum.org/) · [convertor bytes32](https://web3-type-converter.onbrn.com/)

