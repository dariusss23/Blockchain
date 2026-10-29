# Contracte inteligente în Solidity — Laboratorul 4

**Teme:** interacțiunea dintre contracte, gestionarea erorilor, evenimente, organizarea stocării și optimizarea consumului de gas  
**Instrumente:** Foundry (`forge`, `cast`), Anvil, Solidity, Sepolia, Etherscan

## Cuprins

- [Prezentare generală](#prezentare-generală)
- [Concepte-cheie](#concepte-cheie)
  - [Modificatori de funcții](#modificatori-de-funcții)
  - [Erori și revert](#erori-și-revert)
  - [`try`/`catch`](#trycatch)
  - [Evenimente](#evenimente)
  - [Interacțiunea dintre contracte](#interacțiunea-dintre-contracte)
  - [Organizarea stocării](#organizarea-stocării)
  - [Costuri de gas și optimizare](#costuri-de-gas-și-optimizare)
- [Configurarea practică](#configurarea-practică)
- [Exerciții](#exerciții)
- [Comenzi utile](#comenzi-utile)
- [Referințe](#referințe)

## Prezentare generală

Acest laborator continuă platforma de **puncte de fidelitate** din Laboratorul 3. Contractul `FidelityPoints` este conectat la contractul `Catalog`, astfel încât clienții să poată folosi punctele pentru a cumpăra produse. Ulterior, contractele sunt extinse cu evenimente, o gestionare mai precisă a erorilor, teste și optimizări ale consumului de gas.

## Concepte-cheie

### Modificatori de funcții

Un modificator schimbă comportamentul unei funcții, de obicei verificând o condiție înainte de executarea corpului funcției.

```solidity
modifier onlyAdmin() {
    if (msg.sender != admin) revert NotAdmin(msg.sender);
    _;
}
```

- `_;` indică locul în care este executat corpul funcției modificate.
- Modificatorii pot primi argumente, de exemplu `validAmount(_points)`.
- Dacă o funcție are mai mulți modificatori, aceștia se execută în ordinea în care sunt scriși.
- Modificatorii lungi, folosiți de multe funcții, pot mări dimensiunea bytecode-ului contractului. Mutarea logicii într-o funcție `internal` poate reduce duplicarea codului.

### Erori și revert

Un `revert` anulează toate modificările de stare efectuate în apelul eșuat și returnează informații despre eroare.

```solidity
error NotAdmin(address caller);

if (msg.sender != admin) {
    revert NotAdmin(msg.sender);
}
```

- `require(condition, "message")` verifică parametrii sau starea contractului și declanșează un `revert` dacă expresia este falsă.
- `revert CustomError(args)` și `revert("message")` declanșează explicit o eroare.
- `assert(condition)` verifică invariante care ar trebui să fie întotdeauna adevărate dacă programul funcționează corect. Eșecul unui `assert` indică, de regulă, o eroare în implementare.
- **Erorile personalizate** (*custom errors*) sunt, în general, mai eficiente decât mesajele text, deoarece codifică un selector și argumentele, nu un șir de caractere complet.
- Coduri `Panic` întâlnite frecvent: `0x01` — `assert` eșuat; `0x11` — depășire sau scădere sub limită la operații aritmetice; `0x12` — împărțire la zero; `0x32` — index de tablou în afara limitelor.
- Dacă un apel extern declanșează un `revert`, eroarea se propagă, în mod normal, către contractul apelant, cu excepția cazului în care acesta o gestionează prin `try`/`catch`.

### `try`/`catch`

Folosește `try`/`catch` pentru a gestiona eșecul unui apel către un contract extern sau al creării unui contract.

```solidity
try catalog.decreaseStock(code, quantity) {
    // Apelul extern s-a încheiat cu succes.
} catch Error(string memory reason) {
    // Eroare de tip Error(string), de exemplu generată de require("mesaj").
} catch Panic(uint errorCode) {
    // Eroare Panic din Solidity, de exemplu împărțirea la zero.
} catch (bytes memory lowLevelData) {
    // Alte erori, inclusiv erori personalizate.
}
```

Erorile personalizate nu au o clauză `catch` dedicată; ele ajung în clauza generală care primește `bytes`. `try`/`catch` gestionează erorile apelului extern, nu orice eroare apărută în contractul apelant. Dacă apelantul declanșează ulterior un `revert`, toate modificările sale — inclusiv cele făcute în clauza `catch` — sunt anulate.

### Evenimente

Evenimentele scriu informații în jurnalele tranzacțiilor (*logs*), pe care aplicațiile din afara blockchainului le pot căuta sau la care se pot abona.

```solidity
event PointsAdded(address indexed client, uint amount);

emit PointsAdded(client, _points);
```

- O înregistrare (*log*) conține adresa contractului care a emis evenimentul, câmpurile `topics` și datele.
- Hash-ul semnăturii evenimentului este primul `topic`.
- Fiecare parametru marcat `indexed` devine un `topic`; pot exista cel mult trei parametri `indexed`.
- Jurnalele sunt mai ieftine decât stocarea persistentă, dar **contractele nu pot citi jurnalele**. Dacă o informație trebuie folosită ulterior de codul on-chain, ea trebuie păstrată în stocarea contractului.

### Interacțiunea dintre contracte

Un contract poate apela alt contract folosind adresa acestuia și o interfață compatibilă.

```solidity
interface ICatalog {
    function getPrice(bytes32 code) external view returns (uint);
    function decreaseStock(bytes32 code, uint amount) external;
}

ICatalog catalog = ICatalog(catalogAddress);
uint price = catalog.getPrice(code);
```

Aspecte importante:

- În timpul unui apel din `FidelityPoints` către `Catalog`, contractul `Catalog` vede **contractul `FidelityPoints` ca `msg.sender`**, nu clientul inițial.
- Nu folosi `tx.origin` pentru autorizare. Acesta poate permite unui alt contract din lanțul de apeluri să acționeze în numele expeditorului inițial al tranzacției.
- Respectă modelul **checks–effects–interactions**: verifică întâi condițiile, actualizează apoi starea locală și abia după aceea apelează contractele externe.
- Apelurile `view` executate prin `eth_call` nu consumă gas de tranzacție, însă un apel `view` efectuat în interiorul unei tranzacții consumă gas.
- Apelurile externe au costuri suplimentare pentru accesarea adresei, codificarea argumentelor, execuție și decodificarea datelor returnate.

### Organizarea stocării

Solidity stochează starea contractului în sloturi de câte 32 de octeți. Fiecare contract are propria zonă de stocare, independentă de celelalte.

- Tipurile de date cu dimensiune fixă pot fi grupate în același slot dacă variabilele alăturate încap în spațiul disponibil.
- Valorile `constant` și `immutable` sunt incluse în bytecode, în loc să fie păstrate în sloturile obișnuite ale stării.
- Tablourile dinamice își păstrează lungimea în slotul `p`, iar elementele încep de la poziția determinată de `keccak256(p)`.
- Valorile unui `mapping` sunt stocate la poziții calculate cu ajutorul hash-urilor. Un `mapping` nu poate fi parcurs sau golit integral, deoarece contractul nu ține evidența tuturor cheilor.
- Șirurile și valorile `bytes` scurte (de până la 31 de octeți) sunt stocate chiar în slot; valorile mai lungi sunt stocate începând de la o poziție calculată prin hash.
- Poți inspecta organizarea stocării unui contract folosind:

```bash
forge inspect Catalog storageLayout
forge inspect FidelityPoints storageLayout
```

După conectarea contractelor, organizarea generală a stocării, conform laboratorului, este următoarea:

**`FidelityPoints`**

| Slot | Variable |
|---:|---|
| 0 | `admin` |
| 1 | `pointValue` |
| 2 | `points` mapping (mapping values are stored at hash-derived slots) |
| 3 | `totalPoints` |
| 4 | `catalog` |

**`Catalog`**

| Slot | Variable |
|---:|---|
| 0 | `products` array |
| 1–4 | `generalPromo` |
| 5 | `admin` |
| 6 | `productPromos` mapping |
| 7 | `fidelityProgram` |

Organizarea exactă depinde de ordinea declarațiilor și de tipurile variabilelor. Verific-o din nou după orice modificare a contractelor.

### Costuri de gas și optimizare

Taxele unei tranzacții depind de cantitatea de gas consumată și de prețul efectiv al gas-ului. Scrierile în stocare se numără, în general, printre operațiile uzuale cele mai costisitoare.

Useful rules of thumb from the laboratory:

| Operation | Approximate gas |
|---|---:|
| Base transaction cost | 21,000 |
| `SLOAD` — cold / warm | 2,100 / 100 |
| `SSTORE` — zero to non-zero | 20,000, plus cold-access cost if applicable |
| `SSTORE` — non-zero to non-zero | 2,900, plus cold-access cost if applicable |
| `SSTORE` — non-zero to zero | 2,900, plus cold-access cost; a refund may apply |
| Cold / warm external contract address access | 2,600 / 100 |
| Event log | 375 + 375 per topic + 8 per data byte |
| Contract creation | 32,000 + 200 per byte of deployed code |

Valorile sunt aproximative și depind de operație, contextul tranzacției și regulile rețelei folosite.

Tehnici de optimizare pe care le poți măsura și compara:

- Citește variabilele din stocare o singură dată și păstrează valorile în variabile locale.
- Grupează câmpurile în tipuri întregi mai mici atunci când intervalele valorilor sunt cunoscute și verificate.
- Folosește `constant` și `immutable` pentru valorile care nu se modifică.
- Evită stocarea informațiilor care pot fi calculate din alte date sau reprezentate prin evenimente.
- Folosește `mapping` pentru căutări după cheie, în loc să parcurgi repetat tablouri.
- Grupează operațiile asociate într-o singură tranzacție atunci când este potrivit.
- Pentru parametrii doar pentru citire ai funcțiilor externe, preferă `calldata`.
- Folosește erori personalizate în locul mesajelor text pentru `revert`, atunci când este potrivit.
- Folosește `unchecked` numai dacă poți demonstra că operația aritmetică nu poate depăși limitele tipului și nici nu poate coborî sub limita minimă.
- Activează optimizatorul Solidity în `foundry.toml` și măsoară efectul valorilor diferite pentru `optimizer_runs`.

## Configurarea practică

### 1. Creează proiectul Foundry

Pornește de la soluțiile Laboratorului 3. Redenumește fișierele și contractele conform comenzilor de mai jos.

```bash
forge init fidelity-shop
cd fidelity-shop

rm src/Counter.sol test/Counter.t.sol script/Counter.s.sol
cp <path-to-lab4>/src/FidelityPointsFinal.sol src/FidelityPoints.sol
cp <path-to-lab4>/src/CatalogFinal.sol src/Catalog.sol

sed -i 's/contract FidelityPointsFinal/contract FidelityPoints/' src/FidelityPoints.sol
sed -i 's/contract CatalogFinal/contract Catalog/' src/Catalog.sol

forge build
```

Inspectează ambele contracte și identifică modificatorul `onlyAdmin`, eroarea `NotAdmin`, variabila `totalPoints`, gestionarea stocului, `productPromos`, `getProducts` și `discountedPrice`.

### 2. Pornește Anvil și configurează conturile

Într-un terminal, rulează:

```bash
anvil
```

Într-un al doilea terminal, setează adresa RPC locală și conturile Anvil folosite ca exemplu în laborator:

```bash
export ETH_RPC_URL=http://127.0.0.1:8545

# Contul Anvil 0 — doar pentru dezvoltare locală
ANVIL_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Contul Anvil 1
CLIENT=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
CLIENT_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
```

> **Securitate:** Acestea sunt chei de dezvoltare Anvil cunoscute public. Nu le folosi niciodată pentru fonduri reale sau pe o rețea reală.

### 3. Inspectează stocarea și publică `Catalog`

```bash
forge inspect Catalog storageLayout

forge create src/Catalog.sol:Catalog \
  --private-key $ANVIL_KEY --broadcast
CAT=<deployed-catalog-address>

cast send $CAT "addProduct(bytes32,string,uint256,uint256)" \
  $(cast format-bytes32-string "P001") "Coffee mug" 50 10 \
  --private-key $ANVIL_KEY

cast send $CAT "addProduct(bytes32,string,uint256,uint256)" \
  $(cast format-bytes32-string "P002") "T-shirt" 100 5 \
  --private-key $ANVIL_KEY
```

Pentru un tablou aflat în slotul de stocare `0`, primul element începe la poziția `keccak256(0)`. În laborator, fiecare structură `Product` ocupă inițial cinci sloturi.

```bash
cast storage $CAT 0
BASE=$(cast keccak $(cast to-uint256 0))
slot() { python3 -c "print(hex(int('$1', 16) + $2))"; }

cast storage $CAT $BASE
cast storage $CAT $(slot $BASE 1)
cast --to-dec $(cast storage $CAT $(slot $BASE 7))
```

Start a product promotion and inspect its mapping entry:

```bash
cast send $CAT "startProductPromo(bytes32,uint256,uint256)" \
  $(cast format-bytes32-string "P001") 7 20 --private-key $ANVIL_KEY

PROMO=$(cast index bytes32 $(cast format-bytes32-string "P001") 6)
cast --to-dec $(cast storage $CAT $(slot $PROMO 3))
```

### 4. Measure gas for `addPoints`

```bash
forge create src/FidelityPoints.sol:FidelityPoints \
  --private-key $ANVIL_KEY --broadcast --constructor-args 10
FP=<deployed-fidelity-points-address>

CLIENT2=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC

cast send $FP "addPoints(address,uint256)" $CLIENT 100 \
  --private-key $ANVIL_KEY | grep gasUsed
cast send $FP "addPoints(address,uint256)" $CLIENT 100 \
  --private-key $ANVIL_KEY | grep gasUsed
cast send $FP "addPoints(address,uint256)" $CLIENT2 100 \
  --private-key $ANVIL_KEY | grep gasUsed
```

The lab's approximate results are:

| Transaction | Gas used |
|---|---:|
| First award to `CLIENT` | 69,201 |
| Second award to `CLIENT` | 35,001 |
| First award to `CLIENT2` | 52,089 |

The difference comes mainly from whether the client's points slot is being initialized from zero or updated from a non-zero value.

Estimate gas before sending a transaction:

```bash
cast estimate $FP "addPoints(address,uint256)" $CLIENT 100 \
  --from $(cast wallet address --private-key $ANVIL_KEY)
```

### 5. Inspect failed transactions and error data

```bash
cast send $FP "addPoints(address,uint256)" $CLIENT 1 \
  --private-key $CLIENT_KEY

cast sig "NotAdmin(address)"
cast decode-error <error-data> --sig "NotAdmin(address)"
```

To force a reverting transaction to be included in a local block rather than failing during gas estimation:

```bash
cast send $FP "addPoints(address,uint256)" $CLIENT 1 \
  --private-key $CLIENT_KEY --gas-limit 100000
```

A failed transaction does not keep its state changes, but gas is still charged when the transaction is included in a block.

### 6. Measure gas in tests

```bash
forge test --gas-report
forge snapshot
forge snapshot --diff
forge build --sizes
```

For a focused gas measurement in a test:

```solidity
function test_GasAddPoints() public {
    vm.startSnapshotGas("addPoints");
    fp.addPoints(client, 100);
    uint gasUsed = vm.stopSnapshotGas();
    emit log_named_uint("addPoints gas", gasUsed);
}
```

Run the specific test in isolation:

```bash
forge test --match-test test_GasAddPoints -vv --isolate
```

Test measurements may differ from real transactions because calls in a test can share a transaction context and reuse warm storage slots.

### 7. Study error propagation with two contracts

Copy the example contract file into the project:

```bash
cp <path-to-lab4>/src/ContractInteraction.sol src/
```

Deploy `A`, then deploy `B` with `A`'s address as its constructor argument:

```bash
forge create src/ContractInteraction.sol:A \
  --private-key $ANVIL_KEY --broadcast
A=<deployed-A-address>

forge create src/ContractInteraction.sol:B \
  --private-key $ANVIL_KEY --broadcast --constructor-args $A
B=<deployed-B-address>
```

Try direct calls and calls handled by `try`/`catch`:

```bash
cast send $B "setDirect(int256)" 5 --private-key $ANVIL_KEY
cast send --private-key $ANVIL_KEY $B "setDirect(int256)" -- -7
cast send --private-key $ANVIL_KEY $B "setDirect(int256)" 13

cast send --private-key $ANVIL_KEY $B "setWithTry(int256)" -- -7
cast send --private-key $ANVIL_KEY $B "setWithTry(int256)" 13
cast send --private-key $ANVIL_KEY $B "setWithTry(int256)" 10
cast send --private-key $ANVIL_KEY $B "setWithTry(int256)" 20
```

Inspect a transaction's internal execution trace:

```bash
cast run <transaction-hash>
```

When `B` calls `A` directly and `A` reverts, the entire transaction reverts. When `B` catches the external error, changes made by `B` can persist while changes inside the failed call to `A` are rolled back.

## Exerciții

### Exercițiul 1 — Redeeming points in the catalog

1. Add the `ICatalog` interface, a `catalog` state variable, and an admin-only `setCatalog(address)` function to `FidelityPoints`.
2. Implement `redeem(bytes32 code, uint quantity)`. Obtain the current catalog price, calculate required points with rounding up, validate the client's balance, update points and `totalPoints`, and then decrease stock. Use custom errors for insufficient points and invalid configuration/quantity.
3. Restrict `Catalog.decreaseStock` to the administrator or the linked fidelity program. Add `fidelityProgram` and `setFidelityProgram(address)`.
4. Deploy and link the contracts, add a product, award points, and redeem it:

   ```bash
   cast send $FP "setCatalog(address)" $CAT --private-key $ANVIL_KEY
   cast send $CAT "setFidelityProgram(address)" $FP --private-key $ANVIL_KEY
   cast send $FP "redeem(bytes32,uint256)" \
     $(cast format-bytes32-string "P001") 2 --private-key $CLIENT_KEY
   ```

5. Verify the client's points, `getTotalPoints()`, and product stock. Start a promotion and verify the new redemption price.
6. Try redeeming a non-existent product and explain how the catalog's error reaches the client.
7. Use `try`/`catch` around `decreaseStock`. On failure, restore the points and `totalPoints`, return `false`, and increment separate counters for `Error(string)`, `Panic(uint)` and generic errors. Verify each path and explain why the counters would be rolled back if the entire redemption reverted afterward.

### Exercițiul 2 — Evenimente

1. Add and emit these events in `FidelityPoints`:
   - `PointsAdded(address indexed client, uint amount)`
   - `PointsSpent(address indexed client, uint amount)`
   - `PointValueChanged(uint oldValue, uint newValue)`
   - `PointsRedeemed(address indexed client, bytes32 indexed code, uint quantity, uint pointsSpent)`
   - `RedemptionFailed(address indexed client, bytes32 indexed code, bytes reason)`
2. Add `ProductAdded`, `StockChanged`, and `PromoStarted` events to `Catalog`. Use `bytes32(0)` for a general promotion.
3. Retrieve logs and filter redemption events for one client:

   ```bash
   cast logs --from-block 0 --address $FP \
     "PointsAdded(address indexed client, uint256 amount)"

   cast logs --from-block 0 --address $FP \
     "PointsRedeemed(address indexed, bytes32 indexed, uint256, uint256)" $CLIENT

   cast sig-event "PointsRedeemed(address,bytes32,uint256,uint256)"
   ```

4. Inspect the receipt of a redemption and identify logs emitted by each contract. Compare an event with storing the same history in an array; estimate and measure the gas, and explain when persistent storage is necessary.

### Exercițiul 3 — Modificatori și erori

1. Add `paused`, `pause()` and `unpause()`, restricted to the administrator. While paused, points cannot be added, spent or redeemed; the point value can only be changed while paused.
2. Implement `validAmount(uint amount)` with a custom error and apply it to `addPoints`, `spendPoints` and `redeem`.
3. Apply multiple modifiers to `addPoints`, change their order, and compare the error returned to a client when the program is paused.
4. Use `assert` to check the `totalPoints` invariant after spending or redeeming. Explain why `assert` is appropriate for invariants but not for ordinary input validation.
5. Run `forge build --sizes`. Move the body of `onlyAdmin` into `_checkAdmin()` and compare bytecode sizes.

### Exercițiul 4 — Testare

Creează fișierul `test/Redeem.t.sol`. Funcția `setUp` trebuie să publice și să conecteze cele două contracte, să adauge produse și să acorde puncte unui client de test.

Scrie teste care să verifice următoarele:

- A successful redemption updates the client's points, `totalPoints`, and stock, and emits `PointsRedeemed`.
- Points are rounded up correctly (e.g. price 55 and point value 10 requires 6 points) and an active promotion reduces the cost.
- Insufficient points reverts with the correct `InsufficientPoints(required, available)` values.
- A client cannot call `decreaseStock` directly.
- A redemption exceeding stock returns `false`, restores points, and increments the relevant failure counter.
- `addPoints`, `spendPoints` and `redeem` revert while paused.

Rulează:

```bash
forge test --gas-report --isolate
```

Notează cantitatea de gas consumată de `redeem` și estimează cât din aceasta provine din apelurile externe către catalog.

### Exercițiul 5 — Organizarea stocării și gruparea variabilelor

1. Read the second product's stock and the end date of the general promotion directly from storage.
2. Run `forge snapshot`, then pack the structs:

   ```solidity
   struct Promo {
       State state;
       uint40 start;
       uint40 end;
       uint8 percent;
   }

   struct Product {
       bytes32 code;
       string description;
       uint128 price;
       uint64 stock;
       bool inStock;
   }
   ```

3. Rulează din nou `forge inspect Catalog storageLayout`. Compară dimensiunile structurilor și sloturile afectate.
4. Run `forge snapshot --diff` and explain the effect on `addProduct`, `startProductPromo`, `decreaseStock` and `redeem`.
5. Verifică limitele înainte de conversia unui `uint` la `uint128`; demonstrează că o conversie la un tip mai mic, fără verificarea limitelor, poate trunchia valorile.
6. Explică de ce `uint40` este suficient pentru marcajele temporale (*timestamps*).
7. Elimină câmpul redundant `inStock` dacă valoarea lui poate fi dedusă din `stock > 0`, apoi măsoară din nou consumul de gas și actualizează funcțiile și testele afectate.

### Exercițiul 6 — Tablouri și mapping-uri

1. Adaugă 100 de produse și măsoară consumul de gas pentru `decreaseStock` sau `redeem` asupra primului și ultimului produs.
2. Adaugă `mapping(bytes32 => uint) productIndex`, în care salvezi indexul fiecărui produs plus unu. Rescrie `findProduct` astfel încât să nu mai parcurgă tabloul, să prevină codurile duplicate și măsoară impactul asupra consumului de gas.
3. Implementează funcția `removeProduct(bytes32 code)`, accesibilă doar administratorului, folosind metoda **swap and pop**. Menține corectă asocierea din `mapping` și elimină promoția produsului. Explică de ce `delete products[i]`, folosit singur, nu este suficient.
4. Estimează costul apelului `getProducts(false, false)` pentru 100 de produse și compară-l cu limita de gas a tranzacției discutată la laborator. Implementează paginarea folosind `getProducts(uint offset, uint limit)`.

### Exercițiul 7 — Optimizarea contractului `FidelityPoints`

Rulează `forge snapshot` înainte de fiecare modificare și `forge snapshot --diff` după modificare. Înregistrează rezultatele într-un tabel cu coloanele **Funcție**, **Gas înainte**, **Gas după** și **Tehnică**.

1. Schimbă `admin` în `immutable`, inspectează noua organizare a stocării și explică efectul asupra inspectării directe a sloturilor.
2. Citește `points[msg.sender]` o singură dată în `spendPoints` și `redeem`. Folosește o eroare personalizată și scăderea în bloc `unchecked` numai după o verificare care garantează că scăderea este sigură. Analizează separat dacă același raționament se aplică și pentru `totalPoints`.
3. Adaugă funcția `addPointsBatch(address[] calldata clients, uint[] calldata amounts)`. Compară o singură tranzacție în lot cu zece tranzacții individuale, apoi compară `calldata` cu `memory`.
4. Într-o copie a contractului, înlocuiește erorile personalizate cu mesaje text în `require` și compară dimensiunea bytecode-ului și consumul de gas la `revert`.
5. Activează optimizatorul în `foundry.toml` și compară consumul de gas la publicare și la răscumpărare pentru `optimizer_runs = 1` și `optimizer_runs = 1000000`.

### Exercițiul 8 — Publicarea pe Sepolia

Publică versiunile finale ale contractelor `Catalog` și `FidelityPoints` pe Sepolia și conectează-le. Adaugă un produs și acordă puncte la adresa unui coleg. Roagă colegul să folosească punctele din propriul cont.

În [Etherscan Sepolia](https://sepolia.etherscan.io/), deschide fila **Logs** a tranzacției de răscumpărare și identifică evenimentele și câmpurile `topics` emise de ambele contracte. Compară `gasUsed` cu valoarea obținută în Anvil, calculează costul tranzacției în ether folosind prețul efectiv al gas-ului și notează în raport adresele contractelor și hash-urile tranzacțiilor.

## Comenzi utile

| Scop | Comandă |
|---|---|
| Compilarea contractelor | `forge build` |
| Rularea testelor | `forge test` |
| Rularea testelor cu raport de gas | `forge test --gas-report` |
| Salvarea instantaneelor de consum de gas | `forge snapshot` |
| Compararea instantaneelor de consum de gas | `forge snapshot --diff` |
| Afișarea dimensiunii bytecode-ului contractelor | `forge build --sizes` |
| Inspectarea organizării stocării | `forge inspect Catalog storageLayout` |
| Estimarea consumului unei tranzacții | `cast estimate ...` |
| Citirea unui slot de stocare | `cast storage <address> <slot>` |
| Decodificarea datelor unei erori personalizate | `cast decode-error ...` |
| Citirea traseului de execuție al unei tranzacții | `cast run <transaction-hash>` |
| Căutarea evenimentelor | `cast logs ...` |

## Referințe

1. [Solidity — Function modifiers](https://docs.soliditylang.org/en/latest/contracts.html#function-modifiers)
2. [Solidity — Error handling](https://docs.soliditylang.org/en/latest/control-structures.html#error-handling-assert-require-revert-and-exceptions)
3. [Solidity — `try`/`catch`](https://docs.soliditylang.org/en/latest/control-structures.html#try-catch)
4. [Solidity — Events](https://docs.soliditylang.org/en/latest/contracts.html#events)
5. [Solidity ABI — Events](https://docs.soliditylang.org/en/latest/abi-spec.html#events)
6. [Solidity — Interfaces](https://docs.soliditylang.org/en/latest/contracts.html#interfaces)
7. [Solidity — External function calls](https://docs.soliditylang.org/en/latest/control-structures.html#external-function-calls)
8. [Solidity — Security considerations](https://docs.soliditylang.org/en/latest/security-considerations.html#use-the-checks-effects-interactions-pattern)
9. [Solidity — Storage layout](https://docs.soliditylang.org/en/latest/internals/layout_in_storage.html)
10. [Ethereum.org — Gas and fees](https://ethereum.org/en/developers/docs/gas/)
11. [EIP-2929 — Gas cost increases for state access opcodes](https://eips.ethereum.org/EIPS/eip-2929)
12. [EIP-3529 — Reduction in refunds](https://eips.ethereum.org/EIPS/eip-3529)
13. [EVM Codes — Opcode reference](https://www.evm.codes/)
14. [EIP-7825 — Transaction gas limit cap](https://eips.ethereum.org/EIPS/eip-7825)
15. [Solidity — `constant` and `immutable`](https://docs.soliditylang.org/en/latest/contracts.html#constant-and-immutable-state-variables)
16. [Solidity — Optimizer](https://docs.soliditylang.org/en/latest/internals/optimizer.html)
17. [Foundry — `forge inspect`](https://getfoundry.sh/forge/reference/forge-inspect)
18. [Foundry — Gas tracking and reports](https://getfoundry.sh/forge/gas-tracking)
19. [Foundry — Gas snapshots](https://getfoundry.sh/forge/gas-function-snapshots)
20. [Foundry — `expectEmit`](https://getfoundry.sh/reference/cheatcodes/expect-emit)
21. [Foundry — `cast logs`](https://getfoundry.sh/cast/reference/logs)
22. [Solidity — Type conversions](https://docs.soliditylang.org/en/latest/types.html#conversions-between-elementary-types)
23. [Etherscan — Sepolia testnet](https://sepolia.etherscan.io/)

Resurse suplimentare: [Solidity documentation](https://docs.soliditylang.org/en/latest/), [Remix IDE](https://remix.ethereum.org/), [bytes32 converter](https://web3-type-converter.onbrn.com/).
