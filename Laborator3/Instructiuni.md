# Laboratorul 3 — Smart Contracts în Solidity

## Platformă de puncte de fidelitate

Acest laborator prezintă dezvoltarea, testarea și publicarea unor smart contracts în Solidity folosind Foundry. Contractul `FidelityPoints.sol` gestionează punctele de fidelitate ale clienților, iar `Catalog.sol` gestionează produse, stocuri și promoții.

## 1. Noțiuni de bază Solidity

Un smart contract este un program care rulează pe blockchain. Acesta conține cod și date persistente, iar funcțiile sale sunt executate de EVM.

### Structura unui contract

Un contract poate conține:

- **State variables** — date persistente, precum `admin`, `pointValue` și `points`.
- **Constructor** — funcție executată o singură dată la deploy.
- **Functions** — operațiile contractului.
- **Modifiers** — verificări reutilizabile pentru acces.
- **Events** — înregistrări pe care aplicațiile externe le pot urmări.
- **Errors** — erori explicite pentru operații invalide.
- **Structs și enums** — tipuri de date definite de programator.

Variabile globale importante:

- `msg.sender` — adresa contului sau contractului care face apelul curent.
- `block.timestamp` — timestamp-ul blocului curent, în secunde de la Unix epoch.

### Tipuri de date

```solidity
uint points;
bool inStock;
address admin;
bytes32 code;
```

- `uint` — număr întreg fără semn.
- `bool` — `true` sau `false`.
- `address` — adresă Ethereum.
- `bytes32` — valoare de 32 de octeți, folosită în laborator pentru codurile produselor.
- `enum` — tip cu un set finit de valori.
- `struct` — grupează mai multe câmpuri într-un singur tip.

Exemplu de structură:

```solidity
struct Product {
    bytes32 code;
    string name;
    uint price;
    bool inStock;
}
```

### Mapping

Un `mapping` asociază o cheie cu o valoare:

```solidity
mapping(address => uint) public points;
```

Acesta poate fi privit ca un dicționar care asociază fiecărei adrese un număr de puncte. Un `mapping` nu are `length` și nu permite enumerarea cheilor. Dacă este necesară parcurgerea tuturor cheilor, acestea trebuie păstrate separat, de exemplu într-un array.

### `storage`, `memory` și `calldata`

- `storage` — date persistente ale contractului.
- `memory` — date temporare, existente doar pe durata apelului.
- `calldata` — datele de intrare ale apelului, doar pentru citire.

Exemplu:

```solidity
Product storage p = products[index];
p.stock += amount;
```

`p` este o referință la produsul persistent, deci modificarea lui `p.stock` modifică starea contractului. În schimb, un obiect `Product memory` este o copie temporară.

### Vizibilitate și mutabilitate

| Specificator | Semnificație |
|---|---|
| `public` | Accesibil din exterior și interior; pentru variabile generează un getter |
| `external` | Parte a interfeței externe a contractului |
| `internal` | Accesibil în contract și în contractele derivate |
| `private` | Accesibil doar în contractul în care este declarat |
| `view` | Poate citi starea, dar nu o poate modifica |
| `pure` | Nu citește și nu modifică starea contractului |
| `payable` | Permite primirea de Ether |

**Important:** `private` și `internal` nu fac datele secrete. Starea de pe blockchain poate fi inspectată direct.

### Apeluri eșuate

Dacă o condiție nu este respectată, o funcție poate face `revert`. Schimbările efectuate în apel sunt anulate, dar o tranzacție eșuată inclusă într-un bloc poate consuma în continuare gas.

În Solidity 0.8+, operațiile aritmetice obișnuite sunt verificate. De exemplu, scăderea unui număr de puncte mai mare decât soldul disponibil produce o eroare.

## 2. Crearea proiectului Foundry

Creează proiectul:

```bash
forge init fidelity-points
cd fidelity-points
```

Copiază `FidelityPoints.sol` și `Catalog.sol` în directorul `src`, apoi compilează:

```bash
forge build
```

Structura principală a proiectului:

```text
fidelity-points/
├── foundry.toml
├── src/
│   ├── FidelityPoints.sol
│   └── Catalog.sol
├── test/
├── script/
├── lib/
└── out/
```

- `src/` — contractele Solidity.
- `test/` — testele Solidity.
- `script/` — scripturi de deploy.
- `lib/` — dependențe, inclusiv `forge-std`.
- `out/` — rezultate generate la compilare.

Poți inspecta ABI-ul contractului:

```bash
forge inspect FidelityPoints abi
```

ABI-ul descrie interfața contractului, iar bytecode-ul este codul executabil trimis la deploy.

## 3. Deploy și interacțiune pe Anvil

Anvil pornește o rețea Ethereum locală pentru dezvoltare și testare.

În primul terminal:

```bash
anvil
```

În al doilea terminal, din directorul proiectului, configurează RPC-ul local și conturile de test. Exemplul următor este pentru Bash/WSL:

```bash
export ETH_RPC_URL=http://127.0.0.1:8545

ANVIL_KEY=CHEIA_PRIVATA_ANVIL_ACCOUNT_0
CLIENT=ADRESA_ANVIL_ACCOUNT_1
CLIENT_KEY=CHEIA_PRIVATA_ANVIL_ACCOUNT_1
```

Folosește valorile afișate de Anvil. Cheile implicite Anvil sunt publice și trebuie folosite **doar pe rețeaua locală**, niciodată pentru fonduri reale.

### 3.1 Deploy

Publică `FidelityPoints` cu valoarea inițială a unui punct setată la `10`:

```bash
forge create src/FidelityPoints.sol:FidelityPoints \
  --private-key $ANVIL_KEY \
  --broadcast \
  --constructor-args 10
```

Copiază adresa afișată după `Deployed to`:

```bash
FP=ADRESA_CONTRACTULUI
cast code $FP
```

`cast code` afișează bytecode-ul contractului de la adresa respectivă.

### 3.2 Citirea stării cu `cast call`

```bash
cast call $FP 'pointValue()(uint256)'
cast call $FP 'admin()(address)'
cast call $FP 'points(address)(uint256)' $CLIENT
```

Aceste comenzi citesc valoarea punctului, administratorul și soldul clientului. Pentru variabilele `public`, Solidity generează automat funcții getter.

`cast call` execută apelul fără a trimite o tranzacție on-chain și nu modifică starea persistentă.

### 3.3 Modificarea stării cu `cast send`

Acordă clientului 100 de puncte:

```bash
cast send $FP 'addPoints(address,uint256)' \
  $CLIENT 100 \
  --private-key $ANVIL_KEY
```

Verifică rezultatul:

```bash
cast call $FP 'points(address)(uint256)' $CLIENT
cast call $FP 'getTotalValue(address)(uint256)' $CLIENT
```

Inspectează receipt-ul tranzacției cu:

```bash
cast receipt HASHUL_TRANZACTIEI
```

Compară valoarea `gasUsed` cu cei 21.000 gas ai unui transfer simplu de Ether.

### 3.4 Identificarea unei probleme de acces

În versiunea inițială a contractului, încearcă să schimbi valoarea punctului din contul clientului:

```bash
cast send $FP 'setPointValue(uint256)' \
  1000 \
  --private-key $CLIENT_KEY
```

Tranzacția poate reuși deoarece funcția inițială nu verifică dacă apelantul este administrator. Această problemă este rezolvată în Exercițiul 1 cu un modifier `onlyAdmin`.

### 3.5 Citirea directă a storage-ului

În versiunea inițială, ordinea variabilelor este `admin`, `pointValue`, `points`. Sloturile de bază sunt:

| Slot | Variabilă |
|---:|---|
| `0` | `admin` |
| `1` | `pointValue` |
| `2` | `points` — slotul de bază al mapping-ului |

Citește primele două sloturi:

```bash
cast storage $FP 0
cast storage $FP 1
cast --to-dec $(cast storage $FP 1)
```

Valorile din mapping sunt stocate la poziții calculate prin hashing, nu direct în slotul de bază:

```bash
SLOT=$(cast index address $CLIENT 2)
cast --to-dec $(cast storage $FP $SLOT)
```

Acest lucru demonstrează că variabilele `private` sau `internal` nu sunt secrete pe blockchain.

## 4. Testare cu Forge

Testele sunt scrise în Solidity și folosesc de obicei `forge-std`:

- `setUp()` — pregătește starea inițială înaintea fiecărui test.
- `assertEq(a, b)` — verifică dacă două valori sunt egale.
- `vm.prank(address)` — schimbă `msg.sender` pentru următorul apel relevant.
- `vm.expectRevert(...)` — verifică dacă următorul apel eșuează cu eroarea așteptată.

Exemplu de test pentru acordarea punctelor:

```solidity
function test_AddPoints() public {
    fp.addPoints(client, 100);

    assertEq(fp.points(client), 100);
    assertEq(fp.getTotalValue(client), 1000);
}
```

Rulează testele:

```bash
forge test
forge test -vvvv
forge test --match-test test_AddPoints
forge test --gas-report
```

`-vvvv` oferă un trace detaliat pentru depanare, iar `--gas-report` afișează consumul de gas pentru funcțiile testate.

## 5. Deploy pe Sepolia

Sepolia este o rețea de test Ethereum. Pentru acest pas ai nevoie de un endpoint RPC Infura, un cont Foundry configurat și Ether de test.

Creează `.env` în rădăcina proiectului:

```bash
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/API_KEY
```

Înlocuiește `API_KEY` cu cheia ta Infura. Verifică să nu fie publicat fișierul `.env` în Git:

```bash
grep -x .env .gitignore
```

Adaugă la finalul lui `foundry.toml`:

```toml
[rpc_endpoints]
sepolia = "${SEPOLIA_RPC_URL}"
```

Verifică rețeaua și soldul contului:

```bash
unset ETH_RPC_URL
cast chain-id --rpc-url sepolia
cast balance $(cast wallet address --account sepolia-dev) \
  --ether --rpc-url sepolia
```

Chain ID-ul Sepolia trebuie să fie `11155111`.

Publică contractul:

```bash
forge create src/FidelityPoints.sol:FidelityPoints \
  --rpc-url sepolia \
  --account sepolia-dev \
  --broadcast \
  --constructor-args 10
```

Foundry semnează tranzacția folosind keystore-ul `sepolia-dev` și îți cere parola. Nu pune cheia privată în `.env` sau în repository.

După deploy, salvează adresa contractului și testează o tranzacție:

```bash
FP=ADRESA_CONTRACTULUI

cast send $FP 'addPoints(address,uint256)' \
  $(cast wallet address --account sepolia-dev) 50 \
  --rpc-url sepolia \
  --account sepolia-dev

cast call $FP 'points(address)(uint256)' \
  $(cast wallet address --account sepolia-dev) \
  --rpc-url sepolia
```

Verifică tranzacțiile la [Sepolia Etherscan](https://sepolia.etherscan.io/). Opțional, contractul poate fi verificat pe Etherscan pentru a publica sursa și a permite decodarea tranzacțiilor.

## 6. Exerciții

### Exercițiul 1 — Extinderea `FidelityPoints`

1. Implementează `spendPoints(uint _points)`, astfel încât un client să poată cheltui doar punctele proprii, identificate prin `msg.sender`.
2. Adaugă `totalPoints`, care reține suma punctelor deținute de toți clienții, și o funcție `internal` pentru actualizarea acestei valori când punctele sunt adăugate sau cheltuite. Adaugă o funcție pentru citirea sumei.
3. Restricționează `addPoints` și `setPointValue` la administrator, folosind `onlyAdmin` și o eroare personalizată, de exemplu `NotAdmin(address caller)`.
4. Publică versiunea modificată pe Anvil și citește `totalPoints` direct din storage. Determină slotul variabilei și explică dacă slotul de bază al mapping-ului `points` s-a schimbat.

### Exercițiul 2 — Testare

Extinde `testFidelityPoints.t.sol` pentru a verifica:

1. Cheltuirea punctelor reduce soldul clientului și `totalPoints`.
2. Cheltuirea unui număr mai mare de puncte decât soldul disponibil produce `revert`.
3. Apelarea `addPoints` de către un cont diferit de administrator produce `NotAdmin`.

Rulează:

```bash
forge test --gas-report
```

Notează consumul de gas al funcțiilor `addPoints` și `spendPoints`.

### Exercițiul 3 — Deploy pe Sepolia

Publică versiunea finală a contractului pe Sepolia. Acordă puncte unui coleg și verifică pe Etherscan că tranzacția a fost trimisă de contul tău. Colegul trebuie să își poată citi soldul cu `cast call`.

În raport, notează adresa contractului și hash-urile tranzacțiilor.

### Exercițiul 4 — Stocul produselor

În `Catalog.sol`, adaugă câmpul `uint stock` în `Product` și implementează:

- `increaseStock(bytes32 code, uint amount)`
- `decreaseStock(bytes32 code, uint amount)`

Câmpul `inStock` trebuie să rămână consistent cu `stock`. Ambele funcții trebuie să caute produsul după cod și să dea `revert` dacă acesta nu există.

Pentru coduri de produs, poți folosi:

```bash
cast format-bytes32-string P001
```

### Exercițiul 5 — Promoții individuale

Extinde `Catalog.sol`, astfel încât fiecare produs să poată avea propria promoție. Folosește un `mapping` de la codul produsului la `Promo` și implementează:

```solidity
function startProductPromo(bytes32 code, uint ndays, uint percent) external;

function startPromoBatch(
    bytes32[] calldata codes,
    uint ndays,
    uint percent
) external;
```

Adaugă și o funcție `view` care indică dacă un produs are o promoție activă.

### Exercițiul 6 — Filtrarea produselor

Implementează:

```solidity
function getProducts(bool inStock, bool inPromo)
    public
    view
    returns (Product[] memory);
```

Funcția trebuie să returneze produsele care corespund filtrelor. Apeleaz-o cu `cast call` și explică de ce apelul de citire nu necesită o taxă de tranzacție on-chain și de ce parcurgerea tuturor produselor poate fi problematică într-o funcție care modifică starea.

### Exercițiul 7 — Funcție `pure`

Adaugă o funcție `pure`, de exemplu una care calculează prețul unui produs după aplicarea unei reduceri procentuale. Testeaz-o cu Forge.

## 7. Concepte de reținut

- `msg.sender` identifică apelantul curent.
- `public` generează getter-e pentru variabilele de stare.
- `mapping` asociază chei cu valori, dar nu permite enumerarea cheilor.
- `storage` reprezintă date persistente, `memory` date temporare, iar `calldata` date de intrare doar pentru citire.
- `cast call` citește fără tranzacție on-chain; `cast send` trimite o tranzacție.
- `modifier` permite reutilizarea verificărilor de acces.
- `revert` anulează modificările apelului care eșuează, dar tranzacția poate consuma gas.
- Datele `private` și `internal` nu sunt confidențiale pe blockchain.
- Testele trebuie să verifice atât cazurile de succes, cât și cazurile invalide.

## Resurse

- [Documentația Solidity](https://docs.soliditylang.org/en/latest/)
- [Foundry Book](https://book.getfoundry.sh/)
- [Remix IDE](https://remix.ethereum.org/)
- [Sepolia Etherscan](https://sepolia.etherscan.io/)
- [MetaMask](https://metamask.io/)
- [Infura](https://www.infura.io/)

---

**Notă:** Comenzile cu `cast`, căile fișierelor și argumentele ABI trebuie adaptate dacă structura proiectului sau semnăturile contractelor tale diferă. Folosește cheile implicite Anvil exclusiv pe rețeaua locală și nu publica secrete în Git.
